# frozen_string_literal: true

require "rails_helper"

# Test that audit events can use EXPLICIT adapters (UC-019 scenario)
# This ensures our fix doesn't break explicit adapter configuration
RSpec.describe "Audit Events with Explicit Adapters", :integration do
  let(:storage_path) { Dir.mktmpdir("audit_test") }
  let(:test_encryption_key) { OpenSSL::Random.random_bytes(32) }
  let(:test_signing_key) { SecureRandom.hex(32) }

  # Create a test audit event class with EXPLICIT adapters
  let(:audit_event_with_explicit_adapters) do
    Class.new(E11y::Event::Base) do
      audit_event true
      adapters :audit_encrypted # ← Explicit adapter, should bypass routing rules

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

    # Configure signing key
    ENV["E11Y_AUDIT_SIGNING_KEY"] = test_signing_key

    # Configure routing rules that should be BYPASSED by explicit adapters
    E11y.config.routing_rules = [
      ->(event) { :memory if event[:audit_event] } # This should be ignored!
    ]
    E11y.config.fallback_adapters = [:memory]

    # Clear cached pipeline
    E11y.config.instance_variable_set(:@built_pipeline, nil)
  end

  after do
    FileUtils.rm_rf(storage_path)
    ENV.delete("E11Y_AUDIT_SIGNING_KEY")
  end

  it "respects explicit adapters even for audit events" do
    # Track event with explicit adapter
    audit_event_with_explicit_adapters.track(
      user_id: 123,
      action: "deleted_account"
    )

    # Verify: Event went to audit_encrypted (explicit), NOT memory (routing rule)
    encrypted_files = Dir.glob(File.join(storage_path, "*.enc"))
    expect(encrypted_files.size).to eq(1), "Expected 1 encrypted file, got #{encrypted_files.size}"

    # Verify: Memory adapter received nothing (routing rule was bypassed)
    memory_adapter = E11y.config.adapters[:memory]
    expect(memory_adapter.events.size).to eq(0), "Memory adapter should be empty (routing bypassed)"
  end

  it "uses routing rules when no explicit adapters set" do
    # Create audit event WITHOUT explicit adapters
    audit_event_without_explicit = Class.new(E11y::Event::Base) do
      audit_event true
      # NO adapters specified → should use routing rules

      schema do
        required(:user_id).filled(:integer)
        required(:action).filled(:string)
      end

      def self.name
        "Events::ImplicitAuditEvent"
      end
    end

    # Track event
    audit_event_without_explicit.track(
      user_id: 456,
      action: "viewed_document"
    )

    # Verify: Event went to memory (routing rule), NOT audit_encrypted
    memory_adapter = E11y.config.adapters[:memory]
    expect(memory_adapter.events.size).to eq(1), "Expected 1 event in memory (routing rule applied)"

    # Verify: No encrypted files (explicit adapter not used)
    encrypted_files = Dir.glob(File.join(storage_path, "*.enc"))
    expect(encrypted_files.size).to eq(0), "Expected 0 encrypted files (routing to memory)"
  end
end
