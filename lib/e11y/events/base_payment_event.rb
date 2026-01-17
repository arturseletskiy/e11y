# frozen_string_literal: true

module E11y
  module Events
    # Base class for payment and high-value events
    #
    # Payment events require special handling:
    # - 100% sampling (never miss a payment)
    # - Unlimited rate limit (never drop payment events)
    # - Multiple adapters (Loki + Sentry for alerting)
    # - High-priority tracking
    #
    # @example Creating a payment event
    #   class PaymentProcessed < E11y::Events::BasePaymentEvent
    #     schema do
    #       required(:payment_id).filled(:integer)
    #       required(:amount).filled(:float)
    #       required(:currency).filled(:string)
    #       required(:user_id).filled(:integer)
    #     end
    #   end
    #
    #   PaymentProcessed.track(
    #     payment_id: 123,
    #     amount: 99.99,
    #     currency: "USD",
    #     user_id: 456
    #   )
    class BasePaymentEvent < E11y::Event::Base
      include E11y::Presets::HighValueEvent
    end
  end
end
