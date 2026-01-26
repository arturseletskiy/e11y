# frozen_string_literal: true

# This file is loaded by RSpec for Rails integration tests
# See spec_helper.rb for general RSpec configuration

require "spec_helper"

# Only load Rails environment when running integration tests
# This prevents conflicts when running regular specs
# NOTE: spec_helper.rb sets ENV["INTEGRATION"] = "true" when --tag integration is detected
# If not set, we're in unit test mode - skip Rails loading
unless ENV["INTEGRATION"] == "true"
  # CRITICAL: Don't just return - raise an error if someone tries to require rails_helper outside integration mode
  # This makes debugging easier than silent failures
  if caller.grep(/spec_helper\.rb/).empty?
    warn "\n⚠️  WARNING: rails_helper.rb loaded without INTEGRATION=true!"
    warn "   This file should only be loaded during integration tests."
    warn "   Run with: bundle exec rspec --tag integration\n\n"
  end
  return
end

# CRITICAL: Set RAILS_ENV FIRST, before loading anything else
# This ensures Rails.env is correctly set to "test" from the start
ENV["RAILS_ENV"] = "test"

# Set test-only environment variables BEFORE loading Rails
ENV["E11Y_AUDIT_SIGNING_KEY"] ||= "test_signing_key_for_integration_tests_only"

# Load Rails environment file (but DON'T initialize yet - that happens in before(:suite))
# Use global variable because constants don't persist across multiple file loads
# rubocop:disable Style/GlobalVars
unless $rails_env_loaded
  # CRITICAL: Load dummy Rails app using absolute path from this file's location
  # This ensures database.yml can be found regardless of current working directory
  # See: https://rderik.com/blog/how-to-add-rspec-to-an-existing-engine/
  require File.expand_path("dummy/config/environment", __dir__)
  $rails_env_loaded = true
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
  # rubocop:disable Style/GlobalVars
  config.before(:suite) do
    # Initialize Rails application ONCE
    unless $rails_app_initialized
      # CRITICAL: Ensure config.root is set BEFORE initialize!
      # Rails 8.0 needs this to find database.yml during initialization
      dummy_root = File.expand_path("dummy", __dir__)
      Rails.application.config.root = dummy_root unless Rails.application.config.root.to_s == dummy_root

      # Disable host authorization BEFORE initializing
      # Rails 6.1+ has HostAuthorization middleware that blocks requests without proper Host header
      Rails.application.config.hosts.clear if Rails.application.config.respond_to?(:hosts)

      Rails.application.initialize!
      $rails_app_initialized = true
    end
    # rubocop:enable Style/GlobalVars
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
    # If routes are empty, reload them from config/routes.rb
    Rails.application.routes_reloader.reload! if Rails.application.routes.empty?

    # E11y is already configured in dummy/config/application.rb
    # Verify configuration is correct
    raise "E11y should be enabled for integration tests! Check dummy/config/application.rb" unless E11y.config.enabled

    # NOTE: E11y instrumentation is set up automatically by Railtie initializers
    # DO NOT call setup methods here or it will cause double instrumentation!
    # The initializers run as part of Rails.application.initialize! above.
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
