# frozen_string_literal: true

require "spec_helper"
require "logger"
require "e11y/logger/bridge"

RSpec.describe E11y::Logger::Bridge do
  let(:original_logger) { Logger.new(StringIO.new) }
  let(:bridge) { described_class.new(original_logger) }

  describe "#initialize" do
    it "wraps the original logger" do
      expect(bridge.__getobj__).to eq(original_logger)
    end

    it "sets up severity mapping" do
      expect(bridge.instance_variable_get(:@severity_mapping)).to be_a(Hash)
    end
  end

  describe "logger methods" do
    before do
      # Mock E11y events to avoid requiring full E11y setup
      stub_const("E11y::Events::Rails::Log::Debug", double(track: nil))
      stub_const("E11y::Events::Rails::Log::Info", double(track: nil))
      stub_const("E11y::Events::Rails::Log::Warn", double(track: nil))
      stub_const("E11y::Events::Rails::Log::Error", double(track: nil))
      stub_const("E11y::Events::Rails::Log::Fatal", double(track: nil))
    end

    describe "#debug" do
      it "delegates to original logger" do
        expect(original_logger).to receive(:debug).with("debug message")
        bridge.debug("debug message")
      end

      it "tracks to E11y" do
        allow(original_logger).to receive(:debug)
        expect(E11y::Events::Rails::Log::Debug).to receive(:track).with(
          hash_including(message: "debug message")
        )
        bridge.debug("debug message")
      end
    end

    describe "#info" do
      it "delegates to original logger" do
        expect(original_logger).to receive(:info).with("test message")
        bridge.info("test message")
      end

      it "tracks to E11y" do
        allow(original_logger).to receive(:info)
        expect(E11y::Events::Rails::Log::Info).to receive(:track).with(
          hash_including(message: "test message")
        )
        bridge.info("test message")
      end
    end

    describe "#warn" do
      it "delegates to original logger" do
        expect(original_logger).to receive(:warn).with("warn message")
        bridge.warn("warn message")
      end

      it "tracks to E11y" do
        allow(original_logger).to receive(:warn)
        expect(E11y::Events::Rails::Log::Warn).to receive(:track).with(
          hash_including(message: "warn message")
        )
        bridge.warn("warn message")
      end
    end

    describe "#error" do
      it "delegates to original logger" do
        expect(original_logger).to receive(:error).with("error message")
        bridge.error("error message")
      end

      it "tracks to E11y" do
        allow(original_logger).to receive(:error)
        expect(E11y::Events::Rails::Log::Error).to receive(:track).with(
          hash_including(message: "error message")
        )
        bridge.error("error message")
      end
    end

    describe "#fatal" do
      it "delegates to original logger" do
        expect(original_logger).to receive(:fatal).with("fatal message")
        bridge.fatal("fatal message")
      end

      it "tracks to E11y" do
        allow(original_logger).to receive(:fatal)
        expect(E11y::Events::Rails::Log::Fatal).to receive(:track).with(
          hash_including(message: "fatal message")
        )
        bridge.fatal("fatal message")
      end
    end

    describe "#add" do
      it "delegates to original logger" do
        expect(original_logger).to receive(:add).with(Logger::INFO, "test", nil)
        bridge.add(Logger::INFO, "test")
      end

      it "tracks to E11y with mapped severity" do
        allow(original_logger).to receive(:add)
        expect(E11y::Events::Rails::Log::Info).to receive(:track).with(
          hash_including(message: "test")
        )
        bridge.add(Logger::INFO, "test")
      end

      it "handles UNKNOWN severity" do
        allow(original_logger).to receive(:add)
        expect(E11y::Events::Rails::Log::Warn).to receive(:track).with(
          hash_including(message: "unknown")
        )
        bridge.add(Logger::UNKNOWN, "unknown")
      end
    end

    describe "#log" do
      before do
        stub_const("E11y::Events::Rails::Log::Info", double(track: nil))
      end

      it "is aliased to #add" do
        allow(E11y::Events::Rails::Log::Info).to receive(:track)
        # log is an alias to add, so expect add to be called on underlying logger
        expect(original_logger).to receive(:add).with(Logger::INFO, "test", nil)
        bridge.log(Logger::INFO, "test")
      end
    end
  end

  describe "#track_to_e11y" do
    before do
      stub_const("E11y::Events::Rails::Log::Info", double(track: nil))
    end

    it "handles nil messages gracefully" do
      allow(original_logger).to receive(:info)
      expect(E11y::Events::Rails::Log::Info).not_to receive(:track)
      bridge.info(nil)
    end

    it "handles empty messages gracefully" do
      allow(original_logger).to receive(:info)
      expect(E11y::Events::Rails::Log::Info).not_to receive(:track)
      bridge.info("")
    end

    it "handles block messages" do
      allow(original_logger).to receive(:info)
      expect(E11y::Events::Rails::Log::Info).to receive(:track).with(
        hash_including(message: "block message")
      )
      bridge.info { "block message" }
    end

    it "skips tracking when severity not in track_severities" do
      allow(original_logger).to receive(:debug)
      allow(E11y.config.logger_bridge).to receive(:track_severities).and_return(%i[info warn error fatal])
      allow(E11y.config.logger_bridge).to receive(:ignore_patterns).and_return([])

      expect(E11y::Events::Rails::Log::Debug).not_to receive(:track)
      bridge.debug("debug message")
    end

    it "tracks when severity in track_severities" do
      allow(original_logger).to receive(:warn)
      allow(E11y.config.logger_bridge).to receive(:track_severities).and_return(%i[warn error])
      allow(E11y.config.logger_bridge).to receive(:ignore_patterns).and_return([])

      expect(E11y::Events::Rails::Log::Warn).to receive(:track).with(
        hash_including(message: "warn message")
      )
      bridge.warn("warn message")
    end

    it "skips tracking when message matches ignore_patterns" do
      allow(original_logger).to receive(:info)
      allow(E11y.config.logger_bridge).to receive(:track_severities).and_return(nil)
      allow(E11y.config.logger_bridge).to receive(:ignore_patterns).and_return([/Started GET/, /Completed \d+ OK/])

      expect(E11y::Events::Rails::Log::Info).not_to receive(:track)
      bridge.info("Started GET \"/posts\" for 127.0.0.1 at 2024-01-15 10:00:00")
    end

    it "tracks when message does not match ignore_patterns" do
      allow(original_logger).to receive(:info)
      allow(E11y.config.logger_bridge).to receive(:track_severities).and_return(nil)
      allow(E11y.config.logger_bridge).to receive(:ignore_patterns).and_return([/Started GET/])

      expect(E11y::Events::Rails::Log::Info).to receive(:track).with(
        hash_including(message: "Order created")
      )
      bridge.info("Order created")
    end

    it "silently handles E11y tracking errors" do
      allow(original_logger).to receive(:info)
      allow(E11y::Events::Rails::Log::Info).to receive(:track).and_raise(StandardError, "tracking failed")

      expect { bridge.info("test") }.not_to raise_error
    end

    it "warns about tracking errors in development" do
      # Create a Rails mock with development environment
      rails_env = double("RailsEnv", development?: true)
      rails_mock = double("Rails", env: rails_env)
      stub_const("Rails", rails_mock)

      # Allow the original logger methods to be called
      allow(original_logger).to receive(:info).and_call_original

      # Create a stub for Warn event that doesn't raise
      stub_const("E11y::Events::Rails::Log::Warn", double(track: nil))

      # Make track_to_e11y fail for :info
      allow(E11y::Events::Rails::Log::Info).to receive(:track).and_raise(StandardError, "tracking failed")

      # Override the bridge's warn method to actually output to stderr
      allow(bridge).to receive(:warn) do |msg|
        warn msg
        original_logger.warn(msg)
      end

      # The warn output happens when calling info, which triggers track_to_e11y error
      expect do
        bridge.info("test")
      end.to output(/E11y logger tracking failed: tracking failed/).to_stderr
    end
  end

  describe ".setup!" do
    let(:logger_bridge_config) { instance_double(E11y::LoggerBridgeConfig, enabled: enabled) }

    before do
      allow(E11y.config).to receive(:logger_bridge).and_return(logger_bridge_config)

      # Reset Rails.logger if it exists
      if defined?(Rails)
        allow(Rails).to receive(:logger).and_return(original_logger)
        allow(Rails).to receive(:logger=)
      end
    end

    context "when logger_bridge is enabled" do
      let(:enabled) { true }

      it "wraps Rails.logger when Rails is defined", :skip_unless_rails do
        skip "Rails not loaded" unless defined?(Rails)

        described_class.setup!
        expect(Rails).to have_received(:logger=).with(instance_of(described_class))
      end
    end

    context "when logger_bridge is disabled" do
      let(:enabled) { false }

      it "does not wrap Rails.logger", :skip_unless_rails do
        skip "Rails not loaded" unless defined?(Rails)

        described_class.setup!
        expect(Rails).not_to have_received(:logger=)
      end
    end
  end
end
