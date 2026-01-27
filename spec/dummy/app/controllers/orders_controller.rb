# frozen_string_literal: true

# Test controller for nested params filtering
class OrdersController < ApplicationController
  def create
    order_params = params[:order]&.to_unsafe_h || {}

    Events::OrderCreated.track(**order_params)

    render json: { order_id: SecureRandom.uuid, status: "created" }, status: :created
  end
end
