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

### 3. **Prior Action (TRIZ #10)** - Opt-In Features
**Proposed:** Features disabled by default, enable only when needed.

**Evaluation:** ⭐⭐⭐⭐ (4/5) - Partially implemented (VersioningMiddleware opt-in)

---

## 🏆 Recommendation

**Solutions #1 + #2 already implemented.** Extend Solution #3 (more opt-in features).  
**Performance budget met:** <1ms p99 (0.15-0.3ms middleware chain + 0.05ms buffer write).

---

**Status:** ✅ Analysis Complete - **LARGELY RESOLVED**
