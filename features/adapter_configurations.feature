# features/adapter_configurations.feature
#
# Verifies adapter configuration APIs.
# Documents silent config key mismatches and health-check bugs.
#
# Bug tags:
#   @wip — scenario exposes a known bug; expected to FAIL.
@adapters
Feature: Adapter configurations

  Background:
    Given the application is running

  # ─── Stdout Adapter ─────────────────────────────────────────────────────────

  # BUG-011: Stdout adapter reads :pretty_print, NOT :format.
  # Passing format: :pretty as the documented key has no effect on the output format.
  # When user passes format: :compact expecting compact output, adapter ignores it
  # and defaults to pretty_print: true (multi-line). Documented here via compact case.
  @wip
  Scenario: Stdout adapter compact output when format is not the :pretty_print key
    # BUG: User passes pretty_print: false but uses :format key — adapter uses :pretty_print default (true)
    # This scenario uses format: :compact expecting single-line output but gets multi-line.
    Given a Stdout adapter with format config key "format: :compact"
    When I write an event through the Stdout adapter
    Then the Stdout output should be a single-line JSON string

  Scenario: Stdout adapter produces multi-line output with pretty_print: true
    Given a Stdout adapter with format config key "pretty_print: true"
    When I write an event through the Stdout adapter
    Then the Stdout output should be multi-line pretty-printed JSON

  Scenario: Stdout adapter produces single-line output with pretty_print: false
    Given a Stdout adapter with format config key "pretty_print: false"
    When I write an event through the Stdout adapter
    Then the Stdout output should be a single-line JSON string

  # ─── File Adapter ──────────────────────────────────────────────────────────

  Scenario: File adapter writes tracked events as JSONL to configured path
    Given a File adapter writing to a temporary file
    When I write a sample event through the File adapter
    Then the output file should contain at least 1 valid JSON line
    And the JSON line should include the field "event_name"

  # ─── Loki Adapter ──────────────────────────────────────────────────────────

  Scenario: Loki healthy? returns false when the host is unreachable
    Given a Loki adapter pointing to "http://localhost:19998"
    When I call healthy? on the Loki adapter
    Then the Loki healthy? result should be false

  Scenario: Loki healthy? does not raise an error
    Given a Loki adapter pointing to "http://localhost:19998"
    When I call healthy? on the Loki adapter
    Then calling healthy? should not raise an error

  # ─── Sentry Adapter ─────────────────────────────────────────────────────────

  # BUG-013: E11y::Adapters::Sentry.new calls Sentry.init unconditionally.
  # Any existing Sentry SDK configuration is overwritten.
  Scenario: Sentry adapter does not reinitialize an already-configured Sentry SDK
    Given Sentry SDK is initialized with a reference DSN
    When I create an E11y Sentry adapter with a different DSN
    Then the Sentry SDK configuration should not have been overwritten
