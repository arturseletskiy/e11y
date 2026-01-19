# frozen_string_literal: true

require "active_support/concern"

module E11y
  module Instruments
    # ActiveJob integration for job-scoped context and trace propagation.
    #
    # Provides callbacks to:
    # 1. Inject trace context when job is enqueued (before_enqueue)
    # 2. Set up job-scoped context when job executes (around_perform)
    #
    # @example Setup (automatic via Railtie)
    #   class ApplicationJob < ActiveJob::Base
    #     include E11y::Instruments::ActiveJob::Callbacks
    #   end
    #
    # @see ADR-008 §10 (ActiveJob Integration)
    module ActiveJob
      # Callbacks module to be included into ActiveJob classes.
      # Provides before_enqueue and around_perform callbacks for trace propagation.
      module Callbacks
        extend ActiveSupport::Concern

        included do
          # Inject trace context before enqueueing
          before_enqueue do |job|
            job.e11y_trace_id = E11y::Current.trace_id if E11y::Current.trace_id
            job.e11y_span_id = E11y::Current.span_id if E11y::Current.span_id
          end

          # Set up job-scoped context around job execution
          around_perform do |job, block|
            # Extract trace context from job metadata (propagated from enqueue)
            trace_id = job.e11y_trace_id || generate_trace_id
            span_id = generate_span_id # Always generate new span for job execution

            # Set job-scoped context (same E11y::Current as for HTTP requests)
            E11y::Current.trace_id = trace_id
            E11y::Current.span_id = span_id
            E11y::Current.request_id = job.job_id # Use ActiveJob ID as request_id

            # Start job-scoped buffer (for debug events)
            E11y::Buffers::RequestScopedBuffer.start! if E11y.config.request_buffer&.enabled

            # Execute job
            block.call
          rescue StandardError
            # Flush buffer on error (includes debug events)
            E11y::Buffers::RequestScopedBuffer.flush_on_error! if E11y.config.request_buffer&.enabled

            raise # Re-raise original exception
          ensure
            # Flush buffer on success (not on error, already flushed in rescue)
            if !$ERROR_INFO && E11y.config.request_buffer&.enabled # No exception occurred
              E11y::Buffers::RequestScopedBuffer.flush!
            end

            # Reset context
            E11y::Current.reset
          end
        end

        private

        # Generate new trace_id (32-character hex)
        # @return [String]
        def generate_trace_id
          SecureRandom.hex(16)
        end

        # Generate new span_id (16-character hex)
        # @return [String]
        def generate_span_id
          SecureRandom.hex(8)
        end
      end

      # Custom attribute accessors for trace context
      module TraceAttributes
        def e11y_trace_id
          @e11y_trace_id
        end

        def e11y_trace_id=(value)
          @e11y_trace_id = value
        end

        def e11y_span_id
          @e11y_span_id
        end

        def e11y_span_id=(value)
          @e11y_span_id = value
        end
      end
    end
  end
end

# Extend ActiveJob::Base with trace attributes
ActiveJob::Base.include(E11y::Instruments::ActiveJob::TraceAttributes) if defined?(ActiveJob::Base)
