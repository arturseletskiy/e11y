# frozen_string_literal: true

# Test controller for PII filtering integration
class UsersController < ApplicationController
  def create
    user_id = SecureRandom.uuid
    user_params = params.require(:user).permit(:email, :password, :password_confirmation, :name)

    Events::UserRegistered.track(
      user_id: user_id,
      email: user_params[:email],
      password: user_params[:password],
      password_confirmation: user_params[:password_confirmation],
      name: user_params[:name]
    )

    render json: { status: "created", user_id: user_id }, status: :created
  end
end
