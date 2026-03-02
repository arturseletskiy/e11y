# UC-004 Zero-Config SLO Tracking: Integration Test Plan

**Task:** FEAT-5404 - UC-004 Phase 2: Planning Complete  
**Date:** 2026-01-26  
**Status:** Planning Complete

---

## 📋 Executive Summary

**Test Strategy:** Event-based integration tests using Rails dummy app, following pattern from rate limiting and high cardinality protection integration tests.

**Scope:** 8 core scenarios covering availability, latency P95/P99, error rate, error budget, time windows, breach detection, and multi-window burn rate alerts.

**Test Infrastructure:** Rails dummy app (`spec/dummy`), HTTP request simulation, Yabeda/Prometheus integration, SLO::Tracker, time series test data.

**Note:** Tests focus on SLO metric emission and verification. SLO calculations are Prometheus-based (not E11y-native), so tests verify metrics are emitted correctly and can be used for SLO calculation.

---

## 🎯 Test Strategy Overview

### 1. Test Approach

**Pattern:** Follow `spec/integration/rate_limiting_integration_spec.rb` and `spec/integration/high_cardinality_protection_integration_spec.rb` structure

**Key Components:**
- Rails dummy app (`spec/dummy`)
- HTTP request simulation (via `SLO::Tracker.track_http_request`)
- Background job simulation (via `SLO::Tracker.track_background_job`)
- Yabeda adapter for Prometheus metrics export
- In-memory adapter for event capture (verify events tracked)
- Yabeda metrics inspection (verify SLO metrics exported correctly)

**Test Structure:**
```ruby
RSpec.describe "Zero-Config SLO Tracking Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }
  let(:yabeda_adapter) { E11y.config.adapters[:yabeda] }
  
  before do
    memory_adapter.clear!
    Yabeda.reset! if defined?(Yabeda)
    
    # Enable SLO tracking
    E11y.configure do |config|
      config.slo_tracking.enabled = true
    end
    
    # Configure Yabeda adapter
    yabeda_adapter_instance = E11y::Adapters::Yabeda.new(...)
    E11y.config.adapters[:yabeda] = yabeda_adapter_instance
    
    # Configure Yabeda metrics
    Yabeda.configure do
      group :e11y do
        counter :slo_http_requests_total, tags: [:controller, :action, :status]
        histogram :slo_http_request_duration_seconds, tags: [:controller, :action]
        counter :slo_background_jobs_total, tags: [:job_class, :status, :queue]
        histogram :slo_background_job_duration_seconds, tags: [:job_class, :queue]
      end
    end
    Yabeda.configure!
    
    E11y.config.fallback_adapters = [:memory, :yabeda]
  end
  
  after do
    memory_adapter.clear!
    Yabeda.reset! if defined?(Yabeda)
  end
  
  describe "Scenario 1: Availability SLO" do
    # Test implementation
  end
  
  # ... other scenarios
end
```

### 2. Assertion Strategy

**SLO Calculation Assertions (with ±0.01% tolerance):**
- ✅ Availability: `expect(availability).to be_within(0.0001).of(expected)` (±0.01%)
- ✅ Latency P95: `expect(p95_latency).to be_within(1).of(expected)` (±1ms)
- ✅ Latency P99: `expect(p99_latency).to be_within(1).of(expected)` (±1ms)
- ✅ Error rate: `expect(error_rate).to be_within(0.0001).of(expected)` (±0.01%)

**Metric Emission Assertions:**
- ✅ Request count: `expect(Yabeda.e11y.slo_http_requests_total.get(...)).to eq(expected_count)`
- ✅ Histogram buckets: `expect(histogram_data).to be_a(Hash)` (buckets present)
- ✅ Labels extracted: Verify controller, action, status labels

**Time Series Assertions:**
- ✅ Time window respected: Data outside window excluded
- ✅ Aggregation correct: Sum/rate calculations accurate

---

## 📊 8 Core Integration Test Scenarios

### Scenario 1: Availability SLO

**Objective:** Verify availability SLO calculation (successes/total).

**Setup:**
- SLO target: 99.9% availability
- Time window: 30 days
- Track 1000 HTTP requests: 950 success (2xx), 50 errors (5xx)

