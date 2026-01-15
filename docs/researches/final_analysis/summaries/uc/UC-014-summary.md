# UC-014: Adaptive Sampling - Summary

**Document:** UC-014  
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
| **Dependencies** | ADR-009 (Critical - 2 sections), UC-001, UC-004, UC-006, UC-011, UC-015 |
| **Contradictions** | 4 identified |

---

## 🎯 Purpose & Problem Statement

**What problem does this solve?**
Fixed sampling wastes resources during normal times (could track more) AND provides insufficient data during incidents (need more samples, not same rate). No signal/noise optimization, fixed cost regardless of load.

**Who is affected?**
SRE, DevOps, Engineering Managers

**Expected outcome:**
Dynamic sampling adapts to conditions: 100% during error spikes (better data!), 1% during high load (90% savings), 6.5% effective rate during Black Friday (35% savings vs. fixed 10%).

---

## 📝 Key Requirements

### Must Have (Critical)
- [x] **8 Adaptive Sampling Strategies:**
  1. Error-Based: Increase sampling during error spikes (100%)
  2. Load-Based: Adjust based on event volume (tiered: 100% → 50% → 10% → 1%)
  3. Value-Based: Always sample high-value events (>$1000, VIP users, importance >8)
  4. Content-Based: Sample by event patterns (always: payment.*, security.*, never: debug.*, heartbeat.*)
  5. Tail-Based: Sample based on final outcome (requires buffering, max 30s request time)
  6. ML-Based: Learn optimal sampling from historical data (7-day training window, daily retrain)
  7. Trace-Consistent: Propagate sample decision across services/jobs (via X-E11y-Sampled header)
  8. Stratified Sampling for SLO (C11 Resolution): Preserve error/success ratio (errors: 100%, success: 10%)
- [x] **Error Spike Detection:** Absolute threshold (>100 errors/min) + relative threshold (3x normal rate)
- [x] **Load Tiers:** Tiered sampling by event volume (0-1k: 100%, 1k-10k: 50%, 10k-50k: 10%, >50k: 1%)
- [x] **Always Sample:** Critical events never dropped (severities: error/fatal, patterns: payment.*, security.*)
- [x] **Trace-Consistent Propagation:** Sample decision stored in metadata, propagated to jobs/services, orphaned job handling
- [x] **Stratified Sampling (C11):** Sample rate by severity (error: 100%, warn: 50%, info: 10%, debug: 5%)
- [x] **SLO Sampling Correction:** Auto-correct metrics for accurate SLO (enable_sampling_correction: true)

### Should Have (Important)
- [x] **Exponential Decay:** Gradually return to normal sampling after error spike (5 min at 100% → 10 min decay)
- [x] **Hysteresis:** Prevent flapping between tiers (20% buffer before tier change)
- [x] **Smooth Transitions:** Avoid sudden sampling jumps (30s transition period)
- [x] **Whitelist Sampling:** Debug-specific users at 100% (temporary, 1 hour TTL)
- [x] **Self-Monitoring Metrics:** Current sample rate, events sampled/dropped, strategy transitions, resource savings

### Could Have (Nice to have)
- [ ] ML model auto-tuning based on cost/accuracy trade-offs
- [ ] Multi-dimensional stratified sampling (by severity + event pattern + time of day)
- [ ] Predictive sampling (anticipate spikes before they happen)

---

## 🔗 Dependencies

### Related Use Cases
- **UC-001: Request-Scoped Debug Buffering** - sample_on_error works with buffering (tail-based sampling)
- **UC-004: SLO Tracking with Sampling Correction** - Stratified sampling (C11) for accurate SLO
- **UC-006: Trace Context Management** - Trace-consistent sampling requires trace propagation
- **UC-011: Rate Limiting** - Complementary with sampling (both reduce event volume)
- **UC-015: Cost Optimization** - Sampling reduces costs (35-90% savings)

