# frozen_string_literal: true

# features/step_definitions/pii_filtering_steps.rb
#
# Step definitions specific to pii_filtering.feature.
# Generic event count and field assertions are in common_steps.rb.

# ---------------------------------------------------------------------------
# HTTP request steps — PII-specific routes
# ---------------------------------------------------------------------------

When("I POST user params to {string}:") do |path, table|
  params = table.rows_hash
  post path, params
end

When("I POST payment params to {string}:") do |path, table|
  params = table.rows_hash
  post path, params
end

When("I GET {string} with Authorization header {string}") do |path, auth_value|
  get path, {}, { "HTTP_AUTHORIZATION" => auth_value }
end

# Sends an order with status "process_token_renewal_completed" to trigger
# the BUG-008 filter_string_patterns corruption of non-sensitive token substrings.
When("I POST order params with a token-like status to {string}") do |path|
  post path, { "order[status]" => "process_token_renewal_completed" }
end

# Sends a report with description containing "password" to trigger
# the BUG-009 filter_string_patterns corruption of non-sensitive password substrings.
When("I POST report params with description {string} to {string}") do |description, path|
  post path, { "report[description]" => description, "report[title]" => "Test Report" }
end
