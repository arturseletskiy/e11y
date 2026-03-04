# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "time"

RSpec.describe E11y::Adapters::AuditEncrypted do
  let(:temp_dir) { Dir.mktmpdir }
  let(:encryption_key) { OpenSSL::Random.random_bytes(32) }
  let(:adapter) do
    described_class.new(
      storage_path: temp_dir,
      encryption_key: encryption_key
    )
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "Encrypted Storage" do
    let(:event_data) do
      {
        event_name: "Events::UserDeleted",
        payload: {
          user_id: 123,
          deleted_by: 456,
          ip_address: "192.168.1.1",
          reason: "GDPR right to be forgotten"
        },
        timestamp: Time.now.utc.iso8601(6),
        version: 1,
        audit_signature: "abc123def456",
        audit_signed_at: Time.now.utc.iso8601(6)
      }
    end

    it "writes encrypted event to storage" do
      adapter.write(event_data)

      files = Dir.glob(File.join(temp_dir, "*.enc"))
      expect(files.size).to eq(1)
    end

    it "returns false on write errors" do
      # Simulate write error by making storage path read-only
      allow(adapter).to receive(:write_to_storage).and_raise(StandardError, "Disk full")

      expect(adapter.write(event_data)).to be false
    end

    it "warns on write errors" do
      allow(adapter).to receive(:write_to_storage).and_raise(StandardError, "Disk full")

      expect do
        adapter.write(event_data)
      end.to output(/AuditEncrypted adapter error: Disk full/).to_stderr
    end

    it "encrypts data (plaintext not visible in file)" do
      adapter.write(event_data)

      files = Dir.glob(File.join(temp_dir, "*.enc"))
      file_content = File.read(files.first)

      # Plaintext should NOT be visible
      expect(file_content).not_to include("192.168.1.1")
      expect(file_content).not_to include("GDPR right to be forgotten")
    end

    it "stores nonce and auth_tag" do
      adapter.write(event_data)

      files = Dir.glob(File.join(temp_dir, "*.enc"))
      encrypted = JSON.parse(File.read(files.first), symbolize_names: true)

      expect(encrypted[:nonce]).not_to be_nil
      expect(encrypted[:auth_tag]).not_to be_nil
      expect(encrypted[:encrypted_data]).not_to be_nil
    end

    it "uses unique nonce for each event" do
      adapter.write(event_data)
      adapter.write(event_data)

      files = Dir.glob(File.join(temp_dir, "*.enc"))
      expect(files.size).to eq(2)

      nonce1 = JSON.parse(File.read(files[0]), symbolize_names: true)[:nonce]
      nonce2 = JSON.parse(File.read(files[1]), symbolize_names: true)[:nonce]

      expect(nonce1).not_to eq(nonce2)
    end

    it "decrypts event successfully" do
      adapter.write(event_data)

      files = Dir.glob(File.join(temp_dir, "*.enc"))
      event_id = File.basename(files.first)

      decrypted = adapter.read(event_id)

      expect(decrypted[:event_name]).to eq("Events::UserDeleted")
      expect(decrypted[:payload][:user_id]).to eq(123)
      expect(decrypted[:payload][:ip_address]).to eq("192.168.1.1")
      expect(decrypted[:audit_signature]).to eq("abc123def456")
    end

    it "preserves signature metadata" do
      adapter.write(event_data)

      files = Dir.glob(File.join(temp_dir, "*.enc"))
      event_id = File.basename(files.first)

      decrypted = adapter.read(event_id)

      expect(decrypted[:audit_signature]).to eq(event_data[:audit_signature])
      expect(decrypted[:audit_signed_at]).to eq(event_data[:audit_signed_at])
    end

    it "detects tampered ciphertext" do
      adapter.write(event_data)

      files = Dir.glob(File.join(temp_dir, "*.enc"))
      filepath = files.first

      # Tamper with encrypted data
      encrypted = JSON.parse(File.read(filepath), symbolize_names: true)
      encrypted[:encrypted_data] = Base64.strict_encode64("tampered")
      File.write(filepath, JSON.generate(encrypted))

      event_id = File.basename(filepath)

      # read now returns nil on decryption failure instead of raising
      expect(adapter.read(event_id)).to be_nil
    end

    it "detects tampered auth_tag" do
      adapter.write(event_data)

      files = Dir.glob(File.join(temp_dir, "*.enc"))
      filepath = files.first

      # Tamper with auth tag
      encrypted = JSON.parse(File.read(filepath), symbolize_names: true)
      encrypted[:auth_tag] = Base64.strict_encode64("0" * 16)
      File.write(filepath, JSON.generate(encrypted))

      event_id = File.basename(filepath)

      # read now returns nil on decryption failure instead of raising
      expect(adapter.read(event_id)).to be_nil
    end
  end

  describe "Configuration" do
    it "accepts nil encryption key in development" do
      expect do
        described_class.new(
          storage_path: temp_dir,
          encryption_key: nil
        )
      end.not_to raise_error
    end

    it "requires 32-byte encryption key if provided" do
      expect do
        described_class.new(
          storage_path: temp_dir,
          encryption_key: "too_short"
        )
      end.to raise_error(E11y::Error, /must be 32 bytes/)
    end

    it "creates storage directory if not exists" do
      new_dir = File.join(temp_dir, "new_audit_dir")
      expect(Dir.exist?(new_dir)).to be false

      described_class.new(
        storage_path: new_dir,
        encryption_key: encryption_key
      )

      expect(Dir.exist?(new_dir)).to be true
    end

    it "uses ENV E11Y_AUDIT_ENCRYPTION_KEY when available" do
      key_hex = encryption_key.unpack1("H*")
      ClimateControl.modify E11Y_AUDIT_ENCRYPTION_KEY: key_hex do
        adapter = described_class.new(storage_path: temp_dir)
        expect(adapter.encryption_key).not_to be_nil
      end
    end

    it "handles hex-encoded encryption keys" do
      # Create a 64-character hex string (32 bytes when decoded)
      key_hex = encryption_key.unpack1("H*")

      # Use ClimateControl to set ENV and create adapter with no explicit key
      ClimateControl.modify E11Y_AUDIT_ENCRYPTION_KEY: key_hex do
        adapter = described_class.new(storage_path: temp_dir)

        event_data = {
          event_name: "Events::Test",
          payload: { data: "test" },
          timestamp: Time.now.utc.iso8601(6),
          version: 1
        }

        # Should encrypt and decrypt successfully
        expect { adapter.write(event_data) }.not_to raise_error
      end
    end

    it "raises error in production without encryption key" do
      ClimateControl.modify E11Y_AUDIT_ENCRYPTION_KEY: nil do
        stub_const("Rails", double(root: temp_dir, env: double(production?: true)))

        expect do
          described_class.new(
            storage_path: temp_dir,
            encryption_key: nil
          )
        end.to raise_error(E11y::Error, /E11Y_AUDIT_ENCRYPTION_KEY must be set in production/)
      end
    end
  end

  describe "Filename Format" do
    let(:event_data) do
      {
        event_name: "Events::PermissionChanged",
        payload: { user_id: 123 },
        timestamp: Time.now.utc.iso8601(6),
        version: 1
      }
    end

    it "includes timestamp in filename for sorting" do
      adapter.write(event_data)

      files = Dir.glob(File.join(temp_dir, "*.enc"))
      filename = File.basename(files.first)

      expect(filename).to match(/^\d{8}_\d{6}_\d{6}_.*\.enc$/)
    end

    it "includes event name in filename" do
      adapter.write(event_data)

      files = Dir.glob(File.join(temp_dir, "*.enc"))
      filename = File.basename(files.first)

      expect(filename).to include("Events_PermissionChanged")
    end
  end
end
