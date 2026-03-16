# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::TraceContext::Sampler do
  let(:config_double) { instance_double(E11y::Configuration, tracing: tracing_config) }
  let(:tracing_config) do
    double(
      default_sample_rate: 0.0,
      respect_parent_sampling: true,
      per_event_sample_rates: {},
      always_sample_if: nil
    )
  end

  before do
    allow(E11y).to receive(:config).and_return(config_double)
  end

  describe ".should_sample?" do
    it "respects parent sampled when respect_parent_sampling" do
      allow(tracing_config).to receive(:respect_parent_sampling).and_return(true)
      expect(described_class.should_sample?(sampled: true)).to be true
      expect(described_class.should_sample?(sampled: false)).to be false
    end

    it "ignores parent when respect_parent_sampling false" do
      allow(tracing_config).to receive(:respect_parent_sampling).and_return(false)
      allow(tracing_config).to receive(:default_sample_rate).and_return(1.0)
      expect(described_class.should_sample?(sampled: false)).to be true
    end

    it "always samples when context has error" do
      allow(tracing_config).to receive(:default_sample_rate).and_return(0.0)
      expect(described_class.should_sample?(error: true)).to be true
    end

    it "always samples when always_sample_if proc returns true" do
      allow(tracing_config).to receive(:always_sample_if).and_return(->(ctx) { ctx[:request_path]&.include?("admin") })
      allow(tracing_config).to receive(:default_sample_rate).and_return(0.0)
      expect(described_class.should_sample?(request_path: "/admin/users")).to be true
      expect(described_class.should_sample?(request_path: "/api/users")).to be false
    end

    it "always samples by user_id via always_sample_if" do
      allow(tracing_config).to receive(:always_sample_if).and_return(->(ctx) { ctx[:user_id].in?([42, 123]) })
      allow(tracing_config).to receive(:default_sample_rate).and_return(0.0)
      expect(described_class.should_sample?(user_id: 42)).to be true
      expect(described_class.should_sample?(user_id: 999)).to be false
    end

    it "uses per_event_sample_rates when event_name matches" do
      allow(tracing_config).to receive(:per_event_sample_rates).and_return("payment.x" => 1.0)
      allow(tracing_config).to receive(:default_sample_rate).and_return(0.0)
      expect(described_class.should_sample?(event_name: "payment.x")).to be true
    end

    it "falls back to default_sample_rate when no match" do
      allow(tracing_config).to receive(:default_sample_rate).and_return(0.0)
      expect(described_class.should_sample?({})).to be false
    end

    it "handles nil config gracefully" do
      allow(E11y).to receive(:config).and_return(nil)
      # Should not raise; uses 0.1 default
      expect { described_class.should_sample?({}) }.not_to raise_error
    end
  end
end
