# frozen_string_literal: true

require "spec_helper"
require "e11y/middleware/base"

RSpec.describe E11y::Middleware::Base do
  # Test middleware classes
  let(:test_middleware_class) do
    Class.new(described_class) do
      middleware_zone :pre_processing

      def call(event_data)
        event_data[:processed] = true
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

  let(:middleware) { test_middleware_class.new(final_app) }
  let(:event_data) { { event_name: "test", payload: {} } }

  describe ".middleware_zone" do
    context "when setting a zone" do
      it "accepts valid zones" do
        E11y::Middleware::Base::VALID_ZONES.each do |zone|
          test_class = Class.new(described_class)
          expect { test_class.middleware_zone zone }.not_to raise_error
          expect(test_class.middleware_zone).to eq(zone)
        end
      end

      it "rejects invalid zones" do
        test_class = Class.new(described_class)
        expect { test_class.middleware_zone :invalid_zone }
          .to raise_error(ArgumentError, /Invalid middleware zone/)
      end
    end

    context "when getting a zone" do
      it "returns the set zone" do
        test_class = Class.new(described_class)
        test_class.middleware_zone :security
        expect(test_class.middleware_zone).to eq(:security)
      end

      it "inherits zone from parent class" do
        parent_class = Class.new(described_class)
        parent_class.middleware_zone :routing

        child_class = Class.new(parent_class)
        expect(child_class.middleware_zone).to eq(:routing)
      end

      it "allows child to override parent zone" do
        parent_class = Class.new(described_class)
        parent_class.middleware_zone :routing

        child_class = Class.new(parent_class)
        child_class.middleware_zone :post_processing

        expect(child_class.middleware_zone).to eq(:post_processing)
        expect(parent_class.middleware_zone).to eq(:routing)
      end

      it "returns nil if no zone set" do
        test_class = Class.new(described_class)
        expect(test_class.middleware_zone).to be_nil
      end
    end
  end

  describe ".modifies_fields" do
    it "declares modified fields" do
      test_class = Class.new(described_class)
      test_class.modifies_fields :field1, :field2

      expect(test_class.modifies_fields).to eq(%i[field1 field2])
    end

    it "returns empty array if no fields declared" do
      test_class = Class.new(described_class)
      expect(test_class.modifies_fields).to eq([])
    end

    it "allows multiple declarations" do
      test_class = Class.new(described_class)
      test_class.modifies_fields :field1
      test_class.modifies_fields :field2, :field3

      # Last declaration wins
      expect(test_class.modifies_fields).to eq(%i[field2 field3])
    end
  end

  describe "#initialize" do
    it "stores the next app in chain" do
      middleware = test_middleware_class.new(final_app)
      expect(middleware.instance_variable_get(:@app)).to eq(final_app)
    end
  end

  describe "#call" do
    context "with abstract base class" do
      it "raises NotImplementedError" do
        abstract_middleware = Class.new(described_class).new(final_app)
        expect { abstract_middleware.call(event_data) }
          .to raise_error(NotImplementedError, /must implement #call/)
      end
    end

    context "with implemented middleware" do
      it "processes event and continues chain" do
        result = middleware.call(event_data)

        expect(result[:processed]).to be true
        expect(result[:final]).to be true
      end

      it "passes event_data through middleware chain" do
        middleware1 = Class.new(described_class) do
          def call(event_data)
            event_data[:step1] = true
            @app.call(event_data)
          end
        end

        middleware2 = Class.new(described_class) do
          def call(event_data)
            event_data[:step2] = true
            @app.call(event_data)
          end
        end

        # Build chain: middleware1 -> middleware2 -> final_app
        chain = middleware1.new(middleware2.new(final_app))
        result = chain.call(event_data)

        expect(result[:step1]).to be true
        expect(result[:step2]).to be true
        expect(result[:final]).to be true
      end
    end
  end

  describe "ADR-015 compliance" do
    it "defines all required zones in order" do
      expected_zones = %i[
        pre_processing
        security
        routing
        post_processing
        adapters
      ]

      expect(described_class::VALID_ZONES).to eq(expected_zones)
    end

    it "supports zone-based configuration" do
      test_class = Class.new(described_class)
      test_class.middleware_zone :security

      expect(test_class.middleware_zone).to eq(:security)
    end

    it "supports field modification declarations" do
      test_class = Class.new(described_class)
      test_class.modifies_fields :trace_id, :timestamp

      expect(test_class.modifies_fields).to include(:trace_id, :timestamp)
    end
  end

  describe "UC-001 compliance" do
    it "supports middleware chain pattern" do
      middleware1 = Class.new(described_class) do
        def call(event_data)
          event_data[:middleware1] = true
          @app.call(event_data)
        end
      end

      middleware2 = Class.new(described_class) do
        def call(event_data)
          event_data[:middleware2] = true
          @app.call(event_data)
        end
      end

      chain = middleware1.new(middleware2.new(final_app))
      result = chain.call(event_data)

      expect(result[:middleware1]).to be true
      expect(result[:middleware2]).to be true
      expect(result[:final]).to be true
    end
  end
end
