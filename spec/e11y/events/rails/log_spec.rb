# frozen_string_literal: true

require "spec_helper"
require "e11y/events/rails/log"

RSpec.describe E11y::Events::Rails::Log do
  describe "base class" do
    it "defines common schema for all log events" do
      # Base class has schema, but should not be used directly
      expect(described_class.compiled_schema).not_to be_nil
    end
  end

  describe E11y::Events::Rails::Log::Debug do
    it "has debug severity" do
      result = described_class.track(message: "Debug message")
      expect(result[:severity]).to eq(:debug)
    end

    it "uses :logs adapter" do
      result = described_class.track(message: "Debug message")
      expect(result[:adapters]).to eq([:logs])
    end

    it "allows optional caller_location" do
      result = described_class.track(
        message: "Debug",
        caller_location: "file.rb:10"
      )
      expect(result[:payload][:caller_location]).to eq("file.rb:10")
    end
  end

  describe E11y::Events::Rails::Log::Info do
    it "has info severity" do
      result = described_class.track(message: "Info message")
      expect(result[:severity]).to eq(:info)
    end

    it "uses :logs adapter" do
      result = described_class.track(message: "Info message")
      expect(result[:adapters]).to eq([:logs])
    end
  end

  describe E11y::Events::Rails::Log::Warn do
    it "has warn severity" do
      result = described_class.track(message: "Warn message")
      expect(result[:severity]).to eq(:warn)
    end

    it "uses :logs adapter" do
      result = described_class.track(message: "Warn message")
      expect(result[:adapters]).to eq([:logs])
    end
  end

  describe E11y::Events::Rails::Log::Error do
    it "has error severity" do
      result = described_class.track(message: "Error message")
      expect(result[:severity]).to eq(:error)
    end

    it "uses :logs + :errors_tracker adapters" do
      result = described_class.track(message: "Error message")
      expect(result[:adapters]).to eq(%i[logs errors_tracker])
    end
  end

  describe E11y::Events::Rails::Log::Fatal do
    it "has fatal severity" do
      result = described_class.track(message: "Fatal message")
      expect(result[:severity]).to eq(:fatal)
    end

    it "uses :logs + :errors_tracker adapters" do
      result = described_class.track(message: "Fatal message")
      expect(result[:adapters]).to eq(%i[logs errors_tracker])
    end
  end

  describe "inheritance" do
    it "all severity classes inherit from Log" do
      expect(E11y::Events::Rails::Log::Debug.superclass).to eq(E11y::Events::Rails::Log)
      expect(E11y::Events::Rails::Log::Info.superclass).to eq(E11y::Events::Rails::Log)
      expect(E11y::Events::Rails::Log::Warn.superclass).to eq(E11y::Events::Rails::Log)
      expect(E11y::Events::Rails::Log::Error.superclass).to eq(E11y::Events::Rails::Log)
      expect(E11y::Events::Rails::Log::Fatal.superclass).to eq(E11y::Events::Rails::Log)
    end
  end
end
