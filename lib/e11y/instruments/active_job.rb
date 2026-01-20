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
          # Inject trace context before enqueueing (C17 Hybrid Tracing)
          # Store parent trace context for job to link back to originating request
          before_enqueue do |job|
            # Store current trace as parent (job will create NEW trace)
            job.e11y_parent_trace_id = E11y::Current.trace_id if E11y::Current.trace_id
            job.e11y_parent_span_id = E11y::Current.span_id if E11y::Current.span_id
          end

          # Set up job-scoped context around job execution (C17 Hybrid Tracing + C18 Non-Failing)
          around_perform do |job, block|
            # C18: Disable fail_on_error for jobs (observability should not block business logic)
            original_fail_on_error = E11y.config.error_handling.fail_on_error
            E11y.config.error_handling.fail_on_error = false

            setup_job_context_active_job(job)
            setup_job_buffer_active_job

            # Track job start time for SLO
            start_time = Time.now
            job_status = :success

            # Execute job (business logic)
            block.call
          rescue StandardError => e
            job_status = :failed
            # Handle error (C18: Non-Failing Event Tracking)
            handle_job_error_active_job(e)

            raise # Always re-raise original exception
          ensure
            # Track SLO metrics
            track_job_slo_active_job(job, job_status, start_time)

            cleanup_job_context_active_job

            # Restore original setting
            E11y.config.error_handling.fail_on_error = original_fail_on_error
          end
        end

        private

        # Setup job-scoped context (C17 Hybrid Tracing)
        def setup_job_context_active_job(job)
          # Extract parent trace context from job metadata
          parent_trace_id = job.e11y_parent_trace_id

          # Generate NEW trace_id for this job (not reuse parent!)
          trace_id = generate_trace_id
          span_id = generate_span_id

          # Set job-scoped context
          E11y::Current.trace_id = trace_id
          E11y::Current.span_id = span_id
          E11y::Current.parent_trace_id = parent_trace_id
          E11y::Current.request_id = job.job_id
        end

        # Setup job-scoped buffer
        def setup_job_buffer_active_job
          return unless E11y.config.request_buffer&.enabled

          E11y::Buffers::RequestScopedBuffer.start!
        rescue StandardError => e
          # C18: Don't fail job if buffer setup fails
          warn "[E11y] Failed to start job buffer: #{e.message}"
        end

        # Handle job error (C18: Non-Failing Event Tracking)
        def handle_job_error_active_job(_error)
          return unless E11y.config.request_buffer&.enabled

          E11y::Buffers::RequestScopedBuffer.flush_on_error!
        rescue StandardError => e
          # C18: Don't fail job if buffer flush fails
          warn "[E11y] Failed to flush job buffer on error: #{e.message}"
        end

        # Cleanup job-scoped context
        def cleanup_job_context_active_job
          # Flush buffer on success (not on error, already flushed in rescue)
          if !$ERROR_INFO && E11y.config.request_buffer&.enabled
            begin
              E11y::Buffers::RequestScopedBuffer.flush!
            rescue StandardError => e
              # C18: Don't fail job if buffer flush fails
              warn "[E11y] Failed to flush job buffer: #{e.message}"
            end
          end

          # Reset context (always, even if flush failed)
          E11y::Current.reset
        rescue StandardError => e
          # C18: Absolutely don't fail job on context cleanup
          warn "[E11y] Failed to reset job context: #{e.message}"
        end

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

        # Track ActiveJob for SLO metrics (if enabled).
        #
        # @param job [ActiveJob::Base] Job instance
        # @param status [Symbol] Job status (:success or :failed)
        # @param start_time [Time] Job start time
        # @return [void]
        # @api private
        def track_job_slo_active_job(job, status, start_time)
          return unless E11y.config.slo_tracking&.enabled

          duration_ms = ((Time.now - start_time) * 1000).round(2)

          require "e11y/slo/tracker"
          E11y::SLO::Tracker.track_background_job(
            job_class: job.class.name,
            status: status,
            duration_ms: duration_ms,
            queue: job.queue_name
          )
        rescue StandardError => e
          # C18: Don't fail if SLO tracking fails
          E11y.logger.warn("[E11y] SLO tracking error: #{e.message}", error: e.class.name)
        end
      end

      # Custom attribute accessors for trace context (C17 Hybrid Tracing)
      module TraceAttributes
        def e11y_parent_trace_id
          @e11y_parent_trace_id
        end

        def e11y_parent_trace_id=(value)
          @e11y_parent_trace_id = value
        end

        def e11y_parent_span_id
          @e11y_parent_span_id
        end

        def e11y_parent_span_id=(value)
          @e11y_parent_span_id = value
        end

        # Deprecated: Jobs should create NEW trace_id (C17)
        # These are kept for backward compatibility but should not be used.
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
