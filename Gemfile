# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in e11y.gemspec
gemspec

# Runtime dependencies (also in gemspec)
gem "concurrent-ruby", "~> 1.2" # Thread-safe data structures
gem "dry-schema", "~> 1.13" # Event schema validation

gem "rake", "~> 13.0"
gem "rspec", "~> 3.0"
gem "rubocop", "~> 1.21"

# Development tools
group :development do
  gem "pry", "~> 0.14"
  gem "pry-byebug", "~> 3.10"

  # Documentation
  gem "redcarpet", "~> 3.6" # Markdown support for YARD
  gem "yard", "~> 0.9"
end

# Testing tools
group :test do
  gem "climate_control", "~> 1.2" # ENV manipulation for tests
  gem "factory_bot", "~> 6.2"
  gem "faker", "~> 3.2"
  gem "rspec-benchmark", "~> 0.6"
  gem "timecop", "~> 0.9"
  gem "webmock", "~> 3.18"
end

# Integration testing dependencies (optional)
# Install with: bundle install --with integration
# Run integration tests: INTEGRATION=true bundle exec rspec --tag integration
group :integration do
  # Support Rails 7.0, 7.1, 8.0 (not 8.1 due to sqlite3_production_warning bug)
  rails_version = ENV.fetch("RAILS_VERSION", "8.0")
  gem "rails", "~> #{rails_version}.0", "< 8.1"

  # sqlite3 version depends on Rails version:
  # Rails 7.x requires sqlite3 ~> 1.4
  # Rails 8.x requires sqlite3 ~> 2.0
  if rails_version.to_f < 8.0
    gem "sqlite3", "~> 1.4" # Rails 7.x compatibility
  else
    gem "sqlite3", "~> 2.0" # Rails 8.x compatibility
  end

  # Background job processing
  gem "sidekiq", "~> 7.0" # Sidekiq for job processing tests

  # OpenTelemetry SDK for OTel adapter tests
  gem "opentelemetry-logs-api", "~> 0.1"
  gem "opentelemetry-logs-sdk", "~> 0.1"
  gem "opentelemetry-sdk", "~> 1.0"

  # Yabeda for Yabeda adapter tests
  gem "yabeda", "~> 0.12" # Yabeda core
  gem "yabeda-prometheus", "~> 0.9" # Prometheus exporter

  # Additional Rails dependencies
  gem "database_cleaner-active_record", "~> 2.0" # DB cleanup between tests
  gem "rspec-rails", "~> 7.0" # Rails-specific RSpec matchers
end

# Code quality
group :development, :test do
  gem "bundler-audit", "~> 0.9" # Check for vulnerable dependencies
  gem "rubocop-performance", "~> 1.21" # Performance cops
  gem "simplecov", require: false
  gem "simplecov-cobertura", require: false
end
