# frozen_string_literal: true

require "spec_helper"

RSpec.describe "E11y::Event::Base Metrics DSL" do
  let(:registry) { E11y::Metrics::Registry.instance }

  before do
    # Clear registry before each test
    registry.clear!
  end

  describe "metrics DSL" do
    it "defines counter metrics" do
      event_class = Class.new(E11y::Event::Base) do
        def self.name
          "TestEvent"
        end

        metrics do
          counter :test_counter, tags: [:status]
        end
      end

      expect(event_class.metrics_config.size).to eq(1)
      expect(event_class.metrics_config.first[:type]).to eq(:counter)
      expect(event_class.metrics_config.first[:name]).to eq(:test_counter)
      expect(event_class.metrics_config.first[:tags]).to eq([:status])
    end

    it "defines histogram metrics" do
      event_class = Class.new(E11y::Event::Base) do
        def self.name
          "TestEvent"
        end

        metrics do
          histogram :test_histogram,
                    value: :amount,
                    tags: [:currency],
                    buckets: [10, 50, 100]
        end
      end

      config = event_class.metrics_config.first
      expect(config[:type]).to eq(:histogram)
      expect(config[:name]).to eq(:test_histogram)
      expect(config[:value]).to eq(:amount)
      expect(config[:tags]).to eq([:currency])
      expect(config[:buckets]).to eq([10, 50, 100])
    end

    it "defines gauge metrics" do
      event_class = Class.new(E11y::Event::Base) do
        def self.name
          "TestEvent"
        end

        metrics do
          gauge :test_gauge, value: :size, tags: [:queue_name]
        end
      end

      config = event_class.metrics_config.first
      expect(config[:type]).to eq(:gauge)
      expect(config[:name]).to eq(:test_gauge)
      expect(config[:value]).to eq(:size)
      expect(config[:tags]).to eq([:queue_name])
    end

    it "defines multiple metrics" do
      event_class = Class.new(E11y::Event::Base) do
        def self.name
          "TestEvent"
        end

        metrics do
          counter :test_counter, tags: [:status]
          histogram :test_histogram, value: :amount, tags: [:currency]
          gauge :test_gauge, value: :size, tags: [:queue]
        end
      end

      expect(event_class.metrics_config.size).to eq(3)
      expect(event_class.metrics_config.map { |m| m[:type] }).to eq(%i[counter histogram gauge])
    end

    it "supports Proc value extractors" do
      event_class = Class.new(E11y::Event::Base) do
        def self.name
          "TestEvent"
        end

        metrics do
          histogram :test_histogram,
                    value: ->(event) { event[:payload][:amount] * 2 },
                    tags: [:currency]
        end
      end

      config = event_class.metrics_config.first
      expect(config[:value]).to be_a(Proc)
    end
  end

  describe "registry integration" do
    it "registers metrics in global registry" do
      Class.new(E11y::Event::Base) do
        def self.name
          "OrderCreated"
        end

        metrics do
          counter :orders_total, tags: [:status]
        end
      end

      # Metrics should be registered in global registry
      matches = registry.find_matching("OrderCreated")
      expect(matches.size).to eq(1)
      expect(matches.first[:name]).to eq(:orders_total)
    end

    it "includes source information" do
      Class.new(E11y::Event::Base) do
        def self.name
          "OrderCreated"
        end

        metrics do
          counter :orders_total, tags: [:status]
        end
      end

      metric = registry.find_by_name(:orders_total)
      expect(metric[:source]).to eq("OrderCreated.metrics")
    end

    it "uses event name as pattern" do
      Class.new(E11y::Event::Base) do
        def self.name
          "OrderCreated"
        end

        metrics do
          counter :orders_total, tags: [:status]
        end
      end

      metric = registry.find_by_name(:orders_total)
      expect(metric[:pattern]).to eq("OrderCreated")
    end
  end

  describe "metric inheritance" do
    it "inherits metrics from base class" do
      base_class = Class.new(E11y::Event::Base) do
        def self.name
          "BaseOrderEvent"
        end

        metrics do
          counter :orders_total, tags: %i[currency status]
        end
      end

      child_class = Class.new(base_class) do
        def self.name
          "OrderCreated"
        end

        metrics do
          histogram :order_amount, value: :amount, tags: [:currency]
        end
      end

      # Child should have both metrics
      expect(child_class.metrics_config.size).to eq(1) # Only own metrics
      expect(base_class.metrics_config.size).to eq(1)

      # But both should be in registry
      base_metrics = registry.find_matching("BaseOrderEvent")
      child_metrics = registry.find_matching("OrderCreated")

      expect(base_metrics.map { |m| m[:name] }).to include(:orders_total)
      expect(child_metrics.map { |m| m[:name] }).to include(:order_amount)
    end
  end

  describe "validation on registration" do
    it "detects label conflicts at boot time" do
      Class.new(E11y::Event::Base) do
        def self.name
          "OrderCreated"
        end

        metrics do
          counter :orders_total, tags: %i[currency status]
        end
      end

      expect do
        Class.new(E11y::Event::Base) do
          def self.name
            "OrderPaid"
          end

          metrics do
            counter :orders_total, tags: [:currency] # Different labels!
          end
        end
      end.to raise_error(E11y::Metrics::Registry::LabelConflictError)
    end

    it "detects type conflicts at boot time" do
      Class.new(E11y::Event::Base) do
        def self.name
          "OrderCreated"
        end

        metrics do
          counter :orders_total, tags: [:currency]
        end
      end

      expect do
        Class.new(E11y::Event::Base) do
          def self.name
            "OrderPaid"
          end

          metrics do
            histogram :orders_total, value: :amount, tags: [:currency] # Different type!
          end
        end
      end.to raise_error(E11y::Metrics::Registry::TypeConflictError)
    end

    it "allows same metric with same configuration" do
      Class.new(E11y::Event::Base) do
        def self.name
          "OrderCreated"
        end

        metrics do
          counter :orders_total, tags: %i[currency status]
        end
      end

      expect do
        Class.new(E11y::Event::Base) do
          def self.name
            "OrderPaid"
          end

          metrics do
            counter :orders_total, tags: %i[currency status] # Same config - OK!
          end
        end
      end.not_to raise_error
    end
  end

  describe "metrics_config getter" do
    it "returns empty array when no metrics defined" do
      event_class = Class.new(E11y::Event::Base) do
        def self.name
          "TestEvent"
        end
      end

      expect(event_class.metrics_config).to eq([])
    end

    it "returns metrics configuration" do
      event_class = Class.new(E11y::Event::Base) do
        def self.name
          "TestEvent"
        end

        metrics do
          counter :test_counter, tags: [:status]
        end
      end

      expect(event_class.metrics_config).to be_an(Array)
      expect(event_class.metrics_config.size).to eq(1)
    end
  end

  describe "real-world usage examples" do
    context "e-commerce order events" do
      before do
        # Base order event with shared metric
        @base_order_event = Class.new(E11y::Event::Base) do
          def self.name
            "BaseOrderEvent"
          end

          schema do
            required(:order_id).filled(:string)
            required(:currency).filled(:string)
            required(:status).filled(:string)
          end

          metrics do
            counter :orders_total, tags: %i[currency status]
          end
        end

        # Specific order events
        @order_created = Class.new(@base_order_event) do
          def self.name
            "OrderCreated"
          end
        end

        @order_paid = Class.new(@base_order_event) do
          def self.name
            "OrderPaid"
          end

          metrics do
            histogram :order_amount, value: :amount, tags: [:currency]
          end
        end
      end

      it "shares counter metric across events" do
        # Base event metric is registered with BaseOrderEvent pattern
        base_metrics = registry.find_matching("BaseOrderEvent")
        expect(base_metrics.map { |m| m[:name] }).to include(:orders_total)

        # OrderPaid has its own metric
        paid_metrics = registry.find_matching("OrderPaid")
        expect(paid_metrics.map { |m| m[:name] }).to include(:order_amount)
      end

      it "has event-specific histogram" do
        paid_metrics = registry.find_matching("OrderPaid")
        expect(paid_metrics.map { |m| m[:name] }).to include(:order_amount)

        # OrderCreated doesn't have order_amount metric
        created_metrics = registry.find_matching("OrderCreated")
        expect(created_metrics).to be_empty # No metrics for OrderCreated
      end
    end

    context "queue monitoring" do
      before do
        @queue_event = Class.new(E11y::Event::Base) do
          def self.name
            "QueueUpdated"
          end

          metrics do
            gauge :queue_depth, value: :size, tags: [:queue_name]
            counter :queue_operations, tags: %i[queue_name operation]
          end
        end
      end

      it "defines both gauge and counter" do
        metrics = registry.find_matching("QueueUpdated")
        expect(metrics.size).to eq(2)
        expect(metrics.map { |m| m[:type] }).to contain_exactly(:gauge, :counter)
      end
    end
  end
end
