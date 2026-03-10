# features/audit_encrypted.feature
@audit_encrypted
Feature: AuditEncrypted adapter

  # AuditEncrypted stores audit events as individually-encrypted files on disk.
  # README: "Persistent encrypted audit log with key rotation support."
  #
  # Fixed: default_encryption_key now derives a stable key via PBKDF2 for dev/test,
  #         so two instances without an explicit key share the same derived key.
  #
  # NOTE: Each event is written to its own .enc file (not a shared JSONL file),
  #       so the concurrent-write-corruption risk is lower than in JSONL adapters.

  Background:
    Given the application is running

  Scenario: AuditEncrypted adapter can be instantiated with an explicit 32-byte key
    Given an AuditEncrypted adapter with a known key and a temp storage directory
    Then no adapter creation error should have been raised

  Scenario: AuditEncrypted adapter writes an encrypted file for each event
    Given an AuditEncrypted adapter with a known key and a temp storage directory
    When I write an event to the AuditEncrypted adapter
    Then the audit storage directory should contain at least 1 file
    And the written audit file should not contain the plaintext order_id value

  Scenario: An event encrypted with key A can be decrypted with the same key A
    Given an AuditEncrypted adapter with a known key and a temp storage directory
    When I write an event to the AuditEncrypted adapter
    And I read the encrypted audit file with the same key
    Then the decrypted payload should contain the original event_name

  Scenario: A new AuditEncrypted instance without explicit key cannot decrypt entries from a previous instance
    Given an AuditEncrypted adapter with a known key and a temp storage directory
    When I write an event to the AuditEncrypted adapter
    And I create a new AuditEncrypted adapter without specifying the key
    Then the new adapter should fail to decrypt the previously written entry
