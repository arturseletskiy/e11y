# AuditEncrypted Adapter — Cucumber QA Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Verify the AuditEncrypted adapter's encryption, key rotation, and thread-safety behavior — exposing that a new random key is generated on every adapter restart (making old ciphertexts permanently unreadable) and that concurrent writes can corrupt the audit log file.

**Approach:** Instantiate the adapter directly. Encrypt and decrypt payloads. Simulate key rotation by creating a second instance. Check thread safety with concurrent writes. Inspect the output file format.

**Known bugs covered:**
- `AuditEncrypted` generates a new random `SecureRandom.hex(32)` key on every instantiation — no persistence, no rotation protocol. All previously encrypted audit entries become permanently unreadable after restart.
- `write_to_file` uses `File.write(path, content, mode: "a")` without a mutex — concurrent writes from multiple threads can interleave, corrupting JSONL lines.
- No initialization vector (IV) persistence check — IV may be reused across writes if state is not reset per entry.

---

## Task 1: Feature file

**Files:**
- Create: `features/audit_encrypted.feature`

**Step 1: Write the feature file**

```gherkin
# features/audit_encrypted.feature
@audit_encrypted
Feature: AuditEncrypted adapter

  # AuditEncrypted writes events to an encrypted JSONL file.
  # README: "Persistent encrypted audit log with key rotation support."
  #
  # BUG 1: Key is generated randomly on each instantiation (SecureRandom.hex(32)).
  #         Events encrypted with instance A cannot be decrypted by instance B.
  #         "Key rotation support" is effectively broken — it's key destruction.
  # BUG 2: File writes are not mutex-protected — concurrent writes corrupt JSONL.

  Background:
    Given the application is running

  Scenario: AuditEncrypted adapter can be instantiated with an explicit key
    Given an AuditEncrypted adapter with a known key and a temporary file
    Then no error should be raised during adapter creation

  Scenario: AuditEncrypted adapter writes an encrypted entry to the file
    Given an AuditEncrypted adapter with a known key and a temporary file
    When I deliver an event to the AuditEncrypted adapter
    Then the audit file should exist on disk
    And the audit file should not contain plaintext event_name

  @wip
  Scenario: Events encrypted by one adapter instance can be decrypted by another with the same key
    # BUG: Random key per instantiation — second instance has a DIFFERENT key.
    # Decryption of entries from the first instance will fail.
    Given an AuditEncrypted adapter with a known key and a temporary file
    When I deliver an event to the AuditEncrypted adapter
    And I create a second AuditEncrypted adapter with the same key and file
    Then the second adapter should be able to read and decrypt the entries

  @wip
  Scenario: A new AuditEncrypted instance without explicit key cannot decrypt entries from a previous instance
    # Documents the actual broken behavior: random key means permanent data loss.
    Given an AuditEncrypted adapter with a known key and a temporary file
    When I deliver an event to the AuditEncrypted adapter
    And I create a new AuditEncrypted adapter without specifying the key
    Then decryption should fail with a key mismatch error

  @wip
  Scenario: Concurrent writes do not corrupt the audit file
    # BUG: No mutex in write_to_file — lines from different threads can interleave.
    Given an AuditEncrypted adapter with a known key and a temporary file
    When 10 threads simultaneously deliver events to the AuditEncrypted adapter
    Then every line in the audit file should be valid JSON
    And the audit file should contain exactly 10 entries
```

**Step 2: Run to verify undefined steps**

```bash
bundle exec cucumber features/audit_encrypted.feature --dry-run
```

---

## Task 2: Step definitions

**Files:**
- Create: `features/step_definitions/audit_encrypted_steps.rb`

**Step 1: Write step definitions**