**Test Steps:**
1. Enable SLO tracking
2. Track 1000 HTTP requests:
   - 950 requests: `status: 200` (success)
   - 50 requests: `status: 500` (error)
3. Calculate availability: `(950 / 1000) = 0.95 = 95%`
4. Verify SLO breach: `95% < 99.9%` (breach detected)
5. Verify error budget consumed

**Assertions:**
- Availability calculated: `expect(availability).to be_within(0.0001).of(0.95)`
- SLO breach detected: `expect(slo_breached).to be(true)`
- Error budget consumed: `expect(error_budget_consumed).to be > 0`
- Metrics emitted: `expect(Yabeda.e11y.slo_http_requests_total.get(status: "2xx")).to eq(950)`

**Test Data:**
- Requests: 1000 total
  - Success: 950 (status: 200)
  - Errors: 50 (status: 500)
- Expected availability: `0.95` (95%)
- Expected breach: `true` (95% < 99.9%)

---

### Scenario 2: Latency P95 SLO

**Objective:** Verify latency P95 calculation from histogram.

**Setup:**
- SLO target: P95 < 300ms
- Track HTTP requests with various durations

**Test Steps:**
1. Enable SLO tracking
2. Track HTTP requests with durations: `[50, 100, 150, 200, 250, 300, 350, 400, 450, 500]` ms (100 requests each)
3. Calculate P95 latency from histogram: Should be ~450ms (95th percentile)
4. Verify SLO breach: `P95 > 300ms` (breach detected)

**Assertions:**
- P95 calculated: `expect(p95_latency).to be_within(1).of(450)` (±1ms tolerance)
- SLO breach detected: `expect(p95_latency).to be > 300`
- Histogram buckets updated: Verify histogram data in Yabeda

**Test Data:**
- Durations: `[50, 100, 150, 200, 250, 300, 350, 400, 450, 500]` ms
- Count per duration: 100 requests each (1000 total)
- Expected P95: ~450ms (95th percentile of sorted durations)
- Expected breach: `true` (450ms > 300ms)

---

### Scenario 3: Latency P99 SLO

**Objective:** Verify latency P99 calculation from histogram.

**Setup:**
- SLO target: P99 < 500ms
- Track HTTP requests with various durations including outliers

**Test Steps:**
1. Enable SLO tracking
2. Track HTTP requests with durations: `[50, 100, 150, 200, 250, 300, 350, 400, 450, 500, 600, 700, 800, 900, 1000]` ms
3. Calculate P99 latency from histogram: Should be ~990ms (99th percentile)
4. Verify SLO breach: `P99 > 500ms` (breach detected)

**Assertions:**
- P99 calculated: `expect(p99_latency).to be_within(1).of(990)` (±1ms tolerance)
- SLO breach detected: `expect(p99_latency).to be > 500`
- Outliers handled: P99 reflects tail latency correctly

**Test Data:**
- Durations: `[50, 100, 150, 200, 250, 300, 350, 400, 450, 500, 600, 700, 800, 900, 1000]` ms
- Count per duration: 66 requests each (990 total, 10 requests at 1000ms for P99)
- Expected P99: ~990ms (99th percentile)
- Expected breach: `true` (990ms > 500ms)

---

### Scenario 4: Error Rate SLO

**Objective:** Verify error rate calculation (errors/total).

**Setup:**
- SLO target: Error rate < 1%
- Track HTTP requests with various status codes

**Test Steps:**
1. Enable SLO tracking
2. Track 1000 HTTP requests:
   - 990 requests: `status: 200` (success)
   - 10 requests: `status: 500` (error)
3. Calculate error rate: `(10 / 1000) = 0.01 = 1%`
4. Verify SLO breach: `1% >= 1%` (breach detected at threshold)

**Assertions:**
- Error rate calculated: `expect(error_rate).to be_within(0.0001).of(0.01)` (±0.01% tolerance)
- SLO breach detected: `expect(error_rate).to be >= 0.01`
- Error budget consumed: `expect(error_budget_consumed).to be > 0`

**Test Data:**
- Requests: 1000 total
  - Success: 990 (status: 200)
  - Errors: 10 (status: 500)
