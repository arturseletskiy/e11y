# frozen_string_literal: true

# Re-enable E11y for integration tests.
# Railtie sets config.enabled = false in test by default; this runs after
# before_initialize and restores enabled = true for the dummy app.
E11y.configure { |c| c.enabled = true } if Rails.env.test? && ENV["INTEGRATION"] == "true"
