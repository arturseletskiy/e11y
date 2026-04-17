# spec/e11y/adapters/dev_log/query_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "tempfile"
require "json"
require "time"

RSpec.describe E11y::Adapters::DevLog::Query do
  subject(:query) { described_class.new(path) }

  let(:dir)  { Dir.mktmpdir("e11y_query") }
  let(:path) { File.join(dir, "e11y_dev.jsonl") }

  after { FileUtils.remove_entry(dir) }

  def write_events(*events)
    File.open(path, "a") { |f| events.each { |e| f.puts(JSON.generate(e)) } }
  end

  def build_event(overrides = {})
    {
      "id" => SecureRandom.uuid,
      "timestamp" => Time.now.iso8601(3),
      "event_name" => "test.event",
      "severity" => "info",
      "trace_id" => SecureRandom.hex(8),
      "span_id" => SecureRandom.hex(4),
      "payload" => { "key" => "value" },
      "metadata" => { "source" => "web", "path" => "/test", "duration_ms" => 10 }
    }.merge(overrides.transform_keys(&:to_s))
  end

  describe "#stored_events" do
    it "returns empty array when file does not exist" do
      expect(query.stored_events).to eq([])
    end

    it "returns events newest-first" do
      t = Time.now
      write_events(
        build_event("id" => "old", "timestamp" => (t - 10).iso8601(3)),
        build_event("id" => "new", "timestamp" => t.iso8601(3))
      )
      events = query.stored_events
      expect(events.first["id"]).to eq("new")
    end

    it "respects limit" do
      5.times { |i| write_events(build_event("id" => i.to_s)) }
      expect(query.stored_events(limit: 3).size).to eq(3)
    end

    it "filters by severity" do
      write_events(
        build_event("severity" => "info"),
        build_event("severity" => "error")
      )
      events = query.stored_events(severity: "error")
      expect(events.size).to eq(1)
      expect(events.first["severity"]).to eq("error")
    end

    it "filters by source" do
      write_events(
        build_event("metadata" => { "source" => "web" }),
        build_event("metadata" => { "source" => "job" })
      )
      events = query.stored_events(source: "web")
      expect(events.size).to eq(1)
    end
  end

  describe "#find_event" do
    it "returns nil when not found" do
      expect(query.find_event("nope")).to be_nil
    end

    it "finds event by id" do
      event = build_event("id" => "target-123")
      write_events(build_event, event, build_event)
      found = query.find_event("target-123")
      expect(found["id"]).to eq("target-123")
    end
  end

  describe "#search" do
    it "returns empty array when no match" do
      write_events(build_event("event_name" => "order.created"))
      expect(query.search("payment")).to eq([])
    end

    it "matches by event_name substring" do
      write_events(
        build_event("event_name" => "payment.failed"),
        build_event("event_name" => "order.created")
      )
      results = query.search("payment")
      expect(results.size).to eq(1)
    end

    it "matches inside payload JSON" do
      write_events(build_event("payload" => { "order_id" => "ORD-7821" }))
      expect(query.search("ORD-7821").size).to eq(1)
    end
  end

  describe "#events_by_trace" do
    it "returns all events for a trace in chronological order" do
      trace_id = "abc123"
      write_events(
        build_event("trace_id" => trace_id, "event_name" => "a"),
        build_event("trace_id" => "other",  "event_name" => "b"),
        build_event("trace_id" => trace_id, "event_name" => "c")
      )
      events = query.events_by_trace(trace_id)
      expect(events.size).to eq(2)
      expect(events.map { |e| e["event_name"] }).to eq(%w[a c])
    end
  end

  describe "#stats" do
    it "returns zeroed stats when file does not exist" do
      stats = query.stats
      expect(stats[:total_events]).to eq(0)
      expect(stats[:file_size]).to eq(0)
    end

    it "counts by severity" do
      write_events(
        build_event("severity" => "info"),
        build_event("severity" => "info"),
        build_event("severity" => "error")
      )
      stats = query.stats
      expect(stats[:total_events]).to eq(3)
      expect(stats[:by_severity]["info"]).to eq(2)
      expect(stats[:by_severity]["error"]).to eq(1)
    end
  end

  describe "#updated_since?" do
    it "returns false when file does not exist" do
      expect(query.updated_since?(Time.now)).to be false
    end

    it "returns true when file was modified after given time" do
      write_events(build_event)
      expect(query.updated_since?(Time.now - 60)).to be true
    end

    it "returns false when file is older than given time" do
      write_events(build_event)
      expect(query.updated_since?(Time.now + 60)).to be false
    end
  end

  describe "#clear!" do
    it "removes the file" do
      write_events(build_event)
      query.clear!
      expect(File.exist?(path)).to be false
    end
  end

  describe "#interactions HTTP fields" do
    let(:tmp) { Tempfile.new(["q_http", ".jsonl"]) }
    let(:query) { described_class.new(tmp.path) }

    after do
      tmp.close
      tmp.unlink
    end

    def write_event(data)
      tmp.puts(JSON.generate(data))
      tmp.flush
    end

    it "exposes http_method, http_path, http_status, duration_ms on Interaction" do
      write_event({
                    "trace_id" => "abc",
                    "severity" => "info",
                    "timestamp" => "2026-04-03T10:00:00.000Z",
                    "metadata" => {
                      "source" => "web",
                      "started_at" => "2026-04-03T10:00:00.000Z",
                      "http_method" => "GET",
                      "http_path" => "/dashboard",
                      "http_status" => 200,
                      "duration_ms" => 55
                    }
                  })

      ix = query.interactions.first
      expect(ix.http_method).to eq("GET")
      expect(ix.http_path).to eq("/dashboard")
      expect(ix.http_status).to eq(200)
      expect(ix.duration_ms).to eq(55)
    end

    it "returns nil HTTP fields when metadata has no HTTP context" do
      write_event({
                    "trace_id" => "xyz",
                    "severity" => "info",
                    "timestamp" => "2026-04-03T10:00:00.000Z",
                    "metadata" => { "source" => "job", "started_at" => "2026-04-03T10:00:00.000Z" }
                  })
      ix = query.interactions.first
      expect(ix.http_method).to be_nil
      expect(ix.http_path).to be_nil
    end
  end

  describe "#interactions" do
    it "returns empty array when no events" do
      expect(query.interactions).to eq([])
    end

    it "groups traces starting within window_ms into one interaction" do
      t = Time.now
      write_events(
        build_event("trace_id" => "t1", "metadata" => { "source" => "web", "started_at" => t.iso8601(3) }),
        build_event("trace_id" => "t2", "metadata" => { "source" => "web", "started_at" => (t + 0.3).iso8601(3) }),
        build_event("trace_id" => "t3", "metadata" => { "source" => "web", "started_at" => (t + 1.2).iso8601(3) })
      )
      groups = query.interactions(window_ms: 500)
      expect(groups.size).to eq(2)
      expect(groups.first.trace_ids.sort).to eq(%w[t1 t2].sort)
      expect(groups.last.trace_ids).to eq(%w[t3])
    end

    it "marks interaction has_error? when any trace event has error severity" do
      t = Time.now
      write_events(
        build_event("trace_id" => "t1", "severity" => "error",
                    "metadata" => { "source" => "web", "started_at" => t.iso8601(3) }),
        build_event("trace_id" => "t1", "severity" => "info",
                    "metadata" => { "source" => "web", "started_at" => t.iso8601(3) })
      )
      groups = query.interactions(window_ms: 500)
      expect(groups.first.has_error?).to be true
    end

    it "filters by source" do
      t = Time.now
      write_events(
        build_event("trace_id" => "w1", "metadata" => { "source" => "web", "started_at" => t.iso8601(3) }),
        build_event("trace_id" => "j1", "metadata" => { "source" => "job", "started_at" => t.iso8601(3) })
      )
      groups = query.interactions(window_ms: 500, source: "web")
      expect(groups.first.trace_ids).to eq(%w[w1])
    end
  end

  describe "caching" do
    it "returns same result on second call without re-reading file" do
      write_events(build_event)
      query.stored_events # prime cache
      # Poison the file but preserve mtime so cache key doesn't change
      original_mtime = File.mtime(path)
      File.write(path, "INVALID JSON\n")
      File.utime(original_mtime, original_mtime, path)
      events = query.stored_events
      expect(events.size).to eq(1)
    end

    it "invalidates cache when file mtime changes" do
      write_events(build_event)
      query.stored_events # prime cache
      sleep 0.01
      write_events(build_event)
      FileUtils.touch(path)
      events = query.stored_events
      expect(events.size).to eq(2)
    end
  end
end
