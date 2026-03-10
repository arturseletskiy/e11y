# frozen_string_literal: true

# Initialize Yabeda for integration tests
# This ensures the :e11y group is available for metrics registration

return unless defined?(Yabeda)

# Configure Yabeda once (Railtie will handle this in real Rails apps)
# In tests, we need to configure it manually before any metrics are registered
Yabeda.configure! unless Yabeda.configured?
