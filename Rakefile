# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new

task default: %i[spec rubocop]

# Test suite tasks
namespace :spec do
  desc "Run unit tests only (fast, no Rails/integrations)"
  task :unit do
    sh "bundle exec rspec spec/e11y spec/e11y_spec.rb spec/zeitwerk_spec.rb"
  end

  desc "Run integration tests (requires Rails, bundle install --with integration)"
  task :integration do
    sh "INTEGRATION=true bundle exec rspec spec/integration/"
  end

  desc "Run railtie integration tests (separate Rails app instance)"
  task :railtie do
    sh "bundle exec rspec spec/e11y/railtie_integration_spec.rb --tag railtie_integration"
  end

  desc "Run all tests (unit + integration + railtie, ~1729 examples)"
  task :all do
    puts "\n#{'=' * 80}"
    puts "Running UNIT tests (spec/e11y + top-level specs)..."
    puts "#{'=' * 80}\n"
    Rake::Task["spec:unit"].invoke

    puts "\n#{'=' * 80}"
    puts "Running INTEGRATION tests (spec/integration)..."
    puts "#{'=' * 80}\n"
    Rake::Task["spec:integration"].invoke

    puts "\n#{'=' * 80}"
    puts "Running RAILTIE tests (Rails initialization)..."
    puts "#{'=' * 80}\n"
    Rake::Task["spec:railtie"].invoke

    puts "\n#{'=' * 80}"
    puts "✅ All test suites completed!"
    puts "#{'=' * 80}\n"
  end

  desc "Run tests with coverage report"
  task :coverage do
    sh "COVERAGE=true bundle exec rspec"
  end

  desc "Run integration tests with coverage"
  task :coverage_integration do
    sh "COVERAGE=true INTEGRATION=true bundle exec rspec spec/integration/"
  end

  desc "Run benchmark tests (performance tests, slow)"
  task :benchmark do
    sh "bundle exec rspec spec/e11y --tag benchmark"
  end

  desc "Run ALL tests including benchmarks (very slow)"
  task :everything do
    puts "\n#{'=' * 80}"
    puts "Running ALL tests (unit + integration + railtie + benchmarks)"
    puts "#{'=' * 80}\n"
    Rake::Task["spec:unit"].invoke
    Rake::Task["spec:integration"].invoke
    Rake::Task["spec:railtie"].invoke
    Rake::Task["spec:benchmark"].invoke

    puts "\n#{'=' * 80}"
    puts "✅ All test suites including benchmarks completed!"
    puts "#{'=' * 80}\n"
  end
end

# Custom tasks
namespace :e11y do
  desc "Start interactive console"
  task :console do
    require "pry"
    require_relative "lib/e11y"
    Pry.start
  end

  desc "Run performance benchmarks"
  task :benchmark do
    ruby "spec/benchmarks/run_all.rb"
  end

  desc "Generate documentation"
  task :docs do
    sh "yard doc"
  end

  desc "Run security audit"
  task :audit do
    sh "bundle exec bundler-audit check --update"
    sh "bundle exec brakeman --no-pager"
  end
end
