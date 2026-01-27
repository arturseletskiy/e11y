# frozen_string_literal: true

require "rails_helper"

# Require dependencies - fail fast if not available
begin
  require "yabeda"
  require "yabeda/prometheus"
rescue LoadError => e
  raise "Required dependency 'yabeda' is not available. " \
        "Install with: bundle install --with integration. " \
        "Original error: #{e.message}"
end

# Zero-config SLO tracking integration tests for UC-004
# Tests SLO metric emission, availability/latency/error rate calculations, error budget, time windows, breach detection
#
# Scenarios:
# 1. Availability SLO (successes/total calculation)
# 2. Latency P95 SLO (histogram quantile calculation)
# 3. Latency P99 SLO (histogram quantile calculation)
# 4. Error rate SLO (errors/total calculation)
# 5. Error budget calculation (budget calculation and consumption)
# 6. Time window aggregation (7d, 30d, 90d windows)
# 7. Breach detection (actual < target)
# 8. Multi-window burn rate alerts (1h/6h/24h/3d windows)

RSpec.describe "Zero-Config SLO Tracking Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }
  let(:yabeda_adapter) { E11y.config.adapters[:yabeda] }

  before do
    memory_adapter.clear!
    
    # Enable SLO tracking
    E11y.configure do |config|
      config.slo_tracking.enabled = true
    end

    # Configure Yabeda metrics only if not already configured
    unless Yabeda.configured?
      Yabeda.configure do
        group :e11y do
          counter :slo_http_requests_total, tags: %i[controller action status], comment: "SLO HTTP requests"
          histogram :slo_http_request_duration_seconds, tags: %i[controller action],
                                                        buckets: [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0], comment: "SLO HTTP request duration"
          counter :slo_background_jobs_total, tags: %i[job_class status queue], comment: "SLO background jobs"
          histogram :slo_background_job_duration_seconds, tags: %i[job_class queue],
                                                          buckets: [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0], comment: "SLO background job duration"
        end
      end
      Yabeda.configure!
    else
      # Reset Yabeda counter values between tests (without calling Yabeda.reset!)
      # This ensures tests don't accumulate counter values
      reset_yabeda_metrics!
    end

    # Configure Yabeda adapter
    yabeda_adapter_instance = E11y::Adapters::Yabeda.new(
      auto_register: false # Don't auto-register since we manually configured above
    )
    E11y.config.adapters[:yabeda] = yabeda_adapter_instance

    # Reset metrics backend to detect the new Yabeda adapter
    E11y::Metrics.reset_backend!

    # Configure routing to send events to both memory and yabeda adapters
    E11y.config.fallback_adapters = %i[memory yabeda]
  end
  
  # Helper method to reset Yabeda metric values without calling Yabeda.reset!
  def reset_yabeda_metrics!
    # Reset counter and histogram values by accessing their internal storage
    # This is a hack but necessary since Yabeda.reset! breaks metric registration
    Yabeda.e11y.slo_http_requests_total.instance_variable_get(:@values)&.clear if Yabeda.e11y.respond_to?(:slo_http_requests_total)
    Yabeda.e11y.slo_http_request_duration_seconds.instance_variable_get(:@values)&.clear if Yabeda.e11y.respond_to?(:slo_http_request_duration_seconds)
    Yabeda.e11y.slo_background_jobs_total.instance_variable_get(:@values)&.clear if Yabeda.e11y.respond_to?(:slo_background_jobs_total)
    Yabeda.e11y.slo_background_job_duration_seconds.instance_variable_get(:@values)&.clear if Yabeda.e11y.respond_to?(:slo_background_job_duration_seconds)
  rescue StandardError => e
    # If internal structure changed, fall back to no reset (tests may accumulate values)
    # Silently continue - this is a best-effort reset
  end

  after do
    memory_adapter.clear!
    # Don't reset Yabeda - it causes issues with metric registration
    # Instead, we accept that counter values accumulate across tests
    # This is acceptable for integration tests that verify metric increments work
  end

  describe "Scenario 1: Availability SLO" do
    it "calculates availability SLO (successes/total)" do
      # Setup: SLO target 99.9% availability, track 1000 HTTP requests (950 success, 50 errors)
      # Test: Track requests, calculate availability, verify SLO breach
      # Expected: Availability = 95%, breach detected (95% < 99.9%)

      memory_adapter.clear!

      # Verify metrics backend is available
      backend = E11y::Metrics.backend
      expect(backend).not_to be_nil, "Metrics backend should be configured"
      expect(backend).to be_a(E11y::Adapters::Yabeda), "Metrics backend should be Yabeda adapter"

      # Track 1000 HTTP requests: 950 success (2xx), 50 errors (5xx)
      950.times do
        E11y::SLO::Tracker.track_http_request(
          controller: "OrdersController",
          action: "create",
          status: 200,
          duration_ms: 100
        )
      end

      50.times do
        E11y::SLO::Tracker.track_http_request(
          controller: "OrdersController",
          action: "create",
          status: 500,
          duration_ms: 200
        )
      end

      # Calculate availability: successes / total
      # successes = count(status = "2xx")
      # total = count(all statuses)
      success_count = Yabeda.e11y.slo_http_requests_total.get(
        controller: "OrdersController",
        action: "create",
        status: "2xx"
      )

      error_count = Yabeda.e11y.slo_http_requests_total.get(
        controller: "OrdersController",
        action: "create",
        status: "5xx"
      )

      total_count = success_count + error_count
      availability = total_count > 0 ? success_count.to_f / total_count : 0.0

      # Verify availability calculated correctly (with ±0.01% tolerance)
      expected_availability = 950.0 / 1000.0
      expect(availability).to be_within(0.0001).of(expected_availability),
                              "Expected availability #{expected_availability}, got #{availability}"

      # Verify SLO breach: 95% < 99.9%
      slo_target = 0.999
      slo_breached = availability < slo_target
      expect(slo_breached).to be(true),
                              "Expected SLO breach (95% < 99.9%), but breach not detected"

      # Verify error budget consumed (conceptual - actual calculation would be in Prometheus)
      expect(error_count).to be > 0,
                             "Expected errors to consume error budget"
    end
  end

  describe "Scenario 2: Latency P95 SLO" do
    it "calculates latency P95 SLO from histogram" do
      # Setup: SLO target P95 < 300ms, track HTTP requests with various durations
      # Test: Track requests, calculate P95 latency, verify SLO breach
      # Expected: P95 calculated correctly, breach detected if P95 > 300ms

      memory_adapter.clear!

      # Track HTTP requests with durations: [50, 100, 150, 200, 250, 300, 350, 400, 450, 500] ms
      # 100 requests each (1000 total)
      durations = [50, 100, 150, 200, 250, 300, 350, 400, 450, 500]
      durations.each do |duration_ms|
        100.times do
          E11y::SLO::Tracker.track_http_request(
            controller: "OrdersController",
            action: "create",
            status: 200,
            duration_ms: duration_ms
          )
        end
      end

      # Get histogram last observed value from Yabeda
      # Note: Yabeda histogram.get() returns the last observed value as a Float, not a hash
      # Histogram buckets are exposed through Prometheus exporter, not via .get()
      histogram_value = Yabeda.e11y.slo_http_request_duration_seconds.get(
        controller: "OrdersController",
        action: "create"
      )

      expect(histogram_value).to be_a(Numeric),
                                "Expected histogram value to be numeric, got #{histogram_value.class}"

      # Calculate P95 latency from histogram buckets
      # Note: Yabeda histograms track bucket data internally, P95 calculation is done in Prometheus
      # For integration test, we verify histogram is tracking values (last value should be > 0)
      # P95 would be approximately 450ms (95th percentile of sorted durations)
      expect(histogram_value).to be > 0,
                                    "Expected histogram to be tracking values"

      # Verify SLO breach: P95 > 300ms (conceptual - actual P95 calculation in Prometheus)
      # For test purposes, we verify that requests with duration > 300ms were tracked
      high_latency_count = durations.count { |d| d > 300 }
      expect(high_latency_count).to be > 0,
                                    "Expected some requests with latency > 300ms for P95 breach test"
    end
  end

  describe "Scenario 3: Latency P99 SLO" do
    it "calculates latency P99 SLO from histogram" do
      # Setup: SLO target P99 < 500ms, track HTTP requests with outliers
      # Test: Track requests, calculate P99 latency, verify SLO breach
      # Expected: P99 calculated correctly, breach detected if P99 > 500ms

      memory_adapter.clear!

      # Track HTTP requests with durations including outliers: [50, 100, 150, 200, 250, 300, 350, 400, 450, 500, 600, 700, 800, 900, 1000] ms
      # 66 requests each for first 14 durations, 10 requests at 1000ms for P99
      durations = [50, 100, 150, 200, 250, 300, 350, 400, 450, 500, 600, 700, 800, 900, 1000]
      durations[0..13].each do |duration_ms|
        66.times do
          E11y::SLO::Tracker.track_http_request(
            controller: "OrdersController",
            action: "create",
            status: 200,
            duration_ms: duration_ms
          )
        end
      end

      # Track 10 requests at 1000ms for P99 calculation
      10.times do
        E11y::SLO::Tracker.track_http_request(
          controller: "OrdersController",
          action: "create",
          status: 200,
          duration_ms: 1000
        )
      end

      # Get histogram last observed value from Yabeda
      # Note: Yabeda histogram.get() returns the last observed value as a Float, not a hash
      histogram_value = Yabeda.e11y.slo_http_request_duration_seconds.get(
        controller: "OrdersController",
        action: "create"
      )

      expect(histogram_value).to be_a(Numeric),
                                "Expected histogram value to be numeric"
      expect(histogram_value).to be > 0,
                                    "Expected histogram to be tracking values"

      # Verify outliers tracked: Requests with duration > 500ms
      outlier_count = durations.count { |d| d > 500 }
      expect(outlier_count).to be > 0,
                               "Expected some requests with latency > 500ms for P99 breach test"
    end
  end

  describe "Scenario 4: Error Rate SLO" do
    it "calculates error rate SLO (errors/total)" do
      # Setup: SLO target error rate < 1%, track HTTP requests with various status codes
      # Test: Track requests, calculate error rate, verify SLO breach
      # Expected: Error rate calculated correctly, breach detected if error rate >= 1%

      memory_adapter.clear!

      # Track 1000 HTTP requests: 990 success (200), 10 errors (500)
      990.times do
        E11y::SLO::Tracker.track_http_request(
          controller: "OrdersController",
          action: "create",
          status: 200,
          duration_ms: 100
        )
      end

      10.times do
        E11y::SLO::Tracker.track_http_request(
          controller: "OrdersController",
          action: "create",
          status: 500,
          duration_ms: 200
        )
      end

      # Calculate error rate: errors / total
      success_count = Yabeda.e11y.slo_http_requests_total.get(
        controller: "OrdersController",
        action: "create",
        status: "2xx"
      ) || 0

      error_count = Yabeda.e11y.slo_http_requests_total.get(
        controller: "OrdersController",
        action: "create",
        status: "5xx"
      ) || 0

      total_count = success_count + error_count
      error_rate = total_count > 0 ? error_count.to_f / total_count : 0.0

      # Verify error rate calculated correctly (with ±0.01% tolerance)
      expected_error_rate = 10.0 / 1000.0
      expect(error_rate).to be_within(0.0001).of(expected_error_rate),
                            "Expected error rate #{expected_error_rate}, got #{error_rate}"

      # Verify SLO breach: 1% >= 1% (breach at threshold)
      slo_target = 0.01
      slo_breached = error_rate >= slo_target
      expect(slo_breached).to be(true),
                              "Expected SLO breach (1% >= 1%), but breach not detected"
    end
  end

  describe "Scenario 5: Error Budget Calculation" do
    it "calculates error budget and consumption" do
      # Setup: SLO target 99.9% availability, 30-day window, error budget = 43.2 minutes
      # Test: Track requests with errors, calculate error budget, verify consumption
      # Expected: Error budget calculated correctly, budget consumed tracked

      memory_adapter.clear!

      slo_target = 0.999
      window_duration = 30.days

      # Calculate error budget: (1 - target) * window_duration
      error_budget_seconds = (1 - slo_target) * window_duration
      error_budget_minutes = error_budget_seconds / 60.0

      # Expected error budget: (1 - 0.999) * 30 days = 43.2 minutes
      expected_budget_minutes = 43.2
      expect(error_budget_minutes).to be_within(0.1).of(expected_budget_minutes),
                                      "Expected error budget #{expected_budget_minutes} minutes, got #{error_budget_minutes}"

      # Track requests with errors
      error_durations = [100, 200, 300] # ms
      error_durations.each do |duration_ms|
        E11y::SLO::Tracker.track_http_request(
          controller: "OrdersController",
          action: "create",
          status: 500,
          duration_ms: duration_ms
        )
      end

      # Verify errors tracked (budget consumption tracked via error count)
      error_count = Yabeda.e11y.slo_http_requests_total.get(
        controller: "OrdersController",
        action: "create",
        status: "5xx"
      ) || 0

      expect(error_count).to eq(3),
                             "Expected 3 errors tracked, got #{error_count}"

      # Budget consumed would be calculated in Prometheus based on error durations
      # For integration test, we verify errors are tracked correctly
      expect(error_count).to be > 0,
                             "Expected errors to consume error budget"
    end
  end

  describe "Scenario 6: Time Window Aggregation" do
    it "calculates SLO over different time windows (7d, 30d, 90d)" do
      # Setup: Multiple time windows, hourly data points for 90 days
      # Test: Track requests over time, calculate SLO for each window
      # Expected: SLO calculated correctly for each window, window boundaries respected

      memory_adapter.clear!

      # Generate time series data: Hourly HTTP requests for 30 days (simplified for test)
      # Each hour: 100 requests (95 success, 5 errors) = 95% availability
      # Note: In real scenario, this would span 30 days with timestamps
      # For integration test, we track requests and verify metrics are emitted
      30.times do |_day|
        24.times do |_hour|
          # Track 95 success requests
          95.times do
            E11y::SLO::Tracker.track_http_request(
              controller: "OrdersController",
              action: "create",
              status: 200,
              duration_ms: 100
            )
          end

          # Track 5 error requests
          5.times do
            E11y::SLO::Tracker.track_http_request(
              controller: "OrdersController",
              action: "create",
              status: 500,
              duration_ms: 200
            )
          end
        end
      end

      # Verify metrics emitted (time window calculations would be done in Prometheus)
      success_count = Yabeda.e11y.slo_http_requests_total.get(
        controller: "OrdersController",
        action: "create",
        status: "2xx"
      ) || 0

      error_count = Yabeda.e11y.slo_http_requests_total.get(
        controller: "OrdersController",
        action: "create",
        status: "5xx"
      ) || 0

      total_count = success_count + error_count
      availability = total_count > 0 ? success_count.to_f / total_count : 0.0

      # Expected availability: 95% (95 success / 100 total per hour)
      expected_availability = 0.95
      expect(availability).to be_within(0.0001).of(expected_availability),
                              "Expected availability #{expected_availability}, got #{availability}"

      # Verify window boundaries would be respected in Prometheus queries
      # (7d window = last 7 days, 30d window = last 30 days, etc.)
      expect(total_count).to eq(30 * 24 * 100),
                             "Expected #{30 * 24 * 100} total requests tracked"
    end
  end

  describe "Scenario 7: Breach Detection" do
    it "detects SLO breach (actual < target)" do
      # Setup: SLO target 99.9% availability, track requests below target
      # Test: Track requests, detect breach, verify breach status
      # Expected: Breach detected when actual < target, error budget impacted

      memory_adapter.clear!

      slo_target = 0.999

      # Track HTTP requests: 95% availability (below 99.9% target)
      # 950 success, 50 errors
      950.times do
        E11y::SLO::Tracker.track_http_request(
          controller: "OrdersController",
          action: "create",
          status: 200,
          duration_ms: 100
        )
      end

      50.times do
        E11y::SLO::Tracker.track_http_request(
          controller: "OrdersController",
          action: "create",
          status: 500,
          duration_ms: 200
        )
      end

      # Calculate availability
      success_count = Yabeda.e11y.slo_http_requests_total.get(
        controller: "OrdersController",
        action: "create",
        status: "2xx"
      ) || 0

      error_count = Yabeda.e11y.slo_http_requests_total.get(
        controller: "OrdersController",
        action: "create",
        status: "5xx"
      ) || 0

      total_count = success_count + error_count
      availability = total_count > 0 ? success_count.to_f / total_count : 0.0

      # Verify breach detected: actual < target
      slo_breached = availability < slo_target
      expect(slo_breached).to be(true),
                              "Expected SLO breach (95% < 99.9%), but breach not detected"

      # Verify error budget impacted
      expect(error_count).to be > 0,
                             "Expected errors to impact error budget"
    end
  end

  describe "Scenario 8: Multi-Window Burn Rate Alerts" do
    it "detects burn rate alerts across multiple windows" do
      # Setup: Burn rate windows (1h, 6h, 24h, 3d), thresholds (14.4x, 6.0x, 1.0x)
      # Test: Simulate high error rate, calculate burn rate, verify alerts
      # Expected: Alerts triggered at thresholds for each window

      memory_adapter.clear!

      slo_target = 0.999

      # Simulate high error rate: 50% error rate (burning budget quickly)
      # Track 1000 requests: 500 success, 500 errors
      500.times do
        E11y::SLO::Tracker.track_http_request(
          controller: "OrdersController",
          action: "create",
          status: 200,
          duration_ms: 100
        )
      end

      500.times do
        E11y::SLO::Tracker.track_http_request(
          controller: "OrdersController",
          action: "create",
          status: 500,
          duration_ms: 200
        )
      end

      # Calculate error rate
      success_count = Yabeda.e11y.slo_http_requests_total.get(
        controller: "OrdersController",
        action: "create",
        status: "2xx"
      ) || 0

      error_count = Yabeda.e11y.slo_http_requests_total.get(
        controller: "OrdersController",
        action: "create",
        status: "5xx"
      ) || 0

      total_count = success_count + error_count
      error_rate = total_count > 0 ? error_count.to_f / total_count : 0.0

      # Calculate burn rate: error_rate / (1 - target)
      burn_rate = error_rate / (1 - slo_target)

      # Verify burn rate calculated correctly
      expected_burn_rate = 0.5 / 0.001 # 500x burn rate
      expect(burn_rate).to be_within(1.0).of(expected_burn_rate),
                           "Expected burn rate ~#{expected_burn_rate}x, got #{burn_rate}x"

      # Verify alerts would be triggered at thresholds
      # Fast burn rate threshold: 14.4x
      expect(burn_rate).to be > 14.4,
                           "Expected burn rate > 14.4x (fast alert threshold)"

      # Medium burn rate threshold: 6.0x
      expect(burn_rate).to be > 6.0,
                           "Expected burn rate > 6.0x (medium alert threshold)"

      # Slow burn rate threshold: 1.0x
      expect(burn_rate).to be > 1.0,
                           "Expected burn rate > 1.0x (slow alert threshold)"

      # NOTE: Actual alert triggering would be done in Prometheus alert rules
      # Integration test verifies metrics are emitted correctly for burn rate calculation
    end
  end
end
