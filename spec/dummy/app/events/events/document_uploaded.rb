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
      allows :filename, :size, :metadata
    end

    # Use fallback routing for integration tests
    adapters []
  end
end
