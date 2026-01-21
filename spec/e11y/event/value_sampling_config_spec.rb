# frozen_string_literal: true

require "spec_helper"
require "e11y/event/value_sampling_config"
require "e11y/sampling/value_extractor"

RSpec.describe E11y::Event::ValueSamplingConfig do
  let(:extractor) { E11y::Sampling::ValueExtractor.new }

  describe "#initialize" do
    it "accepts field and comparisons" do
      config = described_class.new(:amount, greater_than: 1000)
      expect(config.field).to eq(:amount)
      expect(config.comparisons).to eq({ greater_than: 1000 })
    end

    it "raises error for empty comparisons" do
      expect do
        described_class.new(:amount, {})
      end.to raise_error(ArgumentError, "At least one comparison required")
    end

    it "raises error for invalid comparison type" do
      expect do
        described_class.new(:amount, invalid_type: 100)
      end.to raise_error(ArgumentError, /Invalid comparison type/)
    end

    it "raises error for non-Range in_range" do
      expect do
        described_class.new(:amount, in_range: 100)
      end.to raise_error(ArgumentError, "in_range requires a Range")
    end

    it "raises error for non-Numeric greater_than" do
      expect do
        described_class.new(:amount, greater_than: "not a number")
      end.to raise_error(ArgumentError, "greater_than requires a Numeric threshold")
    end
  end

  describe "#matches?" do
    context "with greater_than comparison" do
      let(:config) { described_class.new(:amount, greater_than: 1000) }

      it "matches when value > threshold" do
        event_data = { amount: 1500 }
        expect(config.matches?(event_data, extractor)).to be true
      end

      it "does not match when value <= threshold" do
        event_data = { amount: 1000 }
        expect(config.matches?(event_data, extractor)).to be false

        event_data = { amount: 500 }
        expect(config.matches?(event_data, extractor)).to be false
      end
    end

    context "with less_than comparison" do
      let(:config) { described_class.new(:priority, less_than: 5) }

      it "matches when value < threshold" do
        event_data = { priority: 3 }
        expect(config.matches?(event_data, extractor)).to be true
      end

      it "does not match when value >= threshold" do
        event_data = { priority: 5 }
        expect(config.matches?(event_data, extractor)).to be false

        event_data = { priority: 10 }
        expect(config.matches?(event_data, extractor)).to be false
      end
    end

    context "with equals comparison" do
      let(:config) { described_class.new(:status_code, equals: 200) }

      it "matches when value == threshold" do
        event_data = { status_code: 200 }
        expect(config.matches?(event_data, extractor)).to be true
      end

      it "does not match when value != threshold" do
        event_data = { status_code: 404 }
        expect(config.matches?(event_data, extractor)).to be false
      end
    end

    context "with in_range comparison" do
      let(:config) { described_class.new(:score, in_range: 50..100) }

      it "matches when value is in range" do
        event_data = { score: 75 }
        expect(config.matches?(event_data, extractor)).to be true

        event_data = { score: 50 }  # Range start
        expect(config.matches?(event_data, extractor)).to be true

        event_data = { score: 100 } # Range end
        expect(config.matches?(event_data, extractor)).to be true
      end

      it "does not match when value is outside range" do
        event_data = { score: 49 }
        expect(config.matches?(event_data, extractor)).to be false

        event_data = { score: 101 }
        expect(config.matches?(event_data, extractor)).to be false
      end
    end

    context "with multiple comparisons (OR logic)" do
      let(:config) do
        described_class.new(:amount, greater_than: 1000, less_than: 100)
      end

      it "matches if ANY comparison is true" do
        # Matches greater_than
        event_data = { amount: 1500 }
        expect(config.matches?(event_data, extractor)).to be true

        # Matches less_than
        event_data = { amount: 50 }
        expect(config.matches?(event_data, extractor)).to be true
      end

      it "does not match if ALL comparisons are false" do
        # Between 100 and 1000 (fails both comparisons)
        event_data = { amount: 500 }
        expect(config.matches?(event_data, extractor)).to be false
      end
    end

    context "with nested fields" do
      let(:config) { described_class.new("user.balance", greater_than: 5000) }

      it "matches nested field values" do
        event_data = { user: { balance: 6000 } }
        expect(config.matches?(event_data, extractor)).to be true
      end

      it "does not match when nested value is below threshold" do
        event_data = { user: { balance: 3000 } }
        expect(config.matches?(event_data, extractor)).to be false
      end
    end

    context "when testing ADR-009 §3.4 compliance" do
      let(:config) { described_class.new(:amount, greater_than: 1000) }

      it "implements value-based sampling for high-value events" do
        # High-value payment (should be sampled)
        high_value = { amount: 5000 }
        expect(config.matches?(high_value, extractor)).to be true

        # Low-value payment (can be dropped)
        low_value = { amount: 50 }
        expect(config.matches?(low_value, extractor)).to be false
      end
    end
  end
end
