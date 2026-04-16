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
      # Sentinel returned by read_entry when the key is absent or expired.
      # Allows storing nil/false as real values.
      MISSING = Object.new.freeze

      def initialize
        super
        @data = {}
        @mutex = Mutex.new
      end

      def get(key)
        @mutex.synchronize do
          result = read_entry(key)
          result.equal?(MISSING) ? nil : result
        end
      end

      def set(key, value, ttl: nil)
        @mutex.synchronize do
          @data[key] = build_entry(value, ttl)
          value
        end
      end

      def increment(key, by: 1, ttl: nil)
        @mutex.synchronize do
          entry   = @data[key]
          expired = entry && entry[:expires_at] && Time.now > entry[:expires_at]
          if entry.nil? || expired
            new_value = by
            @data[key] = build_entry(new_value, ttl)
          else
            new_value = entry[:value].to_i + by
            @data[key] = { value: new_value, expires_at: entry[:expires_at] }
          end
          new_value
        end
      end

      def set_if_absent(key, value, ttl:)
        @mutex.synchronize do
          return false unless read_entry(key).equal?(MISSING)

          @data[key] = build_entry(value, ttl)
          true
        end
      end

      def delete(key)
        @mutex.synchronize { @data.delete(key) }
      end

      def fetch(key, ttl: nil, &_block)
        @mutex.synchronize do
          existing = read_entry(key)
          return existing unless existing.equal?(MISSING)

          new_value = yield
          @data[key] = build_entry(new_value, ttl)
          new_value
        end
      end

      private

      # Must be called inside @mutex.synchronize.
      # Returns MISSING when the key is absent or expired.
      def read_entry(key)
        entry = @data[key]
        return MISSING unless entry
        return MISSING if entry[:expires_at] && Time.now > entry[:expires_at]

        entry[:value]
      end

      def build_entry(value, ttl)
        { value: value, expires_at: ttl ? Time.now + ttl.to_f : nil }
      end
    end
  end
end
