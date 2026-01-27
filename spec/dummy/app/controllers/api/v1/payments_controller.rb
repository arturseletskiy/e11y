# frozen_string_literal: true

module Api
  module V1
    # Test controller for JSON API PII filtering
    class PaymentsController < ApplicationController
      def create
        payment_id = SecureRandom.uuid
        payment_params = params[:payment]&.to_unsafe_h || {}

        Events::PaymentSubmitted.track(
          payment_id: payment_id,
          **payment_params
        )

        render json: { payment_id: payment_id, status: "processing" }, status: :created
      end
    end
  end
end
