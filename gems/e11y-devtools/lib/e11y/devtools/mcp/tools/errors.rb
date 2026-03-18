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
        # Returns recent error and fatal events only.
        class Errors < ToolBase
          ERROR_SEVERITIES = %w[error fatal].freeze

          description "Get recent error and fatal events only"

          input_schema(
            type: :object,
            properties: {
              limit: { type: :integer, description: "Max events", default: 20 }
            }
          )

          def self.call(server_context:, limit: 20)
            events = server_context[:store].stored_events(limit: limit * 5)
            events.select { |e| ERROR_SEVERITIES.include?(e["severity"]) }.first(limit)
          end
        end
      end
    end
  end
end
