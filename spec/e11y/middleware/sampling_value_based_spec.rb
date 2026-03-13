# frozen_string_literal: true

require "spec_helper"
require "e11y/middleware/sampling"

# rubocop:disable RSpec/SpecFilePathFormat, RSpec/DescribeMethod
# Feature test suite grouped by functionality, not class structure.
RSpec.describe E11y::Middleware::Sampling, "Value-Based Sampling (FEAT-4849)" do
  let(:app) { ->(event_data) { event_data } }
  let(:middleware) do
    instance = described_class.new
    instance.instance_variable_set(:@app, app)
    instance
  end

  # Test event with value-based sampling config
  let(:payment_event_class) do
    Class.new(E11y::Event::Base) do
      def self.name
        "PaymentEvent"
      end

      def self.event_name
        "payment.processed"
      end

      sample_by_value :amount, greater_than: 1000
    end
  end

  let(:order_event_class) do
    Class.new(E11y::Event::Base) do
      def self.name
        "OrderEvent"
      end

      def self.event_name
        "order.placed"
      end

      sample_by_value :total, in_range: 100..500
    end
  end

  describe "high-value event sampling" do
    it "always samples events matching value criteria" do
      high_value_payment = {
        event_name: "payment.processed",
        event_class: payment_event_class,
        amount: 5000 # > 1000
      }

      result = middleware.call(high_value_payment)
      expect(result).not_to be_nil
      expect(result[:sampled]).to be true
    end

    it "applies normal sampling for low-value events" do
      allow(middleware).to receive(:rand).and_return(0.99) # Will drop if rate < 1.0

      low_value_payment = {
        event_name: "payment.processed",
        event_class: payment_event_class,
        amount: 50 # < 1000
      }

      result = middleware.call(low_value_payment)
      expect(result).to be_nil # Dropped by normal sampling
    end
  end

  describe "range-based sampling" do
    it "samples events within configured range" do
      in_range_order = {
        event_name: "order.placed",
        event_class: order_event_class,
        total: 250 # In range 100..500
      }

      result = middleware.call(in_range_order)
      expect(result).not_to be_nil
      expect(result[:sampled]).to be true
    end

    it "applies normal sampling for events outside range" do
      allow(middleware).to receive(:rand).and_return(0.99)

      out_of_range_order = {
        event_name: "order.placed",
        event_class: order_event_class,
        total: 600 # > 500
      }

      result = middleware.call(out_of_range_order)
      expect(result).to be_nil
    end
  end

  describe "interaction with other sampling strategies" do
    it "error spike takes precedence over value-based sampling" do
      middleware_with_error = described_class.new(error_based_adaptive: true)
      middleware_with_error.instance_variable_set(:@app, app)

      detector = middleware_with_error.instance_variable_get(:@error_spike_detector)

      # Simulate error spike
      200.times do
        detector.record_event(event_name: "test.error", severity: :error)
      end

      expect(detector.error_spike?).to be true

      # Even low-value event should be sampled during spike
      low_value = {
        event_name: "payment.processed",
        event_class: payment_event_class,
        amount: 10
      }

      result = middleware_with_error.call(low_value)
      expect(result).not_to be_nil
      expect(result[:sampled]).to be true
    end

    it "value-based sampling works with load-based adaptive" do
      middleware_with_load = described_class.new(load_based_adaptive: true)
      middleware_with_load.instance_variable_set(:@app, app)

      # High-value event should still be sampled regardless of load
      high_value = {
        event_name: "payment.processed",
        event_class: payment_event_class,
        amount: 2000
      }

      result = middleware_with_load.call(high_value)
      expect(result).not_to be_nil
      expect(result[:sampled]).to be true
    end
  end

  describe "ADR-009 §3.4 compliance" do
    it "prioritizes high-value business events" do
      # High-value payment (e.g., enterprise customer)
      enterprise_payment = {
        event_name: "payment.processed",
        event_class: payment_event_class,
        amount: 10_000
      }

      result = middleware.call(enterprise_payment)
      expect(result).not_to be_nil
      expect(result[:sample_rate]).to eq(1.0)
    end
  end

  describe "without value-based config" do
    let(:regular_event_class) do
      Class.new(E11y::Event::Base) do
        def self.name
          "RegularEvent"
        end

        def self.event_name
          "regular.event"
        end
      end
    end

    it "falls back to normal sampling" do
      event_data = {
        event_name: "regular.event",
        event_class: regular_event_class,
        amount: 5000 # Has amount but no value_sampling_config
      }

      # Should use default sampling (not value-based)
      sample_rate = middleware.send(:determine_sample_rate, regular_event_class, event_data)
      expect(sample_rate).to eq(0.1) # Default rate
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat, RSpec/DescribeMethod
