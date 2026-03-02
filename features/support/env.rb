# frozen_string_literal: true

# features/support/env.rb
#
# Cucumber environment bootstrap.
# Loads the dummy Rails application and wires Rack::Test into World.
#
# Load order matters:
#   1. Set RAILS_ENV so Rails boots in test mode.
#   2. Require the dummy app's environment (which calls require "e11y" internally).
#   3. Initialize the Rails application exactly once.
#   4. Load all dummy app source files (controllers, events, models) because
#      config.eager_load = false in the dummy app.

ENV["RAILS_ENV"] = "test"
ENV["E11Y_AUDIT_SIGNING_KEY"] ||= "test_signing_key_for_cucumber_tests_only"
ENV["E11Y_RATE_LIMITING_ENABLED"] = "false"

# Locate the dummy app relative to the features/ directory.
DUMMY_APP_PATH = File.expand_path("../../spec/dummy", __dir__)

# Load the dummy Rails application environment.
# This defines the Dummy::Application class and configures E11y with the
# in-memory adapter at config.adapters[:memory].
require File.join(DUMMY_APP_PATH, "config/environment")

# Initialize the Rails application once.
# Guard against double-initialization if the suite is re-run without a fresh
# process (e.g., during interactive development with `binding.pry`).
unless $rails_app_initialized_for_cucumber # rubocop:disable Style/GlobalVars
  dummy_root = DUMMY_APP_PATH
  Rails.application.config.root = dummy_root unless Rails.application.config.root.to_s == dummy_root
  Rails.application.config.hosts.clear if Rails.application.config.respond_to?(:hosts)
  Rails.application.initialize!
  $rails_app_initialized_for_cucumber = true # rubocop:disable Style/GlobalVars
end

# Run pending database migrations.
ActiveRecord::Base.establish_connection
ActiveRecord::Migration.suppress_messages do
  ActiveRecord::MigrationContext.new(
    File.join(DUMMY_APP_PATH, "db/migrate")
  ).migrate
end

# Eagerly load all dummy app Ruby files.
# The dummy app disables eager_load to avoid issues during multiple test runs,
# so we manually require every file here once.
Dir[File.join(DUMMY_APP_PATH, "app/**/*.rb")].sort.each do |file|
  require file unless File.basename(file).start_with?(".")
end

# Ensure Rails routes are loaded.
Rails.application.routes_reloader.reload! if Rails.application.routes.empty?

# Disable rate limiting globally — it interferes with test assertions.
E11y.configure do |config|
  config.rate_limiting.enabled = false if config.respond_to?(:rate_limiting)
end

# Require Rack::Test so World modules can include it.
require "rack/test"