### Related ADRs
- **ADR-009 Section 3:** Adaptive Sampling (all 8 strategies architecture)
- **ADR-009 §3.7:** Stratified Sampling for SLO Accuracy (C11 Resolution)

### External Dependencies
- Redis (optional, for whitelist sampling across multiple app servers)
- ML libraries (optional, for ML-based sampling: training, prediction)

---

## ⚡ Technical Constraints

### Performance
- **Error spike detection:** 1-minute sliding window, p95 baseline calculation (1-hour window)
- **Load-based sampling:** Real-time event volume tracking, 30s transition period, 20% hysteresis
- **Tail-based sampling:** 30s max buffer duration (max request time)
- **Trace-consistent sampling:** Propagation overhead (store in metadata, HTTP header, job args)
- **ML-based sampling:** 7-day training window, daily retrain (1-day interval)

### Scalability
- **Load tiers:** 0-1k/sec (100%), 1k-10k (50%), 10k-50k (10%), >50k/sec (1%)
- **Stratified sampling:** Handles 10M events/month (1.45M kept, 85.5% cost savings)
- **Trace-consistent sampling:** Works across distributed services (HTTP header propagation)

### Security
- No direct security constraints (adaptive sampling is performance/cost optimization)

### Compatibility
- Ruby/Rails (requires Current for thread-local sampling state)
- Redis (optional, for distributed whitelist sampling)
- OpenTelemetry (trace-consistent sampling compatible with OTel trace propagation)

---

## 🎭 User Story

**As an** SRE/Engineering Manager  
**I want** adaptive sampling that increases during errors (100%) and decreases during high load (1%)  
**So that** I get better data during incidents while saving 35-90% costs during peaks compared to fixed 10% sampling

**Rationale:**
Fixed sampling (e.g., 10% all events) has two problems:
1. **Wasted capacity during normal times:** Could track 100% when load is low (only 1k events/sec)
2. **Insufficient data during incidents:** 10% of 100k errors/sec = 10k sampled, but we need ALL errors for debugging!

Adaptive sampling solves this by:
- **Error-based:** 100% sampling during error spikes (better data quality!)
- **Load-based:** 1% sampling during high load (90% cost savings)
- **Value-based:** Always sample high-value events (>$1000 transactions, VIP users)
- **Trace-consistent:** Propagate sample decision to jobs/services (no orphaned events)
- **Stratified (C11):** Preserve error/success ratio for accurate SLO (85.5% cost savings + 100% accuracy)

**Alternatives considered:**
1. **Fixed sampling** - Rejected: wastes resources during normal, insufficient during incidents
2. **Manual toggle** - Rejected: requires human intervention, slow response
3. **Random sampling** - Rejected: breaks SLO metrics (errors are rare, random sampling drops most errors)

**Trade-offs:**
- ✅ **Pros:** 35-90% cost savings during peaks, 100% error visibility during spikes, accurate SLO (C11), trace completeness (propagation)
- ❌ **Cons:** Configuration complexity (8 strategies), tail-based sampling adds latency (30s buffer), ML-based requires training data/retraining, trace-consistent adds propagation overhead

---

## ⚠️ Potential Contradictions

### Contradiction 1: Trace-Consistent Sampling Requires Buffering BUT Buffering Adds Memory Overhead
**Conflict:** Need trace-consistent sampling (no orphaned events) BUT requires buffering (30s max request time) which adds memory overhead
**Impact:** Medium (memory vs. trace completeness)
**Related to:** UC-001 (Request-Scoped Debug Buffering), UC-006 (Trace Context Management)
**Notes:** Lines 242-282 describe tail-based sampling: buffer events for request duration (max 30s), then decide to keep or drop ALL events. This ensures trace consistency BUT adds memory overhead:
- Typical request (10 events, 200ms): ~5KB buffer (acceptable)
- Long request (100 events, 30s): ~50KB buffer (higher overhead)
- Concurrent requests (100): 500KB - 5MB total memory

