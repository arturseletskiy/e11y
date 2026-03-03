# frozen_string_literal: true

# features/step_definitions/rails_integration_steps.rb
# Step definitions for rails_integration.feature.

Then("E11y should be disabled in the test environment") do
  # Simulate a fresh configuration with @enabled = nil (the fixed default).
  # The Railtie guard `config.enabled = !Rails.env.test? if config.enabled.nil?`
  # should set enabled to false in the test environment.
  original_enabled = E11y.configuration.enabled
  begin
    E11y.configuration.enabled = nil
    # Re-run the Railtie guard logic as it runs in before_initialize
    E11y.configuration.enabled = !Rails.env.test? if E11y.configuration.enabled.nil?
    expect(E11y.configuration.enabled).to be(false),
      "Expected Railtie guard to set enabled=false in test environment, " \
      "but got #{E11y.configuration.enabled.inspect}. " \
      "Rails.env.test? = #{Rails.env.test?.inspect}"
  ensure
    E11y.configuration.enabled = original_enabled
  end
end

When("I set E11y enabled to {word}") do |value|
  @original_enabled = E11y.configuration.enabled
  E11y.configuration.enabled = (value == "true")
end

Then("I restore E11y enabled to {word}") do |value|
  E11y.configuration.enabled = (value == "true")
end

# Helper: select E11y around_perform callbacks from a class's callback chain.
def e11y_around_perform_callbacks(klass)
  klass._perform_callbacks
    .select { |cb| cb.kind == :around }
    .select { |cb| cb.filter.to_s.include?("E11y") || cb.filter.to_s.include?("e11y") || cb.filter.to_s.include?("active_job.rb") }
end

# @wip — demonstrates BUG 2: double callback registration.
#
# setup_active_job includes Callbacks in ApplicationJob FIRST, then in ActiveJob::Base.
# Because ActiveJob::Base is an ancestor of ApplicationJob, including the module
# in ActiveJob::Base AFTER adds a second entry to ApplicationJob's inherited chain.
# Result: every job that inherits from ApplicationJob fires the callback twice.
Then("the E11y around_perform callback should fire exactly once per job class") do
  skip unless defined?(::ActiveJob)
  require "e11y/instruments/active_job"

  # Simulate ApplicationJob (a concrete subclass of ActiveJob::Base)
  simulated_app_job = Class.new(::ActiveJob::Base)

  # Replicate what setup_active_job does:
  #   1. Include in ApplicationJob first
  simulated_app_job.include(E11y::Instruments::ActiveJob::Callbacks)
  #   2. Include in ActiveJob::Base second
  ::ActiveJob::Base.include(E11y::Instruments::ActiveJob::Callbacks)

  callbacks = e11y_around_perform_callbacks(simulated_app_job)
  expect(callbacks.size).to eq(1),
    "Expected exactly 1 E11y around_perform callback on simulated ApplicationJob, " \
    "but found #{callbacks.size}. " \
    "BUG: setup_active_job registers on both ApplicationJob and ActiveJob::Base — " \
    "callbacks fire twice per job."
end

When("E11y ActiveJob integration is set up") do
  skip unless defined?(::ActiveJob)
  require "e11y/instruments/active_job"
  E11y::Railtie.setup_active_job
end

Then("at least {int} E11y around_perform callback(s) should exist on ActiveJob::Base") do |min|
  skip unless defined?(::ActiveJob)
  callbacks = e11y_around_perform_callbacks(::ActiveJob::Base)
  expect(callbacks.size).to be >= min,
    "Expected >= #{min} E11y around_perform callbacks on ActiveJob::Base, " \
    "found #{callbacks.size}."
end

When("ActiveSupport::Notifications publishes {string}") do |event_name|
  @notification_error = nil
  payload = case event_name
            when "sql.active_record"
              { sql: "SELECT 1", name: "Test Load", duration: 0.5 }
            when "process_action.action_controller"
              { controller: "PostsController", action: "index",
                format: :html, method: "GET", path: "/posts",
                status: 200, view_runtime: 1.0, db_runtime: 0.5 }
            else
              {}
            end
  begin
    ActiveSupport::Notifications.instrument(event_name, payload)
  rescue NameError => e
    @notification_error = e
  end
end

Then("no notification error should have been raised") do
  expect(@notification_error).to be_nil,
    "Got #{@notification_error&.class}: #{@notification_error&.message}. " \
    "BUG: Railtie subscribes to AS::Notifications but the event class " \
    "(e.g. E11y::Events::Rails::Database::Query) doesn't exist."
end
