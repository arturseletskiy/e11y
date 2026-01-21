# frozen_string_literal: true

require "spec_helper"
require "active_support/parameter_filter"

RSpec.describe E11y::Middleware::PIIFilter do
  let(:app) { ->(event_data) { event_data } }
  let(:middleware) { described_class.new(app) }

  describe "PII Filtering - 3-Tier Strategy" do
    context "when using Tier 1: No PII (contains_pii false)" do
      let(:event_class) do
        Class.new(E11y::Event::Base) do
          def self.name
            "Events::HealthCheck"
          end

          schema do
            required(:status).filled(:string)
            required(:uptime_ms).filled(:integer)
          end

          contains_pii false
        end
      end

      it "skips PII filtering" do
        event_data = {
          event_class: event_class,
          payload: {
            status: "ok",
            uptime_ms: 12_345
          }
        }

        result = middleware.call(event_data)

        expect(result[:payload][:status]).to eq("ok")
        expect(result[:payload][:uptime_ms]).to eq(12_345)
      end
    end

    context "when using Tier 2: Rails filters (default)" do
      before do
        # rubocop:disable RSpec/AnyInstance
        # Mocking Rails parameter_filter which is a private method
        # Mock Rails filter_parameters
        allow_any_instance_of(described_class).to receive(:parameter_filter).and_return(
          ActiveSupport::ParameterFilter.new(%i[password api_key token])
        )
        # rubocop:enable RSpec/AnyInstance
      end

      let(:event_class) do
        Class.new(E11y::Event::Base) do
          def self.name
            "Events::OrderCreated"
          end

          schema do
            required(:order_id).filled(:string)
            optional(:api_key).filled(:string)
          end
        end
      end

      it "applies Rails filter_parameters" do
        event_data = {
          event_class: event_class,
          payload: {
            order_id: "o123",
            api_key: "sk_live_secret"
          }
        }

        result = middleware.call(event_data)

        expect(result[:payload][:order_id]).to eq("o123")
        expect(result[:payload][:api_key]).to eq("[FILTERED]")
      end
    end

    context "when using Tier 3: Explicit PII (contains_pii true)" do
      let(:event_class) do
        Class.new(E11y::Event::Base) do
          def self.name
            "Events::UserRegistered"
          end

          schema do
            required(:email).filled(:string)
            required(:password).filled(:string)
            required(:user_id).filled(:string)
          end

          contains_pii true

          pii_filtering do
            hashes :email
            masks :password
            allows :user_id
          end
        end
      end

      it "applies field-level strategies" do
        event_data = {
          event_class: event_class,
          payload: {
            email: "user@example.com",
            password: "secret123",
            user_id: "u-123"
          }
        }

        result = middleware.call(event_data)

        expect(result[:payload][:email]).to match(/^hashed_[a-f0-9]{16}$/)
        expect(result[:payload][:password]).to eq("[FILTERED]")
        expect(result[:payload][:user_id]).to eq("u-123")
      end
    end
  end

  describe "Field Strategies" do
    let(:event_class) do
      Class.new(E11y::Event::Base) do
        def self.name
          "Events::TestEvent"
        end

        schema do
          required(:mask_field).filled(:string)
          required(:hash_field).filled(:string)
          required(:partial_field).filled(:string)
          required(:redact_field).filled(:string)
          required(:allow_field).filled(:string)
        end

        contains_pii true

        pii_filtering do
          masks :mask_field
          hashes :hash_field
          partials :partial_field
          redacts :redact_field
          allows :allow_field
        end
      end
    end

    it "applies :mask strategy" do
      event_data = {
        event_class: event_class,
        payload: {
          mask_field: "secret_value",
          hash_field: "hash_me",
          partial_field: "partial_me",
          redact_field: "redact_me",
          allow_field: "keep_me"
        }
      }

      result = middleware.call(event_data)

      expect(result[:payload][:mask_field]).to eq("[FILTERED]")
    end

    it "applies :hash strategy" do
      event_data = {
        event_class: event_class,
        payload: {
          mask_field: "secret",
          hash_field: "hash_me",
          partial_field: "partial",
          redact_field: "redact",
          allow_field: "keep"
        }
      }

      result = middleware.call(event_data)

      expect(result[:payload][:hash_field]).to match(/^hashed_[a-f0-9]{16}$/)
      expect(result[:payload][:hash_field]).not_to eq("hash_me")
    end

    it "applies :partial strategy" do
      event_data = {
        event_class: event_class,
        payload: {
          mask_field: "secret",
          hash_field: "hash",
          partial_field: "user@example.com",
          redact_field: "redact",
          allow_field: "keep"
        }
      }

      result = middleware.call(event_data)

      expect(result[:payload][:partial_field]).to eq("us***com")
    end

    it "applies :redact strategy" do
      event_data = {
        event_class: event_class,
        payload: {
          mask_field: "secret",
          hash_field: "hash",
          partial_field: "partial",
          redact_field: "redact_me",
          allow_field: "keep"
        }
      }

      result = middleware.call(event_data)

      expect(result[:payload][:redact_field]).to be_nil
    end

    it "applies :allow strategy" do
      event_data = {
        event_class: event_class,
        payload: {
          mask_field: "secret",
          hash_field: "hash",
          partial_field: "partial",
          redact_field: "redact",
          allow_field: "keep_original"
        }
      }

      result = middleware.call(event_data)

      expect(result[:payload][:allow_field]).to eq("keep_original")
    end
  end

  describe "Pattern-Based Filtering" do
    let(:event_class) do
      Class.new(E11y::Event::Base) do
        def self.name
          "Events::TestEvent"
        end

        schema do
          required(:message).filled(:string)
        end

        contains_pii true

        pii_filtering do
          allows :message
        end
      end
    end

    it "filters email patterns in content" do
      event_data = {
        event_class: event_class,
        payload: {
          message: "Contact us at support@example.com"
        }
      }

      result = middleware.call(event_data)

      expect(result[:payload][:message]).not_to include("support@example.com")
      expect(result[:payload][:message]).to include("[FILTERED]")
    end

    it "filters SSN patterns" do
      event_data = {
        event_class: event_class,
        payload: {
          message: "SSN: 123-45-6789"
        }
      }

      result = middleware.call(event_data)

      expect(result[:payload][:message]).not_to include("123-45-6789")
    end

    it "filters credit card patterns" do
      event_data = {
        event_class: event_class,
        payload: {
          message: "Card: 4111 1111 1111 1111"
        }
      }

      result = middleware.call(event_data)

      expect(result[:payload][:message]).not_to include("4111 1111 1111 1111")
    end

    it "filters IP addresses" do
      event_data = {
        event_class: event_class,
        payload: {
          message: "From IP: 192.168.1.100"
        }
      }

      result = middleware.call(event_data)

      expect(result[:payload][:message]).not_to include("192.168.1.100")
    end
  end

  describe "Nested Data Filtering" do
    let(:event_class) do
      Class.new(E11y::Event::Base) do
        def self.name
          "Events::NestedEvent"
        end

        schema do
          required(:user).filled(:hash)
        end

        contains_pii true

        pii_filtering do
          masks :user
        end
      end
    end

    it "applies pattern filtering to nested hashes" do
      event_data = {
        event_class: event_class,
        payload: {
          user: {
            name: "John Doe",
            contact: {
              email: "john@example.com",
              phone: "555-1234"
            }
          }
        }
      }

      result = middleware.call(event_data)

      # First mask the whole :user field
      expect(result[:payload][:user]).to eq("[FILTERED]")
    end
  end
end
