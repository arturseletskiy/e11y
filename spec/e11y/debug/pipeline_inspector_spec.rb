# frozen_string_literal: true

require "spec_helper"
require "e11y/debug/pipeline_inspector"

RSpec.describe E11y::Debug::PipelineInspector do
  # Use error severity so Sampling middleware does not drop the event (error = 100% sample rate)
  let(:event_class) do
    Class.new(E11y::Event::Base) do
      schema { required(:id).filled(:string) }
      def self.name
        "Events::Test"
      end

      def self.event_name
        "test"
      end

      def self.severity
        :error
      end
    end
  end

  describe ".trace_event" do
    it "returns event_data after pipeline" do
      result = described_class.trace_event(event_class, id: "123")
      expect(result).to be_a(Hash)
      expect(result[:event_name]).to eq("test")
      expect(result[:payload][:id]).to eq("123")
    end

    it "runs event through pipeline (adds trace_id)" do
      result = described_class.trace_event(event_class, id: "123")
      expect(result).to be_a(Hash)
      expect(result[:trace_id] || result["trace_id"]).to be_present
    end
  end
end
