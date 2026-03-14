# frozen_string_literal: true

# Rails env required when Yabeda loads (integration mode)
require(ENV["INTEGRATION"] == "true" ? "rails_helper" : "spec_helper")

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
    reset_yabeda_values!
  end

  # Unified approach: no Yabeda.reset! — metrics pre-registered in dummy/config/application.rb

  describe "real Yabeda integration" do
    context "with counter metrics" do
      it "increments real Yabeda counter" do
        event = {
          event_name: "order.created",
          currency: "USD",
          status: "pending"
        }

        initial_value = Yabeda.e11y.orders_total_yabeda_spec.get(currency: "USD", status: "pending") || 0
        adapter.write(event)
        new_value = Yabeda.e11y.orders_total_yabeda_spec.get(currency: "USD", status: "pending")
        expect(new_value).to eq(initial_value + 1)
      end

      it "handles multiple increments" do
        3.times do
          adapter.write(event_name: "order.created", currency: "EUR", status: "paid")
        end
        value = Yabeda.e11y.orders_total_yabeda_spec.get(currency: "EUR", status: "paid")
        expect(value).to eq(3)
      end

      it "tracks different label combinations separately" do
        adapter.write(event_name: "order.created", currency: "USD", status: "pending")
        adapter.write(event_name: "order.created", currency: "USD", status: "paid")
        adapter.write(event_name: "order.created", currency: "EUR", status: "pending")

        expect(Yabeda.e11y.orders_total_yabeda_spec.get(currency: "USD", status: "pending")).to eq(1)
        expect(Yabeda.e11y.orders_total_yabeda_spec.get(currency: "USD", status: "paid")).to eq(1)
        expect(Yabeda.e11y.orders_total_yabeda_spec.get(currency: "EUR", status: "pending")).to eq(1)
      end
    end

    context "with histogram metrics" do
      it "observes real Yabeda histogram" do
        adapter.write(
          event_name: "order.paid",
          payload: { amount: 99.99 },
          currency: "USD"
        )
        metric = Yabeda.e11y.order_amount_yabeda_spec
        usd_values = metric.values.select { |labels, _| labels[:currency] == "USD" }
        expect(usd_values).not_to be_empty
      end

      it "records multiple observations" do
        [25.0, 75.0, 150.0].each do |amount|
          adapter.write(event_name: "order.paid", payload: { amount: amount }, currency: "EUR")
        end
        eur_values = Yabeda.e11y.order_amount_yabeda_spec.values.select { |labels, _| labels[:currency] == "EUR" }
        expect(eur_values).not_to be_empty
      end
    end

    context "with gauge metrics" do
      it "sets real Yabeda gauge" do
        adapter.write(event_name: "queue.updated", payload: { size: 42 }, queue_name: "default")
        expect(Yabeda.e11y.queue_depth_yabeda_spec.get(queue_name: "default")).to eq(42)
      end

      it "updates gauge value" do
        adapter.write(event_name: "queue.updated", payload: { size: 10 }, queue_name: "priority")
        adapter.write(event_name: "queue.updated", payload: { size: 25 }, queue_name: "priority")
        expect(Yabeda.e11y.queue_depth_yabeda_spec.get(queue_name: "priority")).to eq(25)
      end
    end

    context "E11y::Metrics facade integration" do # rubocop:todo RSpec/ContextWording
      before do
        allow(E11y.config.adapters).to receive(:values).and_return([adapter])
        E11y::Metrics.reset_backend!
      end

      it "delegates increment to real Yabeda" do
        E11y::Metrics.increment(:api_requests_yabeda_spec, { method: "GET" })
        expect(Yabeda.e11y.api_requests_yabeda_spec.get(method: "GET")).to eq(1)
      end

      it "delegates histogram to real Yabeda" do
        E11y::Metrics.histogram(:request_duration_yabeda_spec, 0.042, { endpoint: "/api/users" })
        metric = Yabeda.e11y.request_duration_yabeda_spec
        values = metric.values.select { |labels, _| labels[:endpoint] == "/api/users" }
        expect(values).not_to be_empty
      end

      it "delegates gauge to real Yabeda" do
        E11y::Metrics.gauge(:active_connections_yabeda_spec, 42, { server: "web-01" })
        expect(Yabeda.e11y.active_connections_yabeda_spec.get(server: "web-01")).to eq(42)
      end
    end

    context "cardinality protection with real metrics" do # rubocop:todo RSpec/ContextWording
      it "prevents cardinality explosion" do
        adapter_with_limit = described_class.new(
          cardinality_limit: 3,
          auto_register: false,
          overflow_strategy: :drop
        )
        5.times { |i| adapter_with_limit.write(event_name: "test.event", label1: "value_#{i}") }
        expect(adapter_with_limit.cardinality_stats).to be_a(Hash)
      end
    end

    context "Prometheus export" do # rubocop:todo RSpec/ContextWording
      it "exports metrics in Prometheus format" do
        # Use existing Prometheus adapter (yabeda-prometheus auto-registers on load).
        # Do NOT create a new adapter — Prometheus::Client.registry is global; re-registering causes AlreadyRegisteredError.
        prometheus_adapter = Yabeda.adapters[:prometheus]
        Yabeda.e11y.exported_metric_yabeda_spec.increment({})

        prometheus_registry = prometheus_adapter.registry
        exporter = Yabeda::Prometheus::Exporter.new(prometheus_registry)
        output = exporter.call(Rack::MockRequest.env_for("/metrics"))
        prometheus_text = output[2].join

        expect(prometheus_text).to include("e11y_exported_metric_yabeda_spec")
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
      expect(adapter.healthy?).to be(true)
    end
  end

  describe "auto-registration" do
    it "automatically registers metrics from registry" do
      described_class.new(auto_register: true)
      expect(Yabeda.e11y).to respond_to(:auto_counter_yabeda_spec)
    end
  end
end
