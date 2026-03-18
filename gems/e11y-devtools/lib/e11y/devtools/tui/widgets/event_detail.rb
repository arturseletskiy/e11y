# frozen_string_literal: true

require "ratatui_ruby"
require "json"

module E11y
  module Devtools
    module Tui
      module Widgets
        # Full-screen popup overlay showing event payload + metadata.
        class EventDetail
          def initialize(event:)
            @event = event
          end

          def render(frame, area)
            popup_area = centered_rect(area, percent_x: 80, percent_y: 70)

            frame.render_widget(frame.clear, popup_area)

            sev   = @event["severity"] || "info"
            title = " #{@event['event_name']} · #{sev.upcase} "

            frame.render_widget(
              frame.paragraph(text: build_lines)
                   .block(title: title, borders: :all)
                   .scroll(0),
              popup_area
            )
          end

          private

          def build_lines
            lines = []
            lines << "  timestamp:  #{@event['timestamp']}"
            lines << "  trace_id:   #{@event['trace_id']}"
            lines << "  span_id:    #{@event['span_id']}"
            lines << ""
            lines << "  payload:"
            JSON.pretty_generate(@event["payload"] || {}).each_line do |l|
              lines << "    #{l.chomp}"
            end
            lines << ""
            lines << "  [c] copy JSON    [b] back"
            lines
          end

          def centered_rect(area, percent_x:, percent_y:)
            w = (area.width  * percent_x / 100).to_i
            h = (area.height * percent_y / 100).to_i
            x = area.x + ((area.width  - w) / 2)
            y = area.y + ((area.height - h) / 2)
            RatatuiRuby::Rect.new(x: x, y: y, width: w, height: h)
          end
        end
      end
    end
  end
end
