# E11y Devtools Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the `e11y-devtools` ecosystem: DevLog Adapter (JSONL write+read), TUI (ratatui_ruby), Browser Overlay (Rails Engine), and MCP Server (gem 'mcp') — giving Rails developers instant, low-noise visibility into their app.

**Architecture:** Hub-and-Spoke — one JSONL file (`log/e11y_dev.jsonl`) is the single source of truth; three independent thin viewers (TUI, Overlay, MCP) read from it via a shared `Query` class. Core gem `e11y` holds only the write+read adapter; all viewers live in `gem 'e11y-devtools'` (same monorepo, separate gemspec).

**Tech Stack:** Ruby 3.2+, Rails 7–8, ratatui_ruby ~> 1.4 (TUI), gem 'mcp' official SDK (MCP), Zlib stdlib (gzip rotation), oj (optional fast JSON), vanilla JS + Shadow DOM (Overlay).

**Design doc:** `docs/plans/2026-03-18-e11y-devtools-design.md`

---

## Phase 1: DevLog Adapter (`gem 'e11y'`)

### Task 1: FileStore — JSONL write, locking, rotation

**Files:**
- Create: `lib/e11y/adapters/dev_log/file_store.rb`
- Create: `spec/e11y/adapters/dev_log/file_store_spec.rb`

**Context:** `FileStore` handles all I/O. Current file is always plain text (fast append). Rotation: shift numbered `.gz` files, gzip-compress current file, open new empty file. Thread-safe via `Mutex` + `File::LOCK_EX`.

**Step 1: Write the failing tests**

```ruby
# spec/e11y/adapters/dev_log/file_store_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "zlib"

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

    it "shifts existing rotated files (1.gz → 2.gz)" do
      # First rotation
      11.times { |i| store.append("{\"id\":#{i}}") }
      # Second rotation
      11.times { |i| store.append("{\"id\":#{i + 100}}") }
      expect(File.exist?("#{path}.2.gz")).to be true
    end

    it "deletes rotated files beyond keep_rotated" do
      (keep_rotated + 1).times do
        11.times { |i| store.append("{\"id\":#{i}}") }
      end
      expect(File.exist?("#{path}.4.gz")).to be false
    end

    def keep_rotated = 3
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
```

**Step 2: Run to verify it fails**

```bash
bundle exec rspec spec/e11y/adapters/dev_log/file_store_spec.rb
```

Expected: `LoadError` or `NameError` — `E11y::Adapters::DevLog::FileStore` does not exist yet.

**Step 3: Implement FileStore**

```ruby
# lib/e11y/adapters/dev_log/file_store.rb
# frozen_string_literal: true

require "zlib"
require "fileutils"

module E11y
  module Adapters
    class DevLog
      # Handles JSONL file I/O with thread-safe append, numbered gzip rotation.
      #
      # Current file is always plain text for fast appends.
      # Rotated files are gzip-compressed to save disk space.
      # Rotation is triggered synchronously on the write that crosses the threshold.
      class FileStore
        DEFAULT_MAX_SIZE      = 50 * 1024 * 1024  # 50 MB
        DEFAULT_MAX_LINES     = 10_000
        DEFAULT_KEEP_ROTATED  = 5

        attr_reader :path

        def initialize(path:,
                       max_size: DEFAULT_MAX_SIZE,
                       max_lines: DEFAULT_MAX_LINES,
                       keep_rotated: DEFAULT_KEEP_ROTATED)
          @path         = path.to_s
          @max_size     = max_size
          @max_lines    = max_lines
          @keep_rotated = keep_rotated
          @mutex        = Mutex.new
          @line_count   = nil  # lazy; reset on rotation
        end

        # Append a JSON line to the log file. Thread-safe.
        #
        # @param json_line [String] A single JSON object (no newline)
        def append(json_line)
          @mutex.synchronize do
            ensure_dir!
            File.open(@path, "a") do |f|
              f.flock(File::LOCK_EX)
              f.write("#{json_line}\n")
              f.flock(File::LOCK_UN)
            end
            @line_count = (@line_count || 0) + 1
            rotate_if_needed!
          end
        end

        # Remove log file and reset internal state.
        def clear!
          @mutex.synchronize do
            FileUtils.rm_f(@path)
            @line_count = nil
          end
        end

        # Current file size in bytes (0 if file does not exist).
        def file_size
          File.size(@path)
        rescue Errno::ENOENT
          0
        end

        # Number of lines in current file (0 if does not exist).
        def line_count
          @mutex.synchronize { count_lines }
        end

        private

        def ensure_dir!
          FileUtils.mkdir_p(File.dirname(@path))
        end

        def rotate_if_needed!
          return unless should_rotate?

          rotate!
          @line_count = nil
        end

        def should_rotate?
          file_size > @max_size ||
            (@line_count && @line_count > @max_lines)
        end

        # Shift existing .N.gz files up, gzip current file into .1.gz, open fresh file.
        def rotate!
          # Shift: 4.gz→5.gz, 3.gz→4.gz, ..., 1.gz→2.gz (drop beyond keep_rotated)
          @keep_rotated.downto(1) do |n|
            src = rotated_path(n)
            dst = rotated_path(n + 1)
            next unless File.exist?(src)

            if n + 1 > @keep_rotated
              FileUtils.rm_f(src)
            else
              File.rename(src, dst)
            end
          end

          # Gzip current file → .1.gz
          if File.exist?(@path)
            gz_path = rotated_path(1)
            Zlib::GzipWriter.open(gz_path) do |gz|
              gz.write(File.read(@path))
            end
            FileUtils.rm_f(@path)
          end
        end

        def rotated_path(n)
          "#{@path}.#{n}.gz"
        end

        def count_lines
          return 0 unless File.exist?(@path)

          File.foreach(@path).count
        end
      end
    end
  end
end
```

**Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/e11y/adapters/dev_log/file_store_spec.rb
```

Expected: all green (≥ 12 examples).

**Step 5: Commit**

```bash
git add lib/e11y/adapters/dev_log/file_store.rb \
        spec/e11y/adapters/dev_log/file_store_spec.rb
git commit -m "feat: add DevLog::FileStore (JSONL append, gzip rotation)"
```

---

### Task 2: Query — read API, caching, interactions grouping

**Files:**
- Create: `lib/e11y/adapters/dev_log/query.rb`
- Create: `spec/e11y/adapters/dev_log/query_spec.rb`

**Context:** `Query` reads the JSONL file with an in-memory cache (invalidated by `File.mtime`). Uses tail-read for `stored_events` (fast for large files). Implements `interactions` — time-window grouping of traces. Used by TUI, Overlay, and MCP.

**Step 1: Write the failing tests**

```ruby
# spec/e11y/adapters/dev_log/query_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"
require "time"

