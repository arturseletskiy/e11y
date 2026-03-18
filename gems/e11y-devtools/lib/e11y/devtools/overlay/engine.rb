# frozen_string_literal: true

require "rails"

module E11y
  module Devtools
    module Overlay
      # Rails Engine that mounts JSON endpoints at /_e11y/
      # and injects the overlay badge via Rack middleware.
      class Engine < Rails::Engine
        isolate_namespace E11y::Devtools::Overlay

        initializer "e11y_devtools.overlay.middleware" do |app|
          next unless Rails.env.development? || Rails.env.test?

          require "e11y/devtools/overlay/middleware"
          app.middleware.use E11y::Devtools::Overlay::Middleware
        end

        config.generators do |g|
          g.test_framework :rspec
        end
      end
    end
  end
end
