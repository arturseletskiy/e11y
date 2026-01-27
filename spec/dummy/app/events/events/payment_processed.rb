# frozen_string_literal: true

module Events
  class PaymentProcessed < E11y::Event::Base
    schema do
      required(:payment_id).filled(:string)
      required(:status).filled(:string)
    end

    metrics do
      counter :payments_total, tags: [:status]
    end
  end
end
