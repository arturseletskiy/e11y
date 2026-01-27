# frozen_string_literal: true

module Events
  class PaymentSubmitted < E11y::Event::Base
    schema do
      required(:payment_id).filled(:string)
      optional(:card_number).maybe(:string)
      optional(:cvv).maybe(:string)
      optional(:amount).maybe(:float)
      optional(:currency).maybe(:string)
      optional(:billing).maybe(:hash)
    end

    contains_pii true

    pii_filtering do
      masks :cvv
      allows :payment_id, :amount, :currency, :card_number, :billing
    end
  end
end
