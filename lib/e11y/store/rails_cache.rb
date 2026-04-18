# lib/e11y/store/rails_cache.rb
# frozen_string_literal: true

require_relative "base"

module E11y
  module Store
    # ActiveSupport::Cache-backed store for cross-process shared state.
    #
    # Delegates to Rails.cache (or an explicitly provided cache store).
    # Supports Redis, Memcached, and other distributed backends.
    #
    # RAISES ArgumentError at initialisation if MemoryStore or NullStore
    # is detected in production/staging — these backends are per-process
    # and would silently break cross-process throttling guarantees.
    #
    # @example Production setup (Redis-backed Rails.cache)
    #   E11y::Adapters::MattermostAdapter.new(
    #     webhook_url: ENV["MATTERMOST_WEBHOOK"],
    #     store: E11y::Store::RailsCache.new
    #   )
    #
    # @example Test setup
    #   store = E11y::Store::RailsCache.new(
    #     cache_store: ActiveSupport::Cache::MemoryStore.new
    #   )
    class RailsCache < Base
      UNSAFE_STORE_CLASSES = %w[
        ActiveSupport::Cache::MemoryStore
        ActiveSupport::Cache::NullStore
      ].freeze

      # @param cache_store [ActiveSupport::Cache::Store, nil] defaults to Rails.cache
      # @param namespace [String] key prefix (default: "e11y")
      def initialize(cache_store: nil, namespace: "e11y")
        super()
        @cache = cache_store || rails_cache
        @namespace = namespace
        validate_cache_store!
      end

      def get(key)
        @cache.read(ns(key))
      end

      def set(key, value, ttl: nil)
        opts = ttl ? { expires_in: ttl.to_f } : {}
        @cache.write(ns(key), value, **opts)
        value
      end

      def increment(key, by: 1, ttl: nil)
        ns_key = ns(key)
        opts = ttl ? { expires_in: ttl.to_f } : {}
        # Initialise to 0 if absent so cache.increment has something to work with.
        # write with unless_exist: true maps to SET NX on Redis (atomic per-command).
        # write + increment together are not a single atomic transaction, but correct:
        # only one process wins the NX init; all subsequent INCRs are atomic on Redis.
        @cache.write(ns_key, 0, unless_exist: true, **opts)
        @cache.increment(ns_key, by) || by
      end

      def set_if_absent(key, value, ttl:)
        @cache.write(ns(key), value, expires_in: ttl.to_f, unless_exist: true)
      end

      def delete(key)
        @cache.delete(ns(key))
      end

      def fetch(key, ttl: nil, &)
        opts = ttl ? { expires_in: ttl.to_f } : {}
        @cache.fetch(ns(key), **opts, &)
      end

      # Exposed as class method for test stubbing
      def self.rails_env
        defined?(Rails) ? Rails.env.to_s : "test"
      end

      private

      def ns(key)
        "#{@namespace}:#{key}"
      end

      def rails_cache
        raise ArgumentError, "[E11y] Store::RailsCache: Rails.cache not available" unless defined?(Rails)

        Rails.cache
      end

      def validate_cache_store!
        return unless unsafe_env?
        return unless unsafe_store?

        raise ArgumentError,
              "[E11y] Store::RailsCache: #{@cache.class} is not suitable for " \
              "#{self.class.rails_env} — it is per-process and will break cross-process " \
              "notification throttling. Configure Rails.cache with Redis or Memcached."
      end

      def unsafe_env?
        %w[production staging].include?(self.class.rails_env)
      end

      def unsafe_store?
        UNSAFE_STORE_CLASSES.include?(@cache.class.name)
      end
    end
  end
end
