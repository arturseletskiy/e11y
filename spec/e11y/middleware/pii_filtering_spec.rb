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

      context "when exclude_adapters present (per-adapter Tier 3)" do
        let(:event_class) do
          Class.new(E11y::Event::Base) do
            def self.name
              "Events::UserWithAudit"
            end

            schema do
              required(:email).filled(:string)
              required(:user_id).filled(:string)
            end

            contains_pii true

            pii_filtering do
              field :email do
                strategy :hash
                exclude_adapters [:file_audit]
              end
              allows :user_id
            end
          end
        end

        it "produces payload_rewrites with original for excluded adapter" do
          event_data = {
            event_class: event_class,
            adapters: %i[memory file_audit],
            payload: { email: "user@example.com", user_id: "u-123" }
          }

          result = middleware.call(event_data)

          expect(result[:payload_rewrites]).to be_a(Hash)
          expect(result[:payload_rewrites][:file_audit]).to eq(email: "user@example.com")
          expect(result[:payload_rewrites][:memory]).to be_nil
          expect(result[:payload][:email]).to match(/^hashed_[a-f0-9]{16}$/)
        end
      end
    end

    context "when using inheritance (child inherits and overrides parent pii_filtering)" do
      let(:parent_class) do
        Class.new(E11y::Event::Base) do
          def self.name
            "Events::BaseUserEvent"
          end

          schema do
            required(:email).filled(:string)
            required(:password).filled(:string)
          end

          contains_pii true

          pii_filtering do
            hashes :email
            masks :password
          end
        end
      end

      let(:child_class) do
        Class.new(parent_class) do
          def self.name
            "Events::PaymentCreated"
          end

          schema do
            required(:email).filled(:string)
            required(:password).filled(:string)
            required(:card_number).filled(:string)
          end

          pii_filtering do
            masks :card_number
          end
        end
      end

      it "child inherits parent rules and adds own" do
        event_data = {
          event_class: child_class,
          payload: {
            email: "user@example.com",
            password: "secret",
            card_number: "4111111111111111"
          }
        }

        result = middleware.call(event_data)

        expect(result[:payload][:email]).to match(/^hashed_[a-f0-9]{16}$/)
        expect(result[:payload][:password]).to eq("[FILTERED]")
        expect(result[:payload][:card_number]).to eq("[FILTERED]")
      end

      it "child without pii_filtering inherits parent config" do
        child_no_override = Class.new(parent_class) do
          def self.name
            "Events::UserLogin"
          end

          schema do
            required(:email).filled(:string)
            required(:password).filled(:string)
          end
        end

        event_data = {
          event_class: child_no_override,
          payload: {
            email: "user@example.com",
            password: "secret"
          }
        }

        result = middleware.call(event_data)

        expect(result[:payload][:email]).to match(/^hashed_[a-f0-9]{16}$/)
        expect(result[:payload][:password]).to eq("[FILTERED]")
      end
    end

    context "when event class has unknown filtering_mode" do
      let(:event_class) do
        Class.new(E11y::Event::Base) do
          def self.name
            "Events::InvalidModeEvent"
          end

          schema do
            required(:data).filled(:string)
          end

          def self.pii_filtering_mode
            :unknown
          end
        end
      end

      it "falls back to no filtering (safe default)" do
        event_data = {
          event_class: event_class,
          payload: {
            data: "sensitive-data-12345"
          }
        }

        result = middleware.call(event_data)

        # Unknown tier should fallback to no filtering (line 79)
        expect(result[:payload][:data]).to eq("sensitive-data-12345")
      end
    end

    context "when event class does not respond to pii_filtering_mode" do
      let(:event_class) do
        Class.new(E11y::Event::Base) do
          def self.name
            "Events::NoModeEvent"
          end

          schema do
            required(:order_id).filled(:string)
          end
        end
      end

      before do
        allow(event_class).to receive(:respond_to?).and_call_original
        allow(event_class).to receive(:respond_to?).with(:pii_filtering_mode).and_return(false)
        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(described_class).to receive(:parameter_filter).and_return(
          ActiveSupport::ParameterFilter.new(%i[password])
        )
        # rubocop:enable RSpec/AnyInstance
      end

      it "defaults to :rails_filters" do
        event_data = {
          event_class: event_class,
          payload: {
            order_id: "o123",
            password: "secret"
          }
        }

        result = middleware.call(event_data)

        expect(result[:payload][:order_id]).to eq("o123")
        expect(result[:payload][:password]).to eq("[FILTERED]")
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

    context "with partial masking strategy" do
      let(:event_class_partial) do
        Class.new(E11y::Event::Base) do
          def self.name
            "Events::PartialMaskingEvent"
          end

          schema do
            required(:email_field).filled(:string)
            required(:generic_field).filled(:string)
          end

          contains_pii true

          pii_filtering do
            partials :email_field, :generic_field
          end
        end
      end

      let(:middleware) { described_class.new(app) }

      it "handles email format correctly" do
        event_data = {
          event_class: event_class_partial,
          payload: {
            email_field: "alice@example.com",
            generic_field: "test"
          }
        }

        result = middleware.call(event_data)

        # Email: show first 2 chars + *** + last 3 chars of domain
        expect(result[:payload][:email_field]).to eq("al***com")
      end

      it "handles generic strings correctly" do
        event_data = {
          event_class: event_class_partial,
          payload: {
            email_field: "test@test.com",
            generic_field: "verylongpassword123"
          }
        }

        result = middleware.call(event_data)

        # Generic: show first 2 + *** + last 2 chars
        expect(result[:payload][:generic_field]).to eq("ve***23")
      end

      it "handles short strings (< 4 chars) by fully masking" do
        event_data = {
          event_class: event_class_partial,
          payload: {
            email_field: "x",
            generic_field: "abc"
          }
        }

        result = middleware.call(event_data)

        # Short strings (< 4 chars) are fully masked for security
        expect(result[:payload][:email_field]).to eq("[FILTERED]")
        expect(result[:payload][:generic_field]).to eq("[FILTERED]")
      end

      it "handles minimum length strings (4 chars) correctly" do
        event_data = {
          event_class: event_class_partial,
          payload: {
            email_field: "test@test.com",
            generic_field: "abcd"
          }
        }

        result = middleware.call(event_data)

        # 4+ chars strings get partial masking
        expect(result[:payload][:generic_field]).to eq("ab***cd")
      end
    end

    context "with hash strategy consistency" do
      let(:event_class_hash) do
        Class.new(E11y::Event::Base) do
          def self.name
            "Events::HashConsistencyEvent"
          end

          schema do
            required(:hash_field).filled(:string)
          end

          contains_pii true

          pii_filtering do
            hashes :hash_field
          end
        end
      end

      it "produces consistent hashes for same input" do
        event_data1 = {
          event_class: event_class_hash,
          payload: { hash_field: "same_value" }
        }

        event_data2 = {
          event_class: event_class_hash,
          payload: { hash_field: "same_value" }
        }

        result1 = middleware.call(event_data1)
        result2 = middleware.call(event_data2)

        expect(result1[:payload][:hash_field]).to eq(result2[:payload][:hash_field])
        expect(result1[:payload][:hash_field]).to match(/^hashed_[a-f0-9]{16}$/)
      end

      it "produces different hashes for different inputs" do
        event_data1 = {
          event_class: event_class_hash,
          payload: { hash_field: "value1" }
        }

        event_data2 = {
          event_class: event_class_hash,
          payload: { hash_field: "value2" }
        }

        result1 = middleware.call(event_data1)
        result2 = middleware.call(event_data2)

        expect(result1[:payload][:hash_field]).not_to eq(result2[:payload][:hash_field])
      end
    end

    context "with unknown strategy" do
      let(:event_class_unknown) do
        Class.new(E11y::Event::Base) do
          def self.name
            "Events::UnknownStrategyEvent"
          end

          schema do
            required(:test_field).filled(:string)
          end

          contains_pii true

          pii_filtering do
            # We'll override the config to inject unknown strategy
          end

          # Override pii_filtering_config to return unknown strategy
          def self.pii_filtering_config
            {
              fields: {
                test_field: { strategy: :unknown_invalid_strategy }
              }
            }
          end
        end
      end

      it "falls back to :allow strategy for unknown strategies (line 171)" do
        event_data = {
          event_class: event_class_unknown,
          payload: {
            test_field: "original_value"
          }
        }

        result = middleware.call(event_data)

        # Unknown strategy should fallback to allow (keep original)
        expect(result[:payload][:test_field]).to eq("original_value")
      end
    end
  end

  describe "Pattern-Based Filtering" do
    # Use :content (not in allows) so pattern filtering runs. "allows" skips pattern filtering.
    let(:event_class) do
      Class.new(E11y::Event::Base) do
        def self.name
          "Events::TestEvent"
        end

        schema do
          required(:content).filled(:string)
        end

        contains_pii true

        pii_filtering do
          allows :message # content is NOT allowed, so pattern filtering applies
        end
      end
    end

    it "filters email patterns in content" do
      event_data = {
        event_class: event_class,
        payload: {
          content: "Contact us at support@example.com"
        }
      }

      result = middleware.call(event_data)

      expect(result[:payload][:content]).not_to include("support@example.com")
      expect(result[:payload][:content]).to include("[FILTERED]")
    end

    it "filters SSN patterns" do
      event_data = {
        event_class: event_class,
        payload: {
          content: "SSN: 123-45-6789"
        }
      }

      result = middleware.call(event_data)

      expect(result[:payload][:content]).not_to include("123-45-6789")
    end

    it "filters credit card patterns" do
      event_data = {
        event_class: event_class,
        payload: {
          content: "Card: 4111 1111 1111 1111"
        }
      }

      result = middleware.call(event_data)

      expect(result[:payload][:content]).not_to include("4111 1111 1111 1111")
    end

    it "filters IP addresses" do
      event_data = {
        event_class: event_class,
        payload: {
          content: "From IP: 192.168.1.100"
        }
      }

      result = middleware.call(event_data)

      expect(result[:payload][:content]).not_to include("192.168.1.100")
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

    context "with arrays in payload" do
      # Use :logs (not in allows) so pattern filtering runs on array elements
      let(:event_class_array) do
        Class.new(E11y::Event::Base) do
          def self.name
            "Events::ArrayEvent"
          end

          schema do
            required(:logs).filled(:array)
          end

          contains_pii true

          pii_filtering do
            allows :items # logs is NOT allowed, so pattern filtering applies
          end
        end
      end

      it "applies pattern filtering to arrays (line 189)" do
        event_data = {
          event_class: event_class_array,
          payload: {
            logs: [
              "User email: john@example.com",
              "Another user: alice@test.com",
              "No PII here"
            ]
          }
        }

        result = middleware.call(event_data)

        # Emails should be filtered in all array elements
        expect(result[:payload][:logs][0]).not_to include("john@example.com")
        expect(result[:payload][:logs][1]).not_to include("alice@test.com")
        expect(result[:payload][:logs][2]).to eq("No PII here")
      end

      it "handles nested arrays correctly" do
        event_data = {
          event_class: event_class_array,
          payload: {
            logs: [
              ["email1@test.com", "email2@test.com"],
              ["192.168.1.1", "text"]
            ]
          }
        }

        result = middleware.call(event_data)

        # Pattern filtering should work recursively in nested arrays
        expect(result[:payload][:logs][0][0]).not_to include("email1@test.com")
        expect(result[:payload][:logs][1][0]).not_to include("192.168.1.1")
      end
    end
  end

  describe "Edge Cases and Data Integrity" do
    # Use :info (not in allows) for mutation test so pattern filtering runs on nested email
    let(:event_class_edge) do
      Class.new(E11y::Event::Base) do
        def self.name
          "Events::EdgeCaseEvent"
        end

        schema do
          required(:info).filled
        end

        contains_pii true

        pii_filtering do
          allows :data # info is NOT allowed, so pattern filtering applies
        end
      end
    end

    it "handles nil values gracefully" do
      event_data = {
        event_class: event_class_edge,
        payload: {
          info: nil
        }
      }

      result = middleware.call(event_data)

      expect(result[:payload][:info]).to be_nil
    end

    it "handles empty strings" do
      event_data = {
        event_class: event_class_edge,
        payload: {
          info: ""
        }
      }

      result = middleware.call(event_data)

      expect(result[:payload][:info]).to eq("")
    end

    it "handles empty hashes" do
      event_data = {
        event_class: event_class_edge,
        payload: {
          info: {}
        }
      }

      result = middleware.call(event_data)

      expect(result[:payload][:info]).to eq({})
    end

    it "handles empty arrays" do
      event_data = {
        event_class: event_class_edge,
        payload: {
          info: []
        }
      }

      result = middleware.call(event_data)

      expect(result[:payload][:info]).to eq([])
    end

    it "prevents mutation of original data (deep_dup)" do
      original_payload = {
        info: {
          nested: %w[value1 value2],
          email: "test@example.com"
        }
      }

      event_data = {
        event_class: event_class_edge,
        payload: original_payload
      }

      # Call middleware
      result = middleware.call(event_data)

      # Original should be unchanged
      expect(original_payload[:info][:nested]).to eq(%w[value1 value2])
      expect(original_payload[:info][:email]).to eq("test@example.com")

      # Result should be filtered
      expect(result[:payload][:info][:email]).not_to eq("test@example.com")
    end

    it "handles complex nested structures with arrays (line 250)" do
      event_data = {
        event_class: event_class_edge,
        payload: {
          info: {
            users: [
              { name: "John", email: "john@test.com" },
              { name: "Alice", email: "alice@test.com" }
            ],
            settings: {
              notifications: %w[email sms],
              preferences: { theme: "dark" }
            }
          }
        }
      }

      result = middleware.call(event_data)

      # Should handle deep nesting with arrays
      expect(result[:payload][:info][:users]).to be_an(Array)
      expect(result[:payload][:info][:settings][:notifications]).to eq(%w[email sms])
    end

    context "with unduplicatable objects" do
      it "handles objects that cannot be duplicated (line 257)" do
        # Create a custom object that raises on dup
        unduplicatable = Class.new do
          def dup
            raise TypeError, "can't dup"
          end

          def to_s
            "unduplicatable_object"
          end
        end.new

        event_data = {
          event_class: event_class_edge,
          payload: {
            info: unduplicatable
          }
        }

        # Should handle the error gracefully and return original
        expect { middleware.call(event_data) }.not_to raise_error
        result = middleware.call(event_data)
        expect(result[:payload][:info]).to eq(unduplicatable)
      end
    end
  end

  # NOTE: "Non-Rails Environment" tests removed after adding rails dependency to gemspec.
  # E11y is now a Rails-only gem (see e11y.gemspec: spec.add_dependency "rails", ">= 7.0")
end
