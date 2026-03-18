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
        # Returns the most recent events from the dev log.
        class RecentEvents < ToolBase
          description "Get recent E11y events from the development log"

          input_schema(
            type: :object,
            properties: {
              limit: { type: :integer, description: "Max events to return (default 50)", default: 50 },
              severity: { type: :string, description: "Filter by severity",
                          enum: %w[debug info warn error fatal] }
            }
          )

          def self.call(server_context:, limit: 50, severity: nil)
            server_context[:store].stored_events(limit: limit, severity: severity)
          end
        end
      end
    end
  end
end
