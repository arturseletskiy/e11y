# frozen_string_literal: true

module Events
  # Error event emitted by PostsController#error action.
  # Used by request_scoped_buffer feature to verify that error-severity events
  # bypass the buffer and are written to adapters immediately.
  class PostError < E11y::Event::Base
    schema do
      required(:message).filled(:string)
      optional(:error_class).maybe(:string)
    end

    severity :error
    adapters []
  end
end
