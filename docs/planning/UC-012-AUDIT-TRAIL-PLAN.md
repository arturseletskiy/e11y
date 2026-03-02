# UC-012 Audit Trail: Integration Test Plan

**Task:** FEAT-5409 - UC-012 Phase 2: Planning Complete  
**Date:** 2026-01-26  
**Status:** Planning Complete

---

## 📋 Executive Summary

**Test Strategy:** Event-based integration tests using Rails dummy app, following pattern from rate limiting and high cardinality protection integration tests.

**Scope:** 7 core scenarios covering track actions, query logs, export, encryption, tamper detection, key rotation, and compliance.

**Test Infrastructure:** Rails dummy app (`spec/dummy`), audit event classes, AuditSigning middleware, AuditEncrypted adapter, temporary storage directory, test encryption/signing keys.

**Note:** Tests focus on audit pipeline (separate from regular events), encryption (AES-256-GCM), signing (HMAC-SHA256), and tamper detection. Query API and export API may not be fully implemented (per AUDIT-002), so tests verify available functionality.

---

## 🎯 Test Strategy Overview

### 1. Test Approach

**Pattern:** Follow `spec/integration/rate_limiting_integration_spec.rb` and `spec/integration/high_cardinality_protection_integration_spec.rb` structure

**Key Components:**
- Rails dummy app (`spec/dummy`)
- Audit event classes in `spec/dummy/app/events/events/` with `audit_event true`
- AuditSigning middleware configured in pipeline
- AuditEncrypted adapter configured with temporary storage
- Test encryption/signing keys (not production keys)
- Temporary storage directory (cleaned up after tests)

**Test Structure:**
```ruby
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
    ENV['E11Y_AUDIT_SIGNING_KEY'] = test_signing_key
    
    # Ensure audit pipeline is configured
    E11y.config.pipeline.use E11y::Middleware::AuditSigning
    
    # Configure routing for audit events
    E11y.config.fallback_adapters = [:audit_encrypted]
  end
  
  after do
    FileUtils.rm_rf(storage_path) if Dir.exist?(storage_path)
    ENV.delete('E11Y_AUDIT_SIGNING_KEY')
  end
  
  describe "Scenario 1: Track actions" do
    # Test implementation
  end
  
  # ... other scenarios
end
```

### 2. Assertion Strategy

**Audit Event Tracking Assertions:**
- ✅ Event tracked: Encrypted file exists in storage
- ✅ Separate pipeline: Event bypasses PII filtering (original data preserved)
- ✅ Signing: `audit_signature` field present and valid
- ✅ Encryption: Encrypted data written to storage

**Encryption Assertions:**
- ✅ Encryption works: Event encrypted with AES-256-GCM
- ✅ Decryption works: Encrypted event can be decrypted
- ✅ Data integrity: Decrypted data matches original
- ✅ Authentication tag: Tag validates encryption integrity
- ✅ Per-event nonce: Each event has unique nonce

**Tamper Detection Assertions:**
- ✅ Valid signature: Original event signature valid
- ✅ Tamper detected: Modified event signature invalid
- ✅ Error handling: Tamper detection raises error or returns false

**Compliance Assertions:**
- ✅ Immutability: Events cannot be modified after creation
- ✅ Retention: Events stored for required period
- ✅ Signing: All events signed (non-repudiation)
- ✅ Encryption: Sensitive data encrypted (confidentiality)

---

## 📊 7 Core Integration Test Scenarios

### Scenario 1: Track Actions

**Objective:** Verify audit events are tracked correctly through separate audit pipeline.

**Setup:**
- Audit event class: `Events::UserDeleted` with `audit_event true`
- AuditSigning middleware configured
- AuditEncrypted adapter configured

**Test Steps:**
1. Define audit event class:
   ```ruby
   class Events::UserDeleted < E11y::Event::Base
     audit_event true
     
     schema do
       required(:user_id).filled(:integer)
       required(:deleted_by).filled(:integer)
       required(:ip_address).filled(:string)
     end
   end
   ```
2. Track audit event: `Events::UserDeleted.track(user_id: 123, deleted_by: 456, ip_address: "192.168.1.1")`
3. Verify separate pipeline: Event bypasses PII filtering (IP address preserved)
4. Verify signing: Event signed with HMAC-SHA256 (`audit_signature` present)
5. Verify encryption: Event encrypted with AES-256-GCM (encrypted file in storage)
6. Verify storage: Encrypted event written to storage

**Assertions:**
- Event tracked: Encrypted file exists in storage directory
- Original data preserved: `expect(decrypted_event[:payload][:ip_address]).to eq("192.168.1.1")`
- Signature present: `expect(decrypted_event[:audit_signature]).to be_present`
- Encryption present: Encrypted data written to file

**Test Data:**
- Event: `Events::UserDeleted`
- Payload: `{ user_id: 123, deleted_by: 456, ip_address: "192.168.1.1" }`
- Expected: Encrypted file in storage, signature present, IP preserved

---

### Scenario 2: Query Logs