```ruby
# features/step_definitions/audit_encrypted_steps.rb
# frozen_string_literal: true

require "tempfile"

Given("an AuditEncrypted adapter with a known key and a temporary file") do
  skip_this_scenario unless defined?(E11y::Adapters::AuditEncrypted)
  @audit_key = "a" * 64   # 32-byte hex key (64 hex chars)
  @audit_temp = Tempfile.new(["e11y_audit", ".jsonl"])
  @audit_error = nil
  begin
    @audit_adapter = E11y::Adapters::AuditEncrypted.new(
      key: @audit_key,
      path: @audit_temp.path
    )
  rescue => e
    @audit_error = e
  end
end

Then("no error should be raised during adapter creation") do
  expect(@audit_error).to be_nil,
    "AuditEncrypted.new raised: #{@audit_error&.class}: #{@audit_error&.message}"
end

When("I deliver an event to the AuditEncrypted adapter") do
  skip_this_scenario unless @audit_adapter
  @deliver_error = nil
  begin
    @audit_adapter.deliver(
      event_name: "payment_processed",
      severity: :info,
      order_id: "ord-enc-1",
      amount: 99.99,
      timestamp: Time.now.iso8601
    )
  rescue => e
    @deliver_error = e
  end
end

Then("the audit file should exist on disk") do
  expect(File.exist?(@audit_temp.path)).to be(true),
    "Audit file not found at #{@audit_temp.path}"
end

Then("the audit file should not contain plaintext event_name") do
  content = File.read(@audit_temp.path)
  expect(content).not_to include("payment_processed"),
    "Audit file contains plaintext 'payment_processed' — data is NOT encrypted. " \
    "Content: #{content[0, 200].inspect}"
end

And("I create a second AuditEncrypted adapter with the same key and file") do
  skip_this_scenario unless defined?(E11y::Adapters::AuditEncrypted)
  @second_adapter = E11y::Adapters::AuditEncrypted.new(
    key: @audit_key,
    path: @audit_temp.path
  )
end

Then("the second adapter should be able to read and decrypt the entries") do
  skip_this_scenario unless @second_adapter
  entries = @second_adapter.read_entries rescue nil
  expect(entries).not_to be_nil,
    "Second adapter has no read_entries method — cannot verify decryption."
  expect(entries).not_to be_empty,
    "Second adapter read 0 entries from file. " \
    "BUG: Random key per instance — second adapter has a DIFFERENT key, " \
    "making all entries from the first adapter permanently unreadable."
  first = entries.first
  has_name = first.is_a?(Hash) && (first.key?(:event_name) || first.key?("event_name"))
  expect(has_name).to be(true),
    "Decrypted entry missing event_name. Entry: #{first.inspect}"
end

And("I create a new AuditEncrypted adapter without specifying the key") do
  skip_this_scenario unless defined?(E11y::Adapters::AuditEncrypted)
  @new_adapter = E11y::Adapters::AuditEncrypted.new(path: @audit_temp.path)
end

Then("decryption should fail with a key mismatch error") do
  skip_this_scenario unless @new_adapter
  entries = nil
  decrypt_error = nil
  begin
    entries = @new_adapter.read_entries
  rescue => e
    decrypt_error = e
  end
  has_data = entries.is_a?(Array) && !entries.empty? &&
             entries.first.is_a?(Hash) &&
             (entries.first.key?(:event_name) || entries.first.key?("event_name"))
  expect(has_data).to be(false),
    "New adapter with random key successfully decrypted entries from old adapter. " \
    "This SHOULD fail — if it passed, encryption is not working correctly."
end

When("{int} threads simultaneously deliver events to the AuditEncrypted adapter") do |thread_count|
  skip_this_scenario unless @audit_adapter
  threads = thread_count.times.map do |i|
    Thread.new do
      @audit_adapter.deliver(
        event_name: "concurrent_event_#{i}",
        severity: :info,
        thread_index: i,
        timestamp: Time.now.iso8601
      )
    end
  end
  threads.each(&:join)
end

Then("every line in the audit file should be valid JSON") do
  @audit_temp.rewind
  lines = @audit_temp.readlines.map(&:strip).reject(&:empty?)
  corrupt_lines = lines.reject { |l| JSON.parse(l) rescue false }
  expect(corrupt_lines).to be_empty,
    "#{corrupt_lines.size} corrupt line(s) found in audit file. " \
    "BUG: write_to_file has no mutex — concurrent writes interleave. " \
    "Corrupt: #{corrupt_lines.first(3).map(&:inspect).join(', ')}"
ensure
  @audit_temp&.close
  @audit_temp&.unlink
end

Then("the audit file should contain exactly {int} entries") do |count|
  @audit_temp.rewind
  lines = @audit_temp.readlines.map(&:strip).reject(&:empty?)
  expect(lines.size).to eq(count),
    "Expected #{count} entries in audit file, got #{lines.size}. " \
    "Some writes may have been lost due to concurrent write corruption."
end
```

**Step 2: Run the feature**

```bash
bundle exec cucumber features/audit_encrypted.feature
```

Expected:
- `Adapter can be instantiated with explicit key` → **PASS**
- `Adapter writes encrypted entry` → **PASS**
- `@wip` scenarios → **PENDING**

Run wip:
```bash
bundle exec cucumber features/audit_encrypted.feature --tags @wip
```
Expected: `same-key decryption` **FAIL** (random key), `new instance decryption` **FAIL** or behavior undefined, `concurrent writes` **FAIL** (corrupt lines).

**Step 3: Commit**

```bash
git add features/audit_encrypted.feature \
        features/step_definitions/audit_encrypted_steps.rb
git commit -m "test(cucumber): AuditEncrypted — random key per restart, thread-unsafe writes"
```
