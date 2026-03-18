# frozen_string_literal: true

require_relative "lib/e11y/devtools/version"

Gem::Specification.new do |spec|
  spec.name    = "e11y-devtools"
  spec.version = E11y::Devtools::VERSION
  spec.authors = ["Artur Seletskiy"]
  spec.summary = "Developer tools for E11y: TUI, Browser Overlay, MCP Server"

  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*.rb", "exe/*", "*.md"]
  spec.bindir        = "exe"
  spec.executables   = ["e11y"]
  spec.require_paths = ["lib"]

  spec.add_dependency "e11y", "~> #{E11y::Devtools::CORE_VERSION}"
  spec.add_dependency "mcp",          ">= 1.0"
  spec.add_dependency "ratatui_ruby", "~> 1.4"

  # Optional but recommended for performance
  spec.add_development_dependency "oj"
  spec.metadata["rubygems_mfa_required"] = "true"
end
