# features/event_tracking.feature
#
# Verifies the core event tracking API:
#   - EventClass.track(**payload) — the working path
#   - E11y.track(event_instance)  — @wip: currently raises NotImplementedError
#   - Schema field capture in the memory adapter
#   - No phantom events on failed Rails validations
#   - Error-level events on unhandled exceptions
#
# Tag legend:
#   @wip  — scenario exposes a known bug; expected to FAIL until the bug is fixed.
#           Run: bundle exec rake cucumber:wip

Feature: Core event tracking API

  Background:
    Given the application is running

  # ---------------------------------------------------------------------------
  # @wip — BUG: E11y.track(instance) raises NotImplementedError
  #
  # The README Quick Start shows:
  #   E11y.track(Events::UserSignup.new(user_id: 123))
  #
  # In reality lib/e11y.rb:66-68 contains:
  #   def track(event)
  #     raise NotImplementedError, "E11y.track will be implemented in Phase 1"
  #   end
  #
  # Expected (when fixed): the event reaches the memory adapter without error.
  # Actual (current):       NotImplementedError is raised before any adapter is called.
  # ---------------------------------------------------------------------------
  @wip
  Scenario: Calling E11y.track with an event instance delivers the event
    When I call E11y.track with a new Events::OrderCreated instance
    Then no exception should have been raised
    And 1 event of type "Events::OrderCreated" should have been tracked

  # ---------------------------------------------------------------------------
  # Happy path — EventClass.track works correctly
  # ---------------------------------------------------------------------------
  Scenario: POST /orders tracks an Events::OrderCreated event via EventClass.track
    When I POST to "/orders" with order params:
      | order[status] | pending |
    Then the response status should be 201
    And 1 event of type "Events::OrderCreated" should have been tracked

  Scenario: Tracked event payload contains the submitted fields
    When I POST to "/orders" with order params:
      | order[status]   | confirmed |
      | order[order_id] | ord-99    |
    Then the response status should be 201
    And 1 event of type "Events::OrderCreated" should have been tracked
    And the last "Events::OrderCreated" event's field "status" should equal "confirmed"

  Scenario: Tracked event has required metadata fields set by middleware
    When I POST to "/orders" with order params:
      | order[status] | pending |
    Then the response status should be 201
    And 1 event of type "Events::OrderCreated" should have been tracked
    And the last "Events::OrderCreated" event has a non-nil timestamp
    And the last "Events::OrderCreated" event has a non-nil severity

  Scenario: POST /users with valid params tracks a UserRegistered event
    When I POST to "/users" with user params:
      | user[email]                 | alice@example.com |
      | user[password]              | s3cr3t            |
      | user[password_confirmation] | s3cr3t            |
      | user[name]                  | Alice             |
    Then the response status should be 201
    And 1 event of type "Events::UserRegistered" should have been tracked

  Scenario: Multiple sequential requests each track one event
    When I POST to "/orders" with order params:
      | order[status] | pending |
    And I POST to "/orders" with order params:
      | order[status] | confirmed |
    Then 2 events of type "Events::OrderCreated" should have been tracked

  # ---------------------------------------------------------------------------
  # No phantom events on Rails validation failure
  # The PostsController does NOT track any E11y business event on its own —
  # it uses standard ActiveRecord validation. A missing required field
  # returns 422. Rails instrumentation may auto-track request/query events
  # but no business-level event (Orders, Users, etc.) should appear.
  # ---------------------------------------------------------------------------
  Scenario: POST /posts with a missing required title returns 422 and tracks no business event
    When I POST to "/posts" with body params:
      | post[body] | Some body text without a title |
    Then the response status should be 422
    And no event of type "Events::OrderCreated" should have been tracked
    And no event of type "Events::UserRegistered" should have been tracked

  # ---------------------------------------------------------------------------
  # Unhandled exception path
  # GET /test_error triggers PostsController#error which raises StandardError.
  # Rails instrumentation tracks request-level events automatically; no business
  # app event should be created for this error path.
  # ---------------------------------------------------------------------------
  Scenario: GET /test_error raises StandardError and tracks no business event
    When I make a GET request to "/test_error" ignoring exceptions
    Then no event of type "Events::OrderCreated" should have been tracked
    And no event of type "Events::UserRegistered" should have been tracked
