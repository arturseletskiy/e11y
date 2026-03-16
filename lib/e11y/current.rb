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
    attribute :sampled # Trace-consistent sampling (ADR-005 §7)
    attribute :request_id
    attribute :user_id
    attribute :ip_address
    attribute :user_agent
    attribute :request_method
    attribute :request_path

    # Returns current attributes as a hash for sampling context (symbol keys, nil values omitted).
    # Callers may merge job-specific keys (job_class, queue) when in job context.
    #
    # @return [Hash{Symbol=>Object}]
    def self.to_context
      {
        trace_id: trace_id,
        span_id: span_id,
        parent_trace_id: parent_trace_id,
        sampled: sampled,
        request_id: request_id,
        user_id: user_id,
        ip_address: ip_address,
        user_agent: user_agent,
        request_method: request_method,
        request_path: request_path
      }.compact
    end
  end
end
