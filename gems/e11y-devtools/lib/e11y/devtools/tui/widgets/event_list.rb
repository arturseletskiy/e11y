# frozen_string_literal: true

require "ratatui_ruby"

module E11y
  module Devtools
    module Tui
      module Widgets
        # Renders a table of events for the selected trace.
        class EventList
          SEVERITY_COLORS = {
            "debug" => :dark_gray,
            "info" => :white,
            "warn" => :yellow,
            "error" => :red,
            "fatal" => :red
          }.freeze

          def initialize(events:, trace_id:, selected_index: 0)
            @events         = events
            @trace_id       = trace_id
            @selected_index = selected_index
          end

          def render(tui, frame, area)
            frame.render_widget(
              tui.table(
                header: ["#", "Severity", "Event Name", "Duration", "At"],
                rows: build_rows(tui),
                row_highlight_style: { bg: :dark_gray },
                selected_row: @selected_index,
                block: tui.block(title: " #{@trace_id} ", borders: :all)
              ),
              area
            )
          end

          private

          def build_rows(tui)
            @events.each_with_index.map do |e, i|
              sev   = e["severity"] || "info"
              color = SEVERITY_COLORS.fetch(sev, :white)
              [
                (i + 1).to_s,
                tui.span(content: sev.upcase, style: { fg: color }),
                e["event_name"].to_s,
                duration_str(e),
                timestamp_short(e["timestamp"])
              ]
            end
          end

          def duration_str(event)
            ms = event.dig("metadata", "duration_ms")
            ms ? "#{ms}ms" : "—"
          end

          def timestamp_short(timestamp)
            return "—" unless timestamp

            Time.parse(timestamp).strftime(".%L")
          rescue ArgumentError
            "—"
          end
        end
      end
    end
  end
end
