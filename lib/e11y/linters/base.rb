# frozen_string_literal: true

module E11y
  module Linters
    # Namespace for linter base infrastructure (satisfies Zeitwerk for base.rb).
    module Base
    end

    class LinterError < StandardError; end
  end
end
