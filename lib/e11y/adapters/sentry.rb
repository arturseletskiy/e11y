# frozen_string_literal: true

# Check if Sentry SDK is available
begin
  require "sentry-ruby"
rescue LoadError
  raise LoadError, <<~ERROR
    Sentry SDK not available!

    To use E11y::Adapters::Sentry, add to your Gemfile:

      gem 'sentry-ruby'

    Then run: bundle install
  ERROR
end

module E11y
  module Adapters
    # Sentry adapter for error tracking and breadcrumbs.
    #
    # Features:
    # - Automatic error reporting to Sentry
    # - Breadcrumb tracking for context
    # - Severity-based filtering
    # - Trace context propagation
    # - User context support
    #
    # @example Basic usage
    #   adapter = E11y::Adapters::Sentry.new(
    #     dsn: ENV["SENTRY_DSN"],
    #     environment: "production",
    #     severity_threshold: :warn
    #   )
    #
    # @example Configuration
    #   config.adapters[:sentry] = E11y::Adapters::Sentry.new(dsn: ENV["SENTRY_DSN"])
    #
    # @see https://docs.sentry.io/platforms/ruby/
    # rubocop:disable Metrics/ClassLength
    # Sentry adapter contains error transformation and context enrichment logic
    class Sentry < Base
      # Severity levels in order
      SEVERITY_LEVELS = %i[debug info success warn error fatal].freeze

      # Default severity threshold for Sentry
      DEFAULT_SEVERITY_THRESHOLD = :warn

      attr_reader :dsn, :environment, :severity_threshold, :send_breadcrumbs

      # Initialize Sentry adapter
      #
      # @param config [Hash] Configuration options
      # @option config [String] :dsn (required) Sentry DSN
      # @option config [String] :environment ("production") Environment name
      # @option config [Symbol] :severity_threshold (:warn) Minimum severity to send to Sentry
      # @option config [Boolean] :breadcrumbs (true) Enable breadcrumb tracking
      def initialize(config = {})
        @dsn = config[:dsn]
        @environment = config.fetch(:environment, "production")
        @severity_threshold = config.fetch(:severity_threshold, DEFAULT_SEVERITY_THRESHOLD)
        @send_breadcrumbs = config.fetch(:breadcrumbs, true)

        super

        initialize_sentry!
      end

      # Write event to Sentry
      #
      # @param event_data [Hash] Event payload
      # @return [Boolean] Success status
      def write(event_data)
        severity = event_data[:severity]

        # Only send events above threshold
        return true unless should_send_to_sentry?(severity)

        if error_severity?(severity)
          send_error_to_sentry(event_data)
        elsif @send_breadcrumbs
          send_breadcrumb_to_sentry(event_data)
        end

        true
      rescue StandardError => e
        warn "E11y Sentry adapter error: #{e.message}"
        false
      end

      # Adapter capabilities
      #
      # @return [Hash] Capability flags
      def capabilities
        super.merge(
          batching: false, # Sentry SDK handles batching
          compression: false, # Sentry SDK handles compression
          async: true, # Sentry SDK is async
          streaming: false
        )
      end

      # Check if adapter is healthy
      #
      # @return [Boolean] True if Sentry is configured
      def healthy?
        ::Sentry.initialized?
      end

      private

      # Validate configuration
      def validate_config!
        raise ArgumentError, "Sentry adapter requires :dsn" unless @dsn

        return if SEVERITY_LEVELS.include?(@severity_threshold)

        raise ArgumentError,
              "Invalid severity_threshold: #{@severity_threshold}"
      end

      # Initialize Sentry SDK
      def initialize_sentry!
        ::Sentry.init do |config|
          config.dsn = @dsn
          config.environment = @environment
          config.breadcrumbs_logger = [] # We manage breadcrumbs manually
        end
      end

      # Check if severity should be sent to Sentry
      #
      # @param severity [Symbol] Event severity
      # @return [Boolean] True if severity >= threshold
      def should_send_to_sentry?(severity)
        threshold_index = SEVERITY_LEVELS.index(@severity_threshold)
        current_index = SEVERITY_LEVELS.index(severity)

        return false unless threshold_index && current_index

        current_index >= threshold_index
      end

      # Check if severity is error-level
      #
      # @param severity [Symbol] Event severity
      # @return [Boolean] True if error or fatal
      def error_severity?(severity)
        %i[error fatal].include?(severity)
      end

      # Send error to Sentry
      #
      # @param event_data [Hash] Event data
      # rubocop:disable Metrics/AbcSize
      # Sentry scope configuration requires multiple context enrichment steps
      def send_error_to_sentry(event_data)
        ::Sentry.with_scope do |scope|
          # Set tags
          scope.set_tags(extract_tags(event_data))

          # Set extras
          scope.set_extras(event_data[:payload] || {})

          # Set user context
          scope.set_user(event_data[:user] || {}) if event_data[:user]

          # Set trace context
          if event_data[:trace_id]
            scope.set_context("trace", {
                                trace_id: event_data[:trace_id],
                                span_id: event_data[:span_id]
                              })
          end

          # Capture exception or message
          if event_data[:exception]
            ::Sentry.capture_exception(event_data[:exception])
          else
            ::Sentry.capture_message(
              event_data[:message] || event_data[:event_name].to_s,
              level: sentry_level(event_data[:severity])
            )
          end
        end
      end
      # rubocop:enable Metrics/AbcSize

      # Send breadcrumb to Sentry
      #
      # @param event_data [Hash] Event data
      def send_breadcrumb_to_sentry(event_data)
        ::Sentry.add_breadcrumb(
          ::Sentry::Breadcrumb.new(
            category: event_data[:event_name].to_s,
            message: event_data[:message]&.to_s,
            level: sentry_level(event_data[:severity]),
            data: event_data[:payload] || {},
            timestamp: event_data[:timestamp]&.to_i
          )
        )
      end

      # Extract tags from event
      #
      # @param event_data [Hash] Event data
      # @return [Hash] Tags for Sentry
      def extract_tags(event_data)
        {
          event_name: event_data[:event_name].to_s,
          severity: event_data[:severity].to_s,
          environment: @environment
        }
      end

      # Map E11y severity to Sentry level
      #
      # @param severity [Symbol] E11y severity
      # @return [Symbol] Sentry level
      # rubocop:disable Lint/DuplicateBranch
      # Multiple severity levels intentionally map to :info (info, success, unknown)
      def sentry_level(severity)
        case severity
        when :debug then :debug
        when :info, :success then :info
        when :warn then :warning
        when :error then :error
        when :fatal then :fatal
        else :info
        end
      end
      # rubocop:enable Lint/DuplicateBranch
    end
    # rubocop:enable Metrics/ClassLength
  end
end
