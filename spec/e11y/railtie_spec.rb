# frozen_string_literal: true

require "spec_helper"

# Mock Rails before loading Railtie
RSpec.describe "E11y::Railtie", type: :railtie do
  # Note: Full Rails integration testing is complex and requires a Rails app
  # These are basic unit tests for the Railtie class itself
  # Since Railtie requires Rails, we skip these tests if Rails is not available

  before(:all) do
    skip "Rails not available" unless defined?(Rails)
  end

  describe ".derive_service_name" do
    it "derives service name from Rails application class" do
      # Mock Rails application
      stub_const("Rails", Module.new)
      app_class = Class.new
      allow(app_class).to receive(:module_parent_name).and_return("MyApp")
      allow(Rails).to receive_message_chain(:application, :class).and_return(app_class)

      expect(described_class.send(:derive_service_name)).to eq("my_app")
    end

    it "returns default service name on error" do
      # Mock Rails but make it raise an error
      stub_const("Rails", Module.new)
      allow(Rails).to receive_message_chain(:application, :class).and_raise(StandardError)

      expect(described_class.send(:derive_service_name)).to eq("rails_app")
    end
  end

  describe "Rails integration", :skip do
    # TODO: These tests require a full Rails app environment
    # They should be moved to a separate integration test suite

    it "auto-configures E11y on Rails boot"
    it "inserts E11y::Middleware::Request before Rails::Rack::Logger"
    it "loads console helpers in Rails console"
    it "enables Rails instrumentation when configured"
    it "disables E11y in test environment by default"
  end

  describe "initializers", :skip do
    # TODO: These tests require Rails initializers to be loaded

    it "registers e11y.middleware initializer"
    it "middleware initializer inserts E11y::Middleware::Request"
    it "middleware initializer respects config.enabled flag"
  end
end
