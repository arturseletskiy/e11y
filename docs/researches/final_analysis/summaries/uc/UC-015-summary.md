# UC-015: Cost Optimization - Summary

**Document:** UC-015  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Critical  
**Domain:** Performance

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Use Case |
| **Complexity** | Complex |
| **Dependencies** | ADR-009 (Section 9.2.D - Deduplication Rejected), UC-013, UC-014 |
| **Contradictions** | 3 identified |

---

## 🎯 Purpose & Problem Statement

**What problem does this solve?**
Observability costs $160,416/year (unoptimized: 100k events/sec × 2KB × 100% to Datadog + Loki). 80% waste: duplicates (retry storms), empty payloads (50% of payload is null/defaults), debug events in production (30% of volume), 30-day retention for all data (overkill).

**Who is affected?**
Engineering Managers, CTOs, FinOps Teams, SRE

**Expected outcome:**
86% cost reduction ($160,416 → $22,800/year) via 7 optimization strategies: intelligent sampling (90%), payload minimization (90% size), compression (70%), tiered storage (58% cheaper), smart routing (83% reduction), retention-aware tagging, batch & bundle (80% bandwidth).

---

## 📝 Key Requirements (7 Optimization Strategies)

### Must Have (Critical)
- [x] **Intelligent Sampling by Value:** Always sample high-value events (amount >$1000, VIP users, errors), aggressively sample low-value (debug: 1%, success: 5%, low-value <$10: 10%), default 10%
- [x] **Payload Minimization (90% size reduction):** Drop null/empty fields, truncate long strings (max 1000 chars), drop default values (status: 'pending', currency: 'USD'), exclude internal fields
- [x] **Compression (70% reduction):** Zstd algorithm (best for JSON), level 3 (balance speed/ratio), batch compression (500 events together), min batch size 10KB (avoid compressing tiny batches)
- [x] **Tiered Storage (58% cost reduction):** Hot (7 days, Loki, fast queries, $0.20/GB), Warm (30 days, S3, medium queries, $0.05/GB), Cold (1 year, S3 Glacier, slow queries, $0.004/GB), auto-archival (daily at 2 AM)
- [x] **Smart Routing (83% reduction):** Errors → Datadog + Loki + Sentry (multiple destinations), high-value → Datadog + Loki + S3, security → Splunk + S3, debug → Loki only (no expensive Datadog)
- [x] **Retention-Aware Tagging:** Auto-tag events with retention hints (audit/payment: 7 years, errors: 90 days, debug: 7 days, default: 30 days)
- [x] **Batch & Bundle (80% bandwidth reduction):** Max batch size 500 events, max batch bytes 1 MB, max wait time 5s, compress batches, bundle similar events (similarity threshold 80%, max bundle 100)
- [x] **Cost Calculator:** Estimate savings (events/sec, avg size, num services, Datadog hosts, Loki ingestion rate)
- [x] **Self-Monitoring Metrics:** Bytes saved (compression, sampling), events reduced, monthly savings USD, compression ratio
- [x] **IMPORTANT NOTE:** Deduplication intentionally NOT included (rejected in ADR-009 §9.2.D: high overhead 3.6GB memory, false positives on legitimate retries, better alternatives: sampling + compression)

---

## 🔗 Dependencies

### Related Use Cases
- **UC-013:** High Cardinality Protection (metric cost savings)
- **UC-014:** Adaptive Sampling (smart sampling strategies)

### Related ADRs
- **ADR-009 Section 9.2.D:** Deduplication Rejected (why deduplication is NOT included - hash overhead, 3.6GB memory, false positives)

---

## ⚡ Technical Constraints

### Performance
- Compression overhead: zstd level 3 adds ~5ms per batch (500 events)
- Payload minimization: <0.1ms per event (field removal)
- Sampling decision: <0.01ms per event

### Compression Ratios (for JSON events)
- gzip level 6: ~65% reduction (2KB → 700 bytes)
- lz4 default: ~55% reduction (2KB → 900 bytes, faster)
- zstd level 3: ~70% reduction (2KB → 600 bytes, best!)

### Storage Costs (per 1TB/month)
- Hot (Loki): $200/month ($0.20/GB)
- Warm (S3): $50/month ($0.05/GB)
- Cold (Glacier): $4/month ($0.004/GB)

---

## 🎭 User Story

**As an** Engineering Manager/FinOps Lead  
**I want** 70-90% observability cost reduction without losing critical data  
**So that** I save $137,616/year while maintaining full visibility into errors, high-value transactions, and security events

