# TRIZ Contradiction #3: Sampling vs. Reliability

**Created:** 2026-01-15  
**Priority:** 🔴 CRITICAL  
**Domain:** Performance

---

## 📋 Technical Contradiction

**Want to improve:** Cost savings (90% sampling reduces costs)  
**But this worsens:** Reliability (may lose critical events - errors, high-value transactions)

**From:** UC-014 (Adaptive Sampling), ADR-009 (C11 Resolution)

---

## 🎯 IFR

"Critical events are never sampled (100% reliability) while low-value events are aggressively sampled (90% cost reduction)."

---

## 💡 TRIZ Solutions

### 1. **Segmentation (TRIZ #1)** - Stratified Sampling by Severity ✅ **IMPLEMENTED (C11)**
**Proposed:** Different sample rates per severity:
- Errors: 100% (never sample)
- Warn: 50%
- Success/Info: 10%
- Debug: 1%

**Evaluation:** ⭐⭐⭐⭐⭐ (5/5) - **ALREADY IMPLEMENTED** (ADR-009 C11)

### 2. **Prior Action (TRIZ #10)** - Always-Sample Rules
**Proposed:** Explicit rules for critical events:
```ruby
always_sample do
  when_field :amount, greater_than: 1000  # High-value
  when_severity :error, :fatal  # Errors
  when_pattern 'payment.*', 'security.*'  # Critical domains
end
```

**Evaluation:** ⭐⭐⭐⭐ (4/5) - **ALREADY IMPLEMENTED** (UC-014, UC-015)

---

## 🏆 Recommendation

**Solutions already implemented via C11 (Stratified Sampling) + always_sample rules.**  
**Validation:** Monitor drop rate per severity (errors should be 0%, success ~90%).

---

**Status:** ✅ Analysis Complete - **RESOLVED by C11**
