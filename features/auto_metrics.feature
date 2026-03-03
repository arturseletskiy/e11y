# features/auto_metrics.feature
@metrics
Feature: Automatic metric registration

  # E11y events can define counters, histograms, and gauges via a metrics DSL.
  # Definitions are stored in E11y::Metrics::Registry and should be forwarded
  # to a backend (Yabeda/Prometheus) whenever events are tracked.
  #
  # BUG 1: E11y::Metrics.backend is nil in the default setup — all metric calls
  #         are silently discarded. No Yabeda adapter is auto-configured.
  # BUG 2: increment_metric inside middleware (TraceContext, Routing, etc.)
  #         is an empty stub — internal telemetry calls never actually track anything.

  Background:
    Given the application is running

  Scenario: Event class with a metrics block loads without raising
    # Smoke test: the metrics DSL doesn't raise at class-definition time.
    Then defining an event class with a metrics block should not raise

  Scenario: Counter definition is stored in the Metrics Registry
    # The registry holds metric configs for later use by adapters.
    When I define an event class with a counter named "orders_tracked_total"
    Then the Metrics Registry should contain a counter named "orders_tracked_total"

  Scenario: Histogram with custom buckets stores buckets in the Registry
    # Verifies that the metrics DSL captures bucket configuration correctly.
    When I define an event class with a histogram "order_amount_usd" and buckets 1 5 10 100
    Then the Metrics Registry should contain a histogram "order_amount_usd" with buckets 1 5 10 100

  Scenario: Defining two metrics with conflicting types raises TypeConflictError
    # Registry detects type conflicts at registration time to prevent silent corruption.
    When I define two event classes using metric name "conflict_metric" with different types
    Then a TypeConflictError should have been raised

  @wip
  Scenario: E11y has a configured metrics backend after initialization
    # BUG: E11y::Metrics.backend is nil because no Yabeda adapter is auto-configured.
    # Every E11y::Metrics.increment/histogram/gauge call is silently discarded.
    # Users must manually add: config.adapters[:metrics] = E11y::Adapters::Yabeda.new
    Then E11y::Metrics should have a configured backend

  @wip
  Scenario: Middleware internal metrics use a real tracking call
    # BUG: increment_metric in TraceContext/Routing middleware is an empty stub.
    # The method is called but the body contains only a TODO comment — no actual tracking.
    When E11y processes an event through the pipeline
    Then at least 1 internal middleware metric should have been tracked
