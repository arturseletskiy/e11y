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

    it "silently handles E11y tracking errors" do
      allow(original_logger).to receive(:info)
      allow(E11y::Events::Rails::Log::Info).to receive(:track).and_raise(StandardError, "tracking failed")

      expect { bridge.info("test") }.not_to raise_error
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
