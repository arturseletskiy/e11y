# features/schema_validation.feature
@schema
Feature: Schema validation DSL

  # E11y events define their payload shape using a dry-schema DSL.
  # The Validation middleware enforces the schema before events reach adapters.
  # README: "Type-safe events with dry-schema validation."
  #
  # This feature covers baseline passing behavior only.
  # All scenarios should pass — there are no known critical schema DSL bugs.

  Background:
    Given the application is running

  # ─── Field presence ─────────────────────────────────────────────────────────

  Scenario: Event with optional fields is delivered to the adapter
    When I POST to "/orders" with json params '{"order":{"order_id":"ord-s1","status":"pending"}}'
    Then the response status should be 201
    And at least 1 event should be in the memory adapter

  Scenario: Event payload includes submitted order_id in the tracked event
    When I POST to "/orders" with json params '{"order":{"order_id":"ord-s2","status":"pending"}}'
    Then the last event payload in the memory adapter should include "order_id"

  # ─── Type enforcement ────────────────────────────────────────────────────────

  Scenario: Payload order_id value is preserved as a string
    When I POST to "/orders" with json params '{"order":{"order_id":"ord-s3","status":"pending"}}'
    Then the last event payload field "order_id" should be a string

  # ─── Optional fields ────────────────────────────────────────────────────────

  Scenario: Event with all optional fields omitted is still delivered
    # Optional fields must not block delivery when absent.
    When I POST to "/orders" with json params '{"order":{}}'
    Then the response status should be 201
    And at least 1 event should be in the memory adapter

  # ─── Multi-event schema ──────────────────────────────────────────────────────

  Scenario: User registration event with all required fields is delivered
    # Events::UserRegistered requires user_id, email, password,
    # password_confirmation, and name — all provided via controller.
    When I POST to "/users" with json params '{"user":{"email":"test@schema.com","password":"secret123","password_confirmation":"secret123","name":"Schema Test"}}'
    Then the response status should be 201
    And at least 1 event should be in the memory adapter

  # ─── Schema compilation ──────────────────────────────────────────────────────

  Scenario: Defining an event class with a schema block does not raise at load time
    Then defining an event class with a valid schema block should not raise

  Scenario: Event class without a schema block can still be tracked
    # Schema is optional — events with no schema block pass through unvalidated.
    Then defining and tracking an event class without a schema block should not raise
