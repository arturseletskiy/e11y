# ADR-015: Middleware Execution Order - Summary

**Document:** ADR-015  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** CRITICAL  
**Domain:** Core Architecture

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Architectural Decision |
| **Complexity** | Complex |
| **Dependencies** | ADR-001 (Architecture), ADR-006 (Security), ADR-012 (Event Evolution), ADR-013 (DLQ) |
| **Contradictions** | 3 identified |
| **Resolutions** | C01 (Audit Pipeline Separation), C19 (Middleware Zones) |

---

## 🎯 Decision Statement

**Decision:** E11y pipeline uses **definitive middleware order** (VersioningMiddleware MUST be LAST), **two pipeline configurations** (standard vs. audit - C01 resolution), and **middleware zones** with modification constraints (C19 resolution) to prevent PII bypass.

**Context:**
VersioningMiddleware normalizes event names (Events::OrderPaidV2 → Events::OrderPaid) for adapter convenience. BUT all business logic (validation, PII filtering, rate limiting, sampling) MUST use ORIGINAL class name because V2 may have different schema/PII rules/rate limits than V1.

**Consequences:**
- **Positive:** Correct business logic (V2 uses V2 schema/PII rules/rate limits), audit events preserve original data (cryptographic non-repudiation), PII bypass prevention (zone validation), boot-time validation (catches wrong order)
- **Negative:** Two pipelines to maintain (standard + audit), zone constraints reduce flexibility (custom middleware restricted), boot-time validation overhead (~1ms per event in dev/staging)

---

## 📝 Key Architectural Decisions

### Must Have (Critical)
- [x] **Definitive Middleware Order (7 middlewares):**
  1. TraceContext (add trace_id, span_id, timestamp)
  2. Validation (schema validation - uses ORIGINAL class)
  3. PIIFiltering (mask/hash PII - uses ORIGINAL class PII rules)
  4. RateLimiting (check limits - uses ORIGINAL class rate limits)
  5. Sampling (adaptive sampling - uses ORIGINAL class sample rates)
  6. Versioning (normalize event_name - LAST!)
  7. Routing (route to buffer - uses normalized name)
