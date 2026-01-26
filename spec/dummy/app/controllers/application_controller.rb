# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Disable CSRF for test simplicity
  protect_from_forgery with: :null_session
end
