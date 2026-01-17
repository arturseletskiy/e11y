# frozen_string_literal: true

require "spec_helper"
require "e11y/middleware/validation"
require "e11y/event/base"

RSpec.describe E11y::Middleware::Validation do
  let(:final_app) { ->(event_data) { event_data } }
  let(:middleware) { described_class.new(final_app) }

  # Test event classes
  let(:schema_event_class) do
    Class.new(E11y::Event::Base) do
      def self.name
        "Events::OrderPaid"
      end

      schema do
        required(:order_id).filled(:integer)
        required(:amount).filled(:float)
        optional(:currency).filled(:string)
      end
    end
  end

  let(:schema_less_event_class) do
    Class.new(E11y::Event::Base) do
      def self.name
        "Events::SimpleEvent"
      end
      # No schema defined
    end
  end

  describe ".middleware_zone" do
    it "declares pre_processing zone" do
      expect(described_class.middleware_zone).to eq(:pre_processing)
    end
  end

  describe "#call" do
    context "with valid payload" do
      it "passes event through unchanged" do
        event_data = {
          event_class: schema_event_class,
          payload: { order_id: 123, amount: 99.99 }
        }

        result = middleware.call(event_data)

        expect(result).to eq(event_data)
      end

      it "calls the next middleware in the chain" do
        event_data = {
          event_class: schema_event_class,
          payload: { order_id: 123, amount: 99.99 }
        }

        allow(final_app).to receive(:call).and_call_original

        middleware.call(event_data)

        expect(final_app).to have_received(:call).with(event_data)
      end

      it "increments passed metric" do
        event_data = {
          event_class: schema_event_class,
          payload: { order_id: 123, amount: 99.99 }
        }

        allow(middleware).to receive(:increment_metric)

        middleware.call(event_data)

        expect(middleware).to have_received(:increment_metric)
          .with("e11y.middleware.validation.passed")
      end

      it "allows optional fields to be omitted" do
        event_data = {
          event_class: schema_event_class,
          payload: { order_id: 123, amount: 99.99 } # currency omitted
        }

        expect { middleware.call(event_data) }.not_to raise_error
      end

      it "allows optional fields to be present" do
        event_data = {
          event_class: schema_event_class,
          payload: { order_id: 123, amount: 99.99, currency: "USD" }
        }

        expect { middleware.call(event_data) }.not_to raise_error
      end
    end

    context "with invalid payload" do
      it "raises ValidationError for missing required field" do
        event_data = {
          event_class: schema_event_class,
          payload: { amount: 99.99 } # order_id missing
        }

        expect { middleware.call(event_data) }
          .to raise_error(E11y::ValidationError, /order_id.*missing/)
      end

      it "raises ValidationError for wrong type" do
        event_data = {
          event_class: schema_event_class,
          payload: { order_id: "invalid", amount: 99.99 } # order_id should be integer
        }

        expect { middleware.call(event_data) }
          .to raise_error(E11y::ValidationError, /order_id/)
      end

      it "includes event class name in error message" do
        event_data = {
          event_class: schema_event_class,
          payload: { order_id: "invalid", amount: 99.99 }
        }

        expect { middleware.call(event_data) }
          .to raise_error(E11y::ValidationError, /Events::OrderPaid/)
      end

      it "includes field names in error message" do
        event_data = {
          event_class: schema_event_class,
          payload: {} # All required fields missing
        }

        error_raised = false
        error_message = nil

        begin
          middleware.call(event_data)
        rescue E11y::ValidationError => e
          error_raised = true
          error_message = e.message
        end

        expect(error_raised).to be true
        expect(error_message).to match(/order_id/)
        expect(error_message).to match(/amount/)
      end

      it "increments failed metric" do
        event_data = {
          event_class: schema_event_class,
          payload: { order_id: "invalid", amount: 99.99 }
        }

        allow(middleware).to receive(:increment_metric)

        expect { middleware.call(event_data) }.to raise_error(E11y::ValidationError)

        expect(middleware).to have_received(:increment_metric)
          .with("e11y.middleware.validation.failed")
      end
    end

    context "with schema-less events" do
      it "skips validation and passes event through" do
        event_data = {
          event_class: schema_less_event_class,
          payload: { anything: "goes" }
        }

        result = middleware.call(event_data)

        expect(result).to eq(event_data)
      end

      it "increments skipped metric" do
        event_data = {
          event_class: schema_less_event_class,
          payload: { anything: "goes" }
        }

        allow(middleware).to receive(:increment_metric)

        middleware.call(event_data)

        expect(middleware).to have_received(:increment_metric)
          .with("e11y.middleware.validation.skipped")
      end
    end

    context "with missing event_class or payload" do
      it "skips validation if event_class is missing" do
        event_data = { payload: { order_id: 123 } }

        result = middleware.call(event_data)

        expect(result).to eq(event_data)
      end

      it "skips validation if payload is missing" do
        event_data = { event_class: schema_event_class }

        result = middleware.call(event_data)

        expect(result).to eq(event_data)
      end
    end
  end

  describe "ADR-015 compliance" do
    it "runs in pre_processing zone" do
      expect(described_class.middleware_zone).to eq(:pre_processing)
    end

    # rubocop:disable RSpec/ExampleLength
    it "uses original class name for validation (V2 ≠ V1)" do
      # Simulate versioned event classes
      v1_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::OrderPaid"
        end

        schema do
          required(:order_id).filled(:integer)
          # No currency field in V1
        end
      end

      v2_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::OrderPaidV2"
        end

        schema do
          required(:order_id).filled(:integer)
          required(:currency).filled(:string) # New field in V2
        end
      end

      # V1 event without currency - valid
      v1_event = {
        event_class: v1_class,
        payload: { order_id: 123 }
      }

      expect { middleware.call(v1_event) }.not_to raise_error

      # V2 event without currency - invalid
      v2_event = {
        event_class: v2_class,
        payload: { order_id: 123 } # Currency missing!
      }

      expect { middleware.call(v2_event) }
        .to raise_error(E11y::ValidationError, /currency/)
    end
    # rubocop:enable RSpec/ExampleLength

    it "validates BEFORE PII filtering (ADR-015 §3.1 line 96)" do
      # Validation should happen on original data (including PII)
      event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::UserRegistered"
        end

        schema do
          required(:email).filled(:string)
        end
      end

      event_data = {
        event_class: event_class,
        payload: { email: "user@example.com" } # PII present
      }

      # Validation should pass (PII not yet filtered)
      expect { middleware.call(event_data) }.not_to raise_error
    end
  end

  describe "integration" do
    it "works with full pipeline execution" do
      # Simulate multi-middleware pipeline
      middleware2 = Class.new(E11y::Middleware::Base) do
        def call(event_data)
          event_data[:middleware2] = true
          @app.call(event_data)
        end
      end

      pipeline = middleware2.new(middleware)
      event_data = {
        event_class: schema_event_class,
        payload: { order_id: 123, amount: 99.99 }
      }

      result = pipeline.call(event_data)

      expect(result[:middleware2]).to be true
    end

    it "prevents invalid events from reaching downstream middlewares" do
      downstream_called = false

      downstream_middleware = lambda do |_event_data|
        downstream_called = true
        nil
      end

      validation_middleware = described_class.new(downstream_middleware)
      event_data = {
        event_class: schema_event_class,
        payload: { order_id: "invalid", amount: 99.99 }
      }

      expect { validation_middleware.call(event_data) }
        .to raise_error(E11y::ValidationError)

      expect(downstream_called).to be false
    end
  end
end