**Rationale:**
Unoptimized observability costs $160,416/year due to:
- No sampling → 100% of events stored (but 80% are duplicates/noise)
- Full payloads → 2KB/event (but 50% is null/empty values)
- No compression → raw JSON (but JSON compresses 70% with zstd)
- Hot storage only → $0.20/GB (but 23 out of 30 days could be warm @ $0.05/GB)
- All events to Datadog → $15/host (but only errors need Datadog alerting)

E11y solves with 7 optimization strategies (combined effect: 86% reduction).

**Trade-offs:**
- ✅ **Pros:** 86% cost savings, maintains high-value event visibility, preserves error alerting, compliant retention (7 years for payment/audit)
- ❌ **Cons:** Configuration complexity (7 strategies to configure), sampling may miss low-value edge cases, compression adds 5ms latency per batch, tiered storage adds archival complexity

---

## ⚠️ Potential Contradictions

### Contradiction 1: Deduplication Rejected (ADR-009 §9.2.D) BUT Retry Storms Waste 80% of Events
**Conflict:** Document states "80% of events are duplicates (retry storms)" (line 31) BUT deduplication intentionally NOT included as strategy (line 98)
**Impact:** High (missed optimization opportunity?)
**Related to:** ADR-009 Section 9.2.D (Deduplication Rejected)
**Notes:** Line 98 says: "Deduplication is intentionally NOT included... ADR-009 Section 9.2.D explains why it was rejected: high computational overhead (hash + Redis lookup per event), large memory cost (3.6GB for 1000 events/sec), false positives on legitimate retries, and debug confusion. Better alternatives (sampling + compression) achieve the same cost goals without these drawbacks."

**Real Evidence:**
```
Line 31: "80% of events are duplicates (retry storms)"

Line 98: "Deduplication is intentionally NOT included... rejected: high computational overhead... 3.6GB memory cost... false positives... Better alternatives (sampling + compression)."
```

**Question:** If 80% are duplicates, how does sampling + compression solve this? Sampling doesn't deduplicate (it randomly drops 90%, but duplicates still exist in remaining 10%). Compression helps with storage, but duplicates still consume ingestion bandwidth and cost.

**Hypothesis:** The "80% duplicates" claim might be exaggerated, or it assumes retry storms are solved by application-level fixes (proper error handling), not E11y-level deduplication.

**Clarification Needed:** Is the "80% duplicates" assumption based on pre-E11y state (unoptimized application with retry storms), and E11y assumes applications will fix retry logic separately?

### Contradiction 2: Payload Minimization (Drop Null/Empty) vs. Schema Validation (Required Fields)
**Conflict:** Payload minimization drops null/empty values BUT schema validation requires certain fields to be present (even if null/empty)
**Impact:** Medium (data integrity vs. cost savings)
**Related to:** UC-002 (Business Event Tracking - schema validation)
**Notes:** Lines 156-216 describe payload minimization:
- `drop_null_fields: true` - Remove fields with null values
- `drop_empty_strings: true` - Remove fields with ''
- `drop_empty_arrays: true` - Remove fields with []

But UC-002 schema validation (line 68-74) shows `required(:field).filled(:type)` - required fields must be present and filled.

**Problem:** If event has `optional(:notes).filled(:string)` with value `notes: ''`, and payload minimization drops empty strings, the field is removed. But schema validation might expect field to be present (even if empty).

**Clarification Needed:** Does payload minimization only drop OPTIONAL fields? Or does it also drop REQUIRED fields if empty (violating schema)?

**Hypothesis:** Payload minimization only drops fields that are:
1. Not required by schema, OR
2. Required but explicitly configured as "drop if default" (e.g., `currency: 'USD'` is default, can be dropped)

### Contradiction 3: Tiered Storage (7 Days Hot + 23 Days Warm) vs. Retention-Aware Tagging (Per-Event Retention)
**Conflict:** Tiered storage uses fixed durations (7 days hot, 30 days warm, 1 year cold) BUT retention-aware tagging allows per-event retention (audit: 7 years, debug: 7 days, errors: 90 days)
**Impact:** Low (configuration consistency)
**Related to:** Strategy 4 (Tiered Storage), Strategy 6 (Retention-Aware Tagging)
**Notes:** Lines 258-308 describe tiered storage with fixed durations (7 days hot, 30 days warm, 1 year cold). Lines 361-403 describe retention-aware tagging with per-event retention (audit: 7 years, debug: 7 days).

