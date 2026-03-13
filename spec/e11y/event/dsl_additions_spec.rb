# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Event::Base do
  describe ".retention (alias for .retention_period)" do
    it "sets retention period via the retention alias" do
      event_class = Class.new(described_class) do
        def self.name = "RetentionAliasEvent"
        contains_pii false
        retention 7.years
      end

      expect(event_class.retention_period).to eq(7.years)
    end

    it "is an alias — both methods return the same value" do
      event_class = Class.new(described_class) do
        def self.name = "RetentionAliasEvent"
        contains_pii false
        retention 14.days
      end

      expect(event_class.retention).to eq(event_class.retention_period)
    end
  end

  describe ".rate_limit" do
    it "stores count and window" do
      event_class = Class.new(described_class) do
        def self.name = "RateLimitedEvent"
        contains_pii false
        rate_limit 100, window: 60
      end

      expect(event_class.rate_limit_config).to eq(count: 100, window: 60.0)
    end

    it "accepts ActiveSupport::Duration as window" do
      event_class = Class.new(described_class) do
        def self.name = "RateLimitedEvent"
        contains_pii false
        rate_limit 50, window: 1.minute
      end

      expect(event_class.rate_limit_config[:window]).to eq(60.0)
    end

    it "defaults window to 1.0 second" do
      event_class = Class.new(described_class) do
        def self.name = "RateLimitedEvent"
        contains_pii false
        rate_limit 200
      end

      expect(event_class.rate_limit_config).to eq(count: 200, window: 1.0)
    end

    it "returns nil count and window when not configured" do
      event_class = Class.new(described_class) do
        def self.name = "UnlimitedEvent"
        contains_pii false
      end

      expect(event_class.rate_limit_config).to eq(count: nil, window: nil)
    end
  end

  describe ".metric (single-call form)" do
    before { E11y::Metrics::Registry.instance.clear! }

    it "registers a counter via single-call form" do
      event_class = Class.new(described_class) do
        def self.name = "MetricSingleCallEvent"
        contains_pii false
        metric :counter, name: :items_processed_total, tags: [:status]
      end

      config = event_class.metrics_config.first
      expect(config[:type]).to eq(:counter)
      expect(config[:name]).to eq(:items_processed_total)
      expect(config[:tags]).to eq([:status])
    end

    it "registers a histogram via single-call form" do
      event_class = Class.new(described_class) do
        def self.name = "MetricSingleCallEvent"
        contains_pii false
        metric :histogram, name: :request_duration, value: :duration, buckets: [10, 50, 100]
      end

      config = event_class.metrics_config.first
      expect(config[:type]).to eq(:histogram)
      expect(config[:name]).to eq(:request_duration)
      expect(config[:value]).to eq(:duration)
    end

    it "raises ArgumentError for unknown metric type" do
      expect do
        Class.new(described_class) do
          def self.name = "BadMetricEvent"
          contains_pii false
          metric :unknown_type, name: :some_metric
        end
      end.to raise_error(ArgumentError, /Unknown metric type/)
    end
  end

  describe ".track with block (duration measurement)" do
    let(:event_class) do
      Class.new(described_class) do
        def self.name = "BlockTrackEvent"
        contains_pii false
        adapters :stdout
      end
    end

    it "returns the block's return value" do
      result = event_class.track(user_id: 1) { 42 }
      expect(result).to eq(42)
    end

    it "adds duration_ms to the tracked payload" do
      tracked_data = nil
      allow(E11y.config.built_pipeline).to receive(:call) { |data| tracked_data = data }

      event_class.track(user_id: 1) { "work done" }

      expect(tracked_data[:payload]).to include(:duration_ms)
      expect(tracked_data[:payload][:duration_ms]).to be_a(Numeric)
      expect(tracked_data[:payload][:duration_ms]).to be >= 0
    end

    it "merges duration_ms with existing payload keys" do
      tracked_data = nil
      allow(E11y.config.built_pipeline).to receive(:call) { |data| tracked_data = data }

      event_class.track(order_id: 99) { "done" }

      expect(tracked_data[:payload]).to include(order_id: 99, duration_ms: anything)
    end

    it "without block behaves identically to original track" do
      tracked_data = nil
      allow(E11y.config.built_pipeline).to receive(:call) { |data| tracked_data = data }

      event_class.track(foo: "bar")

      expect(tracked_data[:payload]).to eq(foo: "bar")
      expect(tracked_data[:payload]).not_to include(:duration_ms)
    end
  end
end
