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

# Detect integration mode BEFORE loading E11y (critical for Railtie registration)
# Avoid loading E11y before Rails in integration tests, or Railtie won't register.
tag_integration = ARGV.each_cons(2).any? { |a, b| a == "--tag" && b == "integration" } ||
                  ARGV.any?("--tag=integration") ||
                  ENV["INTEGRATION"] == "true"
tag_exclude_integration = ARGV.each_cons(2).any? { |a, b| a == "--tag" && b == "~integration" } ||
                          ARGV.any?("--tag=~integration")
running_integration_files = ARGV.any? { |arg| arg.include?("spec/integration/") }
integration_run = (tag_integration || running_integration_files) && !tag_exclude_integration

# Load ActiveSupport BEFORE core extensions (required for Rails 7.1+ deprecator)
require "active_support"
require "active_support/core_ext/numeric/time" # For 30.days, 7.years
require "active_support/core_ext/integer/time"
require "active_support/core_ext/object/blank" # For .present?
require "climate_control" # For ENV manipulation in tests

# In integration mode, ensure Rails::Railtie is defined BEFORE loading E11y
# so E11y::Railtie registers properly and its initializers run on app boot.
require "rails/railtie" if integration_run
require "e11y"
require "e11y/testing/rspec_matchers"
require "e11y/testing/snapshot_matcher"
require "webmock/rspec"

# Configure WebMock
# CRITICAL: Disable WebMock for integration tests - they must use real services
if integration_run
  # Integration tests use real services (Loki, Prometheus, etc.)
  WebMock.allow_net_connect!
else
  # Unit tests use WebMock to prevent accidental network calls
  WebMock.disable_net_connect!(allow_localhost: true)
end

RSpec.configure do |config|
  config.include E11y::Testing::RSpecMatchers
  config.include(Module.new do
    def match_snapshot(name)
      E11y::Testing::SnapshotMatcher.new(name)
    end
  end)

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
  # Or with: bundle exec rspec --tag integration

  # Integration detection is computed above (integration_run)
  if integration_run
    ENV["INTEGRATION"] = "true" # Ensure rails_helper knows we're in integration mode
    # Run ONLY integration tests
    config.filter_run_including integration: true
    puts "\n🔧 Running INTEGRATION tests (Rails, OpenTelemetry, etc.)"
    puts "   Dependencies: bundle install --with integration\n\n"
  else
    # Default: exclude integration tests (fast unit tests only)
    config.filter_run_excluding integration: true
    # Exclude opentelemetry tests (require OTel SDK; run with: rspec --tag opentelemetry)
    config.filter_run_excluding opentelemetry: true
  end

  # Unit tests: ensure E11y is enabled and audit events have routing
  config.before do |example|
    next if example.metadata[:integration]

    cfg = E11y.configuration
    cfg.enabled = true if cfg.enabled.nil? # Default: enabled for unit tests (Railtie sets false in Rails test env)
    cfg.routing_rules = [->(e) { :stdout if e[:audit_event] }] if cfg.routing_rules.empty?
    # Quiet E11y logs in unit tests (unless VERBOSE)
    cfg.logger = Logger.new(nil) unless ENV["VERBOSE"]
  end

  # Clean up after each test
  config.after do |example|
    if example.metadata[:integration]
      # Integration tests: Clear adapters and pipeline state, but keep Rails config
      if E11y.configuration.respond_to?(:adapters)
        E11y.configuration.adapters.each_value do |adapter|
          adapter.clear! if adapter.respond_to?(:clear!)
        end
      end
      # Clear pipeline state to force rebuild on next test
      E11y.configuration&.instance_variable_set(:@built_pipeline, nil)
    elsif E11y.respond_to?(:reset!)
      # Unit tests: Full reset
      E11y.reset!
    end
  end

  # Load support files
  Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }
end
