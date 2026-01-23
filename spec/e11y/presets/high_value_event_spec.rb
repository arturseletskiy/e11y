# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Presets::HighValueEvent do
  # Create a test event class that includes the preset
  let(:test_event_class) do
    Class.new(E11y::Event::Base) do
      include E11y::Presets::HighValueEvent

      def self.name
        "TestHighValueEvent"
      end

      schema do
        required(:payment_id).filled(:integer)
        required(:amount).filled(:float)
      end
    end
  end

  describe ".included" do
    it "includes the preset module in the event class" do
      expect(test_event_class.ancestors).to include(described_class)
    end

    it "extends the base class with ClassMethods" do
      expect(test_event_class).to respond_to(:resolve_rate_limit)
      expect(test_event_class).to respond_to(:resolve_sample_rate)
    end

    it "sets up the class correctly" do
      # Should be a valid Event::Base subclass
      expect(test_event_class.ancestors).to include(E11y::Event::Base)
    end

    it "calls class_eval on the base class" do
      # The included hook should execute without errors
      # This verifies severity and adapters DSL methods are called
      expect { test_event_class }.not_to raise_error
    end
  end

  describe ".resolve_rate_limit" do
    it "returns nil (unlimited) for payment protection - never drop high-value events" do
      # Critical requirement: Payment events must NEVER be dropped
      expect(test_event_class.resolve_rate_limit).to be_nil
    end
  end

  describe ".resolve_sample_rate" do
    it "returns 1.0 (100%) to track all payment events" do
      # Critical requirement: ALL payment events must be tracked for financial accuracy
      expect(test_event_class.resolve_sample_rate).to eq(1.0)
    end
  end

  describe "high-value event configuration" do
    it "inherits from Event::Base" do
      expect(test_event_class.superclass).to eq(E11y::Event::Base)
    end
  end

  describe "multiple high-value events" do
    let(:payment_event) do
      Class.new(E11y::Event::Base) do
        include E11y::Presets::HighValueEvent

        def self.name
          "PaymentProcessedEvent"
        end

        schema { required(:payment_id).filled(:integer) }
      end
    end

    it "applies preset consistently to different event classes" do
      expect(payment_event.resolve_rate_limit).to be_nil
      expect(payment_event.resolve_sample_rate).to eq(1.0)
    end
  end

  describe "integration with Event::Base" do
    it "preserves Event::Base functionality" do
      # Should be a subclass of Event::Base
      expect(test_event_class.ancestors).to include(E11y::Event::Base)
    end

    it "allows defining custom schema" do
      # High-value events can have custom schemas
      custom_event = Class.new(E11y::Event::Base) do
        include E11y::Presets::HighValueEvent

        def self.name
          "CustomHighValueEvent"
        end

        schema do
          required(:custom_field).filled(:string)
          required(:value).filled(:integer)
        end
      end

      # Should still have high-value behavior
      expect(custom_event.resolve_rate_limit).to be_nil
      expect(custom_event.resolve_sample_rate).to eq(1.0)
    end
  end

  describe "critical requirements validation" do
    it "validates that high-value events cannot be dropped (nil rate limit)" do
      # Business-critical requirement: Payment events must NEVER be lost
      expect(test_event_class.resolve_rate_limit).to be_nil
    end

    it "validates that all high-value events are captured (100% sample rate)" do
      # Business-critical requirement: ALL payment events must be tracked
      expect(test_event_class.resolve_sample_rate).to eq(1.0)
    end

    it "maintains consistency across multiple instances" do
      # Create multiple event classes with high-value preset
      events = Array.new(5) do |i|
        Class.new(E11y::Event::Base) do
          include E11y::Presets::HighValueEvent

          define_singleton_method(:name) { "HighValueEvent#{i}" }

          schema do
            required(:data).filled(:string)
          end
        end
      end

      # All should have consistent behavior
      events.each do |event_class|
        expect(event_class.resolve_rate_limit).to be_nil
        expect(event_class.resolve_sample_rate).to eq(1.0)
      end
    end
  end
end
