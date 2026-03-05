# frozen_string_literal: true

module Events
  class ReportCreated < E11y::Event::Base
    schema do
      optional(:title).maybe(:string)
      optional(:description).maybe(:string)
      optional(:employee_ids).maybe(:array)
      optional(:author).maybe(:string)
    end

    contains_pii true

    pii_filtering do
      allows :title, :employee_ids
      # description, author not in allows - PII patterns (email, phone) filtered in free text
    end

    # Use fallback routing for integration tests
    adapters []
  end
end
