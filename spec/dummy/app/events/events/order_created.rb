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

    slo do
      enabled true
      contributes_to "order_creation_success_rate"
      slo_status_from do |payload|
        case payload[:status].to_s
        when "failed", "cancelled" then "failure"
        when "pending", "completed" then "success"
        else "success" # default for SLO cucumber scenario
        end
      end
    end

    metrics do
      counter :orders_total, tags: [:status]
    end

    # Use fallback routing for integration tests
    adapters []
  end
end
