# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Presets do
  describe E11y::Presets::AuditEvent do
    let(:audit_event_class) do
      Class.new(E11y::Event::Base) do
        include E11y::Presets::AuditEvent

        def self.name
          "TestAuditEvent"
        end

        severity :info # User explicitly sets severity (audit events can be any severity)

        schema do
          required(:user_id).filled(:integer)
        end
      end
    end

    it "does NOT set severity (user must set explicitly)" do
      # Without explicit severity, should use convention-based default
      event_without_severity = Class.new(E11y::Event::Base) do
        include E11y::Presets::AuditEvent

        def self.name
          "AuditEventWithoutSeverity"
        end
      end

      expect(event_without_severity.severity).to eq(:info) # Convention-based default
    end

    it "respects user-defined severity" do
      expect(audit_event_class.severity).to eq(:info) # User explicitly set to :info
    end

    it "has 100% sample rate (compliance requirement)" do
      expect(audit_event_class.resolve_sample_rate).to eq(1.0)
    end

    it "has unlimited rate limit (compliance requirement)" do
      expect(audit_event_class.resolve_rate_limit).to be_nil
    end

    it "adapters are based on user-defined severity" do
      # audit_event_class has severity :info, so adapters should be [:logs]
      expect(audit_event_class.adapters).to eq([:logs])
    end

    it "can track events with user-defined severity" do
      result = audit_event_class.track(user_id: 123)

      expect(result[:event_name]).to eq("TestAuditEvent")
      expect(result[:severity]).to eq(:info) # User-defined severity
    end

    context "with different severities" do
      it "works with :warn severity" do
        warn_audit = Class.new(E11y::Event::Base) do
          include E11y::Presets::AuditEvent

          severity :warn

          def self.name
            "WarnAuditEvent"
          end
        end

        expect(warn_audit.severity).to eq(:warn)
        expect(warn_audit.resolve_sample_rate).to eq(1.0) # Still 100% for audit
        expect(warn_audit.resolve_rate_limit).to be_nil # Still unlimited for audit
      end

      it "works with :fatal severity" do
        fatal_audit = Class.new(E11y::Event::Base) do
          include E11y::Presets::AuditEvent

          severity :fatal

          def self.name
            "FatalAuditEvent"
          end
        end

        expect(fatal_audit.severity).to eq(:fatal)
        expect(fatal_audit.resolve_sample_rate).to eq(1.0) # Still 100% for audit
        expect(fatal_audit.resolve_rate_limit).to be_nil # Still unlimited for audit
      end
    end
  end

  describe E11y::Presets::HighValueEvent do
    let(:high_value_event_class) do
      Class.new(E11y::Event::Base) do
        include E11y::Presets::HighValueEvent

        def self.name
          "TestPaymentEvent"
        end

        schema do
          required(:amount).filled(:float)
        end
      end
    end

    it "sets severity to :success" do
      expect(high_value_event_class.severity).to eq(:success)
    end

    it "explicitly sets adapter names to [:logs, :errors_tracker]" do
      # Adapter NAMES (not implementations)
      expect(high_value_event_class.instance_variable_get(:@adapters)).to eq(%i[logs errors_tracker])
    end

    it "returns adapter names from getter" do
      # Getter returns NAMES
      expect(high_value_event_class.adapters).to eq(%i[logs errors_tracker])
    end

    it "overrides sample rate to 100%" do
      expect(high_value_event_class.resolve_sample_rate).to eq(1.0)
    end

    it "overrides rate limit to unlimited" do
      expect(high_value_event_class.resolve_rate_limit).to be_nil
    end

    it "can track events" do
      result = high_value_event_class.track(amount: 99.99)

      expect(result[:event_name]).to eq("TestPaymentEvent")
      expect(result[:severity]).to eq(:success)
      expect(result[:adapters]).to eq(%i[logs errors_tracker]) # Adapter names
    end
  end

  describe E11y::Presets::DebugEvent do
    let(:debug_event_class) do
      Class.new(E11y::Event::Base) do
        include E11y::Presets::DebugEvent

        def self.name
          "TestDebugEvent"
        end

        schema do
          required(:debug_info).filled(:string)
        end
      end
    end

    it "sets severity to :debug" do
      expect(debug_event_class.severity).to eq(:debug)
    end

    it "explicitly sets adapter name to [:logs]" do
      # Adapter NAME (not implementation)
      expect(debug_event_class.instance_variable_get(:@adapters)).to eq([:logs])
    end

    it "returns adapter name from getter" do
      # Getter returns NAME
      expect(debug_event_class.adapters).to eq([:logs])
    end

    it "has 1% sample rate (from :debug severity)" do
      expect(debug_event_class.resolve_sample_rate).to eq(0.01)
    end

    it "has standard rate limit (from :debug severity)" do
      expect(debug_event_class.resolve_rate_limit).to eq(1000)
    end

    it "can track events" do
      result = debug_event_class.track(debug_info: "cache hit")

      expect(result[:event_name]).to eq("TestDebugEvent")
      expect(result[:severity]).to eq(:debug)
      expect(result[:adapters]).to eq([:logs]) # Adapter name
    end
  end
end
