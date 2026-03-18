# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "zlib"
require "e11y/adapters/dev_log/file_store"

RSpec.describe E11y::Adapters::DevLog::FileStore do
  let(:dir)  { Dir.mktmpdir("e11y_file_store") }
  let(:path) { File.join(dir, "e11y_dev.jsonl") }

  after { FileUtils.remove_entry(dir) }

  subject(:store) do
    described_class.new(path: path, max_size: 1024, max_lines: 10, keep_rotated: 3)
  end

  describe "#append" do
    it "creates the file and writes a JSON line" do
      store.append('{"id":"1"}')
      expect(File.read(path)).to eq("{\"id\":\"1\"}\n")
    end

    it "appends subsequent lines" do
      store.append('{"id":"1"}')
      store.append('{"id":"2"}')
      lines = File.readlines(path)
      expect(lines.size).to eq(2)
    end

    it "is thread-safe under concurrent writes" do
      threads = 10.times.map { |i| Thread.new { store.append("{\"id\":#{i}}") } }
      threads.each(&:join)
      lines = File.readlines(path)
      expect(lines.size).to eq(10)
      lines.each { |l| expect { JSON.parse(l) }.not_to raise_error }
    end
  end

  describe "rotation by max_lines" do
    it "rotates when line count exceeds max_lines" do
      11.times { |i| store.append("{\"id\":#{i}}") }
      expect(File.exist?("#{path}.1.gz")).to be true
      expect(File.readlines(path).size).to be < 11
    end

    it "compresses rotated file with gzip" do
      11.times { |i| store.append("{\"id\":#{i}}") }
      gz_path = "#{path}.1.gz"
      expect { Zlib::GzipReader.open(gz_path) { |f| f.read } }.not_to raise_error
    end

    it "shifts existing rotated files (1.gz -> 2.gz)" do
      # First rotation
      11.times { |i| store.append("{\"id\":#{i}}") }
      # Second rotation
      11.times { |i| store.append("{\"id\":#{i + 100}}") }
      expect(File.exist?("#{path}.2.gz")).to be true
    end

    it "deletes rotated files beyond keep_rotated" do
      4.times do
        11.times { |i| store.append("{\"id\":#{i}}") }
      end
      expect(File.exist?("#{path}.4.gz")).to be false
    end
  end

  describe "rotation by max_size" do
    it "rotates when file size exceeds max_size" do
      long_line = "{\"id\":\"#{"x" * 512}\"}"
      3.times { store.append(long_line) }  # >1024 bytes
      expect(File.exist?("#{path}.1.gz")).to be true
    end
  end

  describe "#clear!" do
    it "removes the log file" do
      store.append('{"id":"1"}')
      store.clear!
      expect(File.exist?(path)).to be false
    end
  end

  describe "#file_size" do
    it "returns 0 when file does not exist" do
      expect(store.file_size).to eq(0)
    end

    it "returns byte size of existing file" do
      store.append('{"id":"1"}')
      expect(store.file_size).to be > 0
    end
  end

  describe "#line_count" do
    it "counts lines in file" do
      3.times { |i| store.append("{\"id\":#{i}}") }
      expect(store.line_count).to eq(3)
    end
  end
end
