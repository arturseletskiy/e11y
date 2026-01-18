# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Metrics::Registry do
  # Use singleton instance
  let(:registry) { described_class.instance }

  # Clear registry before each test
  before { registry.clear! }

  describe "singleton pattern" do
    it "returns the same instance" do
      expect(described_class.instance).to be(described_class.instance)
    end

    it "raises error when trying to create new instance" do
      expect { described_class.new }.to raise_error(NoMethodError)
    end
  end

  describe "#register" do
    context "with valid configurations" do
      it "registers a counter metric" do
        registry.register(
          type: :counter,
          pattern: "order.*",
          name: :orders_total,
          tags: %i[status currency]
        )

        expect(registry.size).to eq(1)
      end

      it "registers a histogram metric" do
        registry.register(
          type: :histogram,
          pattern: "order.paid",
          name: :orders_amount,
          value: ->(e) { e[:payload][:amount] },
          tags: [:currency],
          buckets: [10, 50, 100, 500, 1000]
        )

        expect(registry.size).to eq(1)
      end

      it "registers a gauge metric" do
        registry.register(
          type: :gauge,
          pattern: "queue.*",
          name: :queue_size,
          value: :size,
          tags: [:queue_name]
        )

        expect(registry.size).to eq(1)
      end

      it "registers multiple metrics" do
        registry.register(
          type: :counter,
          pattern: "order.*",
          name: :orders_total,
          tags: [:status]
        )

        registry.register(
          type: :histogram,
          pattern: "order.paid",
          name: :orders_amount,
          value: :amount,
          tags: [:currency]
        )

        expect(registry.size).to eq(2)
      end
    end

    context "with validation errors" do
      it "raises error for missing type" do
        expect do
          registry.register(
            pattern: "order.*",
            name: :orders_total
          )
        end.to raise_error(ArgumentError, /type is required/)
      end

      it "raises error for invalid type" do
        expect do
          registry.register(
            type: :invalid,
            pattern: "order.*",
            name: :orders_total
          )
        end.to raise_error(ArgumentError, /Invalid metric type/)
      end

      it "raises error for missing pattern" do
        expect do
          registry.register(
            type: :counter,
            name: :orders_total
          )
        end.to raise_error(ArgumentError, /Pattern is required/)
      end

      it "raises error for missing name" do
        expect do
          registry.register(
            type: :counter,
            pattern: "order.*"
          )
        end.to raise_error(ArgumentError, /Metric name is required/)
      end

      it "raises error for histogram without value extractor" do
        expect do
          registry.register(
            type: :histogram,
            pattern: "order.paid",
            name: :orders_amount,
            tags: [:currency]
          )
        end.to raise_error(ArgumentError, /Value extractor is required/)
      end

      it "raises error for gauge without value extractor" do
        expect do
          registry.register(
            type: :gauge,
            pattern: "queue.*",
            name: :queue_size,
            tags: [:queue_name]
          )
        end.to raise_error(ArgumentError, /Value extractor is required/)
      end
    end

    context "with label conflicts" do
      it "raises LabelConflictError when same metric has different labels" do
        registry.register(
          type: :counter,
          pattern: "order.*",
          name: :orders_total,
          tags: %i[currency status],
          source: "Event1"
        )

        expect do
          registry.register(
            type: :counter,
            pattern: "order.paid",
            name: :orders_total,
            tags: [:currency], # Different labels!
            source: "Event2"
          )
        end.to raise_error(E11y::Metrics::Registry::LabelConflictError, /label conflict/)
      end

      it "allows same metric with same labels" do
        registry.register(
          type: :counter,
          pattern: "order.*",
          name: :orders_total,
          tags: %i[currency status]
        )

        expect do
          registry.register(
            type: :counter,
            pattern: "order.paid",
            name: :orders_total,
            tags: %i[currency status] # Same labels - OK!
          )
        end.not_to raise_error

        expect(registry.size).to eq(2) # Both registered
      end

      it "allows same metric with same labels in different order" do
        registry.register(
          type: :counter,
          pattern: "order.*",
          name: :orders_total,
          tags: %i[status currency]
        )

        expect do
          registry.register(
            type: :counter,
            pattern: "order.paid",
            name: :orders_total,
            tags: %i[currency status] # Same labels, different order - OK!
          )
        end.not_to raise_error
      end
    end

    context "with type conflicts" do
      it "raises TypeConflictError when same metric has different type" do
        registry.register(
          type: :counter,
          pattern: "order.*",
          name: :orders_total,
          tags: [:currency],
          source: "Event1"
        )

        expect do
          registry.register(
            type: :histogram, # Different type!
            pattern: "order.paid",
            name: :orders_total,
            value: :amount,
            tags: [:currency],
            source: "Event2"
          )
        end.to raise_error(E11y::Metrics::Registry::TypeConflictError, /type conflict/)
      end
    end

    context "with bucket conflicts" do
      it "warns when same histogram has different buckets" do
        registry.register(
          type: :histogram,
          pattern: "order.*",
          name: :orders_amount,
          value: :amount,
          tags: [:currency],
          buckets: [10, 50, 100]
        )

        expect do
          registry.register(
            type: :histogram,
            pattern: "order.paid",
            name: :orders_amount,
            value: :amount,
            tags: [:currency],
            buckets: [20, 100, 500] # Different buckets - warns but allows
          )
        end.to output(/different buckets/).to_stderr
      end
    end
  end

  describe "#find_matching" do
    before do
      registry.register(
        type: :counter,
        pattern: "order.*",
        name: :orders_total,
        tags: [:status]
      )

      registry.register(
        type: :counter,
        pattern: "order.paid",
        name: :orders_paid,
        tags: [:currency]
      )

      registry.register(
        type: :counter,
        pattern: "user.*",
        name: :users_total,
        tags: [:role]
      )
    end

    it "finds metrics matching exact pattern" do
      matches = registry.find_matching("order.paid")
      expect(matches.size).to eq(2) # Both "order.*" and "order.paid" match
      expect(matches.map { |m| m[:name] }).to contain_exactly(:orders_total, :orders_paid)
    end

    it "finds metrics matching wildcard pattern" do
      matches = registry.find_matching("order.created")
      expect(matches.size).to eq(1) # Only "order.*" matches
      expect(matches.first[:name]).to eq(:orders_total)
    end

    it "returns empty array for non-matching event" do
      matches = registry.find_matching("payment.received")
      expect(matches).to be_empty
    end

    it "handles double wildcard patterns" do
      registry.register(
        type: :counter,
        pattern: "order.**",
        name: :orders_all,
        tags: []
      )

      matches = registry.find_matching("order.paid.usd")
      expect(matches.map { |m| m[:name] }).to include(:orders_all)
    end
  end

  describe "#find_by_name" do
    before do
      registry.register(
        type: :counter,
        pattern: "order.*",
        name: :orders_total,
        tags: [:status]
      )
    end

    it "finds metric by name" do
      metric = registry.find_by_name(:orders_total)
      expect(metric).not_to be_nil
      expect(metric[:type]).to eq(:counter)
    end

    it "returns nil for non-existent metric" do
      metric = registry.find_by_name(:non_existent)
      expect(metric).to be_nil
    end
  end

  describe "#all" do
    it "returns all registered metrics" do
      registry.register(
        type: :counter,
        pattern: "order.*",
        name: :orders_total,
        tags: [:status]
      )

      registry.register(
        type: :histogram,
        pattern: "order.paid",
        name: :orders_amount,
        value: :amount,
        tags: [:currency]
      )

      all_metrics = registry.all
      expect(all_metrics.size).to eq(2)
      expect(all_metrics.map { |m| m[:name] }).to contain_exactly(:orders_total, :orders_amount)
    end

    it "returns empty array when no metrics registered" do
      expect(registry.all).to be_empty
    end
  end

  describe "#clear!" do
    it "removes all registered metrics" do
      registry.register(
        type: :counter,
        pattern: "order.*",
        name: :orders_total,
        tags: [:status]
      )

      expect(registry.size).to eq(1)

      registry.clear!

      expect(registry.size).to eq(0)
      expect(registry.all).to be_empty
    end
  end

  describe "#size" do
    it "returns count of registered metrics" do
      expect(registry.size).to eq(0)

      registry.register(
        type: :counter,
        pattern: "order.*",
        name: :orders_total,
        tags: [:status]
      )

      expect(registry.size).to eq(1)

      registry.register(
        type: :histogram,
        pattern: "order.paid",
        name: :orders_amount,
        value: :amount,
        tags: [:currency]
      )

      expect(registry.size).to eq(2)
    end
  end

  describe "thread safety" do
    it "handles concurrent registrations" do
      threads = 10.times.map do |i|
        Thread.new do
          registry.register(
            type: :counter,
            pattern: "event.#{i}",
            name: :"metric_#{i}",
            tags: []
          )
        end
      end

      threads.each(&:join)

      expect(registry.size).to eq(10)
    end
  end
end
