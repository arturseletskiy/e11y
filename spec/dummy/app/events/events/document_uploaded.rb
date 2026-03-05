# frozen_string_literal: true

module Events
  class DocumentUploaded < E11y::Event::Base
    schema do
      required(:filename).filled(:string)
      required(:size).filled(:integer)
      optional(:metadata).maybe(:hash)
    end

    contains_pii true

    pii_filtering do
      allows :size
      # filename, metadata not in allows - PII patterns (SSN, email) filtered
    end

    # Use fallback routing for integration tests
    adapters []
  end
end
