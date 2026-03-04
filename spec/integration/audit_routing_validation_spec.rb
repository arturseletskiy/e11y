# frozen_string_literal: true

require "rails_helper"

# Test that audit events MUST have proper routing configuration
# Validates UC-012 compliance requirement: audit events cannot use fallback adapters
RSpec.describe "Audit Event Routing Validation", :integration do
  let(:audit_event_class) do
    Class.new(E11y::Event::Base) do
      audit_event true

      schema do
        required(:user_id).filled(:integer)
        required(:action).filled(:string)
      end

      def self.name
        "Events::UnroutedAuditEvent"
      end
    end
  end

  before do
    # Configure routing rules that DON'T match audit events
    E11y.config.routing_rules = [
      ->(event) { :memory if event[:event_name] == "SomeOtherEvent" }
    ]
    # Fallback goes to stdout (NOT compliance-grade!)
    E11y.config.fallback_adapters = [:stdout]

    # Clear cached pipeline
    E11y.config.instance_variable_set(:@built_pipeline, nil)
  end

  after do
    # Restore default routing
    E11y.config.routing_rules = []
    E11y.config.fallback_adapters = [:stdout]
    E11y.config.instance_variable_set(:@built_pipeline, nil)
  end

  it "raises error when audit event routes to fallback adapter" do
    expect do
      audit_event_class.track(
        user_id: 123,
        action: "deleted_account"
      )
    end.to raise_error(E11y::Error, /CRITICAL: Audit event has no routing configuration/)
  end

  it "includes helpful error message with fix options" do
    expect do
      audit_event_class.track(user_id: 123, action: "test")
    end.to raise_error do |error|
      expect(error.message).to include("Add explicit adapters")
      expect(error.message).to include("Configure routing rule")
      expect(error.message).to include("audit_encrypted")
    end
  end

  context "with proper routing configured" do
    let(:storage_path) { Dir.mktmpdir("audit_test") }
    let(:test_encryption_key) { OpenSSL::Random.random_bytes(32) }

    before do
      # Configure proper audit adapter
      audit_adapter = E11y::Adapters::AuditEncrypted.new(
        storage_path: storage_path,
        encryption_key: test_encryption_key
      )
      E11y.config.adapters[:audit_encrypted] = audit_adapter

      # Configure routing rule that matches audit events
      E11y.config.routing_rules = [
        ->(event) { :audit_encrypted if event[:audit_event] }
      ]

      # Set signing key
      ENV["E11Y_AUDIT_SIGNING_KEY"] = SecureRandom.hex(32)

      # Clear cached pipeline
      E11y.config.instance_variable_set(:@built_pipeline, nil)
    end

    after do
      FileUtils.rm_rf(storage_path)
      ENV.delete("E11Y_AUDIT_SIGNING_KEY")
    end

    it "allows audit event with proper routing" do
      expect do
        audit_event_class.track(
          user_id: 123,
          action: "deleted_account"
        )
      end.not_to raise_error

      # Verify event was written
      encrypted_files = Dir.glob(File.join(storage_path, "*.enc"))
      expect(encrypted_files.size).to eq(1)
    end
  end

  context "with explicit adapters" do
    let(:storage_path) { Dir.mktmpdir("audit_test") }
    let(:test_encryption_key) { OpenSSL::Random.random_bytes(32) }

    let(:explicit_audit_event) do
      Class.new(E11y::Event::Base) do
        audit_event true
        adapters :audit_encrypted # Explicit adapter

        schema do
          required(:user_id).filled(:integer)
          required(:action).filled(:string)
        end

        def self.name
          "Events::ExplicitAuditEvent"
        end
      end
    end

    before do
      # Configure audit adapter
      audit_adapter = E11y::Adapters::AuditEncrypted.new(
        storage_path: storage_path,
        encryption_key: test_encryption_key
      )
      E11y.config.adapters[:audit_encrypted] = audit_adapter

      # Set signing key
      ENV["E11Y_AUDIT_SIGNING_KEY"] = SecureRandom.hex(32)

      # Routing rules still don't match (but explicit adapter overrides)
      E11y.config.routing_rules = []
      E11y.config.fallback_adapters = [:stdout]

      # Clear cached pipeline
      E11y.config.instance_variable_set(:@built_pipeline, nil)
    end

    after do
      FileUtils.rm_rf(storage_path)
      ENV.delete("E11Y_AUDIT_SIGNING_KEY")
    end

    it "allows audit event with explicit adapter (bypasses fallback validation)" do
      expect do
        explicit_audit_event.track(
          user_id: 123,
          action: "deleted_account"
        )
      end.not_to raise_error

      # Verify event was written
      encrypted_files = Dir.glob(File.join(storage_path, "*.enc"))
      expect(encrypted_files.size).to eq(1)
    end
  end
end
