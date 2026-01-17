# frozen_string_literal: true

module E11y
  # Base event classes for common patterns
  #
  # These classes provide pre-configured base classes for typical event types.
  # Users can inherit from these instead of E11y::Event::Base for less boilerplate.
  #
  # @example Using a base event class
  #   class UserLoginAudit < E11y::Events::BaseAuditEvent
  #     schema do
  #       required(:user_id).filled(:integer)
  #       required(:ip_address).filled(:string)
  #     end
  #   end
  module Events
  end
end
