# frozen_string_literal: true

# See https://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration

# Load local lib path FIRST (before any requires)
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# SimpleCov setup (must be at the very top)
if ENV["COVERAGE"]
  require "simplecov"
  require "simplecov-cobertura"

  SimpleCov.start do
    # Set coverage directory
    coverage_dir "coverage"

    add_filter "/spec/"
    add_filter "/vendor/"
    add_filter "/benchmarks/"

    # Exclude namespace-only files (no logic to test)
    add_filter "lib/e11y/buffers.rb"
    add_filter "lib/e11y/middleware.rb"
    add_filter "lib/e11y/pii.rb"
    add_filter "lib/e11y/pipeline.rb"
    add_filter "lib/e11y/version.rb"

    # Exclude deprecated/duplicate files (old versions not used in production)
    add_filter "lib/e11y/middleware/pii_filtering.rb" # Duplicate of pii_filter.rb
    add_filter "lib/e11y/middleware/slo.rb" # Duplicate of event_slo.rb

    # Exclude Rails-specific files (tested in integration tests with Rails environment)
    add_filter "lib/e11y/railtie.rb" # Requires Rails environment
    add_filter "lib/e11y/instruments/active_job.rb" # Requires ActiveJob
    add_filter "lib/e11y/instruments/sidekiq.rb" # Requires Sidekiq
    add_filter "lib/e11y/adapters/otel_logs.rb" # Requires OpenTelemetry (optional dependency)

    # Coverage groups
    add_group "Core", "lib/e11y"
    add_group "Events", "lib/e11y/events"
    add_group "Buffers", "lib/e11y/buffers"
    add_group "Middleware", "lib/e11y/middleware"
    add_group "Adapters", "lib/e11y/adapters"

    minimum_coverage line: 95
    refuse_coverage_drop

    # Print files with low coverage (using SimpleCov's at_exit hook)
    SimpleCov.at_exit do
      SimpleCov.result.format! # CRITICAL: Ensure formatters run!

      if SimpleCov.result
        files_under_target = SimpleCov.result.files.select { |f| f.covered_percent < 100 }.sort_by(&:covered_percent)
        if files_under_target.any?
          puts "\n\n📊 Files with < 100% coverage (#{files_under_target.size} files):\n\n"
          files_under_target.first(20).each do |file|
            short_name = file.filename.gsub("#{Dir.pwd}/", "")
            percent = file.covered_percent.round(2).to_s.rjust(6)
            puts "  #{percent}% - #{short_name}"
          end
        end
      end
    end

    # Multiple formatters
    SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new([
                                                                      SimpleCov::Formatter::HTMLFormatter,
                                                                      SimpleCov::Formatter::CoberturaFormatter
                                                                    ])
  end
end

# Eager load all files for coverage tracking (Zeitwerk uses lazy loading by default)
if ENV["COVERAGE"]
  require "e11y"

  # Force load all lib files to ensure coverage tracking
  Dir.glob(File.expand_path("../lib/**/*.rb", __dir__)).each do |file|
    # Skip namespace-only files already filtered in SimpleCov
    next if file.end_with?("/buffers.rb", "/middleware.rb", "/pii.rb", "/pipeline.rb", "/version.rb")
    # Skip deprecated files
    next if file.end_with?("/pii_filtering.rb", "/slo.rb")
    # Skip Rails-specific files (require Rails environment)
    next if file.end_with?("/railtie.rb")
    # Skip files that are already auto-required by e11y.rb
    next if file.end_with?("/e11y.rb")

    begin
      require file
    rescue LoadError, NameError => e
      # Some files may have dependencies not available in test environment
      warn "Warning: Could not eager load #{file}: #{e.message}"
    end
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

  # Clean up after each test (but NOT for integration tests - they rely on Rails app config)
  config.after do |example|
    E11y.reset! if !example.metadata[:integration] && E11y.respond_to?(:reset!)
  end

  # Load support files
  Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }
end
