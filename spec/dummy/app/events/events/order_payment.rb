# frozen_string_literal: true

module Events
  class OrderPayment < E11y::Event::Base
    schema do
      required(:order_id).filled(:string)
      required(:currency).filled(:string)
      required(:payment_method).filled(:string)
      required(:status).filled(:string)
    end

    metrics do
      counter :orders_payment_total, tags: %i[currency payment_method status]
    end
  end
end
