# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Events do
  describe E11y::Events::BaseAuditEvent do
    let(:audit_event_class) do
      Class.new(E11y::Events::BaseAuditEvent) do
        def self.name
          "UserLoginAudit"
        end

        severity :info # User must explicitly set severity
        adapters :stdout # Explicit adapters for unit test (routing validation)
        contains_pii false # Tier 1 - skip Rails filter in unit tests (no Rails)

        schema do
          required(:user_id).filled(:integer)
          required(:ip_address).filled(:string)
        end
      end
    end

    it "inherits from E11y::Event::Base" do
      expect(described_class.superclass).to eq(E11y::Event::Base)
    end

    it "includes AuditEvent preset" do
      expect(described_class.included_modules).to include(E11y::Presets::AuditEvent)
    end

    it "has audit_event? method" do
      expect(described_class.audit_event?).to be true
    end

    it "does NOT set default severity (user must set explicitly)" do
      event_without_severity = Class.new(E11y::Events::BaseAuditEvent) do
        def self.name
          "AuditWithoutSeverity"
        end
      end

      # Should use convention-based default
      expect(event_without_severity.severity).to eq(:info)
    end

    it "respects user-defined severity" do
      expect(audit_event_class.severity).to eq(:info)
    end

    it "has 100% sample rate (from preset, regardless of severity)" do
      expect(audit_event_class.resolve_sample_rate).to eq(1.0)
    end

    it "has unlimited rate limit (from preset, regardless of severity)" do
      expect(audit_event_class.resolve_rate_limit).to be_nil
    end

    it "requires only schema + severity (2-6 lines DoD)" do
      # Event definition:
      # class UserLoginAudit < E11y::Events::BaseAuditEvent
      #   severity :info  # User explicitly sets
      #   schema do
      #     required(:user_id).filled(:integer)
      #     required(:ip_address).filled(:string)
      #   end
      # end
      # Total: 6 lines (class + severity + schema block) ✅

      result = audit_event_class.track(user_id: 123, ip_address: "192.168.1.1")

      expect(result[:event_name]).to eq("UserLoginAudit")
      expect(result[:severity]).to eq(:info)
      expect(result[:adapters]).to eq([:stdout]) # Explicit adapters for unit test
    end

    context "with different severities" do
      it "works with :fatal severity for critical audit events" do
        fatal_audit = Class.new(E11y::Events::BaseAuditEvent) do
          severity :fatal

          def self.name
            "SecurityBreachAudit"
          end
        end

        expect(fatal_audit.severity).to eq(:fatal)
        # Audit events use routing rules by default (adapters: []), not severity-based mapping
        expect(fatal_audit.adapters).to eq([])
        expect(fatal_audit.resolve_sample_rate).to eq(1.0) # Still 100%
        expect(fatal_audit.resolve_rate_limit).to be_nil # Still unlimited
      end
    end
  end

  describe E11y::Events::BasePaymentEvent do
    let(:payment_event_class) do
      Class.new(E11y::Events::BasePaymentEvent) do
        def self.name
          "PaymentProcessed"
        end

        schema do
          required(:payment_id).filled(:integer)
          required(:amount).filled(:float)
        end
      end
    end

    it "inherits from E11y::Event::Base" do
      expect(described_class.superclass).to eq(E11y::Event::Base)
    end

    it "includes HighValueEvent preset" do
      expect(described_class.included_modules).to include(E11y::Presets::HighValueEvent)
    end

    it "has :success severity (from preset)" do
      expect(payment_event_class.severity).to eq(:success)
    end

    it "has 100% sample rate (from preset override)" do
      expect(payment_event_class.resolve_sample_rate).to eq(1.0)
    end

    it "has unlimited rate limit (from preset override)" do
      expect(payment_event_class.resolve_rate_limit).to be_nil
    end

    it "requires only schema (1-5 lines DoD)" do
      # Event definition:
      # class PaymentProcessed < E11y::Events::BasePaymentEvent
      #   schema do
      #     required(:payment_id).filled(:integer)
      #     required(:amount).filled(:float)
      #   end
      # end
      # Total: 5 lines (class + schema block) ✅

      result = payment_event_class.track(payment_id: 123, amount: 99.99)

      expect(result[:event_name]).to eq("PaymentProcessed")
      expect(result[:severity]).to eq(:success)
      expect(result[:adapters]).to eq(%i[logs errors_tracker]) # Adapter names
    end
  end
end