**Real Evidence:**
```
Lines 251-252: "buffer_duration 30.seconds  # Max request time"

Lines 275-277: "Request starts → Buffer all events
Request ends → Evaluate criteria
Decision: Keep all or drop all events for this request"
```

**Trade-off:** Buffering overhead is necessary for trace completeness. Without buffering, traces would be incomplete (orphaned events). Document shows this is acceptable (<10MB even at high load).

**Mitigation:** UC-001 already implements request-scoped buffering. Tail-based sampling reuses this infrastructure, so no additional overhead beyond what UC-001 requires.

### Contradiction 2: Stratified Sampling (C11) is More Accurate BUT Keeps More Events Than Random Sampling
**Conflict:** Stratified sampling preserves error/success ratio (100% accuracy) BUT keeps more events than random sampling (85.5% vs. 90% cost savings)
**Impact:** Low (acceptable trade-off for SLO accuracy)
**Related to:** ADR-009 §3.7 (C11 Resolution), UC-004 (SLO Tracking)
**Notes:** Lines 548-626 explain stratified sampling. Comparison table (lines 616-625):
- Random sampling (10%): 1M events kept (90% savings), ±5% SLO error ❌
- Stratified sampling (C11): 1.45M events kept (85.5% savings), 0% SLO error ✅

**Real Evidence:**
```
Lines 616-625: "Comparison: Random vs Stratified
| Aspect | Random Sampling (10%) | Stratified Sampling (C11) |
| Events kept | 1M (10% of 10M) | 1.45M (14.5% of 10M) |
| Errors kept | ~50K (10% × 500K) ❌ | 500K (100% × 500K) ✅ |
| SLO accuracy | ±5% error ❌ | 0% error ✅ |
| Cost savings | 90% | 85.5% |"
```

**Trade-off:** 4.5% less cost savings (90% → 85.5%) is acceptable for 100% SLO accuracy. Document concludes: "Accuracy > simplicity" (line 714).

**Justification:** Production SLO tracking requires accurate error rates. Random sampling drops 90% of errors, making SLO metrics unreliable. Stratified sampling keeps ALL errors (100%) while sampling 10% of success events.

### Contradiction 3: Tail-Based Sampling Provides Best Signal BUT Requires Buffering and Adds Latency
**Conflict:** Tail-based sampling (sample based on final outcome) provides best signal quality BUT requires buffering entire request and adds latency decision overhead
**Impact:** Medium (latency vs. signal quality)
**Related to:** UC-001 (Request-Scoped Debug Buffering)
**Notes:** Lines 242-282 describe tail-based sampling. It buffers ALL events for request duration (max 30s), then evaluates criteria at request end:
- Always sample if ANY error
- Always sample if slow (>1s)
- Always sample if high-value transaction (>$1000)
- Otherwise: probabilistic sampling (10%)

**Real Evidence:**
```
Lines 251-268: "buffer_duration 30.seconds  # Max request time

# Decision criteria (applied at request end)
sample_if do |events_in_request|
  # Always sample if ANY error
  return true if events_in_request.any? { |e| e.severity == :error }
  
  # Always sample if slow (>1 second)
  request_duration = events_in_request.last.timestamp - events_in_request.first.timestamp
  return true if request_duration > 1.0
  
  # Always sample if high-value transaction
  return true if events_in_request.any? { |e| e.payload[:amount].to_i > 1000 }
  
  # Otherwise: probabilistic sampling
  rand < 0.1  # 10%
end"
```

**Trade-off:** Tail-based sampling provides best signal (knows outcome before deciding) BUT:
- Memory: 5-50KB per request buffer
- Latency: Decision evaluated at request END (blocking response?)
- Complexity: Requires buffering infrastructure (UC-001)

**Clarification Needed:** Does tail-based sampling decision block response? Or is decision async (response sent, then buffer flushed/discarded)?

