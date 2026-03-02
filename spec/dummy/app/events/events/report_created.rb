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
      allows :title, :description, :employee_ids, :author
    end
  end

    # Use fallback routing for integration tests
    adapters []
end
