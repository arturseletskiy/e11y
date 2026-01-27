# frozen_string_literal: true

module Events
  class UserRegistered < E11y::Event::Base
    schema do
      required(:user_id).filled(:string)
      required(:email).filled(:string)
      required(:password).filled(:string)
      required(:password_confirmation).filled(:string)
      required(:name).filled(:string)
    end
  end
end
