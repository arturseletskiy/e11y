# lib/e11y/store/base.rb
# frozen_string_literal: true

module E11y
  module Store
    # Abstract base class for E11y shared state stores.
    #
    # Implementations must provide atomic #increment and #set_if_absent
    # to support cross-process notification throttling and digest accumulation.
    #
    # All writes MUST accept a ttl: argument (seconds or ActiveSupport::Duration).
    # Keys without TTL may accumulate indefinitely — always pass ttl: in production use.
    class Base
      # @param key [String]
      # @return [Object, nil]
      def get(key)
        raise NotImplementedError
      end

      # @param key [String]
      # @param value [Object]
      # @param ttl [Numeric, nil] expiry in seconds
      # @return [Object] stored value
      def set(key, value, ttl: nil)
        raise NotImplementedError
      end

      # Atomic increment. Initialises to `by` if key absent.
      # @param key [String]
      # @param by [Integer]
      # @param ttl [Numeric, nil] expiry in seconds; applied on initialisation
      # @return [Integer] new value
      def increment(key, by: 1, ttl: nil)
        raise NotImplementedError
      end

      # Write only if key absent (NX semantics).
      # @param key [String]
      # @param value [Object]
      # @param ttl [Numeric] expiry in seconds (required — prevents stale locks)
      # @return [Boolean] true if written, false if already existed
      def set_if_absent(key, value, ttl:)
        raise NotImplementedError
      end

      # @param key [String]
      def delete(key)
        raise NotImplementedError
      end

      # @param key [String]
      # @param ttl [Numeric, nil]
      # @yield default value block, called only when key absent
      # @return [Object]
      def fetch(key, ttl: nil, &block)
        raise NotImplementedError
      end
    end
  end
end
