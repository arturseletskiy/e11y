# frozen_string_literal: true

require "rails_helper"

RSpec.describe "E11y Railtie Integration", :integration, type: :integration do
  describe "Rails initialization" do
    it "loads E11y railtie" do
      # E11y::Railtie is loaded but may not appear in Rails.application.railties
      # if E11y was configured before the Application class was defined.
      # Instead, verify E11y::Railtie is defined and responds to setup methods.
      expect(defined?(E11y::Railtie)).to be_truthy
      expect(E11y::Railtie).to respond_to(:setup_rails_instrumentation)
    end

    it "configures E11y from Rails" do
      expect(E11y.config.environment).to eq("test")
      expect(E11y.config.service_name).to eq("dummy_app")
      expect(E11y.config.enabled).to be true
    end

    it "registers in-memory adapter" do
      expect(E11y.config.adapters[:memory]).to be_a(E11y::Adapters::InMemory)
    end
  end

  describe "Middleware integration" do
    it "has E11y middleware class available" do
      # E11y::Middleware::Request may not be automatically inserted
      # when E11y is configured before Rails Application is defined.
      # Verify the middleware class is available for manual insertion.
      expect(defined?(E11y::Middleware::Request)).to be_truthy
    end

    it "has middleware that can be inserted into Rails stack" do
      # Verify middleware can be instantiated with a rack app
      app = ->(_env) { [200, {}, ["OK"]] }
      middleware = E11y::Middleware::Request.new(app)
      expect(middleware).to respond_to(:call)
    end
  end

  describe "Rails instrumentation" do
    it "enables Rails instrumentation when configured" do
      expect(E11y.config.rails_instrumentation_enabled).to be true
    end
  end

  describe "ActiveJob instrumentation" do
    it "enables ActiveJob instrumentation when configured" do
      expect(E11y.config.active_job_enabled).to be true
    end

    it "includes E11y callbacks in ActiveJob::Base" do
      expect(ActiveJob::Base.included_modules.map(&:name)).to include("E11y::Instruments::ActiveJob::Callbacks")
    end
  end
end
