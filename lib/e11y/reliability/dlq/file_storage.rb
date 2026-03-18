# frozen_string_literal: true

require "json"
require "fileutils"
require "securerandom"

module E11y
  module Reliability
    module DLQ
      # File-based Dead Letter Queue storage.
      #
      # Stores failed events to a JSONL file for later analysis/replay.
      # Each line is a JSON object representing a failed event with metadata.
      #
      # @example Usage
      #   dlq = FileStorage.new(file_path: "log/e11y_dlq.jsonl")
      #   dlq.save(event_data, metadata: { error: "Timeout", retry_count: 3 })
      #
      # @see ADR-013 §4 (Dead Letter Queue)
      # @see UC-021 §3 (DLQ File Storage)
      # rubocop:disable Metrics/ClassLength
      # DLQ file storage is a cohesive unit handling event persistence, rotation, and querying
      class FileStorage
        # @param file_path [String] Path to DLQ file (default: log/e11y_dlq.jsonl)
        # @param max_file_size_mb [Integer] Maximum file size in MB before rotation (default: 100)
        # @param retention_days [Integer] Days to retain DLQ files (default: 30)
        def initialize(file_path: nil, max_file_size_mb: 100, retention_days: 30)
          @file_path = file_path || default_file_path
          @max_file_size_bytes = max_file_size_mb * 1024 * 1024
          @retention_days = retention_days
          @mutex = Mutex.new

          ensure_directory_exists
        end

        # Save failed event to DLQ.
        #
        # @param event_data [Hash] Event data
        # @param metadata [Hash] Failure metadata (error, retry_count, adapter, etc.)
        # @return [String] Event ID (UUID)
        # DLQ save requires building entry, writing, rotation, cleanup, and metrics
        def save(event_data, metadata: {})
          event_id = SecureRandom.uuid
          timestamp = Time.now.utc

          dlq_entry = {
            id: event_id,
            timestamp: timestamp.iso8601(3),
            event_name: event_data[:event_name],
            event_data: event_data,
            metadata: metadata.merge(
              failed_at: timestamp.iso8601(3),
              retry_count: metadata[:retry_count] || 0,
              error_message: metadata[:error]&.message,
              error_class: metadata[:error]&.class&.name
            )
          }

          write_entry(dlq_entry)
          rotate_if_needed
          cleanup_old_files

          E11y::Metrics.increment("e11y.dlq.saved", event_name: event_data[:event_name])
          update_dlq_size_gauge

          event_id
        end

        # List DLQ entries with optional filters.
        #
        # @param limit [Integer] Maximum entries to return
        # @param offset [Integer] Number of entries to skip
        # @param filters [Hash] Filter options (event_name, after, before)
        # @return [Array<Hash>] Array of DLQ entries
        # rubocop:disable Metrics/AbcSize
        # DLQ listing requires file iteration, pagination, multiple filters, and error handling
        def list(limit: 100, offset: 0, filters: {})
          entries = []

          return entries unless File.exist?(@file_path)

          File.foreach(@file_path).with_index do |line, index|
            next if index < offset
            break if entries.size >= limit

            entry = JSON.parse(line, symbolize_names: true)

            # Apply filters
            next if filters[:event_name] && entry[:event_name] != filters[:event_name]
            next if filters[:after] && Time.parse(entry[:timestamp]) < filters[:after]
            next if filters[:before] && Time.parse(entry[:timestamp]) > filters[:before]

            entries << entry
          end

          entries
        rescue JSON::ParserError => e
          # Log parsing error but don't crash
          E11y::Metrics.increment("e11y.dlq.parse_error", error: e.class.name)
          entries
        end
        # rubocop:enable Metrics/AbcSize

        # Get DLQ statistics.
        #
        # @return [Hash] Statistics (total_entries, file_size_mb, oldest_entry, newest_entry)
        # DLQ stats requires reading file size, counting entries, extracting timestamps, and error handling
        def stats
          return default_stats unless File.exist?(@file_path)

          file_size_bytes = File.size(@file_path)
          total_entries = File.foreach(@file_path).count

          oldest_entry = nil
          newest_entry = nil

          # Read first and last line for oldest/newest timestamps
          File.foreach(@file_path).with_index do |line, index|
            entry = JSON.parse(line, symbolize_names: true)
            oldest_entry = entry[:timestamp] if index.zero?
            newest_entry = entry[:timestamp]
          end

          {
            total_entries: total_entries,
            file_size_mb: (file_size_bytes / 1024.0 / 1024.0).round(2),
            oldest_entry: oldest_entry,
            newest_entry: newest_entry,
            file_path: @file_path
          }
        rescue StandardError
          default_stats
        end

        # Replay single event from DLQ.
        #
        # Re-dispatches event through E11y pipeline so it reaches adapters.
        #
        # @param event_id [String] Event ID to replay
        # @return [Boolean] true if replayed successfully
        def replay(event_id)
          entry = find_entry(event_id)
          return false unless entry

          event_data = entry[:event_data]
          return false unless event_data

          # F-004/C07: Mark as DLQ-replayed so PIIFilter skips (avoid double-hashing)
          event_data = event_data.dup
          event_data[:dlq_replayed] = true

          E11y.config.built_pipeline.call(event_data)
          E11y::Metrics.increment("e11y.dlq.replayed", event_name: entry[:event_name])
          true
        rescue StandardError => e
          E11y::Metrics.increment("e11y.dlq.replay_failed", error: e.class.name)
          false
        end

        # Replay batch of events from DLQ.
        #
        # @param event_ids [Array<String>] Event IDs to replay
        # @return [Hash] Result summary (success_count, failure_count)
        def replay_batch(event_ids)
          success_count = 0
          failure_count = 0

          event_ids.each do |event_id|
            if replay(event_id)
              success_count += 1
            else
              failure_count += 1
            end
          end

          { success_count: success_count, failure_count: failure_count }
        end

        # Delete entry from DLQ.
        #
        # Rewrites file excluding the entry. For large files this is expensive.
        #
        # @param event_id [String] Event ID to delete
        # @return [Boolean] true if deleted
        # delete is an action method returning boolean status, not a predicate query
        def delete(event_id)
          return false unless File.exist?(@file_path)

          entries, found = read_entries_excluding(event_id)
          return false unless found

          rewrite_file_with(entries)
          update_dlq_size_gauge
          true
        rescue StandardError
          false
        end

        private

        def update_dlq_size_gauge
          return unless defined?(E11y::Metrics) && E11y::Metrics.respond_to?(:gauge)

          count = stats[:total_entries]
          E11y::Metrics.gauge(:e11y_dlq_size, count)
        rescue StandardError
          # Non-fatal: gauge update must not break DLQ operations
        end

        def read_entries_excluding(event_id)
          entries = []
          found = false
          File.foreach(@file_path) do |line|
            entry = JSON.parse(line, symbolize_names: true)
            if entry[:id] == event_id
              found = true
            else
              entries << entry
            end
          end
          [entries, found]
        end

        def rewrite_file_with(entries)
          @mutex.synchronize do
            File.open(@file_path, "w") do |f|
              f.flock(File::LOCK_EX)
              entries.each { |e| f.puts(JSON.generate(e)) }
            end
          end
        end

        # Get default file path (log/e11y_dlq.jsonl).
        def default_file_path
          ::Rails.root.join("log", "e11y_dlq.jsonl").to_s
        end

        # Ensure log directory exists.
        def ensure_directory_exists
          dir = File.dirname(@file_path)
          FileUtils.mkdir_p(dir)
        end

        # Write DLQ entry to file (thread-safe).
        def write_entry(entry)
          @mutex.synchronize do
            File.open(@file_path, "a") do |f|
              f.flock(File::LOCK_EX)
              f.puts(JSON.generate(entry))
            end
          end
        end

        # Rotate file if size exceeds max_file_size.
        def rotate_if_needed
          return unless File.exist?(@file_path)
          return if File.size(@file_path) < @max_file_size_bytes

          @mutex.synchronize do
            # Rotate: log/e11y_dlq.jsonl → log/e11y_dlq.2026-01-20T12:34:56Z.jsonl
            timestamp = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
            rotated_path = @file_path.sub(/\.jsonl$/, ".#{timestamp}.jsonl")

            FileUtils.mv(@file_path, rotated_path)
          end
        end

        # Cleanup old rotated files.
        def cleanup_old_files
          dir = File.dirname(@file_path)
          base_name = File.basename(@file_path, ".jsonl")

          # Find all rotated files: e11y_dlq.*.jsonl
          pattern = File.join(dir, "#{base_name}.*.jsonl")

          Dir.glob(pattern).each do |file|
            next unless File.file?(file)

            file_age_days = (Time.now - File.mtime(file)) / 86_400

            File.delete(file) if file_age_days > @retention_days
          end
        end

        # Find DLQ entry by ID.
        def find_entry(event_id)
          return nil unless File.exist?(@file_path)

          File.foreach(@file_path) do |line|
            entry = JSON.parse(line, symbolize_names: true)
            return entry if entry[:id] == event_id
          end

          nil
        rescue JSON::ParserError
          nil
        end

        # Default stats when file doesn't exist.
        def default_stats
          {
            total_entries: 0,
            file_size_mb: 0.0,
            oldest_entry: nil,
            newest_entry: nil,
            file_path: @file_path
          }
        end

        # Increment DLQ metric.
        #
        # Normalizes metric_name like "e11y.dlq.saved" to :e11y_dlq_saved_total.
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
