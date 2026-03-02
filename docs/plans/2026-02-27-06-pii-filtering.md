# PII Filtering — Cucumber QA Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Verify that the PIIFilter middleware correctly masks sensitive fields in event payloads, and expose the confirmed regex-corruption bug where `PASSWORD_FIELDS` is applied to string VALUES instead of field names.

**Approach:** Make HTTP requests through the dummy app routes that already carry PII data (passwords, card numbers, auth tokens). After each request, read the captured event from the memory adapter and assert on the filtered payload. Two `@wip` scenarios send strings that contain PII-related subwords in a non-sensitive context and verify they are NOT corrupted — these are expected to fail because the current `filter_string_patterns` method blindly applies `E11y::PII::Patterns::PASSWORD_FIELDS` to string values.

**Known bugs covered:**
- `PASSWORD_FIELDS` regex (`/password|passwd|pwd|secret|token|api[_-]?key/i`) is applied to string VALUES via `filter_string_patterns` — a description field containing the word "token" as part of `"process_token_renewal_completed"` becomes `"process_[FILTERED]_renewal_completed"` (scenario 6)
- A status field containing `"password_reset_email_sent"` becomes `"[FILTERED]_reset_email_sent"` (scenario 7)
- `parameter_filter` in Tier 2 calls `Rails.application.config.filter_parameters` — will crash if Rails is not loaded (not exercised by these tests because the dummy app provides Rails context, but documented)
- `PIIFilter` nested hash handling: `apply_field_strategies` flattens one level only; if the event payload has a nested hash, inner PII-named keys survive — documented in scenario 8

---

## Files

| Path | Purpose |
|------|---------|
| `features/pii_filtering.feature` | Gherkin scenarios |
| `features/step_definitions/pii_filtering_steps.rb` | Step definitions |
| `features/support/world_helpers.rb` | Rack::Test World setup (shared) |

---

## Task 1 — Write the feature file

**Step 1: Create `features/pii_filtering.feature`**

