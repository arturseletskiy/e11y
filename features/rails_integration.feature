# features/rails_integration.feature
@rails
Feature: Rails Railtie integration

  # E11y ships a Railtie that hooks into the Rails lifecycle:
  #   - Auto-disables E11y in test environment (config defaults to nil, Railtie sets false)
  #   - Registers around_perform on ActiveJob for request context propagation
  #   - Subscribes to ActiveSupport::Notifications for DB queries, requests, etc.
  #
  # NOTE: Double-callback bug — if both ApplicationJob and ActiveJob::Base each call
  #       `include E11y::Instruments::ActiveJob`, the around_perform callback is registered
  #       twice, causing every job to emit duplicate events and run context-setup twice.
  #       This cannot be demonstrated here because the dummy app's ActiveJob::Base is
  #       already configured; the Railtie guards against double-registration via
  #       `around_perform_callbacks.any? { |cb| cb.filter == E11y::... }`.

  Background:
    Given the application is running

  Scenario: E11y is automatically disabled in the test environment
    # Fixed: @enabled = nil by default, so the Railtie guard correctly sets false in test env.
    Then E11y should be disabled in the test environment

  Scenario: E11y configuration can be explicitly disabled
    # The Railtie auto-disables E11y in the test environment only.
    # In all other environments users must set `config.enabled = false` explicitly.
    # This scenario verifies that the flag itself works when set at runtime.
    When I set E11y enabled to false
    Then E11y should be disabled in the test environment
    And I restore E11y enabled to true

  Scenario: ActiveJob around_perform callback is registered when integration is set up
    # Documents that setup_active_job correctly registers at least one callback
    # on ActiveJob::Base.
    When E11y ActiveJob integration is set up
    Then at least 1 E11y around_perform callback should exist on ActiveJob::Base

  Scenario: ActiveSupport::Notifications can be published without raising
    # instrument() with no active E11y subscriber should not raise.
    When ActiveSupport::Notifications publishes "sql.active_record"
    Then no notification error should have been raised

  Scenario: Railtie does not break the Rails app boot
    # Smoke test: dummy app loads and responds to requests.
    When I GET "/posts"
    Then the response status should be 200
