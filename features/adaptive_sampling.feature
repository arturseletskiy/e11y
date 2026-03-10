# features/adaptive_sampling.feature
Feature: Adaptive Sampling

  Background:
    Given the memory adapter is cleared
    And E11y is configured with the memory adapter as fallback
    And the Sampling middleware is reconfigured with trace_aware false and default_sample_rate 1.0

  # -----------------------------------------------------------------------
  # Scenario 1: sample_rate 1.0 always tracked
  # -----------------------------------------------------------------------
  Scenario: Events with sample_rate 1.0 are always tracked
    Given an event class "Events::AlwaysTracked" with sample_rate 1.0
    When I track 100 "Events::AlwaysTracked" events
    Then the memory adapter should contain exactly 100 "Events::AlwaysTracked" events

  # -----------------------------------------------------------------------
  # Scenario 2: sample_rate 0.0 never tracked
  # -----------------------------------------------------------------------
  Scenario: Events with sample_rate 0.0 are never tracked
    Given an event class "Events::NeverTracked" with sample_rate 0.0
    When I track 100 "Events::NeverTracked" events
    Then the memory adapter should contain exactly 0 "Events::NeverTracked" events

  # -----------------------------------------------------------------------
  # Scenario 3 (@wip): LoadMonitor returns :normal at exactly the normal threshold
  # Bug: load_level returns :high when rate == thresholds[:normal]
  # -----------------------------------------------------------------------
  Scenario: Load at exactly normal threshold produces :normal load level
    Given a LoadMonitor with normal threshold 100 events per second and window 1 second
    When I record exactly 100 events in 1 second in the LoadMonitor
    Then the LoadMonitor load_level should be :normal

  # -----------------------------------------------------------------------
  # Scenario 4 (@wip): Normal-threshold load yields 100 % sampling
  # Depends on scenario 3 bug: :high returned instead of :normal -> 50 % rate
  # -----------------------------------------------------------------------
  Scenario: Load at normal threshold results in 100% sampling rate
    Given a LoadMonitor with normal threshold 100 events per second and window 1 second
    When I record exactly 100 events in 1 second in the LoadMonitor
    Then the LoadMonitor recommended_sample_rate should be 1.0

  # -----------------------------------------------------------------------
  # Scenario 5: High load yields reduced sampling
  # -----------------------------------------------------------------------
  Scenario: Load above high threshold results in reduced sampling rate
    Given a LoadMonitor with normal threshold 10, high threshold 50 events per second and window 1 second
    When I record 60 events in 1 second in the LoadMonitor
    Then the LoadMonitor recommended_sample_rate should be less than 1.0

  # -----------------------------------------------------------------------
  # Scenario 6: Critical (overload) load yields lowest sampling
  # -----------------------------------------------------------------------
  Scenario: Load at overload threshold results in 1% sampling rate
    Given a LoadMonitor with normal threshold 10, high threshold 50, very_high threshold 100, overload threshold 200 events per second and window 1 second
    When I record 250 events in 1 second in the LoadMonitor
    Then the LoadMonitor recommended_sample_rate should be 0.01

  # -----------------------------------------------------------------------
  # Scenario 7: Error spike increases sample rate for affected event type
  # -----------------------------------------------------------------------
  Scenario: Error spike detection activates 100% sampling across all event types
    Given the Sampling middleware is reconfigured with error_based_adaptive true and default_sample_rate 0.1
    And an event class "Events::OrderForSpike" with sample_rate 0.1
    When I track 15 error events to trigger the spike detector
    Then the error spike detector should be active
    When I track 20 "Events::OrderForSpike" events
    Then the memory adapter should contain exactly 20 "Events::OrderForSpike" events

  # -----------------------------------------------------------------------
  # Scenario 8 (@wip): Same trace_id gets consistent sampling decision
  # Bug: cleanup_trace_decisions randomly evicts 50% of cache keys,
  # potentially evicting an active trace and breaking consistency.
  # -----------------------------------------------------------------------
  Scenario: Events from the same trace_id receive consistent sampling decisions
    Given the Sampling middleware is reconfigured with trace_aware true and default_sample_rate 0.5
    And an event class "Events::TracedOrder" with sample_rate 0.5
    And the trace decisions cache is filled with 1001 dummy entries to trigger cleanup
    When I set the current trace_id to "cucumber-trace-consistency-test"
    And I track 50 "Events::TracedOrder" events
    Then all 50 "Events::TracedOrder" events should have the same sampling outcome
