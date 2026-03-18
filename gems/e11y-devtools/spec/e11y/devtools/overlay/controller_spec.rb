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
end
