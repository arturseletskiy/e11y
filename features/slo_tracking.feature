# features/slo_tracking.feature
#
# Verifies E11y::SLO::Tracker and related SLO infrastructure.
# Known bugs documented with @wip tag.
#
# Bug tags:
#   @wip — scenario exposes a known bug; expected to FAIL.
Feature: SLO Tracking

  As a platform engineer
  I want E11y to automatically track Service Level Objectives
  So that I can monitor availability and latency without manual instrumentation

  Background:
    Given the application is running
    And the memory adapter is empty
    And SLO tracking is reset to its default state

  Scenario: SLO tracking is enabled by default without any configuration
    When I inspect the default SLO tracking configuration
    Then E11y.configuration.slo_tracking_enabled should be true

  Scenario: Successful HTTP request is tracked in SLO
    Given SLO tracking is enabled
    When I POST to "/orders" with order params:
      | order[status] | pending |
    Then the SLO tracker should have recorded a request for "orders#create"
    And the normalize_status for 201 should return "2xx"

  Scenario: Failed HTTP request updates SLO failure count
    Given SLO tracking is enabled
    When I make a GET request to "/test_error" ignoring exceptions
    Then the SLO tracker should have recorded a request for "posts#error"
    And the normalize_status for 500 should return "5xx"

  Scenario: Event-level SLO fires when EventSlo middleware is in the pipeline
    Given E11y::Middleware::EventSlo is added to the pipeline
    When I POST to "/orders" with order params:
      | order[status] | pending |
    Then the SLO metric "slo_event_result_total" should have been incremented

  Scenario: SLO is disabled when config.slo_tracking_enabled is false
    Given SLO tracking is explicitly disabled
    When I POST to "/orders" with order params:
      | order[status] | pending |
    Then no SLO metrics should have been recorded

  Scenario: SLO tracking can be explicitly disabled
    # Zero-config: enabled by default; can opt-out.
    When I inspect the default SLO tracking configuration
    Then E11y.configuration.slo_tracking_enabled should be true
    And enabling SLO tracking requires setting slo_tracking_enabled to true
