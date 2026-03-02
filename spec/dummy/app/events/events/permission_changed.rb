# frozen_string_literal: true

module Events
  class PermissionChanged < E11y::Event::Base
    audit_event true

    schema do
      required(:user_id).filled(:integer)
      required(:permission).filled(:string)
      required(:action).filled(:string)
      required(:granted_by).filled(:integer)
    end

    # Use fallback routing for integration tests
    adapters []
  end
end
