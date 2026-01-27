# frozen_string_literal: true

module Events
  class ApiRequest < E11y::Event::Base
    schema do
      required(:endpoint).filled(:string)
      required(:status).filled(:string)
      optional(:http_status).maybe(:integer)
    end

    metrics do
      counter :api_requests_total, tags: %i[endpoint status]
    end
  end
end
