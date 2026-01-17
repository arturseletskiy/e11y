# frozen_string_literal: true

module E11y
  module Presets
    # Preset for debug events (development/troubleshooting)
    #
    # Debug events have:
    # - Low priority (debug severity)
    # - Standard rate limit (1000/sec)
    # - Low sampling (1% - reduces noise)
    # - Only logs adapter (no error tracking/alerting)
    #
    # Adapter name:
    # - :logs → centralized logging (implementation: Loki, Elasticsearch, CloudWatch, etc.)
    #
    # @example
    #   class DebugCacheHitEvent < E11y::Event::Base
    #     include E11y::Presets::DebugEvent
    #
    #     schema do
    #       required(:cache_key).filled(:string)
    #       required(:hit).filled(:bool)
    #     end
    #   end
    module DebugEvent
      def self.included(base)
        base.class_eval do
          severity :debug
          adapters :logs # Adapter name
        end
      end
    end
  end
end