**Objective:** Verify audit logs can be queried (using adapter.read() or query API if implemented).

**Setup:**
- Multiple audit events stored
- Query API (if implemented) or adapter.read() method

**Test Steps:**
1. Track multiple audit events:
   - `Events::UserDeleted.track(user_id: 123, ...)`
   - `Events::UserDeleted.track(user_id: 456, ...)`
   - `Events::PermissionChanged.track(user_id: 789, ...)`
2. Query events: Use `adapter.read(event_id)` for single event or query API (if exists)
3. Verify results: Events returned correctly
4. Verify signature validation: Signatures verified during query

**Assertions:**
- Events queryable: Can retrieve events from storage
- Signature validation: `expect(AuditSigning.verify_signature(event)).to be(true)`
- Filtering works: Can filter by event name, timestamp (if query API exists)

**Test Data:**
- Events: 3 audit events (UserDeleted x2, PermissionChanged x1)
- Query: By event_id or event_name (if query API exists)
- Expected: Events returned with valid signatures

**Note:** Per AUDIT-002 F-008, query API may not be implemented. Tests should verify `adapter.read(event_id)` works for single event retrieval.

---

### Scenario 3: Export

**Objective:** Verify audit logs can be exported (if export API implemented).

**Setup:**
- Multiple audit events stored
- Export API (if implemented)

**Test Steps:**
1. Track multiple audit events
2. Export events: Use export API (if exists) or custom export logic
3. Verify export format: Events exported in correct format (JSON, CSV, etc.)
4. Verify signature validation: Signatures included in export

**Assertions:**
- Export works: Events can be exported
- Format correct: Export format matches requirements
- Signatures included: Signatures present in export

**Test Data:**
- Events: 5 audit events
- Export format: JSON or CSV (if export API exists)
- Expected: Exported file with events and signatures

**Note:** Export API may not be implemented. Tests should verify basic export functionality if available, or note limitation.

---

### Scenario 4: Encryption

**Objective:** Verify AES-256-GCM encryption works correctly.

**Setup:**
- AuditEncrypted adapter configured with test key
- Test encryption/decryption

**Test Steps:**
1. Track audit event: `Events::UserDeleted.track(...)`
2. Read encrypted event from storage: Get encrypted file
3. Decrypt event: Use `adapter.decrypt_event(encrypted_data)`
4. Verify decryption: Decrypted data matches original
5. Verify authentication tag: Tag validates encryption integrity

**Assertions:**
- Encryption works: Event encrypted correctly (encrypted file exists)
- Decryption works: `expect(decrypted_event).to be_a(Hash)`
- Data integrity: `expect(decrypted_event[:payload]).to eq(original_payload)`
- Authentication tag: Tag validates encryption integrity (decryption succeeds)

**Test Data:**
- Original event: `{ event_name: "Events::UserDeleted", payload: { user_id: 123, deleted_by: 456, ip_address: "192.168.1.1" } }`
- Encrypted: Base64-encoded ciphertext with nonce and tag
- Decrypted: Should match original event

---

### Scenario 5: Tamper Detection

**Objective:** Verify signature verification detects tampering.

**Setup:**
- Audit event with signature
- Tampered event (modified payload)

**Test Steps:**
1. Track audit event: `Events::UserDeleted.track(user_id: 123, deleted_by: 456, ip_address: "192.168.1.1")`
2. Read encrypted event from storage
3. Decrypt event
4. Verify signature: `expect(AuditSigning.verify_signature(decrypted_event)).to be(true)`
5. Tamper event: Modify payload (e.g., change `user_id` from 123 to 999)
6. Verify tamper detection: `expect(AuditSigning.verify_signature(tampered_event)).to be(false)`

**Assertions:**
- Valid signature: Original event signature valid
- Tamper detected: Modified event signature invalid
- Error handling: Tamper detection returns false (or raises error)

**Test Data:**
- Original event: `{ user_id: 123, deleted_by: 456, ip_address: "192.168.1.1" }`
- Tampered event: `{ user_id: 999, deleted_by: 456, ip_address: "192.168.1.1" }` (user_id modified)
- Expected: Original signature valid, tampered signature invalid

---

### Scenario 6: Key Rotation

**Objective:** Verify key rotation works (if implemented, or verify key change handling).

**Setup:**
- Old encryption key
- New encryption key
- Events encrypted with old key

**Test Steps:**
1. Track audit events with old key: `Events::UserDeleted.track(...)`
2. Rotate key: Change encryption key in adapter configuration
3. Read old events: Verify old events can still be decrypted (if key rotation supported)
4. Track new events: Verify new events encrypted with new key

**Assertions:**
- Old events readable: Can decrypt events encrypted with old key (if rotation supported)
- New events encrypted: New events use new key
- Key management: Key rotation handled correctly

**Test Data:**
- Old key: `OpenSSL::Random.random_bytes(32)`
- New key: `OpenSSL::Random.random_bytes(32)`
- Events: 2 events with old key, 1 event with new key
- Expected: Old events decryptable (if rotation supported), new events use new key

