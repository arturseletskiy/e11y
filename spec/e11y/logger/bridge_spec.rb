# frozen_string_literal: true

require "spec_helper"
require "e11y/logger/bridge"
require "logger"

RSpec.describe E11y::Logger::Bridge do
  let(:original_logger) { instance_double(Logger) }
  let(:bridge) { described_class.new(original_logger) }

  before do
    # Mock configuration
    allow(E11y).to receive(:config).and_return(
      double(logger_bridge: double(track_to_e11y: false))
    )
  end

  describe "#initialize" do
    it "wraps the original logger via SimpleDelegator" do
      expect(bridge.__getobj__).to eq(original_logger)
    end

    it "sets up severity mapping" do
      expect(bridge.instance_variable_get(:@severity_mapping)).to be_a(Hash)
      expect(bridge.instance_variable_get(:@severity_mapping)[Logger::INFO]).to eq(:info)
    end
  end

  describe "logger methods delegation" do
    it "delegates debug to original logger" do
      expect(original_logger).to receive(:debug).with("Test message")
      bridge.debug("Test message")
    end

    it "delegates info to original logger" do
      expect(original_logger).to receive(:info).with("Test message")
      bridge.info("Test message")
    end

    it "delegates warn to original logger" do
      expect(original_logger).to receive(:warn).with("Test message")
      bridge.warn("Test message")
    end

    it "delegates error to original logger" do
      expect(original_logger).to receive(:error).with("Test message")
      bridge.error("Test message")
    end

    it "delegates fatal to original logger" do
      expect(original_logger).to receive(:fatal).with("Test message")
      bridge.fatal("Test message")
    end
  end

  describe "per-severity tracking configuration" do
    let(:debug_class) { class_double("E11y::Events::Rails::Log::Debug") }
    let(:info_class) { class_double("E11y::Events::Rails::Log::Info") }
    let(:warn_class) { class_double("E11y::Events::Rails::Log::Warn") }
    let(:error_class) { class_double("E11y::Events::Rails::Log::Error") }
    let(:fatal_class) { class_double("E11y::Events::Rails::Log::Fatal") }

    before do
      stub_const("E11y::Events::Rails::Log::Debug", debug_class)
      stub_const("E11y::Events::Rails::Log::Info", info_class)
      stub_const("E11y::Events::Rails::Log::Warn", warn_class)
      stub_const("E11y::Events::Rails::Log::Error", error_class)
      stub_const("E11y::Events::Rails::Log::Fatal", fatal_class)

      allow(original_logger).to receive(:debug)
      allow(original_logger).to receive(:info)
      allow(original_logger).to receive(:warn)
      allow(original_logger).to receive(:error)
      allow(original_logger).to receive(:fatal)
    end

    context "when track_to_e11y is true (all severities)" do
      before do
        allow(E11y).to receive(:config).and_return(
          double(logger_bridge: double(track_to_e11y: true))
        )
      end

      it "tracks all severity levels using specific classes" do
        expect(debug_class).to receive(:track).with(hash_including(message: "Debug"))
        bridge.debug("Debug")

        expect(info_class).to receive(:track).with(hash_including(message: "Info"))
        bridge.info("Info")

        expect(error_class).to receive(:track).with(hash_including(message: "Error"))
        bridge.error("Error")
      end
    end

    context "when track_to_e11y is false (none)" do
      before do
        allow(E11y).to receive(:config).and_return(
          double(logger_bridge: double(track_to_e11y: false))
        )
      end

      it "does not track any severity" do
        expect(debug_class).not_to receive(:track)
        expect(info_class).not_to receive(:track)
        expect(error_class).not_to receive(:track)

        bridge.debug("Debug")
        bridge.info("Info")
        bridge.error("Error")
      end
    end

    context "when track_to_e11y is Hash (per-severity config)" do
      before do
        allow(E11y).to receive(:config).and_return(
          double(
            logger_bridge: double(
              track_to_e11y: {
                debug: false,
                info: true,
                warn: true,
                error: true,
                fatal: true
              }
            )
          )
        )
      end

      it "tracks only enabled severities" do
        # Debug is disabled
        expect(debug_class).not_to receive(:track)
        bridge.debug("Debug")

        # Info is enabled
        expect(info_class).to receive(:track).with(hash_including(message: "Info"))
        bridge.info("Info")

        # Error is enabled
        expect(error_class).to receive(:track).with(hash_including(message: "Error"))
        bridge.error("Error")
      end
    end

    context "when track_to_e11y is Hash with only errors" do
      before do
        allow(E11y).to receive(:config).and_return(
          double(
            logger_bridge: double(
              track_to_e11y: {
                error: true,
                fatal: true
              }
            )
          )
        )
      end

      it "tracks only errors and fatal" do
        # Info/warn/debug are not in config -> not tracked
        expect(info_class).not_to receive(:track)
        bridge.info("Info")

        # Error is enabled
        expect(error_class).to receive(:track).with(hash_including(message: "Error"))
        bridge.error("Error")

        # Fatal is enabled
        expect(fatal_class).to receive(:track).with(hash_including(message: "Fatal"))
        bridge.fatal("Fatal")
      end
    end
  end

  describe "error handling" do
    before do
      allow(E11y).to receive(:config).and_return(
        double(logger_bridge: double(track_to_e11y: true))
      )
      allow(original_logger).to receive(:info)
    end

    it "does not break original logging if E11y tracking fails" do
      stub_const("E11y::Events::Rails::Log", class_double("E11y::Events::Rails::Log"))
      allow(E11y::Events::Rails::Log).to receive(:track).and_raise(StandardError, "E11y error")

      # Should not raise, only warn
      expect { bridge.info("Test") }.not_to raise_error

      # Original logger should still be called
      expect(original_logger).to have_received(:info).with("Test")
    end
  end
end
