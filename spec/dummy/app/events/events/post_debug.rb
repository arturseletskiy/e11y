# frozen_string_literal: true

module Events
  # Debug event emitted by PostsController#error action.
  # Used by request_scoped_buffer feature to verify that debug-severity events
  # are buffered during a request and flushed to adapters only when the request fails.
  class PostDebug < E11y::Event::Base
    schema do
      required(:message).filled(:string)
    end

    severity :debug
    adapters []
  end
end
