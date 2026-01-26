# frozen_string_literal: true

# This file is loaded by RSpec for Rails integration tests
# See spec_helper.rb for general RSpec configuration

require "spec_helper"

# Only load Rails environment when running integration tests
# This prevents conflicts when running regular specs
# Check if we're running with --tag integration or INTEGRATION=true
if ENV["INTEGRATION"] != "true" && ARGV.none? { |arg| arg.include?("integration") }
  # Set ENV["INTEGRATION"] so subsequent requires know we're in integration mode
  ENV["INTEGRATION"] = "true"
end

# Skip if not in integration mode
return unless ENV["INTEGRATION"] == "true"

# Set test-only environment variables
ENV["E11Y_AUDIT_SIGNING_KEY"] ||= "test_signing_key_for_integration_tests_only"
ENV["RAILS_ENV"] ||= "test"

# Load Rails environment ONLY if not already loaded
# Use global variable because constants don't persist across multiple file loads
# rubocop:disable Style/GlobalVars
unless $rails_app_initialized
  require File.expand_path("dummy/config/environment", __dir__)

  # Initialize Rails application
  Rails.application.initialize!
  $rails_app_initialized = true
  # rubocop:enable Style/GlobalVars

  require "rspec/rails"

  # Load Sidekiq for background job tests (if available)
  begin
    require "sidekiq/testing"
  rescue LoadError
    # Sidekiq not available, skip Sidekiq tests
  end
end

RSpec.configure do |config|
  # Rails-specific configuration
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # Treat integration specs as request specs to get Rails request helpers (get, post, etc.)
  config.define_derived_metadata(file_path: %r{/spec/integration/}) do |metadata|
    metadata[:type] = :request
  end

  # Initialize Rails environment ONCE for the entire test suite
  config.before(:suite) do
    # Run migrations to create database schema
    ActiveRecord::Base.establish_connection
    ActiveRecord::Migration.suppress_messages do
      ActiveRecord::MigrationContext.new(File.expand_path("dummy/db/migrate", __dir__)).migrate
    end

    # Load dummy app models and controllers manually
    # Since eager_load is false, we need to manually load these files
    Dir[File.expand_path("dummy/app/**/*.rb", __dir__)].each do |file|
      require file unless File.basename(file).start_with?(".")
    end

    # Ensure routes are loaded (they should already be loaded during Rails.application.initialize!)
    # Just verify they're available
    Rails.application.routes.draw { nil } if Rails.application.routes.empty?

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
  end

  config.before do |example|
    # Clear E11y adapter events before each test (but don't reset config!)
    if example.metadata[:integration] || %i[integration request].include?(example.metadata[:type])
      adapter = E11y.config.adapters[:memory]
      adapter.clear! if adapter.respond_to?(:clear!)
    end
  end

  config.after do
    # Clean up database
    ActiveRecord::Base.connection.execute("DELETE FROM posts") if ActiveRecord::Base.connection.table_exists?("posts")
  end
end
