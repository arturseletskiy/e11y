# frozen_string_literal: true

require "zlib"
require "fileutils"

module E11y
  module Adapters
    class DevLog
      # Handles JSONL file I/O with thread-safe append and numbered gzip rotation.
      #
      # Current file is always plain text for fast appends.
      # Rotated files are gzip-compressed to save disk space.
      # Rotation is triggered synchronously on the write that crosses the threshold.
      class FileStore
        DEFAULT_MAX_SIZE = 50 * 1024 * 1024 # 50 MB
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
          @line_count   = nil
          @dir_ensured  = false
        end

        # Append a JSON line to the log file. Thread-safe.
        def append(json_line)
          @mutex.synchronize do
            ensure_dir!
            # Warm the line count before writing so the post-write increment is accurate.
            # If @line_count is nil (cold start or after clear!), scan the file now.
            warm_count = @line_count || count_lines
            ::File.open(@path, "a") do |f|
              f.flock(::File::LOCK_EX)
              begin
                f.write("#{json_line}\n")
              ensure
                f.flock(::File::LOCK_UN)
              end
            end
            @line_count = warm_count + 1
            rotate_if_needed!
          end
        end

        # Remove log file, rotated archives, and reset state.
        def clear!
          @mutex.synchronize do
            ::FileUtils.rm_f(@path)
            ::Dir.glob("#{@path}.*.gz").each { |f| ::FileUtils.rm_f(f) }
            @line_count = nil
            @dir_ensured = false
          end
        end

        # Current file size in bytes (0 if file does not exist).
        def file_size
          ::File.size(@path)
        rescue Errno::ENOENT
          0
        end

        # Number of lines in current file.
        def line_count
          @mutex.synchronize { @line_count || count_lines }
        end

        private

        def ensure_dir!
          return if @dir_ensured

          ::FileUtils.mkdir_p(::File.dirname(@path))
          @dir_ensured = true
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

        def rotate!
          shift_rotated_files!
          compress_current_file!
        end

        def shift_rotated_files!
          @keep_rotated.downto(1) do |n|
            src = rotated_path(n)
            next unless ::File.exist?(src)

            if n + 1 > @keep_rotated
              ::FileUtils.rm_f(src)
            else
              ::File.rename(src, rotated_path(n + 1))
            end
          end
        end

        def compress_current_file!
          return unless ::File.exist?(@path)

          tmp_path = "#{rotated_path(1)}.tmp"
          begin
            ::Zlib::GzipWriter.open(tmp_path) do |gz|
              ::File.open(@path, "rb") { |f| ::IO.copy_stream(f, gz) }
            end
            ::File.rename(tmp_path, rotated_path(1))
          ensure
            ::FileUtils.rm_f(tmp_path)
          end
          # Truncate rather than delete so the file always exists after rotation
          ::File.open(@path, "w") { |f| f.truncate(0) }
        end

        def rotated_path(num)
          "#{@path}.#{num}.gz"
        end

        def count_lines
          return 0 unless ::File.exist?(@path)

          ::File.foreach(@path).count
        end
      end
    end
  end
end
