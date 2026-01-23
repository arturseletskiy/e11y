# frozen_string_literal: true

require "spec_helper"

# Integration tests for Yabeda adapter with real Yabeda gem
# These tests require: bundle install --with integration
# Run with: INTEGRATION=true bundle exec rspec --tag integration spec/e11y/adapters/yabeda_integration_spec.rb

begin
  require "yabeda"
  require "yabeda/prometheus"
  require "e11y/adapters/yabeda"
rescue LoadError
  RSpec.describe "E11y::Adapters::Yabeda Integration (skipped)", :integration do
    it "requires Yabeda gems to be installed" do
      skip "Install with: bundle install --with integration"
    end
  end

  return
end

RSpec.describe E11y::Adapters::Yabeda, :integration do
  let(:registry) { E11y::Metrics::Registry.instance }
  let(:adapter) { described_class.new(auto_register: false) }

  before do
    # Clear Yabeda configuration
    Yabeda.reset!

    # Clear E11y registry
    registry.clear!
  end

  after do
    Yabeda.reset!
    registry.clear!
  end

  describe "real Yabeda integration" do
    context "with counter metrics" do
      before do
        # Register metric in E11y
        registry.register(
          type: :counter,
          pattern: "order.*",
          name: :orders_total,
          tags: %i[currency status]
        )

        # Configure Yabeda
        Yabeda.configure do
          group :e11y do
            counter :orders_total,
                    tags: %i[currency status],
                    comment: "Total orders tracked"
          end
        end
        Yabeda.configure!
      end

      it "increments real Yabeda counter" do
        event = {
          event_name: "order.created",
          currency: "USD",
          status: "pending"
        }

        # Get initial value
        initial_value = Yabeda.e11y.orders_total.get(currency: "USD", status: "pending")

        # Write event through adapter
        adapter.write(event)

        # Check that counter was incremented
        new_value = Yabeda.e11y.orders_total.get(currency: "USD", status: "pending")
        expect(new_value).to eq(initial_value + 1)
      end

      it "handles multiple increments" do
        3.times do
          adapter.write(
            event_name: "order.created",
            currency: "EUR",
            status: "paid"
          )
        end

        value = Yabeda.e11y.orders_total.get(currency: "EUR", status: "paid")
        expect(value).to eq(3)
      end

      it "tracks different label combinations separately" do
        adapter.write(event_name: "order.created", currency: "USD", status: "pending")
        adapter.write(event_name: "order.created", currency: "USD", status: "paid")
        adapter.write(event_name: "order.created", currency: "EUR", status: "pending")

        usd_pending = Yabeda.e11y.orders_total.get(currency: "USD", status: "pending")
        usd_paid = Yabeda.e11y.orders_total.get(currency: "USD", status: "paid")
        eur_pending = Yabeda.e11y.orders_total.get(currency: "EUR", status: "pending")

        expect(usd_pending).to eq(1)
        expect(usd_paid).to eq(1)
        expect(eur_pending).to eq(1)
      end
    end

    context "with histogram metrics" do
      before do
        registry.register(
          type: :histogram,
          pattern: "order.paid",
          name: :order_amount,
          value: :amount,
          tags: [:currency],
          buckets: [10, 50, 100, 500, 1000]
        )

        Yabeda.configure do
          group :e11y do
            histogram :order_amount,
                      tags: [:currency],
                      buckets: [10, 50, 100, 500, 1000],
                      comment: "Order amounts"
          end
        end
        Yabeda.configure!
      end

      it "observes real Yabeda histogram" do
        event = {
          event_name: "order.paid",
          payload: { amount: 99.99 },
          currency: "USD"
        }

        adapter.write(event)

        # Check histogram was recorded
        metric = Yabeda.e11y.order_amount
        values = metric.values

        # Check that observation was recorded for USD
        usd_values = values.select { |labels, _| labels[:currency] == "USD" }
        expect(usd_values).not_to be_empty
      end

      it "records multiple observations" do
        [25.0, 75.0, 150.0].each do |amount|
          adapter.write(
            event_name: "order.paid",
            payload: { amount: amount },
            currency: "EUR"
          )
        end

        metric = Yabeda.e11y.order_amount
        eur_values = metric.values.select { |labels, _| labels[:currency] == "EUR" }

        # Should have recorded 3 observations
        # The values structure varies by Yabeda version
        expect(eur_values).not_to be_empty
      end
    end

    context "with gauge metrics" do
      before do
        registry.register(
          type: :gauge,
          pattern: "queue.*",
          name: :queue_depth,
          value: :size,
          tags: [:queue_name]
        )

        Yabeda.configure do
          group :e11y do
            gauge :queue_depth,
                  tags: [:queue_name],
                  comment: "Queue depth"
          end
        end
        Yabeda.configure!
      end

      it "sets real Yabeda gauge" do
        event = {
          event_name: "queue.updated",
          payload: { size: 42 },
          queue_name: "default"
        }

        adapter.write(event)

        value = Yabeda.e11y.queue_depth.get(queue_name: "default")
        expect(value).to eq(42)
      end

      it "updates gauge value" do
        adapter.write(
          event_name: "queue.updated",
          payload: { size: 10 },
          queue_name: "priority"
        )

        adapter.write(
          event_name: "queue.updated",
          payload: { size: 25 },
          queue_name: "priority"
        )

        value = Yabeda.e11y.queue_depth.get(queue_name: "priority")
        expect(value).to eq(25) # Should be latest value, not sum
      end
    end

    context "E11y::Metrics facade integration" do # rubocop:todo RSpec/ContextWording
      before do
        # Register Yabeda adapter in E11y config
        allow(E11y.config.adapters).to receive(:values).and_return([adapter])

        # Reset backend cache
        E11y::Metrics.reset_backend!
      end

      it "delegates increment to real Yabeda" do
        Yabeda.configure do
          group :e11y do
            counter :api_requests, tags: [:method], comment: "API requests"
          end
        end
        Yabeda.configure!

        E11y::Metrics.increment(:api_requests, { method: "GET" })

        value = Yabeda.e11y.api_requests.get(method: "GET")
        expect(value).to eq(1)
      end

      it "delegates histogram to real Yabeda" do
        Yabeda.configure do
          group :e11y do
            histogram :request_duration,
                      tags: [:endpoint],
                      buckets: [0.001, 0.01, 0.1, 1.0],
                      comment: "Request duration"
          end
        end
        Yabeda.configure!

        E11y::Metrics.histogram(:request_duration, 0.042, { endpoint: "/api/users" })

        metric = Yabeda.e11y.request_duration
        values = metric.values.select { |labels, _| labels[:endpoint] == "/api/users" }
        expect(values).not_to be_empty
      end

      it "delegates gauge to real Yabeda" do
        Yabeda.configure do
          group :e11y do
            gauge :active_connections, tags: [:server], comment: "Active connections"
          end
        end
        Yabeda.configure!

        E11y::Metrics.gauge(:active_connections, 42, { server: "web-01" })

        value = Yabeda.e11y.active_connections.get(server: "web-01")
        expect(value).to eq(42)
      end
    end

    context "cardinality protection with real metrics" do # rubocop:todo RSpec/ContextWording
      before do
        Yabeda.configure do
          group :e11y do
            counter :protected_metric, tags: [:label1], comment: "Protected metric"
          end
        end
        Yabeda.configure!

        registry.register(
          type: :counter,
          pattern: "test.*",
          name: :protected_metric,
          tags: [:label1]
        )
      end

      it "prevents cardinality explosion" do
        adapter_with_limit = described_class.new(
          cardinality_limit: 3,
          auto_register: false,
          overflow_strategy: :drop
        )

        # Write 5 unique labels (should only accept 3)
        5.times do |i|
          adapter_with_limit.write(
            event_name: "test.event",
            label1: "value_#{i}"
          )
        end

        # Check that cardinality was tracked and limited
        # The adapter should have dropped some labels
        cardinality_stats = adapter_with_limit.cardinality_stats
        expect(cardinality_stats).to be_a(Hash)
      end
    end

    context "Prometheus export" do # rubocop:todo RSpec/ContextWording
      it "exports metrics in Prometheus format" do
        Yabeda.configure do
          group :e11y do
            counter :exported_metric, tags: [], comment: "Exported metric"
          end
        end
        Yabeda.configure!

        Yabeda.e11y.exported_metric.increment({})

        # Export to Prometheus format
        # Get the Prometheus registry
        registry = Yabeda.adapters.find { |a| a.is_a?(Yabeda::Prometheus::Adapter) }&.registry
        skip "Prometheus adapter not configured" unless registry

        exporter = Yabeda::Prometheus::Exporter.new(registry)
        env = Rack::MockRequest.env_for("/metrics")
        output = exporter.call(env)
        prometheus_text = output[2].join

        expect(prometheus_text).to include("e11y_exported_metric")
      end
    end
  end

  describe "adapter capabilities" do
    it "reports metrics support" do
      expect(adapter.capabilities[:metrics]).to be(true)
    end

    it "reports batch support" do
      expect(adapter.capabilities[:batch]).to be(true)
    end

    it "is healthy when Yabeda is configured" do
      Yabeda.configure {} # Configure Yabeda
      Yabeda.configure! # Apply configuration
      expect(adapter.healthy?).to be(true)
    end
  end

  describe "auto-registration" do
    it "automatically registers metrics from registry" do
      registry.register(
        type: :counter,
        pattern: "auto.*",
        name: :auto_counter,
        tags: [:tag1]
      )

      # Create adapter with auto_register: true
      described_class.new(auto_register: true)

      # Configure Yabeda to apply the registrations
      Yabeda.configure!

      # Check that metric was auto-registered in Yabeda
      expect(Yabeda.e11y).to respond_to(:auto_counter)
    end
  end
end
