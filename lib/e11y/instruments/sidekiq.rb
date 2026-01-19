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
      class ServerMiddleware
        # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        def call(_worker, job, _queue)
          # Extract parent trace context from job metadata (C17 Hybrid Tracing)
          parent_trace_id = job["e11y_parent_trace_id"]

          # Generate NEW trace_id for this job (not reuse parent!) - C17 Resolution
          trace_id = generate_trace_id
          span_id = generate_span_id

          # Set job-scoped context (same E11y::Current as for HTTP requests)
          E11y::Current.trace_id = trace_id
          E11y::Current.span_id = span_id
          E11y::Current.parent_trace_id = parent_trace_id # ✅ Link to parent request
          E11y::Current.request_id = job["jid"] # Use Sidekiq job ID as request_id

          # Start job-scoped buffer (for debug events)
          E11y::Buffers::RequestScopedBuffer.start! if E11y.config.request_buffer&.enabled

          # Execute job
          yield
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
        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

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
    end
  end
end