### Contradiction 4: ML-Based Sampling is Optimal BUT Requires Training Data, Model Retraining, and Fallback
**Conflict:** ML-based sampling learns optimal patterns from historical data BUT requires 7-day training window, daily retraining, and fallback strategy (adds complexity)
**Impact:** Medium (optimality vs. operational complexity)
**Related to:** ADR-009 Section 3 (Adaptive Sampling)
**Notes:** Lines 286-323 describe ML-based sampling. It trains a model on 7 days of historical data, predicts event "importance", and retrains daily. Fallback to 10% sampling if model fails.

**Real Evidence:**
```
Lines 296-314: "training_data window: 7.days,
              features: [
                :event_name,
                :severity,
                :error_rate,
                :request_duration,
                :time_of_day,
                :day_of_week,
                :load_level
              ]

# Model predicts event 'importance'
importance_threshold 0.7  # >0.7 → always sample

# Update model periodically
retrain_interval 1.day

# Fallback if model fails
fallback_sample_rate 0.1"
```

**Trade-off:** ML-based sampling is optimal (learns from production data) BUT:
- Operational complexity: Model training, storage, versioning
- Cold start: Requires 7 days of data before first model
- Retraining: Daily job (1-day interval) - what if retraining fails?
- Fallback: Falls back to 10% if model unavailable (acceptable, but not adaptive)

**Recommendation:** Document shows ML-based sampling is "Strategy 6" (advanced feature). For most use cases, strategies 1-5 are sufficient. ML-based should be opt-in for teams with ML infrastructure.

---

## 🔍 Implementation Notes

### Key Components
- **E11y::Sampling::ErrorSpikeDetector** - Track error rate, detect spikes (1-min window, p95 baseline)
- **E11y::Sampling::LoadBasedSampler** - Tiered sampling by event volume (4 tiers, hysteresis)
- **E11y::Sampling::ValueBasedSampler** - Sample by field values (amount, user_segment, importance)
- **E11y::Sampling::ContentBasedSampler** - Sample by event patterns (always/never sample)
- **E11y::Sampling::TailBasedSampler** - Buffer events, decide at request end
- **E11y::Sampling::MLBasedSampler** - Train model, predict importance, retrain daily
- **E11y::Sampling::TraceConsistentSampler** - Propagate sample decision (Current, metadata, headers)
- **E11y::Sampling::StratifiedAdaptiveSampler** - Sample by severity (C11 resolution)
- **E11y::SLO::Calculator** - Auto-correct metrics for accurate SLO (sampling correction)

### Configuration Required

**Basic (Error + Load + Value):**
```ruby
E11y.configure do |config|
  config.adaptive_sampling do
    base_sample_rate 0.1  # 10% default
    
    # Strategy 1: Error-Based
    on_error_spike do
      sample_rate 1.0  # 100% during errors
      duration 5.minutes
      error_rate_threshold 0.05  # 5% error rate triggers
    end
    
    # Strategy 2: Load-Based
    on_high_load do
      sample_rate 0.01  # 1% during overload
      load_threshold 50_000  # events/sec
    end
    
    # Strategy 3: Value-Based
    sample_by_value do
      field :amount
      threshold 1000  # Always sample >$1000 transactions
    end
    
    # Always sample critical events
    always_sample severities: [:error, :fatal],
                  event_patterns: ['payment.*', 'security.*']
  end
end
```

**Advanced (Trace-Consistent + Stratified):**
```ruby
E11y.configure do |config|
  config.adaptive_sampling do
    # Strategy 7: Trace-Consistent
    trace_consistent do
      enabled true
      propagate_decision true
      sample_decision_key 'e11y_sampled'
      sample_on_error true  # Override decision if error occurs
    end
    
    # Strategy 8: Stratified (C11)
    strategy :stratified_adaptive
    stratified_rates do
      error 1.0    # 100% - Keep ALL errors
      warn  0.5    # 50%
      info  0.1    # 10%
      debug 0.05   # 5%
    end
  end
  
  # SLO tracking with auto-correction
  config.slo do
    enable_sampling_correction true  # Auto-correct metrics
  end
end
```

