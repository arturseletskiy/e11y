# frozen_string_literal: true

# See https://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration

# SimpleCov setup (must be at the very top)
if ENV["COVERAGE"]
  require "simplecov"
  require "simplecov-cobertura"

  SimpleCov.start do
    add_filter "/spec/"
    add_filter "/vendor/"
    add_filter "/benchmarks/"

    # Coverage groups
    add_group "Core", "lib/e11y"
    add_group "Events", "lib/e11y/events"
    add_group "Buffers", "lib/e11y/buffers"
    add_group "Middleware", "lib/e11y/middleware"
    add_group "Adapters", "lib/e11y/adapters"

    # Minimum coverage requirement
    minimum_coverage 100
    refuse_coverage_drop

    # Multiple formatters
    formatter SimpleCov::Formatter::MultiFormatter.new([
                                                         SimpleCov::Formatter::HTMLFormatter,
                                                         SimpleCov::Formatter::CoberturaFormatter
                                                       ])
  end
end

require "active_support/core_ext/numeric/time" # For 30.days, 7.years
require "active_support/core_ext/integer/time"
require "active_support/core_ext/object/blank" # For .present?
require "e11y"
require "webmock/rspec"

# Configure WebMock
WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  # Use expect syntax
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Seed for reproducibility
  config.order = :random
  Kernel.srand config.seed

  # Integration tests configuration
  # By default, exclude integration tests (requires Rails, OpenTelemetry SDK, Docker)
  # Run integration tests with: INTEGRATION=true bundle exec rspec
  if ENV["INTEGRATION"] == "true"
    # Run ONLY integration tests when INTEGRATION=true
    config.filter_run_including integration: true
    puts "\n🔧 Running INTEGRATION tests (Rails, OpenTelemetry, etc.)"
    puts "   Dependencies: bundle install --with integration\n\n"
  else
    # Default: exclude integration tests (fast unit tests only)
    config.filter_run_excluding integration: true
  end

  # Clean up after each test
  config.after do
    E11y.reset! if E11y.respond_to?(:reset!)
  end

  # Load support files
  Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }
end
