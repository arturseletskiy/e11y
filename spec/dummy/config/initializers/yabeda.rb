# frozen_string_literal: true

# Initialize Yabeda for integration tests
# This ensures the :e11y group is available for metrics registration (Yabeda.e11y)
# Must create group BEFORE configure! — once configured, config is frozen

return unless defined?(Yabeda)

unless Yabeda.configured?
  Yabeda.configure do
    group :e11y do
      # Empty — SLO, pattern metrics, etc. register their own metrics
    end
  end
  Yabeda.configure!
end
