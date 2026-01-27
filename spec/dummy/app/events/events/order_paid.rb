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
  end
end
