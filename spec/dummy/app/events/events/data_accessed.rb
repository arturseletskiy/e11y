# frozen_string_literal: true

module Events
  class DataAccessed < E11y::Event::Base
    audit_event true

    schema do
      required(:patient_id).filled(:integer)
      required(:accessed_by).filled(:integer)
      required(:access_type).filled(:string)
    end
  end
end
