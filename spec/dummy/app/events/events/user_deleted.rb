# frozen_string_literal: true

module Events
  class UserDeleted < E11y::Event::Base
    audit_event true

    schema do
      required(:user_id).filled(:integer)
      required(:deleted_by).filled(:integer)
      required(:ip_address).filled(:string)
    end

    # Use fallback routing for integration tests
    adapters []
  end
end
