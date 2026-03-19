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
        # Full-text search across event names and payload content.
        class Search < ToolBase
          description "Full-text search across event names and payload content"

          input_schema(
            type: :object,
            required: ["query"],
            properties: {
              query: { type: :string, description: "Search term" },
              limit: { type: :integer, description: "Max results", default: 50 }
            }
          )

          def self.call(query:, server_context:, limit: 50)
            server_context[:store].search(query, limit: limit)
          end
        end
      end
    end
  end
end