**Real Evidence:**
```
Lines 264-285: "hot_tier do
  duration 7.days
  storage :loki
end

warm_tier do
  duration 30.days
  storage :s3
end

cold_tier do
  duration 1.year
  storage :s3_glacier
end"

Lines 367-382: "tag_with_retention do
  when_pattern 'audit.*', 'gdpr.*', retention: 7.years
  when_pattern 'payment.*', 'transaction.*', retention: 7.years
  when_severity :error, :fatal, retention: 90.days
  when_severity :debug, retention: 7.days
  default_retention 30.days
end"
```

**Question:** How do these two strategies interact?
- If audit event has `retention: 7.years` tag, but tiered storage moves to cold (Glacier) after 1 year, does it stay in Glacier for 6 more years? Or deleted after 1 year (violating retention tag)?
- If debug event has `retention: 7.days` tag, but tiered storage keeps in hot (Loki) for 7 days, then moves to warm (S3) for 30 days total, is this correct?

**Hypothesis:** Tiered storage is about WHERE data is stored (hot Loki vs. warm S3), retention-aware tagging is about HOW LONG data is stored. They should work together:
- Audit (7 years): 7 days hot (Loki) + 23 days warm (S3) + 6.9 years cold (Glacier)
- Debug (7 days): 7 days hot (Loki), then deleted

But configuration doesn't show this integration clearly.

---

## 🧪 Testing Considerations

### Test Scenarios
1. Intelligent sampling: High-value event (amount: 5000), verify always sampled (100%)
2. Payload minimization: Event with null fields, verify dropped
3. Compression: 500 events batch, verify zstd compression ratio >60%
4. Tiered storage: Mock archival, verify events moved to S3 after 7 days
5. Smart routing: Error event, verify sent to Datadog + Loki + Sentry; success event, verify sent to Loki only
6. Retention tagging: Audit event, verify retention tag = 7 years
7. Cost calculator: Calculate savings for 100k events/sec, verify 86% reduction

---

## 📊 Complexity Assessment

**Overall Complexity:** Complex

**Reasoning:**
- 7 optimization strategies (each with own configuration)
- Intelligent sampling requires understanding of value-based sampling (amount thresholds, user segments, severities)
- Payload minimization requires understanding of defaults, truncation, exclusion rules
- Compression requires algorithm selection (zstd vs. lz4 vs. gzip), level tuning
- Tiered storage requires understanding of hot/warm/cold storage costs, archival schedules
- Smart routing requires understanding of destination costs (Datadog expensive, Loki cheap)
- Retention-aware tagging requires legal compliance knowledge (7 years for payment/audit, 90 days for errors)
- Cost calculator requires understanding of pricing models (Datadog $15/host, Loki $0.20/GB)

**Estimated Implementation Time:**
- Junior dev: 20-25 days (7 strategies, cost calculator, testing, tuning)
- Senior dev: 12-15 days (familiar with compression, storage tiers, cost optimization)

---

## 📚 References

### Related Documentation
- [UC-013: High Cardinality Protection](./UC-013-high-cardinality-protection.md) - Metric cost savings
- [UC-014: Adaptive Sampling](./UC-014-adaptive-sampling.md) - Intelligent sampling strategies
- [ADR-009 Section 9.2.D](../ADR-009-cost-optimization.md#alternatives-considered) - Why deduplication rejected

### Research Notes
- **Real-world savings (lines 14-92):**
  - Before: $160,416/year (100k events/sec, 2KB each, 100% to Datadog + Loki)
  - After: $22,800/year (10k events/sec, 0.6KB each, errors only to Datadog)
  - Savings: $137,616/year (86% reduction)
- **Deduplication rejection (line 98):**
  - High overhead (hash + Redis lookup per event)
  - Large memory cost (3.6GB for 1000 events/sec)
  - False positives (legitimate retries)
  - Debug confusion
  - Better alternatives: sampling + compression
- **Compression ratios (lines 247-253):**
  - gzip: 65% reduction
  - lz4: 55% reduction (faster)
  - zstd: 70% reduction (best!)
- **Storage tier costs (lines 295-308):**
  - Hot (Loki): $200/TB/month
  - Warm (S3): $50/TB/month
  - Cold (Glacier): $4/TB/month
  - Strategy: 7 days hot + 23 days warm = 58% cost reduction vs. 30 days hot

---

## 🏷️ Tags

`#critical` `#cost-optimization` `#86-percent-reduction` `#intelligent-sampling` `#compression` `#tiered-storage` `#smart-routing` `#deduplication-rejected`

---

**Last Updated:** 2026-01-15  
**Next Review:** Before implementation (Phase 3 - Consolidated Analysis)
