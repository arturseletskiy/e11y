# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Metrics do
  before do
    # Reset backend before each test
    described_class.reset_backend!
  end

  after do
    # Reset backend after each test
    described_class.reset_backend!
  end

  describe ".increment" do
    context "when no backend is configured" do
      it "does not raise an error (noop)" do
        expect { described_class.increment(:test_counter, { foo: :bar }) }.not_to raise_error
      end
    end

    context "when Yabeda backend is configured" do
      let(:yabeda_adapter) { double("YabedaAdapter") }

      before do
        allow(E11y.config.adapters).to receive(:values).and_return([yabeda_adapter])
        allow(yabeda_adapter).to receive(:class).and_return(double(name: "E11y::Adapters::Yabeda"))
      end

      it "delegates to Yabeda adapter" do
        expect(yabeda_adapter).to receive(:increment).with(:test_counter, { foo: :bar }, value: 1)
        described_class.increment(:test_counter, { foo: :bar })
      end

      it "passes custom value" do
        expect(yabeda_adapter).to receive(:increment).with(:test_counter, { foo: :bar }, value: 5)
        described_class.increment(:test_counter, { foo: :bar }, value: 5)
      end
    end
  end

  describe ".histogram" do
    context "when no backend is configured" do
      it "does not raise an error (noop)" do
        expect { described_class.histogram(:test_histogram, 0.042, { foo: :bar }) }.not_to raise_error
      end
    end

    context "when Yabeda backend is configured" do
      let(:yabeda_adapter) { double("YabedaAdapter") }

      before do
        allow(E11y.config.adapters).to receive(:values).and_return([yabeda_adapter])
        allow(yabeda_adapter).to receive(:class).and_return(double(name: "E11y::Adapters::Yabeda"))
      end

      it "delegates to Yabeda adapter" do
        expect(yabeda_adapter).to receive(:histogram).with(:test_histogram, 0.042, { foo: :bar }, buckets: nil)
        described_class.histogram(:test_histogram, 0.042, { foo: :bar })
      end

      it "passes custom buckets" do
        buckets = [0.001, 0.01, 0.1, 1.0]
        expect(yabeda_adapter).to receive(:histogram).with(:test_histogram, 0.042, { foo: :bar }, buckets: buckets)
        described_class.histogram(:test_histogram, 0.042, { foo: :bar }, buckets: buckets)
      end
    end
  end

  describe ".gauge" do
    context "when no backend is configured" do
      it "does not raise an error (noop)" do
        expect { described_class.gauge(:test_gauge, 42, { foo: :bar }) }.not_to raise_error
      end
    end

    context "when Yabeda backend is configured" do
      let(:yabeda_adapter) { double("YabedaAdapter") }

      before do
        allow(E11y.config.adapters).to receive(:values).and_return([yabeda_adapter])
        allow(yabeda_adapter).to receive(:class).and_return(double(name: "E11y::Adapters::Yabeda"))
      end

      it "delegates to Yabeda adapter" do
        expect(yabeda_adapter).to receive(:gauge).with(:test_gauge, 42, { foo: :bar })
        described_class.gauge(:test_gauge, 42, { foo: :bar })
      end
    end
  end

  describe ".backend" do
    context "when no adapters are configured" do
      it "returns nil" do
        allow(E11y.config.adapters).to receive(:values).and_return([])
        expect(described_class.backend).to be_nil
      end
    end

    context "when Yabeda adapter is configured" do
      let(:yabeda_adapter) { double("YabedaAdapter") }
      let(:other_adapter) { double("StdoutAdapter") }

      before do
        allow(E11y.config.adapters).to receive(:values).and_return([other_adapter, yabeda_adapter])
        allow(yabeda_adapter).to receive(:class).and_return(double(name: "E11y::Adapters::Yabeda"))
        allow(other_adapter).to receive(:class).and_return(double(name: "E11y::Adapters::Stdout"))
      end

      it "returns Yabeda adapter" do
        expect(described_class.backend).to eq(yabeda_adapter)
      end

      it "caches the backend" do
        expect(E11y.config.adapters).to receive(:values).once.and_return([yabeda_adapter])
        allow(yabeda_adapter).to receive(:class).and_return(double(name: "E11y::Adapters::Yabeda"))

        described_class.backend
        described_class.backend # Second call should use cached value
      end
    end
  end

  describe ".reset_backend!" do
    it "clears the cached backend" do
      yabeda_adapter = double("YabedaAdapter")
      allow(E11y.config.adapters).to receive(:values).and_return([yabeda_adapter])
      allow(yabeda_adapter).to receive(:class).and_return(double(name: "E11y::Adapters::Yabeda"))

      # First call caches backend
      expect(described_class.backend).to eq(yabeda_adapter)

      # Reset
      described_class.reset_backend!

      # Next call should re-detect backend
      expect(E11y.config.adapters).to receive(:values).and_return([])
      expect(described_class.backend).to be_nil
    end
  end
end
