# frozen_string_literal: true

require "rails_helper"
require "openssl"
require "securerandom"

# Audit trail integration tests for UC-012
# Tests audit event tracking, encryption (AES-256-GCM), signing (HMAC-SHA256), tamper detection, compliance
#
# Scenarios:
# 1. Track actions (separate pipeline, no PII filtering, signing, encryption)
# 2. Query logs (adapter.read() or query API if implemented)
# 3. Export (if export API implemented)
# 4. Encryption (AES-256-GCM encryption/decryption verification)
# 5. Tamper detection (signature verification detects tampering)
# 6. Key rotation (if implemented, or basic key change handling)
# 7. Compliance (SOC2, HIPAA, GDPR audit requirements)

RSpec.describe "Audit Trail Integration", :integration do
  let(:storage_path) { Dir.mktmpdir("audit_test") }
  let(:test_encryption_key) { OpenSSL::Random.random_bytes(32) }
  let(:test_signing_key) { SecureRandom.hex(32) }
  let(:audit_adapter) { E11y.config.adapters[:audit_encrypted] }

  before do
    # Configure audit adapter with test storage
    audit_adapter_instance = E11y::Adapters::AuditEncrypted.new(
      storage_path: storage_path,
      encryption_key: test_encryption_key
    )
    E11y.config.adapters[:audit_encrypted] = audit_adapter_instance

    # Configure audit signing key
    ENV["E11Y_AUDIT_SIGNING_KEY"] = test_signing_key

    # Configure routing for audit events: Route audit events to audit_encrypted adapter
    E11y.config.routing_rules = [
      ->(event) { :audit_encrypted if event[:audit_event] }
    ]
    E11y.config.fallback_adapters = [:audit_encrypted]

    # Clear cached pipeline to rebuild with new configuration
    E11y.config.instance_variable_set(:@built_pipeline, nil)
  end

  after do
    FileUtils.rm_rf(storage_path)
    ENV.delete("E11Y_AUDIT_SIGNING_KEY")
  end

  describe "Scenario 1: Track actions" do
    it "tracks audit events through separate audit pipeline" do
      # Track audit event
      Events::UserDeleted.track(
        user_id: 123,
        deleted_by: 456,
        ip_address: "192.168.1.1"
      )

      # Verify event tracked: Encrypted file exists in storage
      encrypted_files = Dir.glob(File.join(storage_path, "*.enc"))
      expect(encrypted_files.size).to eq(1)

      # Read and decrypt event
      filename = File.basename(encrypted_files.first)
      decrypted_event = audit_adapter.read(filename)

      # Verify original data preserved: IP address not filtered (separate pipeline)
      expect(decrypted_event[:payload][:ip_address]).to eq("192.168.1.1")

      # Verify signing: audit_signature present
      expect(decrypted_event[:audit_signature]).to be_present
      expect(decrypted_event[:audit_signed_at]).to be_present
      expect(decrypted_event[:audit_canonical]).to be_present

      # Verify encryption: Encrypted data written (plaintext not visible)
      encrypted_content = File.read(encrypted_files.first)
      expect(encrypted_content).not_to include("192.168.1.1")
      expect(encrypted_content).not_to include("123")
    end
  end

  describe "Scenario 2: Query logs" do
    it "queries audit logs (adapter.read() or query API if implemented)" do
      # Track multiple audit events
      Events::UserDeleted.track(user_id: 123, deleted_by: 456, ip_address: "192.168.1.1")
      Events::UserDeleted.track(user_id: 789, deleted_by: 456, ip_address: "192.168.1.2")
      Events::PermissionChanged.track(user_id: 123, permission: "admin", action: "granted",
                                      granted_by: 456)

      # Verify events stored
      encrypted_files = Dir.glob(File.join(storage_path, "*.enc"))
      expect(encrypted_files.size).to eq(3)

      # Query events: Read each event using adapter.read()
      events = encrypted_files.map do |filepath|
        filename = File.basename(filepath)
        audit_adapter.read(filename)
      end

      # Verify results: Events returned correctly
      expect(events.size).to eq(3)

      # Verify signature validation: Signatures verified during query
      events.each do |event|
        expect(event[:audit_signature]).to be_present
        expect(E11y::Middleware::AuditSigning.verify_signature(event)).to be(true)
      end

      # Verify filtering: Can filter by event name (manual filtering)
      user_deleted_events = events.select { |e| e[:event_name] == "Events::UserDeleted" }
      expect(user_deleted_events.size).to eq(2)

      permission_changed_events = events.select { |e| e[:event_name] == "Events::PermissionChanged" }
      expect(permission_changed_events.size).to eq(1)
    end
  end

  describe "Scenario 3: Export" do
    it "exports audit logs (if export API implemented)" do
      # Track multiple audit events
      Events::UserDeleted.track(user_id: 123, deleted_by: 456, ip_address: "192.168.1.1")
      Events::UserDeleted.track(user_id: 789, deleted_by: 456, ip_address: "192.168.1.2")
      Events::PermissionChanged.track(user_id: 123, permission: "admin", action: "granted", granted_by: 456)

      # Export events: Read all encrypted files and export as JSON
      encrypted_files = Dir.glob(File.join(storage_path, "*.enc"))
      exported_events = encrypted_files.map do |filepath|
        filename = File.basename(filepath)
        audit_adapter.read(filename)
      end

      # Verify export works: Events exported
      expect(exported_events.size).to eq(3)

      # Verify format correct: Export format matches requirements (JSON structure)
      exported_events.each do |event|
        expect(event).to be_a(Hash)
        expect(event[:event_name]).to be_present
        expect(event[:payload]).to be_present
        expect(event[:timestamp]).to be_present

        # Verify signatures included: Signatures present in export
        expect(event[:audit_signature]).to be_present
        expect(event[:audit_signed_at]).to be_present
      end
    end
  end

  describe "Scenario 4: Encryption" do
    it "verifies AES-256-GCM encryption works correctly" do
      # Track audit event
      original_payload = { user_id: 123, deleted_by: 456, ip_address: "192.168.1.1" }
      Events::UserDeleted.track(**original_payload)

      # Read encrypted event from storage
      encrypted_files = Dir.glob(File.join(storage_path, "*.enc"))
      expect(encrypted_files.size).to eq(1)

      filename = File.basename(encrypted_files.first)

      # Decrypt event: Use adapter.read() which calls decrypt_event internally
      decrypted_event = audit_adapter.read(filename)

      # Verify decryption works: Event decrypted correctly
      expect(decrypted_event).to be_a(Hash)
      expect(decrypted_event[:payload]).to be_present

      # Verify data integrity: Decrypted data matches original
      expect(decrypted_event[:payload][:user_id]).to eq(123)
      expect(decrypted_event[:payload][:deleted_by]).to eq(456)
      expect(decrypted_event[:payload][:ip_address]).to eq("192.168.1.1")

      # Verify authentication tag: Tag validates encryption integrity (decryption succeeds)
      # If tag was invalid, decrypt_event would raise OpenSSL::Cipher::CipherError
      expect(decrypted_event[:event_name]).to eq("Events::UserDeleted")
    end
  end

  describe "Scenario 5: Tamper detection" do
    it "verifies signature verification detects tampering" do
      # Track audit event
      Events::UserDeleted.track(user_id: 123, deleted_by: 456, ip_address: "192.168.1.1")

      # Read encrypted event from storage
      encrypted_files = Dir.glob(File.join(storage_path, "*.enc"))
      filename = File.basename(encrypted_files.first)
      decrypted_event = audit_adapter.read(filename)

      # Verify signature: Original event signature valid
      expect(E11y::Middleware::AuditSigning.verify_signature(decrypted_event)).to be(true)

      # Tamper event: Modify payload
      tampered_event = decrypted_event.dup
      tampered_event[:payload] = tampered_event[:payload].dup
      tampered_event[:payload][:user_id] = 999 # Modify user_id

      # Verify tamper detection: Modified event signature invalid
      expect(E11y::Middleware::AuditSigning.verify_signature(tampered_event)).to be(false)
    end
  end

  describe "Scenario 6: Key rotation" do
    it "verifies key rotation works (if implemented, or basic key change handling)" do
      # Track events with old key
      test_encryption_key
      Events::UserDeleted.track(user_id: 123, deleted_by: 456, ip_address: "192.168.1.1")

      # Get encrypted files from old key
      encrypted_files_old = Dir.glob(File.join(storage_path, "*.enc"))
      expect(encrypted_files_old.size).to eq(1)

      # Save reference to old adapter before rotation
      old_adapter = audit_adapter

      # Rotate key: Create new adapter with new key
      new_key = OpenSSL::Random.random_bytes(32)
      new_storage_path = Dir.mktmpdir("audit_test_new")
      new_adapter = E11y::Adapters::AuditEncrypted.new(
        storage_path: new_storage_path,
        encryption_key: new_key
      )

      # Update config to use new adapter
      E11y.config.adapters[:audit_encrypted] = new_adapter

      # Track new events: Verify new events encrypted with new key
      Events::UserDeleted.track(user_id: 789, deleted_by: 456, ip_address: "192.168.1.2")

      # Verify new events use new key (stored in new location)
      new_encrypted_files = Dir.glob(File.join(new_storage_path, "*.enc"))
      expect(new_encrypted_files.size).to eq(1)

      # Verify old events readable: Can decrypt events encrypted with old key
      old_filename = File.basename(encrypted_files_old.first)
      old_decrypted = old_adapter.read(old_filename)
      expect(old_decrypted[:payload][:user_id]).to eq(123)

      # Verify new events use new key: Can decrypt with new adapter
      new_filename = File.basename(new_encrypted_files.first)
      new_decrypted = new_adapter.read(new_filename)
      expect(new_decrypted[:payload][:user_id]).to eq(789)

      # Cleanup
      FileUtils.rm_rf(new_storage_path)
    end
  end

  describe "Scenario 7: Compliance" do
    it "verifies audit trail meets compliance requirements (SOC2, HIPAA, GDPR)" do # rubocop:todo RSpec/ExampleLength
      # Track compliance-critical events
      # User deletion (GDPR)
      Events::UserDeleted.track(
        user_id: 123,
        deleted_by: 456,
        ip_address: "192.168.1.1"
      )

      # Data access (HIPAA)
      Events::DataAccessed.track(
        patient_id: 789,
        accessed_by: 456,
        access_type: "view"
      )

      # Permission change (SOC2)
      Events::PermissionChanged.track(
        user_id: 123,
        permission: "admin",
        action: "granted",
        granted_by: 456
      )

      # Verify immutability: Events cannot be modified after creation (signature prevents tampering)
      encrypted_files = Dir.glob(File.join(storage_path, "*.enc"))
      expect(encrypted_files.size).to eq(3)

      events = encrypted_files.map do |filepath|
        filename = File.basename(filepath)
        audit_adapter.read(filename)
      end

      events.each do |event|
        # Verify signature prevents tampering
        tampered = event.dup
        tampered[:payload] = tampered[:payload].dup
        # Modify a field that exists in the event (try user_id, patient_id, or any integer field)
        if tampered[:payload][:user_id]
          tampered[:payload][:user_id] = 999
        elsif tampered[:payload][:patient_id]
          tampered[:payload][:patient_id] = 999
        end
        expect(E11y::Middleware::AuditSigning.verify_signature(tampered)).to be(false)

        # Verify retention: Events stored for compliance period (file exists in storage)
        expect(event[:timestamp]).to be_present

        # Verify signing: All events cryptographically signed (non-repudiation)
        expect(event[:audit_signature]).to be_present
        expect(event[:audit_signed_at]).to be_present
        expect(E11y::Middleware::AuditSigning.verify_signature(event)).to be(true)
      end

      # Verify encryption: Sensitive data encrypted (confidentiality)
      encrypted_files.each do |filepath|
        encrypted_content = File.read(filepath)
        # Plaintext should NOT be visible
        expect(encrypted_content).not_to include("123")
        expect(encrypted_content).not_to include("789")
        expect(encrypted_content).not_to include("192.168.1.1")
      end
    end
  end
end
