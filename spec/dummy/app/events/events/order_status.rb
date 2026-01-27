# frozen_string_literal: true

module Events
  class OrderStatus < E11y::Event::Base
    schema do
      required(:order_id).filled(:string)
      required(:status).filled(:string)
    end

    metrics do
      gauge :order_status, value: :status, tags: [:order_id]
    end
  end
end
