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
        # Returns all events for a specific trace ID in chronological order.
        class EventsByTrace < ToolBase
          description "Get all events for a specific trace ID in chronological order"

          input_schema(
            type: :object,
            required: ["trace_id"],
            properties: {
              trace_id: { type: :string, description: "Trace ID" }
            }
          )

          def self.call(trace_id:, server_context:)
            server_context[:store].events_by_trace(trace_id)
          end
        end
      end
    end
  end
end
