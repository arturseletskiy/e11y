# frozen_string_literal: true

require "spec_helper"
require "e11y/sampling/value_extractor"

RSpec.describe E11y::Sampling::ValueExtractor do
  subject(:extractor) { described_class.new }

  describe "#extract" do
    context "with top-level numeric fields" do
      let(:event_data) { { amount: 1500, count: 42 } }

      it "extracts integer values as floats" do
        expect(extractor.extract(event_data, :amount)).to eq(1500.0)
        expect(extractor.extract(event_data, :count)).to eq(42.0)
      end

      it "extracts float values" do
        event_data[:price] = 99.99
        expect(extractor.extract(event_data, :price)).to eq(99.99)
      end
    end

    context "with nested fields" do
      let(:event_data) do
        {
          user: {
            balance: 5000,
            account: {
              credit_limit: 10_000
            }
          }
        }
      end

      it "extracts nested values using dot notation" do
        expect(extractor.extract(event_data, "user.balance")).to eq(5000.0)
      end

      it "extracts deeply nested values" do
        expect(extractor.extract(event_data, "user.account.credit_limit")).to eq(10_000.0)
      end

      it "returns 0.0 for missing nested fields" do
        expect(extractor.extract(event_data, "user.nonexistent")).to eq(0.0)
      end
    end

    context "with string keys" do
      let(:event_data) do
        {
          "amount" => 2500,
          "user" => { "balance" => 3000 }
        }
      end

      it "extracts values with string keys" do
        expect(extractor.extract(event_data, :amount)).to eq(2500.0)
      end

      it "extracts nested values with string keys" do
        expect(extractor.extract(event_data, "user.balance")).to eq(3000.0)
      end
    end

    context "with type coercion" do
      let(:event_data) do
        {
          string_number: "1234.56",
          string_integer: "789",
          invalid_string: "not a number"
        }
      end

      it "converts numeric strings to floats" do
        expect(extractor.extract(event_data, :string_number)).to eq(1234.56)
        expect(extractor.extract(event_data, :string_integer)).to eq(789.0)
      end

      it "returns 0.0 for non-numeric strings" do
        expect(extractor.extract(event_data, :invalid_string)).to eq(0.0)
      end
    end

    context "with nil and missing values" do
      let(:event_data) { { existing_field: 100 } }

      it "returns 0.0 for missing fields" do
        expect(extractor.extract(event_data, :nonexistent_field)).to eq(0.0)
      end

      it "returns 0.0 for nil values" do
        event_data[:nil_field] = nil
        expect(extractor.extract(event_data, :nil_field)).to eq(0.0)
      end
    end

    context "with edge cases" do
      it "returns 0.0 for non-hash event data" do
        expect(extractor.extract(nil, :field)).to eq(0.0)
        expect(extractor.extract("not a hash", :field)).to eq(0.0)
        expect(extractor.extract([], :field)).to eq(0.0)
      end

      it "returns 0.0 for non-numeric types" do
        event_data = { boolean: true, array: [1, 2, 3], hash: { a: 1 } }
        expect(extractor.extract(event_data, :boolean)).to eq(0.0)
        expect(extractor.extract(event_data, :array)).to eq(0.0)
        expect(extractor.extract(event_data, :hash)).to eq(0.0)
      end

      it "handles zero and negative numbers" do
        event_data = { zero: 0, negative: -500, negative_float: -99.99 }
        expect(extractor.extract(event_data, :zero)).to eq(0.0)
        expect(extractor.extract(event_data, :negative)).to eq(-500.0)
        expect(extractor.extract(event_data, :negative_float)).to eq(-99.99)
      end

      it "handles very large numbers" do
        event_data = { large: 999_999_999_999 }
        expect(extractor.extract(event_data, :large)).to eq(999_999_999_999.0)
      end
    end

    context "when testing ADR-009 §3.4 compliance" do
      it "extracts monetary amounts for value-based sampling" do
        payment_event = { payment: { amount: 1500, currency: "USD" } }
        expect(extractor.extract(payment_event, "payment.amount")).to eq(1500.0)
      end

      it "handles decimal amounts" do
        payment_event = { amount: 1234.56 }
        expect(extractor.extract(payment_event, :amount)).to eq(1234.56)
      end
    end

    context "when testing UC-014 examples" do
      it "supports e-commerce transaction amounts" do
        order_event = { order: { total: 2500 } }
        expect(extractor.extract(order_event, "order.total")).to eq(2500.0)
      end

      it "supports user balance checks" do
        balance_event = { user_balance: "5000.00" }
        expect(extractor.extract(balance_event, :user_balance)).to eq(5000.0)
      end
    end
  end
end
