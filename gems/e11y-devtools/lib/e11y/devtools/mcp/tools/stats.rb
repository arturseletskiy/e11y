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
        # Returns aggregate statistics about the E11y development log.
        class Stats < ToolBase
          description "Get aggregate statistics about the E11y development log"

          input_schema(
            type: :object,
            properties: {}
          )

          def self.call(server_context:, **_opts)
            server_context[:store].stats
          end
        end
      end
    end
  end
end
