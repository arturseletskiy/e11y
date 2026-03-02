# frozen_string_literal: true

module Events
  class OrderAmount < E11y::Event::Base
    schema do
      required(:order_id).filled(:string)
      required(:amount).filled(:float)
      required(:currency).filled(:string)
    end

    metrics do
      histogram :orders_amount, value: :amount, tags: [:currency], buckets: [10, 50, 100, 500, 1000]
    end

    # Use fallback routing for integration tests
    adapters []
  end
end
