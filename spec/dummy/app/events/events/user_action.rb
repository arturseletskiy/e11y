# frozen_string_literal: true

module Events
  class UserAction < E11y::Event::Base
    schema do
      required(:user_id).filled(:string)
      required(:action).filled(:string)
    end

    metrics do
      counter :user_actions_total, tags: [:action]
    end
  end
end
