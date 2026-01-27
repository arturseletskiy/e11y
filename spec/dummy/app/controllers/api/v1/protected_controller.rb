# frozen_string_literal: true

module Api
  module V1
    # Test controller for header filtering
    class ProtectedController < ApplicationController
      before_action :authenticate!

      def index
        Events::ProtectedRequest.track(
          authorization: request.headers["Authorization"],
          api_key: request.headers["X-API-Key"],
          user_agent: request.headers["User-Agent"]
        )

        render json: { data: "protected resource", user: "authenticated_user" }
      end

      private

      def authenticate!
        token = request.headers["Authorization"]&.remove("Bearer ")
        head :unauthorized unless token == "valid_token_123"
      end
    end
  end
end
