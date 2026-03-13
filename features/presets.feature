# features/presets.feature
@presets
Feature: Event presets

  # E11y ships three preset modules that configure common event patterns:
  #   - AuditEvent: 100% sample rate, signed (audit trail)
  #   - DebugEvent: severity :debug, routes to :logs only
  #   - HighValueEvent: 100% sample rate, routes to :logs + :errors_tracker
  #
  Background:
    Given the application is running

  # ─── AuditEvent Preset ─────────────────────────────────────────────────────

  Scenario: Event including AuditEvent preset is marked as audit_event
    Given an event class including "E11y::Presets::AuditEvent"
    Then the event class should respond to audit_event? with true

  Scenario: Event including AuditEvent preset is signed when AuditSigning is in pipeline
    Given an event class including "E11y::Presets::AuditEvent"
    And the AuditSigning middleware is in the pipeline
    When I track the preset event
    Then the tracked event should have a "audit_signature" field

  Scenario: Event including AuditEvent preset has resolve_sample_rate 1.0
    # resolve_sample_rate IS correctly set by the preset.
    Given an event class including "E11y::Presets::AuditEvent"
    Then the event class should have resolve_sample_rate 1.0

  # ─── DebugEvent Preset ─────────────────────────────────────────────────────

  Scenario: Event including DebugEvent preset has severity :debug
    Given an event class including "E11y::Presets::DebugEvent"
    Then the event class should have severity :debug

  Scenario: Event including DebugEvent preset routes to :logs adapter only
    Given an event class including "E11y::Presets::DebugEvent"
    Then the event class adapter list should equal "logs"

  # ─── HighValueEvent Preset ─────────────────────────────────────────────────

  Scenario: Event including HighValueEvent preset routes to :logs and :errors_tracker
    Given an event class including "E11y::Presets::HighValueEvent"
    Then the event class adapter list should equal "logs, errors_tracker"

  Scenario: Event including HighValueEvent preset has resolve_sample_rate 1.0
    Given an event class including "E11y::Presets::HighValueEvent"
    Then the event class should have resolve_sample_rate 1.0
