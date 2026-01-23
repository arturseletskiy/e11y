# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Events::BasePaymentEvent do
  # Create a concrete payment event class for testing
  let(:concrete_payment_event) do
    Class.new(described_class) do
      def self.name
        "TestPaymentEvent"
      end

      schema do
        required(:payment_id).filled(:integer)
        required(:amount).filled(:float)
        required(:currency).filled(:string)
      end
    end
  end

  describe "inheritance" do
    it "inherits from E11y::Event::Base" do
      expect(described_class.superclass).to eq(E11y::Event::Base)
    end

    it "is a valid Event::Base subclass" do
      expect(described_class.ancestors).to include(E11y::Event::Base)
    end
  end

  describe "preset inclusion" do
    it "includes E11y::Presets::HighValueEvent" do
      expect(described_class.ancestors).to include(E11y::Presets::HighValueEvent)
    end

    it "has unlimited rate limit from HighValueEvent preset" do
      expect(concrete_payment_event.resolve_rate_limit).to be_nil
    end

    it "has 100% sample rate from HighValueEvent preset" do
      expect(concrete_payment_event.resolve_sample_rate).to eq(1.0)
    end
  end

  describe "rate limiting behavior" do
    it "returns nil (unlimited) to never drop payment events" do
      # Critical: Payment events must NEVER be dropped
      expect(concrete_payment_event.resolve_rate_limit).to be_nil
    end

    it "ensures payment events are never rate-limited regardless of load" do
      # Business requirement: Never lose payment data
      expect(described_class).to respond_to(:resolve_rate_limit)
      expect(concrete_payment_event.resolve_rate_limit).to be_nil
    end
  end

  describe "sampling behavior" do
    it "returns 1.0 (100%) to track all payment events" do
      # Critical: ALL payment events must be tracked for financial accuracy
      expect(concrete_payment_event.resolve_sample_rate).to eq(1.0)
    end

    it "ensures no payment events are missed" do
      # Business requirement: 100% payment tracking
      expect(described_class).to respond_to(:resolve_sample_rate)
      expect(concrete_payment_event.resolve_sample_rate).to eq(1.0)
    end
  end

  describe "schema definition" do
    it "allows subclasses to define payment-specific schemas" do
      expect { concrete_payment_event }.not_to raise_error
    end

    it "supports schema validation" do
      expect(concrete_payment_event).to respond_to(:schema)
    end
  end

  describe "high-value requirements" do
    it "has unlimited rate limit for payment protection" do
      # High-value events (payments, transactions) must never be dropped
      expect(concrete_payment_event.resolve_rate_limit).to be_nil
    end

    it "has 100% sampling for complete payment tracking" do
      # All payment events must be tracked for financial accuracy
      expect(concrete_payment_event.resolve_sample_rate).to eq(1.0)
    end
  end

  describe "multiple payment event subclasses" do
    it "all subclasses maintain high-value behavior" do
      payment_types = %w[Processed Refunded Failed].map do |type|
        Class.new(described_class) do
          define_singleton_method(:name) { "Payment#{type}Event" }

          schema do
            required(:payment_id).filled(:integer)
            required(:amount).filled(:float)
          end
        end
      end

      payment_types.each do |payment_class|
        expect(payment_class.resolve_rate_limit).to be_nil
        expect(payment_class.resolve_sample_rate).to eq(1.0)
      end
    end
  end

  describe "consistency with HighValueEvent preset" do
    it "inherits all HighValueEvent preset behavior" do
      # Should have same behavior as if HighValueEvent preset was directly included
      expect(concrete_payment_event.resolve_rate_limit).to be_nil
      expect(concrete_payment_event.resolve_sample_rate).to eq(1.0)
      expect(concrete_payment_event.ancestors).to include(E11y::Presets::HighValueEvent)
    end
  end
end
