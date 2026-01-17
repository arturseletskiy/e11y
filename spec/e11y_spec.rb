# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y do
  it "has a version number" do
    expect(E11y::VERSION).not_to be_nil
    expect(E11y::VERSION).to match(/\d+\.\d+\.\d+/)
  end

  describe ".configure" do
    it "yields configuration" do
      expect { |b| described_class.configure(&b) }.to yield_with_args(E11y::Configuration)
    end

    it "returns configuration" do
      config = nil
      described_class.configure { |c| config = c }
      expect(config).to be_a(E11y::Configuration)
    end
  end

  describe ".configuration" do
    it "returns configuration instance" do
      expect(described_class.configuration).to be_a(E11y::Configuration)
    end

    it "returns same instance on multiple calls" do
      config1 = described_class.configuration
      config2 = described_class.configuration
      expect(config1).to equal(config2)
    end
  end

  describe ".track" do
    it "raises NotImplementedError" do
      expect { described_class.track(double("event")) }.to raise_error(NotImplementedError, /Phase 1/)
    end
  end

  describe ".logger" do
    it "returns logger instance" do
      expect(described_class.logger).to respond_to(:info)
      expect(described_class.logger).to respond_to(:error)
    end
  end

  describe ".reset!" do
    it "resets configuration" do
      described_class.configure { |c| c.log_level = :debug }
      expect { described_class.reset! }.to change { described_class.configuration.log_level }
        .from(:debug).to(:info)
    end
  end
end
