# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Event::Base do
  # Test event classes
  let(:simple_event_class) do
    Class.new(described_class) do
      def self.name
        "SimpleEvent"
      end
    end
  end

  let(:schema_event_class) do
    Class.new(described_class) do
      def self.name
        "UserSignupEvent"
      end

      schema do
        required(:user_id).filled(:integer)
        required(:email).filled(:string)
      end
    end
  end

  let(:configured_event_class) do
    Class.new(described_class) do
      def self.name
        "OrderPaidEvent"
      end

      severity :success
      version 2
      adapters :loki, :sentry

      schema do
        required(:order_id).filled(:integer)
        required(:amount).filled(:float)
      end
    end
  end

  describe ".severity" do
    context "when explicitly set" do
      it "returns the set severity" do
        event_class = Class.new(described_class) do
          def self.name
            "TestEvent"
          end

          severity :error
        end

        expect(event_class.severity).to eq(:error)
      end
    end

    context "when using convention-based resolution" do
      it "resolves Failed suffix to :error" do
        event_class = Class.new(described_class) do
          def self.name
            "PaymentFailedEvent"
          end
        end

        expect(event_class.severity).to eq(:error)
      end

      it "resolves Error suffix to :error" do
        event_class = Class.new(described_class) do
          def self.name
            "ValidationErrorEvent"
          end
        end

        expect(event_class.severity).to eq(:error)
      end

      it "resolves Paid suffix to :success" do
        event_class = Class.new(described_class) do
          def self.name
            "OrderPaidEvent"
          end
        end

        expect(event_class.severity).to eq(:success)
      end

      it "resolves Success suffix to :success" do
        event_class = Class.new(described_class) do
          def self.name
            "ProcessSuccessEvent"
          end
        end

        expect(event_class.severity).to eq(:success)
      end

      it "resolves Completed suffix to :success" do
        event_class = Class.new(described_class) do
          def self.name
            "TaskCompletedEvent"
          end
        end

        expect(event_class.severity).to eq(:success)
      end

      it "resolves Warn suffix to :warn" do
        event_class = Class.new(described_class) do
          def self.name
            "HighMemoryWarnEvent"
          end
        end

        expect(event_class.severity).to eq(:warn)
      end

      it "resolves Warning suffix to :warn" do
        event_class = Class.new(described_class) do
          def self.name
            "DiskSpaceWarningEvent"
          end
        end

        expect(event_class.severity).to eq(:warn)
      end

      it "defaults to :info for unknown suffixes" do
        event_class = Class.new(described_class) do
          def self.name
            "CustomEvent"
          end
        end

        expect(event_class.severity).to eq(:info)
      end
    end

    context "with validation rules" do
      it "raises ArgumentError for invalid severity" do
        expect do
          Class.new(described_class) do
            severity :invalid
          end
        end.to raise_error(ArgumentError, /Invalid severity/)
      end

      it "accepts all valid severities" do
        E11y::Event::Base::SEVERITIES.each do |sev|
          event_class = Class.new(described_class) do
            severity sev
          end

          expect(event_class.severity).to eq(sev)
        end
      end
    end
  end

  describe ".version" do
    it "defaults to 1" do
      expect(simple_event_class.version).to eq(1)
    end

    it "can be set explicitly" do
      event_class = Class.new(described_class) do
        version 2
      end

      expect(event_class.version).to eq(2)
    end

    it "returns the set version" do
      expect(configured_event_class.version).to eq(2)
    end
  end

  describe ".adapters" do
    context "when explicitly set" do
      it "returns the set adapters" do
        expect(configured_event_class.adapters).to contain_exactly(:loki, :sentry)
      end

      it "accepts multiple adapters" do
        event_class = Class.new(described_class) do
          adapters :loki, :sentry, :stdout
        end

        expect(event_class.adapters).to contain_exactly(:loki, :sentry, :stdout)
      end
    end

    context "when using convention-based resolution" do
      it "resolves :error severity to [:logs, :errors_tracker]" do
        event_class = Class.new(described_class) do
          def self.name
            "TestEvent"
          end

          severity :error
        end

        expect(event_class.adapters).to eq(%i[logs errors_tracker])
      end

      it "resolves :fatal severity to [:logs, :errors_tracker]" do
        event_class = Class.new(described_class) do
          def self.name
            "TestEvent"
          end

          severity :fatal
        end

        expect(event_class.adapters).to eq(%i[logs errors_tracker])
      end

      it "resolves other severities to [:logs]" do
        %i[debug info success warn].each do |sev|
          event_class = Class.new(described_class) do
            severity sev

            def self.name
              "TestEvent"
            end
          end

          expect(event_class.adapters).to eq([:logs])
        end
      end
    end
  end

  describe ".event_name" do
    it "returns the class name without version suffix" do
      event_class = Class.new(described_class) do
        def self.name
          "OrderPaidEventV2"
        end
      end

      expect(event_class.event_name).to eq("OrderPaidEvent")
    end

    it "returns the class name as-is if no version suffix" do
      event_class = Class.new(described_class) do
        def self.name
          "OrderPaidEvent"
        end
      end

      expect(event_class.event_name).to eq("OrderPaidEvent")
    end

    it "handles multiple digit versions" do
      event_class = Class.new(described_class) do
        def self.name
          "OrderPaidEventV12"
        end
      end

      expect(event_class.event_name).to eq("OrderPaidEvent")
    end
  end

  describe ".schema" do
    it "stores schema block" do
      block = proc { required(:test).filled(:string) }
      event_class = Class.new(described_class)

      event_class.schema(&block)

      expect(event_class.instance_variable_get(:@schema_block)).to eq(block)
    end
  end

  describe ".compiled_schema" do
    it "returns nil when no schema defined" do
      expect(simple_event_class.compiled_schema).to be_nil
    end

    it "compiles schema on first access" do
      expect(schema_event_class.compiled_schema).not_to be_nil
      expect(schema_event_class.compiled_schema).to be_a(Dry::Schema::Params)
    end

    it "caches compiled schema" do
      schema1 = schema_event_class.compiled_schema
      schema2 = schema_event_class.compiled_schema

      expect(schema1).to be(schema2)
    end

    it "validates correct data" do
      result = schema_event_class.compiled_schema.call(user_id: 123, email: "test@example.com")
      expect(result).to be_success
    end

    it "rejects invalid data" do
      result = schema_event_class.compiled_schema.call(user_id: "invalid", email: nil)
      expect(result).not_to be_success
    end
  end

  describe ".track" do
    context "with valid payload" do
      it "returns event hash with metadata" do
        result = configured_event_class.track(order_id: 123, amount: 99.99)

        expect(result).to be_a(Hash)
        expect(result[:event_name]).to eq("OrderPaidEvent")
        expect(result[:payload]).to eq(order_id: 123, amount: 99.99)
        expect(result[:severity]).to eq(:success)
        expect(result[:version]).to eq(2)
        expect(result[:adapters]).to eq(%i[loki sentry])
        expect(result[:timestamp]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z/)
      end

      it "validates payload against schema" do
        result = schema_event_class.track(user_id: 456, email: "test@example.com")

        expect(result[:payload]).to eq(user_id: 456, email: "test@example.com")
        expect(result[:event_name]).to eq("UserSignupEvent")
      end

      it "works with events without schema" do
        no_schema_class = Class.new(described_class) do
          def self.name
            "NoSchemaEvent"
          end
        end

        result = no_schema_class.track(any: "data", works: true)

        expect(result[:payload]).to eq(any: "data", works: true)
        expect(result[:event_name]).to eq("NoSchemaEvent")
      end

      it "includes timestamp in ISO8601 format with milliseconds" do
        result = simple_event_class.track(user_id: 123, email: "test@example.com")

        expect(result[:timestamp]).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/)

        # Verify it's parseable
        expect { Time.iso8601(result[:timestamp]) }.not_to raise_error
      end
    end

    context "with invalid payload" do
      it "raises ValidationError when required field is missing" do
        expect do
          schema_event_class.track(user_id: 123) # missing :email
        end.to raise_error(E11y::ValidationError, /Validation failed.*email/)
      end

      it "raises ValidationError when type is wrong" do
        expect do
          schema_event_class.track(user_id: "not_an_integer", email: "test@example.com")
        end.to raise_error(E11y::ValidationError, /Validation failed/)
      end

      it "raises ValidationError when field is empty" do
        expect do
          schema_event_class.track(user_id: 123, email: "")
        end.to raise_error(E11y::ValidationError, /Validation failed/)
      end
    end

    # rubocop:disable RSpec/ContextWording
    context "zero-allocation pattern" do
      # rubocop:enable RSpec/ContextWording
      it "does not create event objects" do
        # Track should return a Hash, not an Event object
        result = simple_event_class.track(user_id: 123, email: "test@example.com")

        expect(result).to be_a(Hash)
        expect(result).not_to be_a(described_class)
      end

      # rubocop:disable RSpec/MessageSpies
      it "reuses class methods without instantiation" do
        # Verify we're calling class methods, not instance methods
        # Note: event_name is called multiple times internally (in validate_payload! and track)
        expect(schema_event_class).to receive(:severity).at_least(:once).and_call_original
        expect(schema_event_class).to receive(:version).at_least(:once).and_call_original
        expect(schema_event_class).to receive(:adapters).at_least(:once).and_call_original
        # rubocop:enable RSpec/MessageSpies

        schema_event_class.track(user_id: 123, email: "test@example.com")
      end
    end
  end

  describe "SEVERITIES constant" do
    it "defines all severity levels in order" do
      expect(E11y::Event::Base::SEVERITIES).to eq(%i[debug info success warn error fatal])
    end
  end

  describe "zero-allocation pattern compliance" do
    it "uses class methods for event tracking (not instances)" do
      # Zero-allocation pattern: class methods, not instances
      # Note: .new is still accessible (Ruby default), but not used
      expect(simple_event_class).to respond_to(:track)
      expect(simple_event_class).to respond_to(:severity)
      expect(simple_event_class).to respond_to(:version)
      expect(simple_event_class).to respond_to(:adapters)
      expect(simple_event_class).to respond_to(:schema)
    end
  end

  describe "integration examples" do
    it "allows minimal configuration (schema only)" do
      event_class = Class.new(described_class) do
        def self.name
          "MinimalEvent"
        end

        schema do
          required(:message).filled(:string)
        end
      end

      expect(event_class.severity).to eq(:info) # Default
      expect(event_class.version).to eq(1) # Default
      expect(event_class.adapters).to eq([:logs]) # Default for :info
    end

    it "supports full configuration" do
      event_class = Class.new(described_class) do
        def self.name
          "FullyConfiguredEvent"
        end

        severity :error
        version 3
        adapters :logs, :errors_tracker

        schema do
          required(:error_code).filled(:integer)
          required(:message).filled(:string)
        end
      end

      expect(event_class.severity).to eq(:error)
      expect(event_class.version).to eq(3)
      expect(event_class.adapters).to contain_exactly(:logs, :errors_tracker)
      expect(event_class.compiled_schema).not_to be_nil
    end
  end

  describe ".resolve_sample_rate" do
    it "returns 1.0 for :error severity (100%)" do
      event_class = Class.new(described_class) do
        def self.name
          "TestEvent"
        end

        severity :error
      end

      expect(event_class.resolve_sample_rate).to eq(1.0)
    end

    it "returns 1.0 for :fatal severity (100%)" do
      event_class = Class.new(described_class) do
        def self.name
          "TestEvent"
        end

        severity :fatal
      end

      expect(event_class.resolve_sample_rate).to eq(1.0)
    end

    it "returns 0.1 for :success severity (10%)" do
      event_class = Class.new(described_class) do
        def self.name
          "TestEvent"
        end

        severity :success
      end

      expect(event_class.resolve_sample_rate).to eq(0.1)
    end

    it "returns 0.1 for :info severity (10%)" do
      event_class = Class.new(described_class) do
        def self.name
          "TestEvent"
        end

        severity :info
      end

      expect(event_class.resolve_sample_rate).to eq(0.1)
    end

    it "returns 0.01 for :debug severity (1%)" do
      event_class = Class.new(described_class) do
        def self.name
          "TestEvent"
        end

        severity :debug
      end

      expect(event_class.resolve_sample_rate).to eq(0.01)
    end

    it "returns 0.1 for :warn severity (default 10%)" do
      event_class = Class.new(described_class) do
        def self.name
          "TestEvent"
        end

        severity :warn
      end

      expect(event_class.resolve_sample_rate).to eq(0.1)
    end
  end

  describe ".resolve_rate_limit" do
    it "returns nil for :error severity (unlimited)" do
      event_class = Class.new(described_class) do
        def self.name
          "TestEvent"
        end

        severity :error
      end

      expect(event_class.resolve_rate_limit).to be_nil
    end

    it "returns nil for :fatal severity (unlimited)" do
      event_class = Class.new(described_class) do
        def self.name
          "TestEvent"
        end

        severity :fatal
      end

      expect(event_class.resolve_rate_limit).to be_nil
    end

    it "returns 1000 for :info severity" do
      event_class = Class.new(described_class) do
        def self.name
          "TestEvent"
        end

        severity :info
      end

      expect(event_class.resolve_rate_limit).to eq(1000)
    end

    it "returns 1000 for :success severity" do
      event_class = Class.new(described_class) do
        def self.name
          "TestEvent"
        end

        severity :success
      end

      expect(event_class.resolve_rate_limit).to eq(1000)
    end

    it "returns 1000 for :debug severity" do
      event_class = Class.new(described_class) do
        def self.name
          "TestEvent"
        end

        severity :debug
      end

      expect(event_class.resolve_rate_limit).to eq(1000)
    end
  end

  describe ".validation_mode" do
    it "defaults to :always (safest)" do
      event_class = Class.new(described_class) do
        def self.name
          "TestEvent"
        end
      end

      expect(event_class.validation_mode).to eq(:always)
    end

    it "can be set to :sampled" do
      event_class = Class.new(described_class) do
        def self.name
          "TestEvent"
        end

        validation_mode :sampled
      end

      expect(event_class.validation_mode).to eq(:sampled)
    end

    it "can be set to :never" do
      event_class = Class.new(described_class) do
        def self.name
          "TestEvent"
        end

        validation_mode :never
      end

      expect(event_class.validation_mode).to eq(:never)
    end

    it "raises ArgumentError for invalid mode" do
      expect do
        Class.new(described_class) do
          validation_mode :invalid
        end
      end.to raise_error(ArgumentError, /Invalid validation mode/)
    end

    it "accepts custom sample_rate for :sampled mode" do
      event_class = Class.new(described_class) do
        def self.name
          "TestEvent"
        end

        validation_mode :sampled, sample_rate: 0.05 # 5%
      end

      expect(event_class.validation_sample_rate).to eq(0.05)
    end

    it "uses default sample_rate (1%) if not specified" do
      event_class = Class.new(described_class) do
        def self.name
          "TestEvent"
        end

        validation_mode :sampled
      end

      expect(event_class.validation_sample_rate).to eq(0.01)
    end
  end

  describe ".track with validation modes" do
    let(:schema_event_class) do
      Class.new(described_class) do
        def self.name
          "SchemaEvent"
        end

        schema do
          required(:user_id).filled(:integer)
          required(:email).filled(:string)
        end

        severity :info
      end
    end

    context "with validation_mode :always" do
      it "validates all events" do
        schema_event_class.validation_mode :always

        # Valid payload - should pass
        expect { schema_event_class.track(user_id: 123, email: "test@example.com") }.not_to raise_error

        # Invalid payload - should raise
        expect { schema_event_class.track(user_id: "not_integer", email: "test@example.com") }
          .to raise_error(E11y::ValidationError)
      end
    end

    context "with validation_mode :never" do
      it "skips validation for all events" do
        schema_event_class.validation_mode :never

        # Invalid payload - should NOT raise (validation skipped)
        result = schema_event_class.track(user_id: "not_integer", email: "test@example.com")

        expect(result[:payload][:user_id]).to eq("not_integer")
      end
    end

    context "with validation_mode :sampled" do
      it "validates approximately sample_rate % of events" do
        schema_event_class.validation_mode :sampled, sample_rate: 0.5 # 50% for testability

        # Track 100 events with invalid payload
        # Approximately 50 should raise ValidationError
        errors_count = 0
        100.times do
          schema_event_class.track(user_id: "invalid", email: "test@example.com")
        rescue E11y::ValidationError
          errors_count += 1
        end

        # Allow 30-70% range (statistical variance)
        expect(errors_count).to be_between(30, 70)
      end
    end
  end

  describe ".sample_rate" do
    context "when explicitly set" do
      it "returns the set sample rate" do
        event_class = Class.new(described_class) do
          def self.name
            "TestEvent"
          end

          sample_rate 0.5
        end

        expect(event_class.sample_rate).to eq(0.5)
      end

      it "validates sample rate is between 0.0 and 1.0" do
        event_class = Class.new(described_class) do
          def self.name
            "TestEvent"
          end
        end

        expect { event_class.sample_rate(-0.1) }.to raise_error(ArgumentError, /between 0.0 and 1.0/)
        expect { event_class.sample_rate(1.5) }.to raise_error(ArgumentError, /between 0.0 and 1.0/)
        expect { event_class.sample_rate("invalid") }.to raise_error(ArgumentError, /between 0.0 and 1.0/)
      end

      it "converts integer to float" do
        event_class = Class.new(described_class) do
          def self.name
            "TestEvent"
          end

          sample_rate 1
        end

        expect(event_class.sample_rate).to eq(1.0)
        expect(event_class.sample_rate).to be_a(Float)
      end
    end

    context "when not set" do
      it "returns nil" do
        event_class = Class.new(described_class) do
          def self.name
            "TestEvent"
          end
        end

        expect(event_class.sample_rate).to be_nil
      end
    end

    context "with inheritance" do
      it "inherits sample_rate from parent" do
        parent_class = Class.new(described_class) do
          def self.name
            "ParentEvent"
          end

          sample_rate 0.1
        end

        child_class = Class.new(parent_class) do
          def self.name
            "ChildEvent"
          end
        end

        expect(child_class.sample_rate).to eq(0.1)
      end

      it "allows child to override parent's sample_rate" do
        parent_class = Class.new(described_class) do
          def self.name
            "ParentEvent"
          end

          sample_rate 0.1
        end

        child_class = Class.new(parent_class) do
          def self.name
            "ChildEvent"
          end

          sample_rate 0.5
        end

        expect(child_class.sample_rate).to eq(0.5)
        expect(parent_class.sample_rate).to eq(0.1) # Parent unchanged
      end
    end
  end

  describe ".resolve_sample_rate" do
    context "with explicit sample_rate" do
      it "returns explicit sample_rate (highest priority)" do
        event_class = Class.new(described_class) do
          def self.name
            "ErrorEvent"
          end

          severity :error  # Would default to 1.0
          sample_rate 0.1  # Explicit override
        end

        expect(event_class.resolve_sample_rate).to eq(0.1)
      end
    end

    context "without explicit sample_rate" do
      it "returns severity-based default for error" do
        event_class = Class.new(described_class) do
          def self.name
            "ErrorEvent"
          end

          severity :error
        end

        expect(event_class.resolve_sample_rate).to eq(1.0)
      end

      it "returns severity-based default for debug" do
        event_class = Class.new(described_class) do
          def self.name
            "DebugEvent"
          end

          severity :debug
        end

        expect(event_class.resolve_sample_rate).to eq(0.01)
      end

      it "returns 0.1 for unknown severity" do
        event_class = Class.new(described_class) do
          def self.name
            "CustomEvent"
          end

          severity :info
        end

        expect(event_class.resolve_sample_rate).to eq(0.1)
      end
    end
  end

  describe ".adaptive_sampling" do
    context "when enabled" do
      it "returns configuration hash" do
        event_class = Class.new(described_class) do
          def self.name
            "TestEvent"
          end

          adaptive_sampling enabled: true,
                            error_rate_threshold: 0.05,
                            load_threshold: 50_000
        end

        config = event_class.adaptive_sampling
        expect(config).to be_a(Hash)
        expect(config[:enabled]).to be true
        expect(config[:error_rate_threshold]).to eq(0.05)
        expect(config[:load_threshold]).to eq(50_000)
      end
    end

    context "when not enabled" do
      it "returns nil" do
        event_class = Class.new(described_class) do
          def self.name
            "TestEvent"
          end
        end

        expect(event_class.adaptive_sampling).to be_nil
      end

      it "returns nil when explicitly disabled" do
        event_class = Class.new(described_class) do
          def self.name
            "TestEvent"
          end

          adaptive_sampling enabled: false
        end

        expect(event_class.adaptive_sampling).to be_nil
      end
    end

    context "with inheritance" do
      it "inherits adaptive_sampling from parent" do
        parent_class = Class.new(described_class) do
          def self.name
            "ParentEvent"
          end

          adaptive_sampling enabled: true, error_rate_threshold: 0.1
        end

        child_class = Class.new(parent_class) do
          def self.name
            "ChildEvent"
          end
        end

        expect(child_class.adaptive_sampling[:enabled]).to be true
        expect(child_class.adaptive_sampling[:error_rate_threshold]).to eq(0.1)
      end

      it "allows child to override parent's adaptive_sampling" do
        parent_class = Class.new(described_class) do
          def self.name
            "ParentEvent"
          end

          adaptive_sampling enabled: true, error_rate_threshold: 0.1
        end

        child_class = Class.new(parent_class) do
          def self.name
            "ChildEvent"
          end

          adaptive_sampling enabled: true, error_rate_threshold: 0.05
        end

        expect(child_class.adaptive_sampling[:error_rate_threshold]).to eq(0.05)
        expect(parent_class.adaptive_sampling[:error_rate_threshold]).to eq(0.1) # Parent unchanged
      end
    end
  end
end
