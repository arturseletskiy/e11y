# features/pii_filtering.feature
#
# Verifies that PIIFilter middleware correctly masks sensitive fields.
# Documents the regex-corruption bug where PASSWORD_FIELDS pattern is applied
# to string VALUES (not just field names), corrupting innocent data.
#
# Bug tags:
#   @wip — scenario exposes a known bug; expected to FAIL.
Feature: PII Filtering

  As a compliance officer
  I want E11y to automatically mask sensitive fields before they reach adapters
  So that personal data never appears in logs or error trackers

  Background:
    Given the application is running
    And the memory adapter is empty

  Scenario: Password field is filtered from user registration event
    # UserRegistered has no pii_filtering block → Tier 2 (Rails filter_parameters).
    # filter_parameters includes :password and :password_confirmation.
    When I POST user params to "/users":
      | user[email]                 | alice@example.com |
      | user[password]              | secret123         |
      | user[password_confirmation] | secret123         |
      | user[name]                  | Alice             |
    Then 1 event of type "Events::UserRegistered" should have been tracked
    And the last "Events::UserRegistered" event's field "password" should be filtered
    And the last "Events::UserRegistered" event's field "password_confirmation" should be filtered

  Scenario: Email address passes through (not in Rails filter_parameters)
    # email is NOT in filter_parameters, so it is retained unchanged.
    # password_confirmation is required by the UserRegistered schema.
    When I POST user params to "/users":
      | user[email]                 | bob@example.com |
      | user[password]              | hunter2         |
      | user[password_confirmation] | hunter2         |
      | user[name]                  | Bob             |
    Then 1 event of type "Events::UserRegistered" should have been tracked
    And the last "Events::UserRegistered" event's field "email" should equal "bob@example.com"

  Scenario: Credit card CVV is masked in payment event
    # PaymentSubmitted has contains_pii true and masks :cvv explicitly.
    When I POST payment params to "/api/v1/payments":
      | payment[card_number] | 4111111111111111 |
      | payment[cvv]         | 123              |
      | payment[amount]      | 99.99            |
      | payment[currency]    | USD              |
    Then 1 event of type "Events::PaymentSubmitted" should have been tracked
    And the last "Events::PaymentSubmitted" event's field "cvv" should be filtered

  # BUG-010: pii_filtering { allows :card_number } does not protect against
  # apply_pattern_filtering. The CREDIT_CARD regex matches "4111111111111111"
  # and replaces it with "[FILTERED]" even though the field is explicitly allowed.
  # The allows directive bypasses field-level masking but NOT pattern-based value filtering.
  @wip
  Scenario: Card number is retained when explicitly allowed in pii_filtering config
    # pii_filtering allows :card_number — expect value to pass through unchanged.
    # BUG: apply_pattern_filtering runs after field strategies and catches the card number.
    When I POST payment params to "/api/v1/payments":
      | payment[card_number] | 4111111111111111 |
      | payment[cvv]         | 456              |
      | payment[amount]      | 50.00            |
      | payment[currency]    | GBP              |
    Then 1 event of type "Events::PaymentSubmitted" should have been tracked
    And the last "Events::PaymentSubmitted" event's field "card_number" should not be filtered

  Scenario: Authorization header is filtered from protected request event
    # ProtectedRequest → Tier 2. filter_parameters includes :authorization.
    # "Bearer valid_token_123" is the valid auth token from the dummy app.
    When I GET "/api/v1/protected" with Authorization header "Bearer valid_token_123"
    Then 1 event of type "Events::ProtectedRequest" should have been tracked
    And the last "Events::ProtectedRequest" event's field "authorization" should be filtered

  # BUG-008: filter_string_patterns applies PASSWORD_FIELDS regex to string values.
  # "process_token_renewal_completed" → "process_[FILTERED]_renewal_completed"
  # The word "token" inside a non-sensitive status string is corrupted.
  @wip
  Scenario: Legitimate status string containing the word "token" is not corrupted
    When I POST order params with a token-like status to "/orders"
    Then 1 event of type "Events::OrderCreated" should have been tracked
    And the last "Events::OrderCreated" event's field "status" should equal "process_token_renewal_completed"

  # BUG-009: Same root cause — filter_string_patterns applies PASSWORD_FIELDS to values.
  # "password_reset_email_sent" → "[FILTERED]_reset_email_sent"
  # A status string containing "password" as a substring is corrupted.
  @wip
  Scenario: Legitimate description containing the word "password" is not corrupted
    When I POST report params with description "password_reset_email_sent" to "/reports"
    Then 1 event of type "Events::ReportCreated" should have been tracked
    And the last "Events::ReportCreated" event's field "description" should equal "password_reset_email_sent"

  Scenario: Multiple PII fields in same event are all filtered independently
    When I POST user params to "/users":
      | user[email]                 | charlie@example.com |
      | user[password]              | p@ssw0rd!           |
      | user[password_confirmation] | p@ssw0rd!           |
      | user[name]                  | Charlie             |
    Then 1 event of type "Events::UserRegistered" should have been tracked
    And the last "Events::UserRegistered" event's field "password" should be filtered
    And the last "Events::UserRegistered" event's field "password_confirmation" should be filtered
    And the last "Events::UserRegistered" event's field "email" should equal "charlie@example.com"
    And the last "Events::UserRegistered" event's field "name" should equal "Charlie"
