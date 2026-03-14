# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Configuration do
  subject(:config) { described_class.new }

  after { E11y.reset! }

  # ---------------------------------------------------------------------------
  # rate_limiting block DSL
  # ---------------------------------------------------------------------------
  describe "#rate_limiting block DSL" do
    it "yields the RateLimitingConfig to the block via instance_eval" do
      # instance_eval means `self` inside the block IS the RateLimitingConfig
      yielded_self = nil
      config.rate_limiting { yielded_self = self }
      expect(yielded_self).to be_a(E11y::RateLimitingConfig)
    end

    it "sets per_event_limit (global_limit) attribute via assignment" do
      E11y.configure do |c|
        c.rate_limiting do
          @global_limit = 100
        end
      end
      expect(E11y.config.rate_limiting.global_limit).to eq(100)
    end

    it "sets global_window attribute via assignment" do
      E11y.configure do |c|
        c.rate_limiting do
          @global_window = 60.0
        end
      end
      expect(E11y.config.rate_limiting.global_window).to eq(60.0)
    end

    it "configures global limit via #global DSL method" do
      E11y.configure do |c|
        c.rate_limiting do
          global limit: 5000, window: 30.0
        end
      end
      expect(E11y.config.rate_limiting.global_limit).to eq(5000)
      expect(E11y.config.rate_limiting.global_window).to eq(30.0)
    end

    it "configures per-event limit via #per_event DSL method" do
      E11y.configure do |c|
        c.rate_limiting do
          per_event "user.login.failed", limit: 50, window: 60.0
        end
      end
      limits = E11y.config.rate_limiting.per_event_limits
      expect(limits.size).to eq(1)
      expect(limits.first[:pattern]).to eq("user.login.failed")
      expect(limits.first[:limit]).to eq(50)
      expect(limits.first[:window]).to eq(60.0)
    end

    it "returns the RateLimitingConfig when called without a block" do
      result = config.rate_limiting
      expect(result).to be_a(E11y::RateLimitingConfig)
    end

    it "returns the same object each time (no re-instantiation)" do
      first  = config.rate_limiting
      second = config.rate_limiting
      expect(first).to equal(second)
    end
  end

  # ---------------------------------------------------------------------------
  # slo / slo_tracking block DSL
  # ---------------------------------------------------------------------------
  describe "#slo block DSL" do
    it "yields the SLOTrackingConfig to the block via instance_eval" do
      yielded_self = nil
      config.slo { yielded_self = self }
      expect(yielded_self).to be_a(E11y::SLOTrackingConfig)
    end

    it "sets enabled to false via block assignment" do
      E11y.configure do |c|
        c.slo do
          @enabled = false
        end
      end
      expect(E11y.config.slo.enabled).to be(false)
    end

    it "configures http_ignore_statuses via DSL method" do
      E11y.configure do |c|
        c.slo do
          http_ignore_statuses [404, 401]
        end
      end
      # http_ignore_statuses is a DSL setter (requires 1 arg), read via ivar
      stored = E11y.config.slo.instance_variable_get(:@http_ignore_statuses)
      expect(stored).to eq([404, 401])
    end

    it "configures latency_percentiles via DSL method" do
      E11y.configure do |c|
        c.slo do
          latency_percentiles [50, 90, 99]
        end
      end
      # latency_percentiles is a DSL setter (requires 1 arg), read via ivar
      stored = E11y.config.slo.instance_variable_get(:@latency_percentiles)
      expect(stored).to eq([50, 90, 99])
    end

    it "returns the SLOTrackingConfig when called without a block" do
      result = config.slo
      expect(result).to be_a(E11y::SLOTrackingConfig)
    end
  end

  describe "#slo_tracking block DSL (alias)" do
    it "yields the SLOTrackingConfig to the block via instance_eval" do
      yielded_self = nil
      config.slo_tracking { yielded_self = self }
      expect(yielded_self).to be_a(E11y::SLOTrackingConfig)
    end

    it "returns the SLOTrackingConfig when called without a block" do
      result = config.slo_tracking
      expect(result).to be_a(E11y::SLOTrackingConfig)
    end
  end

  describe "#slo_tracking= boolean coercion" do
    it "accepts true — sets enabled to true on the existing SLOTrackingConfig" do
      config.slo_tracking = true
      expect(config.slo_tracking.enabled).to be(true)
    end

    it "accepts false — sets enabled to false on the existing SLOTrackingConfig" do
      config.slo_tracking = false
      expect(config.slo_tracking.enabled).to be(false)
    end

    it "accepts a SLOTrackingConfig directly — replaces the stored config" do
      custom = E11y::SLOTrackingConfig.new
      custom.enabled = false
      config.slo_tracking = custom
      expect(config.slo_tracking).to equal(custom)
      expect(config.slo_tracking.enabled).to be(false)
    end

    it "does not raise for unknown value types (no TypeError — silent ignore)" do
      # The implementation uses a case/when without else, so unknown types are
      # silently ignored rather than raising. This matches the actual code.
      expect { config.slo_tracking = "yes" }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # cardinality_protection block DSL
  # ---------------------------------------------------------------------------
  describe "#cardinality_protection block DSL" do
    it "yields the CardinalityProtectionConfig to the block via instance_eval" do
      yielded_self = nil
      config.cardinality_protection { yielded_self = self }
      expect(yielded_self).to be_a(E11y::CardinalityProtectionConfig)
    end

    it "configures max_cardinality via DSL method" do
      E11y.configure do |c|
        c.cardinality_protection do
          max_cardinality 500
        end
      end
      expect(E11y.config.cardinality_protection.max_cardinality_limit).to eq(500)
    end

    it "configures denylist via DSL method" do
      E11y.configure do |c|
        c.cardinality_protection do
          denylist %i[user_id email]
        end
      end
      # denylist is a DSL setter (requires 1 arg), read via ivar
      stored = E11y.config.cardinality_protection.instance_variable_get(:@denylist)
      expect(stored).to eq(%i[user_id email])
    end

    it "configures overflow_strategy via DSL method" do
      E11y.configure do |c|
        c.cardinality_protection do
          overflow_strategy :drop
        end
      end
      # overflow_strategy is a DSL setter (requires 1 arg), read via ivar
      stored = E11y.config.cardinality_protection.instance_variable_get(:@overflow_strategy)
      expect(stored).to eq(:drop)
    end

    it "returns the CardinalityProtectionConfig when called without a block" do
      result = config.cardinality_protection
      expect(result).to be_a(E11y::CardinalityProtectionConfig)
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

    it "registers exactly 9 middlewares" do
      expect(middleware_classes.size).to eq(9)
    end

    it "orders middlewares per ADR-015: TraceContext → Validation → AuditSigning → PIIFilter → RateLimiting → Sampling → Versioning → Routing → EventSlo" do # rubocop:disable Layout/LineLength
      expected_order = [
        E11y::Middleware::TraceContext,
        E11y::Middleware::Validation,
        E11y::Middleware::AuditSigning,
        E11y::Middleware::PIIFilter,
        E11y::Middleware::RateLimiting,
        E11y::Middleware::Sampling,
        E11y::Middleware::Versioning,
        E11y::Middleware::Routing,
        E11y::Middleware::EventSlo
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
