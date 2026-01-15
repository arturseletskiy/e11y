# ADR-006: Security & Compliance - Summary

**Document:** ADR-006  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Critical  
**Domain:** Security & Compliance

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Architectural Decision |
| **Complexity** | Very Complex |
| **Dependencies** | ADR-001, ADR-004, ADR-007 (OTel Baggage C08), UC-007, UC-011, UC-012 |
| **Contradictions** | 4 identified |

---

## 🎯 Decision Statement

**Decision:** E11y implements **3-tier PII filtering strategy** (explicit opt-in, per-adapter rules), **multi-level rate limiting** (global, per-event, per-context), and **cryptographically-signed audit trail** (HMAC-SHA256, immutable chain).

**Context:**
Production applications must comply with GDPR/HIPAA/SOX while maintaining performance (<0.2ms PII filtering). Traditional approaches (filter all events) cause massive CPU waste (20% vs. 4% with 3-tier). No audit trail or rate limiting leads to compliance violations and system abuse.

**Consequences:**
- **Positive:** GDPR-ready, 4% CPU overhead (vs. 20% filter-all), >99% rate limit accuracy, cryptographic audit trail
- **Negative:** Configuration complexity (3 tiers, per-adapter rules, rate limit levels), linter dependency, per-adapter filtering overhead (4 filter passes for 4 adapters)

---

## 📝 Key Architectural Decisions

### Must Have (Critical)
- [x] **3-Tier PII Filtering:** Tier 1 (skip, 0ms), Tier 2 (Rails filters, ~0.05ms), Tier 3 (deep, ~0.2ms)
- [x] **Explicit PII Declaration:** `contains_pii` flag enables linter validation
- [x] **Per-Field Strategies:** `:mask`, `:hash`, `:allow`, `:partial`
- [x] **Per-Adapter PII Rules:** audit_file (skip), elasticsearch (hash), sentry (mask), loki (mask)
- [x] **PII Declaration Linter:** Boot-time validation (dev/test), CI validation
- [x] **Rails-Style DSL:** `masks`, `hashes`, `allows`, `partials` shortcuts
- [x] **Multi-Level Rate Limiting:** Global (10k/sec), per-event (100-1000/sec), per-context (100/min)
- [x] **Rate Strategies:** `:sliding_window` (>99% accurate), `:token_bucket`, `:fixed_window`
- [x] **Redis Integration:** Distributed rate limiting, fallback to in-memory
- [x] **Audit Trail:** HMAC-SHA256 signature, immutable chain, tamper detection
- [x] **Performance Budget:** PII <0.2ms, Rate <0.05ms, Audit <1ms

### Should Have (Important)
- [x] Pattern-based PII filtering (emails, credit cards, SSNs, phones, IPs)
- [x] Deep scanning (nested hashes/arrays, max depth: 10)
- [x] PII sampling for debug (log 1% of filtered values)
- [x] Rate overflow actions (`:drop`, `:sample`, `:queue`)
- [x] Per-context allowlist (whitelist admin, system users)
- [x] Audit chain verification (detect tampering)

### Could Have (Nice to have)
- [ ] ML-based PII detection (rejected: too slow)
- [ ] PKI signatures (rejected: overkill, HMAC sufficient)

---

## 🔗 Dependencies

### Related Use Cases
- **UC-007:** PII Filtering (complete implementation details)
- **UC-011:** Rate Limiting (strategies and configuration)
- **UC-012:** Audit Trail (signing and immutability)

### Related ADRs
- **ADR-001:** Core Architecture (middleware chain, pipeline order)
- **ADR-004:** Adapter Architecture (per-adapter filtering)
- **ADR-007:** OpenTelemetry Integration (C08 baggage PII leak)

### External Dependencies
- Rails >= 8.0.0 (required, Rails.filter_parameters)
- OpenSSL (required, HMAC-SHA256)
- Redis >= 5.0 (optional, distributed rate limiting)

---

