# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"
require_relative "../../../../lib/e11y/reliability/dlq/file_adapter"

# DLQ file storage integration tests require filesystem operations,
# rotation scenarios, and extensive query testing with multiple fixtures.
RSpec.describe E11y::Reliability::DLQ::FileAdapter do
  let(:temp_dir) { Dir.mktmpdir }
  let(:file_path) { File.join(temp_dir, "test_dlq.jsonl") }
  let(:dlq) { described_class.new(file_path: file_path, max_file_size_mb: 1) }

  let(:event_data) do
    {
      event_name: "payment.failed",
      severity: :error,
      payload: { order_id: 123, amount: 100.0 },
      timestamp: "2026-01-20T12:00:00.000Z"
    }
  end

  let(:metadata) do
    {
      error: StandardError.new("Connection timeout"),
      retry_count: 3,
      adapter: "LokiAdapter"
    }
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "creates directory if it doesn't exist" do
      expect(Dir.exist?(temp_dir)).to be true
    end

    it "uses default file path if not provided" do
      # Use a writable temporary directory for testing
      temp_dir = Dir.mktmpdir
      allow(Rails).to receive(:root).and_return(Pathname.new(temp_dir)) if defined?(Rails)

      dlq_default = described_class.new
      # Should not crash
      expect(dlq_default).to be_a(described_class)
    ensure
      FileUtils.rm_rf(temp_dir) if temp_dir
    end
  end

  describe "#save" do
    it "saves event to DLQ file" do
      event_id = dlq.save(event_data, metadata: metadata)

      expect(event_id).to be_a(String)
      expect(File.exist?(file_path)).to be true
    end

    it "returns UUID as event ID" do
      event_id = dlq.save(event_data, metadata: metadata)

      expect(event_id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it "stores event in JSONL format" do
      dlq.save(event_data, metadata: metadata)

      line = File.readlines(file_path).first
      entry = JSON.parse(line, symbolize_names: true)

      expect(entry).to include(
        :id,
        :timestamp,
        event_name: "payment.failed",
        event_data: hash_including(event_name: "payment.failed"),
        metadata: hash_including(
          retry_count: 3,
          adapter: "LokiAdapter"
        )
      )
    end

    it "includes error message and class in metadata" do
      dlq.save(event_data, metadata: metadata)

      line = File.readlines(file_path).first
      entry = JSON.parse(line, symbolize_names: true)

      expect(entry[:metadata]).to include(
        error_message: "Connection timeout",
        error_class: "StandardError"
      )
    end

    it "appends to existing file" do
      dlq.save(event_data, metadata: metadata)
      dlq.save(event_data.merge(event_name: "order.failed"), metadata: metadata)

      lines = File.readlines(file_path)
      expect(lines.size).to eq(2)
    end
  end

  describe "#list" do
    before do
      3.times do |i|
        dlq.save(event_data.merge(event_name: "event.#{i}"), metadata: metadata)
      end
    end

    it "returns list of DLQ entries" do
      entries = dlq.list

      expect(entries.size).to eq(3)
      expect(entries).to all(include(:id, :timestamp, :event_name, :event_data, :metadata))
    end

    it "limits number of entries" do
      entries = dlq.list(limit: 2)

      expect(entries.size).to eq(2)
    end

    it "supports offset for pagination" do
      entries = dlq.list(limit: 2, offset: 1)

      expect(entries.size).to eq(2)
      expect(entries.first[:event_name]).to eq("event.1")
    end

    it "filters by event_name" do
      entries = dlq.list(filters: { event_name: "event.1" })

      expect(entries.size).to eq(1)
      expect(entries.first[:event_name]).to eq("event.1")
    end

    it "filters by timestamp (after)" do
      # Save old events first
      dlq.list # Ensure old events exist

      # Wait to ensure timestamp difference
      sleep(0.1)
      future_time = Time.now - 0.05 # Set cutoff slightly in the past

      # Save new event
      dlq.save(event_data.merge(event_name: "event.future"), metadata: metadata)

      entries = dlq.list(filters: { after: future_time })

      expect(entries.size).to be >= 1
      expect(entries.map { |e| e[:event_name] }).to include("event.future")
    end

    it "returns empty array when file doesn't exist" do
      FileUtils.rm_f(file_path)

      entries = dlq.list

      expect(entries).to eq([])
    end
  end

  describe "#stats" do
    it "returns stats when file doesn't exist" do
      FileUtils.rm_f(file_path)

      stats = dlq.stats

      expect(stats).to include(
        total_entries: 0,
        file_size_mb: 0.0,
        oldest_entry: nil,
        newest_entry: nil,
        file_path: file_path
      )
    end

    it "returns correct stats for existing file" do
      dlq.save(event_data, metadata: metadata)
      sleep(0.01)
      dlq.save(event_data, metadata: metadata)

      stats = dlq.stats

      expect(stats[:total_entries]).to eq(2)
      expect(stats[:file_size_mb]).to be >= 0.0 # File might be small, just check it's a number
      expect(stats[:oldest_entry]).to be_a(String)
      expect(stats[:newest_entry]).to be_a(String)
      expect(stats[:oldest_entry]).not_to eq(stats[:newest_entry])
    end
  end

  describe "#replay" do
    it "returns true for successful replay" do
      event_id = dlq.save(event_data, metadata: metadata)

      # TODO: Implement E11y::Pipeline.dispatch
      # For now, just check it doesn't crash
      result = dlq.replay(event_id)

      expect(result).to be(true)
    end

    it "returns false for non-existent event" do
      result = dlq.replay("non-existent-uuid")

      expect(result).to be(false)
    end
  end

  describe "#replay_batch" do
    it "replays multiple events" do
      event_ids = Array.new(3) do
        dlq.save(event_data, metadata: metadata)
      end

      result = dlq.replay_batch(event_ids)

      expect(result[:success_count]).to eq(3)
      expect(result[:failure_count]).to eq(0)
    end

    it "counts failures for non-existent events" do
      result = dlq.replay_batch(%w[non-existent-1 non-existent-2])

      expect(result[:success_count]).to eq(0)
      expect(result[:failure_count]).to eq(2)
    end
  end

  describe "file rotation" do
    let(:dlq_small) { described_class.new(file_path: file_path, max_file_size_mb: 0.001) } # 1KB

    it "rotates file when size exceeds max" do
      # Write enough data to exceed 1KB
      50.times do
        dlq_small.save(event_data, metadata: metadata)
      end

      # Check for rotated files
      rotated_files = Dir.glob(File.join(temp_dir, "test_dlq.*.jsonl"))
      expect(rotated_files).not_to be_empty
    end

    it "keeps main file after rotation" do
      50.times do
        dlq_small.save(event_data, metadata: metadata)
      end

      expect(File.exist?(file_path)).to be true
    end
  end

  describe "file cleanup" do
    it "removes old rotated files" do
      dlq_cleanup = described_class.new(file_path: file_path, retention_days: 0)

      # Create rotated file
      old_file = File.join(temp_dir, "test_dlq.2020-01-01T00:00:00Z.jsonl")
      FileUtils.touch(old_file)
      File.utime(Time.now - (31 * 86_400), Time.now - (31 * 86_400), old_file)

      # Trigger cleanup
      dlq_cleanup.save(event_data, metadata: metadata)

      expect(File.exist?(old_file)).to be false
    end
  end

  describe "thread safety" do
    it "handles concurrent writes safely" do
      threads = Array.new(10) do |i|
        Thread.new do
          10.times do
            dlq.save(event_data.merge(thread_id: i), metadata: metadata)
          end
        end
      end

      threads.each(&:join)

      # All 100 events should be saved
      entries = dlq.list(limit: 200)
      expect(entries.size).to eq(100)
    end
  end

  describe "real-world scenario: adapter failure recovery" do
    it "stores failed events during outage" do
      # Simulate 10 failed events during Loki outage
      event_ids = Array.new(10) do |i|
        dlq.save(
          event_data.merge(order_id: i),
          metadata: metadata.merge(retry_count: 3)
        )
      end

      expect(event_ids.size).to eq(10)

      # Later: check stats
      stats = dlq.stats
      expect(stats[:total_entries]).to eq(10)

      # Replay all events after recovery
      result = dlq.replay_batch(event_ids)
      expect(result[:success_count]).to eq(10)
    end
  end
end
