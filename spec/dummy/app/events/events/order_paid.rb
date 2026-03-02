# frozen_string_literal: true

module Events
  class OrderPaid < E11y::Event::Base
    schema do
      required(:order_id).filled(:string)
      required(:currency).filled(:string)
    end

    metrics do
      counter :orders_paid_total, tags: [:currency]
    end

    # Return empty adapters array to force fallback routing
    # This allows integration tests to control routing via fallback_adapters config
    adapters []
  end
end