## ⚡ Technical Constraints

### Performance Targets
| Metric | Target | Critical? |
|--------|--------|-----------|
| **PII filtering** | <0.2ms/event | ✅ Yes |
| **Rate limit** | >99% accuracy | ✅ Yes |
| **Audit signing** | <1ms/event | ✅ Yes |
| **False positive PII** | <5% | ⚠️ Important |

### PII Filtering Budget
```
Tier 1: 500 events/sec × 0ms     = 0ms CPU
Tier 2: 400 events/sec × 0.05ms  = 20ms CPU
Tier 3: 100 events/sec × 0.2ms   = 20ms CPU
Total: 40ms CPU/sec = 4% CPU ✅
```

### Rate Limiting
- Global: 10,000 events/sec (system-wide)
- Per-event: 100-1000/sec (varies by type)
- Per-context: 100/min per user_id/session/IP
- Sliding window: >99% accuracy

### Audit Trail
- HMAC-SHA256 (<1ms signature time)
- Immutable chain (prev_signature linking)
- Append-only storage (no updates/deletes)

---

## 🎭 Rationale & Alternatives

**Decision:** 3-tier PII + multi-level rate limiting + HMAC audit trail

**Rationale:**
1. **PII Filtering:** 3-tier strategy = 4% CPU vs. 20% with filter-all
2. **Rate Limiting:** Multi-level prevents abuse (global + per-event + per-context)
3. **Audit Trail:** HMAC sufficient (vs. PKI overkill)

**Alternatives Rejected:**
1. No PII filtering → GDPR violations
2. ML-based PII → Too slow (>1ms)
3. Token bucket only → Need sliding window (>99% accuracy)
4. PKI signatures → Overkill, HMAC sufficient

**Trade-offs:**
- ✅ GDPR-ready, 4% CPU, >99% accuracy, cryptographic trail
- ❌ Config complexity, linter dependency, per-adapter overhead, immutability vs. GDPR erasure

---

## ⚠️ Potential Contradictions

### Contradiction 1: Global PII Middleware (ADR-001) vs. Per-Adapter Filtering (ADR-006)
**Conflict:** ADR-001 shows PiiFilterMiddleware as global middleware #3, BUT ADR-006 says "PII filtering is NOT a global middleware — it's applied INSIDE each adapter"
**Impact:** CRITICAL (architecture inconsistency)
**Related to:** ADR-001, UC-007, ADR-015
**Real Evidence:** ADR-006 semantic search lines 631-642 show per-adapter filtering (inside adapters), but ADR-001 shows global middleware.
**Hypothesis:** ADR-006 updated pipeline order, ADR-001 not updated yet. Need clarification.

### Contradiction 2: Audit Immutability vs. GDPR Right to Be Forgotten
**Conflict:** Audit chain is immutable (HMAC signature chain) BUT GDPR requires data deletion
**Impact:** High (compliance paradox)
**Related to:** UC-012, UC-007
**Solutions:** Pseudonymization, retention limits, legal obligation exception (GDPR Art. 6(1)(c))
**Clarification Needed:** Which solution recommended?

### Contradiction 3: Per-Adapter Filtering Overhead (4 Filter Passes for 4 Adapters)
**Conflict:** Per-adapter rules provide flexibility BUT filter same event 4 times (0.15ms vs. 0.05ms global)
**Impact:** Medium (3x overhead)
**Related to:** ADR-004, UC-007
**Trade-off:** 3x overhead acceptable for compliance (audit needs original PII)

### Contradiction 4: OTel Baggage PII Leak (C08) vs. Flexibility
**Conflict:** Need baggage allowlist (prevent PII leaks) BUT reduces flexibility (must explicitly allow every baggage key) and adds overhead (~0.01ms)
**Impact:** Medium (security vs. flexibility vs. performance)
**Related to:** ADR-007 (OTel), UC-008
**Trade-off:** Security > flexibility. GDPR compliance requires preventing PII leaks. 0.01ms overhead acceptable.

