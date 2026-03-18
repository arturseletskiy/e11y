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
        # Returns the full payload of a single event by ID.
        class EventDetail < ToolBase
          description "Get full payload of a single event by ID"

          input_schema(
            type: :object,
            required: ["event_id"],
            properties: {
              event_id: { type: :string, description: "Event UUID" }
            }
          )

          def self.call(event_id:, server_context:)
            server_context[:store].find_event(event_id) || { error: "Event #{event_id} not found" }
          end
        end
      end
    end
  end
end