- [x] **VersioningMiddleware MUST Be LAST** (before Routing): All business logic (#2-5) uses ORIGINAL class name (Events::OrderPaidV2), only adapters receive normalized name (Events::OrderPaid)
- [x] **C01 Resolution: Two Pipeline Configurations:**
  - Standard Pipeline (most events): TraceContext → Validation → PIIFiltering → Rate → Sampling → Versioning → Routing
  - Audit Pipeline (audit_event: true): TraceContext → Validation → AuditSigning → Versioning → AuditRouting (NO PII filtering, NO rate limiting, NO sampling)
- [x] **C01 Audit Event Declaration:** `audit_event true` flag triggers audit pipeline, skips PII filtering, adds HMAC-SHA256 signature, routes to encrypted storage
- [x] **C01 Encrypted Storage Requirement:** Audit events MUST be stored encrypted (AES-256-GCM) because they contain original PII (not filtered)
- [x] **C19 Resolution: Middleware Zones (5 zones with modification rules):**
  - Zone 1: Pre-Processing (can add fields, can reject events)
  - Zone 2: Security (PII filtering - CRITICAL, no custom middleware allowed)
  - Zone 3: Routing (can drop events, read-only, cannot modify payload)
  - Zone 4: Post-Processing (can add non-PII metadata, cannot add PII)
  - Zone 5: Adapters (read-only, delivery only)
- [x] **C19 Zone Validation:** Boot-time checks (validate zone progression), runtime checks (prevent PII bypass in post-processing), warning system (dev/staging), fail-fast (production raises error)
- [x] **C19 Custom Middleware Constraints:** Can be added to pre-processing or post-processing zones only, CANNOT be added in security zone (PII filtering), MUST declare `middleware_zone` and `modifies_fields`

### Should Have (Important)
- [x] **Zone-Based Configuration:** Configure middlewares by zone (`config.pipeline.zone(:pre_processing)`)
- [x] **Custom Middleware Template:** Validate zone rules, validate no PII fields added in post-processing
- [x] **Warning System:** Development/staging warnings for zone violations, production fail-fast (raise error)
- [x] **Monitoring Metrics:** `zone_violations` counter, `pii_bypass_prevented` counter (Yabeda)

### Could Have (Nice to have)
- [ ] Automatic middleware reordering (rejected: too implicit, error-prone)
- [ ] Visual pipeline debugger (show current zone, field modifications)

---

## 🔗 Dependencies

### Related ADRs
- **ADR-001:** Architecture (pipeline architecture, middleware chain)
- **ADR-006:** Security & Compliance (PII filtering, audit trail, GDPR)
- **ADR-012:** Event Evolution & Versioning (why versioning is cosmetic normalization)
- **ADR-013:** Reliability & Error Handling (DLQ replay considerations)

### Related Use Cases
- **UC-001:** Request-Scoped Debug Buffering (middleware order warning)
- **UC-007:** PII Filtering (middleware order: PII BEFORE buffer routing)
- **UC-012:** Audit Trail (C01 resolution: audit pipeline separation)

### External Dependencies
- None (pure architectural decision)

---

## ⚡ Technical Constraints

### Performance
- **Zone validation overhead:** ~1ms per event (dev/staging only, disabled in production)
- **Audit signing overhead:** <1ms per audit event (HMAC-SHA256)
- **Encryption overhead:** AES-256-GCM for audit storage

### Scalability
- Two pipelines (standard + audit) maintained in parallel
- Zone validation at boot time (one-time overhead)

### Security
- **C01:** Audit events preserve original PII (not filtered) for non-repudiation
- **C01:** Encrypted storage MANDATORY (AES-256-GCM) for audit events with PII
- **C19:** Zone validation prevents PII bypass (custom middleware cannot run after PII filtering)

### Compatibility
- Rails >= 8.0.0 (ActiveSupport::CurrentAttributes for zone tracking)
- OpenSSL (HMAC-SHA256 for audit signing, AES-256-GCM for encryption)

---

## 🎭 Rationale & Alternatives

**Decision:** VersioningMiddleware LAST + Two Pipelines (standard/audit) + 5 Middleware Zones

**Rationale:**

**1. Versioning LAST:**
- Problem: If versioning normalizes early (Events::OrderPaidV2 → Events::OrderPaid), business logic uses wrong schema/PII rules/rate limits
- Solution: Versioning is cosmetic normalization for adapters only (easy querying), business logic uses original class name
- Benefit: V2 can have different schema, PII rules, rate limits than V1 (A/B testing, gradual rollout)

**2. Two Pipelines (C01):**
- Problem: PII filtering BEFORE signing breaks non-repudiation (signature is on filtered data, not original)
- Solution: Audit events use separate pipeline (skip PII filtering, add AuditSigning middleware, encrypted storage)
- Benefit: Non-repudiation for audit (signature on original PII data), GDPR compliance (encrypted at rest)

**3. Middleware Zones (C19):**
- Problem: Custom middleware can bypass PII filtering (add PII after filtering) or undo security modifications
- Solution: 5 zones with clear modification rules, boot-time validation, runtime checks (dev/staging)
- Benefit: Prevents PII bypass, forces correct patterns, clear boundaries

**Alternatives Rejected:**
1. **Versioning first** - Rejected: Breaks business logic (wrong schema, wrong PII rules, wrong rate limits)
2. **Single pipeline for audit** - Rejected: Cannot both filter PII (GDPR) and sign original data (non-repudiation)
3. **No zone constraints** - Rejected: Custom middleware can bypass security (PII leak risk)

**Trade-offs:**
- ✅ Correct business logic, non-repudiation for audit, PII bypass prevention
- ❌ Two pipelines complexity, zone constraints reduce flexibility, boot-time validation overhead (~1ms in dev/staging)

---

## ⚠️ Potential Contradictions

### Contradiction 1: Two Pipelines (Standard + Audit) Adds Maintenance Complexity
**Conflict:** Need separate pipelines (standard with PII filtering, audit without) BUT doubles maintenance burden (two pipeline configs to keep in sync)
**Impact:** Medium (maintenance overhead)
**Related to:** ADR-006 (Security & Compliance), UC-012 (Audit Trail)
**Notes:** Lines 281-305 show two pipeline configurations:
- Standard: 7 middlewares (includes PIIFiltering, RateLimiting, Sampling)
- Audit: 5 middlewares (NO PIIFiltering, NO RateLimiting, NO Sampling, but adds AuditSigning)

**Real Evidence:**
```
Lines 281-305: "Standard Events (Non-Audit):
1. TraceContext
2. Validation
3. PIIFiltering    ← LAST PII touchpoint
4. RateLimiting
5. Sampling
6. Versioning
7. Routing

Audit Events (Legal Compliance):
1. TraceContext
2. Validation
3. AuditSigning    ← Sign ORIGINAL data (includes PII!)
4. Versioning
5. Routing

❌ NO PII filtering for audit events!
❌ NO rate limiting for audit events!
❌ NO sampling for audit events!"
```

**Trade-off:** Two pipelines is necessary for C01 resolution (PII filtering vs. non-repudiation). But if middlewares are added/removed in standard pipeline, must remember to update audit pipeline too (or explicitly decide if audit should have new middleware).

**Risk:** Drift between pipelines over time (new middleware added to standard but forgotten in audit).

**Mitigation:** Document explicitly states "Do not change order without updating all ADRs!" (line 1058). But this is documentation-based, not code-enforced.

### Contradiction 2: Zone Validation Prevents PII Bypass BUT Adds Conceptual and Runtime Overhead
**Conflict:** Middleware zones (5 zones with modification rules) prevent PII bypass BUT add conceptual complexity (developers must understand zones) and runtime overhead (~1ms per event in dev/staging)
**Impact:** Medium (safety vs. complexity vs. performance)
**Related to:** ADR-001 (Architecture), ADR-006 (Security)
**Notes:** Lines 658-1043 describe C19 resolution (Middleware Zones). Five zones with clear modification rules:
- Zone 1 (Pre-Processing): can add fields, can reject events
- Zone 2 (Security): PII filtering ONLY, no custom middleware
- Zone 3 (Routing): can drop events, read-only, cannot modify payload
- Zone 4 (Post-Processing): can add non-PII metadata, cannot add PII
- Zone 5 (Adapters): read-only, delivery only

**Real Evidence:**
```
Lines 997-1002: "Trade-offs:
| Aspect | Pro | Con | Mitigation |
| Safety | ✅ Prevents PII bypass | ⚠️ More restrictive API | Clear documentation |
| Flexibility | ⚠️ Less freedom for custom middleware | ✅ Forces correct patterns | Two zones: pre/post processing |
| Validation | ✅ Runtime checks catch violations | ⚠️ Adds overhead (~1ms per event) | Only in dev/staging |
| Complexity | ⚠️ Zones add conceptual overhead | ✅ Clear boundaries | Visual zone diagrams |"
```

**Trade-off:** Zone validation is ONLY in dev/staging (lines 915-940), disabled in production (no runtime overhead). Boot-time validation at Rails initialization (lines 906-908) catches most errors.

**Justification:** ~1ms overhead in dev/staging is acceptable for preventing PII bypass (GDPR violations in production).

### Contradiction 3: Audit Events Skip PII Filtering (Original Data for Signature) BUT Require Encrypted Storage (Complexity)
**Conflict:** Audit events preserve original PII (no filtering) for non-repudiation BUT require encrypted storage (AES-256-GCM) which adds implementation complexity
**Impact:** Medium (security vs. implementation complexity)
**Related to:** ADR-006 (Security), UC-012 (Audit Trail)
**Notes:** Lines 458-529 describe encrypted audit adapter implementation:
- AES-256-GCM encryption for all audit events
- Encrypted payload includes IV, auth_tag, encrypted data
- Signature verification before encryption
- Access control, key rotation requirements (lines 614-650)

**Real Evidence:**
```
Lines 460-464: "Why Encryption is Mandatory:
- Audit events contain PII (not filtered)
- Signature is on original data (including PII)
- Storage must protect PII at rest (GDPR compliance)"

Lines 614-650: Security requirements:
- Encrypted storage (mandatory)
- Access control (MFA, RBAC)
- Key rotation (quarterly)
```

**Trade-off:** Encrypted storage adds complexity (key management, AES-256-GCM implementation, access control) BUT necessary for GDPR compliance (audit events contain original PII).

**Justification:** Audit events are rare (<1% of total events - line 612), so encryption overhead is acceptable. Non-repudiation requirement (legal compliance) outweighs implementation complexity.

---

## 🔍 Implementation Notes

### Key Components
- **E11y::Pipeline** - Two pipeline configurations (standard, audit)
- **E11y::Middleware::Versioning** - Normalize event_name (LAST middleware before routing)
- **E11y::Middleware::AuditSigning** - HMAC-SHA256 signature on original data (audit pipeline only)
- **E11y::Middleware::AuditRouting** - Route audit events to encrypted storage
- **E11y::Adapters::AuditEncryptedAdapter** - AES-256-GCM encryption, signature verification
- **E11y::Pipeline::ZoneValidator** - Boot-time validation (zone progression check)
- **E11y::Pipeline::ZoneWarningSystem** - Runtime warnings (dev/staging), fail-fast (production)

### Configuration Required

**Standard Pipeline:**
```ruby
E11y.configure do |config|
  config.middleware.use E11y::Middleware::TraceContext      # 1
  config.middleware.use E11y::Middleware::Validation        # 2
  config.middleware.use E11y::Middleware::PIIFiltering      # 3
  config.middleware.use E11y::Middleware::RateLimiting      # 4
  config.middleware.use E11y::Middleware::Sampling          # 5
  config.middleware.use E11y::Middleware::Versioning        # 6 ← LAST!
  config.middleware.use E11y::Middleware::Routing           # 7
end
```

**Audit Pipeline (C01):**
```ruby
E11y.configure do |config|
  # Audit pipeline override
  config.audit_pipeline.use E11y::Middleware::TraceContext      # 1
  config.audit_pipeline.use E11y::Middleware::Validation        # 2
  config.audit_pipeline.use E11y::Middleware::AuditSigning      # 3 (NEW!)
  config.audit_pipeline.use E11y::Middleware::Versioning        # 4
  config.audit_pipeline.use E11y::Middleware::AuditRouting      # 5
  
  # Audit event configuration
  config.audit_events do
    enabled true
    
    # Signing (HMAC-SHA256)
    signing do
      algorithm :hmac_sha256
      secret_key ENV['E11Y_AUDIT_SECRET_KEY']
      include_fields :all  # Sign all fields (including PII)
    end
    
    # Storage (encrypted)
    storage do
      encrypted true  # MANDATORY
      adapter :audit_encrypted
    end
  end
end
```

**Middleware Zones (C19):**
```ruby
E11y.configure do |config|
  # Zone-based configuration
  config.pipeline.zone(:pre_processing) do
    use E11y::Middleware::TraceContext
    use E11y::Middleware::Validation
  end
  
  config.pipeline.zone(:security) do
    use E11y::Middleware::PIIFiltering  # ← NO custom middleware here!
  end
  
  config.pipeline.zone(:routing) do
    use E11y::Middleware::RateLimiting
    use E11y::Middleware::Sampling
  end
  
  config.pipeline.zone(:post_processing) do
    use E11y::Middleware::Versioning
  end
  
  config.pipeline.zone(:adapters) do
    use E11y::Middleware::Routing
  end
  
  # Enable zone warnings (dev/staging)
  config.pipeline.enable_zone_warnings = true if Rails.env.development?
end
```

### APIs / Interfaces
- `audit_event(boolean)` - Event class flag (triggers audit pipeline)
- `middleware_zone(symbol)` - Custom middleware zone declaration (`:pre_processing`, `:post_processing`)
- `modifies_fields(*fields)` - Custom middleware field modification declaration
- `E11y::Pipeline.validate_zones!` - Boot-time zone validation
- `E11y::Middleware::AuditSigning#call(event_data)` - Sign with HMAC-SHA256
- `E11y::Adapters::AuditEncryptedAdapter#write_batch(events)` - Encrypt and store

### Data Structures
- **Audit Signature:** `{ value: String (hex), algorithm: String, timestamp: Time, key_id: String, payload_hash: String (SHA256) }`
- **Zone Metadata:** `{ zone: Symbol, middleware_class: Class, allowed_modifications: Array<Symbol> }`

---

## ❓ Questions & Gaps

### Clarification Needed
1. **ADR-001 vs. ADR-006 inconsistency:** ADR-015 shows PIIFiltering as global middleware #3, ADR-006 says "PII filtering is NOT a global middleware". Clarification: Standard events use global PIIFiltering middleware, audit events skip it (C01). But ADR-006's phrasing is misleading?
2. **Audit pipeline maintenance:** If new middleware added to standard pipeline, is there a checklist/validation to update audit pipeline too?
3. **Zone validation in production:** Lines 997 show "~1ms overhead" for zone validation. Is this dev/staging only, or also production?

### Missing Information
1. **Custom middleware in routing zone:** Can custom middleware be added to routing zone (drop events), or only pre-processing/post-processing?
2. **Zone transition rules:** Lines 890-900 show zone_order validation. Can zones be repeated (e.g., pre_processing → security → pre_processing again)?
3. **Audit event volume:** Line 612 mentions "audit events are rare (<1%)" - is this assumption validated? What if audit events are 10% of volume?

### Ambiguities
1. **"Versioning LAST (before routing)"** - Is routing considered part of middleware chain, or separate? Line numbering shows Versioning #6, Routing #7, so routing IS part of chain.
2. **"No custom middleware in security zone"** (line 1014) - Is this enforced at boot time, or just documentation?

---

## 🧪 Testing Considerations

### Test Scenarios
1. **Wrong order:** Add VersioningMiddleware first, verify validation error (can't find V2 schema)
2. **Two pipelines:** Track standard event, verify PIIFiltering applied. Track audit event, verify PIIFiltering skipped, AuditSigning applied
3. **C01 audit signing:** Track audit event with PII (email), verify signature on original data (not filtered)
4. **C01 encrypted storage:** Track audit event, verify stored encrypted (AES-256-GCM), verify signature verification before encryption
5. **C19 zone validation:** Add custom middleware in security zone, verify boot error (zone violation)
6. **C19 PII bypass prevention:** Custom middleware in post-processing adds email field, verify runtime warning (dev) or error (prod)
7. **Middleware order:** Track Events::OrderPaidV2, verify business logic uses V2 schema/PII rules/rate limits (not V1)

### Mocking Needs
- `OpenSSL::HMAC` - Spy on signature generation (verify HMAC-SHA256 called with correct payload)
- `OpenSSL::Cipher` - Mock encryption/decryption for audit adapter
- `Rails.logger` - Capture zone violation warnings

---

## 📊 Complexity Assessment

**Overall Complexity:** Complex

**Reasoning:**
- Definitive middleware order requires understanding of why order matters (V2 vs. V1 schema/PII rules/rate limits)
- Two pipeline configurations (standard + audit) adds maintenance overhead (must keep in sync)
- C01 resolution (audit pipeline separation) requires understanding of non-repudiation vs. GDPR PII filtering paradox
- C19 resolution (middleware zones) adds conceptual overhead (5 zones with different modification rules)
- Zone validation at boot time and runtime (dev/staging) requires understanding of zone progression rules
- Encrypted audit storage (AES-256-GCM) adds key management, encryption/decryption, access control complexity
- Custom middleware must declare zone and validate no PII bypass (developer discipline required)

**Estimated Implementation Time:**
- Junior dev: 15-20 days (two pipelines, zone validation, audit signing, encrypted storage, testing)
- Senior dev: 10-12 days (familiar with cryptography, pipeline patterns, GDPR requirements)

---

## 📚 References

### Related Documentation
- [ADR-001: Architecture](./ADR-001-architecture.md) - Pipeline architecture, middleware chain
- [ADR-006: Security & Compliance](./ADR-006-security-compliance.md) - PII filtering, GDPR, audit trail
- [ADR-012: Event Evolution](./ADR-012-event-evolution.md) - Versioning design (why versioning is cosmetic)
- [ADR-013: Reliability & Error Handling](./ADR-013-reliability-error-handling.md) - DLQ replay
- [UC-001: Request-Scoped Debug Buffering](../use_cases/UC-001-request-scoped-debug-buffering.md) - Middleware order warning
- [UC-007: PII Filtering](../use_cases/UC-007-pii-filtering.md) - PII BEFORE buffer routing
- [UC-012: Audit Trail](../use_cases/UC-012-audit-trail.md) - Audit event use cases
- [CONFLICT-ANALYSIS.md](../researches/CONFLICT-ANALYSIS.md) - C01 (Audit + PII), C19 (Custom Middleware)

### Research Notes
- **C01 Resolution (lines 252-655):**
  - Problem: PII filtering before signing breaks non-repudiation
  - Solution: Two pipelines (audit skips PII filtering, signs original data, encrypted storage)
  - Trade-off: Maintenance complexity (two pipelines) vs. legal compliance (non-repudiation)
- **C19 Resolution (lines 658-1043):**
  - Problem: Custom middleware can bypass PII filtering (add PII after filtering)
  - Solution: 5 zones with modification constraints, boot-time validation, runtime checks
  - Trade-off: Safety (prevents PII bypass) vs. flexibility (restricts custom middleware)
- **Definitive order (lines 72-81):**
  - VersioningMiddleware MUST be LAST (before routing)
  - All business logic (#2-5) uses ORIGINAL class name
  - Only adapters receive normalized name

---

## 🏷️ Tags

`#critical` `#middleware-order` `#versioning-last` `#two-pipelines` `#c01-audit-pipeline` `#c19-middleware-zones` `#pii-bypass-prevention` `#audit-signing` `#encrypted-storage`

---

**Last Updated:** 2026-01-15  
**Next Review:** Before implementation (Phase 3 - Consolidated Analysis)  
**Status:** ✅ Stable - **DO NOT change order without updating all ADRs!**
