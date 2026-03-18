# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"
require "securerandom"
require "time"
require "fileutils"
require "e11y/adapters/dev_log/query"

# Load tool files (guarded in case mcp gem is absent)
[
  "recent_events", "events_by_trace", "search", "stats", "errors", "clear"
].each do |name|
  require "e11y/devtools/mcp/tools/#{name}"
end

RSpec.describe "MCP Tools" do
  let(:dir)   { Dir.mktmpdir("e11y_mcp") }
  let(:path)  { ::File.join(dir, "e11y_dev.jsonl") }
  let(:store) { E11y::Adapters::DevLog::Query.new(path) }
  let(:ctx)   { { store: store } }

  after { FileUtils.remove_entry(dir) }

  def write_event(overrides = {})
    data = {
      "id"         => SecureRandom.uuid,
      "timestamp"  => Time.now.iso8601(3),
      "event_name" => "test.event",
      "severity"   => "info",
      "trace_id"   => "t1",
      "payload"    => {},
      "metadata"   => {}
    }.merge(overrides)
    ::File.open(path, "a") { |f| f.puts(JSON.generate(data)) }
  end

  describe E11y::Devtools::Mcp::Tools::RecentEvents do
    it "returns recent events as array" do
      write_event
      result = described_class.call(limit: 10, server_context: ctx)
      expect(result).to be_an(Array)
      expect(result.first["event_name"]).to eq("test.event")
    end

    it "respects limit" do
      5.times { write_event }
      result = described_class.call(limit: 2, server_context: ctx)
      expect(result.size).to eq(2)
    end

    it "filters by severity" do
      write_event("severity" => "info")
      write_event("severity" => "error")
      result = described_class.call(limit: 10, severity: "error", server_context: ctx)
      expect(result.all? { |e| e["severity"] == "error" }).to be true
    end
  end

  describe E11y::Devtools::Mcp::Tools::EventsByTrace do
    it "returns events for given trace_id" do
      write_event("trace_id" => "abc", "event_name" => "a")
      write_event("trace_id" => "xyz", "event_name" => "b")
      result = described_class.call(trace_id: "abc", server_context: ctx)
      expect(result.size).to eq(1)
      expect(result.first["event_name"]).to eq("a")
    end
  end

  describe E11y::Devtools::Mcp::Tools::Search do
    it "finds events matching query" do
      write_event("event_name" => "payment.failed")
      write_event("event_name" => "order.created")
      result = described_class.call(query: "payment", limit: 10, server_context: ctx)
      expect(result.size).to eq(1)
    end
  end

  describe E11y::Devtools::Mcp::Tools::Stats do
    it "returns stats hash" do
      write_event
      result = described_class.call(server_context: ctx)
      expect(result).to be_a(Hash)
      expect(result).to have_key(:total_events)
    end
  end

  describe E11y::Devtools::Mcp::Tools::Errors do
    it "returns only error/fatal events" do
      write_event("severity" => "info")
      write_event("severity" => "error")
      result = described_class.call(limit: 10, server_context: ctx)
      expect(result.all? { |e| %w[error fatal].include?(e["severity"]) }).to be true
    end
  end

  describe E11y::Devtools::Mcp::Tools::Clear do
    it "clears the log and returns confirmation string" do
      write_event
      result = described_class.call(server_context: ctx)
      expect(result).to include("cleared")
      expect(store.stored_events).to be_empty
    end
  end
end
