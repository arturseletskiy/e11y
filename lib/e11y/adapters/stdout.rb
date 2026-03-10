# frozen_string_literal: true

require "json"

module E11y
  module Adapters
    # Stdout Adapter - Console output for development and debugging
    #
    # Outputs events to STDOUT with optional colorization and pretty printing.
    # Primarily for development use.
    #
    # **Features:**
    # - Colorized output based on severity
    # - Pretty-print JSON (optional)
    # - Streaming output
    #
    # @example Configuration
    #   E11y.configure do |config|
    #     config.register_adapter :stdout, E11y::Adapters::Stdout.new(
    #       colorize: true,
    #       pretty_print: true
    #     )
    #   end
    #
    # @see ADR-004 §4.1 (Stdout Adapter)
    class Stdout < Base
      # ANSI color codes for severity levels
      SEVERITY_COLORS = {
        debug: "\e[37m",      # Gray
        info: "\e[36m",       # Cyan
        success: "\e[32m",    # Green
        warn: "\e[33m",       # Yellow
        error: "\e[31m",      # Red
        fatal: "\e[35m"       # Magenta
      }.freeze

      # Color reset
      COLOR_RESET = "\e[0m"

      # Initialize adapter
      #
      # @param config [Hash] Configuration options
      # @option config [Boolean] :colorize (true) Enable colored output
      # @option config [Boolean] :pretty_print (true) Enable pretty-printed JSON
      def initialize(config = {})
        @colorize = config.fetch(:colorize, true)
        @pretty_print = if config.key?(:format)
                          config[:format] != :compact
                        else
                          config.fetch(:pretty_print, true)
                        end

        super
      end

      # Write event to STDOUT
      #
      # @param event_data [Hash] Event payload
      # @return [Boolean] true on success, false on failure
      def write(event_data)
        output = format_event(event_data)

        if @colorize
          puts colorize_output(output, event_data[:severity])
        else
          puts output
        end

        true
      rescue StandardError => e
        warn "Stdout adapter error: #{e.message}"
        false
      end

      # Adapter capabilities
      #
      # @return [Hash] Capability flags
      def capabilities
        {
          batching: false,
          compression: false,
          async: false,
          streaming: true
        }
      end

      private

      # Format event for console output
      #
      # @param event_data [Hash] Event data
      # @return [String] Formatted output
      def format_event(event_data)
        if @pretty_print
          JSON.pretty_generate(event_data)
        else
          event_data.to_json
        end
      end

      # Colorize output based on severity
      #
      # @param output [String] Formatted output
      # @param severity [Symbol] Event severity
      # @return [String] Colorized output
      def colorize_output(output, severity)
        color_code = SEVERITY_COLORS[severity] || ""
        "#{color_code}#{output}#{COLOR_RESET}"
      end
    end
  end
end
