# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"
require "json"
require "time"
require "zlib"

# File adapter integration tests require extensive filesystem mocking,
# compression testing, and rotation scenarios with multiple fixtures.
RSpec.describe E11y::Adapters::File do
  let(:temp_dir) { Dir.mktmpdir("e11y_file_adapter_test") }
  let(:login_event) do
    {
      event_name: "user.login",
      severity: :info,
      timestamp: Time.now.iso8601,
      user_id: 123
    }
  end
  let(:logout_event) do
    {
      event_name: "user.logout",
      severity: :info,
      timestamp: Time.now.iso8601,
      user_id: 123
    }
  end
  let(:log_path) { File.join(temp_dir, "test.log") }

  after do
    FileUtils.rm_rf(temp_dir) if File.directory?(temp_dir)
  end

  describe "ADR-004 compliance" do
    describe "Section 3.1: Base Adapter Contract" do
      let(:adapter) { described_class.new(path: log_path) }

      after { adapter.close }

      it "inherits from E11y::Adapters::Base" do
        expect(adapter).to be_a(E11y::Adapters::Base)
      end

      it "implements #write" do
        expect(adapter).to respond_to(:write)
        expect(adapter.write(login_event)).to be(true).or(be(false))
      end

      it "implements #write_batch" do
        expect(adapter).to respond_to(:write_batch)
        expect(adapter.write_batch([login_event, logout_event])).to be(true).or(be(false))
      end

      it "implements #healthy?" do
        expect(adapter).to respond_to(:healthy?)
        expect(adapter.healthy?).to be(true).or(be(false))
      end

      it "implements #close" do
        expect(adapter).to respond_to(:close)
        expect { adapter.close }.not_to raise_error
      end

      it "implements #capabilities" do
        expect(adapter).to respond_to(:capabilities)
        caps = adapter.capabilities
        expect(caps).to be_a(Hash)
        expect(caps).to include(:batching, :compression, :async, :streaming)
      end
    end

    describe "Section 4.2: File Adapter Specification" do
      it "writes events in JSONL format" do
        adapter = described_class.new(path: log_path)
        adapter.write(login_event)
        adapter.close

        content = File.read(log_path)
        parsed = JSON.parse(content, symbolize_names: true)

        expect(parsed[:event_name]).to eq("user.login")
        expect(parsed[:severity]).to eq("info")
      end

      it "supports batch writes" do
        adapter = described_class.new(path: log_path)
        adapter.write_batch([login_event, logout_event])
        adapter.close

        lines = File.readlines(log_path)
        expect(lines.size).to eq(2)

        parsed1 = JSON.parse(lines[0], symbolize_names: true)
        parsed2 = JSON.parse(lines[1], symbolize_names: true)

        expect(parsed1[:event_name]).to eq("user.login")
        expect(parsed2[:event_name]).to eq("user.logout")
      end

      it "flushes after each write" do
        adapter = described_class.new(path: log_path)
        adapter.write(login_event)

        # Should be readable immediately without closing
        content = File.read(log_path)
        expect(content).not_to be_empty

        adapter.close
      end
    end
  end

  describe "Configuration" do
    it "requires :path parameter" do
      expect { described_class.new({}) }.to raise_error(ArgumentError, /requires :path/)
    end

    it "accepts valid rotation strategies" do
      expect { described_class.new(path: log_path, rotation: :daily) }.not_to raise_error
      expect { described_class.new(path: log_path, rotation: :size) }.not_to raise_error
      expect { described_class.new(path: log_path, rotation: :none) }.not_to raise_error
    end

    it "rejects invalid rotation strategies" do
      expect do
        described_class.new(path: log_path, rotation: :invalid)
      end.to raise_error(ArgumentError, /Invalid rotation/)
    end

    it "validates max_size is positive" do
      expect do
        described_class.new(path: log_path, max_size: -100)
      end.to raise_error(ArgumentError, /max_size must be positive/)
    end

    it "uses default values" do
      adapter = described_class.new(path: log_path)

      expect(adapter.rotation).to eq(:daily)
      expect(adapter.max_size).to eq(100 * 1024 * 1024)
      expect(adapter.compress_on_rotate).to be true

      adapter.close
    end

    it "creates directory if it doesn't exist" do
      nested_path = File.join(temp_dir, "nested", "dir", "test.log")
      adapter = described_class.new(path: nested_path)

      expect(File.directory?(File.dirname(nested_path))).to be true

      adapter.close
    end
  end

  describe "Writing events" do
    let(:adapter) { described_class.new(path: log_path) }

    after { adapter.close }

    it "writes single event successfully" do
      result = adapter.write(login_event)

      expect(result).to be true
      expect(File.exist?(log_path)).to be true
    end

    it "writes multiple events" do
      adapter.write(login_event)
      adapter.write(logout_event)

      lines = File.readlines(log_path)
      expect(lines.size).to eq(2)
    end

    it "writes batch of events" do
      result = adapter.write_batch([login_event, logout_event])

      expect(result).to be true

      lines = File.readlines(log_path)
      expect(lines.size).to eq(2)
    end

    it "handles empty batch" do
      result = adapter.write_batch([])

      expect(result).to be true
    end

    it "returns false on write error" do
      adapter.close # Close file to cause error

      result = adapter.write(login_event)

      expect(result).to be false
    end
  end

  describe "Rotation" do
    context "with :daily rotation" do
      let(:adapter) { described_class.new(path: log_path, rotation: :daily, compress: false) }

      after { adapter.close }

      it "rotates file when date changes" do
        adapter.write(login_event)

        # Simulate date change
        allow(Date).to receive(:today).and_return(Date.today + 1)

        adapter.write(logout_event)

        # Should have rotated file
        rotated_files = Dir.glob("#{log_path}.*")
        expect(rotated_files.size).to eq(1)

        # New file should have only second event
        lines = File.readlines(log_path)
        expect(lines.size).to eq(1)

        parsed = JSON.parse(lines[0], symbolize_names: true)
        expect(parsed[:event_name]).to eq("user.logout")
      end

      it "does not rotate on same day" do
        adapter.write(login_event)
        adapter.write(logout_event)

        rotated_files = Dir.glob("#{log_path}.*")
        expect(rotated_files.size).to eq(0)

        lines = File.readlines(log_path)
        expect(lines.size).to eq(2)
      end
    end

    context "with :size rotation" do
      let(:small_size) { 100 } # 100 bytes
      let(:adapter) { described_class.new(path: log_path, rotation: :size, max_size: small_size, compress: false) }

      after { adapter.close }

      it "rotates file when size exceeded" do
        # Write enough events to exceed size
        large_event = { event_name: "large.event", data: "x" * 200 }

        adapter.write(large_event)
        adapter.write(large_event)

        rotated_files = Dir.glob("#{log_path}.*")
        expect(rotated_files.size).to be >= 1
      end

      it "does not rotate if size not exceeded" do
        adapter.write(login_event)

        rotated_files = Dir.glob("#{log_path}.*")
        expect(rotated_files.size).to eq(0)
      end
    end

    context "with :none rotation" do
      let(:adapter) { described_class.new(path: log_path, rotation: :none) }

      after { adapter.close }

      it "never rotates" do
        adapter.write(login_event)

        # Simulate date change
        allow(Date).to receive(:today).and_return(Date.today + 1)

        adapter.write(logout_event)

        rotated_files = Dir.glob("#{log_path}.*")
        expect(rotated_files.size).to eq(0)

        lines = File.readlines(log_path)
        expect(lines.size).to eq(2)
      end
    end
  end

  describe "Compression" do
    context "with compression enabled" do
      let(:adapter) { described_class.new(path: log_path, rotation: :daily, compress: true) }

      after { adapter.close }

      it "compresses rotated files" do
        adapter.write(login_event)

        # Simulate date change to trigger rotation
        allow(Date).to receive(:today).and_return(Date.today + 1)

        adapter.write(logout_event)

        # Should have .gz file
        gz_files = Dir.glob("#{log_path}.*.gz")
        expect(gz_files.size).to eq(1)

        # Original rotated file should be deleted
        rotated_files = Dir.glob("#{log_path}.*").reject { |f| f.end_with?(".gz") }
        expect(rotated_files).to be_empty
      end

      it "compressed file contains original data" do
        adapter.write(login_event)

        allow(Date).to receive(:today).and_return(Date.today + 1)

        adapter.write(logout_event)

        gz_file = Dir.glob("#{log_path}.*.gz").first
        expect(gz_file).not_to be_nil

        # Decompress and verify content
        Zlib::GzipReader.open(gz_file) do |gz|
          content = gz.read
          parsed = JSON.parse(content, symbolize_names: true)
          expect(parsed[:event_name]).to eq("user.login")
        end
      end
    end

    context "with compression disabled" do
      let(:adapter) { described_class.new(path: log_path, rotation: :daily, compress: false) }

      after { adapter.close }

      it "does not compress rotated files" do
        adapter.write(login_event)

        allow(Date).to receive(:today).and_return(Date.today + 1)

        adapter.write(logout_event)

        # Should have uncompressed rotated file
        rotated_files = Dir.glob("#{log_path}.*").reject { |f| f.end_with?(".gz") }
        expect(rotated_files.size).to eq(1)

        # No .gz files
        gz_files = Dir.glob("#{log_path}.*.gz")
        expect(gz_files).to be_empty
      end
    end
  end

  describe "#healthy?" do
    it "returns true when file is open" do
      adapter = described_class.new(path: log_path)

      expect(adapter.healthy?).to be true

      adapter.close
    end

    it "returns false when file is closed" do
      adapter = described_class.new(path: log_path)
      adapter.close

      expect(adapter.healthy?).to be false
    end
  end

  describe "#close" do
    it "closes file handle" do
      adapter = described_class.new(path: log_path)
      adapter.write(login_event)

      adapter.close

      expect(adapter.healthy?).to be false
    end

    it "can be called multiple times safely" do
      adapter = described_class.new(path: log_path)

      expect { adapter.close }.not_to raise_error
      expect { adapter.close }.not_to raise_error
    end
  end

  describe "#capabilities" do
    it "reports correct capabilities" do
      adapter = described_class.new(path: log_path, compress: true)
      caps = adapter.capabilities

      expect(caps[:batching]).to be true
      expect(caps[:compression]).to be true
      expect(caps[:streaming]).to be true
      expect(caps[:async]).to be false

      adapter.close
    end

    it "reflects compression setting" do
      adapter_compressed = described_class.new(path: log_path, compress: true)
      adapter_uncompressed = described_class.new(path: "#{log_path}.2", compress: false)

      expect(adapter_compressed.capabilities[:compression]).to be true
      expect(adapter_uncompressed.capabilities[:compression]).to be false

      adapter_compressed.close
      adapter_uncompressed.close
    end
  end

  describe "Thread safety" do
    let(:adapter) { described_class.new(path: log_path) }

    after { adapter.close }

    it "handles concurrent writes safely" do
      threads = 10.times.map do |i|
        Thread.new do
          adapter.write(event_name: "concurrent.event.#{i}", severity: :info)
        end
      end

      threads.each(&:join)

      lines = File.readlines(log_path)
      expect(lines.size).to eq(10)

      # All lines should be valid JSON
      lines.each do |line|
        expect { JSON.parse(line) }.not_to raise_error
      end
    end
  end
end
