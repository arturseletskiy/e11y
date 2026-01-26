# frozen_string_literal: true

require "rails_helper"

RSpec.describe "E11y Eager Loading", :integration do
  # This test ensures E11y works correctly with eager_load = true (production mode)
  # Many autoloading issues only appear when all files are loaded upfront

  it "loads all E11y files without errors when eager_load is enabled" do # rubocop:disable RSpec/MultipleExpectations
    # Verify E11y is properly loaded
    expect(defined?(E11y::Railtie)).to be_truthy
    expect(defined?(E11y::Middleware::Request)).to be_truthy
    expect(defined?(E11y::Instruments::ActiveJob)).to be_truthy
    expect(defined?(E11y::Instruments::RailsInstrumentation)).to be_truthy

    # Verify all adapters are loadable
    expect(defined?(E11y::Adapters::InMemory)).to be_truthy
    expect(defined?(E11y::Adapters::Stdout)).to be_truthy
    expect(defined?(E11y::Adapters::File)).to be_truthy

    # Verify all middleware classes are loadable
    expect(defined?(E11y::Middleware::Base)).to be_truthy
    expect(defined?(E11y::Middleware::Request)).to be_truthy
    expect(defined?(E11y::Middleware::TraceContext)).to be_truthy
    expect(defined?(E11y::Middleware::Sampling)).to be_truthy

    # Verify all event classes are loadable
    expect(defined?(E11y::Event::Base)).to be_truthy
    expect(defined?(E11y::Events::BaseAuditEvent)).to be_truthy

    # Verify pipeline components
    expect(defined?(E11y::Pipeline::Builder)).to be_truthy
    expect(defined?(E11y::Buffers::AdaptiveBuffer)).to be_truthy

    # Verify metrics components
    expect(defined?(E11y::Metrics::Registry)).to be_truthy
    expect(defined?(E11y::Metrics::CardinalityProtection)).to be_truthy
  end

  it "eager loads E11y gem files directly" do
    # Test that we can eager load E11y's own files
    e11y_lib_path = File.expand_path("../../lib", __dir__)

    # Find all Ruby files in lib/e11y
    ruby_files = Dir.glob(File.join(e11y_lib_path, "e11y/**/*.rb"))

    expect(ruby_files).not_to be_empty

    # Try to require each file
    errors = []
    ruby_files.each do |file|
      # Skip railtie if Rails not loaded
      next if file.include?("railtie.rb") && !defined?(Rails)

      # Get relative require path
      require_path = file.sub("#{e11y_lib_path}/", "").sub(".rb", "")
      require require_path
    rescue StandardError => e
      errors << "#{file}: #{e.class} - #{e.message}"
    end

    expect(errors).to be_empty, "Failed to load files:\n#{errors.join("\n")}"
  end

  it "works with Rails.application.eager_load! in test environment" do
    # Ensure current dummy app can eager load
    expect { Rails.application.eager_load! }.not_to raise_error

    # Verify E11y components are loaded
    expect(defined?(E11y::Railtie)).to be_truthy
    expect(E11y.config.enabled).to be true
  end
end
