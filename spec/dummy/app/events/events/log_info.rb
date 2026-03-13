# frozen_string_literal: true

module Events
  class LogInfo < E11y::Event::Base
    schema do
      required(:message).filled(:string)
      optional(:level).filled(:string)
    end

    # Use fallback routing for integration tests
    adapters []
  end
end
