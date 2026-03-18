# frozen_string_literal: true

require "e11y"
require_relative "devtools/version"

module E11y
  # Developer tooling for E11y: TUI, Browser Overlay, and MCP Server.
  module Devtools
    autoload :Tui,     "e11y/devtools/tui"
    autoload :Overlay, "e11y/devtools/overlay"
    autoload :Mcp,     "e11y/devtools/mcp"
  end
end
