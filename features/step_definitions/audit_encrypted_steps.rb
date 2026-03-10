# frozen_string_literal: true

# features/step_definitions/audit_encrypted_steps.rb
# Step definitions for audit_encrypted.feature.

require "tmpdir"
require "openssl"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def latest_audit_file(storage_dir)
  Dir.glob(File.join(storage_dir, "*.enc")).max_by { |f| File.mtime(f) }
end

# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

Given("an AuditEncrypted adapter with a known key and a temp storage directory") do
  # Use a 32-byte raw key so validate_config! passes.
  # AuditEncrypted.validate_config! requires encryption_key.bytesize == 32.
  @audit_key = OpenSSL::Random.random_bytes(32)
  @audit_storage = Dir.mktmpdir("e11y_audit_")
  @adapter_error = nil

  begin
    @audit_adapter = E11y::Adapters::AuditEncrypted.new(
      encryption_key: @audit_key,
      storage_path: @audit_storage
    )
  rescue StandardError => e
    @adapter_error = e
  end
end

After("@audit_encrypted") do
  FileUtils.rm_rf(@audit_storage) if @audit_storage && File.exist?(@audit_storage)
  @audit_adapter  = nil
  @audit_storage  = nil
  @adapter_error  = nil
  @audit_filename = nil
end

# ---------------------------------------------------------------------------
# Step definitions
# ---------------------------------------------------------------------------

Then("no adapter creation error should have been raised") do
  expect(@adapter_error).to be_nil,
                            "AuditEncrypted.new raised #{@adapter_error&.class}: #{@adapter_error&.message}"
end

When("I write an event to the AuditEncrypted adapter") do
  expect(@audit_adapter).not_to be_nil
  @test_event_name = "payment_processed"
  @audit_adapter.write(
    event_name: @test_event_name,
    severity: :info,
    order_id: "ord-enc-1",
    amount: 99.99,
    timestamp: Time.now.utc.iso8601
  )
  # Remember the file created so later steps can reference it.
  @audit_filename = latest_audit_file(@audit_storage)&.then { |f| File.basename(f) }
end

Then("the audit storage directory should contain at least {int} file") do |min|
  files = Dir.glob(File.join(@audit_storage, "*.enc"))
  expect(files.size).to be >= min,
                        "Expected >= #{min} .enc file(s) in #{@audit_storage}, found #{files.size}"
end

Then("the written audit file should not contain the plaintext order_id value") do
  file = latest_audit_file(@audit_storage)
  expect(file).not_to be_nil, "No .enc file found in #{@audit_storage}"

  content = File.read(file)
  # event_name IS stored as plaintext metadata (intentional, for routing/indexing).
  # But the actual payload fields (order_id, amount, etc.) must be encrypted.
  expect(content).not_to include("ord-enc-1"),
                         "Audit file contains plaintext order_id 'ord-enc-1' — payload is NOT encrypted. " \
                         "Content (first 300 chars): #{content[0, 300].inspect}"
end

When("I read the encrypted audit file with the same key") do
  expect(@audit_filename).not_to be_nil, "No filename recorded from write step"
  @decrypted = @audit_adapter.read(@audit_filename)
end

Then("the decrypted payload should contain the original event_name") do
  expect(@decrypted).to be_a(Hash),
                        "Expected decrypted payload to be a Hash, got: #{@decrypted.inspect}"

  has_name = @decrypted[:event_name].to_s == @test_event_name.to_s ||
             @decrypted["event_name"].to_s == @test_event_name.to_s
  expect(has_name).to be(true),
                      "Expected decrypted payload to have event_name '#{@test_event_name}', " \
                      "got: #{@decrypted.inspect}"
end

When("I create a new AuditEncrypted adapter without specifying the key") do
  # No encryption_key → default_encryption_key → OpenSSL::Random.random_bytes(32)
  # This generates a DIFFERENT key from @audit_key (BUG).
  @second_adapter = E11y::Adapters::AuditEncrypted.new(storage_path: @audit_storage)
end

Then("the new adapter should fail to decrypt the previously written entry") do
  expect(@audit_filename).not_to be_nil
  # First adapter used explicit key (@audit_key). Second adapter has no key, so uses
  # default_encryption_key (PBKDF2-derived stable key for dev/test). These are DIFFERENT keys,
  # so decryption with the second adapter must fail.
  expect do
    @second_adapter.read(@audit_filename)
  end.to raise_error(OpenSSL::Cipher::CipherError)
end
