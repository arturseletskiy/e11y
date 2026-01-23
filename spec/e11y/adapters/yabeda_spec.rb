# frozen_string_literal: true

require "spec_helper"

# Unit tests for Yabeda adapter (without real Yabeda gem)
RSpec.describe E11y::Adapters::Yabeda do
  # Skip if Yabeda not available
  begin
    require "yabeda"
  rescue LoadError
    skip "Yabeda gem not available"
  end

  let(:registry) { E11y::Metrics::Registry.instance }
  let(:adapter) { described_class.new(auto_register: false) }

  before do
    # Mock Yabeda
    allow(Yabeda).to receive(:configured?).and_return(true)
    allow(Yabeda).to receive(:configure!).and_return(true)
    allow(Yabeda).to receive(:configure).and_yield
    
    # Clear registry
    registry.clear!
  end

  after do
    registry.clear!
  end

  describe "#initialize" do
    it "initializes with default config" do
      expect { described_class.new }.not_to raise_error
    end

    it "accepts cardinality_limit option" do
      adapter = described_class.new(cardinality_limit: 500)
      expect(adapter.instance_variable_get(:@cardinality_protection)).to be_a(E11y::Metrics::CardinalityProtection)
    end

    it "accepts forbidden_labels option" do
      adapter = described_class.new(forbidden_labels: [:user_id])
      expect(adapter.instance_variable_get(:@cardinality_protection)).to be_a(E11y::Metrics::CardinalityProtection)
    end

    it "accepts overflow_strategy option" do
      adapter = described_class.new(overflow_strategy: :alert)
      expect(adapter.instance_variable_get(:@cardinality_protection)).to be_a(E11y::Metrics::CardinalityProtection)
    end

    it "auto-registers metrics by default" do
      registry.register(type: :counter, pattern: "test.*", name: :test_counter, tags: [])
      
      expect_any_instance_of(described_class).to receive(:register_metrics_from_registry!)
      described_class.new(auto_register: true)
    end

    it "skips auto-registration when disabled" do
      expect_any_instance_of(described_class).not_to receive(:register_metrics_from_registry!)
      described_class.new(auto_register: false)
    end
  end

  describe "#write" do
    let(:yabeda_group) { double("YabedaGroup") }
    let(:yabeda_metric) { double("YabedaMetric", increment: true, measure: true, set: true) }

    before do
      allow(Yabeda).to receive(:e11y).and_return(yabeda_group)
      allow(yabeda_group).to receive(:orders_total).and_return(yabeda_metric)
      
      registry.register(
        type: :counter,
        pattern: "order.*",
        name: :orders_total,
        tags: [:status]
      )
    end

    it "writes event and updates matching metrics" do
      event = { event_name: "order.created", status: "paid" }
      
      expect(yabeda_metric).to receive(:increment).with({ status: "paid" })
      expect(adapter.write(event)).to be true
    end

    it "returns false on error" do
      event = { event_name: "order.created", status: "paid" }
      
      allow(registry).to receive(:find_matching).and_raise(StandardError, "Test error")
      expect(adapter.write(event)).to be false
    end

    it "warns on error" do
      event = { event_name: "order.created", status: "paid" }
      
      allow(registry).to receive(:find_matching).and_raise(StandardError, "Test error")
      expect { adapter.write(event) }.to output(/Yabeda adapter error/).to_stderr
    end
  end

  describe "#write_batch" do
    it "writes multiple events" do
      events = [
        { event_name: "test.1" },
        { event_name: "test.2" }
      ]
      
      expect(adapter).to receive(:write).twice
      expect(adapter.write_batch(events)).to be true
    end

    it "returns false on error" do
      allow(adapter).to receive(:write).and_raise(StandardError)
      expect(adapter.write_batch([{}])).to be false
    end
  end

  describe "#healthy?" do
    it "returns true when Yabeda is configured" do
      allow(Yabeda).to receive(:configured?).and_return(true)
      expect(adapter.healthy?).to be true
    end

    it "returns false when Yabeda is not configured" do
      allow(Yabeda).to receive(:configured?).and_return(false)
      expect(adapter.healthy?).to be false
    end

    it "returns false on error" do
      allow(Yabeda).to receive(:configured?).and_raise(StandardError)
      expect(adapter.healthy?).to be false
    end
  end

  describe "#close" do
    it "does nothing (no-op for Yabeda)" do
      expect { adapter.close }.not_to raise_error
    end
  end

  describe "#capabilities" do
    it "returns capabilities hash" do
      caps = adapter.capabilities
      expect(caps).to be_a(Hash)
      expect(caps[:batch]).to be true
      expect(caps[:async]).to be false
      expect(caps[:filtering]).to be false
      expect(caps[:metrics]).to be true
    end
  end

  describe "#increment" do
    let(:yabeda_group) { double("YabedaGroup") }
    let(:yabeda_metric) { double("YabedaMetric") }

    before do
      allow(Yabeda).to receive(:e11y).and_return(yabeda_group)
      allow(Yabeda).to receive(:metrics).and_return({})
      allow(yabeda_group).to receive(:test_counter).and_return(yabeda_metric)
      allow(adapter).to receive(:register_metric_if_needed)
    end

    it "increments counter metric" do
      expect(yabeda_metric).to receive(:increment).with({}, by: 1)
      adapter.increment(:test_counter)
    end

    it "increments with labels" do
      expect(yabeda_metric).to receive(:increment).with({ status: "success" }, by: 1)
      adapter.increment(:test_counter, { status: "success" })
    end

    it "increments with custom value" do
      expect(yabeda_metric).to receive(:increment).with({}, by: 5)
      adapter.increment(:test_counter, {}, value: 5)
    end

    it "applies cardinality protection" do
      expect(adapter.instance_variable_get(:@cardinality_protection)).to receive(:filter).and_return({})
      expect(yabeda_metric).to receive(:increment).with({}, by: 1)
      adapter.increment(:test_counter, { user_id: 123 })
    end

    it "handles errors gracefully" do
      allow(yabeda_metric).to receive(:increment).and_raise(StandardError)
      expect { adapter.increment(:test_counter) }.not_to raise_error
    end
  end

  describe "#histogram" do
    let(:yabeda_group) { double("YabedaGroup") }
    let(:yabeda_metric) { double("YabedaMetric") }

    before do
      allow(Yabeda).to receive(:e11y).and_return(yabeda_group)
      allow(Yabeda).to receive(:metrics).and_return({})
      allow(yabeda_group).to receive(:request_duration).and_return(yabeda_metric)
      allow(adapter).to receive(:register_metric_if_needed)
    end

    it "observes histogram value" do
      expect(yabeda_metric).to receive(:measure).with({}, 0.5)
      adapter.histogram(:request_duration, 0.5)
    end

    it "observes with labels" do
      expect(yabeda_metric).to receive(:measure).with({ method: "GET" }, 1.2)
      adapter.histogram(:request_duration, 1.2, { method: "GET" })
    end

    it "accepts custom buckets" do
      expect(adapter).to receive(:register_metric_if_needed).with(
        :request_duration,
        :histogram,
        [],
        buckets: [0.1, 1.0, 10.0]
      )
      expect(yabeda_metric).to receive(:measure).with({}, 0.5)
      adapter.histogram(:request_duration, 0.5, {}, buckets: [0.1, 1.0, 10.0])
    end
  end

  describe "#gauge" do
    let(:yabeda_group) { double("YabedaGroup") }
    let(:yabeda_metric) { double("YabedaMetric") }

    before do
      allow(Yabeda).to receive(:e11y).and_return(yabeda_group)
      allow(Yabeda).to receive(:metrics).and_return({})
      allow(yabeda_group).to receive(:queue_size).and_return(yabeda_metric)
      allow(adapter).to receive(:register_metric_if_needed)
    end

    it "sets gauge value" do
      expect(yabeda_metric).to receive(:set).with({}, 42)
      adapter.gauge(:queue_size, 42)
    end

    it "sets with labels" do
      expect(yabeda_metric).to receive(:set).with({ queue: "default" }, 10)
      adapter.gauge(:queue_size, 10, { queue: "default" })
    end
  end

  describe "#validate_config!" do
    it "validates cardinality_limit type" do
      expect do
        described_class.new(cardinality_limit: "invalid")
      end.to raise_error(ArgumentError, /cardinality_limit must be an Integer/)
    end

    it "validates forbidden_labels type" do
      expect do
        described_class.new(forbidden_labels: "invalid")
      end.to raise_error(ArgumentError, /forbidden_labels must be an Array/)
    end

    it "accepts valid config" do
      expect do
        described_class.new(
          cardinality_limit: 1000,
          forbidden_labels: [:user_id]
        )
      end.not_to raise_error
    end
  end

  describe "#format_event" do
    it "returns event data unchanged" do
      event = { test: "data" }
      expect(adapter.format_event(event)).to eq(event)
    end
  end

  describe "#cardinality_stats" do
    it "returns cardinality statistics" do
      stats = adapter.cardinality_stats
      expect(stats).to be_a(Hash)
    end
  end

  describe "#reset_cardinality!" do
    it "resets cardinality tracking" do
      protection = adapter.instance_variable_get(:@cardinality_protection)
      expect(protection).to receive(:reset!)
      adapter.reset_cardinality!
    end
  end

  describe "private methods" do
    describe "#extract_labels" do
      it "extracts labels from event payload" do
        metric_config = { tags: [:status, :method] }
        event_data = { payload: { status: "success", method: "GET" } }
        
        labels = adapter.send(:extract_labels, metric_config, event_data)
        expect(labels).to eq({ status: "success", method: "GET" })
      end

      it "handles missing labels" do
        metric_config = { tags: [:status] }
        event_data = { payload: {} }
        
        labels = adapter.send(:extract_labels, metric_config, event_data)
        expect(labels).to eq({})
      end
    end

    describe "#extract_value" do
      it "extracts symbol value from payload" do
        metric_config = { value: :duration }
        event_data = { payload: { duration: 1.5 } }
        
        value = adapter.send(:extract_value, metric_config, event_data)
        expect(value).to eq(1.5)
      end

      it "extracts proc value" do
        metric_config = { value: ->(data) { data[:payload][:count] * 2 } }
        event_data = { payload: { count: 5 } }
        
        value = adapter.send(:extract_value, metric_config, event_data)
        expect(value).to eq(10)
      end

      it "returns 1 as default" do
        metric_config = { value: nil }
        event_data = {}
        
        value = adapter.send(:extract_value, metric_config, event_data)
        expect(value).to eq(1)
      end
    end
  end
end