- Expected error rate: `0.01` (1%)
- Expected breach: `true` (1% >= 1%)

---

### Scenario 5: Error Budget Calculation

**Objective:** Verify error budget calculation and consumption.

**Setup:**
- SLO target: 99.9% availability
- Time window: 30 days
- Error budget: `(1 - 0.999) * 30_days = 43.2 minutes`

**Test Steps:**
1. Enable SLO tracking
2. Track HTTP requests with errors
3. Calculate error budget: `(target - actual) * window_duration`
4. Calculate consumed budget: Track error durations
5. Verify budget remaining: `budget - consumed`

**Assertions:**
- Error budget calculated: `expect(error_budget).to be_within(0.1).of(43.2.minutes)` (±0.1 minute tolerance)
- Budget consumed: `expect(budget_consumed).to be > 0`
- Budget remaining: `expect(budget_remaining).to be < error_budget`

**Test Data:**
- SLO target: `0.999` (99.9%)
- Time window: `30.days`
- Error budget: `(1 - 0.999) * 30.days = 43.2.minutes`
- Track errors with durations: `[100, 200, 300]` ms
- Expected consumed: Sum of error durations

---

### Scenario 6: Time Window Aggregation

**Objective:** Verify SLO calculation over different time windows.

**Setup:**
- Multiple time windows: 7d, 30d, 90d
- Time series data: Hourly data points for 90 days

**Test Steps:**
1. Enable SLO tracking
2. Generate time series data: Hourly HTTP requests for 90 days
   - Each hour: 100 requests (95 success, 5 errors)
   - Availability: 95% per hour
3. Calculate SLO for each window:
   - 7-day window: Last 7 days (168 hours)
   - 30-day window: Last 30 days (720 hours)
   - 90-day window: Last 90 days (2160 hours)
4. Verify window-specific calculations

**Assertions:**
- 7-day window: `expect(availability_7d).to be_within(0.0001).of(0.95)`
- 30-day window: `expect(availability_30d).to be_within(0.0001).of(0.95)`
- 90-day window: `expect(availability_90d).to be_within(0.0001).of(0.95)`
- Window boundaries: Old data excluded from calculations

**Test Data:**
- Time series: 90 days × 24 hours = 2160 data points
- Each hour: 100 requests (95 success, 5 errors)
- Availability per hour: `0.95` (95%)
- Expected availability (all windows): `0.95` (95%)

---

### Scenario 7: Breach Detection

**Objective:** Verify SLO breach detection (actual < target).

**Setup:**
- SLO target: 99.9% availability
- Track HTTP requests below target

**Test Steps:**
1. Enable SLO tracking
2. Track HTTP requests: 95% availability (below 99.9% target)
   - 950 requests: `status: 200` (success)
   - 50 requests: `status: 500` (error)
3. Detect SLO breach: `95% < 99.9%`
4. Verify breach status and error budget impact

**Assertions:**
- Breach detected: `expect(slo_breached).to be(true)`
- Breach duration: `expect(breach_duration).to be > 0` (if tracked)
- Error budget impacted: `expect(error_budget_consumed).to be > 0`

**Test Data:**
- Requests: 1000 total
  - Success: 950 (status: 200)
  - Errors: 50 (status: 500)
- Availability: `0.95` (95%)
- SLO target: `0.999` (99.9%)
- Expected breach: `true` (95% < 99.9%)

---

### Scenario 8: Multi-Window Burn Rate Alerts

**Objective:** Verify multi-window burn rate alert detection.

**Setup:**
- Burn rate windows: 1h, 6h, 24h, 3d
- Burn rate thresholds: 14.4x (fast), 6.0x (medium), 1.0x (slow)
- SLO target: 99.9% availability

**Test Steps:**
1. Enable SLO tracking
2. Simulate high error rate: Track requests with 50% error rate (burning budget quickly)
3. Calculate burn rate for each window:
   - 1h window: `burn_rate = error_rate / (1 - target) = 0.5 / 0.001 = 500x`
   - 6h window: `burn_rate = 0.5 / 0.001 = 500x`
   - 24h window: `burn_rate = 0.5 / 0.001 = 500x`
   - 3d window: `burn_rate = 0.5 / 0.001 = 500x`
