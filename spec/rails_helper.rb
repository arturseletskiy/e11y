# frozen_string_literal: true

# This file is loaded by RSpec for Rails integration tests
# See spec_helper.rb for general RSpec configuration

require "spec_helper"

# Only load Rails environment when running integration tests
# This prevents conflicts when running regular specs
# Check if we're running with --tag integration or INTEGRATION=true
if ENV["INTEGRATION"] != "true" && !ARGV.any? { |arg| arg.include?("integration") }
  # When integration tests are loaded but not run (rspec without --tag integration),
  # just skip initializing Rails - the tests will be filtered out anyway
  return
end

# Set ENV["INTEGRATION"] for compatibility
ENV["INTEGRATION"] = "true"

# Set test-only environment variables
ENV["E11Y_AUDIT_SIGNING_KEY"] ||= "test_signing_key_for_integration_tests_only"

# Load dummy Rails app for integration tests
ENV["RAILS_ENV"] ||= "test"
require_relative "dummy/config/environment"
require "rspec/rails"

# Load Sidekiq for background job tests (if available)
begin
  require "sidekiq/testing"
rescue LoadError
  # Sidekiq not available, skip Sidekiq tests
end

# Run migrations to create database schema
ActiveRecord::Base.establish_connection
ActiveRecord::Migration.suppress_messages do
  ActiveRecord::MigrationContext.new(File.expand_path("dummy/db/migrate", __dir__)).migrate
end

# Load dummy app models and controllers
# Rails eager_load doesn't load dummy app files automatically
Dir[File.expand_path("dummy/app/**/*.rb", __dir__)].each { |f| require f }

# E11y is already configured in dummy/config/application.rb
# Verify configuration is correct
raise "E11y should be enabled for integration tests! Check dummy/config/application.rb" unless E11y.config.enabled

# Setup E11y instrumentation manually since Rails is already initialized
# when rails_helper is loaded (initializers don't run after Rails.application.initialize!)
if E11y.config.enabled
  E11y::Railtie.setup_rails_instrumentation if E11y.config.rails_instrumentation&.enabled
  E11y::Railtie.setup_active_job if defined?(ActiveJob) && E11y.config.active_job&.enabled
  E11y::Railtie.setup_sidekiq if defined?(Sidekiq) && E11y.config.sidekiq&.enabled
end

RSpec.configure do |config|
  # Rails-specific configuration
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # Database cleaner
  config.before(:suite) do
    # Setup database
    ActiveRecord::Base.establish_connection
  end

  config.before do |example|
    # Clear E11y adapter events before each test
    if %i[integration request].include?(example.metadata[:type])
      adapter = E11y.config.adapters[:memory]
      adapter.clear! if adapter.respond_to?(:clear!)
    end
  end

  config.after do
    # Clean up database
    ActiveRecord::Base.connection.execute("DELETE FROM posts") if ActiveRecord::Base.connection.table_exists?("posts")
  end
end
