# frozen_string_literal: true

module Events
  class TestEvent < E11y::Event::Base
    schema do
      required(:message).filled(:string)
    end
  end
end
