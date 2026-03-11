# features/event_versioning.feature
@event_versioning
Feature: Event Versioning middleware

  # The Versioning middleware (opt-in) extracts a version number from the
  # event class name suffix (V2, V3, …) and normalises event_name for
  # consistent storage queries. Custom event_name overrides are preserved.
  #
  # NOTE: The Versioning middleware is NOT in the default pipeline (opt-in).

  Background:
    Given the application is running

  # -----------------------------------------------------------------------
  # Scenario 1 — Standard class name normalisation (V1 — no version suffix)
  # -----------------------------------------------------------------------
  Scenario: OrderCreated class name is normalised to dot-notation event_name
    Given the Versioning middleware is prepended to the pipeline
    When I POST to "/orders" with versioning params:
      | order_id | order-001 |
      | status   | pending   |
    Then the last versioned "Events::OrderCreated" event has event_name "order.created"
    And  the last versioned "Events::OrderCreated" event does not have a "v" field

  # -----------------------------------------------------------------------
  # Scenario 2 — Multi-word class name normalisation
  # -----------------------------------------------------------------------
  Scenario: PaymentSubmitted class name is normalised to dot-notation event_name
    Given the Versioning middleware is prepended to the pipeline
    When I POST to "/api/v1/payments" with versioning params:
      | payment_id | pay-001 |
    Then the last versioned "Events::PaymentSubmitted" event has event_name "payment.submitted"
    And  the last versioned "Events::PaymentSubmitted" event does not have a "v" field

  # -----------------------------------------------------------------------
  # Scenario 3 — Custom event_name override preserved
  # -----------------------------------------------------------------------
  Scenario: Custom event_name override on event class is preserved by Versioning middleware
    Given the Versioning middleware is prepended to the pipeline
    And   an inline versioning event class "Events::CustomNamedEvent" with event_name "my.custom.name"
    When  the versioning event "Events::CustomNamedEvent" is tracked directly with payload:
      | field | data |
    Then the last versioned "Events::CustomNamedEvent" event has event_name "my.custom.name"

  # -----------------------------------------------------------------------
  # Scenario 4 — V2 versioned event
  # -----------------------------------------------------------------------
  Scenario: V2 event class adds v:2 to payload and strips version from event_name
    Given the Versioning middleware is prepended to the pipeline
    And   an inline versioning event class "Events::OrderPaidV2" inheriting from "Events::OrderPaid"
    When  the versioning event "Events::OrderPaidV2" is tracked directly with payload:
      | order_id | ord-002 |
      | currency | USD     |
    Then the last versioned "Events::OrderPaidV2" event has event_name "order.paid"
    And  the last versioned "Events::OrderPaidV2" event has a "v" field equal to 2

  # -----------------------------------------------------------------------
  # Scenario 5 — Versioning NOT active by default
  # -----------------------------------------------------------------------
  Scenario: Without Versioning middleware event_name retains the raw class name
    Given the Versioning middleware is NOT in the pipeline
    When I POST to "/orders" with versioning params:
      | order_id | order-002 |
      | status   | pending   |
    Then the last versioned "Events::OrderCreated" event is present
    And  the last versioned "Events::OrderCreated" event has event_name "Events::OrderCreated"
