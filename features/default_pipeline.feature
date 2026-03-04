# features/default_pipeline.feature
@pipeline
Feature: Default pipeline completeness

  # The E11y pipeline processes every event through a chain of middleware.
  # README and docs list these as part of the default pipeline:
  #   TraceContext → Validation → PIIFilter → AuditSigning → Sampling → Routing
  # Plus (advertised but missing): RateLimiting, EventSlo
  #
  # Fixed: RateLimiting and EventSlo are now included in the default pipeline.

  Background:
    Given the application is running

  Scenario: Default pipeline includes TraceContext middleware
    Then the pipeline should include the "TraceContext" middleware

  Scenario: Default pipeline includes Validation middleware
    Then the pipeline should include the "Validation" middleware

  Scenario: Default pipeline includes PIIFilter middleware
    Then the pipeline should include the "PIIFilter" middleware

  Scenario: Default pipeline includes AuditSigning middleware
    Then the pipeline should include the "AuditSigning" middleware

  Scenario: Default pipeline includes Sampling middleware
    Then the pipeline should include the "Sampling" middleware

  Scenario: Default pipeline includes Routing middleware
    Then the pipeline should include the "Routing" middleware

  Scenario: Default pipeline includes RateLimiting middleware
    Then the pipeline should include the "RateLimiting" middleware

  Scenario: Default pipeline includes EventSlo middleware
    Then the pipeline should include the "EventSlo" middleware

  Scenario: Event tracked via HTTP request arrives in the memory adapter
    # Golden-path smoke test: full pipeline end-to-end.
    When I POST to "/orders" with json params '{"order":{"order_id":"ord-pipe-1","status":"pending"}}'
    Then the response status should be 201
    And at least 1 event should be in the memory adapter

  Scenario: Pipeline middleware order matches documented sequence
    # Verifies Validation comes before Routing (critical per ADR-015).
    Then "Validation" should come before "Routing" in the pipeline
    And "PIIFilter" should come before "Routing" in the pipeline
    And "Sampling" should come before "Routing" in the pipeline
    And "AuditSigning" should come before "Routing" in the pipeline

  Scenario: RateLimiting middleware blocks events over the configured limit
    Given rate limiting is configured with global_limit 2
    When I send 5 rapid order events
    Then fewer than 5 events should arrive in the adapter
