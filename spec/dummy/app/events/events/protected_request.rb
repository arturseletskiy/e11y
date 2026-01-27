# frozen_string_literal: true

module Events
  class ProtectedRequest < E11y::Event::Base
    schema do
      optional(:authorization).maybe(:string)
      optional(:api_key).maybe(:string)
      optional(:user_agent).maybe(:string)
    end
  end
end
