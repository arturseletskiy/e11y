# frozen_string_literal: true

require "rails/railtie"

module E11y
  # Rails integration for E11y
  #
  # Provides automatic initialization and boot-time validation for Rails applications.
  #
  # @example Automatic initialization
  #   # config/application.rb
  #   # E11y::Railtie is loaded automatically when Rails is present
  #
  # @example Manual validation
  #   # Validate all metrics after loading
  #   E11y::Metrics::Registry.instance.validate_all!
  class Railtie < Rails::Railtie
    # Initialize E11y after Rails loads all application code
    #
    # This ensures all Event classes are loaded and metrics are registered
    # before we validate the configuration.
    initializer "e11y.validate_metrics", after: :load_config_initializers do
      # Validate metrics configuration at boot time
      # This catches label/type conflicts before the app starts
      Rails.application.config.after_initialize do
        if defined?(E11y::Metrics::Registry)
          E11y::Metrics::Registry.instance.validate_all!
          Rails.logger.info "E11y: Metrics validated successfully (#{E11y::Metrics::Registry.instance.size} metrics)"
        end
      end
    end

    # Add E11y to Rails logger tagged logging
    initializer "e11y.logger" do
      E11y.configure do |config|
        config.logger = Rails.logger if config.logger.nil?
      end
    end
  end
end
