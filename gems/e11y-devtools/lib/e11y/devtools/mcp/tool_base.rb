# frozen_string_literal: true

module E11y
  module Devtools
    module Mcp
      # Conditional base: use MCP::Tool if available, otherwise plain class.
      # This allows tests to run without the mcp gem installed.
      ToolBase = if defined?(MCP::Tool)
                   MCP::Tool
                 else
                   Class.new do
                     def self.description(desc = nil)
                       @description = desc if desc
                       @description
                     end

                     def self.input_schema(schema = nil)
                       @input_schema = schema if schema
                       @input_schema
                     end
                   end
                 end
    end
  end
end
