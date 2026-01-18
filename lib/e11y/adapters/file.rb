# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "zlib"

module E11y
  module Adapters
    # File adapter for writing events to local files with rotation and compression.
    #
    # Features:
    # - JSONL format (one JSON object per line)
    # - Automatic rotation (by size, time, or daily)
    # - Optional gzip compression on rotation
    # - Thread-safe writes
    # - Batch write support
    #
    # @example Basic usage
    #   adapter = E11y::Adapters::File.new(
    #     path: "log/e11y.log",
    #     rotation: :daily,
    #     max_size: 100 * 1024 * 1024, # 100MB
    #     compress: true
    #   )
    #
    #   adapter.write(event_name: "user.login", severity: :info)
    #
    # @example With Registry
    #   E11y::Adapters::Registry.register(
    #     :file_logger,
    #     E11y::Adapters::File.new(path: "log/events.log")
    #   )
    class File < Base
      # Default maximum file size before rotation (100MB)
      DEFAULT_MAX_SIZE = 100 * 1024 * 1024

      # Default rotation strategy
      DEFAULT_ROTATION = :daily

      attr_reader :path, :rotation, :max_size, :compress_on_rotate

      # Initialize File adapter
      #
      # @param config [Hash] Configuration options
      # @option config [String] :path (required) Path to log file
      # @option config [Symbol] :rotation (:daily) Rotation strategy (:daily, :size, :none)
      # @option config [Integer] :max_size (100MB) Max file size before rotation (for :size strategy)
      # @option config [Boolean] :compress (true) Compress rotated files with gzip
      def initialize(config = {})
        @path = config[:path]
        @rotation = config.fetch(:rotation, DEFAULT_ROTATION)
        @max_size = config.fetch(:max_size, DEFAULT_MAX_SIZE)
        @compress_on_rotate = config.fetch(:compress, true)
        @file = nil
        @mutex = Mutex.new
        @current_date = nil

        super(config)

        ensure_directory!
        open_file!
      end

      # Write a single event to file
      #
      # @param event_data [Hash] Event payload
      # @return [Boolean] Success status
      def write(event_data)
        @mutex.synchronize do
          rotate_if_needed!

          line = format_event(event_data)
          @file.puts(line)
          @file.flush
        end

        true
      rescue StandardError => e
        warn "E11y File adapter error: #{e.message}"
        false
      end

      # Write a batch of events to file
      #
      # @param events [Array<Hash>] Array of event payloads
      # @return [Boolean] Success status
      def write_batch(events)
        @mutex.synchronize do
          rotate_if_needed!

          events.each do |event_data|
            line = format_event(event_data)
            @file.puts(line)
          end

          @file.flush
        end

        true
      rescue StandardError => e
        warn "E11y File adapter batch error: #{e.message}"
        false
      end

      # Close the file handle
      def close
        @mutex.synchronize do
          @file&.close
          @file = nil
        end
      end

      # Check if adapter is healthy
      #
      # @return [Boolean] True if file is writable
      def healthy?
        @mutex.synchronize do
          return false unless @file

          !@file.closed?
        end
      end

      # Adapter capabilities
      #
      # @return [Hash] Capability flags
      def capabilities
        super.merge(
          batching: true,
          compression: @compress_on_rotate,
          streaming: true
        )
      end

      private

      # Validate configuration
      def validate_config!
        raise ArgumentError, "File adapter requires :path" unless @path
        raise ArgumentError, "Invalid rotation: #{@rotation}" unless %i[daily size none].include?(@rotation)
        raise ArgumentError, "max_size must be positive" if @max_size && @max_size <= 0
      end

      # Ensure directory exists
      def ensure_directory!
        dir = ::File.dirname(@path)
        FileUtils.mkdir_p(dir) unless ::File.directory?(dir)
      end

      # Open file for writing
      def open_file!
        @file = ::File.open(@path, "a")
        @file.sync = true
        @current_date = Date.today if @rotation == :daily
      end

      # Format event as JSONL
      #
      # @param event_data [Hash] Event payload
      # @return [String] JSON string
      def format_event(event_data)
        event_data.to_json
      end

      # Check if rotation is needed and perform it
      def rotate_if_needed!
        case @rotation
        when :daily
          rotate_daily!
        when :size
          rotate_by_size!
        end
      end

      # Rotate file if date changed
      def rotate_daily!
        today = Date.today
        return unless @current_date && today != @current_date

        perform_rotation!
        @current_date = today
      end

      # Rotate file if size exceeded
      def rotate_by_size!
        return unless @file.size >= @max_size

        perform_rotation!
      end

      # Perform actual file rotation
      def perform_rotation!
        @file.close if @file

        timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
        rotated_path = "#{@path}.#{timestamp}"

        ::File.rename(@path, rotated_path) if ::File.exist?(@path)

        compress_file(rotated_path) if @compress_on_rotate

        open_file!
      end

      # Compress rotated file with gzip
      #
      # @param file_path [String] Path to file to compress
      def compress_file(file_path)
        return unless ::File.exist?(file_path)

        Zlib::GzipWriter.open("#{file_path}.gz") do |gz|
          ::File.open(file_path, "rb") do |file|
            gz.write(file.read)
          end
        end

        ::File.delete(file_path)
      rescue StandardError => e
        warn "E11y File adapter compression error: #{e.message}"
      end
    end
  end
end
