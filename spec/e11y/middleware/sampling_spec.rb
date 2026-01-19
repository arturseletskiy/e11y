# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers

require "spec_helper"

RSpec.describe E11y::Middleware::Sampling do
  let(:app) { ->(event_data) { event_data } } # Simple passthrough app
  let(:middleware) do
    instance = described_class.new(config)
    instance.instance_variable_set(:@app, app)
    instance
  end
  let(:config) { {} }
  let(:event_class) do
    Class.new(E11y::Event::Base) do
      def self.name
        "TestEvent"
      end

      def self.event_name
        "test.event"
      end
    end
  end
  let(:event_data) { { event_name: "test.event", payload: { test: "data" }, event_class: event_class } }

  describe "#initialize" do
    it "sets default sample rate to 1.0" do
      middleware = described_class.new
      expect(middleware.instance_variable_get(:@default_sample_rate)).to eq(1.0)
    end

    it "allows custom default sample rate" do
      middleware = described_class.new(default_sample_rate: 0.5)
      expect(middleware.instance_variable_get(:@default_sample_rate)).to eq(0.5)
    end

    it "enables trace-aware sampling by default" do
      middleware = described_class.new
      expect(middleware.instance_variable_get(:@trace_aware)).to be true
    end

    it "allows disabling trace-aware sampling" do
      middleware = described_class.new(trace_aware: false)
      expect(middleware.instance_variable_get(:@trace_aware)).to be false
    end
  end

  describe "#call" do
    context "with default 100% sampling via severity override" do
      let(:config) { { severity_rates: { success: 1.0 } } }
      let(:success_event) do
        Class.new(E11y::Event::Base) do
          def self.name
            "SuccessEvent"
          end

          def self.severity
            :success
          end
        end
      end
      let(:event_data) { super().merge(event_class: success_event) }

      it "always samples events" do
        result = middleware.call(event_data)
        expect(result).not_to be_nil
        expect(result[:sampled]).to be true
      end

      it "includes sample_rate in event data" do
        result = middleware.call(event_data)
        expect(result[:sample_rate]).to eq(1.0)
      end
    end

    context "with 0% sampling via severity override" do
      let(:config) { { severity_rates: { success: 0.0 } } }
      let(:success_event) do
        Class.new(E11y::Event::Base) do
          def self.name
            "SuccessEvent"
          end

          def self.severity
            :success
          end
        end
      end
      let(:event_data) { super().merge(event_class: success_event) }

      it "never samples events" do
        10.times do
          result = middleware.call(event_data.dup)
          expect(result).to be_nil
        end
      end
    end

    context "with 50% sampling via severity override" do
      let(:config) { { severity_rates: { success: 0.5 } } }
      let(:success_event) do
        Class.new(E11y::Event::Base) do
          def self.name
            "SuccessEvent"
          end

          def self.severity
            :success
          end
        end
      end
      let(:event_data) { super().merge(event_class: success_event) }

      it "samples approximately 50% of events" do
        sampled_count = 0
        total_count = 1000

        total_count.times do
          result = middleware.call(event_data.dup)
          sampled_count += 1 if result
        end

        # Allow 10% variance (450-550 sampled out of 1000)
        expect(sampled_count).to be_within(50).of(500)
      end
    end

    context "with audit events" do
      let(:audit_event_class) do
        Class.new(E11y::Event::Base) do
          def self.name
            "AuditEvent"
          end

          def self.event_name
            "audit.event"
          end

          def self.audit_event?
            true
          end
        end
      end

      let(:config) { { default_sample_rate: 0.0 } }

      it "always samples audit events (never drops)" do
        10.times do
          audit_data = event_data.merge(event_class: audit_event_class)
          result = middleware.call(audit_data)
          expect(result).not_to be_nil
          expect(result[:sampled]).to be true
        end
      end
    end
  end

  describe "#determine_sample_rate" do
    context "with event-level sample rate (via severity)" do
      let(:debug_event) do
        Class.new(E11y::Event::Base) do
          def self.name
            "DebugEvent"
          end

          def self.event_name
            "debug.event"
          end

          def self.severity
            :debug
          end
        end
      end

      it "uses severity-based sample rate from Event::Base" do
        rate = middleware.send(:determine_sample_rate, debug_event)
        # debug severity → 0.01 (from SEVERITY_SAMPLE_RATES in Event::Base)
        expect(rate).to eq(0.01)
      end
    end

    context "with severity-based override" do
      let(:config) { { severity_rates: { error: 1.0, debug: 0.01 }, default_sample_rate: 0.1 } }

      let(:error_event) do
        Class.new(E11y::Event::Base) do
          def self.name
            "ErrorEvent"
          end

          def self.severity
            :error
          end
        end
      end

      let(:debug_event) do
        Class.new(E11y::Event::Base) do
          def self.name
            "DebugEvent"
          end

          def self.severity
            :debug
          end
        end
      end

      it "uses severity-based rate for errors" do
        rate = middleware.send(:determine_sample_rate, error_event)
        expect(rate).to eq(1.0)
      end

      it "uses severity-based rate for debug" do
        rate = middleware.send(:determine_sample_rate, debug_event)
        expect(rate).to eq(0.01)
      end

      it "uses default rate for unknown severity" do
        rate = middleware.send(:determine_sample_rate, event_class)
        expect(rate).to eq(0.1)
      end
    end

    context "with default sample rate" do
      let(:config) { { default_sample_rate: 0.3 } }
      let(:event_without_severity) do
        Class.new(E11y::Event::Base) do
          def self.name
            "EventWithoutSeverity"
          end

          def self.event_name
            "event.without.severity"
          end

          # No severity defined, so resolve_sample_rate returns default
        end
      end

      it "uses Event::Base default when event has no explicit config" do
        # Event::Base.resolve_sample_rate returns 0.1 by default (from SEVERITY_SAMPLE_RATES)
        rate = middleware.send(:determine_sample_rate, event_without_severity)
        expect(rate).to eq(0.1)
      end
    end
  end

  describe "Trace-Aware Sampling (C05)" do
    let(:config) { { trace_aware: true, severity_rates: { success: 0.5 } } }
    let(:trace_id) { "trace-123" }
    let(:success_event) do
      Class.new(E11y::Event::Base) do
        def self.name
          "SuccessEvent"
        end

        def self.severity
          :success
        end
      end
    end
    let(:event_data_with_trace) do
      { event_name: "test.event", payload: { test: "data" }, event_class: success_event, trace_id: trace_id }
    end

    context "with same trace_id" do
      it "makes consistent sampling decision for all events in trace" do
        # First event determines sampling decision
        first_result = middleware.call(event_data_with_trace.dup)
        first_sampled = !first_result.nil?

        # All subsequent events in same trace should have same decision
        10.times do
          result = middleware.call(event_data_with_trace.dup)
          sampled = !result.nil?
          expect(sampled).to eq(first_sampled)
        end
      end
    end

    context "with different trace_ids" do
      it "makes independent sampling decisions for different traces" do
        sampled_count = 0
        total_count = 100

        total_count.times do |i|
          trace_data = event_data_with_trace.merge(trace_id: "trace-#{i}")
          result = middleware.call(trace_data)
          sampled_count += 1 if result
        end

        # Should be approximately 50% sampled (allow 20% variance)
        expect(sampled_count).to be_within(20).of(50)
      end
    end

    context "when trace-aware sampling is disabled" do
      let(:config) { { trace_aware: false, default_sample_rate: 0.5 } }

      it "makes independent decisions for each event" do
        # Track decisions for same trace
        # Use more iterations to reduce flakiness
        decisions = []
        50.times do
          result = middleware.call(event_data_with_trace.dup)
          decisions << !result.nil?
        end

        # Should have mix of true/false (not all same)
        # With 50 iterations and 50% sampling, probability of all same is ~0.00000009%
        expect(decisions.uniq.size).to be > 1
      end
    end
  end

  describe "#cleanup_trace_decisions" do
    let(:config) { { trace_aware: true } }

    it "removes approximately 50% of cached decisions" do
      # Populate cache with 1000 decisions
      decisions = middleware.instance_variable_get(:@trace_decisions)
      1000.times { |i| decisions["trace-#{i}"] = true }

      expect(decisions.size).to eq(1000)

      # Trigger cleanup
      middleware.send(:cleanup_trace_decisions)

      # Should have ~500 decisions left (allow variance)
      expect(decisions.size).to be_within(100).of(500)
    end

    it "is triggered when cache exceeds 1000 entries" do
      # Simulate 1001 trace sampling calls
      1001.times do |i|
        trace_data = event_data.merge(trace_id: "trace-#{i}")
        middleware.call(trace_data)
      end

      decisions = middleware.instance_variable_get(:@trace_decisions)
      # Cache should be cleaned up, so size < 1000
      expect(decisions.size).to be < 1000
    end
  end

  describe "#capabilities" do
    it "reports correct capabilities" do
      capabilities = middleware.capabilities
      expect(capabilities[:filters_events]).to be true
      expect(capabilities[:trace_aware]).to be true
      expect(capabilities[:severity_aware]).to be true
    end

    it "reports trace_aware based on config" do
      middleware_disabled = described_class.new(trace_aware: false)
      capabilities = middleware_disabled.capabilities
      expect(capabilities[:trace_aware]).to be false
    end
  end

  describe "Integration with Event::Base" do
    let(:high_frequency_event) do
      Class.new(E11y::Event::Base) do
        def self.name
          "HighFrequencyEvent"
        end

        def self.event_name
          "high.frequency"
        end

        def self.severity
          :debug # debug → 0.01 (1% sampling)
        end
      end
    end

    let(:critical_event) do
      Class.new(E11y::Event::Base) do
        def self.name
          "CriticalEvent"
        end

        def self.event_name
          "critical.event"
        end

        def self.severity
          :error # error → 1.0 (100% sampling)
        end
      end
    end

    it "respects severity-based sample rates from Event::Base" do
      # High frequency (debug): 1% sampling
      sampled_count = 0
      100.times do
        data = event_data.merge(event_class: high_frequency_event)
        result = middleware.call(data)
        sampled_count += 1 if result
      end
      expect(sampled_count).to be < 10 # Should be ~1 event

      # Critical (error): 100% sampling
      sampled_count = 0
      10.times do
        data = event_data.merge(event_class: critical_event)
        result = middleware.call(data)
        sampled_count += 1 if result
      end
      expect(sampled_count).to eq(10) # All events sampled
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
