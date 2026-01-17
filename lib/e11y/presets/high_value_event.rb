# frozen_string_literal: true

module E11y
  module Presets
    # Preset for high-value events (payments, transactions)
    #
    # High-value events require:
    # - High priority (success severity)
    # - Unlimited rate limit (never drop payment events)
    # - 100% sampling (all payment events)
    # - Multiple adapters (logs + errors_tracker for full observability)
    #
    # Adapter names:
    # - :logs → centralized logging (implementation: Loki, Elasticsearch, CloudWatch, etc.)
    # - :errors_tracker → error tracking with alerting (implementation: Sentry, Rollbar, Bugsnag, etc.)
    #
    # @example
    #   class PaymentProcessedEvent < E11y::Event::Base
    #     include E11y::Presets::HighValueEvent
    #
    #     schema do
    #       required(:payment_id).filled(:integer)
    #       required(:amount).filled(:float)
    #     end
    #   end
    module HighValueEvent
      def self.included(base)
        base.class_eval do
          severity :success
          adapters :logs, :errors_tracker # Adapter names
        end

        # Extend class with overridden methods
        base.extend(ClassMethods)
      end

      # Class methods that override default behavior
      module ClassMethods
        # Override resolve_rate_limit to unlimited for high-value events
        def resolve_rate_limit
          nil # Unlimited - never drop payment events
        end

        # Override resolve_sample_rate to 100% for high-value events
        def resolve_sample_rate
          1.0 # 100% - track all payment events
        end
      end
    end
  end
end
