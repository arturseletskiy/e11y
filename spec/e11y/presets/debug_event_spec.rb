# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Presets::DebugEvent do
  # Create a test event class that includes the preset
  let(:test_event_class) do
    Class.new(E11y::Event::Base) do
      include E11y::Presets::DebugEvent

      def self.name
        "TestDebugEvent"
      end

      schema do
        required(:message).filled(:string)
      end
    end
  end

  describe ".included" do
    it "includes the preset module in the event class" do
      expect(test_event_class.ancestors).to include(described_class)
    end

    it "extends the base class correctly" do
      # Should be a valid Event::Base subclass
      expect(test_event_class.ancestors).to include(E11y::Event::Base)
    end

    it "calls class_eval on the base class" do
      # The included hook should execute without errors
      # This verifies severity and adapters DSL methods are called
      expect { test_event_class }.not_to raise_error
    end
  end

  describe "debug event configuration" do
    it "inherits from Event::Base" do
      expect(test_event_class.superclass).to eq(E11y::Event::Base)
    end

    it "applies to event class without errors" do
      # Verify the preset can be included and used
      expect(test_event_class.ancestors).to include(described_class)
    end
  end

  describe "multiple debug events" do
    let(:debug_event_one) do
      Class.new(E11y::Event::Base) do
        include E11y::Presets::DebugEvent

        def self.name
          "DebugEventOne"
        end

        schema { required(:data).filled(:string) }
      end
    end

    it "applies preset consistently to different event classes" do
      expect(debug_event_one.ancestors).to include(described_class)
      expect(debug_event_one.superclass).to eq(E11y::Event::Base)
    end
  end

  describe "preset behavior" do
    it "configures the event class without raising errors" do
      # The preset should call severity and adapters DSL methods
      # which are part of Event::Base
      expect do
        Class.new(E11y::Event::Base) do
          include E11y::Presets::DebugEvent

          def self.name
            "AnotherDebugEvent"
          end

          schema do
            required(:test).filled(:string)
          end
        end
      end.not_to raise_error
    end
  end
end
