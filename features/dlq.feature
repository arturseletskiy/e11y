# features/dlq.feature
@dlq
Feature: Dead Letter Queue (DLQ) reliability

  # When an adapter fails to deliver an event, the DLQ captures it
  # so no data is permanently lost. Operators can later replay entries.
  #
  # BUG 1: DLQ::FileStorage#replay is a stub — events are NOT re-dispatched.
  # BUG 2: DLQ::FileStorage#delete always returns false.
  # BUG 3: Default file path calls Rails.root — fails without Rails.

  Background:
    Given the application is running
    And the DLQ uses a temporary file for storage

  Scenario: Failed event can be saved to the DLQ
    When a failing adapter saves an event to the DLQ
    Then the DLQ should contain at least 1 entry
    And the DLQ entry should have an event_name field

  Scenario: DLQ entry contains the delivery error message
    When a failing adapter saves an event to the DLQ
    Then the DLQ entry should have a metadata field

  @wip
  Scenario: Replaying a DLQ entry re-dispatches the event through the pipeline
    # BUG: replay calls empty increment_metric, returns true, does nothing else.
    # E11y::Pipeline.dispatch is commented out — doesn't exist.
    Given a secondary working adapter is configured
    When a failing adapter saves an event to the DLQ
    And I replay the DLQ entry
    Then the event should appear in the secondary adapter

  @wip
  Scenario: Deleting a DLQ entry removes it permanently
    # BUG: delete always returns false regardless of input.
    When a failing adapter saves an event to the DLQ
    And I delete the DLQ entry by ID
    Then the delete result should be true

  Scenario: DLQ with FileStorage persists entries to disk
    When a failing adapter saves an event to the DLQ
    Then the DLQ file should exist on disk
    And the DLQ file should contain valid JSONL content

  Scenario: DLQ FileStorage default path does not require Rails
    # BUG: default_file_path calls Rails.root.join("log", "e11y_dlq.jsonl")
    # Raises NameError: uninitialized constant Rails in non-Rails contexts.
    When I create a FileStorage without an explicit path
    Then no NameError should be raised
