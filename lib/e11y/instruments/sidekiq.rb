# frozen_string_literal: true

module E11y
  module Instruments
    # Sidekiq integration for job-scoped context and trace propagation.
    #
    # Provides two middleware:
    # 1. ClientMiddleware - Injects trace context when job is enqueued
    # 2. ServerMiddleware - Sets up job-scoped context when job executes
    #
    # @example Setup (automatic via Railtie)
    #   Sidekiq.configure_server do |config|
    #     config.server_middleware do |chain|
    #       chain.add E11y::Instruments::Sidekiq::ServerMiddleware
    #     end
    #   end
    #
    #   Sidekiq.configure_client do |config|
    #     config.client_middleware do |chain|
    #       chain.add E11y::Instruments::Sidekiq::ClientMiddleware
    #     end
    #   end
    #
    # @see ADR-008 §9 (Sidekiq Integration)
    module Sidekiq
      # Client-side middleware: Inject trace context when enqueueing job
      #
      # **C17 Hybrid Tracing**: Propagates parent_trace_id to job metadata.
      # Job will create NEW trace_id but keep link to parent.
      class ClientMiddleware
        def call(_worker_class, job, _queue, _redis_pool)
          # Inject current trace context into job metadata as parent trace
          # Job will generate NEW trace_id but keep parent link (C17)
          job["e11y_parent_trace_id"] = E11y::Current.trace_id if E11y::Current.trace_id
          job["e11y_parent_span_id"] = E11y::Current.span_id if E11y::Current.span_id

          yield
        end
      end

      # Server-side middleware: Set up job-scoped context when executing job
      #
      # **C17 Hybrid Tracing**: Creates NEW trace_id for job, but preserves parent link.
      # **C18 Non-Failing**: E11y errors don't fail jobs (observability is secondary to business logic).
      class ServerMiddleware
        # rubocop:disable Metrics/AbcSize
        def call(_worker, job, queue)
          # C18: Disable fail_on_error for jobs (observability should not block business logic)
          original_fail_on_error = E11y.config.error_handling.fail_on_error
          E11y.config.error_handling.fail_on_error = false

          setup_job_context(job)
          setup_job_buffer

          # Track job start time for SLO
          start_time = Time.now
          job_status = :success

          # Execute job (business logic)
          yield
        rescue StandardError => e
          job_status = :failed
          # Check if this is E11y error (circuit breaker, retry exhausted, etc.)
          handle_job_error(e)

          raise # Always re-raise original exception
        ensure
          # Track SLO metrics
          track_job_slo(job, queue, job_status, start_time)

          cleanup_job_context

          # Restore original setting
          E11y.config.error_handling.fail_on_error = original_fail_on_error
        end
        # rubocop:enable Metrics/AbcSize

        private

        # Setup job-scoped context (C17 Hybrid Tracing)
        def setup_job_context(job)
          # Extract parent trace context from job metadata
          parent_trace_id = job["e11y_parent_trace_id"]

          # Generate NEW trace_id for this job (not reuse parent!)
          trace_id = generate_trace_id
          span_id = generate_span_id

          # Set job-scoped context
          E11y::Current.trace_id = trace_id
          E11y::Current.span_id = span_id
          E11y::Current.parent_trace_id = parent_trace_id
          E11y::Current.request_id = job["jid"]
        end

        # Setup job-scoped buffer
        def setup_job_buffer
          return unless E11y.config.request_buffer&.enabled

          E11y::Buffers::RequestScopedBuffer.start!
        rescue StandardError => e
          # C18: Don't fail job if buffer setup fails
          warn "[E11y] Failed to start job buffer: #{e.message}"
        end

        # Handle job error (C18: Non-Failing Event Tracking)
        def handle_job_error(_error)
          # Flush buffer on error (includes debug events)
          return unless E11y.config.request_buffer&.enabled

          E11y::Buffers::RequestScopedBuffer.flush_on_error!
        rescue StandardError => e
          # C18: Don't fail job if buffer flush fails
          warn "[E11y] Failed to flush job buffer on error: #{e.message}"
        end

        # Cleanup job-scoped context
        def cleanup_job_context
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

        # Track Sidekiq job for SLO metrics (if enabled).
        #
        # @param job [Hash] Sidekiq job hash
        # @param queue [String] Queue name
        # @param status [Symbol] Job status (:success or :failed)
        # @param start_time [Time] Job start time
        # @return [void]
        # @api private
        def track_job_slo(job, queue, status, start_time)
          return unless E11y.config.slo_tracking&.enabled

          duration_ms = ((Time.now - start_time) * 1000).round(2)

          require "e11y/slo/tracker"
          E11y::SLO::Tracker.track_background_job(
            job_class: job["class"],
            status: status,
            duration_ms: duration_ms,
            queue: queue
          )
        rescue StandardError => e
          # C18: Don't fail if SLO tracking fails
          warn "[E11y] SLO tracking error: #{e.message}"
        end
      end
    end
  end
end
