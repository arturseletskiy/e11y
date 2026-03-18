# frozen_string_literal: true

require "pathname"
require "e11y/adapters/dev_log/query"
require_relative "tools/recent_events"
require_relative "tools/events_by_trace"
require_relative "tools/search"
require_relative "tools/stats"
require_relative "tools/interactions"
require_relative "tools/event_detail"
require_relative "tools/errors"
require_relative "tools/clear"

module E11y
  module Devtools
    module Mcp
      # MCP Server wrapping the E11y DevLog adapter.
      #
      # Exposes 8 tools to AI tools like Cursor and Claude Code.
      # Supports stdio (default) and StreamableHTTP transports.
      #
      # @example Start stdio server
      #   E11y::Devtools::Mcp::Server.new.run
      #
      # @example Start HTTP server on port 3099
      #   E11y::Devtools::Mcp::Server.new.run(transport: :http, port: 3099)
      class Server
        TOOLS = [
          Tools::RecentEvents, Tools::EventsByTrace, Tools::Search,
          Tools::Stats, Tools::Interactions, Tools::EventDetail,
          Tools::Errors, Tools::Clear
        ].freeze

        def initialize(log_path: nil)
          @log_path = log_path || auto_detect_log_path
          @store    = E11y::Adapters::DevLog::Query.new(@log_path)
        end

        # Start the MCP server.
        #
        # @param transport [:stdio, :http] Transport to use
        # @param port      [Integer, nil]  HTTP port (default 3099)
        def run(transport: :stdio, port: nil)
          require "mcp"
          server = build_mcp_server
          case transport
          when :stdio then run_stdio(server)
          when :http  then run_http(server, port || 3099)
          else raise ArgumentError, "Unknown transport: #{transport}"
          end
        end

        private

        def build_mcp_server
          MCP::Server.new(
            name: "e11y",
            version: E11y::Devtools::VERSION,
            tools: TOOLS,
            server_context: { store: @store }
          )
        end

        def run_stdio(server)
          t = MCP::Server::Transports::StdioTransport.new(server)
          server.transport = t
          t.open
        end

        def run_http(server, port)
          require "webrick"
          t = MCP::Server::Transports::StreamableHTTPTransport.new(server)
          server.transport = t
          s = WEBrick::HTTPServer.new(Port: port, Logger: WEBrick::Log.new(nil))
          s.mount("/mcp", t)
          trap("INT") { s.shutdown }
          s.start
        end

        def auto_detect_log_path
          dir = Pathname.new(Dir.pwd)
          loop do
            candidate = dir.join("log", "e11y_dev.jsonl")
            return candidate.to_s if candidate.exist?

            parent = dir.parent
            break if parent == dir

            dir = parent
          end
          "log/e11y_dev.jsonl"
        end
      end
    end
  end
end
