# frozen_string_literal: true

module E11y
  # Presets for common event patterns
  #
  # Presets are modules that can be included in event classes to provide
  # pre-configured settings (severity, adapters, sample rate, etc.)
  #
  # @example Using a preset
  #   class MyDebugEvent < E11y::Event::Base
  #     include E11y::Presets::DebugEvent
  #
  #     schema do
  #       required(:debug_info).filled(:string)
  #     end
  #   end
  module Presets
  end
end
