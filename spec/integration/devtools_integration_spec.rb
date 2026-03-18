# spec/integration/devtools_integration_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "e11y/adapters/dev_log"
require "tmpdir"

RSpec.describe "DevTools E2E", :integration do
  let(:tmpdir) { Dir.mktmpdir("e11y_e2e") }
  let(:adapter) { E11y::Adapters::DevLog.new(path: path) }
  let(:query)   { E11y::Adapters::DevLog::Query.new(path) }
  let(:path) { File.join(tmpdir, "e11y_dev.jsonl") }

  after { FileUtils.remove_entry(tmpdir) }

  describe "write → read → search pipeline" do
    before do
      adapter.write(event_name: "payment.failed", severity: "error",
                    trace_id: "trace-1", payload: { code: "declined" }, metadata: {})
      adapter.write(event_name: "order.created", severity: "info",
                    trace_id: "trace-2", payload: { amount: 99 }, metadata: {})
    end

    it "stores and retrieves all events" do
      expect(query.stored_events.size).to eq(2)
    end

    it "searches by event_name" do
      expect(query.search("payment").size).to eq(1)
    end

    it "retrieves events by trace_id" do
      expect(query.events_by_trace("trace-1").size).to eq(1)
    end

    it "returns correct severity stats" do
      stats = query.stats
      expect(stats[:by_severity]["error"]).to eq(1)
      expect(stats[:by_severity]["info"]).to  eq(1)
      expect(stats[:total_events]).to          eq(2)
    end

    it "find_event returns event by id" do
      adapter.write(event_name: "x", severity: "info", trace_id: "t99",
                    payload: {}, metadata: {})
      event_id = query.stored_events.first["id"]
      found = query.find_event(event_id)
      expect(found).not_to be_nil
      expect(found["id"]).to eq(event_id)
    end
  end

  describe "interaction grouping" do
    it "groups traces started within 500ms into one interaction" do
      t = Time.now
      # Two parallel requests within 300ms → one interaction
      adapter.write(event_name: "e", severity: "info", trace_id: "t1",
                    payload: {}, metadata: { "source" => "web", "started_at" => t.iso8601(3) })
      adapter.write(event_name: "e", severity: "error", trace_id: "t2",
                    payload: {}, metadata: { "source" => "web", "started_at" => (t + 0.2).iso8601(3) })
      # Third request 2 seconds later → different interaction
      adapter.write(event_name: "e", severity: "info", trace_id: "t3",
                    payload: {}, metadata: { "source" => "web", "started_at" => (t + 2.0).iso8601(3) })

      groups = query.interactions(window_ms: 500)
      expect(groups.size).to eq(2)
      # interactions are oldest-first (chronological order)
      expect(groups.last.trace_ids).to eq(["t3"])
      expect(groups.first.trace_ids.sort).to eq(%w[t1 t2].sort)
    end

    it "marks interaction has_error? based on any event having error severity" do
      t = Time.now
      adapter.write(event_name: "e", severity: "error", trace_id: "t1",
                    payload: {}, metadata: { "source" => "web", "started_at" => t.iso8601(3) })
      adapter.write(event_name: "e", severity: "info",  trace_id: "t1",
                    payload: {}, metadata: { "source" => "web", "started_at" => t.iso8601(3) })

      groups = query.interactions(window_ms: 500)
      expect(groups.first.has_error?).to be true
    end
  end

  describe "rotation" do
    it "keeps keep_rotated .gz files and discards older ones" do
      small_adapter = E11y::Adapters::DevLog.new(
        path: path, max_lines: 3, keep_rotated: 2
      )
      10.times do |i|
        small_adapter.write(event_name: "e#{i}", severity: "info",
                            trace_id: "t#{i}", payload: {}, metadata: {})
      end
      expect(File.exist?("#{path}.1.gz")).to be true
      expect(File.exist?("#{path}.3.gz")).to be false # beyond keep_rotated: 2
    end
  end

  describe "clear!" do
    it "removes the log file and returns empty events" do
      adapter.write(event_name: "x", severity: "info", trace_id: "t1",
                    payload: {}, metadata: {})
      expect(query.stored_events.size).to eq(1)

      query.clear!
      expect(query.stored_events).to be_empty
    end
  end

  describe "updated_since?" do
    it "returns true after new events are written" do
      past = Time.now - 60
      adapter.write(event_name: "x", severity: "info", trace_id: "t1",
                    payload: {}, metadata: {})
      expect(query.updated_since?(past)).to be true
    end
  end
end