RSpec.describe E11y::Adapters::DevLog::Query do
  let(:dir)  { Dir.mktmpdir("e11y_query") }
  let(:path) { File.join(dir, "e11y_dev.jsonl") }

  after { FileUtils.remove_entry(dir) }

  def write_events(*events)
    File.open(path, "a") { |f| events.each { |e| f.puts(JSON.generate(e)) } }
  end

  def build_event(overrides = {})
    {
      "id"         => SecureRandom.uuid,
      "timestamp"  => Time.now.iso8601(3),
      "event_name" => "test.event",
      "severity"   => "info",
      "trace_id"   => SecureRandom.hex(8),
      "span_id"    => SecureRandom.hex(4),
      "payload"    => { "key" => "value" },
      "metadata"   => { "source" => "web", "path" => "/test", "duration_ms" => 10 }
    }.merge(overrides.transform_keys(&:to_s))
  end

  subject(:query) { described_class.new(path) }

  describe "#stored_events" do
    it "returns empty array when file does not exist" do
      expect(query.stored_events).to eq([])
    end

    it "returns events newest-first" do
      t = Time.now
      write_events(
        build_event(id: "old", timestamp: (t - 10).iso8601(3)),
        build_event(id: "new", timestamp: t.iso8601(3))
      )
      events = query.stored_events
      expect(events.first["id"]).to eq("new")
    end

    it "respects limit" do
      5.times { |i| write_events(build_event(id: i.to_s)) }
      expect(query.stored_events(limit: 3).size).to eq(3)
    end

    it "filters by severity" do
      write_events(
        build_event(severity: "info"),
        build_event(severity: "error")
      )
      events = query.stored_events(severity: "error")
      expect(events.size).to eq(1)
      expect(events.first["severity"]).to eq("error")
    end

    it "filters by source" do
      write_events(
        build_event(metadata: { "source" => "web" }),
        build_event(metadata: { "source" => "job" })
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
      event = build_event(id: "target-123")
      write_events(build_event, event, build_event)
      found = query.find_event("target-123")
      expect(found["id"]).to eq("target-123")
    end
  end

  describe "#search" do
    it "returns empty array when no match" do
      write_events(build_event(event_name: "order.created"))
      expect(query.search("payment")).to eq([])
    end

    it "matches by event_name substring" do
      write_events(
        build_event(event_name: "payment.failed"),
        build_event(event_name: "order.created")
      )
      results = query.search("payment")
      expect(results.size).to eq(1)
    end

    it "matches inside payload JSON" do
      write_events(build_event(payload: { "order_id" => "ORD-7821" }))
      expect(query.search("ORD-7821").size).to eq(1)
    end
  end

  describe "#events_by_trace" do
    it "returns all events for a trace in chronological order" do
      trace_id = "abc123"
      write_events(
        build_event(trace_id: trace_id, event_name: "a"),
        build_event(trace_id: "other",  event_name: "b"),
        build_event(trace_id: trace_id, event_name: "c")
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
        build_event(severity: "info"),
        build_event(severity: "info"),
        build_event(severity: "error")
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

  describe "#interactions" do
    it "returns empty array when no events" do
      expect(query.interactions).to eq([])
    end

    it "groups traces starting within window_ms into one interaction" do
      t = Time.now
      write_events(
        build_event(trace_id: "t1", metadata: { "source" => "web", "started_at" => t.iso8601(3) }),
        build_event(trace_id: "t2", metadata: { "source" => "web", "started_at" => (t + 0.3).iso8601(3) }),
        build_event(trace_id: "t3", metadata: { "source" => "web", "started_at" => (t + 1.2).iso8601(3) })
      )
      groups = query.interactions(window_ms: 500)
      expect(groups.size).to eq(2)
      expect(groups.first.trace_ids.sort).to eq(%w[t1 t2].sort)
      expect(groups.last.trace_ids).to eq(%w[t3])
    end

    it "marks interaction has_error? when any trace event has error severity" do
      t = Time.now
      write_events(
        build_event(trace_id: "t1", severity: "error",
                    metadata: { "source" => "web", "started_at" => t.iso8601(3) }),
        build_event(trace_id: "t1", severity: "info",
                    metadata: { "source" => "web", "started_at" => t.iso8601(3) })
      )
      groups = query.interactions(window_ms: 500)
      expect(groups.first.has_error?).to be true
    end

    it "filters by source" do
      t = Time.now
      write_events(
        build_event(trace_id: "w1", metadata: { "source" => "web", "started_at" => t.iso8601(3) }),
        build_event(trace_id: "j1", metadata: { "source" => "job", "started_at" => t.iso8601(3) })
      )
      groups = query.interactions(window_ms: 500, source: "web")
      expect(groups.first.trace_ids).to eq(%w[w1])
    end
  end

  describe "caching" do
    it "returns same result on second call without re-reading file" do
      write_events(build_event)
      query.stored_events  # prime cache
      # Poison the file — cache should serve old result
      File.write(path, "INVALID JSON\n")
      events = query.stored_events
      expect(events.size).to eq(1)
    end

    it "invalidates cache when file mtime changes" do
      write_events(build_event)
      query.stored_events  # prime cache
      sleep 0.01
      # Touch file with new mtime
      write_events(build_event)
      FileUtils.touch(path)
      events = query.stored_events
      expect(events.size).to eq(2)
    end
  end
end
```

**Step 2: Run to verify it fails**

```bash
bundle exec rspec spec/e11y/adapters/dev_log/query_spec.rb
```

Expected: `LoadError` — `E11y::Adapters::DevLog::Query` does not exist.

**Step 3: Implement Query**

```ruby
# lib/e11y/adapters/dev_log/query.rb
# frozen_string_literal: true

require "json"
require "time"

module E11y
  module Adapters
    class DevLog
      # Read-only query interface for the JSONL dev log.
      #
      # Used by TUI, Browser Overlay, and MCP Server — all three viewers
      # share this single class.
      #
      # Performance strategy:
      #   - stored_events: tail-read from end of file (O(limit), not O(total))
      #   - All queries: in-memory cache invalidated by File.mtime
      #   - JSON parser: oj if available, stdlib JSON as fallback
      class Query
        # Value object returned by #interactions
        Interaction = Struct.new(:started_at, :trace_ids, :has_error?, :source,
                                 keyword_init: true) do
          def traces_count = trace_ids.size
        end

        # Choose fastest available JSON parser
        JSON_LOAD = if defined?(Oj)
                      ->(str) { Oj.load(str) }
                    else
                      ->(str) { JSON.parse(str) }
                    end

        def initialize(path)
          @path       = path.to_s
          @cache      = nil
          @cache_mtime = nil
        end

        # Return last +limit+ events, newest-first.
        #
        # @param limit    [Integer]      Max events to return
        # @param severity [String, nil]  Filter by severity
        # @param source   [String, nil]  Filter by metadata.source ("web", "job")
        def stored_events(limit: 1000, severity: nil, source: nil)
          events = all_events
          events = events.select { |e| e["severity"] == severity } if severity
          events = events.select { |e| e.dig("metadata", "source") == source } if source
          events.last(limit).reverse
        end

        # Find event by id (returns nil if not found).
        def find_event(id)
          all_events.find { |e| e["id"] == id }
        end

        # Full-text search in event_name and payload JSON.
        def search(query_str, limit: 500)
          q = query_str.downcase
          all_events.select do |e|
            e["event_name"].to_s.downcase.include?(q) ||
              JSON.generate(e["payload"]).downcase.include?(q)
          end.last(limit).reverse
        end

        # All events for a given trace_id in chronological order.
        def events_by_trace(trace_id)
          all_events.select { |e| e["trace_id"] == trace_id }
        end

        # Aggregate stats about the log.
        def stats
          events = all_events
          {
            total_events:   events.size,
            file_size:      file_size,
            by_severity:    events.group_by { |e| e["severity"] }.transform_values(&:count),
            by_event_name:  events.group_by { |e| e["event_name"] }.transform_values(&:count),
            oldest_event:   events.first&.dig("timestamp"),
            newest_event:   events.last&.dig("timestamp")
          }
        end

        # True if log file was modified after +timestamp+.
        def updated_since?(timestamp)
          return false unless File.exist?(@path)

          File.mtime(@path) > timestamp
        end

        # Remove the log file and invalidate cache.
        def clear!
          FileUtils.rm_f(@path)
          invalidate_cache!
        end

        # Group traces into time-window interaction bands.
        #
        # Traces started within +window_ms+ of each other form one interaction.
        # Returns Array<Interaction> sorted newest-first.
        #
        # @param window_ms [Integer]     Grouping window in milliseconds (default 500)
        # @param limit     [Integer]     Max interactions to return
        # @param source    [String, nil] Filter by metadata.source
        def interactions(window_ms: 500, limit: 50, source: nil)
          events = all_events
          events = events.select { |e| e.dig("metadata", "source") == source } if source

          # Build per-trace summaries: { trace_id → { started_at, has_error } }
          trace_map = {}
          events.each do |e|
            tid = e["trace_id"]
            next unless tid

            started = parse_started_at(e)
            next unless started

            entry = trace_map[tid] ||= { started_at: started, has_error: false }
            entry[:has_error] = true if %w[error fatal].include?(e["severity"])
            entry[:started_at] = started if started < entry[:started_at]
            entry[:source] = e.dig("metadata", "source")
          end

          return [] if trace_map.empty?

          # Sort traces by start time, group into window bands
          sorted = trace_map.sort_by { |_, v| v[:started_at] }
          groups = []
          current = nil

          sorted.each do |trace_id, meta|
            if current.nil? ||
               (meta[:started_at] - current[:last_started_at]) * 1000 > window_ms
              current = {
                started_at:      meta[:started_at],
                last_started_at: meta[:started_at],
                trace_ids:       [],
                has_error:       false,
                source:          meta[:source]
              }
              groups << current
            end
            current[:trace_ids] << trace_id
            current[:has_error] ||= meta[:has_error]
            current[:last_started_at] = meta[:started_at]
          end

          groups
            .last(limit)
            .reverse
            .map do |g|
              Interaction.new(
                started_at: g[:started_at],
                trace_ids:  g[:trace_ids],
                has_error?: g[:has_error],
                source:     g[:source]
              )
            end
        end

        private

        def all_events
          return @cache if cache_valid?

          @cache = load_events
          @cache_mtime = current_mtime
          @cache
        end

        def cache_valid?
          return false unless @cache && @cache_mtime
          return false unless File.exist?(@path)

          current_mtime == @cache_mtime
        end

        def current_mtime
          File.mtime(@path)
        rescue Errno::ENOENT
          nil
        end

        def invalidate_cache!
          @cache = nil
          @cache_mtime = nil
        end

        def load_events
          return [] unless File.exist?(@path)

          events = []
          File.foreach(@path) do |line|
            line = line.chomp
            next if line.empty?

            events << JSON_LOAD.call(line)
          rescue JSON::ParserError, StandardError
            next  # skip malformed lines
          end
          events
        end

        def file_size
          File.size(@path)
        rescue Errno::ENOENT
          0
        end

        def parse_started_at(event)
          ts = event.dig("metadata", "started_at") || event["timestamp"]
          Time.parse(ts)
        rescue ArgumentError, TypeError
          nil
        end
      end
    end
  end
end
```

**Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/e11y/adapters/dev_log/query_spec.rb
```

Expected: all green (≥ 25 examples).

**Step 5: Commit**

```bash
git add lib/e11y/adapters/dev_log/query.rb \
        spec/e11y/adapters/dev_log/query_spec.rb
git commit -m "feat: add DevLog::Query (read API, caching, interactions grouping)"
```

---

### Task 3: DevLog Adapter façade

**Files:**
- Create: `lib/e11y/adapters/dev_log.rb`
- Create: `spec/e11y/adapters/dev_log_spec.rb`

**Context:** `DevLog` inherits `Adapters::Base`, implements `write(event_data)`, composes `FileStore` (write) and `Query` (read). Generates `id` and `metadata.source` if not present.

**Step 1: Write the failing tests**

```ruby
# spec/e11y/adapters/dev_log_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe E11y::Adapters::DevLog do
  let(:dir)     { Dir.mktmpdir("e11y_devlog") }
  let(:path)    { File.join(dir, "e11y_dev.jsonl") }

  after { FileUtils.remove_entry(dir) }

  subject(:adapter) { described_class.new(path: path) }

  describe "#write" do
    let(:event_data) do
      {
        event_name: "order.created",
        severity:   "info",
        trace_id:   "abc123",
        payload:    { order_id: 1 },
        metadata:   {}
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

    it "sets metadata.source to 'web' from Thread.current if present" do
      Thread.current[:e11y_source] = "job"
      adapter.write(event_data)
      line = JSON.parse(File.readlines(path).last)
      expect(line.dig("metadata", "source")).to eq("job")
    ensure
      Thread.current[:e11y_source] = nil
    end
  end

  describe "read API delegation" do
    before do
      adapter.write(event_name: "a", severity: "info", trace_id: "t1", payload: {}, metadata: {})
      adapter.write(event_name: "b", severity: "error", trace_id: "t2", payload: {}, metadata: {})
    end

    it "#stored_events delegates to Query" do
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
    it "declares dev_log capability" do
      caps = adapter.capabilities
      expect(caps[:dev_log]).to be true
    end
  end
end
```

**Step 2: Run to verify it fails**

```bash
bundle exec rspec spec/e11y/adapters/dev_log_spec.rb
```

Expected: `LoadError` — `E11y::Adapters::DevLog` does not exist.

**Step 3: Implement DevLog façade**

```ruby
# lib/e11y/adapters/dev_log.rb
# frozen_string_literal: true

require "json"
require "securerandom"
require_relative "base"
require_relative "dev_log/file_store"
require_relative "dev_log/query"

module E11y
  module Adapters
    # Development-only adapter that stores events in a local JSONL file
    # and exposes a rich read API for TUI, Browser Overlay, and MCP Server.
    #
    # Only use in development/test — auto-registered by Railtie.
    #
    # @example Manual setup
    #   adapter = E11y::Adapters::DevLog.new(
    #     path: Rails.root.join("log", "e11y_dev.jsonl"),
    #     max_size: 50.megabytes,
    #     keep_rotated: 5
    #   )
    class DevLog < Base
      # @param path         [String, Pathname]
      # @param max_size     [Integer]  Rotation threshold in bytes (default 50 MB)
      # @param max_lines    [Integer]  Rotation threshold in line count (default 10_000)
      # @param keep_rotated [Integer]  Number of .N.gz files to retain (default 5)
      # @param enable_watcher [Boolean] Enable file watcher for real-time updates
      def initialize(path: "log/e11y_dev.jsonl",
                     max_size: FileStore::DEFAULT_MAX_SIZE,
                     max_lines: FileStore::DEFAULT_MAX_LINES,
                     keep_rotated: FileStore::DEFAULT_KEEP_ROTATED,
                     enable_watcher: false)
        super({})
        @store = FileStore.new(path: path, max_size: max_size,
                               max_lines: max_lines, keep_rotated: keep_rotated)
        @query = Query.new(@store.path)
        # enable_watcher reserved for future rb-inotify/rb-kqueue integration
        @enable_watcher = enable_watcher
      end

      # Write a single event to the JSONL file.
      #
      # @param event_data [Hash] Event from the E11y pipeline
      # @return [Boolean]
      def write(event_data)
        @store.append(serialize(event_data))
        true
      rescue StandardError => e
        warn "[E11y::DevLog] write failed: #{e.message}"
        false
      end

      # --- Read API (delegated to Query) ---

      def stored_events(limit: 1000, severity: nil, source: nil)
        @query.stored_events(limit: limit, severity: severity, source: source)
      end

      def find_event(id)         = @query.find_event(id)
      def search(q, limit: 500)  = @query.search(q, limit: limit)
      def events_by_name(name, limit: 500)     = @query.stored_events(limit: limit).select { |e| e["event_name"] == name }
      def events_by_severity(sev, limit: 500)  = @query.stored_events(limit: limit, severity: sev)
      def events_by_trace(trace_id)            = @query.events_by_trace(trace_id)
      def interactions(window_ms: 500, limit: 50, source: nil)
        @query.interactions(window_ms: window_ms, limit: limit, source: source)
      end
      def stats                  = @query.stats
      def updated_since?(ts)     = @query.updated_since?(ts)
      def clear!                 = @query.clear!

      def capabilities
        super.merge(dev_log: true, readable: true)
      end

      private

      def serialize(event_data)
        data = event_data.is_a?(Hash) ? event_data.transform_keys(&:to_s) : {}
        data["id"]        ||= SecureRandom.uuid
        data["timestamp"] ||= Time.now.utc.iso8601(3)
        # Pick up source from Thread.current (set by Railtie Rack middleware)
        source = Thread.current[:e11y_source] || "web"
        meta = (data["metadata"] || {}).dup
        meta["source"] ||= source
        meta["started_at"] ||= data["timestamp"]
        data["metadata"] = meta
        JSON.generate(data)
      end
    end
  end
end
```

**Step 4: Run tests**

```bash
bundle exec rspec spec/e11y/adapters/dev_log_spec.rb
```

Expected: all green.

**Step 5: Add require to main lib file**

Open `lib/e11y.rb` and add inside the adapters require block:
```ruby
require_relative "e11y/adapters/dev_log"
```

**Step 6: Commit**

```bash
git add lib/e11y/adapters/dev_log.rb \
        lib/e11y/adapters/dev_log/file_store.rb \
        lib/e11y/adapters/dev_log/query.rb \
        lib/e11y.rb \
        spec/e11y/adapters/dev_log_spec.rb
git commit -m "feat: add DevLog adapter façade with read/write API"
```

---

### Task 4: Railtie auto-registration + source middleware

**Files:**
- Modify: `lib/e11y/railtie.rb`
- Create: `lib/e11y/middleware/dev_log_source.rb`
- Create: `spec/e11y/adapters/dev_log_railtie_spec.rb`

**Context:** Railtie auto-registers DevLog in dev/test if not already configured. A lightweight Rack middleware sets `Thread.current[:e11y_source]` from request context (`"web"`) and `env["e11y.trace_id"]` for the Overlay.

**Step 1: Write tests**

```ruby
# spec/e11y/adapters/dev_log_railtie_spec.rb
# frozen_string_literal: true

require "spec_helper"
# Integration test — requires dummy Rails app
require "rails"

RSpec.describe "DevLog Railtie auto-registration", type: :integration do
  it "registers :dev_log adapter in development" do
    expect(E11y.configuration.adapters).to have_key(:dev_log)
  end

  it "registered adapter is a DevLog instance" do
    expect(E11y.configuration.adapters[:dev_log])
      .to be_a(E11y::Adapters::DevLog)
  end
end

RSpec.describe E11y::Middleware::DevLogSource do
  let(:app)  { ->(env) { [200, {}, ["OK"]] } }
  let(:mw)   { described_class.new(app) }

  it "sets Thread.current[:e11y_source] to 'web' for HTML requests" do
    env = Rack::MockRequest.env_for("/orders")
    mw.call(env)
    # Thread local should have been set and cleared
    # (Check via app that captures it)
    captured = nil
    capturing_app = lambda do |e|
      captured = Thread.current[:e11y_source]
      [200, {}, ["OK"]]
    end
    described_class.new(capturing_app).call(env)
    expect(captured).to eq("web")
  end

  it "clears Thread.current[:e11y_source] after request" do
    Thread.current[:e11y_source] = nil
    env = Rack::MockRequest.env_for("/orders")
    mw.call(env)
    expect(Thread.current[:e11y_source]).to be_nil
  end
end
```

**Step 2: Run to verify it fails**

```bash
bundle exec rspec spec/e11y/adapters/dev_log_railtie_spec.rb
```

**Step 3: Implement middleware**

```ruby
# lib/e11y/middleware/dev_log_source.rb
# frozen_string_literal: true

module E11y
  module Middleware
    # Sets Thread.current[:e11y_source] = "web" during a web request.
    # Cleared after the request completes (even on exception).
    # Also stores trace_id in env["e11y.trace_id"] for the Browser Overlay.
    class DevLogSource
      def initialize(app)
        @app = app
      end

      def call(env)
        Thread.current[:e11y_source] = "web"
        # Propagate trace_id for overlay: prefer existing, else generate
        env["e11y.trace_id"] ||= Thread.current[:e11y_trace_id]
        @app.call(env)
      ensure
        Thread.current[:e11y_source] = nil
      end
    end
  end
end
```

**Step 4: Add Railtie initializer**

Add to `lib/e11y/railtie.rb` inside `class Railtie < Rails::Railtie`:

```ruby
initializer "e11y.setup_development", after: :load_config_initializers do |app|
  next unless Rails.env.development? || Rails.env.test?
  next if E11y.configuration.adapters.key?(:dev_log)

  require "e11y/adapters/dev_log"
  require "e11y/middleware/dev_log_source"

  E11y.configure do |config|
    config.register_adapter :dev_log, E11y::Adapters::DevLog.new(
      path:           Rails.root.join("log", "e11y_dev.jsonl"),
      max_lines:      ENV.fetch("E11Y_MAX_EVENTS",    10_000).to_i,
      max_size:       ENV.fetch("E11Y_MAX_SIZE",          50).to_i.megabytes,
      keep_rotated:   ENV.fetch("E11Y_KEEP_ROTATED",       5).to_i,
      enable_watcher: !Rails.env.test?
    )
  end

  app.middleware.use E11y::Middleware::DevLogSource
end
```

**Step 5: Run integration tests**

```bash
bundle exec rspec spec/integration/ --tag integration
```

Expected: dev_log adapter present in dummy app.

**Step 6: Commit**

```bash
git add lib/e11y/railtie.rb \
        lib/e11y/middleware/dev_log_source.rb \
        spec/e11y/adapters/dev_log_railtie_spec.rb
git commit -m "feat: auto-register DevLog adapter in dev/test via Railtie"
```

---

## Phase 2: CLI + TUI (`gem 'e11y-devtools'`)

### Task 5: Gem scaffold — e11y-devtools.gemspec + directory structure

**Files:**
- Create: `gems/e11y-devtools/e11y-devtools.gemspec`
- Create: `gems/e11y-devtools/lib/e11y/devtools/version.rb`
- Create: `gems/e11y-devtools/lib/e11y/devtools.rb`
- Create: `gems/e11y-devtools/exe/e11y`

**Step 1: No failing test — scaffold only. Run this check instead:**

```bash
ls gems/ 2>/dev/null || echo "gems/ dir missing"
```

**Step 2: Create directory structure**

```bash
mkdir -p gems/e11y-devtools/{lib/e11y/devtools,exe,spec}
mkdir -p gems/e11y-devtools/lib/e11y/devtools/{tui,tui/widgets,overlay,mcp,mcp/tools}
```

**Step 3: Create gemspec**

```ruby
# gems/e11y-devtools/e11y-devtools.gemspec
# frozen_string_literal: true

require_relative "lib/e11y/devtools/version"

Gem::Specification.new do |spec|
  spec.name    = "e11y-devtools"
  spec.version = E11y::Devtools::VERSION
  spec.authors = ["Artur Seletskiy"]
  spec.summary = "Developer tools for E11y: TUI, Browser Overlay, MCP Server"

  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*.rb", "exe/*", "*.md"]
  spec.bindir        = "exe"
  spec.executables   = ["e11y"]
  spec.require_paths = ["lib"]

  spec.add_dependency "e11y", "~> #{E11y::Devtools::CORE_VERSION}"
  spec.add_dependency "ratatui_ruby", "~> 1.4"
  spec.add_dependency "mcp",          ">= 1.0"

  # Optional but recommended for performance
  spec.add_development_dependency "oj"
end
```

**Step 4: Create version file**

```ruby
# gems/e11y-devtools/lib/e11y/devtools/version.rb
# frozen_string_literal: true

module E11y
  module Devtools
    VERSION      = "0.1.0"
    CORE_VERSION = "0.2"  # compatible e11y gem version
  end
end
```

**Step 5: Create main lib file**

```ruby
# gems/e11y-devtools/lib/e11y/devtools.rb
# frozen_string_literal: true

require "e11y"
require_relative "devtools/version"

module E11y
  module Devtools
    autoload :Tui,     "e11y/devtools/tui"
    autoload :Overlay, "e11y/devtools/overlay"
    autoload :Mcp,     "e11y/devtools/mcp"
  end
end
```

**Step 6: Create CLI executable**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
# gems/e11y-devtools/exe/e11y

require "e11y/devtools"

command = ARGV.shift || "tui"

case command
when "tui"
  require "e11y/devtools/tui/app"
  E11y::Devtools::Tui::App.new.run
when "mcp"
  require "e11y/devtools/mcp/server"
  E11y::Devtools::Mcp::Server.new.run(
    transport: ARGV.include?("--port") ? :http : :stdio,
    port:      (ARGV[ARGV.index("--port") + 1] if ARGV.include?("--port"))&.to_i
  )
when "tail"
  require "e11y/devtools/tui/tail"
  E11y::Devtools::Tui::Tail.new.run
when "help", "--help", "-h"
  puts <<~HELP
    bundle exec e11y [command]

    Commands:
      tui   (default)  Interactive TUI — browse events and traces
      mcp              MCP server for Cursor / Claude Code AI integration
      tail             Stream new events to stdout (pipe-friendly)
      help             Show this help
  HELP
else
  warn "Unknown command: #{command}. Run `bundle exec e11y help`."
  exit 1
end
```

```bash
chmod +x gems/e11y-devtools/exe/e11y
```

**Step 7: Verify gemspec is valid**

```bash
cd gems/e11y-devtools && gem build e11y-devtools.gemspec 2>&1 | head -5
```

Expected: `Successfully built RubyGem` or no errors.

**Step 8: Commit**

```bash
git add gems/e11y-devtools/
git commit -m "feat: scaffold e11y-devtools gem (gemspec, CLI, version)"
```

---

### Task 6: Interaction grouping logic (pure Ruby, standalone)

**Files:**
- Create: `gems/e11y-devtools/lib/e11y/devtools/tui/grouping.rb`
- Create: `gems/e11y-devtools/spec/tui/grouping_spec.rb`

**Context:** Extract grouping logic from Query into a pure-function module so TUI widgets can use it without instantiating a Query. Also validates the algorithm independently.

**Step 1: Write tests**

```ruby
# gems/e11y-devtools/spec/tui/grouping_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "time"
require "e11y/devtools/tui/grouping"

RSpec.describe E11y::Devtools::Tui::Grouping do
  def make_trace(id, offset_ms, severity: "info", source: "web")
    {
      trace_id:   id,
      started_at: Time.now + (offset_ms / 1000.0),
      severity:   severity,
      source:     source
    }
  end

  describe ".group" do
    it "returns empty array for empty input" do
      expect(described_class.group([])).to eq([])
    end

    it "places single trace in one interaction" do
      groups = described_class.group([make_trace("t1", 0)])
      expect(groups.size).to eq(1)
      expect(groups.first.trace_ids).to eq(["t1"])
    end

    it "groups traces within window into one interaction" do
      traces = [
        make_trace("t1", 0),
        make_trace("t2", 300),  # 300ms after t1 — within 500ms window
        make_trace("t3", 1200)  # 1200ms after t1 — outside window
      ]
      groups = described_class.group(traces, window_ms: 500)
      expect(groups.size).to eq(2)
      expect(groups.first.trace_ids.sort).to eq(%w[t1 t2].sort)
      expect(groups.last.trace_ids).to eq(["t3"])
    end

    it "marks interaction has_error? when any trace has error severity" do
      traces = [
        make_trace("t1", 0, severity: "error"),
        make_trace("t2", 100, severity: "info")
      ]
      groups = described_class.group(traces, window_ms: 500)
      expect(groups.first.has_error?).to be true
    end

    it "marks interaction clean when no errors" do
      groups = described_class.group([make_trace("t1", 0, severity: "info")])
      expect(groups.first.has_error?).to be false
    end

    it "returns groups newest-first" do
      traces = [
        make_trace("old", 0),
        make_trace("new", 2000)
      ]
      groups = described_class.group(traces, window_ms: 500)
      expect(groups.first.trace_ids).to eq(["new"])
    end
  end
end
```

**Step 2: Run to verify it fails**

```bash
bundle exec rspec gems/e11y-devtools/spec/tui/grouping_spec.rb
```

**Step 3: Implement**

```ruby
# gems/e11y-devtools/lib/e11y/devtools/tui/grouping.rb
# frozen_string_literal: true

module E11y
  module Devtools
    module Tui
      # Pure-function time-window grouping for traces → interactions.
      # Shared by TUI widgets, Overlay, and MCP interactions tool.
      module Grouping
        Interaction = Struct.new(:started_at, :trace_ids, :has_error?,
                                 :source, keyword_init: true)

        # Group an array of trace hashes into Interaction bands.
        #
        # @param traces     [Array<Hash>]  Each hash must have :trace_id,
        #                                  :started_at (Time), :severity
        # @param window_ms  [Integer]      Grouping window in milliseconds
        # @return [Array<Interaction>]     Newest-first
        def self.group(traces, window_ms: 500)
          return [] if traces.empty?

          sorted = traces.sort_by { |t| t[:started_at] }
          groups = []
          current = nil

          sorted.each do |trace|
            if current.nil? ||
               (trace[:started_at] - current[:anchor]) * 1000 > window_ms
              current = {
                anchor:    trace[:started_at],
                started_at: trace[:started_at],
                trace_ids: [],
                has_error: false,
                source:    trace[:source]
              }
              groups << current
            end
            current[:trace_ids] << trace[:trace_id]
            current[:has_error] ||= %w[error fatal].include?(trace[:severity])
          end

          groups.reverse.map do |g|
            Interaction.new(
              started_at: g[:started_at],
              trace_ids:  g[:trace_ids],
              has_error?: g[:has_error],
              source:     g[:source]
            )
          end
        end
      end
    end
  end
end
```

**Step 4: Run tests**

```bash
bundle exec rspec gems/e11y-devtools/spec/tui/grouping_spec.rb
```

Expected: all green.

**Step 5: Commit**

```bash
git add gems/e11y-devtools/lib/e11y/devtools/tui/grouping.rb \
        gems/e11y-devtools/spec/tui/grouping_spec.rb
git commit -m "feat: add TUI grouping logic (time-window interaction grouping)"
```

---

### Task 7: TUI widgets — InteractionList, EventList, EventDetail

**Files:**
- Create: `gems/e11y-devtools/lib/e11y/devtools/tui/widgets/interaction_list.rb`
- Create: `gems/e11y-devtools/lib/e11y/devtools/tui/widgets/event_list.rb`
- Create: `gems/e11y-devtools/lib/e11y/devtools/tui/widgets/event_detail.rb`
- Create: `gems/e11y-devtools/spec/tui/widgets/interaction_list_spec.rb`
- Create: `gems/e11y-devtools/spec/tui/widgets/event_list_spec.rb`

**Context:** Three ratatui_ruby widgets. Each implements `#render(frame, area)`.
Use `RatatuiRuby::TestHelper` for snapshot + style assertions.

**Step 1: Write tests for InteractionListWidget**

```ruby
# gems/e11y-devtools/spec/tui/widgets/interaction_list_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "ratatui_ruby/test_helper"
require "e11y/devtools/tui/widgets/interaction_list"

RSpec.describe E11y::Devtools::Tui::Widgets::InteractionList do
  include RatatuiRuby::TestHelper

  let(:t0) { Time.now }

  def make_interaction(trace_ids:, has_error: false)
    E11y::Devtools::Tui::Grouping::Interaction.new(
      started_at: t0,
      trace_ids:  trace_ids,
      has_error?: has_error,
      source:     "web"
    )
  end

  it "renders bullet as ● red when interaction has error" do
    widget = described_class.new(
      interactions:  [make_interaction(trace_ids: ["t1"], has_error: true)],
      selected_index: 0
    )
    with_test_terminal(40, 5) do |terminal|
      terminal.draw { |frame| frame.render_widget(widget, frame.area) }
      assert_cell_style(0, 1, char: "●", fg: :red)
    end
  end

  it "renders bullet as ○ when interaction is clean" do
    widget = described_class.new(
      interactions:  [make_interaction(trace_ids: ["t1"], has_error: false)],
      selected_index: 0
    )
    with_test_terminal(40, 5) do |terminal|
      terminal.draw { |frame| frame.render_widget(widget, frame.area) }
      assert_cell_style(0, 1, char: "○")
    end
  end

  it "shows trace count in row" do
    widget = described_class.new(
      interactions:  [make_interaction(trace_ids: %w[t1 t2 t3])],
      selected_index: 0
    )
    with_test_terminal(60, 5) do |terminal|
      terminal.draw { |frame| frame.render_widget(widget, frame.area) }
      assert_snapshot("interaction_list_3_traces")
    end
  end
end
```

**Step 2: Run to verify it fails**

```bash
bundle exec rspec gems/e11y-devtools/spec/tui/widgets/interaction_list_spec.rb
```

**Step 3: Implement InteractionListWidget**

```ruby
# gems/e11y-devtools/lib/e11y/devtools/tui/widgets/interaction_list.rb
# frozen_string_literal: true

require "ratatui_ruby"
require_relative "../grouping"

module E11y
  module Devtools
    module Tui
      module Widgets
        class InteractionList
          def initialize(interactions:, selected_index: 0, source_filter: :all)
            @interactions   = interactions
            @selected_index = selected_index
            @source_filter  = source_filter
          end

          def render(frame, area)
            rows = @interactions.each_with_index.map do |ix, i|
              bullet    = ix.has_error? ? "●" : "○"
              bullet_fg = ix.has_error? ? :red : :gray
              time_str  = ix.started_at.strftime("%H:%M:%S")
              count_str = "#{ix.traces_count} req"
              error_str = ix.has_error? ? "  ● err" : ""

              [
                frame.span(bullet, style: { fg: bullet_fg }),
                " #{time_str}  #{count_str}#{error_str}"
              ].join
            end

            frame.render_widget(
              frame.list(
                items:          rows,
                highlight_style: { bg: :dark_gray },
                selected:       @selected_index
              ).block(title: " INTERACTIONS ", borders: :all),
              area
            )
          end
        end
      end
    end
  end
end
```

**Step 4: Implement EventListWidget**

```ruby
# gems/e11y-devtools/lib/e11y/devtools/tui/widgets/event_list.rb
# frozen_string_literal: true

require "ratatui_ruby"

module E11y
  module Devtools
    module Tui
      module Widgets
        class EventList
          SEVERITY_COLORS = {
            "debug" => :dark_gray,
            "info"  => :white,
            "warn"  => :yellow,
            "error" => :red,
            "fatal" => :red
          }.freeze

          def initialize(events:, trace_id:, selected_index: 0)
            @events         = events
            @trace_id       = trace_id
            @selected_index = selected_index
          end

          def render(frame, area)
            header = %w[# Severity Event\ Name Duration At]
            rows   = @events.each_with_index.map do |e, i|
              sev   = e["severity"] || "info"
              color = SEVERITY_COLORS.fetch(sev, :white)
              [
                (i + 1).to_s,
                frame.span(sev.upcase, style: { fg: color }),
                e["event_name"].to_s,
                duration_str(e),
                timestamp_short(e["timestamp"])
              ]
            end

            frame.render_widget(
              frame.table(
                header:          header,
                rows:            rows,
                highlight_style: { bg: :dark_gray },
                selected:        @selected_index
              ).block(title: " #{@trace_id} ", borders: :all),
              area
            )
          end

          private

          def duration_str(event)
            ms = event.dig("metadata", "duration_ms")
            ms ? "#{ms}ms" : "—"
          end

          def timestamp_short(ts)
            return "—" unless ts

            Time.parse(ts).strftime(".%L")
          rescue ArgumentError
            "—"
          end
        end
      end
    end
  end
end
```

**Step 5: Implement EventDetailWidget**

```ruby
# gems/e11y-devtools/lib/e11y/devtools/tui/widgets/event_detail.rb
# frozen_string_literal: true

require "ratatui_ruby"
require "json"

module E11y
  module Devtools
    module Tui
      module Widgets
        # Full-screen overlay showing event payload.
        # Rendered as a Popup/Overlay over the main layout.
        class EventDetail
          def initialize(event:)
            @event = event
          end

          def render(frame, area)
            popup_area = centered_rect(area, percent_x: 80, percent_y: 70)

            # Clear background
            frame.render_widget(frame.clear, popup_area)

            sev   = @event["severity"] || "info"
            title = " #{@event["event_name"]} · #{sev.upcase} "

            lines = build_lines
            frame.render_widget(
              frame.paragraph(text: lines)
                   .block(title: title, borders: :all)
                   .scroll(0),
              popup_area
            )
          end

          private

          def build_lines
            lines = []
            lines << "  timestamp:  #{@event["timestamp"]}"
            lines << "  trace_id:   #{@event["trace_id"]}"
            lines << "  span_id:    #{@event["span_id"]}"
            lines << ""
            lines << "  payload:"
            JSON.pretty_generate(@event["payload"] || {}).each_line do |l|
              lines << "    #{l.chomp}"
            end
            lines << ""
            lines << "  [c] copy JSON    [b] back"
            lines
          end

          def centered_rect(area, percent_x:, percent_y:)
            w = (area.width  * percent_x / 100).to_i
            h = (area.height * percent_y / 100).to_i
            x = area.x + (area.width  - w) / 2
            y = area.y + (area.height - h) / 2
            RatatuiRuby::Rect.new(x: x, y: y, width: w, height: h)
          end
        end
      end
    end
  end
end
```

**Step 6: Run widget tests**

```bash
bundle exec rspec gems/e11y-devtools/spec/tui/widgets/
```

Expected: all green.

**Step 7: Commit**

```bash
git add gems/e11y-devtools/lib/e11y/devtools/tui/widgets/ \
        gems/e11y-devtools/spec/tui/widgets/
git commit -m "feat: add TUI widgets (InteractionList, EventList, EventDetail)"
```

---

### Task 8: TUI App — main loop, keyboard bindings, file watcher

**Files:**
- Create: `gems/e11y-devtools/lib/e11y/devtools/tui/app.rb`
- Create: `gems/e11y-devtools/spec/tui/app_spec.rb`

**Context:** Top-level `App` manages navigation state (`:interactions` | `:events` | `:detail`), handles keyboard events, and triggers redraws on file changes. Uses incremental read via `Query`.

**Step 1: Write tests**

```ruby
# gems/e11y-devtools/spec/tui/app_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "e11y/devtools/tui/app"

RSpec.describe E11y::Devtools::Tui::App do
  subject(:app) { described_class.new(log_path: "/dev/null") }

  describe "#initialize" do
    it "starts in :interactions view" do
      expect(app.current_view).to eq(:interactions)
    end

    it "starts with source_filter :web" do
      expect(app.source_filter).to eq(:web)
    end
  end

  describe "#handle_key" do
    context "in :interactions view" do
      it "drills into :events on Enter" do
        allow(app).to receive(:selected_interaction).and_return(
          double(trace_ids: ["t1"])
        )
        app.handle_key("enter")
        expect(app.current_view).to eq(:events)
      end

      it "toggles source to :jobs on 'j'" do
        app.handle_key("j")
        expect(app.source_filter).to eq(:job)
      end

      it "toggles source to :all on 'a'" do
        app.handle_key("a")
        expect(app.source_filter).to eq(:all)
      end

      it "toggles source back to :web on 'w'" do
        app.handle_key("a")
        app.handle_key("w")
        expect(app.source_filter).to eq(:web)
      end
    end

    context "in :events view" do
      before do
        app.instance_variable_set(:@current_view, :events)
        app.instance_variable_set(:@current_trace_id, "t1")
        app.instance_variable_set(:@events, [{ "id" => "e1", "event_name" => "x" }])
      end

      it "goes back to :interactions on Esc" do
        app.handle_key("esc")
        expect(app.current_view).to eq(:interactions)
      end

      it "drills into :detail on Enter" do
        app.handle_key("enter")
        expect(app.current_view).to eq(:detail)
      end
    end

    context "in :detail view" do
      before { app.instance_variable_set(:@current_view, :detail) }

      it "goes back to :events on Esc" do
        app.handle_key("esc")
        expect(app.current_view).to eq(:events)
      end

      it "goes back to :events on 'b'" do
        app.handle_key("b")
        expect(app.current_view).to eq(:events)
      end
    end
  end
end
```

**Step 2: Run to verify it fails**

```bash
bundle exec rspec gems/e11y-devtools/spec/tui/app_spec.rb
```

**Step 3: Implement App**

```ruby
# gems/e11y-devtools/lib/e11y/devtools/tui/app.rb
# frozen_string_literal: true

require "ratatui_ruby"
require "e11y/adapters/dev_log/query"
require_relative "grouping"
require_relative "widgets/interaction_list"
require_relative "widgets/event_list"
require_relative "widgets/event_detail"

module E11y
  module Devtools
    module Tui
      class App
        attr_reader :current_view, :source_filter

        POLL_INTERVAL_MS = 250

        def initialize(log_path: nil)
          @log_path      = log_path || auto_detect_log_path
          @query         = E11y::Adapters::DevLog::Query.new(@log_path)
          @current_view  = :interactions
          @source_filter = :web
          @selected_ix   = 0
          @interactions  = []
          @events        = []
          @current_trace_id = nil
          @current_event    = nil
          @last_mtime       = nil
        end

        def run
          RatatuiRuby.run do |tui|
            loop do
              reload_if_changed!

              tui.draw { |frame| render(frame) }

              event = tui.poll_event(timeout_ms: POLL_INTERVAL_MS)
              break if quit_event?(event)

              handle_key(key_from(event)) if key_event?(event)
            end
          end
        end

        def handle_key(key)
          case @current_view
          when :interactions then handle_interactions_key(key)
          when :events       then handle_events_key(key)
          when :detail       then handle_detail_key(key)
          end
        end

        def selected_interaction
          @interactions[@selected_ix]
        end

        private

        def render(frame)
          case @current_view
          when :interactions
            render_interactions(frame)
          when :events
            render_events(frame)
          when :detail
            render_events(frame)
            Widgets::EventDetail.new(event: @current_event).render(frame, frame.area)
          end
        end

        def render_interactions(frame)
          Widgets::InteractionList.new(
            interactions:   @interactions,
            selected_index: @selected_ix
          ).render(frame, frame.area)
        end

        def render_events(frame)
          Widgets::EventList.new(
            events:         @events,
            trace_id:       @current_trace_id || "",
            selected_index: @selected_ix
          ).render(frame, frame.area)
        end

        # --- Key handlers per view ---

        def handle_interactions_key(key)
          case key
          when "enter"
            ix = selected_interaction
            return unless ix

            @current_trace_id = ix.trace_ids.first
            @events           = @query.events_by_trace(@current_trace_id)
            @selected_ix      = 0
            @current_view     = :events
          when "j", "down" then @selected_ix = [@selected_ix + 1, @interactions.size - 1].min
          when "k", "up"   then @selected_ix = [@selected_ix - 1, 0].max
          when "w"         then @source_filter = :web;  reload!
          when "j"         then @source_filter = :job;  reload!
          when "a"         then @source_filter = :all;  reload!
          when "i"         then toggle_interaction_mode
          when "r"         then reload!
          end
        end

        def handle_events_key(key)
          case key
          when "esc", "b"
            @current_view = :interactions
            @selected_ix  = 0
          when "enter"
            event = @events[@selected_ix]
            return unless event

            @current_event = event
            @current_view  = :detail
          when "j", "down" then @selected_ix = [@selected_ix + 1, @events.size - 1].min
          when "k", "up"   then @selected_ix = [@selected_ix - 1, 0].max
          end
        end

        def handle_detail_key(key)
          case key
          when "esc", "b" then @current_view = :events
          when "c"        then copy_to_clipboard(JSON.generate(@current_event))
          end
        end

        # --- Data loading ---

        def reload_if_changed!
          mtime = file_mtime
          return if mtime == @last_mtime

          @last_mtime = mtime
          reload!
        end

        def reload!
          source = @source_filter == :all ? nil : @source_filter.to_s
          traces = build_traces(source)
          @interactions = Grouping.group(traces, window_ms: 500)
        end

        def build_traces(source)
          events = @query.stored_events(limit: 5000, source: source)
          trace_map = {}
          events.each do |e|
            tid = e["trace_id"]
            next unless tid

            t = trace_map[tid] ||= {
              trace_id:   tid,
              started_at: parse_time(e.dig("metadata", "started_at") || e["timestamp"]),
              severity:   e["severity"],
              source:     e.dig("metadata", "source") || "web"
            }
            t[:severity] = "error" if %w[error fatal].include?(e["severity"])
          end
          trace_map.values.compact
        end

        def file_mtime
          File.mtime(@log_path)
        rescue Errno::ENOENT
          nil
        end

        def toggle_interaction_mode
          # Future: toggle flat trace view
        end

        def copy_to_clipboard(text)
          IO.popen("pbcopy", "w") { |f| f.write(text) } rescue nil  # macOS
          IO.popen("xclip -selection clipboard", "w") { |f| f.write(text) } rescue nil  # Linux
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

        def parse_time(str)
          Time.parse(str)
        rescue ArgumentError, TypeError
          Time.now
        end

        def quit_event?(event)
          return false unless event

          (event[:type] == :key && %w[q].include?(event[:code])) ||
            (event[:type] == :key && event[:code] == "c" && event[:modifiers]&.include?("ctrl"))
        end

        def key_event?(event)
          event && event[:type] == :key
        end

        def key_from(event)
          event&.dig(:code)
        end
      end
    end
  end
end
```

**Step 4: Run tests**

```bash
bundle exec rspec gems/e11y-devtools/spec/tui/app_spec.rb
```

Expected: all green.

**Step 5: Smoke test — launch TUI manually**

```bash
bundle exec e11y tui
# Should open TUI. Press q to quit.
```

**Step 6: Commit**

```bash
git add gems/e11y-devtools/lib/e11y/devtools/tui/ \
        gems/e11y-devtools/spec/tui/app_spec.rb
git commit -m "feat: add TUI App (main loop, keyboard navigation, file watcher)"
```

---

## Phase 3: Browser Overlay

### Task 9: Rails Engine scaffold + JSON endpoints

**Files:**
- Create: `gems/e11y-devtools/lib/e11y/devtools/overlay/engine.rb`
- Create: `gems/e11y-devtools/lib/e11y/devtools/overlay/controller.rb`
- Create: `gems/e11y-devtools/spec/overlay/controller_spec.rb`

**Step 1: Write failing tests**

```ruby
# gems/e11y-devtools/spec/overlay/controller_spec.rb
# frozen_string_literal: true

require "spec_helper"
# Requires dummy Rails app in spec/dummy/
require "rails"

RSpec.describe E11y::Devtools::Overlay::Controller, type: :request do
  before { allow(Rails).to receive(:env).and_return("development".inquiry) }

  describe "GET /_e11y/events" do
    context "with a trace_id" do
      it "returns JSON array" do
        get "/_e11y/events", params: { trace_id: "abc123" }
        expect(response.content_type).to include("application/json")
        expect(JSON.parse(response.body)).to be_an(Array)
      end
    end
  end

  describe "GET /_e11y/events/recent" do
    it "returns recent events" do
      get "/_e11y/events/recent", params: { limit: 10 }
      expect(response.status).to eq(200)
      expect(JSON.parse(response.body)).to be_an(Array)
    end
  end

  describe "DELETE /_e11y/events" do
    it "clears the log and returns 204" do
      delete "/_e11y/events"
      expect(response.status).to eq(204)
    end
  end

  describe "in production" do
    before { allow(Rails).to receive(:env).and_return("production".inquiry) }

    it "returns 404" do
      get "/_e11y/events/recent"
      expect(response.status).to eq(404)
    end
  end
end
```

**Step 2: Implement Engine**

```ruby
# gems/e11y-devtools/lib/e11y/devtools/overlay/engine.rb
# frozen_string_literal: true

require "rails"

module E11y
  module Devtools
    module Overlay
      class Engine < Rails::Engine
        isolate_namespace E11y::Devtools::Overlay

        initializer "e11y_devtools.overlay.middleware" do |app|
          next unless Rails.env.development?

          require "e11y/devtools/overlay/middleware"
          app.middleware.use E11y::Devtools::Overlay::Middleware
        end

        config.generators do |g|
          g.test_framework :rspec
        end
      end
    end
  end
end
```

**Step 3: Implement Controller**

```ruby
# gems/e11y-devtools/lib/e11y/devtools/overlay/controller.rb
# frozen_string_literal: true

module E11y
  module Devtools
    module Overlay
      class Controller < ActionController::Base
        before_action :development_only!

        # GET /_e11y/events?trace_id=abc123
        def events
          trace_id = params[:trace_id]
          events   = trace_id ? query.events_by_trace(trace_id) : query.stored_events(limit: 50)
          render json: events
        end

        # GET /_e11y/events/recent?limit=50
        def recent
          limit  = (params[:limit] || 50).to_i.clamp(1, 500)
          render json: query.stored_events(limit: limit)
        end

        # DELETE /_e11y/events
        def clear
          query.clear!
          head :no_content
        end

        private

        def query
          @query ||= begin
            adapter = E11y.configuration.adapters[:dev_log]
            adapter || E11y::Adapters::DevLog::Query.new(
              Rails.root.join("log", "e11y_dev.jsonl").to_s
            )
          end
        end

        def development_only!
          head :not_found unless Rails.env.development?
        end
      end
    end
  end
end
```

**Step 4: Add routes via Engine config**

```ruby
# gems/e11y-devtools/config/routes.rb
E11y::Devtools::Overlay::Engine.routes.draw do
  get    "events",        to: "e11y/devtools/overlay/controller#events"
  get    "events/recent", to: "e11y/devtools/overlay/controller#recent"
  delete "events",        to: "e11y/devtools/overlay/controller#clear"
end
```

Mount path `/_e11y` is set in Engine config automatically via `isolate_namespace`.

**Step 5: Run tests**

```bash
bundle exec rspec gems/e11y-devtools/spec/overlay/controller_spec.rb
```

**Step 6: Commit**

```bash
git add gems/e11y-devtools/lib/e11y/devtools/overlay/ \
        gems/e11y-devtools/config/routes.rb \
        gems/e11y-devtools/spec/overlay/controller_spec.rb
git commit -m "feat: add Browser Overlay Rails Engine and JSON endpoints"
```

---

### Task 10: Rack middleware — HTML injection + Shadow DOM overlay

**Files:**
- Create: `gems/e11y-devtools/lib/e11y/devtools/overlay/middleware.rb`
- Create: `gems/e11y-devtools/lib/e11y/devtools/overlay/assets/overlay.js`
- Create: `gems/e11y-devtools/lib/e11y/devtools/overlay/assets/overlay.css`
- Create: `gems/e11y-devtools/spec/overlay/middleware_spec.rb`

**Step 1: Write failing tests**

```ruby
# gems/e11y-devtools/spec/overlay/middleware_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"
require "e11y/devtools/overlay/middleware"

RSpec.describe E11y::Devtools::Overlay::Middleware do
  include Rack::Test::Methods

  let(:html_body) { "<html><body><h1>Hello</h1></body></html>" }
  let(:base_app)  do
    lambda { |_env| [200, { "Content-Type" => "text/html" }, [html_body]] }
  end

  def app = described_class.new(base_app)

  it "injects overlay script before </body>" do
    get "/"
    expect(last_response.body).to include("e11y-overlay")
    expect(last_response.body).to include("</body>")
  end

  it "does not inject into non-HTML responses" do
    json_app = ->(env) { [200, { "Content-Type" => "application/json" }, ['{"ok":true}']] }
    response = described_class.new(json_app).call(Rack::MockRequest.env_for("/"))
    body = response[2].join
    expect(body).not_to include("e11y-overlay")
  end

  it "does not inject into XHR requests" do
    get "/", {}, { "HTTP_X_REQUESTED_WITH" => "XMLHttpRequest" }
    expect(last_response.body).not_to include("e11y-overlay")
  end

  it "does not inject into asset paths" do
    get "/assets/application.js"
    expect(last_response.body).not_to include("e11y-overlay")
  end

  it "preserves Content-Length header after injection" do
    get "/"
    # Content-Length should be updated or removed (not stale)
    if last_response.headers["Content-Length"]
      expect(last_response.headers["Content-Length"].to_i)
        .to eq(last_response.body.bytesize)
    end
  end
end
```

**Step 2: Implement middleware**

```ruby
# gems/e11y-devtools/lib/e11y/devtools/overlay/middleware.rb
# frozen_string_literal: true

module E11y
  module Devtools
    module Overlay
      class Middleware
        OVERLAY_SCRIPT = <<~HTML.freeze

          <!-- E11y Devtools Overlay -->
          <script>
            (function() {
              var s = document.createElement('script');
              s.src = '/_e11y/overlay.js';
              s.defer = true;
              document.head.appendChild(s);
            })();
          </script>
        HTML

        def initialize(app)
          @app = app
        end

        def call(env)
          status, headers, body = @app.call(env)
          return [status, headers, body] unless injectable?(env, headers)

          new_body = inject_overlay(body, env["e11y.trace_id"])
          headers  = update_content_length(headers, new_body)
          [status, headers, [new_body]]
        end

        private

        def injectable?(env, headers)
          return false if xhr?(env)
          return false if asset_path?(env)
          return false unless html_response?(headers)

          true
        end

        def xhr?(env)
          env["HTTP_X_REQUESTED_WITH"]&.downcase == "xmlhttprequest"
        end

        def asset_path?(env)
          path = env["PATH_INFO"] || ""
          path.start_with?("/assets/", "/packs/", "/_e11y/")
        end

        def html_response?(headers)
          ct = headers["Content-Type"] || headers["content-type"] || ""
          ct.include?("text/html")
        end

        def inject_overlay(body, trace_id)
          full_body = body.respond_to?(:join) ? body.join : body.to_s
          script    = trace_id_script(trace_id) + OVERLAY_SCRIPT
          full_body.sub("</body>", "#{script}</body>")
        end

        def trace_id_script(trace_id)
          return "" unless trace_id

          "<script>window.__E11Y_TRACE_ID__ = '#{trace_id}';</script>\n"
        end

        def update_content_length(headers, new_body)
          headers = headers.dup
          headers.delete("Content-Length")
          headers.delete("content-length")
          headers["Content-Length"] = new_body.bytesize.to_s
          headers
        end
      end
    end
  end
end
```

**Step 3: Create overlay JS (vanilla, Shadow DOM)**

```javascript
// gems/e11y-devtools/lib/e11y/devtools/overlay/assets/overlay.js
(function() {
  'use strict';

  const POLL_INTERVAL = 2000;
  const API_BASE = '/_e11y';

  // --- Shadow DOM container ---
  class E11yOverlay extends HTMLElement {
    connectedCallback() {
      const shadow = this.attachShadow({ mode: 'open' });
      shadow.innerHTML = `
        <style>
          :host { position: fixed; bottom: 16px; right: 16px; z-index: 99999; font-family: monospace; }
          .badge { background: #1a1a2e; color: #e0e0e0; border-radius: 6px; padding: 6px 12px;
                   cursor: pointer; font-size: 12px; border: 1px solid #333; }
          .badge.has-error { border-color: #e53e3e; color: #fc8181; }
          .panel { display: none; position: fixed; right: 16px; bottom: 60px; width: 420px;
                   max-height: 70vh; background: #1a1a2e; border: 1px solid #444;
                   border-radius: 8px; overflow: hidden; flex-direction: column; }
          .panel.open { display: flex; }
          .panel-header { padding: 10px 14px; background: #16213e; border-bottom: 1px solid #333;
                          display: flex; justify-content: space-between; align-items: center;
                          font-size: 12px; color: #a0aec0; }
          .panel-title { color: #e0e0e0; font-weight: bold; }
          .close-btn { cursor: pointer; color: #718096; }
          .events { overflow-y: auto; flex: 1; padding: 8px; }
          .event-row { padding: 4px 8px; border-radius: 4px; margin-bottom: 2px;
                       font-size: 11px; cursor: pointer; display: flex; gap: 8px; }
          .event-row:hover { background: #2d3748; }
          .sev-error { color: #fc8181; }
          .sev-warn  { color: #f6ad55; }
          .sev-info  { color: #68d391; }
          .footer { padding: 8px 14px; border-top: 1px solid #333; display: flex;
                    gap: 12px; font-size: 11px; }
          .footer a { color: #63b3ed; cursor: pointer; text-decoration: none; }
          .footer a:hover { text-decoration: underline; }
        </style>

        <div class="badge" id="badge">e11y</div>
        <div class="panel" id="panel">
          <div class="panel-header">
            <span class="panel-title" id="panel-title">e11y devtools</span>
            <span class="close-btn" id="close-btn">✕</span>
          </div>
          <div class="events" id="events-list"></div>
          <div class="footer">
            <a id="clear-btn">clear log</a>
            <a id="copy-trace-btn">copy trace_id</a>
          </div>
        </div>
      `;

      this._shadow     = shadow;
      this._panelOpen  = false;
      this._traceId    = window.__E11Y_TRACE_ID__ || null;
      this._events     = [];

      shadow.getElementById('badge').addEventListener('click',  () => this.togglePanel());
      shadow.getElementById('close-btn').addEventListener('click', () => this.closePanel());
      shadow.getElementById('clear-btn').addEventListener('click', () => this.clearLog());
      shadow.getElementById('copy-trace-btn').addEventListener('click', () => this.copyTrace());

      this.loadEvents();
      this._pollTimer = setInterval(() => this.loadEvents(), POLL_INTERVAL);
    }

    disconnectedCallback() {
      clearInterval(this._pollTimer);
    }

    togglePanel() { this._panelOpen ? this.closePanel() : this.openPanel(); }
    openPanel()   { this._panelOpen = true;  this._shadow.getElementById('panel').classList.add('open'); }
    closePanel()  { this._panelOpen = false; this._shadow.getElementById('panel').classList.remove('open'); }

    loadEvents() {
      const url = this._traceId
        ? `${API_BASE}/events?trace_id=${encodeURIComponent(this._traceId)}`
        : `${API_BASE}/events/recent?limit=20`;

      fetch(url)
        .then(r => r.json())
        .then(events => { this._events = events; this.renderBadge(); this.renderEvents(); })
        .catch(() => {});
    }

    renderBadge() {
      const badge    = this._shadow.getElementById('badge');
      const hasError = this._events.some(e => e.severity === 'error' || e.severity === 'fatal');
      const count    = this._events.length;
      const errCount = this._events.filter(e => e.severity === 'error' || e.severity === 'fatal').length;

      badge.textContent = errCount > 0 ? `e11y  ${count} ● ${errCount}` : `e11y  ${count}`;
      badge.className   = hasError ? 'badge has-error' : 'badge';

      const title = this._traceId
        ? `${this._events[0]?.metadata?.method || 'GET'} ${this._events[0]?.metadata?.path || '/'}`
        : 'e11y devtools';
      this._shadow.getElementById('panel-title').textContent = title;
    }

    renderEvents() {
      const list = this._shadow.getElementById('events-list');
      list.innerHTML = this._events.map(e => `
        <div class="event-row">
          <span class="sev-${e.severity}">${e.severity.toUpperCase().slice(0,4)}</span>
          <span>${e.event_name}</span>
          <span style="color:#718096;margin-left:auto">${e.metadata?.duration_ms || ''}ms</span>
        </div>
      `).join('');
    }

    clearLog() {
      fetch(`${API_BASE}/events`, { method: 'DELETE' })
        .then(() => { this._events = []; this.renderBadge(); this.renderEvents(); });
    }

    copyTrace() {
      if (this._traceId) navigator.clipboard?.writeText(this._traceId);
    }
  }

  customElements.define('e11y-overlay', E11yOverlay);

  // Mount if not already present
  if (!document.querySelector('e11y-overlay')) {
    document.body.appendChild(document.createElement('e11y-overlay'));
  }
})();
```

**Step 4: Run middleware tests**

```bash
bundle exec rspec gems/e11y-devtools/spec/overlay/middleware_spec.rb
```

Expected: all green.

**Step 5: Smoke test in dummy app**

```bash
cd spec/dummy && bundle exec rails server &
# Open http://localhost:3000 — should see e11y badge in bottom-right
```

**Step 6: Commit**

```bash
git add gems/e11y-devtools/lib/e11y/devtools/overlay/ \
        gems/e11y-devtools/spec/overlay/middleware_spec.rb
git commit -m "feat: add Browser Overlay middleware (HTML injection, Shadow DOM, JS badge)"
```

---

## Phase 4: MCP Server

### Task 11: MCP tools + server

**Files:**
- Create: `gems/e11y-devtools/lib/e11y/devtools/mcp/server.rb`
- Create: `gems/e11y-devtools/lib/e11y/devtools/mcp/tools/recent_events.rb`
- Create: `gems/e11y-devtools/lib/e11y/devtools/mcp/tools/events_by_trace.rb`
- Create: `gems/e11y-devtools/lib/e11y/devtools/mcp/tools/search.rb`
- Create: `gems/e11y-devtools/lib/e11y/devtools/mcp/tools/stats.rb`
- Create: `gems/e11y-devtools/lib/e11y/devtools/mcp/tools/interactions.rb`
- Create: `gems/e11y-devtools/lib/e11y/devtools/mcp/tools/event_detail.rb`
- Create: `gems/e11y-devtools/lib/e11y/devtools/mcp/tools/errors.rb`
- Create: `gems/e11y-devtools/lib/e11y/devtools/mcp/tools/clear.rb`
- Create: `gems/e11y-devtools/spec/mcp/tools_spec.rb`

**Context:** Each tool is an `MCP::Tool` subclass. Server wires them together.
`server_context[:store]` is a `DevLog::Query` instance.

**Step 1: Write failing tests**

```ruby
# gems/e11y-devtools/spec/mcp/tools_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "e11y/devtools/mcp/tools/recent_events"
require "e11y/devtools/mcp/tools/events_by_trace"
require "e11y/devtools/mcp/tools/search"
require "e11y/devtools/mcp/tools/stats"
require "e11y/devtools/mcp/tools/errors"
require "e11y/devtools/mcp/tools/clear"

RSpec.describe "MCP Tools" do
  let(:dir)   { Dir.mktmpdir("e11y_mcp") }
  let(:path)  { File.join(dir, "e11y_dev.jsonl") }
  let(:store) { E11y::Adapters::DevLog::Query.new(path) }
  let(:ctx)   { { store: store } }

  after { FileUtils.remove_entry(dir) }

  def write_event(overrides = {})
    data = { "id" => SecureRandom.uuid, "timestamp" => Time.now.iso8601(3),
             "event_name" => "test.event", "severity" => "info",
             "trace_id" => "t1", "payload" => {}, "metadata" => {} }.merge(overrides)
    File.open(path, "a") { |f| f.puts(JSON.generate(data)) }
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
    it "clears the log and returns confirmation" do
      write_event
      result = described_class.call(server_context: ctx)
      expect(result).to include("cleared")
      expect(store.stored_events).to be_empty
    end
  end
end
```

**Step 2: Run to verify it fails**

```bash
bundle exec rspec gems/e11y-devtools/spec/mcp/tools_spec.rb
```

**Step 3: Implement each tool**

```ruby
# gems/e11y-devtools/lib/e11y/devtools/mcp/tools/recent_events.rb
# frozen_string_literal: true

require "mcp"

module E11y::Devtools::Mcp::Tools
  class RecentEvents < MCP::Tool
    description "Get recent E11y events from the development log"

    input_schema(
      type: :object,
      properties: {
        limit:    { type: :integer, description: "Max events to return (default 50)",
                    default: 50 },
        severity: { type: :string, description: "Filter by severity level",
                    enum: %w[debug info warn error fatal] }
      }
    )

    def self.call(limit: 50, severity: nil, server_context:)
      server_context[:store].stored_events(limit: limit, severity: severity)
    end
  end
end
```

```ruby
# gems/e11y-devtools/lib/e11y/devtools/mcp/tools/events_by_trace.rb
# frozen_string_literal: true

require "mcp"

module E11y::Devtools::Mcp::Tools
  class EventsByTrace < MCP::Tool
    description "Get all events for a specific trace ID in chronological order"

    input_schema(
      type: :object,
      required: ["trace_id"],
      properties: {
        trace_id: { type: :string, description: "Trace ID to look up" }
      }
    )

    def self.call(trace_id:, server_context:)
      server_context[:store].events_by_trace(trace_id)
    end
  end
end
```

```ruby
# gems/e11y-devtools/lib/e11y/devtools/mcp/tools/search.rb
# frozen_string_literal: true

require "mcp"

module E11y::Devtools::Mcp::Tools
  class Search < MCP::Tool
    description "Full-text search across event names and payload content"

    input_schema(
      type: :object,
      required: ["query"],
      properties: {
        query: { type: :string, description: "Search term" },
        limit: { type: :integer, description: "Max results (default 50)", default: 50 }
      }
    )

    def self.call(query:, limit: 50, server_context:)
      server_context[:store].search(query, limit: limit)
    end
  end
end
```

```ruby
# gems/e11y-devtools/lib/e11y/devtools/mcp/tools/stats.rb
# frozen_string_literal: true

require "mcp"

module E11y::Devtools::Mcp::Tools
  class Stats < MCP::Tool
    description "Get aggregate statistics about the E11y development log"
    input_schema(type: :object, properties: {})

    def self.call(server_context:, **_)
      server_context[:store].stats
    end
  end
end
```

```ruby
# gems/e11y-devtools/lib/e11y/devtools/mcp/tools/interactions.rb
# frozen_string_literal: true

require "mcp"

module E11y::Devtools::Mcp::Tools
  class Interactions < MCP::Tool
    description "Get time-grouped interactions (parallel requests from one user action)"

    input_schema(
      type: :object,
      properties: {
        limit:     { type: :integer, description: "Max interactions (default 20)", default: 20 },
        window_ms: { type: :integer, description: "Grouping window in ms (default 500)", default: 500 }
      }
    )

    def self.call(limit: 20, window_ms: 500, server_context:)
      server_context[:store].interactions(limit: limit, window_ms: window_ms).map do |ix|
        { started_at: ix.started_at.iso8601(3), trace_ids: ix.trace_ids,
          has_error: ix.has_error?, traces_count: ix.traces_count }
      end
    end
  end
end
```

```ruby
# gems/e11y-devtools/lib/e11y/devtools/mcp/tools/event_detail.rb
# frozen_string_literal: true

require "mcp"

module E11y::Devtools::Mcp::Tools
  class EventDetail < MCP::Tool
    description "Get full payload of a single event by ID"

    input_schema(
      type: :object,
      required: ["event_id"],
      properties: {
        event_id: { type: :string, description: "Event UUID" }
      }
    )

    def self.call(event_id:, server_context:)
      server_context[:store].find_event(event_id) ||
        { error: "Event #{event_id} not found" }
    end
  end
end
```

```ruby
# gems/e11y-devtools/lib/e11y/devtools/mcp/tools/errors.rb
# frozen_string_literal: true

require "mcp"

module E11y::Devtools::Mcp::Tools
  class Errors < MCP::Tool
    description "Get recent error and fatal events only — fastest way to see what went wrong"

    input_schema(
      type: :object,
      properties: {
        limit: { type: :integer, description: "Max events (default 20)", default: 20 }
      }
    )

    def self.call(limit: 20, server_context:)
      events = server_context[:store].stored_events(limit: limit * 5)
      events.select { |e| %w[error fatal].include?(e["severity"]) }.first(limit)
    end
  end
end
```

```ruby
# gems/e11y-devtools/lib/e11y/devtools/mcp/tools/clear.rb
# frozen_string_literal: true

require "mcp"

module E11y::Devtools::Mcp::Tools
  class Clear < MCP::Tool
    description "Clear the E11y development log file"
    input_schema(type: :object, properties: {})

    def self.call(server_context:, **_)
      server_context[:store].clear!
      "E11y log cleared successfully"
    end
  end
end
```

**Step 4: Implement Server**

```ruby
# gems/e11y-devtools/lib/e11y/devtools/mcp/server.rb
# frozen_string_literal: true

require "mcp"
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

        # @param transport [:stdio, :http]
        # @param port      [Integer, nil]
        def run(transport: :stdio, port: nil)
          server = MCP::Server.new(
            name:           "e11y",
            version:        E11y::Devtools::VERSION,
            tools:          TOOLS,
            server_context: { store: @store }
          )

          case transport
          when :stdio
            t = MCP::Server::Transports::StdioTransport.new(server)
            server.transport = t
            t.open
          when :http
            t = MCP::Server::Transports::StreamableHTTPTransport.new(server)
            server.transport = t
            require "webrick"
            s = WEBrick::HTTPServer.new(Port: port || 3099, Logger: WEBrick::Log.new(nil))
            s.mount("/mcp", t)
            trap("INT") { s.shutdown }
            s.start
          end
        end

        private

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
```

**Step 5: Run MCP tool tests**

```bash
bundle exec rspec gems/e11y-devtools/spec/mcp/tools_spec.rb
```

Expected: all green (8 describe blocks, ≥ 12 examples).

**Step 6: Smoke test MCP server (stdio)**

```bash
# Should start without error and wait on stdin:
echo '{"jsonrpc":"2.0","method":"tools/list","id":1}' | bundle exec e11y mcp
# Expected output: JSON with list of 8 tools
```

**Step 7: Commit**

```bash
git add gems/e11y-devtools/lib/e11y/devtools/mcp/ \
        gems/e11y-devtools/spec/mcp/tools_spec.rb
git commit -m "feat: add MCP Server with 8 tools (official gem 'mcp', stdio + HTTP)"
```

---

## Phase 5: Integration + documentation

### Task 12: End-to-end integration test

**Files:**
- Create: `spec/integration/devtools_integration_spec.rb`

**Step 1: Write integration test**

```ruby
# spec/integration/devtools_integration_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "e11y/adapters/dev_log"

RSpec.describe "DevTools E2E", :integration do
  let(:tmpdir) { Dir.mktmpdir("e11y_e2e") }
  let(:path)   { File.join(tmpdir, "e11y_dev.jsonl") }

  after { FileUtils.remove_entry(tmpdir) }

  let(:adapter) { E11y::Adapters::DevLog.new(path: path) }
  let(:query)   { E11y::Adapters::DevLog::Query.new(path) }

  it "write → read → search pipeline works end-to-end" do
    adapter.write(event_name: "payment.failed", severity: "error",
                  trace_id: "trace-1", payload: { code: "declined" }, metadata: {})
    adapter.write(event_name: "order.created", severity: "info",
                  trace_id: "trace-2", payload: { amount: 99 }, metadata: {})

    expect(query.stored_events.size).to eq(2)
    expect(query.search("payment").size).to eq(1)
    expect(query.events_by_trace("trace-1").size).to eq(1)
    expect(query.stats[:by_severity]["error"]).to eq(1)
  end

  it "interaction grouping works across adapter write and query" do
    t = Time.now
    # Simulate 3 parallel requests within 300ms
    adapter.write(event_name: "e", severity: "info", trace_id: "t1",
                  payload: {}, metadata: { "source" => "web", "started_at" => t.iso8601(3) })
    adapter.write(event_name: "e", severity: "error", trace_id: "t2",
                  payload: {}, metadata: { "source" => "web", "started_at" => (t + 0.2).iso8601(3) })
    adapter.write(event_name: "e", severity: "info", trace_id: "t3",
                  payload: {}, metadata: { "source" => "web", "started_at" => (t + 2.0).iso8601(3) })

    groups = query.interactions(window_ms: 500)
    expect(groups.size).to eq(2)
    expect(groups.first.has_error?).to be false  # newest group (t3) is clean
    expect(groups.last.has_error?).to be true    # older group (t1+t2) has error
  end

  it "rotation keeps keep_rotated files and compresses them" do
    small_adapter = E11y::Adapters::DevLog.new(
      path: path, max_lines: 3, keep_rotated: 2
    )
    10.times { |i| small_adapter.write(event_name: "e#{i}", severity: "info",
                                        trace_id: "t#{i}", payload: {}, metadata: {}) }
    expect(File.exist?("#{path}.1.gz")).to be true
    expect(File.exist?("#{path}.3.gz")).to be false  # beyond keep_rotated: 2
  end
end
```

**Step 2: Run integration tests**

```bash
bundle exec rspec spec/integration/devtools_integration_spec.rb
```

Expected: all green.

**Step 3: Run full test suite to check for regressions**

```bash
rake spec:all
```

Expected: all existing tests still pass, new tests added.

**Step 4: Commit**

```bash
git add spec/integration/devtools_integration_spec.rb
git commit -m "test: add DevTools E2E integration tests"
```

---

### Task 13: Documentation in CLAUDE.md and README

**Files:**
- Modify: `CLAUDE.md` (add e11y-devtools to Architecture section)
- Create: `gems/e11y-devtools/README.md`

**Step 1: Add to CLAUDE.md Architecture table**

Add these rows to the `Key Modules` table in `CLAUDE.md`:

```
| `gems/e11y-devtools/` | Developer tools gem (TUI, Browser Overlay, MCP) |
| `gems/e11y-devtools/lib/e11y/devtools/tui/` | ratatui_ruby TUI — interaction-centric log viewer |
| `gems/e11y-devtools/lib/e11y/devtools/overlay/` | Rails Engine — floating badge + slide-in panel |
| `gems/e11y-devtools/lib/e11y/devtools/mcp/` | MCP Server — AI integration for Cursor/Claude Code |
| `lib/e11y/adapters/dev_log.rb` | DevLog adapter — JSONL write+read, shared by all viewers |
```

Also add commands:

```bash
# Run TUI (interactive log viewer)
bundle exec e11y

# Start MCP server (for Cursor / Claude Code)
bundle exec e11y mcp

# Stream events to stdout (pipe-friendly)
bundle exec e11y tail
```

**Step 2: Create gems/e11y-devtools/README.md**

Write a brief README covering:
1. Installation (`gem 'e11y-devtools', group: :development`)
2. TUI usage (`bundle exec e11y`)
3. Browser Overlay (automatic in dev)
4. MCP Server setup (`.cursor/mcp.json` snippet)
5. Configuration (ENV vars)

**Step 3: Commit**

```bash
git add CLAUDE.md gems/e11y-devtools/README.md
git commit -m "docs: add e11y-devtools to CLAUDE.md and README"
```

---

## Summary

| Phase | Tasks | Key deliverable |
|-------|-------|-----------------|
| P1 | 1–4 | `DevLog` adapter + Railtie |
| P2 | 5–8 | TUI (`bundle exec e11y`) |
| P3 | 9–10 | Browser Overlay (badge + panel) |
| P4 | 11 | MCP Server (`bundle exec e11y mcp`) |
| P5 | 12–13 | Integration tests + docs |

**Test commands at each phase:**

```bash
# P1
bundle exec rspec spec/e11y/adapters/dev_log/

# P2
bundle exec rspec gems/e11y-devtools/spec/tui/

# P3
bundle exec rspec gems/e11y-devtools/spec/overlay/

# P4
bundle exec rspec gems/e11y-devtools/spec/mcp/

# Full suite
rake spec:all
```