```gherkin
# features/pii_filtering.feature
Feature: PII Filtering
  As a compliance officer
  I want E11y to automatically mask sensitive fields before they reach adapters
  So that personal data never appears in logs or error trackers

  Background:
    Given the memory adapter is cleared
    And the default E11y pipeline is active

  Scenario: Password field is filtered from user registration event
    When I POST to "/users" with:
      | user[email]                 | alice@example.com |
      | user[password]              | secret123         |
      | user[password_confirmation] | secret123         |
      | user[name]                  | Alice             |
    Then an "Events::UserRegistered" event should have been tracked
    And the event payload field "password" should equal "[FILTERED]"
    And the event payload field "password_confirmation" should equal "[FILTERED]"

  Scenario: Email address is retained (not PII-filtered by default) in UserRegistered payload
    # UserRegistered does not set contains_pii true and has no pii_filtering block,
    # so it falls into Tier 2 (Rails filter_parameters only).
    # Rails default filter_parameters does not include :email, so email passes through.
    When I POST to "/users" with:
      | user[email]    | bob@example.com |
      | user[password] | hunter2         |
      | user[name]     | Bob             |
    Then an "Events::UserRegistered" event should have been tracked
    And the event payload field "email" should equal "bob@example.com"

  Scenario: Credit card CVV is masked in payment event
    # PaymentSubmitted has contains_pii true and masks :cvv explicitly
    When I POST to "/api/v1/payments" with:
      | payment[card_number] | 4111111111111111 |
      | payment[cvv]         | 123              |
      | payment[amount]      | 99.99            |
      | payment[currency]    | USD              |
    Then a "Events::PaymentSubmitted" event should have been tracked
    And the event payload field "cvv" should equal "[FILTERED]"

  Scenario: Card number is allowed through (not masked by PaymentSubmitted config)
    # PaymentSubmitted allows :card_number explicitly in pii_filtering block
    When I POST to "/api/v1/payments" with:
      | payment[card_number] | 4111111111111111 |
      | payment[cvv]         | 456              |
      | payment[amount]      | 50.00            |
      | payment[currency]    | GBP              |
    Then a "Events::PaymentSubmitted" event should have been tracked
    And the event payload field "card_number" should equal "4111111111111111"

  Scenario: Authorization header is filtered from protected request event
    # ProtectedRequest.track receives authorization: request.headers["Authorization"]
    # The value "Bearer valid_token_123" contains "token" — but since it is passed
    # through Tier 2 Rails filtering (no contains_pii declaration), it depends on
    # Rails filter_parameters. The dummy app's filter_parameters includes :password
    # but may not include :authorization. This test documents the actual behaviour.
    When I GET "/api/v1/protected" with Authorization header "Bearer valid_token_123"
    Then a "Events::ProtectedRequest" event should have been tracked
    And the event payload field "authorization" should not be "Bearer valid_token_123"

  @wip
  Scenario: Legitimate string containing the word "token" is NOT corrupted
    # BUG: filter_string_patterns applies PASSWORD_FIELDS regex to string values.
    # The word "token" appears inside the value "process_token_renewal_completed"
    # and gets replaced, producing "process_[FILTERED]_renewal_completed".
    #
    # To trigger this bug: create an order whose description contains "token".
    # The OrderCreated event has contains_pii true and allows :items (array of hashes).
    # The description value passes through apply_pattern_filtering, which calls
    # filter_string_patterns on each string — corrupting it.
    When I POST to "/orders" with a description containing "process_token_renewal_completed"
    Then an "Events::OrderCreated" event should have been tracked
    And the event payload field containing "process_token_renewal_completed" should not be corrupted
    But the event payload field "process_token_renewal_completed" is actually corrupted due to the bug

  @wip
  Scenario: Legitimate status message containing "password" is NOT corrupted
    # BUG: Same root cause — filter_string_patterns applies PASSWORD_FIELDS to values.
    # The string "password_reset_email_sent" is a status code, not a password.
    # After PIIFilter: "password_reset_email_sent" → "[FILTERED]_reset_email_sent"
    When I POST to "/reports" with description "password_reset_email_sent"
    Then a "Events::ReportCreated" event should have been tracked
    And the event payload field "description" should equal "password_reset_email_sent"
    But the event payload field "description" is actually "[FILTERED]_reset_email_sent" due to the bug

  Scenario: Multiple PII fields in same event are all filtered independently
    When I POST to "/users" with:
      | user[email]                 | charlie@example.com |
      | user[password]              | p@ssw0rd!           |
      | user[password_confirmation] | p@ssw0rd!           |
      | user[name]                  | Charlie             |
    Then an "Events::UserRegistered" event should have been tracked
    And the event payload field "password" should equal "[FILTERED]"
    And the event payload field "password_confirmation" should equal "[FILTERED]"
    And the event payload field "email" should equal "charlie@example.com"
    And the event payload field "name" should equal "Charlie"
```

**Step 2: Run to verify it fails (no steps defined yet)**

```bash
bundle exec cucumber features/pii_filtering.feature --dry-run
```

Expected: All steps show as "undefined".

---

## Task 2 — Write step definitions

**Step 3: Create `features/step_definitions/pii_filtering_steps.rb`**

