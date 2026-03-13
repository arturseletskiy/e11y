# frozen_string_literal: true

module Events
  class PaymentFailed < E11y::Event::Base
    schema do
      required(:order_id).filled(:string)
      required(:amount).filled(:float)
    end

    # Use fallback routing for integration tests
    adapters []
  end
end
