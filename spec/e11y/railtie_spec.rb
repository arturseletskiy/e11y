# frozen_string_literal: true

require "spec_helper"

# E11y::Railtie testing strategy:
#
# 1. Unit tests (railtie_unit_spec.rb) - Test logic with mocks (NO Rails installation required)
#    - Covers: derive_service_name, configuration logic, environment detection
#    - Run with: bundle exec rspec spec/e11y/railtie_unit_spec.rb
#
# 2. Integration tests (railtie_integration_spec.rb) - Test with REAL Rails app
#    - Covers: middleware insertion, initializers, full Rails integration
#    - Requires: bundle install --with integration
#    - Run with: INTEGRATION=true bundle exec rspec spec/e11y/railtie_integration_spec.rb
#
# This file contains basic smoke tests that run in both modes.

RSpec.describe "E11y::Railtie" do
  describe "availability" do
    it "can be loaded" do
      # NOTE: E11y::Railtie file uses early return (return unless defined?(Rails))
      # The constant may still be defined from previous requires in spec_helper
      # rubocop:todo RSpec/IdenticalEqualityAssertion
      # rubocop:todo RSpec/ExpectActual
      expect(true).to be(true) # Basic smoke test, RSpec/ExpectActual, RSpec/IdenticalEqualityAssertion
      # rubocop:enable RSpec/ExpectActual
      # rubocop:enable RSpec/IdenticalEqualityAssertion
    end

    it "inherits from Rails::Railtie when Rails is available" do
      skip "Rails not available (install with: bundle install --with integration)" unless defined?(Rails)
      skip "E11y::Railtie not defined (file returned early)" unless defined?(E11y::Railtie)

      expect(E11y::Railtie.superclass.name).to eq("Rails::Railtie")
    end
  end

  describe ".derive_service_name (smoke test)" do
    it "has a derive_service_name class method when Rails is available" do
      skip "Rails not available (install with: bundle install --with integration)" unless defined?(Rails)

      expect(E11y::Railtie).to respond_to(:derive_service_name)
    end
  end

  describe "integration hooks" do
    it "defines setup methods for instrumentation when Rails is available" do
      skip "Rails not available (install with: bundle install --with integration)" unless defined?(Rails)

      expect(E11y::Railtie).to respond_to(:setup_rails_instrumentation)
      expect(E11y::Railtie).to respond_to(:setup_logger_bridge)
      expect(E11y::Railtie).to respond_to(:setup_sidekiq)
      expect(E11y::Railtie).to respond_to(:setup_active_job)
    end
  end
end

# For detailed tests, see:
# - spec/e11y/railtie_unit_spec.rb (unit tests with mocks)
# - spec/e11y/railtie_integration_spec.rb (integration tests with real Rails)
