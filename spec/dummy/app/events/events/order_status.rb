# frozen_string_literal: true

module Events
  class OrderStatus < E11y::Event::Base
    schema do
      required(:order_type).filled(:string) # Changed from order_id to avoid UNIVERSAL_DENYLIST
      required(:status_code).filled(:integer) # Gauge requires numeric value
    end

    metrics do
      gauge :order_status, value: :status_code, tags: [:order_type]
    end
  end
end
