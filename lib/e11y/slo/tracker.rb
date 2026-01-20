# frozen_string_literal: true

require "e11y/metrics"

module E11y
  module SLO
    # Zero-Config SLO Tracker for HTTP requests and background jobs.
    #
    # Automatically tracks Service Level Indicators (SLIs):
    # - HTTP request success rate (availability)
    # - HTTP request latency (p95, p99)
    # - Background job success rate
    # - Background job duration
    #
    # @see UC-004 (Zero-Config SLO Tracking)
    # @see ADR-003 §3 (Multi-Level SLO Strategy)
    #
    # @example Enable SLO tracking
    #   E11y.configure do |config|
    #     config.slo_tracking.enabled = true
    #   end
    #
    # @example Track HTTP request
    #   E11y::SLO::Tracker.track_http_request(
    #     controller: 'OrdersController',
    #     action: 'create',
    #     status: 200,
    #     duration_ms: 42.5
    #   )
    #
    # @note C11 Resolution (Sampling Correction): Not yet implemented.
    #   Requires Phase 2.8 (Stratified Sampling) for accurate SLO with sampling.
    module Tracker
      class << self
        # Track HTTP request for SLO metrics.
        #
        # @param controller [String] Controller name
        # @param action [String] Action name
        # @param status [Integer] HTTP status code
        # @param duration_ms [Numeric] Request duration in milliseconds
        # @return [void]
        def track_http_request(controller:, action:, status:, duration_ms:)
          return unless enabled?

          labels = {
            controller: controller,
            action: action,
            status: normalize_status(status)
          }

          # Track request count
          E11y::Metrics.increment(:slo_http_requests_total, labels)

          # Track request duration
          E11y::Metrics.histogram(
            :slo_http_request_duration_seconds,
            duration_ms / 1000.0,
            labels.except(:status),
            buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
          )
        end

        # Track background job for SLO metrics.
        #
        # @param job_class [String] Job class name
        # @param status [Symbol] Job status (:success or :failed)
        # @param duration_ms [Numeric] Job duration in milliseconds
        # @param queue [String, nil] Queue name (optional)
        # @return [void]
        def track_background_job(job_class:, status:, duration_ms:, queue: nil)
          return unless enabled?

          labels = {
            job_class: job_class,
            status: status.to_s
          }
          labels[:queue] = queue if queue

          # Track job count
          E11y::Metrics.increment(:slo_background_jobs_total, labels)

          # Track job duration (only for successful jobs)
          return unless status == :success

          E11y::Metrics.histogram(
            :slo_background_job_duration_seconds,
            duration_ms / 1000.0,
            labels.except(:status),
            buckets: [0.1, 0.5, 1, 5, 10, 30, 60, 300, 600]
          )
        end

        # Check if SLO tracking is enabled.
        #
        # @return [Boolean] true if enabled
        def enabled?
          E11y.config.respond_to?(:slo_tracking) && E11y.config.slo_tracking&.enabled
        end

        # Normalize HTTP status code to category (2xx, 3xx, 4xx, 5xx).
        #
        # @param status [Integer] HTTP status code
        # @return [String] Status category
        # @api private
        def normalize_status(status)
          case status
          when 200..299 then "2xx"
          when 300..399 then "3xx"
          when 400..499 then "4xx"
          when 500..599 then "5xx"
          else "unknown"
          end
        end

        private :normalize_status
      end
    end
  end
end
