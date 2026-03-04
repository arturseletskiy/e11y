# frozen_string_literal: true

require "spec_helper"
require "e11y/middleware/routing"

# Routing integration tests require multiple adapters, severity-based routing,
# and complex configuration scenarios with extensive mocking.
RSpec.describe E11y::Middleware::Routing do
  let(:final_app) { ->(event_data) { event_data } }
  let(:middleware) { described_class.new(final_app) }

  # Mock adapters
  let(:loki_adapter) { instance_double(E11y::Adapters::Loki, write: true) }
  let(:s3_glacier_adapter) { instance_double(E11y::Adapters::File, write: true) }
  let(:audit_adapter) { instance_double(E11y::Adapters::AuditEncrypted, write: true) }
  let(:sentry_adapter) { instance_double(E11y::Adapters::Sentry, write: true) }
  let(:stdout_adapter) { instance_double(E11y::Adapters::Stdout, write: true) }

  before do
    # Reset configuration
    E11y.configuration.adapters.clear
    E11y.configuration.routing_rules = []
    E11y.configuration.fallback_adapters = [:stdout]

    # Register mock adapters
    E11y.configuration.adapters[:loki] = loki_adapter
    E11y.configuration.adapters[:s3_glacier] = s3_glacier_adapter
    E11y.configuration.adapters[:audit_encrypted] = audit_adapter
    E11y.configuration.adapters[:sentry] = sentry_adapter
    E11y.configuration.adapters[:stdout] = stdout_adapter
  end

  describe ".middleware_zone" do
    it "declares adapters zone (FINAL middleware)" do
      expect(described_class.middleware_zone).to eq(:adapters)
    end
  end

  describe "#call" do
    context "with explicit adapters (bypass routing)" do
      it "uses explicit adapters, ignoring routing rules" do
        E11y.configuration.routing_rules = [
          ->(_event) { :s3_glacier } # This should be ignored
        ]

        event_data = {
          event_name: "payment.completed",
          adapters: %i[loki sentry], # ← Explicit
          retention_until: (Time.now + 365.days).iso8601
        }

        middleware.call(event_data)

        # Should use explicit adapters
        expect(loki_adapter).to have_received(:write).with(event_data)
        expect(sentry_adapter).to have_received(:write).with(event_data)

        # Should NOT use routing rule adapter
        expect(s3_glacier_adapter).not_to have_received(:write)
      end

      it "marks routing as :explicit" do
        event_data = {
          event_name: "test.event",
          adapters: [:loki],
          retention_until: (Time.now + 30.days).iso8601
        }

        result = middleware.call(event_data)

        expect(result[:routing][:routing_type]).to eq(:explicit)
        expect(result[:routing][:adapters]).to eq([:loki])
      end
    end

    context "with routing rules" do
      it "applies rules when no explicit adapters" do
        E11y.configuration.routing_rules = [
          lambda { |event|
            days = (Time.parse(event[:retention_until]) - Time.now) / 86_400
            days > 90 ? :s3_glacier : :loki
          }
        ]

        # Short retention → loki
        event_data = {
          event_name: "order.placed",
          retention_until: (Time.now + 30.days).iso8601
        }

        middleware.call(event_data)

        expect(loki_adapter).to have_received(:write)
        expect(s3_glacier_adapter).not_to have_received(:write)
      end

      it "routes to cold storage for long retention" do
        E11y.configuration.routing_rules = [
          lambda { |event|
            days = (Time.parse(event[:retention_until]) - Time.now) / 86_400
            days > 90 ? :s3_glacier : :loki
          }
        ]

        # Long retention → s3_glacier
        event_data = {
          event_name: "audit.event",
          retention_until: (Time.now + 365.days).iso8601
        }

        middleware.call(event_data)

        expect(s3_glacier_adapter).to have_received(:write)
        expect(loki_adapter).not_to have_received(:write)
      end

      it "marks routing as :rules" do
        E11y.configuration.routing_rules = [
          ->(_event) { :loki }
        ]

        event_data = {
          event_name: "test.event",
          retention_until: (Time.now + 30.days).iso8601
        }

        result = middleware.call(event_data)

        expect(result[:routing][:routing_type]).to eq(:rules)
        expect(result[:routing][:adapters]).to eq([:loki])
      end
    end

    context "with audit events" do
      it "routes audit events to audit_encrypted" do
        E11y.configuration.routing_rules = [
          ->(event) { :audit_encrypted if event[:audit_event] }
        ]

        event_data = {
          event_name: "user.deleted",
          audit_event: true,
          retention_until: (Time.now + 7.years).iso8601
        }

        middleware.call(event_data)

        expect(audit_adapter).to have_received(:write)
      end

      it "collects all matching rules (audit + storage)" do
        E11y.configuration.routing_rules = [
          ->(event) { :audit_encrypted if event[:audit_event] }, # First
          ->(_event) { :loki } # Second (also applied)
        ]

        event_data = {
          event_name: "user.deleted",
          audit_event: true,
          retention_until: (Time.now + 7.years).iso8601
        }

        middleware.call(event_data)

        # Both adapters should be used (collect all matches)
        expect(audit_adapter).to have_received(:write)
        expect(loki_adapter).to have_received(:write)
      end
    end

    context "with multiple routing rules (collect all matches)" do
      it "routes to multiple adapters when rules return multiple results" do
        E11y.configuration.routing_rules = [
          ->(event) { :sentry if event[:severity] == :error },
          ->(_event) { :loki } # Always add loki
        ]

        event_data = {
          event_name: "payment.failed",
          severity: :error,
          retention_until: (Time.now + 30.days).iso8601
        }

        middleware.call(event_data)

        # Both adapters should be used
        expect(sentry_adapter).to have_received(:write)
        expect(loki_adapter).to have_received(:write)
      end

      it "de-duplicates adapters when multiple rules return same adapter" do
        E11y.configuration.routing_rules = [
          ->(event) { :loki if event[:severity] == :error },
          ->(_event) { :loki } # Returns same adapter
        ]

        event_data = {
          event_name: "payment.failed",
          severity: :error,
          retention_until: (Time.now + 30.days).iso8601
        }

        middleware.call(event_data)

        # Should write once, not twice
        expect(loki_adapter).to have_received(:write).once
      end

      it "handles array return values from rules" do
        E11y.configuration.routing_rules = [
          ->(event) { %i[loki sentry] if event[:severity] == :error }
        ]

        event_data = {
          event_name: "payment.failed",
          severity: :error,
          retention_until: (Time.now + 30.days).iso8601
        }

        middleware.call(event_data)

        expect(loki_adapter).to have_received(:write)
        expect(sentry_adapter).to have_received(:write)
      end
    end

    context "with fallback adapters" do
      it "uses fallback when no rule matches" do
        E11y.configuration.routing_rules = [
          ->(_event) {} # Always returns nil
        ]
        E11y.configuration.fallback_adapters = [:stdout]

        event_data = {
          event_name: "unknown.event",
          retention_until: (Time.now + 30.days).iso8601
        }

        middleware.call(event_data)

        expect(stdout_adapter).to have_received(:write)
      end

      it "uses fallback when routing_rules is empty" do
        E11y.configuration.routing_rules = []
        E11y.configuration.fallback_adapters = [:stdout]

        event_data = {
          event_name: "test.event",
          retention_until: (Time.now + 30.days).iso8601
        }

        middleware.call(event_data)

        expect(stdout_adapter).to have_received(:write)
      end
    end

    context "with rule evaluation errors" do
      it "continues to next rule if one raises error" do
        E11y.configuration.routing_rules = [
          ->(_event) { raise "Rule error" }, # Raises error
          ->(_event) { :loki } # Should still be evaluated
        ]

        event_data = {
          event_name: "test.event",
          retention_until: (Time.now + 30.days).iso8601
        }

        expect do
          middleware.call(event_data)
        end.not_to raise_error

        expect(loki_adapter).to have_received(:write)
      end
    end

    context "with adapter write errors" do
      it "continues to other adapters if one fails" do
        allow(loki_adapter).to receive(:write).and_raise("Loki error")

        E11y.configuration.routing_rules = [
          ->(_event) { %i[loki sentry] }
        ]

        event_data = {
          event_name: "test.event",
          retention_until: (Time.now + 30.days).iso8601
        }

        expect do
          middleware.call(event_data)
        end.not_to raise_error

        # Loki failed but Sentry should still be called
        expect(sentry_adapter).to have_received(:write)
      end

      it "increments error metric on adapter failure" do
        allow(loki_adapter).to receive(:write).and_raise("Loki error")
        allow(middleware).to receive(:increment_metric)

        E11y.configuration.routing_rules = [
          ->(_event) { :loki }
        ]

        event_data = {
          event_name: "test.event",
          retention_until: (Time.now + 30.days).iso8601
        }

        middleware.call(event_data)

        expect(middleware).to have_received(:increment_metric)
          .with("e11y.middleware.routing.write_error", adapter: :loki)
      end
    end

    context "with adapter not found" do
      it "skips missing adapters gracefully" do
        E11y.configuration.routing_rules = [
          ->(_event) { :nonexistent_adapter }
        ]

        event_data = {
          event_name: "test.event",
          retention_until: (Time.now + 30.days).iso8601
        }

        expect do
          middleware.call(event_data)
        end.not_to raise_error
      end
    end
  end

  describe "UC-019 compliance (Retention-Based Routing)" do
    it "routes short retention events to hot storage" do
      E11y.configuration.routing_rules = [
        lambda { |event|
          days = (Time.parse(event[:retention_until]) - Time.now) / 86_400
          days <= 30 ? :loki : :s3_glacier
        }
      ]

      event_data = {
        event_name: "debug.log",
        retention_until: (Time.now + 7.days).iso8601
      }

      middleware.call(event_data)

      expect(loki_adapter).to have_received(:write)
      expect(s3_glacier_adapter).not_to have_received(:write)
    end

    it "routes long retention events to cold storage" do
      E11y.configuration.routing_rules = [
        lambda { |event|
          days = (Time.parse(event[:retention_until]) - Time.now) / 86_400
          days > 90 ? :s3_glacier : :loki
        }
      ]

      event_data = {
        event_name: "audit.user_deleted",
        retention_until: (Time.now + 365.days).iso8601
      }

      middleware.call(event_data)

      expect(s3_glacier_adapter).to have_received(:write)
      expect(loki_adapter).not_to have_received(:write)
    end

    it "routes audit events to encrypted storage (+ other matching rules)" do
      E11y.configuration.routing_rules = [
        ->(event) { :audit_encrypted if event[:audit_event] }
        # No fallback rule - only audit rule matches
      ]

      event_data = {
        event_name: "user.deleted",
        audit_event: true,
        retention_until: (Time.now + 7.years).iso8601
      }

      middleware.call(event_data)

      expect(audit_adapter).to have_received(:write)
    end

    it "routes errors to multiple adapters (Sentry + storage)" do
      E11y.configuration.routing_rules = [
        ->(event) { :sentry if event[:severity] == :error },
        ->(_event) { :loki } # Storage
      ]

      event_data = {
        event_name: "payment.failed",
        severity: :error,
        retention_until: (Time.now + 30.days).iso8601
      }

      middleware.call(event_data)

      expect(sentry_adapter).to have_received(:write)
      expect(loki_adapter).to have_received(:write)
    end
  end

  describe "ADR-004 §14 compliance (Retention-Based Routing)" do
    it "explicit adapters have highest priority" do
      E11y.configuration.routing_rules = [
        ->(_event) { :s3_glacier } # Should be ignored
      ]

      event_data = {
        event_name: "test.event",
        adapters: [:loki], # Explicit
        retention_until: (Time.now + 365.days).iso8601
      }

      middleware.call(event_data)

      expect(loki_adapter).to have_received(:write)
      expect(s3_glacier_adapter).not_to have_received(:write)
    end

    it "applies routing rules when adapters not specified" do
      E11y.configuration.routing_rules = [
        ->(_event) { :loki }
      ]

      event_data = {
        event_name: "test.event",
        # No adapters specified
        retention_until: (Time.now + 30.days).iso8601
      }

      middleware.call(event_data)

      expect(loki_adapter).to have_received(:write)
    end

    it "uses fallback adapters when no rule matches" do
      E11y.configuration.routing_rules = [
        ->(_event) {} # Never matches
      ]
      E11y.configuration.fallback_adapters = [:stdout]

      event_data = {
        event_name: "test.event",
        retention_until: (Time.now + 30.days).iso8601
      }

      middleware.call(event_data)

      expect(stdout_adapter).to have_received(:write)
    end
  end

  describe "integration" do
    it "passes event_data to next middleware" do
      collector_received = nil
      collector = lambda do |event_data|
        collector_received = event_data
        nil
      end

      routing_middleware = described_class.new(collector)

      E11y.configuration.routing_rules = [
        ->(_event) { :loki }
      ]

      event_data = {
        event_name: "test.event",
        retention_until: (Time.now + 30.days).iso8601
      }

      routing_middleware.call(event_data)

      # Collector receives complete event with routing metadata
      expect(collector_received[:event_name]).to eq("test.event")
      expect(collector_received[:routing][:adapters]).to eq([:loki])
      expect(collector_received[:routing][:routing_type]).to eq(:rules)
    end

    it "includes routed_at timestamp" do
      E11y.configuration.routing_rules = [
        ->(_event) { :loki }
      ]

      event_data = {
        event_name: "test.event",
        retention_until: (Time.now + 30.days).iso8601
      }

      result = middleware.call(event_data)

      expect(result[:routing][:routed_at]).to be_a(Time)
      expect(result[:routing][:routed_at]).to be_within(1).of(Time.now.utc)
    end
  end

  describe "complex routing scenarios" do
    # Integration test requires multiple tier scenarios with routing logic
    it "handles tiered storage routing (hot/warm/cold)" do
      E11y.configuration.routing_rules = [
        lambda { |event|
          days = (Time.parse(event[:retention_until]) - Time.now) / 86_400
          case days
          when 0..7    then :stdout       # Very short
          when 8..30   then :loki         # Short
          when 31..90  then :s3 # Medium (simulating S3 Standard)
          else              :s3_glacier # Long (cold storage)
          end
        }
      ]

      # Test hot tier
      hot_event = {
        event_name: "debug.log",
        retention_until: (Time.now + 5.days).iso8601
      }

      middleware.call(hot_event)
      expect(stdout_adapter).to have_received(:write).with(hot_event)

      # Test warm tier
      warm_event = {
        event_name: "business.event",
        retention_until: (Time.now + 15.days).iso8601
      }

      middleware.call(warm_event)
      expect(loki_adapter).to have_received(:write).with(warm_event)

      # Test cold tier
      cold_event = {
        event_name: "audit.log",
        retention_until: (Time.now + 100.days).iso8601
      }

      middleware.call(cold_event)
      expect(s3_glacier_adapter).to have_received(:write).with(cold_event)
    end

    it "combines audit routing + error routing" do
      E11y.configuration.routing_rules = [
        ->(event) { :audit_encrypted if event[:audit_event] },
        ->(event) { :sentry if event[:severity] == :error }
      ]

      # Audit + Error → both adapters
      event_data = {
        event_name: "user.deletion_failed",
        audit_event: true,
        severity: :error,
        retention_until: (Time.now + 7.years).iso8601
      }

      middleware.call(event_data)

      expect(audit_adapter).to have_received(:write)
      expect(sentry_adapter).to have_received(:write)
    end
  end
end
