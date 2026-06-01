# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "tempfile"

RSpec.describe E11y::Adapters::DevLog do
  subject(:adapter) { described_class.new(path: path) }

  let(:dir)  { Dir.mktmpdir("e11y_devlog") }
  let(:path) { File.join(dir, "e11y_dev.jsonl") }

  after { FileUtils.remove_entry(dir) }

  describe "#write" do
    let(:event_data) do
      {
        event_name: "order.created",
        severity: "info",
        trace_id: "abc123",
        payload: { order_id: 1 },
        metadata: {}
      }
    end

    it "returns true on success" do
      expect(adapter.write(event_data)).to be true
    end

    it "writes a JSON line to the file" do
      adapter.write(event_data)
      line = JSON.parse(File.readlines(path).last)
      expect(line["event_name"]).to eq("order.created")
    end

    it "adds an id to every event" do
      adapter.write(event_data)
      line = JSON.parse(File.readlines(path).last)
      expect(line["id"]).to be_a(String)
      expect(line["id"]).not_to be_empty
    end

    it "adds a timestamp if not present" do
      adapter.write(event_data)
      line = JSON.parse(File.readlines(path).last)
      expect(line["timestamp"]).to be_a(String)
    end

    it "preserves existing timestamp" do
      ts = "2026-01-01T00:00:00.000Z"
      adapter.write(event_data.merge(timestamp: ts))
      line = JSON.parse(File.readlines(path).last)
      expect(line["timestamp"]).to eq(ts)
    end

    it "sets metadata.source from Thread.current[:e11y_source] when present" do
      Thread.current[:e11y_source] = "job"
      adapter.write(event_data)
      line = JSON.parse(File.readlines(path).last)
      expect(line.dig("metadata", "source")).to eq("job")
    ensure
      Thread.current[:e11y_source] = nil
    end

    it "defaults metadata.source to 'web' when Thread.current not set" do
      Thread.current[:e11y_source] = nil
      adapter.write(event_data)
      line = JSON.parse(File.readlines(path).last)
      expect(line.dig("metadata", "source")).to eq("web")
    end

    it "stores event_class as a constant path string, not #<Class:0x…>" do
      stub_const("E11yDevLogProbeEventClass", Class.new)
      adapter.write(
        event_data.merge(event_class: E11yDevLogProbeEventClass)
      )
      line = JSON.parse(File.readlines(path).last)
      expect(line["event_class"]).to eq("E11yDevLogProbeEventClass")
    end

    it "omits event_class when the class is anonymous" do
      anon = Class.new
      adapter.write(event_data.merge(event_class: anon, event_name: nil))
      line = JSON.parse(File.readlines(path).last)
      expect(line).not_to have_key("event_class")
    end

    it "promotes payload event_name to top level when top-level event_name is blank" do
      adapter.write(
        event_name: nil,
        severity: "info",
        trace_id: "abc123",
        payload: { event_name: "sql.active_record", sql: "SELECT 1" },
        metadata: {}
      )
      line = JSON.parse(File.readlines(path).last)
      expect(line["event_name"]).to eq("sql.active_record")
    end

    describe "HTTP enrichment" do
      let(:adapter) { described_class.new(path: tmp_path) }
      let(:tmp_path) { Tempfile.new(["e11y_test", ".jsonl"]).path }

      after { FileUtils.rm_f(tmp_path) }

      it "stores http_method from Thread.current in metadata" do
        Thread.current[:e11y_http_method] = "POST"
        Thread.current[:e11y_http_path]   = "/orders"
        Thread.current[:e11y_http_status]      = 201
        Thread.current[:e11y_http_duration_ms] = 42
        Thread.current[:e11y_source]           = "web"

        adapter.write({ event_name: "orders.created", severity: "info" })

        event = adapter.stored_events(limit: 1).first
        expect(event.dig("metadata", "http_method")).to eq("POST")
        expect(event.dig("metadata", "http_path")).to   eq("/orders")
        expect(event.dig("metadata", "http_status")).to  eq(201)
        expect(event.dig("metadata", "duration_ms")).to  eq(42)
      ensure
        Thread.current[:e11y_http_method]      = nil
        Thread.current[:e11y_http_path]        = nil
        Thread.current[:e11y_http_status]      = nil
        Thread.current[:e11y_http_duration_ms] = nil
        Thread.current[:e11y_source]           = nil
      end

      it "leaves http fields absent when Thread.current has no HTTP context" do
        adapter.write({ event_name: "bg.job", severity: "info" })
        event = adapter.stored_events(limit: 1).first
        expect(event.dig("metadata", "http_method")).to be_nil
        expect(event.dig("metadata", "http_path")).to be_nil
      end

      it "does not overwrite http fields already present in event_data" do
        Thread.current[:e11y_http_method] = "DELETE"
        adapter.write({
                        event_name: "test",
                        severity: "info",
                        metadata: { "http_method" => "GET", "http_path" => "/existing" }
                      })
        event = adapter.stored_events(limit: 1).first
        expect(event.dig("metadata", "http_method")).to eq("GET")
      ensure
        Thread.current[:e11y_http_method] = nil
      end
    end
  end

  describe "read API delegation" do
    before do
      adapter.write(event_name: "a", severity: "info",  trace_id: "t1", payload: {}, metadata: {})
      adapter.write(event_name: "b", severity: "error", trace_id: "t2", payload: {}, metadata: {})
    end

    it "#stored_events returns all events" do
      expect(adapter.stored_events.size).to eq(2)
    end

    it "#stats returns aggregate data" do
      stats = adapter.stats
      expect(stats[:total_events]).to eq(2)
      expect(stats[:by_severity]["error"]).to eq(1)
    end

    it "#search finds by event_name" do
      expect(adapter.search("event_name_a")).to be_an(Array)
    end

    it "#events_by_trace returns correct events" do
      events = adapter.events_by_trace("t1")
      expect(events.size).to eq(1)
      expect(events.first["event_name"]).to eq("a")
    end

    it "#clear! removes the file" do
      adapter.clear!
      expect(File.exist?(path)).to be false
    end
  end

  describe "capabilities" do
    it "declares dev_log and readable capabilities" do
      caps = adapter.capabilities
      expect(caps[:dev_log]).to be true
      expect(caps[:readable]).to be true
    end
  end

  describe "inheritance" do
    it "inherits from E11y::Adapters::Base" do
      expect(adapter).to be_a(E11y::Adapters::Base)
    end
  end
end
