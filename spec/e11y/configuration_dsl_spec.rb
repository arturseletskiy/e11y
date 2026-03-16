# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Configuration do
  subject(:config) { described_class.new }

  after { E11y.reset! }

  # ---------------------------------------------------------------------------
  # rate_limiting flat accessors and helpers
  # ---------------------------------------------------------------------------
  describe "#rate_limiting_* flat accessors" do
    it "sets rate_limiting_enabled" do
      config.rate_limiting_enabled = true
      expect(config.rate_limiting_enabled).to be(true)
    end

    it "sets rate_limiting_global_limit and rate_limiting_global_window" do
      config.rate_limiting_global_limit = 5000
      config.rate_limiting_global_window = 30.0
      expect(config.rate_limiting_global_limit).to eq(5000)
      expect(config.rate_limiting_global_window).to eq(30.0)
    end

    it "adds per-event limit via add_rate_limit_per_event" do
      config.add_rate_limit_per_event "user.login.failed", limit: 50, window: 60.0
      limits = config.rate_limiting_per_event_limits
      expect(limits.size).to eq(1)
      expect(limits.first[:pattern]).to eq("user.login.failed")
      expect(limits.first[:limit]).to eq(50)
      expect(limits.first[:window]).to eq(60.0)
    end

    it "rate_limit_for returns matching per-event rule" do
      config.add_rate_limit_per_event "user.login.failed", limit: 50, window: 60.0
      result = config.rate_limit_for("user.login.failed")
      expect(result).to eq(limit: 50, window: 60.0)
    end

    it "rate_limit_for returns per_event_limit fallback when no rule matches" do
      config.rate_limiting_per_event_limit = 1_000
      config.rate_limiting_global_window = 1.0
      result = config.rate_limit_for("unknown.event")
      expect(result).to eq(limit: 1_000, window: 1.0)
    end

    it "rate_limit_for matches glob pattern" do
      config.add_rate_limit_per_event "payment.*", limit: 500, window: 60.0
      expect(config.rate_limit_for("payment.retry")).to eq(limit: 500, window: 60.0)
      expect(config.rate_limit_for("payment.charged")).to eq(limit: 500, window: 60.0)
    end
  end

  # ---------------------------------------------------------------------------
  # slo_tracking flat accessors and helpers
  # ---------------------------------------------------------------------------
  describe "#slo_tracking_* flat accessors" do
    it "sets slo_tracking_enabled" do
      config.slo_tracking_enabled = false
      expect(config.slo_tracking_enabled).to be(false)
    end

    it "sets slo_tracking_http_ignore_statuses and slo_tracking_latency_percentiles" do
      config.slo_tracking_http_ignore_statuses = [404, 401]
      config.slo_tracking_latency_percentiles = [50, 90, 99]
      expect(config.slo_tracking_http_ignore_statuses).to eq([404, 401])
      expect(config.slo_tracking_latency_percentiles).to eq([50, 90, 99])
    end

    it "adds controller config via add_slo_controller" do
      config.add_slo_controller "Api::OrdersController", action: "show" do
        slo_target 0.999
        latency_target 200
      end
      cfgs = config.slo_tracking_controller_configs
      expect(cfgs.keys).to include("Api::OrdersController#show")
      cfg = cfgs["Api::OrdersController#show"]
      expect(cfg).to be_a(E11y::ControllerSLOConfig)
      expect(cfg.slo_target).to eq(0.999)
      expect(cfg.latency_target).to eq(200)
    end

    it "adds job config via add_slo_job" do
      config.add_slo_job "ReportGenerationJob" do
        ignore true
      end
      cfgs = config.slo_tracking_job_configs
      expect(cfgs.keys).to include("ReportGenerationJob")
      cfg = cfgs["ReportGenerationJob"]
      expect(cfg).to be_a(E11y::JobSLOConfig)
      expect(cfg.ignore).to be(true)
    end
  end

  describe "#slo_tracking= boolean coercion" do
    it "accepts true — sets slo_tracking_enabled to true" do
      config.slo_tracking_enabled = false
      config.slo_tracking = true
      expect(config.slo_tracking_enabled).to be(true)
    end

    it "accepts false — sets slo_tracking_enabled to false" do
      config.slo_tracking = false
      expect(config.slo_tracking_enabled).to be(false)
    end

    it "does not raise for unknown value types (no TypeError — silent ignore)" do
      expect { config.slo_tracking = "yes" }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # security, tracing, opentelemetry, cardinality_protection flat accessors
  # ---------------------------------------------------------------------------
  describe "#security_baggage_protection_* flat accessors" do
    it "sets security_baggage_protection_enabled and allowed_keys" do
      config.security_baggage_protection_enabled = true
      config.security_baggage_protection_allowed_keys = %w[trace_id span_id request_id]
      config.security_baggage_protection_block_mode = :warn
      expect(config.security_baggage_protection_enabled).to be(true)
      expect(config.security_baggage_protection_allowed_keys).to eq(%w[trace_id span_id request_id])
      expect(config.security_baggage_protection_block_mode).to eq(:warn)
    end

    it "filter_baggage_for_propagation returns only allowed keys when enabled" do
      config.security_baggage_protection_enabled = true
      config.security_baggage_protection_allowed_keys = %w[trace_id experiment]
      hash = { "trace_id" => "abc", "experiment" => "exp-1", "user_email" => "x@y.com" }
      expect(config.filter_baggage_for_propagation(hash)).to eq("trace_id" => "abc", "experiment" => "exp-1")
    end

    it "filter_baggage_for_propagation returns full hash when disabled" do
      config.security_baggage_protection_enabled = false
      hash = { "user_email" => "x@y.com" }
      expect(config.filter_baggage_for_propagation(hash)).to eq(hash)
    end
  end

  describe "#tracing_* flat accessors" do
    it "sets tracing_source and tracing_default_sample_rate" do
      config.tracing_source = :opentelemetry
      config.tracing_default_sample_rate = 0.5
      expect(config.tracing_source).to eq(:opentelemetry)
      expect(config.tracing_default_sample_rate).to eq(0.5)
    end
  end

  describe "#opentelemetry_span_creation_patterns" do
    it "sets opentelemetry_span_creation_patterns" do
      config.opentelemetry_span_creation_patterns = ["order.*", "payment.*"]
      expect(config.opentelemetry_span_creation_patterns).to eq(["order.*", "payment.*"])
    end
  end

  describe "#cardinality_protection_* flat accessors" do
    it "sets cardinality_protection_max_cardinality_limit, denylist, overflow_strategy" do
      config.cardinality_protection_max_cardinality_limit = 500
      config.cardinality_protection_denylist = %i[user_id email]
      config.cardinality_protection_overflow_strategy = :drop
      expect(config.cardinality_protection_max_cardinality_limit).to eq(500)
      expect(config.cardinality_protection_denylist).to eq(%i[user_id email])
      expect(config.cardinality_protection_overflow_strategy).to eq(:drop)
    end
  end

  # ---------------------------------------------------------------------------
  # register_adapter
  # ---------------------------------------------------------------------------
  describe "#register_adapter" do
    let(:adapter) { E11y::Adapters::Null.new }

    it "registers the adapter under the given symbol name" do
      config.register_adapter(:null, adapter)
      expect(config.adapters[:null]).to equal(adapter)
    end

    it "coerces string names to symbols" do
      config.register_adapter("events", adapter)
      expect(config.adapters[:events]).to equal(adapter)
    end

    it "makes the adapter accessible via config.adapters" do
      config.register_adapter(:my_adapter, adapter)
      expect(config.adapters).to have_key(:my_adapter)
    end

    it "overwrites a previously registered adapter with the same name" do
      adapter2 = E11y::Adapters::Null.new
      config.register_adapter(:null, adapter)
      config.register_adapter(:null, adapter2)
      expect(config.adapters[:null]).to equal(adapter2)
    end
  end

  # ---------------------------------------------------------------------------
  # default_adapters
  # ---------------------------------------------------------------------------
  describe "#default_adapters" do
    it "returns [:logs] by default (convention-based default)" do
      expect(config.default_adapters).to eq([:logs])
    end

    it "returns the array of adapter names set via default_adapters=" do
      config.default_adapters = %i[loki sentry]
      expect(config.default_adapters).to eq(%i[loki sentry])
    end

    it "coerces a single symbol to an array" do
      config.default_adapters = :loki
      expect(config.default_adapters).to eq([:loki])
    end

    it "is reflected in adapters_for_severity(:info) (unmatched severity falls back)" do
      config.default_adapters = [:custom]
      # :info has no explicit mapping → falls back to :default
      expect(config.adapters_for_severity(:info)).to eq([:custom])
    end
  end

  # ---------------------------------------------------------------------------
  # configure_default_pipeline — middleware presence and order
  # ---------------------------------------------------------------------------
  describe "#configure_default_pipeline (ADR-015)" do
    # Access the pipeline builder that was configured during initialize
    let(:pipeline) { config.instance_variable_get(:@pipeline) }
    let(:middleware_classes) { pipeline.middlewares.map(&:middleware_class) }

    it "includes TraceContext middleware" do
      expect(middleware_classes).to include(E11y::Middleware::TraceContext)
    end

    it "includes Versioning middleware" do
      expect(middleware_classes).to include(E11y::Middleware::Versioning)
    end

    it "includes Validation middleware" do
      expect(middleware_classes).to include(E11y::Middleware::Validation)
    end

    it "includes PIIFilter middleware" do
      expect(middleware_classes).to include(E11y::Middleware::PIIFilter)
    end

    it "includes AuditSigning middleware" do
      expect(middleware_classes).to include(E11y::Middleware::AuditSigning)
    end

    it "includes Sampling middleware" do
      expect(middleware_classes).to include(E11y::Middleware::Sampling)
    end

    it "includes RateLimiting middleware" do
      expect(middleware_classes).to include(E11y::Middleware::RateLimiting)
    end

    it "includes Routing middleware" do
      expect(middleware_classes).to include(E11y::Middleware::Routing)
    end

    it "registers exactly 12 middlewares (includes TrackLatency, BaggageProtection, SelfMonitoringEmit)" do
      expect(middleware_classes.size).to eq(12)
    end

    it "orders middlewares per ADR-015: TrackLatency → TraceContext → ... → EventSlo → SelfMonitoringEmit" do # rubocop:disable Layout/LineLength
      expected_order = [
        E11y::Middleware::TrackLatency,
        E11y::Middleware::TraceContext,
        E11y::Middleware::Validation,
        E11y::Middleware::BaggageProtection,
        E11y::Middleware::AuditSigning,
        E11y::Middleware::PIIFilter,
        E11y::Middleware::RateLimiting,
        E11y::Middleware::Sampling,
        E11y::Middleware::Versioning,
        E11y::Middleware::Routing,
        E11y::Middleware::EventSlo,
        E11y::Middleware::SelfMonitoringEmit
      ]
      expect(middleware_classes).to eq(expected_order)
    end

    it "places TraceContext before Validation" do
      trace_idx = middleware_classes.index(E11y::Middleware::TraceContext)
      valid_idx = middleware_classes.index(E11y::Middleware::Validation)
      expect(trace_idx).to be < valid_idx
    end

    it "places Validation before Versioning" do
      valid_idx   = middleware_classes.index(E11y::Middleware::Validation)
      version_idx = middleware_classes.index(E11y::Middleware::Versioning)
      expect(valid_idx).to be < version_idx
    end

    it "places AuditSigning before PIIFilter (sign original data per GDPR Art. 30)" do
      audit_idx = middleware_classes.index(E11y::Middleware::AuditSigning)
      pii_idx   = middleware_classes.index(E11y::Middleware::PIIFilter)
      expect(audit_idx).to be < pii_idx
    end

    it "places PIIFilter before Sampling" do
      pii_idx      = middleware_classes.index(E11y::Middleware::PIIFilter)
      sampling_idx = middleware_classes.index(E11y::Middleware::Sampling)
      expect(pii_idx).to be < sampling_idx
    end

    it "places RateLimiting before Sampling (ADR-015 #4 before #5)" do
      rate_idx     = middleware_classes.index(E11y::Middleware::RateLimiting)
      sampling_idx = middleware_classes.index(E11y::Middleware::Sampling)
      expect(rate_idx).to be < sampling_idx
    end

    it "places Versioning before Routing (Versioning last)" do
      version_idx = middleware_classes.index(E11y::Middleware::Versioning)
      routing_idx = middleware_classes.index(E11y::Middleware::Routing)
      expect(version_idx).to be < routing_idx
    end

    it "places Validation before PIIFilter (pre_processing before security zone)" do
      valid_idx = middleware_classes.index(E11y::Middleware::Validation)
      pii_idx   = middleware_classes.index(E11y::Middleware::PIIFilter)
      expect(valid_idx).to be < pii_idx
    end
  end
end
