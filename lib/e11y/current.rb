# frozen_string_literal: true

require "active_support"
require "active_support/current_attributes"

module E11y
  # Request-scoped context using ActiveSupport::CurrentAttributes (Rails Way).
  #
  # Stores trace_id, span_id, user_id, and other request-scoped data
  # for the duration of a single request. Automatically managed by
  # E11y::Middleware::Request.
  #
  # @example Setting request context
  #   E11y::Current.set(
  #     trace_id: "abc123",
  #     span_id: "def456",
  #     user_id: 42
  #   )
  #
  # @example Accessing context
  #   E11y::Current.trace_id  # => "abc123"
  #   E11y::Current.user_id   # => 42
  #
  # @example Resetting context
  #   E11y::Current.reset
  #
  # @see https://api.rubyonrails.org/classes/ActiveSupport/CurrentAttributes.html
  class Current < ActiveSupport::CurrentAttributes
    attribute :trace_id
    attribute :span_id
    attribute :request_id
    attribute :user_id
    attribute :ip_address
    attribute :user_agent
    attribute :request_method
    attribute :request_path
  end
end
