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

  describe E11y::Configuration do
    subject(:config) { described_class.new }

    describe "#adapter_mapping" do
      it "has default mapping with adapter names" do
        expect(config.adapter_mapping).to be_a(Hash)
        # Mapping uses adapter NAMES (not implementations)
        expect(config.adapter_mapping[:error]).to eq(%i[logs errors_tracker])
        expect(config.adapter_mapping[:fatal]).to eq(%i[logs errors_tracker])
        expect(config.adapter_mapping[:default]).to eq([:logs])
      end
    end

    describe "#adapters_for_severity" do
      it "returns adapter names for :error severity" do
        # Returns NAMES, not implementations
        expect(config.adapters_for_severity(:error)).to eq(%i[logs errors_tracker])
      end

      it "returns adapter names for :fatal severity" do
        expect(config.adapters_for_severity(:fatal)).to eq(%i[logs errors_tracker])
      end

      it "returns default adapter names for :info severity" do
        expect(config.adapters_for_severity(:info)).to eq([:logs])
      end

      it "returns default adapter names for :success severity" do
        expect(config.adapters_for_severity(:success)).to eq([:logs])
      end

      it "returns default adapter names for unknown severity" do
        expect(config.adapters_for_severity(:unknown)).to eq([:logs])
      end
    end

    describe "#adapters_for_severity with custom mapping" do
      before do
        # Custom mapping uses adapter NAMES
        config.adapter_mapping[:warn] = %i[logs errors_tracker]
        config.adapter_mapping[:default] = [:logs]
      end

      it "uses custom mapping for :warn" do
        expect(config.adapters_for_severity(:warn)).to eq(%i[logs errors_tracker])
      end

      it "uses custom default for unmapped severity" do
        expect(config.adapters_for_severity(:info)).to eq([:logs])
      end
    end
  end
end
