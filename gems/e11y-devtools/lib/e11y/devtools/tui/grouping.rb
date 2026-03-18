# frozen_string_literal: true

module E11y
  module Devtools
    module Tui
      # Pure-function time-window grouping for traces → interactions.
      # Shared by TUI widgets, Overlay, and MCP interactions tool.
      module Grouping
        # Severities that count as errors for interaction flagging.
        ERROR_SEVERITIES = %w[error fatal].freeze

        # Value object representing one interaction group.
        Interaction = Struct.new(:started_at, :trace_ids, :has_error?,
                                 :source)

        # Group an array of trace hashes into Interaction bands.
        #
        # @param traces     [Array<Hash>]  Each hash must have :trace_id,
        #                                  :started_at (Time), :severity
        # @param window_ms  [Integer]      Grouping window in milliseconds
        # @return [Array<Interaction>]     Newest-first
        def self.group(traces, window_ms: 500)
          return [] if traces.empty?

          build_interactions(accumulate_groups(traces, window_ms))
        end

        def self.accumulate_groups(traces, window_ms)
          sorted = traces.sort_by { |t| t[:started_at] }
          groups = []
          current = nil
          sorted.each { |trace| current = append_trace(groups, current, trace, window_ms) }
          groups
        end

        def self.append_trace(groups, current, trace, window_ms)
          if current.nil? || outside_window?(trace, current, window_ms)
            current = new_group(trace)
            groups << current
          end
          current[:trace_ids] << trace[:trace_id]
          current[:has_error] ||= ERROR_SEVERITIES.include?(trace[:severity])
          current
        end

        def self.outside_window?(trace, current, window_ms)
          (trace[:started_at] - current[:anchor]) * 1000 > window_ms
        end

        def self.new_group(trace)
          { anchor: trace[:started_at], started_at: trace[:started_at],
            trace_ids: [], has_error: false, source: trace[:source] }
        end

        def self.build_interactions(groups)
          groups.reverse.map do |g|
            Interaction.new(g[:started_at], g[:trace_ids], g[:has_error], g[:source])
          end
        end

        private_class_method :accumulate_groups, :append_trace,
                             :outside_window?, :new_group, :build_interactions
      end
    end
  end
end
