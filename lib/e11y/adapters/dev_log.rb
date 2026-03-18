# frozen_string_literal: true

module E11y
  module Adapters
    # DevLog adapter: writes events as JSONL to a local file during development.
    # Full adapter implementation lives in dev_log/*.rb files loaded by Zeitwerk.
    class DevLog # rubocop:disable Lint/EmptyClass
    end
  end
end
