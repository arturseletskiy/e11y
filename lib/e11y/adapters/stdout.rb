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
      # @option config [Boolean] :pretty_print (true) Enable pretty-printed JSON (when format: :json)
      # @option config [Symbol] :format (:json) Output format: :json (JSON), :compact (single-line JSON), :rich (ADR-010 §3 structured)
      def initialize(config = {})
        @colorize = config.fetch(:colorize, true)
        @format = config.fetch(:format, :json)
        @pretty_print = resolve_pretty_print(config)
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

      # Resolve pretty_print from format or pretty_print keys
      #
      # @param config [Hash] Adapter config
      # @return [Boolean]
      def resolve_pretty_print(config)
        return config[:pretty_print] if config.key?(:pretty_print)

        case config[:format]
        when :compact then false
        when :pretty then true
        else config.fetch(:pretty_print, true)
        end
      end

      # Format event for console output
      #
      # @param event_data [Hash] Event data
      # @return [String] Formatted output
      def format_event(event_data)
        case @format
        when :rich then format_event_rich(event_data)
        when :compact then event_data.to_json
        else @pretty_print ? JSON.pretty_generate(event_data) : event_data.to_json
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

      # Rich format: ADR-010 §3 — structured output with header, event name, payload, metadata
      def format_event_rich(event_data)
        lines = []
        lines << format_header(event_data)
        lines << format_event_name_line(event_data)
        lines << format_payload_section(event_data[:payload]) if event_data[:payload]&.any?
        lines << format_metadata_section(event_data) if event_data[:trace_id] || event_data[:span_id]
        lines << "─" * 80
        lines.join("\n")
      end

      def format_header(event_data)
        ts = event_data[:timestamp]
        ts = Time.parse(ts) if ts.is_a?(String)
        time_str = ts&.strftime("%H:%M:%S.%L") || "??:??:??.???"
        sev = event_data[:severity].to_s.upcase.ljust(8)
        "#{time_str} #{sev}"
      end

      def format_event_name_line(event_data)
        name = event_data[:event_name].to_s
        "  → #{name}"
      end

      def format_payload_section(payload)
        lines = ["  Payload:"]
        payload.each do |k, v|
          lines << "    #{k}: #{format_value_rich(v)}"
        end
        lines.join("\n")
      end

      def format_metadata_section(event_data)
        meta = { trace_id: event_data[:trace_id], span_id: event_data[:span_id] }.compact
        return "" if meta.empty?

        meta.map { |k, v| "    #{k}: #{v}" }.unshift("  Metadata:").join("\n")
      end

      def format_value_rich(value)
        case value
        when String then "\"#{value.length > 50 ? "#{value[0...50]}..." : value}\""
        when Array then "[#{value.size} items]"
        when Hash then "{#{value.size} keys}"
        else value.inspect
        end
      end
    end

    # Alias for ADR-010 §3 (Console Output) — Console and Stdout are the same adapter
    Console = Stdout
  end
end
