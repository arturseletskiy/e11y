# frozen_string_literal: true

module E11y
  module Event
    # Base class for all E11y events
    #
    # @abstract Subclass and define schema using {.schema}
    #
    # @example Define custom event
    #   class UserSignupEvent < E11y::Event::Base
    #     schema do
    #       required(:user_id).filled(:integer)
    #       required(:email).filled(:string)
    #     end
    #
    #     pii_fields :email
    #     adapters :loki, :sentry
    #   end
    class Base
      # TODO: Implement in Phase 1 (ADR-001)
      def initialize(**_attributes)
        raise NotImplementedError, "E11y::Event::Base will be implemented in Phase 1"
      end
    end
  end
end
