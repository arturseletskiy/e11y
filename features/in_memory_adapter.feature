# features/in_memory_adapter.feature
#
# Verifies the public API of E11y::Adapters::InMemory.
#
# The memory adapter is the primary tool for asserting events in tests.
# Any regression in its API breaks every integration test that uses it.
#
# Bug tags:
#   @wip  — scenario exposes a known bug; expected to FAIL.
#
# Correct method signatures (from lib/e11y/adapters/in_memory.rb):
#   adapter.clear!                              # clears all events
#   adapter.find_events("Events::OrderCreated") # returns Array<Hash>
#   adapter.event_count                         # total count (no args)
#   adapter.event_count(event_name: "...")      # count by name (keyword arg)
#   adapter.last_events(n)                      # last N events as Array<Hash>
#   adapter.first_events(n)                     # first N events
#   adapter.events_by_severity(:info)           # filter by severity
#   adapter.any_event?("Events::OrderCreated")  # returns Boolean

Feature: InMemory adapter public API

  Background:
    Given the application is running
    And the memory adapter is empty

  # ===========================================================================
  # @wip scenarios — these expose KNOWN BUGS and are expected to FAIL
  # ===========================================================================

  # BUG-002: adapter.last_event does not exist
  #
  # The method `last_event` is NOT defined on E11y::Adapters::InMemory.
  # Calling it raises NoMethodError.
  # The correct call is: adapter.last_events(1).first
  #
  # This is a significant DX bug because `last_event` is the most natural
  # thing to write when asserting the most recent event.
  Scenario: adapter.last_event returns the most recently tracked event
    Given I have tracked 1 order event with status "pending"
    When I call adapter.last_event
    Then the result should be a Hash
    And the result's payload field "status" should equal "pending"

  # BUG-003: adapter.event_count("Events::OrderCreated") raises ArgumentError
  #
  # The method signature is: event_count(event_name: nil)
  # Passing a positional string argument raises:
  #   ArgumentError: wrong number of arguments (given 1, expected 0)
  Scenario: adapter.event_count with positional string arg returns count
    Given I have tracked 2 order events
    When I call adapter.event_count with positional argument "Events::OrderCreated"
    Then the result should equal 2

  # BUG-004: adapter.clear (without bang) raises NoMethodError
  #
  # Only adapter.clear! is defined. The no-bang variant is missing.
  Scenario: adapter.clear without bang clears all events
    Given I have tracked 1 order event with status "pending"
    When I call adapter.clear without bang
    Then the memory adapter should be empty

  # ===========================================================================
  # Passing scenarios — correct API surface
  # ===========================================================================

  Scenario: adapter.clear! removes all tracked events
    Given I have tracked 3 order events
    When I call adapter.clear!
    Then the memory adapter should be empty

  Scenario: adapter.event_count with no args includes business and instrumentation events
    # Rails instrumentation auto-tracks E11y::Events::Rails::* events per request,
    # so total count exceeds the number of business events tracked.
    # We verify count >= 3 (our 3 business events) rather than an exact total.
    Given I have tracked 2 order events
    And I have tracked 1 user registration event
    When I call adapter.event_count with no arguments
    Then the result should be at least 3

  Scenario: adapter.event_count with keyword arg counts events of a specific type
    Given I have tracked 2 order events
    And I have tracked 1 user registration event
    When I call adapter.event_count with keyword event_name "Events::OrderCreated"
    Then the result should equal 2

  Scenario: adapter.find_events returns only events matching the given class name
    Given I have tracked 2 order events
    And I have tracked 1 user registration event
    When I call adapter.find_events with "Events::OrderCreated"
    Then the result should contain 2 items
    And all items in the result should have event_name "Events::OrderCreated"

  Scenario: adapter.find_events returns empty array when no matching events exist
    Given I have tracked 1 user registration event
    When I call adapter.find_events with "Events::OrderCreated"
    Then the result should contain 0 items

  Scenario: adapter.last_events(n) returns the last N events in insertion order
    Given I have tracked 3 order events with statuses "pending", "confirmed", "cancelled"
    When I call adapter.last_events with count 2
    Then the result should contain 2 items

  Scenario: adapter.find_events().last is the workaround for missing last_event
    # adapter.last_events(1) returns the last event overall (may be a Rails event).
    # The correct workaround is find_events("Type").last to get the last business event.
    Given I have tracked 1 order event with status "shipped"
    When I call adapter.find_events("Events::OrderCreated").last
    Then the result should be a Hash
    And the result's payload field "status" should equal "shipped"

  Scenario: adapter.first_events(n) returns the first N events in insertion order
    Given I have tracked 3 order events with statuses "pending", "confirmed", "cancelled"
    When I call adapter.first_events with count 1
    Then the result should contain 1 item

  Scenario: adapter.events_by_severity filters events by severity symbol
    Given I have tracked 1 order event with status "pending"
    When I call adapter.events_by_severity with :info
    Then the result should contain at least 1 item

  Scenario: adapter.any_event? returns true when matching events exist
    Given I have tracked 1 order event with status "pending"
    When I call adapter.any_event? with "Events::OrderCreated"
    Then the boolean result should be true

  Scenario: adapter.any_event? returns false when no matching events exist
    Given the memory adapter is empty
    When I call adapter.any_event? with "Events::OrderCreated"
    Then the boolean result should be false

  Scenario: adapter tracks events across separate requests independently
    Given I have tracked 1 order event with status "first"
    And I have tracked 1 order event with status "second"
    Then 2 events of type "Events::OrderCreated" should have been tracked
    And the last "Events::OrderCreated" event's field "status" should equal "second"

  Scenario: adapter.events returns all events as a non-empty array
    # Rails instrumentation adds extra events per request, so total events
    # will be more than the 2 business events tracked. We verify events is an
    # Array with at least 2 items.
    Given I have tracked 2 order events
    Then the adapter events array should have at least 2 items
