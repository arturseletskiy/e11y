# features/auto_metrics.feature
@metrics
Feature: Automatic metric registration

  # E11y events can define counters, histograms, and gauges via a metrics DSL.
  # Definitions are stored in E11y::Metrics::Registry and should be forwarded
  # to a backend (Yabeda/Prometheus) whenever events are tracked.
  #
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

  Scenario: E11y has a configured metrics backend after initialization
    Then E11y::Metrics should have a configured backend

  Scenario: Middleware internal metrics use a real tracking call
    When E11y processes an event through the pipeline
    Then at least 1 internal middleware metric should have been tracked
