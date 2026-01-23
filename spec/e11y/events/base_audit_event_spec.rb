# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Events::BaseAuditEvent do
  # Create a concrete audit event class for testing
  let(:concrete_audit_event) do
    Class.new(described_class) do
      def self.name
        "TestAuditEvent"
      end

      severity :info

      schema do
        required(:user_id).filled(:integer)
        required(:action).filled(:string)
      end
    end
  end

  describe "inheritance" do
    it "inherits from E11y::Event::Base" do
      expect(described_class.superclass).to eq(E11y::Event::Base)
    end

    it "is a valid Event::Base subclass" do
      expect(described_class.ancestors).to include(E11y::Event::Base)
    end
  end

  describe "preset inclusion" do
    it "includes E11y::Presets::AuditEvent" do
      expect(described_class.ancestors).to include(E11y::Presets::AuditEvent)
    end

    it "has unlimited rate limit from AuditEvent preset" do
      expect(concrete_audit_event.resolve_rate_limit).to be_nil
    end

    it "has 100% sample rate from AuditEvent preset" do
      expect(concrete_audit_event.resolve_sample_rate).to eq(1.0)
    end
  end

  describe ".audit_event?" do
    it "returns true for audit event marker" do
      expect(described_class.audit_event?).to be true
    end

    it "returns true for subclasses" do
      expect(concrete_audit_event.audit_event?).to be true
    end
  end

  describe "schema definition" do
    it "allows subclasses to define schemas" do
      expect { concrete_audit_event }.not_to raise_error
    end

    it "supports schema validation" do
      # Schema requires user_id and action
      expect(concrete_audit_event).to respond_to(:schema)
    end
  end

  describe "severity configuration" do
    it "does not set default severity (user must explicitly set)" do
      # BaseAuditEvent doesn't force severity
      # Subclasses must explicitly set it
      expect(concrete_audit_event).to respond_to(:severity)
    end

    it "allows info severity for routine audit logging" do
      info_audit = Class.new(described_class) do
        def self.name
          "InfoAuditEvent"
        end

        severity :info
        schema { required(:data).filled(:string) }
      end

      expect(info_audit.audit_event?).to be true
    end

    it "allows warn severity for suspicious actions" do
      warn_audit = Class.new(described_class) do
        def self.name
          "WarnAuditEvent"
        end

        severity :warn
        schema { required(:data).filled(:string) }
      end

      expect(warn_audit.audit_event?).to be true
    end

    it "allows error severity for violations" do
      error_audit = Class.new(described_class) do
        def self.name
          "ErrorAuditEvent"
        end

        severity :error
        schema { required(:data).filled(:string) }
      end

      expect(error_audit.audit_event?).to be true
    end

    it "allows fatal severity for critical security events" do
      fatal_audit = Class.new(described_class) do
        def self.name
          "FatalAuditEvent"
        end

        severity :fatal
        schema { required(:data).filled(:string) }
      end

      expect(fatal_audit.audit_event?).to be true
    end
  end

  describe "compliance requirements" do
    it "inherits unlimited rate limit from AuditEvent preset" do
      # Compliance: Audit events must NEVER be dropped
      expect(concrete_audit_event.resolve_rate_limit).to be_nil
    end

    it "inherits 100% sampling from AuditEvent preset" do
      # Compliance: ALL audit events must be tracked
      expect(concrete_audit_event.resolve_sample_rate).to eq(1.0)
    end

    it "maintains audit_event? marker for pipeline routing" do
      # Audit events use Phase 4 audit pipeline
      expect(concrete_audit_event.audit_event?).to be true
    end
  end

  describe "multiple audit event subclasses" do
    it "all subclasses have audit behavior" do
      subclasses = Array.new(3) do |i|
        Class.new(described_class) do
          define_singleton_method(:name) { "AuditEvent#{i}" }
          severity :info
          schema { required(:data).filled(:string) }
        end
      end

      subclasses.each do |subclass|
        expect(subclass.audit_event?).to be true
        expect(subclass.resolve_rate_limit).to be_nil
        expect(subclass.resolve_sample_rate).to eq(1.0)
      end
    end
  end
end
