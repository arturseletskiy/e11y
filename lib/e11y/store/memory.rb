# lib/e11y/store/memory.rb
# frozen_string_literal: true

require_relative "base"

module E11y
  module Store
    # In-process store backed by a Hash with TTL.
    #
    # Thread-safe via Mutex. NOT suitable for multi-process environments —
    # each process maintains independent state. Use for:
    # - Tests (no external dependencies)
    # - Single-process applications (Puma single-worker, etc.)
    #
    # For multi-process / multi-pod deployments use Store::RailsCache
    # backed by Redis or Memcached.
    class Memory < Base
      def initialize
        @data = {}
        @mutex = Mutex.new
      end

      def get(key)
        @mutex.synchronize { read_entry(key) }
      end

      def set(key, value, ttl: nil)
        @mutex.synchronize do
          @data[key] = build_entry(value, ttl)
          value
        end
      end

      def increment(key, by: 1, ttl: nil)
        @mutex.synchronize do
          current = read_entry(key).to_i
          new_value = current + by
          @data[key] = build_entry(new_value, ttl)
          new_value
        end
      end

      def set_if_absent(key, value, ttl:)
        @mutex.synchronize do
          return false unless read_entry(key).nil?

          @data[key] = build_entry(value, ttl)
          true
        end
      end

      def delete(key)
        @mutex.synchronize { @data.delete(key) }
      end

      def fetch(key, ttl: nil)
        @mutex.synchronize do
          existing = read_entry(key)
          return existing unless existing.nil?

          new_value = yield
          @data[key] = build_entry(new_value, ttl)
          new_value
        end
      end

      private

      # Must be called inside @mutex.synchronize
      def read_entry(key)
        entry = @data[key]
        return nil unless entry
        return nil if entry[:expires_at] && Time.now > entry[:expires_at]

        entry[:value]
      end

      def build_entry(value, ttl)
        { value: value, expires_at: ttl ? Time.now + ttl.to_f : nil }
      end
    end
  end
end
