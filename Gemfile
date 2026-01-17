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
  gem "factory_bot", "~> 6.2"
  gem "faker", "~> 3.2"
  gem "rspec-benchmark", "~> 0.6"
  gem "timecop", "~> 0.9"
  gem "webmock", "~> 3.18"
end

# Code quality
group :development, :test do
  gem "brakeman", "~> 6.0"
  gem "bundler-audit", "~> 0.9"
  gem "simplecov", require: false
  gem "simplecov-cobertura", require: false
end
