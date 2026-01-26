# frozen_string_literal: true

# This file is loaded by RSpec for Rails integration tests
# See spec_helper.rb for general RSpec configuration
#
# NOTE: Rails environment is loaded in spec_helper.rb's before(:suite) hook
# to ensure it's only loaded once across all integration tests.

require "spec_helper"

# Only proceed if running integration tests
if ENV["INTEGRATION"] != "true" && !ARGV.any? { |arg| arg.include?("integration") }
  return
end

# Verify Rails is loaded (should be loaded by spec_helper.rb before(:suite))
unless defined?(Rails) && Rails.application.initialized?
  raise "Rails should be initialized by spec_helper.rb before(:suite) hook!"
end

# Load Sidekiq for background job tests (if available)
begin
  require "sidekiq/testing"
rescue LoadError
  # Sidekiq not available, skip Sidekiq tests
end

# Verify E11y configuration
raise "E11y should be enabled for integration tests!" unless E11y.config.enabled

RSpec.configure do |config|
  # Rails-specific configuration
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.before do |example|
    # Clear E11y adapter events before each test
    if %i[integration request].include?(example.metadata[:type])
      adapter = E11y.config.adapters[:memory]
      adapter.clear! if adapter.respond_to?(:clear!)
    end
  end

  config.after do
    # Clean up database
    if defined?(ActiveRecord) && ActiveRecord::Base.connection.table_exists?("posts")
      ActiveRecord::Base.connection.execute("DELETE FROM posts")
    end
  end
end
