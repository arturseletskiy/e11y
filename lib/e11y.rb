# frozen_string_literal: true

require "zeitwerk"

# Zeitwerk autoloader setup
loader = Zeitwerk::Loader.for_gem
loader.setup

# E11y - Event-Driven Observability for Ruby on Rails
#
# @example Basic usage
#   E11y.configure do |config|
#     config.adapters = [:loki, :sentry]
#   end
#
#   E11y.track(Events::UserSignup.new(user_id: 123))
#
# @see https://e11y.dev Documentation
module E11y
  class Error < StandardError; end

  class << self
    # Configure E11y
    #
    # @yield [Configuration] configuration object
    # @return [void]
    #
    # @example
    #   E11y.configure do |config|
    #     config.adapters = [:loki, :stdout]
    #     config.log_level = :debug
    #   end
    def configure
      yield configuration if block_given?
    end

    # Get current configuration
    #
    # @return [Configuration] current configuration instance
    def configuration
      @configuration ||= Configuration.new
    end

    # Track an event
    #
    # @param event [Event] event instance to track
    # @return [void]
    #
    # @example
    #   E11y.track(Events::UserSignup.new(user_id: 123))
    def track(event)
      # TODO: Implement in Phase 1
      raise NotImplementedError, "E11y.track will be implemented in Phase 1"
    end

    # Get logger instance
    #
    # @return [Logger] logger instance
    def logger
      require "logger"
      @logger ||= ::Logger.new($stdout)
    end

    # Reset configuration (primarily for testing)
    #
    # @return [void]
    # @api private
    def reset!
      @configuration = nil
      @logger = nil
    end
  end

  # Placeholder Configuration class (will be implemented in Phase 1)
  class Configuration
    attr_accessor :adapters, :log_level

    def initialize
      @adapters = []
      @log_level = :info
    end
  end
end

# Eager load for production (optional - uncomment if needed)
# loader.eager_load if ENV["RAILS_ENV"] == "production"
