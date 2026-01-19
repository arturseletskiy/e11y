# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Metrics::CardinalityTracker do
  let(:tracker) { described_class.new(limit: 3) }

  describe "#initialize" do
    it "accepts custom limit" do
      custom_tracker = described_class.new(limit: 500)
      expect(custom_tracker).to be_a(described_class)
    end

    it "uses default limit when not specified" do
      default_tracker = described_class.new
      expect(default_tracker).to be_a(described_class)
    end
  end

  describe "#track" do
    it "tracks new label values" do
      result = tracker.track("orders.total", :status, "paid")
      expect(result).to be(true)
      expect(tracker.cardinality("orders.total", :status)).to eq(1)
    end

    it "allows existing values without increasing cardinality" do
      tracker.track("orders.total", :status, "paid")
      tracker.track("orders.total", :status, "paid")
      expect(tracker.cardinality("orders.total", :status)).to eq(1)
    end

    it "tracks multiple values up to limit" do
      tracker.track("orders.total", :status, "paid")
      tracker.track("orders.total", :status, "failed")
      tracker.track("orders.total", :status, "pending")
      expect(tracker.cardinality("orders.total", :status)).to eq(3)
    end

    it "rejects new values when limit reached" do
      tracker.track("orders.total", :status, "paid")
      tracker.track("orders.total", :status, "failed")
      tracker.track("orders.total", :status, "pending")
      result = tracker.track("orders.total", :status, "cancelled")
      expect(result).to be(false)
      expect(tracker.cardinality("orders.total", :status)).to eq(3)
    end

    it "tracks cardinality separately per metric" do
      tracker.track("orders.total", :status, "paid")
      tracker.track("users.count", :status, "active")
      expect(tracker.cardinality("orders.total", :status)).to eq(1)
      expect(tracker.cardinality("users.count", :status)).to eq(1)
    end

    it "tracks cardinality separately per label" do
      tracker.track("orders.total", :status, "paid")
      tracker.track("orders.total", :currency, "USD")
      expect(tracker.cardinality("orders.total", :status)).to eq(1)
      expect(tracker.cardinality("orders.total", :currency)).to eq(1)
    end
  end

  describe "#exceeded?" do
    it "returns false when below limit" do
      tracker.track("orders.total", :status, "paid")
      expect(tracker.exceeded?("orders.total", :status)).to be(false)
    end

    it "returns true when at limit" do
      tracker.track("orders.total", :status, "paid")
      tracker.track("orders.total", :status, "failed")
      tracker.track("orders.total", :status, "pending")
      expect(tracker.exceeded?("orders.total", :status)).to be(true)
    end

    it "returns false for untracked metric" do
      expect(tracker.exceeded?("unknown.metric", :status)).to be(false)
    end
  end

  describe "#cardinality" do
    it "returns 0 for untracked metric+label" do
      expect(tracker.cardinality("unknown.metric", :status)).to eq(0)
    end

    it "returns current cardinality for tracked metric+label" do
      tracker.track("orders.total", :status, "paid")
      tracker.track("orders.total", :status, "failed")
      expect(tracker.cardinality("orders.total", :status)).to eq(2)
    end
  end

  describe "#cardinalities" do
    it "returns empty hash for untracked metric" do
      expect(tracker.cardinalities("unknown.metric")).to eq({})
    end

    it "returns all label cardinalities for a metric" do
      tracker.track("orders.total", :status, "paid")
      tracker.track("orders.total", :status, "failed")
      tracker.track("orders.total", :currency, "USD")

      cardinalities = tracker.cardinalities("orders.total")
      expect(cardinalities).to eq({ status: 2, currency: 1 })
    end
  end

  describe "#all_cardinalities" do
    it "returns empty hash when no metrics tracked" do
      expect(tracker.all_cardinalities).to eq({})
    end

    it "returns all metrics and their label cardinalities" do
      tracker.track("orders.total", :status, "paid")
      tracker.track("orders.total", :currency, "USD")
      tracker.track("users.count", :role, "admin")

      all_cardinalities = tracker.all_cardinalities
      expect(all_cardinalities).to eq({
                                        "orders.total" => { status: 1, currency: 1 },
                                        "users.count" => { role: 1 }
                                      })
    end
  end

  describe "#reset_metric!" do
    it "resets tracking for specific metric" do
      tracker.track("orders.total", :status, "paid")
      tracker.track("users.count", :role, "admin")

      tracker.reset_metric!("orders.total")

      expect(tracker.cardinality("orders.total", :status)).to eq(0)
      expect(tracker.cardinality("users.count", :role)).to eq(1) # Other metric unaffected
    end
  end

  describe "#reset_all!" do
    it "clears all tracking data" do
      tracker.track("orders.total", :status, "paid")
      tracker.track("users.count", :role, "admin")

      tracker.reset_all!

      expect(tracker.all_cardinalities).to eq({})
      expect(tracker.metrics_count).to eq(0)
    end
  end

  describe "#metrics_count" do
    it "returns 0 when no metrics tracked" do
      expect(tracker.metrics_count).to eq(0)
    end

    it "returns number of unique metrics being tracked" do
      tracker.track("orders.total", :status, "paid")
      tracker.track("orders.total", :currency, "USD")
      tracker.track("users.count", :role, "admin")

      expect(tracker.metrics_count).to eq(2)
    end
  end

  describe "thread safety" do
    it "handles concurrent tracking" do
      threads = 10.times.map do |i|
        Thread.new do
          10.times do |j|
            tracker.track("test.metric", :label, "value_#{i}_#{j}")
          end
        end
      end

      threads.each(&:join)

      # Should track all unique values (limited by the 3-value limit)
      expect(tracker.cardinality("test.metric", :label)).to be <= 3
    end

    it "handles concurrent reads" do
      tracker.track("test.metric", :label, "value_1")

      threads = 10.times.map do
        Thread.new do
          100.times { tracker.cardinality("test.metric", :label) }
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
    end
  end
end
