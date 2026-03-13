# frozen_string_literal: true

require "spec_helper"
require "e11y/metrics/test_backend"

RSpec.describe E11y::Metrics::TestBackend do
  subject(:backend) { described_class.new }

  describe "#increment" do
    it "records increments" do
      backend.increment(:orders_total, { status: "paid" })
      expect(backend.increments).to include(
        { name: :orders_total, labels: { status: "paid" }, value: 1 }
      )
    end

    it "accepts custom value" do
      backend.increment(:orders_total, {}, value: 5)
      expect(backend.increments.first[:value]).to eq(5)
    end
  end

  describe "#histogram" do
    it "records histogram observations" do
      backend.histogram(:duration_seconds, 0.042, { controller: "orders" })
      expect(backend.histograms).to include(
        { name: :duration_seconds, value: 0.042, labels: { controller: "orders" } }
      )
    end
  end

  describe "#gauge" do
    it "records gauge values" do
      backend.gauge(:buffer_size, 128, { type: "ring" })
      expect(backend.gauges).to include(
        { name: :buffer_size, value: 128, labels: { type: "ring" } }
      )
    end
  end

  describe "#reset!" do
    it "clears all recorded metrics" do
      backend.increment(:orders_total, {})
      backend.reset!
      expect(backend.increments).to be_empty
    end
  end

  describe "#increment_count" do
    it "returns how many times a metric was incremented" do
      backend.increment(:orders_total, { status: "paid" })
      backend.increment(:orders_total, { status: "failed" })
      expect(backend.increment_count(:orders_total)).to eq(2)
    end

    it "returns 0 for unknown metric" do
      expect(backend.increment_count(:never_tracked)).to eq(0)
    end
  end
end
