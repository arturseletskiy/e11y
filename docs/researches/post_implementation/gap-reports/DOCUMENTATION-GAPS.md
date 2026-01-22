# Documentation Gaps

**Audit Scope:** Documentation-related findings from all phases  
**Total Issues:** TBD  
**Status:** 🔄 In Progress

---

## 📊 Overview

Summary of documentation gaps found during E11y v1.0.0 audit.

**Audits Analyzed:**
- AUDIT-024: UC-006 Event-Based Alerts (documentation)
- AUDIT-025: UC-021 Yabeda Integration (documentation)
- AUDIT-038: UC-022 Event Registry (documentation generation)
- Various recommendations across all audits

---

## 🔴 HIGH Priority Issues

---

## 🟡 MEDIUM Priority Issues

---

## 🟢 LOW Priority Issues

### DOC-001: Rate Limit Algorithm Documentation Mismatch

**Source:** AUDIT-001-GDPR  
**Finding:** F-005  
**Reference:** [AUDIT-001-ADR-006-GDPR-Compliance.md:883-886](docs/researches/post_implementation/AUDIT-001-ADR-006-GDPR-Compliance.md#L883-L886)

**Problem:**
ADR-006 §4.2 says "sliding window" algorithm, but code implements "token bucket" algorithm.

**Impact:**
- LOW - Documentation inconsistency
- Confusing for developers reading ADR
- Both algorithms are valid, just mismatch

**Evidence:**
```
ADR-006 §4.2: "Sliding window rate limiting"
Code: Token bucket with C02 resolution
```

**Recommendation:** Update ADR-006 to reflect token bucket implementation (Priority 3-LOW, 1 hour effort)  
**Status:** ⚠️ INCONSISTENCY

---

### DOC-002: Zero-Allocation DoD Target Unrealistic

**Source:** AUDIT-004-ZERO-ALLOCATION  
**Finding:** F-001  
**Reference:** [AUDIT-004-ADR-001-zero-allocation.md:574, :548-551](docs/researches/post_implementation/AUDIT-004-ADR-001-zero-allocation.md#L574)

**Problem:**
DoD specifies "<100 allocations per 1K events" but this is **impossible in Ruby**. Even minimal Hash creation = 1 allocation, so 1K events = minimum 7,000-9,000 allocations.

**Impact:**
- MEDIUM - Confusing requirement
- Developers may think implementation is broken
- Actual implementation is **optimal** (7-9 allocations/event = Ruby theoretical minimum)

**Evidence:**
```
DoD: <100 allocations per 1K events (<0.1 alloc/event)
Reality: 7-9 allocations/event (Ruby minimum)
Actual: 7,000-9,000 allocations per 1K events (70-90x DoD target)
```

**Clarification:**
E11y implementation is **correct**. Ruby cannot create Hash without allocating memory. 7-9 allocations/event includes:
- Hash creation (1)
- Middleware chain (2-3)
- Adapter calls (2-3)
- String/Symbol interning (1-2)

**Recommendation:** R-001 - Update DoD to realistic target: "<10 allocations/event" (Priority 2-MEDIUM, clarification)  
**Status:** ⚠️ CONFUSING DOCUMENTATION

---

### DOC-003: Grafana Dashboard JSON Template Missing
**Source:** AUDIT-025-UC-004-DASHBOARDS-OVERRIDE
**Finding:** F-412
**Reference:** [AUDIT-025-UC-004-DASHBOARDS-OVERRIDE.md:60-140](docs/researches/post_implementation/AUDIT-025-UC-004-DASHBOARDS-OVERRIDE.md#L60-L140)

**Problem:**
No Grafana dashboard JSON template (docs/dashboards/e11y-slo.json) - usability issue.

**Impact:**
- MEDIUM - Users must manually create Grafana dashboards
- Industry standard: Prometheus exporters include dashboard JSON
- UC-004 describes `rails g e11y:grafana_dashboard`, but not implemented

**Expected Files:**
- ❌ `docs/dashboards/e11y-slo.json`
- ❌ `docs/dashboards/e11y-metrics.json`
- ❌ `lib/generators/e11y/grafana_dashboard_generator.rb`

**Recommendation:**
- **R-141**: Create Grafana dashboard JSON template
- **Priority:** MEDIUM (2-MEDIUM)
- **Effort:** 4-5 hours
- **Phase:** Phase 2 (usability enhancement)

**Status:** ❌ MISSING (Phase 2 feature)

---

### DOC-004: QUICK-START.md References Non-Existent Generator
**Source:** AUDIT-029-ADR-010-5MIN-SETUP
**Finding:** F-444
**Reference:** [AUDIT-029-ADR-010-5MIN-SETUP.md:96-124](docs/researches/post_implementation/AUDIT-029-ADR-010-5MIN-SETUP.md#L96-L124)

**Problem:**
QUICK-START.md line 14 references `rails g e11y:install` generator that does NOT exist.

**Impact:**
- HIGH CRITICAL - New user onboarding broken
- Following docs leads to error: `Could not find generator 'e11y:install'`
- Trust issue (documentation accuracy questioned)
- Already documented in AUDIT-004 F-006 (CRITICAL)

**Current Documentation:**
```markdown
# docs/QUICK-START.md:14
rails g e11y:install  # ← PROBLEM: Generator doesn't exist!
```

**Search Evidence:**
```bash
$ find lib/ -name "*install*generator*"
# → NO RESULTS

$ grep -r "rails.*generate.*e11y\|e11y:install" lib/
# → NO RESULTS
```

**Reality:**
E11y auto-configures via Railtie (no generator needed):
- Sets environment (Rails.env)
- Sets service_name (Rails.application.class.module_parent_name)
- Configures middleware (6 middleware auto-added)
- Configures default adapter (Stdout fallback)

**Recommendation:**
- **R-171**: Fix QUICK-START.md (remove generator reference, document zero-config Railtie approach)
- **Priority:** HIGH CRITICAL (1 hour)
- **Acceptance Criteria:**
  - Update QUICK-START.md line 14 (remove generator step)
  - Add note: "No generator needed! E11y auto-configures via Railtie"
  - Update setup instructions to reflect zero-config approach
  - Test setup flow without generator

**Status:** ❌ CRITICAL ERROR (new user onboarding broken)

---

### DOC-005: No Version Badges (v1.0 vs v1.1+ Features)
**Source:** AUDIT-029-ADR-010-DOCUMENTATION-ERRORS
**Finding:** F-451
**Reference:** [AUDIT-029-ADR-010-DOCUMENTATION-ERRORS.md:300-360](docs/researches/post_implementation/AUDIT-029-ADR-010-DOCUMENTATION-ERRORS.md#L300-L360)

**Problem:**
No version distinction in documentation (users don't know which features are v1.0 vs v1.1+).

**Impact:**
- MEDIUM - Users expect features that aren't implemented yet
- Some UCs describe v1.1+ features (UC-008, UC-009) but not marked
- No clear feature matrix

**Examples:**
- UC-009 (Multi-Service Tracing): Status says "v1.1+ Enhancement" but not prominent
- UC-008 (OpenTelemetry Integration): ADR-007 priority says "v1.1+ enhancement"
- README doesn't show feature availability

**Recommendation:**
- **R-177**: Add version badges to UCs and ADRs
- **Priority:** MEDIUM (3-4 hours)
- **Acceptance Criteria:**
  - Add version badge to each UC (e.g., "Status: v1.0" or "Status: v1.1+ Enhancement")
  - Add version badge to each ADR (e.g., "Priority: v1.0" or "Priority: v1.1+ enhancement")
  - Update UC-INDEX and ADR-INDEX with version column
  - Add feature matrix to README (✅ v1.0 Available, 🚧 v1.1+ Roadmap)

**Status:** ⚠️ MISSING (clarity issue)

---

## 🔗 Cross-References

