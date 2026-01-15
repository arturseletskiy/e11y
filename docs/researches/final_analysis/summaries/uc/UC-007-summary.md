# UC-007: PII Filtering (Rails-Compatible) - Summary

**Document:** UC-007  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Critical  
**Domain:** Security

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Use Case |
| **Complexity** | Complex |
| **Dependencies** | ADR-006 (Critical - 4 sections), UC-001, UC-002, UC-005, UC-008, UC-012 |
| **Contradictions** | 4 identified |

---

## 🎯 Purpose & Problem Statement

**What problem does this solve?**
Eliminates configuration duplication between Rails `filter_parameters` and E11y PII filtering, preventing inconsistencies and reducing maintenance burden while ensuring GDPR compliance.

**Who is affected?**
All developers, Security teams, Compliance teams

**Expected outcome:**
Zero-config PII filtering (Rails compatibility), explicit PII declaration at event level, compile-time validation via linter, per-adapter filtering rules for compliance requirements.

---

## 📝 Key Requirements

### Must Have (Critical)
- [x] Rails-compatible PII filtering: automatically use `Rails.filter_parameters` (zero config)
- [x] Three-tier filtering strategy: Tier 1 (skip), Tier 2 (Rails filters), Tier 3 (deep filtering)
- [x] Explicit PII declaration: `contains_pii` flag at event class level
- [x] Per-field filtering strategies: `:mask`, `:hash`, `:allow`, `:partial`
- [x] Linter enforcement: validate PII declarations at boot time and CI
- [x] Per-adapter filtering rules: different PII treatment for audit vs. observability
- [x] Deep scanning: recursive filtering of nested hashes and arrays (max depth: 10)
- [x] Pattern-based filtering: regex patterns for content scanning (emails, credit cards, SSNs, phones, IPs)
- [x] DSL shortcuts: Rails-style concise syntax (`masks`, `hashes`, `allows`, `partials`)

### Should Have (Important)
- [x] Custom filter functions: full control for complex scenarios
- [x] Whitelisting: `allow_parameters` for IDs (non-PII)
- [x] Partial masking: `keep_partial_data` for debugging (e.g., `em***@ex***`)
- [x] Sampling for debugging: log 1% of filtered values for verification
- [x] Audit report: generate PII declaration report for all events
- [x] RSpec matchers: `have_complete_pii_declaration` for unit tests

### Could Have (Nice to have)
- [ ] Conditional filtering: environment-based rules (e.g., only production)
- [ ] Custom hash algorithms: configurable beyond SHA256
- [ ] Auto-detection: suggest PII fields based on patterns

---

## 🔗 Dependencies

### Related Use Cases
- **UC-001: Request-Scoped Debug Buffering** - PII filtering MUST happen BEFORE buffer routing (middleware order)
- **UC-002: Business Event Tracking** - Event definitions use PII filtering
- **UC-005: Sentry Integration** - Strict PII masking for external service
- **UC-008: OpenTelemetry Integration** - Pseudonymization for OTel semantic conventions
- **UC-012: Audit Trail** - Skip PII filtering (GDPR Art. 6(1)(c) legal obligation)

### Related ADRs
- **ADR-006 Section 3.0:** PII Filtering Strategy (3-tier architecture) - CRITICAL
- **ADR-006 Section 3.0.3:** Explicit PII Declaration (`contains_pii`) - CRITICAL
- **ADR-006 Section 3.4.4:** Configuration API (Rails-Style DSL shortcuts) - CRITICAL
- **ADR-006 Section 3.0.5:** PII Declaration Linter (boot-time validation) - CRITICAL

### External Dependencies
- Rails `filter_parameters` (single source of truth)
- Yabeda (self-monitoring metrics: fields filtered, patterns matched, duration)
- RSpec (for test matchers)

---

## ⚡ Technical Constraints

### Performance
- **Tier 1 (No PII):** 0ms overhead (10,000 events/sec)
- **Tier 2 (Rails filters):** ~0.05ms overhead (8,000 events/sec)
- **Tier 3 (Deep filtering):** ~0.2ms overhead (5,000 events/sec)
- **Performance budget:** 40ms CPU/sec = 4% CPU on single core (1000 events/sec mixed)