---

## 🔍 Implementation Notes

### Key Components
- E11y::Security::PiiFilter (3-tier engine)
- E11y::Security::RailsFilterAdapter (Rails.filter_parameters integration)
- E11y::Linters::PiiDeclarationLinter (boot-time validation)
- E11y::RateLimiting::GlobalLimiter (10k/sec system-wide)
- E11y::RateLimiting::PerEventLimiter (event-specific limits)
- E11y::RateLimiting::PerContextLimiter (user-specific limits)
- E11y::RateLimiting::RedisCounter (distributed state)
- E11y::Audit::Signer (HMAC-SHA256)
- E11y::Audit::ChainVerifier (tamper detection)

### Configuration Required
See "Key Architectural Decisions" section for detailed config examples (PII filtering, rate limiting, audit trail).

---

## ❓ Questions & Gaps

### Clarification Needed
1. Pipeline order: Global PII middleware (ADR-001) vs. per-adapter filtering (ADR-006)?
2. Audit + GDPR erasure: Which solution (pseudonymization, retention, legal exception)?
3. Per-adapter filtering: Event cloned 4 times or filtered in-place?

### Missing Information
1. Linter in production: Does it prevent app boot if error found?
2. Redis failure: Fallback to in-memory or disable rate limiting?
3. Audit key rotation: How to preserve chain with rotated keys?

---

## 🧪 Testing Considerations

### Test Scenarios
1. 3-Tier filtering: Verify overhead (0ms, 0.05ms, 0.2ms)
2. Per-adapter filtering: Same event to 4 adapters, verify different PII treatment
3. Linter: Missing field in `pii_filtering`, verify boot error
4. Global rate: 11k events/sec (limit: 10k), verify 1k dropped
5. Per-event rate: 1.5k order.paid/sec (limit: 1k), verify 500 dropped
6. Per-context rate: 150 events from user_id (limit: 100/min), verify 50 dropped
7. Audit chain: 3 events, verify event2.prev_signature == event1.signature
8. Tamper detection: Modify event1.payload, verify chain verification fails

---

## 📊 Complexity Assessment

**Overall Complexity:** Very Complex

**Reasoning:**
- 3-tier PII strategy (conditional logic, tier selection)
- Per-adapter filtering (4 filter passes, different rules)
- Explicit declaration + linter (developer discipline, CI integration)
- Multi-level rate limiting (global + per-event + per-context)
- Redis distributed state (operational complexity)
- Sliding window algorithm (more complex than token bucket)
- HMAC signature chain (cryptography, chain verification)
- Audit immutability vs. GDPR erasure (compliance paradox)

**Estimated Implementation Time:**
- Junior dev: 30-40 days
- Senior dev: 20-25 days

---

## 📚 References

### Related Documentation
- [UC-007: PII Filtering](../use_cases/UC-007-pii-filtering.md)
- [UC-011: Rate Limiting](../use_cases/UC-011-rate-limiting.md)
- [UC-012: Audit Trail](../use_cases/UC-012-audit-trail.md)
- [ADR-001: Core Architecture](./ADR-001-architecture.md)
- [ADR-004: Adapter Architecture](./ADR-004-adapter-architecture.md)
- [ADR-007: OpenTelemetry Integration](./ADR-007-opentelemetry-integration.md) - C08 baggage PII leak

### Research Notes
- **Performance:** 4% CPU (3-tier) vs. 20% CPU (filter-all)
- **Accuracy:** >99% (sliding window) vs. ~95% (token bucket)
- **Security:** HMAC-SHA256 (tamper detection, not non-repudiation)

---

## 🏷️ Tags

`#critical` `#security` `#compliance` `#gdpr` `#3-tier-pii` `#rate-limiting` `#audit-trail` `#hmac-signature` `#per-adapter-rules`

---

**Last Updated:** 2026-01-15  
**Next Review:** Before implementation (Phase 3 - Consolidated Analysis)