**Production Incident Response:**
```ruby
E11y.configure do |config|
  config.adaptive_sampling do
    # Detect error spike
    error_spike_detection do
      enabled true
      window 1.minute
      absolute_threshold 100  # >100 errors/min
      relative_threshold 3.0  # 3x normal rate
      
      on_spike do
        sample_rate 1.0  # 100% during errors
        duration 10.minutes
        exponential_decay true  # Gradual return
      end
      
      baseline_window 1.hour
      baseline_calculation :p95  # Use p95 as baseline
    end
    
    # Protect from overload
    load_based_sampling do
      tiers [
        { threshold: 0,      sample_rate: 1.0 },
        { threshold: 10_000, sample_rate: 0.5 },
        { threshold: 50_000, sample_rate: 0.1 }
      ]
      transition_period 30.seconds
      hysteresis 0.2  # 20% buffer
    end
    
    # Priority: Always sample payment errors
    always_sample event_patterns: ['payment.*'],
                  severities: [:error, :fatal]
  end
end
```

### APIs / Interfaces
- `base_sample_rate(float)` - Default sampling rate (0.0-1.0)
- `on_error_spike(&block)` - Error-based sampling configuration
- `on_high_load(&block)` - Load-based sampling configuration
- `sample_by_value(&block)` - Value-based sampling configuration
- `always_sample(severities:, event_patterns:)` - Never drop critical events
- `never_sample(patterns:)` - Always drop specific patterns
- `trace_consistent(&block)` - Trace-consistent sampling configuration
- `stratified_rates(&block)` - Stratified sampling by severity (C11)
- `E11y.with_sampling_override(context, sample_rate, duration)` - Temporary override (debugging)
- `E11y.current_sample_rate` - Get current effective sample rate

### Data Structures
- **SamplerState:** Current sample rate, active strategy, transition timestamp
- **ErrorSpikeState:** Baseline error rate, current error rate, spike detected flag
- **LoadTierState:** Current load (events/sec), current tier, transition in progress
- **TraceDecision:** Sample decision (true/false), propagation metadata (trace_id, sampled)
- **StratifiedRates:** Map of severity → sample rate (error: 1.0, warn: 0.5, info: 0.1, debug: 0.05)

---

## ❓ Questions & Gaps

### Clarification Needed
1. **Tail-based sampling latency:** Does tail-based sampling decision block HTTP response? Or is decision async (response sent, buffer flushed/discarded)?
2. **ML-based sampling cold start:** What happens during first 7 days before model trained? Fallback to 10% or disable ML strategy?
3. **Trace-consistent sampling orphaned jobs:** What's the default sample rate for orphaned jobs (cron jobs, manual triggers without parent trace)?

### Missing Information
1. **Error spike detection baseline:** How is p95 baseline calculated? Simple percentile or exponential moving average?
2. **Load-based sampling event counting:** Is "events/sec" counted globally (all adapters) or per-adapter?
3. **Stratified sampling correction:** Is correction applied automatically in Prometheus queries, or manual via E11y::SLO::Calculator?

### Ambiguities
1. **"Always sample" vs. "Never sample"** - What happens if event matches both? Which takes precedence?
2. **"Trace-consistent propagation"** - Is X-E11y-Sampled header standard, or E11y-specific? Is it compatible with OpenTelemetry trace propagation?

---

## 🧪 Testing Considerations

### Test Scenarios
1. **Error spike detection:** Simulate 20 errors in 1 minute (absolute threshold: 10), verify sample rate → 1.0
2. **Load-based sampling:** Simulate 1500 events/sec (tier threshold: 1000), verify sample rate → 0.1
3. **Value-based sampling:** Track 100 high-value events (>$1000), verify all sampled (100%)
4. **Trace-consistent sampling:** HTTP request sampled → verify job also sampled (metadata propagation)
5. **Stratified sampling (C11):** Track 1000 events (950 success, 50 errors), verify: 50 errors + 95 success kept (145 total)
6. **SLO sampling correction:** Verify corrected error rate matches actual rate (not observed rate)
7. **Tail-based sampling:** Track request with error → verify ALL events in request kept (not just error event)

