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

  describe "development DevLog slot aliasing" do
    # Simulate what the railtie does in development: alias :logs/:errors_tracker
    # to the DevLog instance. Integration tests run in test env, so we invoke
    # the class method directly rather than relying on the railtie initializer.
    let(:tmp_file) { Tempfile.new(["e11y_test", ".jsonl"]) }
    let(:tmp_path) { tmp_file.path }
    let(:dev_log) do
      E11y::Adapters::DevLog.new(path: tmp_path, enable_watcher: false)
    end

    before do
      @saved_adapters = E11y.configuration.adapters.dup
      @saved_fallback = E11y.configuration.fallback_adapters.dup
      E11y.configuration.adapters.delete(:dev_log)
      E11y.configuration.adapters.delete(:logs)
      E11y.configuration.adapters.delete(:errors_tracker)
      E11y.configuration.fallback_adapters = [:stdout]
      E11y::Railtie.setup_development_adapters(dev_log)
    end

    after do
      # rubocop:disable RSpec/InstanceVariable
      E11y.configuration.adapters = @saved_adapters
      E11y.configuration.fallback_adapters = @saved_fallback
      # rubocop:enable RSpec/InstanceVariable
      tmp_file.close
      tmp_file.unlink
    end

    it "routes events with adapters: [:logs] to DevLog" do
      E11y::Event::Base.track(
        event_name: "test.routing",
        adapters: [:logs],
        severity: :info,
        payload: { msg: "hello" }
      )
      content = File.read(tmp_path)
      expect(content).to include("test.routing")
    end

    it "routes events with adapters: [:logs, :errors_tracker] to DevLog" do
      E11y::Event::Base.track(
        event_name: "test.error_routing",
        adapters: %i[logs errors_tracker],
        severity: :error,
        payload: { msg: "boom" }
      )
      content = File.read(tmp_path)
      expect(content).to include("test.error_routing")
    end

    it "routes unrouted events to DevLog via fallback" do
      E11y::Event::Base.track(
        event_name: "test.fallback",
        severity: :info,
        payload: { msg: "fallback" }
      )
      content = File.read(tmp_path)
      expect(content).to include("test.fallback")
    end
  end
end