### Scalability
- Deep scanning max depth: 10 levels (prevent infinite recursion)
- Pattern compilation: compile regex once (cache_compiled_patterns: true)
- Per-request overhead: negligible (<1% CPU impact at 1000 events/sec)

### Security
- **CRITICAL:** PII filtering MUST happen BEFORE buffer routing (see UC-001 contradiction)
- **GDPR compliance:** Data minimization, purpose limitation, integrity & confidentiality
- **Audit trail exception:** Skip filtering for audit_file adapter (GDPR Art. 6(1)(c))
- **Per-adapter rules:** Different PII treatment based on adapter purpose (audit vs. observability vs. external)

### Compatibility
- Ruby/Rails (requires `Rails.filter_parameters`)
- Rails-compatible syntax (filter_parameters + regex patterns)
- Adapter-agnostic (per-adapter overrides supported)

---

## 🎭 User Story

**As a** Developer/Security Engineer  
**I want** PII filtering configured once in Rails and automatically applied to E11y events  
**So that** I don't duplicate configuration, avoid inconsistencies, and ensure GDPR compliance without manual work

**Rationale:**
Traditional approaches force developers to configure PII filtering in multiple places (Rails, logging, observability). This creates:
- Duplication (easy to forget updating both places)
- Inconsistency risk (Rails filters X but E11y doesn't)
- Maintenance burden (2x configuration to maintain)

E11y solves this by automatically using `Rails.filter_parameters` while adding:
- Per-adapter rules (audit needs full PII, observability needs filtered)
- Explicit declaration (`contains_pii`) for performance optimization
- Linter validation (catch missing declarations at compile time)

**Alternatives considered:**
1. **Separate E11y config** - Rejected: duplication, inconsistency risk
2. **No filtering** - Rejected: GDPR violation, security risk
3. **Runtime-only filtering** - Rejected: can't catch errors at compile time

**Trade-offs:**
- ✅ **Pros:** Zero-config Rails compatibility, explicit opt-in (performance), compile-time validation, per-adapter flexibility
- ❌ **Cons:** Requires Rails, explicit declaration adds boilerplate for Tier 3 events, linter only runs in dev/test (not production runtime)

---

## ⚠️ Potential Contradictions

### Contradiction 1: Audit Trail Needs Full PII vs. Observability Needs Filtered PII
**Conflict:** Audit trail MUST preserve original PII (GDPR Art. 6(1)(c) legal obligation) BUT observability adapters MUST filter PII (GDPR data minimization)
**Impact:** High (compliance vs. privacy)
**Related to:** ADR-006 (Security & Compliance), UC-012 (Audit Trail), UC-005 (Sentry), UC-008 (OTel)
**Notes:** Document provides per-adapter filtering rules to solve this (lines 2086-2250). Same event sent to multiple adapters with different PII treatment:
- `audit_file` → original PII (skip_filtering: true)
- `elasticsearch` → pseudonymized (hashed for searchability)
- `loki` → masked
- `sentry` → masked (external service)

**Real Evidence:**
```ruby
Lines 2121-2128: "adapter :audit_file do
  skip_filtering true
  # Reason: Legal requirement to keep original data
  # Justification: GDPR Art. 6(1)(c) - 'legal obligation'"

Lines 2152-2157: "adapter :sentry do
  mask_fields :email, :ip_address, :phone, :ssn, :user_id
  # Reason: Sentry is 3rd party, minimize data sharing"
```

**Solution:** Per-adapter filtering rules (global config or per-event overrides). However, this significantly increases configuration complexity (trade-off #1).

### Contradiction 2: Explicit Declaration (contains_pii) is MANDATORY for Tier 3 BUT Defaults to Tier 2 if Omitted
**Conflict:** Need explicit PII declaration for safety (linter validation) BUT default behavior is implicit (Tier 2 Rails filters)
**Impact:** Medium (risk of implicit filtering)
**Related to:** ADR-006 (PII Filtering Strategy)
**Notes:** Document states (lines 752-771): If `contains_pii` is not specified, E11y defaults to Tier 2 (Rails filters only). No linter validation. "Recommended for: Standard business events where Rails filters provide sufficient coverage (90% of use cases)."

**Real Evidence:**
```
Lines 752-771: "If contains_pii is not specified, E11y defaults to Tier 2 (Rails filters only):
- Keys like :password, :token, :api_key filtered
- No linter validation
Recommended for: Standard business events (90% of use cases)"

But lines 496-509: "Event classes MUST explicitly declare whether they contain PII. 
This enables E11y to apply the appropriate filtering tier and allows linter validation."
```

**Problem:** "MUST explicitly declare" contradicts "defaults to Tier 2 if omitted". If explicit is mandatory, default should raise error, not silently apply Tier 2.

**Mitigation:** Linter config option `require_explicit_declaration: true` (lines 1465-1467) forces explicit declaration for ALL events. But this is optional, not default.

### Contradiction 3: Linter Validates at Boot BUT Only Runs in Dev/Test (Not Production)
**Conflict:** Need validation to catch PII declaration errors BUT linter disabled in production (performance)
**Impact:** Medium (dev/prod parity gap)
**Related to:** ADR-006 (PII Declaration Linter)
**Notes:** Lines 1362-1375 show linter only enabled in development/test. Production deploys without runtime validation. If a PII declaration error slips through CI (e.g., conditional logic, dynamic event loading), it won't be caught in production.

**Real Evidence:**
```ruby
Lines 1362-1375: "if Rails.env.development? || Rails.env.test?
  config.after_initialize do
    E11y::Linters::PiiDeclarationLinter.validate_all!
  end
end

# Result: App won't boot if PII declarations invalid in dev/test
# But production has NO runtime validation"
```

**Gap:** What if:
- Event class loaded dynamically in production only (conditional logic)?
- CI test suite doesn't cover all event classes?
- New event added via hot reload/runtime eval?

**Mitigation:** Run linter in CI (`bundle exec rake e11y:lint:pii`) shown in lines 1481-1519. But this requires discipline and doesn't catch runtime issues.

### Contradiction 4: Deep Scanning Performance vs. Comprehensive PII Detection
**Conflict:** Need deep scanning (nested hashes, pattern matching) to catch all PII BUT deep scanning adds 4x overhead (0.05ms → 0.2ms)
**Impact:** Medium (performance vs. security)
**Related to:** ADR-006 (Performance Tiers)
**Notes:** Lines 1626-1866 show 3-tier performance strategy. Tier 3 (deep filtering) required for nested data but adds significant overhead. Document recommends "Reserve Tier 3 for true PII events" (line 1863).

**Real Evidence:**
```
Lines 1640-1647: Performance budget calculation:
- Tier 1 (500 events/sec): 0ms CPU
- Tier 2 (400 events/sec): 20ms CPU/sec
- Tier 3 (100 events/sec): 20ms CPU/sec
Total: 40ms CPU/sec = 4% CPU

Lines 1800-1817: Benchmark shows Tier 3 is 4x slower than Tier 2:
- Tier 2: 8,000 events/sec (0.125ms each)
- Tier 3: 5,000 events/sec (0.200ms each)
```

**Problem:** If developers over-use Tier 3 (conservative approach to avoid missing PII), performance budget exceeded. If developers under-use Tier 3 (performance concern), PII may leak in nested data.

**Guidance:** Document provides decision tree (lines 1829-1842) but relies on developer judgment. No automatic detection of "this event has nested data" → use Tier 3.

---

## 🔍 Implementation Notes

### Key Components
- **E11y::PiiFilter** - Main filtering engine (key-based + pattern-based + deep scanning)
- **E11y::PiiFilter::RailsAdapter** - Reads `Rails.filter_parameters` (zero-config integration)
- **E11y::PiiFilter::PatternMatcher** - Regex-based content scanning (emails, credit cards, SSNs, phones, IPs)
- **E11y::Linters::PiiDeclarationLinter** - Boot-time and CI validation
- **E11y::Event::Base#contains_pii** - Declaration DSL
- **E11y::Event::Base#pii_filtering** - Per-field strategy DSL

### Configuration Required

**Basic (Zero Config):**
```ruby
# config/application.rb (Rails standard)
config.filter_parameters += [:password, :email, :ssn]

# E11y automatically respects this! No E11y config needed.
```

**Advanced (3-Tier Strategy):**
```ruby
E11y.configure do |config|
  config.pii_filter do
    # Tier 2 (default): Rails filters
    use_rails_filter_parameters true
    filter_parameters :api_key, :token, /secret/i
    allow_parameters :user_id, :order_id
    
    # Pattern-based (content scanning)
    filter_pattern /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i,
                   replacement: '[EMAIL]'
    filter_pattern /\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/,
                   replacement: '[CARD]'
    
    # Behavior
    deep_scan true
    max_depth 10
    replacement '[FILTERED]'
    keep_partial_data false  # Or true for 'em***@ex***'
    
    # Debugging
    sample_filtered_values 0.01  # Log 1% of filtered values
    sample_logger Rails.logger
    
    # Performance
    cache_compiled_patterns true
  end
  
  # Linter
  config.pii_linter do
    enabled Rails.env.development? || Rails.env.test?
    fail_on_error true
    require_explicit_declaration false  # Or true to force explicit
  end
end
```

**Per-Event Declaration (Tier 1 or Tier 3):**
```ruby
# Tier 1: No PII (skip filtering)
class Events::HealthCheck < E11y::Event::Base
  contains_pii false  # ✅ Explicit: 0ms overhead
end

# Tier 3: Explicit PII (deep filtering)
class Events::UserRegistered < E11y::Event::Base
  contains_pii true
  
  pii_filtering do
    # DSL shortcuts (concise)
    masks :password, :secret_key
    hashes :email, :phone  # Pseudonymization (searchable)
    allows :user_id, :amount  # Non-PII
    partials :ip_address  # Debugging (show partial)
    
    # Per-adapter overrides
    hashes :email, exclude_adapters: [:file_audit]
  end
end
```

### APIs / Interfaces
- `contains_pii(boolean)` - Tier 1 (false) or Tier 3 (true) declaration
- `pii_filtering(&block)` - Per-field strategy DSL
- `field(name, &block)` - Verbose per-field config (strategy, adapters)
- `masks(*fields)` - DSL shortcut for `:mask` strategy
- `hashes(*fields)` - DSL shortcut for `:hash` strategy (pseudonymization)
- `allows(*fields)` - DSL shortcut for `:allow` strategy (non-PII)
- `partials(*fields)` - DSL shortcut for `:partial` strategy (show first/last chars)
- `E11y::Linters::PiiDeclarationLinter.validate_all!` - Boot-time validation
- `bundle exec rake e11y:lint:pii` - CI validation
- `bundle exec rake e11y:audit:pii_declarations` - Generate audit report

### Data Structures
- **PiiFilterConfig:** Rails filters, patterns, whitelist, replacement, deep_scan, max_depth
- **EventPiiDeclaration:** contains_pii flag, per-field strategies, adapter exclusions
- **FilterStrategy:** `:mask`, `:hash`, `:allow`, `:partial`

---

## ❓ Questions & Gaps

### Clarification Needed
1. **Middleware order enforcement:** UC-001 requires PII filtering BEFORE buffer routing, but no automatic validation mechanism described. How is this enforced?
2. **Per-adapter filtering overhead:** Same event filtered 4 times for 4 adapters? Or filtered once then cloned per adapter?
3. **Linter in production:** Should there be a "safe mode" that validates PII declarations at runtime (first event) without boot-time overhead?

### Missing Information
1. **Pattern performance:** Regex matching 5+ patterns on every Tier 3 event - what's the cumulative overhead?
2. **Hash salt management:** `hash_salt ENV['PII_SALT']` mentioned but no guidance on salt rotation, storage, or key management.
3. **Per-adapter filtering implementation:** Lines 2202-2223 show pseudo-code `deep_dup` and filtering - what's the memory impact of cloning events 4x?
4. **Default Tier 2 behavior validation:** How do we know Rails filters are sufficient for "90% of use cases" (line 770)? Any data/research?

### Ambiguities
1. **"MUST explicitly declare"** (line 498) vs. **"defaults to Tier 2 if omitted"** (line 754) - contradiction or documentation inconsistency?
2. **Audit trail skip_filtering** - Is this GDPR-compliant globally, or only in specific jurisdictions (EU)? What about CCPA, PCI-DSS?
3. **Custom filter execution order:** If multiple `filter` blocks defined (lines 173-202), what's the execution order? First match wins, or all applied?

---

## 🧪 Testing Considerations

### Test Scenarios
1. **Rails filter compatibility:** Configure `Rails.filter_parameters`, verify E11y respects it
2. **Pattern-based filtering:** Track event with email/credit card in content, verify filtered
3. **Deep scanning:** Nested hashes (3 levels), arrays, verify all PII filtered
4. **Tier 1 performance:** Benchmark 10,000 events with `contains_pii false`, verify 0ms overhead
5. **Tier 3 validation:** Linter catches missing field declaration, typo in field name
6. **Per-adapter filtering:** Same event sent to 4 adapters, verify different PII treatment
7. **Whitelist:** Field in `Rails.filter_parameters` but also in `allow_parameters`, verify NOT filtered
8. **Sampling:** Enable `sample_filtered_values 0.01`, verify 1% of filtered values logged

### Mocking Needs
- `Rails.application.config.filter_parameters` - Stub Rails config
- `E11y::Buffer.pop` - Inspect filtered events
- `E11y::Linters::PiiDeclarationLinter` - Spy on validation calls
- `Rails.logger` - Capture sampling logs

---

## 📊 Complexity Assessment

**Overall Complexity:** Complex

**Reasoning:**
- Rails integration (zero-config) is simple, but 3-tier strategy adds conceptual complexity
- Explicit PII declaration requires developer discipline and understanding of tiers
- Per-field strategies (mask/hash/allow/partial) add configuration surface
- Per-adapter filtering rules significantly increase config complexity (trade-off for compliance)
- Linter validation adds safety but requires CI integration and understanding of validation errors
- Deep scanning (nested data, regex patterns) adds performance tuning complexity
- DSL shortcuts reduce boilerplate but add learning curve (when to use shortcuts vs. verbose)

**Estimated Implementation Time:**
- Junior dev: 15-20 days (Rails integration, 3 tiers, linter, per-adapter rules, testing)
- Senior dev: 10-12 days (familiar with Rails filters, regex patterns, AST traversal for linter)

---

## 📚 References

### Related Documentation
- [UC-001: Request-Scoped Debug Buffering](./UC-001-request-scoped-debug-buffering.md) - Middleware order (PII filtering BEFORE buffer routing)
- [UC-002: Business Event Tracking](./UC-002-business-event-tracking.md) - Event definitions using PII filtering
- [UC-005: Sentry Integration](./UC-005-sentry-integration.md) - Strict PII masking for external service
- [UC-008: OpenTelemetry Integration](./UC-008-opentelemetry-integration.md) - Pseudonymization for OTel semantic conventions
- [UC-012: Audit Trail](./UC-012-audit-trail.md) - Skip PII filtering (compliance requirement)
- [ADR-006 Section 3.0: PII Filtering Strategy](../ADR-006-security-compliance.md#30-pii-filtering-strategy) - 3-tier architecture
- [ADR-006 Section 3.0.3: Explicit PII Declaration](../ADR-006-security-compliance.md#303-explicit-pii-declaration) - `contains_pii` design
- [ADR-006 Section 3.4.4: Configuration API](../ADR-006-security-compliance.md#344-configuration-api-rails-style-dsl) - DSL shortcuts
- [ADR-006 Section 3.0.5: PII Declaration Linter](../ADR-006-security-compliance.md#305-pii-declaration-linter) - Boot-time validation

### Similar Solutions
- **Rails ActiveSupport::ParameterFilter** - E11y extends this for observability
- **Lograge** - Log filtering but no per-adapter rules
- **Sentry Data Scrubbing** - Sentry-specific, not reusable

### Research Notes
- **3-tier performance budget (lines 1640-1647):**
  - Tier 1 (500 events/sec × 0ms) = 0ms CPU
  - Tier 2 (400 events/sec × 0.05ms) = 20ms CPU/sec
  - Tier 3 (100 events/sec × 0.2ms) = 20ms CPU/sec
  - Total: 40ms CPU/sec = 4% CPU on single core
- **GDPR compliance (lines 2262-2293):**
  - Data minimization (filter PII)
  - Purpose limitation (logs for observability only)
  - Integrity & confidentiality (PII filtered at source)
  - Accountability (sampling for audit)
- **Rails compatibility:** Zero-config integration is key differentiator from other observability gems

---

## 🏷️ Tags

`#critical` `#security` `#pii-filtering` `#gdpr` `#rails-compatibility` `#3-tier-strategy` `#explicit-declaration` `#linter` `#per-adapter-rules` `#compliance`

---

**Last Updated:** 2026-01-15  
**Next Review:** Before implementation start (Phase 3 - Consolidated Analysis)
