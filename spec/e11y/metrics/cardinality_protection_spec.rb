# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Metrics::CardinalityProtection do
  let(:protection) { described_class.new }

  describe "#filter" do
    context "when using Layer 1: Universal Denylist" do
      it "blocks high-cardinality id fields" do
        labels = {
          user_id: "123",
          order_id: "456",
          status: "paid"
        }

        safe_labels = protection.filter(labels, "orders.total")

        expect(safe_labels).to eq({ status: "paid" })
        expect(safe_labels).not_to have_key(:user_id)
        expect(safe_labels).not_to have_key(:order_id)
      end

      it "blocks trace and span ids" do
        labels = {
          trace_id: "abc-123",
          span_id: "def-456",
          status: "success"
        }

        safe_labels = protection.filter(labels, "requests.total")

        expect(safe_labels).to eq({ status: "success" })
      end

      it "blocks PII fields" do
        labels = {
          email: "user@example.com",
          phone: "+1234567890",
          ip_address: "192.168.1.1",
          status: "active"
        }

        safe_labels = protection.filter(labels, "users.total")

        expect(safe_labels).to eq({ status: "active" })
      end

      it "blocks timestamp fields" do
        labels = {
          created_at: "2026-01-19T12:00:00Z",
          updated_at: "2026-01-19T13:00:00Z",
          status: "completed"
        }

        safe_labels = protection.filter(labels, "tasks.total")

        expect(safe_labels).to eq({ status: "completed" })
      end
    end

    context "when using Layer 3: Per-Metric Cardinality Limits" do
      it "tracks unique values per metric" do
        # Add 3 unique status values
        protection.filter({ status: "pending" }, "orders.total")
        protection.filter({ status: "paid" }, "orders.total")
        protection.filter({ status: "failed" }, "orders.total")

        expect(protection.tracker.cardinality("orders.total", :status)).to eq(3)
      end

      it "allows existing values without increasing cardinality" do
        protection.filter({ status: "paid" }, "orders.total")
        protection.filter({ status: "paid" }, "orders.total")
        protection.filter({ status: "paid" }, "orders.total")

        expect(protection.tracker.cardinality("orders.total", :status)).to eq(1)
      end

      it "blocks new values when limit is exceeded" do
        small_limit_protection = described_class.new(cardinality_limit: 2)

        # Add 2 values (at limit)
        labels1 = small_limit_protection.filter({ status: "paid" }, "orders.total")
        labels2 = small_limit_protection.filter({ status: "pending" }, "orders.total")

        expect(labels1).to eq({ status: "paid" })
        expect(labels2).to eq({ status: "pending" })

        # Try to add 3rd value (should be blocked)
        labels3 = small_limit_protection.filter({ status: "failed" }, "orders.total")

        expect(labels3).to be_empty
      end

      it "tracks cardinality separately per metric" do
        protection.filter({ status: "paid" }, "orders.total")
        protection.filter({ status: "active" }, "users.total")

        expect(protection.tracker.cardinality("orders.total", :status)).to eq(1)
        expect(protection.tracker.cardinality("users.total", :status)).to eq(1)
      end

      it "tracks cardinality separately per label" do
        protection.filter({ status: "paid", currency: "USD" }, "orders.total")
        protection.filter({ status: "pending", currency: "EUR" }, "orders.total")

        expect(protection.tracker.cardinality("orders.total", :status)).to eq(2)
        expect(protection.tracker.cardinality("orders.total", :currency)).to eq(2)
      end
    end

    context "when protection is disabled" do
      it "allows all labels when disabled" do
        disabled_protection = described_class.new(enabled: false)

        labels = {
          user_id: "123",
          order_id: "456",
          custom_field: "value"
        }

        safe_labels = disabled_protection.filter(labels, "orders.total")

        expect(safe_labels).to eq(labels)
      end
    end

    context "with custom denylist" do
      it "supports additional denylist fields" do
        custom_protection = described_class.new(
          additional_denylist: %i[internal_id secret_key]
        )

        labels = {
          internal_id: "abc",
          secret_key: "xyz",
          custom_field: "value"
        }

        safe_labels = custom_protection.filter(labels, "events.total")

        expect(safe_labels).to eq({ custom_field: "value" })
        expect(safe_labels).not_to have_key(:internal_id)
        expect(safe_labels).not_to have_key(:secret_key)
      end
    end
  end

  describe "#cardinality_exceeded?" do
    it "returns false when below limit" do
      protection.filter({ status: "paid" }, "orders.total")

      expect(protection.cardinality_exceeded?("orders.total")).to be false
    end

    it "returns true when at limit" do
      small_limit_protection = described_class.new(cardinality_limit: 2)

      small_limit_protection.filter({ status: "paid" }, "orders.total")
      small_limit_protection.filter({ status: "pending" }, "orders.total")

      expect(small_limit_protection.cardinality_exceeded?("orders.total")).to be true
    end
  end

  describe "#cardinality" do
    it "returns empty hash for untracked metric" do
      expect(protection.cardinality("unknown.metric")).to eq({})
    end

    it "returns hash of label cardinalities for tracked metric" do
      protection.filter({ status: "paid" }, "orders.total")
      protection.filter({ status: "pending" }, "orders.total")
      protection.filter({ status: "failed" }, "orders.total")

      cardinalities = protection.cardinality("orders.total")
      expect(cardinalities[:status]).to eq(3)
    end
  end

  describe "#cardinalities" do
    it "returns all tracked cardinalities" do
      protection.filter({ status: "paid" }, "orders.total")
      protection.filter({ status: "pending" }, "orders.total")
      protection.filter({ currency: "USD" }, "orders.total")

      cardinalities = protection.cardinalities

      expect(cardinalities["orders.total"][:status]).to eq(2)
      expect(cardinalities["orders.total"][:currency]).to eq(1)
    end

    it "returns empty hash when no metrics tracked" do
      expect(protection.cardinalities).to be_empty
    end
  end

  describe "#reset!" do
    it "clears all cardinality tracking" do
      protection.filter({ status: "paid" }, "orders.total")
      protection.filter({ status: "pending" }, "orders.total")

      expect(protection.tracker.cardinality("orders.total", :status)).to eq(2)

      protection.reset!

      expect(protection.tracker.cardinality("orders.total", :status)).to eq(0)
      expect(protection.cardinalities).to be_empty
    end
  end

  describe "thread safety" do
    it "handles concurrent filtering" do
      threads = 100.times.map do |i|
        Thread.new do
          protection.filter({ status: "status_#{i % 10}" }, "orders.total")
        end
      end

      threads.each(&:join)

      # Should have 10 unique status values
      expect(protection.tracker.cardinality("orders.total", :status)).to eq(10)
    end

    it "handles concurrent reads and writes" do
      threads = []

      # Writers
      50.times do |i|
        threads << Thread.new do
          protection.filter({ status: "status_#{i % 5}" }, "orders.total")
        end
      end

      # Readers
      50.times do
        threads << Thread.new do
          protection.tracker.cardinality("orders.total", :status)
        end
      end

      threads.each(&:join)

      expect(protection.tracker.cardinality("orders.total", :status)).to eq(5)
    end
  end

  describe "warning messages" do
    it "warns when cardinality limit exceeded" do
      small_limit_protection = described_class.new(cardinality_limit: 1)

      small_limit_protection.filter({ status: "paid" }, "orders.total")

      expect do
        small_limit_protection.filter({ status: "pending" }, "orders.total")
      end.to output(/Cardinality limit exceeded/).to_stderr
    end
  end

  describe "relabeling integration" do
    it "applies relabeling before cardinality tracking" do
      protection.relabel(:http_status) { |v| "#{v.to_i / 100}xx" }

      protection.filter({ http_status: 200 }, "http.requests")
      protection.filter({ http_status: 201 }, "http.requests")
      protection.filter({ http_status: 404 }, "http.requests")

      # 200 and 201 both become '2xx', so cardinality is 2 (2xx, 4xx)
      expect(protection.tracker.cardinality("http.requests", :http_status)).to eq(2)
    end

    it "reduces cardinality explosion via relabeling" do
      small_limit_protection = described_class.new(cardinality_limit: 3)
      small_limit_protection.relabel(:path) { |v| v.gsub(%r{/\d+}, "/:id") }

      # Without relabeling, these would be 3 different paths
      # With relabeling, all become '/users/:id'
      small_limit_protection.filter({ path: "/users/123" }, "api.requests")
      small_limit_protection.filter({ path: "/users/456" }, "api.requests")
      small_limit_protection.filter({ path: "/users/789" }, "api.requests")

      # All 3 paths relabeled to same value, cardinality is 1
      expect(small_limit_protection.tracker.cardinality("api.requests", :path)).to eq(1)
    end

    it "can disable relabeling via config" do
      protection_no_relabel = described_class.new(relabeling_enabled: false)
      protection_no_relabel.relabel(:http_status) { |v| "#{v.to_i / 100}xx" }

      protection_no_relabel.filter({ http_status: 200 }, "http.requests")
      protection_no_relabel.filter({ http_status: 201 }, "http.requests")

      # Relabeling disabled, so cardinality is 2 (200, 201)
      expect(protection_no_relabel.tracker.cardinality("http.requests", :http_status)).to eq(2)
    end

    it "exposes relabeler for direct access" do
      protection.relabel(:http_status) { |v| "#{v.to_i / 100}xx" }

      expect(protection.relabeler.apply(:http_status, 200)).to eq("2xx")
    end
  end
end