### Mocking Needs
- `rand` - Stub for testing probabilistic sampling
- `Time.now` - Stub for testing time-based strategies (error spike window, baseline calculation)
- `HTTP` - Mock for testing trace propagation (X-E11y-Sampled header)
- `Redis` - Mock for testing whitelist sampling (distributed state)

---

## 📊 Complexity Assessment

**Overall Complexity:** Complex

**Reasoning:**
- 8 different sampling strategies (error, load, value, content, tail, ML, trace-consistent, stratified)
- Error spike detection requires sliding window tracking, baseline calculation (p95), exponential decay
- Load-based sampling requires real-time event volume tracking, tiered transitions, hysteresis
- Trace-consistent sampling requires propagation across HTTP (headers), jobs (metadata), services (distributed state)
- Stratified sampling (C11) requires per-severity sample rates, sampling correction math (SLO calculator)
- Tail-based sampling requires buffering (30s max), request lifecycle tracking, decision evaluation
- ML-based sampling requires model training (7-day window), daily retraining, fallback strategy
- Self-monitoring (6+ metrics) requires understanding of sampling effectiveness

**Estimated Implementation Time:**
- Junior dev: 25-35 days (8 strategies, error detection, load tracking, trace propagation, C11, testing)
- Senior dev: 15-20 days (familiar with distributed tracing, sampling theory, ML)

---

## 📚 References

### Related Documentation
- [UC-001: Request-Scoped Debug Buffering](./UC-001-request-scoped-debug-buffering.md) - sample_on_error + buffering
- [UC-004: SLO Tracking with Sampling Correction](./UC-004-zero-config-slo-tracking.md#sampling-correction-for-accurate-slo-c11-resolution) - Stratified sampling (C11)
- [UC-006: Trace Context Management](./UC-006-trace-context-management.md) - Trace propagation implementation
- [UC-011: Rate Limiting](./UC-011-rate-limiting.md) - Complementary with sampling
- [UC-015: Cost Optimization](./UC-015-cost-optimization.md) - Cost reduction strategies
- [ADR-009 Section 3: Adaptive Sampling](../ADR-009-cost-optimization.md#3-adaptive-sampling) - All 8 strategies architecture
- [ADR-009 §3.7: Stratified Sampling for SLO Accuracy](../ADR-009-cost-optimization.md#37-stratified-sampling-for-slo-accuracy-c11-resolution) - C11 resolution

### Similar Solutions
- **OpenTelemetry Sampling** - Parent-based, trace-ID-based (but no adaptive strategies)
- **Datadog APM Sampling** - Error-based priority sampling (vendor-specific)
- **Honeycomb Sampling** - Tail-based sampling (but proprietary)

### Research Notes
- **Cost savings (lines 1067-1076):**
  - Normal: 0% savings (same 10%)
  - Error spike: Better data quality (100% vs. 10%)
  - High load: 90% savings (1% vs. 10%)
  - Black Friday: 35% savings (6.5% effective vs. 10%)
- **Stratified sampling (C11) cost impact (lines 601-614):**
  - Without stratified: $10,000/month (100% all events)
  - With stratified: $1,450/month (85.5% savings) + 100% SLO accuracy
- **Trace-consistent sampling importance (lines 534-541):**
  - Without: Orphaned job events (parent HTTP dropped, job 10% chance)
  - With: Complete traces (both sampled or both dropped)

---

## 🏷️ Tags

`#critical` `#performance` `#adaptive-sampling` `#8-strategies` `#cost-optimization` `#trace-consistent` `#stratified-c11` `#slo-accuracy` `#error-spike` `#load-based`

---

**Last Updated:** 2026-01-15  
**Next Review:** Before implementation start (Phase 3 - Consolidated Analysis)