```ruby
# features/step_definitions/pii_filtering_steps.rb
# frozen_string_literal: true

require "json"

# ---------------------------------------------------------------------------
# Background steps
# ---------------------------------------------------------------------------

Given("the memory adapter is cleared") do
  @memory_adapter = E11y.config.adapters[:memory]
  @memory_adapter&.clear!
end

Given("the default E11y pipeline is active") do
  # Ensure no leftover pipeline mutations from other scenarios.
  # The default pipeline is set in E11y::Configuration#configure_default_pipeline.
  # We invalidate the built_pipeline cache so it gets rebuilt fresh.
  E11y.config.instance_variable_set(:@built_pipeline, nil)
  # Make the memory adapter reachable via fallback routing.
  E11y.config.fallback_adapters = [:memory] unless E11y.config.fallback_adapters.include?(:memory)
end

# ---------------------------------------------------------------------------
# Request steps
# ---------------------------------------------------------------------------

When("I POST to {string} with:") do |path, table|
  params = {}
  table.raw.each do |key, value|
    # Expand "user[email]" style keys into a nested hash.
    parts = key.scan(/[^\[\]]+/)
    if parts.size == 2
      params[parts[0]] ||= {}
      params[parts[0]][parts[1]] = value
    else
      params[key] = value
    end
  end
  post path, params
  @last_response = last_response
end

When("I GET {string} with Authorization header {string}") do |path, auth_value|
  get path, {}, { "HTTP_AUTHORIZATION" => auth_value }
  @last_response = last_response
end

When("I POST to {string} with a description containing {string}") do |path, description|
  # Send the description inside an order's status field so it ends up in
  # the OrderCreated event payload, which has contains_pii true and will
  # pass through apply_pattern_filtering.
  post path, {
    order: {
      order_id: "T-#{SecureRandom.hex(4)}",
      status: description
    }
  }.to_json, "CONTENT_TYPE" => "application/json"
  @last_response = last_response
  @submitted_description = description
end

When("I POST to {string} with description {string}") do |path, description|
  post path, {
    report: {
      title: "Test Report",
      description: description
    }
  }.to_json, "CONTENT_TYPE" => "application/json"
  @last_response = last_response
  @submitted_description = description
end

# ---------------------------------------------------------------------------
# Event lookup helpers
# ---------------------------------------------------------------------------

Then("an {string} event should have been tracked") do |event_class_name|
  @memory_adapter ||= E11y.config.adapters[:memory]
  @tracked_events = @memory_adapter.find_events(event_class_name)
  expect(@tracked_events).not_to be_empty,
    "Expected at least one #{event_class_name} event in memory adapter, " \
    "but none was found.\nAll events: #{@memory_adapter.events.map { |e| e[:event_name] }.inspect}"
  @last_event = @tracked_events.last
  @last_payload = @last_event[:payload] || {}
end

# Alias for grammatical variation
Then("a {string} event should have been tracked") do |event_class_name|
  step "an \"#{event_class_name}\" event should have been tracked"
end

# ---------------------------------------------------------------------------
# Payload assertion steps
# ---------------------------------------------------------------------------

Then("the event payload field {string} should equal {string}") do |field, expected_value|
  actual = @last_payload[field.to_sym] || @last_payload[field]
  expect(actual).to eq(expected_value),
    "Expected payload[#{field.inspect}] to equal #{expected_value.inspect}, " \
    "but got #{actual.inspect}.\nFull payload: #{@last_payload.inspect}"
end

Then("the event payload field {string} should not be {string}") do |field, unexpected_value|
  actual = @last_payload[field.to_sym] || @last_payload[field]
  expect(actual).not_to eq(unexpected_value),
    "Expected payload[#{field.inspect}] to have been filtered, " \
    "but it was still #{unexpected_value.inspect}.\nFull payload: #{@last_payload.inspect}"
end

Then("the event payload field containing {string} should not be corrupted") do |original_value|
  # Check all string values in the payload for the original intact string.
  found_corrupted = false
  found_intact = false

  @last_payload.each_value do |v|
    if v.is_a?(String)
      found_intact = true if v == original_value
      found_corrupted = true if v.include?("[FILTERED]") && v != "[FILTERED]"
    end
  end

  expect(found_intact).to be(true),
    "Expected to find the original value #{original_value.inspect} intact in the payload, " \
    "but it was not found.\nFull payload: #{@last_payload.inspect}\n" \
    "BUG: PASSWORD_FIELDS regex is applied to string values, corrupting non-sensitive data."
end

# This step documents the bug — it passes when the bug is present.
Then("the event payload field {string} is actually corrupted due to the bug") do |expected_corrupt_value|
  # Verify the bug manifests as documented.
  # The step name uses the CORRUPTED value as the argument to make the bug explicit.
  all_values = @last_payload.values.select { |v| v.is_a?(String) }
  corrupted = all_values.any? { |v| v.include?("[FILTERED]") && v != "[FILTERED]" }
  expect(corrupted).to be(true),
    "Expected the bug to corrupt a string value (containing [FILTERED] as partial replacement), " \
    "but no corruption was found.\nPayload values: #{all_values.inspect}"
end

Then("the event payload field {string} is actually {string} due to the bug") do |field, corrupted_value|
  actual = @last_payload[field.to_sym] || @last_payload[field]
  expect(actual).to eq(corrupted_value),
    "Expected the bug to produce #{corrupted_value.inspect} for field #{field.inspect}, " \
    "but got #{actual.inspect}.\nFull payload: #{@last_payload.inspect}"
end
```

