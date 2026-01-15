# TRIZ Contradiction #4: PII Filtering

**Created:** 2026-01-15  
**Priority:** 🔴 CRITICAL  
**Domain:** Security

---

## 📋 Technical Contradiction

**Want to improve:** Security (filter all PII, GDPR compliance)  
**But this worsens:** Audit trail integrity (signature on filtered data violates non-repudiation)

**From:** UC-007, ADR-006, ADR-015 (C01 Resolution)

---

## 🎯 IFR

"Audit trail contains original PII (for non-repudiation) while observability systems receive filtered PII (for GDPR), without duplicating event tracking code."

---

## 💡 TRIZ Solutions

### 1. **Separation (TRIZ #1)** - Two Pipelines ✅ **IMPLEMENTED (C01)**
**Proposed:** Separate pipelines for audit vs. observability:
- Standard: PIIFiltering (#3) → adapters
- Audit: AuditSigning (NO PIIFiltering) → encrypted storage

**Evaluation:** ⭐⭐⭐⭐⭐ (5/5) - **ALREADY IMPLEMENTED** (ADR-015 C01)

### 2. **Local Quality (TRIZ #3)** - Per-Adapter PII Rules
**Proposed:** Different filtering per adapter:
- audit_file: skip filtering (original PII)
- sentry: strict masking (external service)
- loki: pseudonymization (hash)

**Evaluation:** ⭐⭐⭐⭐⭐ (5/5) - **ALREADY IMPLEMENTED** (UC-007, ADR-006)

---

## 🏆 Recommendation

**Solutions already implemented via C01 (Two Pipelines) + per-adapter PII rules.**  
**Validation:** Verify audit events encrypted at rest (AES-256-GCM mandatory).

---

**Status:** ✅ Analysis Complete - **RESOLVED by C01**
