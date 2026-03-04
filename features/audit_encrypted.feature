# features/audit_encrypted.feature
@audit_encrypted
Feature: AuditEncrypted adapter

  # AuditEncrypted stores audit events as individually-encrypted files on disk.
  # README: "Persistent encrypted audit log with key rotation support."
  #
  # BUG 1: Key is generated randomly on each instantiation when no explicit key
  #         is provided (OpenSSL::Random.random_bytes(32) in default_encryption_key).
  #         Two instances started without an explicit key have different keys —
  #         data encrypted by instance A cannot be decrypted by instance B.
  #         "Key rotation support" is effectively key destruction on restart.
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
    # BUG: default_encryption_key calls OpenSSL::Random.random_bytes(32) —
    # a new adapter instance gets a DIFFERENT random key on every boot.
    # All previously encrypted audit events become permanently unreadable.
    Given an AuditEncrypted adapter with a known key and a temp storage directory
    When I write an event to the AuditEncrypted adapter
    And I create a new AuditEncrypted adapter without specifying the key
    Then the new adapter should fail to decrypt the previously written entry
