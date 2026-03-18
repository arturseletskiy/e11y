# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::TraceContext::Sampler do
  let(:config_double) do
    instance_double(
      E11y::Configuration,
      tracing_default_sample_rate: 0.0,
      tracing_respect_parent_sampling: true,
      tracing_per_event_sample_rates: {},
      tracing_always_sample_if: nil
    )
  end

  before do
    allow(E11y).to receive(:config).and_return(config_double)
  end

  describe ".should_sample?" do
    it "respects parent sampled when respect_parent_sampling" do
      allow(config_double).to receive(:tracing_respect_parent_sampling).and_return(true)
      expect(described_class.should_sample?(sampled: true)).to be true
      expect(described_class.should_sample?(sampled: false)).to be false
    end

    it "ignores parent when respect_parent_sampling false" do
      allow(config_double).to receive_messages(tracing_respect_parent_sampling: false, tracing_default_sample_rate: 1.0)
      expect(described_class.should_sample?(sampled: false)).to be true
    end

    it "always samples when context has error" do
      allow(config_double).to receive(:tracing_default_sample_rate).and_return(0.0)
      expect(described_class.should_sample?(error: true)).to be true
    end

    it "always samples when always_sample_if proc returns true" do
      allow(config_double).to receive_messages(tracing_always_sample_if: lambda { |ctx|
        ctx[:request_path]&.include?("admin")
      }, tracing_default_sample_rate: 0.0)
      expect(described_class.should_sample?(request_path: "/admin/users")).to be true
      expect(described_class.should_sample?(request_path: "/api/users")).to be false
    end

    it "always samples by user_id via always_sample_if" do
      allow(config_double).to receive_messages(tracing_always_sample_if: lambda { |ctx|
        [42, 123].include?(ctx[:user_id])
      }, tracing_default_sample_rate: 0.0)
      expect(described_class.should_sample?(user_id: 42)).to be true
      expect(described_class.should_sample?(user_id: 999)).to be false
    end

    it "uses per_event_sample_rates when event_name matches" do
      allow(config_double).to receive_messages(tracing_per_event_sample_rates: { "payment.x" => 1.0 }, tracing_default_sample_rate: 0.0)
      expect(described_class.should_sample?(event_name: "payment.x")).to be true
    end

    it "falls back to default_sample_rate when no match" do
      allow(config_double).to receive(:tracing_default_sample_rate).and_return(0.0)
      expect(described_class.should_sample?({})).to be false
    end

    it "handles nil config gracefully" do
      allow(E11y).to receive(:config).and_return(nil)
      # Should not raise; uses 0.1 default
      expect { described_class.should_sample?({}) }.not_to raise_error
    end
  end
end
