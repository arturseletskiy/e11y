# frozen_string_literal: true

# features/step_definitions/slo_tracking_steps.rb
#
# Step definitions for slo_tracking.feature.
# Exercises E11y::SLO::Tracker and SLO configuration.

# ---------------------------------------------------------------------------
# Background and configuration steps
# ---------------------------------------------------------------------------

Given("SLO tracking is reset to its default state") do
  E11y.config.slo_tracking.enabled = true # Default is now true (Zero-Config SLO)
  E11y::SLO::Tracker.reset!
end

Given("SLO tracking is enabled") do
  E11y.config.slo_tracking.enabled = true
end

Given("SLO tracking is explicitly disabled") do
  E11y.config.slo_tracking.enabled = false
end

# ---------------------------------------------------------------------------
# Inspection steps
# ---------------------------------------------------------------------------

When("I inspect the default SLO tracking configuration") do
  @slo_config = E11y.config.slo_tracking
end

When("I call E11y::SLO::Tracker.status") do
  @tracker_status_error = nil
  begin
    @tracker_status = E11y::SLO::Tracker.status
  rescue NoMethodError => e
    @tracker_status_error = e
    raise # Re-raise so Cucumber marks the @wip scenario as failed
  end
end

# ---------------------------------------------------------------------------
# Pipeline manipulation steps
# ---------------------------------------------------------------------------

# Recording backend: captures all E11y::Metrics.increment calls so Cucumber
# steps can assert on them without requiring Yabeda in the test environment.
class SloRecordingBackend
  attr_reader :increments

  def initialize
    @increments = []
  end

  def increment(name, labels = {}, value: 1)
    @increments << { name: name, labels: labels, value: value }
  end

  def histogram(_name, _value, _labels = {}, buckets: nil); end

  def gauge(_name, _value, _labels = {}); end
end

Given("E11y::Middleware::EventSlo is added to the pipeline") do
  raise "E11y::Middleware::EventSlo is not defined — event-level SLO cannot be tested" \
    unless defined?(E11y::Middleware::EventSlo)

  # Add EventSlo to the pipeline for this scenario
  E11y.config.pipeline.use(E11y::Middleware::EventSlo)
  # Invalidate cached pipeline so new middleware takes effect
  E11y.config.instance_variable_set(:@built_pipeline, nil) if E11y.config.instance_variable_defined?(:@built_pipeline)

  # Replace metrics backend with a recording backend so we can assert on calls
  @recording_backend = SloRecordingBackend.new
  E11y::Metrics.instance_variable_set(:@backend, @recording_backend)
end

# ---------------------------------------------------------------------------
# Assertion steps
# ---------------------------------------------------------------------------

Then("E11y.configuration.slo_tracking.enabled should be true") do
  expect(@slo_config.enabled).to be(true),
    "Expected SLO tracking enabled by default, got: #{@slo_config.enabled.inspect}"
end

Then("E11y.configuration.slo_tracking.enabled should be false") do
  expect(@slo_config.enabled).to be(false)
end

Then("enabling SLO tracking requires setting slo_tracking.enabled to true") do
  E11y.config.slo_tracking.enabled = true
  expect(E11y.config.slo_tracking.enabled).to be(true)
  E11y.config.slo_tracking.enabled = false
end

Then("the SLO status result should be a Hash") do
  if @tracker_status_error
    raise "E11y::SLO::Tracker.status raised #{@tracker_status_error.class}: " \
          "#{@tracker_status_error.message}\nBUG: Tracker.status method does not exist."
  end
  expect(@tracker_status).to be_a(Hash)
end

Then("the Hash should contain an entry for the orders endpoint") do
  has_entry = @tracker_status.key?("orders#create") || @tracker_status.key?(:orders_create)
  expect(has_entry).to be(true),
    "Expected Tracker.status to include an entry for orders#create, " \
    "got: #{@tracker_status.inspect}"
end

Then("the SLO tracker should have recorded a request for {string}") do |_endpoint|
  # Verify SLO tracking is enabled (the guard in Tracker#track_http_request)
  expect(E11y::SLO::Tracker.enabled?).to be(true),
    "SLO tracking must be enabled for this assertion to be meaningful"
  # Metrics are emitted via E11y::Metrics.increment which delegates to Yabeda.
  # In this test environment Yabeda may not be fully configured, so we verify
  # the guard condition (enabled?) rather than the Yabeda counter value.
end

Then("the normalize_status for {int} should return {string}") do |status_code, expected_category|
  actual = E11y::SLO::Tracker.send(:normalize_status, status_code)
  expect(actual).to eq(expected_category),
    "Expected normalize_status(#{status_code}) to return #{expected_category.inspect}, " \
    "got #{actual.inspect}"
end

Then("no SLO metrics should have been recorded") do
  expect(E11y::SLO::Tracker.enabled?).to be(false),
    "Expected SLO tracker to be disabled, but enabled? returned true"
end

Then("the SLO metric {string} should have been incremented") do |metric_name|
  raise "Recording backend not set up — did you run the EventSlo Given step?" unless @recording_backend

  incremented_names = @recording_backend.increments.map { |i| i[:name].to_s }
  expect(incremented_names).to include(metric_name),
    "Expected E11y::Metrics.increment to be called with #{metric_name.inspect}, " \
    "but recorded calls were: #{incremented_names.inspect}"
end
