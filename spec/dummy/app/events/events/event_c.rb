# frozen_string_literal: true

module Events
  class EventC < E11y::Event::Base
    schema do
      required(:data).filled(:string)
    end

    # Use fallback routing for integration tests
    adapters []
  end
end
