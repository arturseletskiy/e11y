# frozen_string_literal: true

require "ratatui_ruby"
require_relative "../grouping"

module E11y
  module Devtools
    module Tui
      module Widgets
        # Renders a scrollable list of interaction groups.
        # Each row shows: bullet (● error / ○ ok), time, trace count.
        class InteractionList
          def initialize(interactions:, selected_index: 0, source_filter: :all)
            @interactions   = interactions
            @selected_index = selected_index
            @source_filter  = source_filter
          end

          def render(frame, area)
            rows = @interactions.map do |ix|
              bullet    = ix.has_error? ? "●" : "○"
              bullet_fg = ix.has_error? ? :red : :gray
              time_str  = ix.started_at.strftime("%H:%M:%S")
              count_str = "#{ix.traces_count} req"
              error_str = ix.has_error? ? "  ● err" : ""

              "#{frame.span(bullet, style: { fg: bullet_fg })} #{time_str}  #{count_str}#{error_str}"
            end

            frame.render_widget(
              frame.list(
                items: rows,
                highlight_style: { bg: :dark_gray },
                selected: @selected_index
              ).block(title: " INTERACTIONS ", borders: :all),
              area
            )
          end
        end
      end
    end
  end
end
