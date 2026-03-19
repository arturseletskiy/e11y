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
        # Clears the E11y development log file.
        class Clear < ToolBase
          description "Clear the E11y development log file"

          input_schema(
            type: :object,
            properties: {}
          )

          def self.call(server_context:, **_opts)
            server_context[:store].clear!
            "E11y log cleared successfully"
          end
        end
      end
    end
  end
end
