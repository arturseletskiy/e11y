# features/default_pipeline.feature
@pipeline
Feature: Default pipeline completeness

  # The E11y pipeline processes every event through a chain of middleware.
  # README and docs list these as part of the default pipeline:
  #   TraceContext → Validation → PIIFilter → AuditSigning → Sampling → Routing
  # Plus (advertised but missing): RateLimiting, EventSlo
  #
  # BUG 1: E11y::Middleware::RateLimiting is absent from the default pipeline chain —
  #         rate limiting silently never fires.
  # BUG 2: E11y::Middleware::EventSlo is absent from the default pipeline chain —
  #         SLO tracking never fires unless added manually.

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
    # BUG: RateLimiting is never added in configure_default_pipeline in lib/e11y.rb.
    # rate_limiting.enabled defaults to false and the middleware is simply not wired in.
    Then the pipeline should include the "RateLimiting" middleware

  Scenario: Default pipeline includes EventSlo middleware
    # BUG: EventSlo is never added in configure_default_pipeline in lib/e11y.rb.
    # SLO tracking requires manual pipeline.use(E11y::Middleware::EventSlo) to activate.
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
    # BUG: Even after setting rate_limiting.enabled = true, Builder never adds
    # RateLimiting to the chain — events flow through unchecked regardless.
    Given rate limiting is configured with global_limit 2
    When I send 5 rapid order events
    Then fewer than 5 events should arrive in the adapter
