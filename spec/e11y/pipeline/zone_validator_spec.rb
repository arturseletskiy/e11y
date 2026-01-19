# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe E11y::Pipeline::ZoneValidator do
  let(:builder) { E11y::Pipeline::Builder.new }

  # Test middleware classes for each zone
  let(:pre_processing_middleware) do
    Class.new(E11y::Middleware::Base) do
      middleware_zone :pre_processing
      def self.name
        "PreProcessingMiddleware"
      end

      def call(event_data)
        @app.call(event_data)
      end
    end
  end

  let(:security_middleware) do
    Class.new(E11y::Middleware::Base) do
      middleware_zone :security
      def self.name
        "SecurityMiddleware"
      end

      def call(event_data)
        @app.call(event_data)
      end
    end
  end

  let(:routing_middleware) do
    Class.new(E11y::Middleware::Base) do
      middleware_zone :routing
      def self.name
        "RoutingMiddleware"
      end

      def call(event_data)
        @app.call(event_data)
      end
    end
  end

  let(:post_processing_middleware) do
    Class.new(E11y::Middleware::Base) do
      middleware_zone :post_processing
      def self.name
        "PostProcessingMiddleware"
      end

      def call(event_data)
        @app.call(event_data)
      end
    end
  end

  let(:adapters_middleware) do
    Class.new(E11y::Middleware::Base) do
      middleware_zone :adapters
      def self.name
        "AdaptersMiddleware"
      end

      def call(event_data)
        @app.call(event_data)
      end
    end
  end

  describe "#validate_boot_time!" do
    context "with valid zone order" do
      it "allows correct zone progression" do
        builder.use pre_processing_middleware
        builder.use security_middleware
        builder.use routing_middleware
        builder.use post_processing_middleware
        builder.use adapters_middleware

        validator = described_class.new(builder.middlewares)
        expect { validator.validate_boot_time! }.not_to raise_error
      end

      it "allows same zone repeated" do
        builder.use pre_processing_middleware
        builder.use pre_processing_middleware # Same zone again

        validator = described_class.new(builder.middlewares)
        expect { validator.validate_boot_time! }.not_to raise_error
      end

      it "allows skipping zones" do
        builder.use pre_processing_middleware # Zone 1
        builder.use routing_middleware        # Zone 3 (skip security)

        validator = described_class.new(builder.middlewares)
        expect { validator.validate_boot_time! }.not_to raise_error
      end

      it "allows middlewares without zone declaration" do
        middleware_without_zone = Class.new(E11y::Middleware::Base) do
          def self.name
            "NoZoneMiddleware"
          end

          def call(event_data)
            @app.call(event_data)
          end
        end

        builder.use pre_processing_middleware
        builder.use middleware_without_zone # No zone
        builder.use security_middleware

        validator = described_class.new(builder.middlewares)
        expect { validator.validate_boot_time! }.not_to raise_error
      end

      it "handles empty pipeline" do
        validator = described_class.new([])
        expect { validator.validate_boot_time! }.not_to raise_error
      end
    end

    context "with invalid zone order" do
      it "rejects backward zone progression" do
        builder.use security_middleware
        builder.use pre_processing_middleware # Goes backward!

        validator = described_class.new(builder.middlewares)

        expect { validator.validate_boot_time! }
          .to raise_error(
            E11y::Pipeline::ZoneValidator::ZoneOrderError,
            /PreProcessingMiddleware.*pre_processing.*cannot follow.*SecurityMiddleware.*security/m
          )
      end

      it "rejects routing before security" do
        builder.use routing_middleware
        builder.use security_middleware # security after routing = wrong!

        validator = described_class.new(builder.middlewares)

        expect { validator.validate_boot_time! }
          .to raise_error(
            E11y::Pipeline::ZoneValidator::ZoneOrderError,
            /SecurityMiddleware.*security.*cannot follow.*RoutingMiddleware.*routing/m
          )
      end

      it "rejects post_processing after adapters" do
        builder.use adapters_middleware
        builder.use post_processing_middleware # post_processing after adapters = wrong!

        validator = described_class.new(builder.middlewares)

        expect { validator.validate_boot_time! }
          .to raise_error(E11y::Pipeline::ZoneValidator::ZoneOrderError)
      end

      it "provides detailed error message" do
        builder.use security_middleware
        builder.use pre_processing_middleware

        validator = described_class.new(builder.middlewares)

        expect { validator.validate_boot_time! }
          .to raise_error(
            E11y::Pipeline::ZoneValidator::ZoneOrderError,
            /Invalid middleware zone order detected.*Valid zone order/m
          )
      end
    end
  end

  describe "ADR-015 compliance" do
    it "enforces correct middleware zone order per ADR-015 §3.4" do
      # ADR-015 §3.4 zone order
      builder.use pre_processing_middleware  # Zone 1
      builder.use security_middleware        # Zone 2
      builder.use routing_middleware         # Zone 3
      builder.use post_processing_middleware # Zone 4
      builder.use adapters_middleware        # Zone 5

      validator = described_class.new(builder.middlewares)
      expect { validator.validate_boot_time! }.not_to raise_error
    end

    it "prevents PII bypass by rejecting wrong zone order" do
      # Attempt to add middleware after security that could bypass PII filtering
      builder.use security_middleware
      builder.use pre_processing_middleware # Wrong! Would run after PII filtering

      validator = described_class.new(builder.middlewares)

      # validate_boot_time! called at boot (not during event processing)
      expect { validator.validate_boot_time! }
        .to raise_error(E11y::Pipeline::ZoneValidator::ZoneOrderError)
    end
  end

  describe "integration with Pipeline::Builder" do
    it "is called by Builder#validate_zones!" do
      builder.use pre_processing_middleware
      builder.use security_middleware
      builder.use routing_middleware
      builder.use post_processing_middleware
      builder.use adapters_middleware

      # Builder delegates to ZoneValidator
      expect { builder.validate_zones! }.not_to raise_error
    end

    it "raises same error type through Builder#validate_zones!" do
      builder.use security_middleware
      builder.use pre_processing_middleware

      # Error should propagate through Builder
      expect { builder.validate_zones! }
        .to raise_error(E11y::Pipeline::ZoneValidator::ZoneOrderError)
    end
  end

  describe "error hierarchy" do
    it "ZoneOrderError inherits from InvalidPipelineError" do
      expect(E11y::Pipeline::ZoneValidator::ZoneOrderError.ancestors)
        .to include(E11y::InvalidPipelineError)
    end

    it "allows catching as InvalidPipelineError" do
      builder.use security_middleware
      builder.use pre_processing_middleware

      validator = described_class.new(builder.middlewares)

      expect { validator.validate_boot_time! }
        .to raise_error(E11y::InvalidPipelineError)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
