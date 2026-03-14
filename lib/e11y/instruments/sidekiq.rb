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
      #
      # **Job lifecycle events**: Emits Events::Rails::Job::Enqueued for raw Sidekiq jobs only.
      # ActiveJob jobs are handled by RailsInstrumentation (ASN).
      class ClientMiddleware
        def call(worker_class, job, queue, _redis_pool)
          # Inject current trace context into job metadata as parent trace
          # Job will generate NEW trace_id but keep parent link (C17)
          job["e11y_parent_trace_id"] = E11y::Current.trace_id if E11y::Current.trace_id
          job["e11y_parent_span_id"] = E11y::Current.span_id if E11y::Current.span_id

          # Emit Enqueued for raw Sidekiq jobs only (ActiveJob emits via ASN)
          emit_job_enqueued(worker_class, job, queue) if raw_sidekiq_job?(job)

          yield
        end

        private

        def raw_sidekiq_job?(job)
          job_class = job["class"].to_s
          return false if job_class.include?("ActiveJob::QueueAdapters::SidekiqAdapter")
          return false if job["wrapped"].present?

          true
        end

        def emit_job_enqueued(worker_class, job, queue)
          Events::Rails::Job::Enqueued.track(
            event_name: "sidekiq.enqueue",
            duration: 0,
            job_class: worker_class.to_s,
            job_id: job["jid"],
            queue: queue
          )
        rescue StandardError => e
          warn "[E11y] Failed to emit job Enqueued: #{e.message}"
        end
      end

      # Server-side middleware: Set up job-scoped context when executing job
      #
      # **C17 Hybrid Tracing**: Creates NEW trace_id for job, but preserves parent link.
      # **C18 Non-Failing**: E11y errors don't fail jobs (observability is secondary to business logic).
      #
      # **Job lifecycle events**: Emits Events::Rails::Job::Started/Completed/Failed for raw Sidekiq jobs only.
      # ActiveJob jobs (when Sidekiq is the queue adapter) are handled by RailsInstrumentation (ASN).
      class ServerMiddleware
        def call(worker, job, queue)
          # C18: Disable fail_on_error for jobs (observability should not block business logic)
          original_fail_on_error = E11y.config.error_handling.fail_on_error
          E11y.config.error_handling.fail_on_error = false

          setup_job_context(job)
          setup_job_buffer

          # Track job start time for SLO
          start_time = Time.now
          job_status = :success

          # Emit Started for raw Sidekiq jobs only (ActiveJob jobs emit via ASN)
          emit_job_started(job, queue) if raw_sidekiq_job?(job)

          # Execute job (business logic)
          yield
        rescue StandardError => e
          job_status = :failed
          # Emit Failed for raw Sidekiq jobs
          emit_job_failed(job, queue, start_time, e) if raw_sidekiq_job?(job)
          # Check if this is E11y error (circuit breaker, retry exhausted, etc.)
          handle_job_error(e)

          raise # Always re-raise original exception
        ensure
          # Emit Completed for raw Sidekiq jobs (only on success; Failed already emitted in rescue)
          emit_job_completed(job, queue, start_time) if raw_sidekiq_job?(job) && job_status == :success

          # Track SLO metrics
          track_job_slo(job, queue, job_status, start_time)

          cleanup_job_context

          # Restore original setting
          E11y.config.error_handling.fail_on_error = original_fail_on_error
        end

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

        # Setup request-scoped buffer (same as HTTP; optional job_buffer_limit)
        def setup_job_buffer
          return unless E11y.config.ephemeral_buffer&.enabled

          limit = E11y.config.ephemeral_buffer.job_buffer_limit ||
                  E11y::Buffers::EphemeralBuffer::DEFAULT_BUFFER_LIMIT
          E11y::Buffers::EphemeralBuffer.initialize!(buffer_limit: limit)
        rescue StandardError => e
          # C18: Don't fail job if buffer setup fails
          warn "[E11y] Failed to start job buffer: #{e.message}"
        end

        # Handle job error (C18: Non-Failing Event Tracking)
        def handle_job_error(_error)
          # Flush buffer on error (includes debug events)
          return unless E11y.config.ephemeral_buffer&.enabled

          E11y::Buffers::EphemeralBuffer.flush_on_error
        rescue StandardError => e
          # C18: Don't fail job if buffer flush fails
          warn "[E11y] Failed to flush job buffer on error: #{e.message}"
        end

        # Cleanup job-scoped context
        def cleanup_job_context
          # Discard buffer on success (not on error, already flushed in rescue)
          if !$ERROR_INFO && E11y.config.ephemeral_buffer&.enabled
            begin
              E11y::Buffers::EphemeralBuffer.discard
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

        # True if this is a raw Sidekiq job (not ActiveJob-wrapped).
        # ActiveJob jobs use Sidekiq via JobWrapper; we skip event emission for them
        # because RailsInstrumentation (ASN) handles ActiveJob events.
        #
        # @param job [Hash] Sidekiq job hash
        # @return [Boolean]
        def raw_sidekiq_job?(job)
          job_class = job["class"].to_s
          return false if job_class.include?("ActiveJob::QueueAdapters::SidekiqAdapter")
          return false if job["wrapped"].present?

          true
        end

        def emit_job_started(job, queue)
          Events::Rails::Job::Started.track(
            event_name: "sidekiq.perform_start",
            duration: 0,
            job_class: job["class"],
            job_id: job["jid"],
            queue: queue
          )
        rescue StandardError => e
          warn "[E11y] Failed to emit job Started: #{e.message}"
        end

        def emit_job_completed(job, queue, start_time)
          duration_ms = ((Time.now - start_time) * 1000).round(2)
          Events::Rails::Job::Completed.track(
            event_name: "sidekiq.perform",
            duration: duration_ms,
            job_class: job["class"],
            job_id: job["jid"],
            queue: queue
          )
        rescue StandardError => e
          warn "[E11y] Failed to emit job Completed: #{e.message}"
        end

        def emit_job_failed(job, queue, start_time, error)
          duration_ms = ((Time.now - start_time) * 1000).round(2)
          Events::Rails::Job::Failed.track(
            event_name: "sidekiq.perform",
            duration: duration_ms,
            job_class: job["class"],
            job_id: job["jid"],
            queue: queue,
            error_class: error.class.name,
            error_message: error.message
          )
        rescue StandardError => e
          warn "[E11y] Failed to emit job Failed: #{e.message}"
        end
      end
    end
  end
end
