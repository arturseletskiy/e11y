# TRIZ Contradiction #5: Performance vs. Features

**Created:** 2026-01-15  
**Priority:** 🟠 HIGH  
**Domain:** Performance

---

## 📋 Technical Contradiction

**Want to improve:** Feature richness (all 22 UCs: PII filtering, sampling, metrics, tracing, etc.)  
**But this worsens:** Performance (each feature adds latency: PII ~0.2ms, sampling ~0.01ms, etc.)

**From:** ADR-001 (Performance Requirements: <1ms p99)

---

## 🎯 IFR

"All 22 features work together with <1ms p99 latency total."

---

## 💡 TRIZ Solutions

### 1. **Segmentation (TRIZ #1)** - Middleware Chain ✅ **IMPLEMENTED**
**Proposed:** Each feature = separate middleware (can disable individually).

**Evaluation:** ⭐⭐⭐⭐⭐ (5/5) - **ALREADY IMPLEMENTED** (ADR-001 middleware chain)

### 2. **Cheap Object (TRIZ #27)** - Zero-Allocation ✅ **IMPLEMENTED**
**Proposed:** No instance creation, class methods only, Hash-based events.

**Evaluation:** ⭐⭐⭐⭐⭐ (5/5) - **ALREADY IMPLEMENTED** (ADR-001)

### 3. **Prior Action (TRIZ #10)** - Opt-In Features ⚠️ **EXTENDED**
**Proposed:** Features disabled by default, enable only when needed.

**Evaluation:** ⭐⭐⭐⭐⭐ (5/5) - **EXTENDED IMPLEMENTATION**

**Implemented:**
- ✅ VersioningMiddleware opt-in (already implemented)
- ✅ Adaptive sampling opt-in via conventions (already implemented)
- ✅ **NEW: PII filtering opt-out** (see ADR-001 Section 12)
- ✅ **NEW: Rate limiting opt-out** (see ADR-001 Section 12)

**Performance Impact:**
- PII filtering opt-out: saves 0.2ms per event (20% of 1ms budget!)
- Rate limiting opt-out: saves 0.01ms per event

**Use Cases:**
- Public page views (no PII) → opt-out PII filtering
- Rare admin actions (<10/day) → opt-out rate limiting
- Critical payments (100% capture) → opt-out sampling

**Safety:**
- Validation at class load prevents PII fields with pii_filtering disabled
- Default: enabled (safety first)
- Explicit opt-out required (prevents accidents)

---

## 🏆 Recommendation

**Solutions #1 + #2 already implemented.** Solution #3 (opt-in features) **EXTENDED** to PII filtering and rate limiting opt-out.  
**Performance budget met:** <1ms p99 (0.15-0.3ms middleware chain + 0.05ms buffer write).  
**Optimization:** Opt-out PII filtering saves 0.2ms (20% of budget!), opt-out rate limiting saves 0.01ms.

**See:** ADR-001 Section 12 for full opt-in/opt-out pattern documentation.

---

**Status:** ✅ Analysis Complete - **FULLY RESOLVED** (extended from 4/5 to 5/5)