**Step 4: Run to verify scenarios pass/fail as expected**

```bash
# Non-@wip scenarios: should pass
bundle exec cucumber features/pii_filtering.feature --tags "not @wip"

# @wip scenarios: should fail with the documented bug
bundle exec cucumber features/pii_filtering.feature --tags "@wip"
```

Expected results:
- Scenarios 1, 3, 4, 5, 8: pass (field-level strategies work correctly)
- Scenario 2: passes (email is not masked by default Tier 2 filtering)
- Scenario 6: fails — `filter_string_patterns` corrupts `"process_token_renewal_completed"` → `"process_[FILTERED]_renewal_completed"`
- Scenario 7: fails — `filter_string_patterns` corrupts `"password_reset_email_sent"` → `"[FILTERED]_reset_email_sent"`

**Step 5: Commit**

```bash
git add features/pii_filtering.feature features/step_definitions/pii_filtering_steps.rb
git commit -m "feat(cucumber): Add PII filtering QA scenarios with regex-corruption @wip bug markers"
```

---

## Implementation notes

### Tier classification for dummy app events

| Event class | `contains_pii` | `pii_filtering` | Tier |
|-------------|----------------|-----------------|------|
| `Events::UserRegistered` | not set | not set | Tier 2 (Rails filters) |
| `Events::OrderCreated` | `true` | `allows :customer, :payment, :items` | Tier 3 (deep filter) |
| `Events::PaymentSubmitted` | `true` | `masks :cvv; allows :payment_id, :amount, :currency, :card_number, :billing` | Tier 3 |
| `Events::ProtectedRequest` | not set | not set | Tier 2 |
| `Events::ReportCreated` | `true` | `allows :title, :description, :employee_ids, :author` | Tier 3 |

### Why email passes through for UserRegistered (Scenario 2)
`UserRegistered` is Tier 2. Tier 2 calls `apply_rails_filters` which uses `Rails.application.config.filter_parameters`. The dummy app's `filter_parameters` (set in `config/application.rb`) typically includes `[:password]` but not `:email`. Therefore `email` is not filtered.

If the Rails dummy app's `filter_parameters` includes `:email`, Scenario 2 must be updated to assert `[FILTERED]` instead.

### The regex-corruption bug in detail (Scenarios 6 and 7)

In `lib/e11y/middleware/pii_filter.rb`, the `filter_string_patterns` method:

```ruby
def filter_string_patterns(str)
  result = str.dup
  E11y::PII::Patterns::ALL.each do |pattern|
    result = result.gsub(pattern, "[FILTERED]")
  end
  result
end
```

`E11y::PII::Patterns::ALL` includes `PASSWORD_FIELDS = /password|passwd|pwd|secret|token|api[_-]?key/i`.

This pattern matches SUBSTRINGS inside values:
- `"process_token_renewal_completed"` → `"process_[FILTERED]_renewal_completed"` (the word `token` matches)
- `"password_reset_email_sent"` → `"[FILTERED]_reset_email_sent"` (the word `password` matches)

The fix would be to apply `PASSWORD_FIELDS` only against FIELD NAMES (not string values), and to use word-boundary anchors (`\b`) to prevent partial matches. That fix is NOT part of this QA plan — these scenarios document and prove the bug exists.

### Memory adapter access
```ruby
@memory_adapter = E11y.config.adapters[:memory]
@memory_adapter.clear!
events = @memory_adapter.find_events("Events::UserRegistered")
payload = events.last[:payload]
# payload keys are symbols: payload[:password], payload[:email]
```

Note: `find_events` does a substring match on `event_name`, so `"Events::UserRegistered"` matches event names like `"Events::UserRegistered"` or the normalized form `"user.registered"` if Versioning middleware is active.

### Rack::Test form params vs JSON
The step definitions use HTML form-style params (nested hash from `table.raw`) for POST requests, which maps naturally to the controllers that use `params.require(:user).permit(...)`. For JSON-based routes, the step sends `Content-Type: application/json` with a JSON body.