**Note:** Per AUDIT-002, key rotation may NOT be implemented. Tests should verify basic key change handling if available, or note limitation.

---

### Scenario 7: Compliance

**Objective:** Verify audit trail meets compliance requirements (SOC2, HIPAA, GDPR).

**Setup:**
- Audit events with compliance metadata
- Retention period configuration

**Test Steps:**
1. Track compliance-critical events:
   - User deletion (GDPR): `Events::UserDeleted.track(...)`
   - Data access (HIPAA): `Events::DataAccessed.track(...)`
   - Permission change (SOC2): `Events::PermissionChanged.track(...)`
2. Verify immutability: Events cannot be modified after creation
3. Verify retention: Events stored for required period
4. Verify signing: All events cryptographically signed
5. Verify encryption: Sensitive data encrypted at rest

**Assertions:**
- Immutability: Events cannot be modified after creation (signature prevents tampering)
- Retention: Events stored for compliance period (file exists in storage)
- Signing: All events signed (`expect(event[:audit_signature]).to be_present`)
- Encryption: Sensitive data encrypted (`expect(encrypted_file).to exist`)

**Test Data:**
- User deletion: `{ user_id: 123, deleted_by: 456, ip_address: "192.168.1.1", compliance_basis: "gdpr_right_to_be_forgotten" }`
- Data access: `{ patient_id: 789, accessed_by: 456, access_type: "view", compliance_basis: "hipaa_access_log" }`
- Permission change: `{ user_id: 123, permission: "admin", action: "granted", granted_by: 456, compliance_basis: "soc2_access_control" }`

**Compliance Requirements:**
- **SOC2:** Immutable audit logs, cryptographic signing
- **HIPAA:** Access tracking, encryption at rest
- **GDPR:** Data deletion tracking, retention management

---

## 📝 Test Data Requirements

### 7.1. Audit Event Classes

**Required Event Classes:**
- `Events::UserDeleted` - User deletion audit event (GDPR compliance)
- `Events::PermissionChanged` - Permission change audit event (SOC2 compliance)
- `Events::DataAccessed` - Data access audit event (HIPAA compliance)

**Location:** `spec/dummy/app/events/events/`

### 7.2. Test Keys

**Required Keys:**
- Signing key: `ENV['E11Y_AUDIT_SIGNING_KEY']` (32-byte hex string)
- Encryption key: `ENV['E11Y_AUDIT_ENCRYPTION_KEY']` (32-byte hex string)

**Test Key Generation:**
```ruby
test_signing_key = SecureRandom.hex(32)  # 64-character hex string
test_encryption_key = OpenSSL::Random.random_bytes(32)  # 32-byte binary
```

### 7.3. Test Payloads (Sensitive User Actions)

**Required Payloads:**
- User deletion: `{ user_id: 123, deleted_by: 456, ip_address: "192.168.1.1", reason: "gdpr_request" }`
- Permission change: `{ user_id: 123, permission: "admin", action: "granted", granted_by: 456, reason: "promotion" }`
- Data access: `{ patient_id: 789, accessed_by: 456, access_type: "view", data_fields: ["name", "dob"] }`

### 7.4. Storage Configuration

**Required Storage:**
- Temporary directory: `Dir.mktmpdir("audit_test")` (cleaned up after tests)
- Storage path: Configured in test `before` blocks
- File naming: `{timestamp}_{event_name}.enc` format

---

## ✅ Definition of Done

**Planning is complete when:**
1. ✅ All 7 scenarios planned with detailed test steps
2. ✅ Test data requirements documented (sensitive user actions, test keys, payloads)
3. ✅ Assertion strategy defined for encryption and tamper detection
4. ✅ Test infrastructure requirements documented
5. ✅ Compliance requirements documented (SOC2, HIPAA, GDPR)
6. ✅ Test structure follows existing integration test patterns

---

## 📚 References

- **UC-012 Analysis:** `docs/analysis/UC-012-AUDIT-TRAIL-ANALYSIS.md`
- **UC-012 Use Case:** `docs/use_cases/UC-012-audit-trail.md`
- **Integration Tests:** `spec/integration/audit_trail_integration_spec.rb` ✅ (All 7 scenarios implemented)
- **ADR-006:** `docs/ADR-006-security-compliance.md` (Section 5: Audit Trail)
- **ADR-015:** `docs/ADR-015-middleware-order.md` (Section 3.3: C01 Audit Pipeline)
- **AUDIT-002:** `docs/researches/post_implementation/AUDIT-002-ADR-006-SOC2-Compliance.md`
- **AuditSigning Implementation:** `lib/e11y/middleware/audit_signing.rb`
- **AuditEncrypted Implementation:** `lib/e11y/adapters/audit_encrypted.rb`
- **Rate Limiting Tests:** `spec/integration/rate_limiting_integration_spec.rb` (reference pattern)
- **High Cardinality Tests:** `spec/integration/high_cardinality_protection_integration_spec.rb` (reference pattern)

---

**Planning Complete:** 2026-01-26  
**Next Step:** UC-012 Phase 3: Skeleton Complete
