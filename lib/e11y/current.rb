# frozen_string_literal: true

require "active_support"
require "active_support/current_attributes"

module E11y
  # Request/job-scoped context using ActiveSupport::CurrentAttributes (Rails Way).
  #
  # Stores trace_id, span_id, parent_trace_id, and other request/job-scoped data.
  # Automatically managed by E11y::Middleware::Request (HTTP) or
  # Sidekiq/ActiveJob middleware (background jobs).
  #
  # **Hybrid Tracing (C17 Resolution)**:
  # - HTTP Requests: new trace_id, parent_trace_id = nil
  # - Background Jobs: new trace_id, parent_trace_id = enqueuing request's trace_id
  #
  # @example Setting request context (HTTP)
  #   E11y::Current.trace_id = "abc123"
  #   E11y::Current.user_id = 42
  #   # parent_trace_id is nil for requests
  #
  # @example Setting context (Background job with parent link)
  #   E11y::Current.trace_id = "xyz789"         # NEW trace for job
  #   E11y::Current.parent_trace_id = "abc123"  # Link to parent request
  #
  # @example Accessing context
  #   E11y::Current.trace_id        # => "xyz789"
  #   E11y::Current.parent_trace_id # => "abc123"
  #
  # @example Resetting context
  #   E11y::Current.reset
  #
  # @see ADR-005 §8.3 (C17 Resolution: Hybrid Background Job Tracing)
  # @see UC-009 (Multi-Service Tracing with parent_trace_id)
  # @see UC-010 (Background Job Tracking)
  # @see https://api.rubyonrails.org/classes/ActiveSupport/CurrentAttributes.html
  class Current < ActiveSupport::CurrentAttributes
    attribute :trace_id
    attribute :span_id
    attribute :parent_trace_id # ✅ NEW: Link to parent trace (C17 Resolution)
    attribute :request_id
    attribute :user_id
    attribute :ip_address
    attribute :user_agent
    attribute :request_method
    attribute :request_path
  end
end
