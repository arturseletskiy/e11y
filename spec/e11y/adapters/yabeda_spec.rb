# frozen_string_literal: true

require "spec_helper"

# Skip Yabeda tests if Yabeda not available
begin
  require "e11y/adapters/yabeda"
rescue LoadError
  RSpec.describe "E11y::Adapters::Yabeda (skipped)" do
    it "requires Yabeda to be available" do
      skip "Yabeda not available in test environment"
    end
  end

  return
end

RSpec.describe E11y::Adapters::Yabeda do
  let(:adapter) { described_class.new(auto_register: false) }
  let(:registry) { E11y::Metrics::Registry.instance }

  before do
    # Clear registry before each test
    registry.clear!

    # Mock Yabeda
    stub_const("Yabeda", Class.new do
      def self.configured?
        true
      end

      def self.configure(&)
        # No-op for tests
      end

      def self.e11y
        @e11y ||= YabedaGroup.new
      end

      class YabedaGroup
        def method_missing(method_name, *_args)
          YabedaMetric.new(method_name)
        end

        def respond_to_missing?(_method_name, _include_private = false)
          true
        end
      end

      class YabedaMetric
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def increment(labels = {})
          # No-op for tests
        end

        def observe(value, labels = {})
          # No-op for tests
        end

        def set(value, labels = {})
          # No-op for tests
        end
      end
    end)
  end

  describe "ADR-004 compliance" do
    describe "Section 3.1: Base Adapter Contract" do
      it "implements write method" do
        expect(adapter).to respond_to(:write)
      end

      it "implements write_batch method" do
        expect(adapter).to respond_to(:write_batch)
      end

      it "implements healthy? method" do
        expect(adapter).to respond_to(:healthy?)
      end

      it "implements close method" do
        expect(adapter).to respond_to(:close)
      end

      it "implements capabilities method" do
        expect(adapter).to respond_to(:capabilities)
      end

      it "implements validate_config! method" do
        expect(adapter).to respond_to(:validate_config!)
      end

      it "implements format_event method" do
        expect(adapter).to respond_to(:format_event)
      end
    end

    describe "write method" do
      it "returns Boolean" do
        event = { event_name: "test", payload: {} }
        result = adapter.write(event)
        expect(result).to be(true).or(be(false))
      end

      it "never raises exceptions" do
        expect { adapter.write(nil) }.not_to raise_error
        expect { adapter.write({}) }.not_to raise_error
        expect { adapter.write(invalid: "data") }.not_to raise_error
      end
    end

    describe "write_batch method" do
      it "returns Boolean" do
        events = [{ event_name: "test1" }, { event_name: "test2" }]
        result = adapter.write_batch(events)
        expect(result).to be(true).or(be(false))
      end

      it "never raises exceptions" do
        expect { adapter.write_batch(nil) }.not_to raise_error
        expect { adapter.write_batch([]) }.not_to raise_error
        expect { adapter.write_batch([nil, {}]) }.not_to raise_error
      end
    end

    describe "healthy? method" do
      it "returns Boolean" do
        result = adapter.healthy?
        expect(result).to be(true).or(be(false))
      end

      it "returns true when Yabeda is configured" do
        expect(adapter.healthy?).to be(true)
      end

      it "returns false when Yabeda is not defined" do
        hide_const("Yabeda")
        new_adapter = described_class.new(auto_register: false)
        expect(new_adapter.healthy?).to be(false)
      end
    end

    describe "capabilities method" do
      it "returns Hash with required keys" do
        caps = adapter.capabilities
        expect(caps).to be_a(Hash)
        expect(caps).to have_key(:batch)
        expect(caps).to have_key(:async)
        expect(caps).to have_key(:filtering)
      end

      it "indicates metrics support" do
        caps = adapter.capabilities
        expect(caps[:metrics]).to be(true)
      end
    end
  end

  describe "initialization" do
    it "initializes with default config" do
      adapter = described_class.new
      expect(adapter).to be_a(described_class)
    end

    it "initializes with custom cardinality limit" do
      adapter = described_class.new(cardinality_limit: 500, auto_register: false)
      expect(adapter).to be_a(described_class)
    end

    it "initializes with forbidden labels" do
      adapter = described_class.new(
        forbidden_labels: [:custom_id],
        auto_register: false
      )
      expect(adapter).to be_a(described_class)
    end

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
  end

  describe "#write" do
    before do
      registry.register(
        type: :counter,
        pattern: "order.*",
        name: :orders_total,
        tags: %i[currency status]
      )
    end

    it "updates matching metrics" do
      event = {
        event_name: "order.created",
        payload: { amount: 100 },
        currency: "USD",
        status: "pending"
      }

      metric = Yabeda.e11y.orders_total
      allow(Yabeda.e11y).to receive(:orders_total).and_return(metric)
      allow(metric).to receive(:increment)

      adapter.write(event)

      expect(metric).to have_received(:increment).with(hash_including(currency: "USD", status: "pending"))
    end

    it "applies cardinality protection" do
      # Register metric with cardinality limit
      adapter_with_limit = described_class.new(cardinality_limit: 2, auto_register: false)

      event_template = {
        event_name: "order.created",
        payload: {},
        status: "pending"
      }

      # First 2 unique currencies should work
      adapter_with_limit.write(event_template.merge(currency: "USD"))
      adapter_with_limit.write(event_template.merge(currency: "EUR"))

      # 3rd unique currency should be dropped (cardinality limit exceeded)
      expect do
        adapter_with_limit.write(event_template.merge(currency: "GBP"))
      end.to output(/Cardinality limit exceeded/).to_stderr
    end

    it "returns true on success" do
      event = { event_name: "order.created", payload: {} }
      expect(adapter.write(event)).to be(true)
    end

    it "returns false on error" do
      event = { event_name: "order.created", payload: {} }
      allow(registry).to receive(:find_matching).and_raise(StandardError)

      expect(adapter.write(event)).to be(false)
    end

    it "extracts labels from event data" do
      event = {
        event_name: "order.created",
        currency: "USD", # Top-level
        payload: { status: "pending" } # Nested in payload
      }

      metric = Yabeda.e11y.orders_total
      allow(Yabeda.e11y).to receive(:orders_total).and_return(metric)
      allow(metric).to receive(:increment)

      adapter.write(event)

      expect(metric).to have_received(:increment).with(hash_including(currency: "USD", status: "pending"))
    end
  end

  describe "#write_batch" do
    before do
      registry.register(
        type: :counter,
        pattern: "order.*",
        name: :orders_total,
        tags: [:status]
      )
    end

    it "processes all events in batch" do
      events = [
        { event_name: "order.created", status: "pending" },
        { event_name: "order.paid", status: "paid" }
      ]

      metric = Yabeda.e11y.orders_total
      allow(Yabeda.e11y).to receive(:orders_total).and_return(metric)
      allow(metric).to receive(:increment)

      adapter.write_batch(events)

      expect(metric).to have_received(:increment).twice
    end

    it "returns true on success" do
      events = [{ event_name: "order.created" }]
      expect(adapter.write_batch(events)).to be(true)
    end

    it "returns false on error" do
      events = [{ event_name: "order.created" }]
      allow(adapter).to receive(:write).and_raise(StandardError)

      expect(adapter.write_batch(events)).to be(false)
    end
  end

  describe "histogram metrics" do
    before do
      registry.register(
        type: :histogram,
        pattern: "order.paid",
        name: :order_amount,
        value: :amount,
        tags: [:currency]
      )
    end

    it "observes histogram values" do
      event = {
        event_name: "order.paid",
        payload: { amount: 99.99 },
        currency: "USD"
      }

      metric = Yabeda.e11y.order_amount
      allow(Yabeda.e11y).to receive(:order_amount).and_return(metric)
      allow(metric).to receive(:observe)

      adapter.write(event)

      expect(metric).to have_received(:observe).with(99.99, hash_including(currency: "USD"))
    end

    it "extracts value from payload" do
      event = {
        event_name: "order.paid",
        payload: { amount: 123.45 },
        currency: "EUR"
      }

      metric = Yabeda.e11y.order_amount
      allow(Yabeda.e11y).to receive(:order_amount).and_return(metric)
      allow(metric).to receive(:observe)

      adapter.write(event)

      expect(metric).to have_received(:observe).with(123.45, anything)
    end

    it "supports Proc value extractors" do
      registry.clear!
      registry.register(
        type: :histogram,
        pattern: "order.paid",
        name: :order_amount,
        value: ->(event) { event[:payload][:amount] * 2 },
        tags: [:currency]
      )

      event = {
        event_name: "order.paid",
        payload: { amount: 50 },
        currency: "USD"
      }

      metric = Yabeda.e11y.order_amount
      allow(Yabeda.e11y).to receive(:order_amount).and_return(metric)
      allow(metric).to receive(:observe)

      adapter.write(event)

      expect(metric).to have_received(:observe).with(100, anything)
    end
  end

  describe "gauge metrics" do
    before do
      registry.register(
        type: :gauge,
        pattern: "queue.*",
        name: :queue_depth,
        value: :size,
        tags: [:queue_name]
      )
    end

    it "sets gauge values" do
      event = {
        event_name: "queue.updated",
        payload: { size: 42 },
        queue_name: "default"
      }

      metric = Yabeda.e11y.queue_depth
      allow(Yabeda.e11y).to receive(:queue_depth).and_return(metric)
      allow(metric).to receive(:set)

      adapter.write(event)

      expect(metric).to have_received(:set).with(42, hash_including(queue_name: "default"))
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
      adapter.reset_cardinality!
      expect(adapter.cardinality_stats).to be_empty
    end
  end

  describe "#close" do
    it "closes adapter without errors" do
      expect { adapter.close }.not_to raise_error
    end
  end

  describe "#format_event" do
    it "returns event data unchanged" do
      event = { event_name: "test", payload: {} }
      expect(adapter.format_event(event)).to eq(event)
    end
  end

  describe "cardinality protection integration" do
    it "blocks forbidden labels" do
      event = {
        event_name: "order.created",
        user_id: 123, # Forbidden by default
        currency: "USD",
        status: "pending"
      }

      registry.register(
        type: :counter,
        pattern: "order.*",
        name: :orders_total,
        tags: %i[user_id currency status]
      )

      metric = Yabeda.e11y.orders_total
      allow(Yabeda.e11y).to receive(:orders_total).and_return(metric)
      allow(metric).to receive(:increment)

      adapter.write(event)

      # user_id should be filtered out
      expect(metric).to have_received(:increment).with(hash_excluding(:user_id))
    end
  end
end
