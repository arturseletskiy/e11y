# TRIZ Contradiction #2: Buffer Architecture

**Created:** 2026-01-15  
**Priority:** 🟡 MEDIUM  
**Domain:** Performance

---

## 📋 Technical Contradiction

**Want to improve:** Debug visibility (flush debug events on error for troubleshooting)  
**But this worsens:** Memory usage (request-scoped buffer holds events until request end)

**From:** UC-001 (Request-Scoped Debug Buffering)

---

## 🎯 IFR

"Debug events are automatically available when needed (on error) without consuming memory when not needed (on success)."

---

## 💡 TRIZ Solutions (3)

### 1. **Separation in Time (TRIZ #10)** - Conditional Buffering
**Current:** Always buffer debug events in request-scoped buffer.  
**Proposed:** Buffer debug events ONLY if error likelihood detected (ML-based prediction).

**Evaluation:** ⭐⭐ (2/5) - Over-engineering for v1.0

### 2. **Cheap Short-Living Object (TRIZ #27)** - Ring Buffer Reuse
**Proposed:** Reuse request-scoped buffer slots (ring buffer, not array).

**Evaluation:** ⭐⭐⭐⭐ (4/5) - Memory-efficient, already implemented (ADR-001 C20 adaptive buffer)

### 3. **Partial or Excessive Action (TRIZ #16)** - Sampling Debug Events
**Proposed:** Sample debug events before buffering (1% buffered, 99% dropped immediately).

**Evaluation:** ⭐⭐⭐ (3/5) - Reduces memory but may miss critical debug info

---

## 🏆 Recommendation

**Use Solution #2** (already implemented via C20 adaptive buffer).  
**Performance impact:** Bounded memory (<100MB total, including request buffers).

---

**Status:** ✅ Analysis Complete (Concise)
