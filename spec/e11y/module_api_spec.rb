# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y, "module API" do
  before { described_class.reset! }
  after  { described_class.reset! }

  # ---------------------------------------------------------------------------
  # .start!
  # ---------------------------------------------------------------------------
  describe ".start!" do
    context "when E11y is enabled (default)" do
      before { described_class.configure { |c| c.enabled = true } }

      it "returns without error when no adapters are configured" do
        expect { described_class.start! }.not_to raise_error
      end

      it "calls start! on adapters that respond to it" do
        # Use plain double — start! is a duck-typed optional method, not in Adapters::Base interface
        adapter = double("adapter", start!: nil)
        allow(adapter).to receive(:respond_to?).with(:start!).and_return(true)
        described_class.configure { |c| c.adapters[:logs] = adapter }

        described_class.start!

        expect(adapter).to have_received(:start!)
      end

      it "skips adapters that do not respond to start!" do
        adapter = double("adapter")
        allow(adapter).to receive(:respond_to?).with(:start!).and_return(false)
        described_class.configure { |c| c.adapters[:logs] = adapter }

        expect { described_class.start! }.not_to raise_error
      end

      it "logs a started message" do
        allow(described_class.logger).to receive(:info)
        described_class.start!
        expect(described_class.logger).to have_received(:info).with(/\[E11y\] Started/)
      end
    end

    context "when E11y is disabled" do
      before { described_class.configure { |c| c.enabled = false } }

      it "returns immediately without calling adapters" do
        adapter = double("adapter", start!: nil)
        allow(adapter).to receive(:respond_to?).and_return(true)
        described_class.configure { |c| c.adapters[:logs] = adapter }

        described_class.start!

        expect(adapter).not_to have_received(:start!)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # .stop!
  # ---------------------------------------------------------------------------
  describe ".stop!" do
    it "calls stop!(timeout:) on adapters that respond to it" do
      adapter = double("adapter")
      allow(adapter).to receive(:respond_to?).with(:stop!).and_return(true)
      allow(adapter).to receive(:stop!)
      described_class.configure { |c| c.adapters[:logs] = adapter }

      described_class.stop!(timeout: 3)

      expect(adapter).to have_received(:stop!).with(timeout: 3)
    end

    it "wraps flush! in Timeout when adapter has flush! but not stop!" do
      adapter = double("adapter")
      allow(adapter).to receive(:respond_to?).with(:stop!).and_return(false)
      allow(adapter).to receive(:respond_to?).with(:flush!).and_return(true)
      allow(adapter).to receive(:flush!)
      described_class.configure { |c| c.adapters[:logs] = adapter }

      described_class.stop!(timeout: 5)

      expect(adapter).to have_received(:flush!)
    end

    it "rescues StandardError from a failing adapter and warns" do
      adapter = double("adapter")
      allow(adapter).to receive(:respond_to?).with(:stop!).and_return(true)
      allow(adapter).to receive(:stop!).and_raise(StandardError, "boom")
      described_class.configure { |c| c.adapters[:logs] = adapter }
      allow(described_class.logger).to receive(:warn)
      allow(described_class.logger).to receive(:info)

      expect { described_class.stop! }.not_to raise_error
      expect(described_class.logger).to have_received(:warn).with(/Adapter stop error: boom/)
    end

    it "logs a stopped message" do
      allow(described_class.logger).to receive(:info)
      described_class.stop!
      expect(described_class.logger).to have_received(:info).with(/\[E11y\] Stopped/)
    end

    it "uses default timeout of 5 when not specified" do
      adapter = double("adapter")
      allow(adapter).to receive(:respond_to?).with(:stop!).and_return(true)
      allow(adapter).to receive(:stop!)
      described_class.configure { |c| c.adapters[:logs] = adapter }

      described_class.stop!

      expect(adapter).to have_received(:stop!).with(timeout: 5)
    end
  end

  # ---------------------------------------------------------------------------
  # .enabled_for?
  # ---------------------------------------------------------------------------
  describe ".enabled_for?" do
    context "when E11y is disabled" do
      before { described_class.configure { |c| c.enabled = false } }

      it "returns false regardless of severity" do
        expect(described_class.enabled_for?(:info)).to be(false)
        expect(described_class.enabled_for?(:error)).to be(false)
      end
    end

    context "when E11y is enabled" do
      before { described_class.configure { |c| c.enabled = true } }

      it "returns false when no adapters are registered" do
        expect(described_class.enabled_for?(:info)).to be(false)
      end

      it "returns true when a healthy adapter is registered for the severity" do
        adapter = instance_double(E11y::Adapters::Base, healthy?: true)
        described_class.configure { |c| c.adapters[:logs] = adapter }

        expect(described_class.enabled_for?(:info)).to be(true)
      end

      it "returns false when the matched adapter is unhealthy" do
        adapter = instance_double(E11y::Adapters::Base, healthy?: false)
        described_class.configure { |c| c.adapters[:logs] = adapter }

        expect(described_class.enabled_for?(:info)).to be(false)
      end

      it "returns false when adapter is registered but not under mapped name" do
        adapter = instance_double(E11y::Adapters::Base, healthy?: true)
        described_class.configure { |c| c.adapters[:unrelated] = adapter }

        expect(described_class.enabled_for?(:info)).to be(false)
      end

      it "returns false and does not raise when adapter.healthy? raises" do
        adapter = instance_double(E11y::Adapters::Base)
        allow(adapter).to receive(:healthy?).and_raise(RuntimeError, "network down")
        described_class.configure { |c| c.adapters[:logs] = adapter }

        expect(described_class.enabled_for?(:info)).to be(false)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # .buffer_size
  # ---------------------------------------------------------------------------
  describe ".buffer_size" do
    after { Thread.current[:e11y_request_buffer] = nil }

    it "returns 0 when no buffer is set" do
      Thread.current[:e11y_request_buffer] = nil
      expect(described_class.buffer_size).to eq(0)
    end

    it "returns 0 when buffer does not respond to size" do
      Thread.current[:e11y_request_buffer] = Object.new
      expect(described_class.buffer_size).to eq(0)
    end

    it "returns the size of the buffer when it responds to size" do
      Thread.current[:e11y_request_buffer] = [1, 2, 3]
      expect(described_class.buffer_size).to eq(3)
    end

    it "reflects changes to the buffer in real time" do
      buffer = []
      Thread.current[:e11y_request_buffer] = buffer
      expect(described_class.buffer_size).to eq(0)
      buffer << "event1"
      expect(described_class.buffer_size).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  # .circuit_breaker_state
  # ---------------------------------------------------------------------------
  describe ".circuit_breaker_state" do
    it "returns an empty hash when no adapters are configured" do
      expect(described_class.circuit_breaker_state).to eq({})
    end

    it "returns :closed for adapters without a circuit breaker" do
      adapter = instance_double(E11y::Adapters::Base)
      allow(adapter).to receive(:respond_to?).with(:circuit_breaker_state).and_return(false)
      described_class.configure { |c| c.adapters[:logs] = adapter }

      expect(described_class.circuit_breaker_state).to eq(logs: :closed)
    end

    it "returns the adapter circuit breaker state when available" do
      adapter = double("adapter")
      allow(adapter).to receive(:respond_to?).with(:circuit_breaker_state).and_return(true)
      allow(adapter).to receive(:circuit_breaker_state).and_return(:open)
      described_class.configure { |c| c.adapters[:logs] = adapter }

      expect(described_class.circuit_breaker_state).to eq(logs: :open)
    end

    it "maps multiple adapters individually" do
      healthy_adapter = double("adapter")
      allow(healthy_adapter).to receive(:respond_to?).with(:circuit_breaker_state).and_return(true)
      allow(healthy_adapter).to receive(:circuit_breaker_state).and_return(:closed)

      degraded_adapter = double("adapter")
      allow(degraded_adapter).to receive(:respond_to?).with(:circuit_breaker_state).and_return(true)
      allow(degraded_adapter).to receive(:circuit_breaker_state).and_return(:half_open)

      described_class.configure do |c|
        c.adapters[:logs] = healthy_adapter
        c.adapters[:errors_tracker] = degraded_adapter
      end

      result = described_class.circuit_breaker_state
      expect(result[:logs]).to eq(:closed)
      expect(result[:errors_tracker]).to eq(:half_open)
    end
  end
end
