# frozen_string_literal: true

require_relative "file_adapter"

module E11y
  module Reliability
    module DLQ
      # @deprecated Use {DLQ::FileAdapter} instead.
      FileStorage = FileAdapter
    end
  end
end
