# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new

task default: %i[spec rubocop]

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
