# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"
require "securerandom"
require "e11y/adapters/dev_log/query"
require "e11y/devtools/overlay/controller"

RSpec.describe E11y::Devtools::Overlay::Controller do
  let(:dir) { Dir.mktmpdir("e11y_ctrl") }
  let(:controller) { described_class.new(query) }
  let(:path)    { File.join(dir, "e11y_dev.jsonl") }
  let(:query)   { E11y::Adapters::DevLog::Query.new(path) }

  after { FileUtils.remove_entry(dir) }

  def write_event(name: "test.event", severity: "info", trace_id: "t1")
    data = {
      "id" => SecureRandom.uuid, "timestamp" => Time.now.iso8601(3),
      "event_name" => name, "severity" => severity,
      "trace_id" => trace_id, "payload" => {}, "metadata" => {}
    }
    File.open(path, "a") { |f| f.puts(JSON.generate(data)) }
  end

  describe "#events_for" do
    it "returns events_by_trace when trace_id given" do
      write_event(trace_id: "abc")
      result = controller.events_for(trace_id: "abc")
      expect(result).to be_an(Array)
      expect(result.first["trace_id"]).to eq("abc")
    end

    it "returns recent events when no trace_id" do
      write_event
      result = controller.events_for(trace_id: nil)
      expect(result).to be_an(Array)
      expect(result.size).to eq(1)
    end
  end

  describe "#recent_events" do
    it "returns limited recent events" do
      3.times { write_event }
      result = controller.recent_events(limit: 2)
      expect(result.size).to eq(2)
    end
  end

  describe "#clear_log!" do
    it "removes the log file" do
      write_event
      controller.clear_log!
      expect(File.exist?(path)).to be false
    end
  end

  describe "#v1_interactions" do
    it "returns hashes with trace_ids and traces_count" do
      write_event(name: "a", trace_id: "t1", severity: "info")
      write_event(name: "b", trace_id: "t2", severity: "error")
      rows = controller.v1_interactions(source: nil, limit: 10, window_ms: 500)
      expect(rows).to be_an(Array)
      expect(rows.first).to include("started_at", "trace_ids", "has_error", "source", "traces_count")
      expect(rows.first["trace_ids"]).to be_an(Array)
      expect(rows.first["traces_count"]).to eq(rows.first["trace_ids"].size)
    end
  end

  describe "#v1_interactions — HTTP fields" do
    let(:controller) { described_class.new(fake_query) }

    let(:fake_query) do
      double("query").tap do |q|
        allow(q).to receive(:interactions).and_return([
                                                        E11y::Adapters::DevLog::Query::Interaction.new(
                                                          Time.parse("2026-04-03T10:00:00Z"),
                                                          ["trace-1"],
                                                          false,
                                                          "web",
                                                          "GET", "/orders", 200, 45
                                                        )
                                                      ])
      end
    end

    it "includes method, path, status, duration_ms in the response hash" do
      result = controller.v1_interactions
      row = result.first
      expect(row["method"]).to eq("GET")
      expect(row["path"]).to eq("/orders")
      expect(row["status"]).to eq(200)
      expect(row["duration_ms"]).to eq(45)
    end
  end

  describe "#v1_trace_events" do
    it "returns events for trace in order" do
      write_event(name: "first", trace_id: "tx")
      write_event(name: "second", trace_id: "tx")
      rows = controller.v1_trace_events("tx")
      expect(rows.map { |e| e["event_name"] }).to eq(%w[first second])
    end

    it "returns empty array for blank trace id" do
      expect(controller.v1_trace_events("")).to eq([])
    end
  end

  describe "#v1_recent_events" do
    it "respects limit clamp" do
      5.times { write_event }
      rows = controller.v1_recent_events(limit: 2)
      expect(rows.size).to eq(2)
    end
  end
end
