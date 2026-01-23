# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Presets::AuditEvent do
  # Create a test event class that includes the preset
  let(:test_event_class) do
    Class.new(E11y::Event::Base) do
      include E11y::Presets::AuditEvent

      def self.name
        "TestAuditEvent"
      end

      schema do
        required(:action).filled(:string)
        required(:user_id).filled(:integer)
      end

      severity :info
    end
  end

  describe ".included" do
    it "extends the base class with ClassMethods" do
      expect(test_event_class).to respond_to(:resolve_rate_limit)
      expect(test_event_class).to respond_to(:resolve_sample_rate)
    end

    it "sets up the class correctly" do
      # Should be a valid Event::Base subclass
      expect(test_event_class.ancestors).to include(E11y::Event::Base)
      expect(test_event_class.ancestors).to include(described_class)
    end
  end

  describe ".resolve_rate_limit" do
    it "returns nil (unlimited) for compliance requirements" do
      expect(test_event_class.resolve_rate_limit).to be_nil
    end

    it "ensures audit events are never rate-limited regardless of severity" do
      # Even with info severity, rate limit should be nil
      expect(test_event_class.resolve_rate_limit).to be_nil

      # Create another audit event with fatal severity
      fatal_audit_event = Class.new(E11y::Event::Base) do
        include E11y::Presets::AuditEvent

        def self.name
          "FatalAuditEvent"
        end

        schema do
          required(:breach_type).filled(:string)
        end

        severity :fatal
      end

      expect(fatal_audit_event.resolve_rate_limit).to be_nil
    end
  end

  describe ".resolve_sample_rate" do
    it "returns 1.0 (100%) for compliance requirements" do
      expect(test_event_class.resolve_sample_rate).to eq(1.0)
    end

    it "ensures all audit events are tracked regardless of severity" do
      # Even with info severity, sample rate should be 100%
      expect(test_event_class.resolve_sample_rate).to eq(1.0)

      # Create another audit event with warn severity
      warn_audit_event = Class.new(E11y::Event::Base) do
        include E11y::Presets::AuditEvent

        def self.name
          "WarnAuditEvent"
        end

        schema do
          required(:warning).filled(:string)
        end

        severity :warn
      end

      expect(warn_audit_event.resolve_sample_rate).to eq(1.0)
    end
  end

  describe "compliance requirements" do
    it "validates that audit events cannot be dropped (nil rate limit)" do
      # Compliance requirement: Audit events must NEVER be dropped
      expect(test_event_class.resolve_rate_limit).to be_nil
    end

    it "validates that all audit events are captured (100% sample rate)" do
      # Compliance requirement: ALL audit events must be tracked
      expect(test_event_class.resolve_sample_rate).to eq(1.0)
    end

    it "works with any severity level set by user" do
      # Test with different severity levels
      severities = %i[debug info warn error fatal success]

      severities.each do |severity_level|
        audit_event = Class.new(E11y::Event::Base) do
          include E11y::Presets::AuditEvent

          define_singleton_method(:name) { "AuditEvent#{severity_level.capitalize}" }

          schema do
            required(:data).filled(:string)
          end

          severity severity_level
        end

        # All should have unlimited rate and 100% sampling
        expect(audit_event.resolve_rate_limit).to be_nil
        expect(audit_event.resolve_sample_rate).to eq(1.0)
      end
    end
  end

  describe "integration with Event::Base" do
    it "inherits from Event::Base" do
      # Should be a subclass of Event::Base
      expect(test_event_class.ancestors).to include(E11y::Event::Base)
    end

    it "allows setting severity independently of preset" do
      # Preset doesn't force severity - user decides
      info_audit = Class.new(E11y::Event::Base) do
        include E11y::Presets::AuditEvent

        severity :info
        def self.name
          "InfoAudit"
        end

        schema { required(:data).filled(:string) }
      end

      # Audit preset behavior is independent of severity
      expect(info_audit.resolve_rate_limit).to be_nil
    end
  end
end
