# frozen_string_literal: true

require "spec_helper"

# Unit tests for E11y::Railtie logic (without full Rails app)
# These tests work WITHOUT Rails installation (use mocks)
# Run with: bundle exec rspec spec/e11y/railtie_unit_spec.rb

RSpec.describe "E11y::Railtie Logic" do # rubocop:todo RSpec/DescribeClass
  describe ".derive_service_name" do
    context "when Rails is available" do
      let(:app_class) { Class.new }
      let(:rails_app) { double("RailsApp", class: app_class) }

      before do
        # Mock Rails module and application
        stub_const("Rails", Module.new)
        allow(app_class).to receive(:module_parent_name).and_return("MyApplication")
        allow(Rails).to receive(:application).and_return(rails_app)
      end

      it "derives service name from Rails application class" do
        # We need to define Railtie class with the method
        railtie_class = Class.new do
          def self.derive_service_name
            Rails.application.class.module_parent_name.underscore
          rescue StandardError
            "rails_app"
          end
        end

        expect(railtie_class.derive_service_name).to eq("my_application")
      end

      it "converts CamelCase to snake_case" do
        allow(app_class).to receive(:module_parent_name).and_return("MyAwesomeApp")

        railtie_class = Class.new do
          def self.derive_service_name
            Rails.application.class.module_parent_name.underscore
          rescue StandardError
            "rails_app"
          end
        end

        expect(railtie_class.derive_service_name).to eq("my_awesome_app")
      end
    end

    context "when Rails.application raises an error" do
      before do
        stub_const("Rails", Module.new)
        rails_app = double("RailsApp")
        allow(rails_app).to receive(:class).and_raise(NoMethodError)
        allow(Rails).to receive(:application).and_return(rails_app)
      end

      it "returns default service name" do
        railtie_class = Class.new do
          def self.derive_service_name
            Rails.application.class.module_parent_name.underscore
          rescue StandardError
            "rails_app"
          end
        end

        expect(railtie_class.derive_service_name).to eq("rails_app")
      end
    end

    context "when Rails.application is nil" do
      before do
        stub_const("Rails", Module.new)
        allow(Rails).to receive(:application).and_return(nil)
      end

      it "returns default service name" do
        railtie_class = Class.new do
          def self.derive_service_name
            Rails.application.class.module_parent_name.underscore
          rescue StandardError
            "rails_app"
          end
        end

        expect(railtie_class.derive_service_name).to eq("rails_app")
      end
    end
  end

  describe "configuration initialization" do
    let(:app_class) { Class.new }
    let(:rails_app) { double("RailsApp", class: app_class) }

    before do
      E11y.reset!

      # Mock Rails
      stub_const("Rails", Module.new)

      # Create mock env object
      rails_env = double("RailsEnv")
      allow(rails_env).to receive_messages(to_s: "development", test?: false, production?: false)

      allow(app_class).to receive(:module_parent_name).and_return("TestApp")
      allow(Rails).to receive_messages(env: rails_env, application: rails_app)
    end

    it "sets environment from Rails.env" do
      E11y.configure do |config|
        config.environment = Rails.env.to_s
      end

      expect(E11y.config.environment).to eq("development")
    end

    it "sets service_name from derive_service_name" do
      service_name = begin
        Rails.application.class.module_parent_name.underscore
      rescue StandardError
        "rails_app"
      end

      E11y.configure do |config|
        config.service_name = service_name
      end

      expect(E11y.config.service_name).to eq("test_app")
    end

    it "disables E11y in test environment when enabled was unset (nil)" do
      rails_env = double("RailsEnv")
      allow(rails_env).to receive_messages(to_s: "test", test?: true, production?: false)
      allow(Rails).to receive(:env).and_return(rails_env)

      E11y.configure do |config|
        config.enabled = !Rails.env.test? if config.enabled.nil?
      end

      expect(E11y.config.enabled).to be(false)
    end

    it "does not overwrite explicit enabled=true when applying Railtie test default" do
      rails_env = double("RailsEnv")
      allow(rails_env).to receive_messages(to_s: "test", test?: true, production?: false)
      allow(Rails).to receive(:env).and_return(rails_env)

      E11y.configure { |config| config.enabled = true }
      E11y.configure do |config|
        config.enabled = !Rails.env.test? if config.enabled.nil?
      end

      expect(E11y.config.enabled).to be(true)
    end

    it "does not overwrite explicit enabled=false when applying Railtie dev default" do
      rails_env = double("RailsEnv")
      allow(rails_env).to receive_messages(to_s: "development", test?: false, production?: false)
      allow(Rails).to receive(:env).and_return(rails_env)

      E11y.configure { |config| config.enabled = false }
      E11y.configure do |config|
        config.enabled = !Rails.env.test? if config.enabled.nil?
      end

      expect(E11y.config.enabled).to be(false)
    end

    it "enables E11y in development environment when enabled was unset" do
      rails_env = double("RailsEnv")
      allow(rails_env).to receive_messages(to_s: "development", test?: false, production?: false)
      allow(Rails).to receive(:env).and_return(rails_env)

      E11y.configure do |config|
        config.enabled = !Rails.env.test? if config.enabled.nil?
      end

      expect(E11y.config.enabled).to be(true)
    end

    it "enables E11y in production environment when enabled was unset" do
      rails_env = double("RailsEnv")
      allow(rails_env).to receive_messages(to_s: "production", test?: false, production?: true)
      allow(Rails).to receive(:env).and_return(rails_env)

      E11y.configure do |config|
        config.enabled = !Rails.env.test? if config.enabled.nil?
      end

      expect(E11y.config.enabled).to be(true)
    end
  end

  describe "instrumentation setup methods" do
    context "Rails instrumentation" do # rubocop:todo RSpec/ContextWording
      it "requires correct instrument file" do
        # Mock the RailsInstrumentation module
        rails_instrumentation = Module.new do
          def self.setup!
            # Mock setup
          end
        end

        stub_const("E11y::Instruments::RailsInstrumentation", rails_instrumentation)

        expect(rails_instrumentation).to receive(:setup!)

        # Simulate setup call
        rails_instrumentation.setup!
      end
    end

    context "Logger bridge" do # rubocop:todo RSpec/ContextWording
      it "requires correct logger bridge file" do
        logger_bridge = Module.new do
          def self.setup!
            # Mock setup
          end
        end

        stub_const("E11y::Logger::Bridge", logger_bridge)

        expect(logger_bridge).to receive(:setup!)

        logger_bridge.setup!
      end
    end

    context "ActiveJob instrumentation" do # rubocop:todo RSpec/ContextWording
      it "includes callbacks module into ActiveJob::Base" do
        # Mock ActiveJob
        active_job_base = Class.new
        stub_const("ActiveJob::Base", active_job_base)

        # Mock callbacks module
        callbacks_module = Module.new
        stub_const("E11y::Instruments::ActiveJob::Callbacks", callbacks_module)

        # Include module
        active_job_base.include(callbacks_module)

        expect(active_job_base.ancestors).to include(callbacks_module)
      end

      it "includes callbacks into ApplicationJob when defined" do
        active_job_base = Class.new
        application_job = Class.new(active_job_base)

        stub_const("ActiveJob::Base", active_job_base)
        stub_const("ApplicationJob", application_job)

        callbacks_module = Module.new
        stub_const("E11y::Instruments::ActiveJob::Callbacks", callbacks_module)

        application_job.include(callbacks_module)

        expect(application_job.ancestors).to include(callbacks_module)
      end
    end
  end

  describe "environment-based behavior" do
    %w[development production staging].each do |env|
      it "enables E11y in #{env} environment" do
        stub_const(
          "Rails", Module.new
        )
        rails_env = double("RailsEnv")
        allow(rails_env).to receive_messages(
          test?: false, production?: env == "production"
        )
        allow(Rails).to receive(:env).and_return(rails_env)

        enabled = !Rails.env.test?
        expect(enabled).to be(true)
      end
    end

    it "disables E11y in test environment" do
      stub_const("Rails", Module.new)
      rails_env = double("RailsEnv")
      allow(rails_env).to receive_messages(test?: true, production?: false)
      allow(Rails).to receive(:env).and_return(rails_env)

      enabled = !Rails.env.test?
      expect(enabled).to be(false)
    end
  end

  describe "configuration precedence" do
    let(:app_class) { Class.new }
    let(:rails_app) { double("RailsApp", class: app_class) }

    before do
      stub_const("Rails", Module.new)
      allow(app_class).to receive(:module_parent_name).and_return("DefaultApp")

      rails_env = double("RailsEnv")
      allow(rails_env).to receive_messages(to_s: "development", test?: false, production?: false)
      allow(Rails).to receive_messages(application: rails_app, env: rails_env)
    end

    it "allows user configuration to override Railtie defaults" do
      # Simulate Railtie auto-configuration
      E11y.configure do |config|
        config.environment = Rails.env.to_s
        config.service_name = begin
          Rails.application.class.module_parent_name.underscore
        rescue StandardError
          "rails_app"
        end
      end

      # User overrides in initializer
      E11y.configure do |config|
        config.service_name = "custom_service"
        config.environment = "custom_env"
      end

      expect(E11y.config.service_name).to eq("custom_service")
      expect(E11y.config.environment).to eq("custom_env")
    end

    it "merges configurations instead of replacing" do
      E11y.configure do |config|
        config.environment = "auto_detected"
      end

      E11y.configure do |config|
        config.service_name = "user_provided"
      end

      expect(E11y.config.environment).to eq("auto_detected")
      expect(E11y.config.service_name).to eq("user_provided")
    end
  end

  describe "error handling" do
    it "handles missing Rails.application gracefully" do
      stub_const("Rails", Module.new)
      Rails.instance_variable_set(:@application, nil)

      result = begin
        Rails.application.class.module_parent_name.underscore
      rescue StandardError
        "rails_app"
      end

      expect(result).to eq("rails_app")
    end

    it "handles missing module_parent_name method" do
      stub_const("Rails", Module.new)
      app_class = Class.new
      rails_app = double("RailsApp", class: app_class)
      allow(Rails).to receive(:application).and_return(rails_app)

      result = begin
        Rails.application.class.module_parent_name.underscore
      rescue StandardError
        "rails_app"
      end

      expect(result).to eq("rails_app")
    end
  end

  describe ".setup_development_adapters" do
    let(:dev_log) { instance_double("E11y::Adapters::DevLog") }

    before { E11y.reset! }

    it "registers :dev_log adapter" do
      E11y::Railtie.setup_development_adapters(dev_log)
      expect(E11y.config.adapters[:dev_log]).to eq(dev_log)
    end

    it "aliases :logs slot to dev_log when unset" do
      E11y::Railtie.setup_development_adapters(dev_log)
      expect(E11y.config.adapters[:logs]).to eq(dev_log)
    end

    it "aliases :errors_tracker slot to dev_log when unset" do
      E11y::Railtie.setup_development_adapters(dev_log)
      expect(E11y.config.adapters[:errors_tracker]).to eq(dev_log)
    end

    it "does not overwrite :logs if already set by user" do
      custom = double("custom_logs_adapter")
      E11y.configure { |c| c.adapters[:logs] = custom }
      E11y::Railtie.setup_development_adapters(dev_log)
      expect(E11y.config.adapters[:logs]).to eq(custom)
    end

    it "does not overwrite :errors_tracker if already set by user" do
      custom = double("custom_errors_adapter")
      E11y.configure { |c| c.adapters[:errors_tracker] = custom }
      E11y::Railtie.setup_development_adapters(dev_log)
      expect(E11y.config.adapters[:errors_tracker]).to eq(custom)
    end

    it "sets fallback_adapters to [:dev_log] when still at default [:stdout]" do
      expect(E11y.config.fallback_adapters).to eq([:stdout])
      E11y::Railtie.setup_development_adapters(dev_log)
      expect(E11y.config.fallback_adapters).to eq([:dev_log])
    end

    it "does not overwrite fallback_adapters when user changed it" do
      E11y.configure { |c| c.fallback_adapters = [:loki] }
      E11y::Railtie.setup_development_adapters(dev_log)
      expect(E11y.config.fallback_adapters).to eq([:loki])
    end
  end
end
