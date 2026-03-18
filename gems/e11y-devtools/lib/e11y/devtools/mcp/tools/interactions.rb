# frozen_string_literal: true

begin
  require "mcp"
rescue LoadError
  # mcp gem not available — ToolBase will use plain class
end
require_relative "../tool_base"

module E11y
  module Devtools
    module Mcp
      module Tools
        # Returns time-grouped interactions (parallel requests from one user action).
        class Interactions < ToolBase
          description "Get time-grouped interactions (parallel requests from one user action)"

          input_schema(
            type: :object,
            properties: {
              limit: { type: :integer, description: "Max interactions", default: 20 },
              window_ms: { type: :integer, description: "Grouping window in ms", default: 500 }
            }
          )

          def self.call(server_context:, limit: 20, window_ms: 500)
            server_context[:store].interactions(limit: limit, window_ms: window_ms).map do |ix|
              {
                started_at: ix.started_at.iso8601(3),
                trace_ids: ix.trace_ids,
                has_error: ix.has_error?,
                traces_count: ix.traces_count
              }
            end
          end
        end
      end
    end
  end
end
