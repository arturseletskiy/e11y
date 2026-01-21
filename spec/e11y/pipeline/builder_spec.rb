# frozen_string_literal: true

require "spec_helper"
require "e11y/pipeline/builder"
require "e11y/middleware/base"

RSpec.describe E11y::Pipeline::Builder do
  let(:builder) { described_class.new }

  # Test middleware classes with different zones
  let(:pre_processing_middleware) do
    Class.new(E11y::Middleware::Base) do
      middleware_zone :pre_processing

      def call(event_data)
        event_data[:pre_processing] = true
        @app.call(event_data)
      end
    end
  end

  let(:security_middleware) do
    Class.new(E11y::Middleware::Base) do
      middleware_zone :security

      def call(event_data)
        event_data[:security] = true
        @app.call(event_data)
      end
    end
  end

  let(:routing_middleware) do
    Class.new(E11y::Middleware::Base) do
      middleware_zone :routing

      def call(event_data)
        event_data[:routing] = true
        @app.call(event_data)
      end
    end
  end

  let(:post_processing_middleware) do
    Class.new(E11y::Middleware::Base) do
      middleware_zone :post_processing

      def call(event_data)
        event_data[:post_processing] = true
        @app.call(event_data)
      end
    end
  end

  let(:adapters_middleware) do
    Class.new(E11y::Middleware::Base) do
      middleware_zone :adapters

      def call(event_data)
        event_data[:adapters] = true
        @app.call(event_data)
      end
    end
  end

  let(:final_app) do
    lambda do |event_data|
      event_data[:final] = true
      event_data
    end
  end

  describe "#initialize" do
    it "initializes with empty middlewares" do
      expect(builder.middlewares).to be_empty
    end
  end

  describe "#use" do
    it "adds middleware to the pipeline" do
      builder.use pre_processing_middleware

      expect(builder.middlewares.size).to eq(1)
      expect(builder.middlewares.first.middleware_class).to eq(pre_processing_middleware)
    end

    it "accepts middleware with arguments" do
      builder.use pre_processing_middleware, "arg1", "arg2"

      entry = builder.middlewares.first
      expect(entry.args).to eq(%w[arg1 arg2])
    end

    it "accepts middleware with keyword arguments" do
      builder.use pre_processing_middleware, limit: 1000, enabled: true

      entry = builder.middlewares.first
      expect(entry.options).to eq({ limit: 1000, enabled: true })
    end

    it "accepts middleware with both positional and keyword arguments" do
      builder.use pre_processing_middleware, "arg1", limit: 1000

      entry = builder.middlewares.first
      expect(entry.args).to eq(["arg1"])
      expect(entry.options).to eq({ limit: 1000 })
    end

    it "supports method chaining" do
      result = builder.use(pre_processing_middleware).use(security_middleware)

      expect(result).to eq(builder)
      expect(builder.middlewares.size).to eq(2)
    end

    it "rejects non-middleware classes" do
      non_middleware_class = Class.new

      expect { builder.use non_middleware_class }
        .to raise_error(ArgumentError, /must inherit from E11y::Middleware::Base/)
    end
  end

  describe "#zone" do
    it "accepts valid zones" do
      E11y::Middleware::Base::VALID_ZONES.each do |zone|
        expect { builder.zone(zone) { nil } }.not_to raise_error
      end
    end

    it "rejects invalid zones" do
      expect { builder.zone(:invalid_zone) { nil } }
        .to raise_error(ArgumentError, /Invalid zone/)
    end

    it "executes block for middleware configuration" do
      executed = false

      builder.zone(:pre_processing) do
        executed = true
      end

      expect(executed).to be true
    end

    it "supports method chaining" do
      pre_proc_class = pre_processing_middleware

      result = builder.zone(:pre_processing) { use pre_proc_class }

      expect(result).to eq(builder)
    end

    it "allows adding middlewares within zone block" do
      pre_proc_class = pre_processing_middleware

      builder.zone(:pre_processing) do
        use pre_proc_class
      end

      expect(builder.middlewares.size).to eq(1)
    end
  end

  describe "#build" do
    # rubocop:disable RSpec/ExampleLength
    it "builds a functional pipeline" do
      builder.use pre_processing_middleware
      builder.use security_middleware

      pipeline = builder.build(final_app)
      result = pipeline.call({ test: true })

      expect(result[:pre_processing]).to be true
      expect(result[:security]).to be true
      expect(result[:final]).to be true
    end

    it "builds middlewares in correct order (FIFO)" do
      order = []

      middleware1 = Class.new(E11y::Middleware::Base) do
        define_method(:call) do |event_data|
          order << 1
          @app.call(event_data)
        end
      end

      middleware2 = Class.new(E11y::Middleware::Base) do
        define_method(:call) do |event_data|
          order << 2
          @app.call(event_data)
        end
      end

      middleware3 = Class.new(E11y::Middleware::Base) do
        define_method(:call) do |event_data|
          order << 3
          @app.call(event_data)
        end
      end

      builder.use middleware1
      builder.use middleware2
      builder.use middleware3

      pipeline = builder.build(final_app)
      pipeline.call({})

      expect(order).to eq([1, 2, 3])
    end

    it "passes arguments to middleware constructors" do
      test_middleware = Class.new(E11y::Middleware::Base) do
        attr_reader :custom_arg

        def initialize(app, custom_arg, option: nil)
          super(app)
          @custom_arg = custom_arg
          @option = option
        end

        def call(event_data)
          event_data[:custom_arg] = @custom_arg
          event_data[:option] = @option
          @app.call(event_data)
        end
      end

      builder.use test_middleware, "test_value", option: 123

      pipeline = builder.build(final_app)
      result = pipeline.call({})

      expect(result[:custom_arg]).to eq("test_value")
      expect(result[:option]).to eq(123)
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe "#validate_zones!" do
    context "with valid zone order" do
      it "allows correct zone progression" do
        builder.use pre_processing_middleware
        builder.use security_middleware
        builder.use routing_middleware
        builder.use post_processing_middleware
        builder.use adapters_middleware

        expect { builder.validate_zones! }.not_to raise_error
      end

      it "allows same zone multiple times" do
        builder.use pre_processing_middleware
        builder.use pre_processing_middleware # Same zone again

        expect { builder.validate_zones! }.not_to raise_error
      end

      it "allows skipping zones" do
        builder.use pre_processing_middleware
        # Skip security zone
        builder.use routing_middleware

        expect { builder.validate_zones! }.not_to raise_error
      end

      it "allows middlewares without declared zones" do
        no_zone_middleware = Class.new(E11y::Middleware::Base) do
          def call(event_data)
            @app.call(event_data)
          end
        end

        builder.use pre_processing_middleware
        builder.use no_zone_middleware # No zone
        builder.use security_middleware

        expect { builder.validate_zones! }.not_to raise_error
      end

      it "handles empty pipeline" do
        expect { builder.validate_zones! }.not_to raise_error
      end
    end

    context "with invalid zone order" do
      it "rejects backward zone progression" do
        builder.use security_middleware
        builder.use pre_processing_middleware # Goes backward!

        expect { builder.validate_zones! }
          .to raise_error(E11y::Pipeline::ZoneValidator::ZoneOrderError, /pre_processing.*cannot follow.*security/m)
      end

      it "provides detailed error message" do
        builder.use routing_middleware
        builder.use security_middleware # security after routing = wrong!

        expect { builder.validate_zones! }
          .to raise_error(E11y::Pipeline::ZoneValidator::ZoneOrderError,
                          /security.*cannot follow.*routing.*Valid zone order/m)
      end

      it "rejects adapters before post_processing" do
        builder.use pre_processing_middleware
        builder.use adapters_middleware
        builder.use post_processing_middleware # post_processing after adapters = wrong!

        expect { builder.validate_zones! }
          .to raise_error(E11y::InvalidPipelineError)
      end
    end
  end

  describe "#clear" do
    it "removes all middlewares" do
      builder.use pre_processing_middleware
      builder.use security_middleware

      builder.clear

      expect(builder.middlewares).to be_empty
    end
  end

  describe "ADR-015 compliance" do
    it "enforces correct middleware zone order" do
      # ADR-015 §3.4 zone order
      builder.use pre_processing_middleware  # Zone 1
      builder.use security_middleware        # Zone 2
      builder.use routing_middleware         # Zone 3
      builder.use post_processing_middleware # Zone 4
      builder.use adapters_middleware        # Zone 5

      expect { builder.validate_zones! }.not_to raise_error
    end

    it "supports zone-based configuration DSL" do
      pre_proc_class = pre_processing_middleware
      sec_class = security_middleware

      builder.zone(:pre_processing) do
        use pre_proc_class
      end

      builder.zone(:security) do
        use sec_class
      end

      expect(builder.middlewares.size).to eq(2)
      expect { builder.validate_zones! }.not_to raise_error
    end

    it "validates zones at boot time (not runtime)" do
      builder.use security_middleware
      builder.use pre_processing_middleware

      # validate_zones! called at boot (not during event processing)
      expect { builder.validate_zones! }.to raise_error(E11y::InvalidPipelineError)
    end
  end

  describe "integration" do
    it "builds a complete pipeline with all zones" do
      builder.use pre_processing_middleware
      builder.use security_middleware
      builder.use routing_middleware
      builder.use post_processing_middleware
      builder.use adapters_middleware

      builder.validate_zones!

      pipeline = builder.build(final_app)
      result = pipeline.call({ test: true })

      expect(result[:pre_processing]).to be true
      expect(result[:security]).to be true
      expect(result[:routing]).to be true
      expect(result[:post_processing]).to be true
      expect(result[:adapters]).to be true
      expect(result[:final]).to be true
    end
  end
end
