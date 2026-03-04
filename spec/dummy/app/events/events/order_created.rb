# frozen_string_literal: true

module Events
  class OrderCreated < E11y::Event::Base
    schema do
      optional(:order_id).maybe(:string)
      optional(:status).maybe(:string)
      optional(:customer).maybe(:hash)
      optional(:payment).maybe(:hash)
      optional(:items).maybe(:array)
    end

    contains_pii true

    pii_filtering do
      allows :customer, :payment, :items
    end

    metrics do
      counter :orders_total, tags: [:status]
    end

    slo do
      enabled true
      slo_status_from do |payload|
        case payload[:status]
        when "pending", "completed" then "success"
        when "failed", "cancelled" then "failure"
        else "success"
        end
      end
    end

    # Use fallback routing for integration tests
    adapters []
  end
end