4. Verify alerts triggered at thresholds

**Assertions:**
- Fast burn rate: `expect(burn_rate_1h).to be > 14.4` (alert triggered)
- Medium burn rate: `expect(burn_rate_6h).to be > 6.0` (alert triggered)
- Slow burn rate: `expect(burn_rate_3d).to be > 1.0` (alert triggered)
- Alert timing: Alerts fire after `alert_after` duration (if tracked)

**Test Data:**
- Error rate: `0.5` (50%)
- SLO target: `0.999` (99.9%)
- Burn rate: `0.5 / (1 - 0.999) = 0.5 / 0.001 = 500x`
- Thresholds:
  - Fast: `14.4x` → Alert triggered (500x > 14.4x)
  - Medium: `6.0x` → Alert triggered (500x > 6.0x)
  - Slow: `1.0x` → Alert triggered (500x > 1.0x)

---

## 📝 Test Data Requirements

### Time Series Data

**Required Time Series:**
- **Hourly data points for 30 days**: 30 days × 24 hours = 720 data points
- **Each hour**: 100 requests (configurable success/error ratio)
- **Timestamps**: Sequential hourly timestamps over 30-day period

**Example Time Series Generation:**
```ruby
# Generate 30 days of hourly data
start_time = 30.days.ago
30.times do |day|
  24.times do |hour|
    timestamp = start_time + day.days + hour.hours
    
    # Track requests for this hour
    100.times do
      E11y::SLO::Tracker.track_http_request(
        controller: 'OrdersController',
        action: 'create',
        status: rand < 0.95 ? 200 : 500,  # 95% success rate
        duration_ms: rand(50..500)
      )
    end
  end
end
```

### HTTP Request Data

**Required Request Data:**
- Success requests: Status 200-299 (2xx) - various counts
- Redirect requests: Status 300-399 (3xx) - optional
- Client errors: Status 400-499 (4xx) - optional
- Server errors: Status 500-599 (5xx) - various counts
- Durations: `[50, 100, 150, 200, 250, 300, 350, 400, 450, 500]` ms (for latency tests)

### Background Job Data

**Required Job Data:**
- Success jobs: `status: :success` - various counts
- Failed jobs: `status: :failed` - various counts
- Durations: `[100, 500, 1000, 5000, 10000]` ms
- Queue names: `['default', 'critical', 'low']`

### SLO Configuration

**Required SLO Config:**
- Availability target: `0.999` (99.9%)
- Latency P95 target: `300` ms
- Latency P99 target: `500` ms
- Error rate target: `0.01` (1%)
- Time windows: `7d`, `30d`, `90d`
- Burn rate thresholds: `14.4x` (fast), `6.0x` (medium), `1.0x` (slow)

---

## ✅ Definition of Done

**Planning is complete when:**
1. ✅ All 8 scenarios planned with detailed test steps
2. ✅ Time series test data requirements documented (hourly data points for 30 days)
3. ✅ Assertion strategy defined with ±0.01% tolerance
4. ✅ Test infrastructure requirements documented
5. ✅ SLO calculation formulas documented for each scenario
6. ✅ Test structure follows existing integration test patterns

---

## 📚 References

- **UC-004 Analysis:** `docs/analysis/UC-004-ZERO-CONFIG-SLO-TRACKING-ANALYSIS.md`
- **UC-004 Use Case:** `docs/use_cases/UC-004-zero-config-slo-tracking.md`
- **Integration Tests:** `spec/integration/slo_tracking_integration_spec.rb` ✅ (All 8 scenarios implemented)
- **ADR-003:** `docs/ADR-003-slo-observability.md`
- **Tracker Implementation:** `lib/e11y/slo/tracker.rb`
- **Yabeda Adapter:** `lib/e11y/adapters/yabeda.rb`
- **Rate Limiting Tests:** `spec/integration/rate_limiting_integration_spec.rb` (reference pattern)
- **High Cardinality Tests:** `spec/integration/high_cardinality_protection_integration_spec.rb` (reference pattern)

---

**Planning Complete:** 2026-01-26  
**Next Step:** UC-004 Phase 3: Skeleton Complete
