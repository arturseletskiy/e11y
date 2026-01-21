# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Metrics::Relabeling do
  let(:relabeler) { described_class.new }

  describe "#initialize" do
    it "accepts initial rules hash" do
      rules = { http_status: ->(v) { "#{v.to_i / 100}xx" } }
      relabeler = described_class.new(rules)
      expect(relabeler.defined?(:http_status)).to be(true)
    end
  end

  describe "#define" do
    it "defines relabeling rule via block" do
      relabeler.define(:http_status) { |v| "#{v.to_i / 100}xx" }
      expect(relabeler.defined?(:http_status)).to be(true)
    end

    it "raises error when block not provided" do
      expect { relabeler.define(:http_status) }.to raise_error(ArgumentError, /Block required/)
    end

    it "accepts both Symbol and String keys" do
      relabeler.define("http_status") { |v| "#{v.to_i / 100}xx" }
      expect(relabeler.defined?(:http_status)).to be(true)
    end
  end

  describe "#apply" do
    before do
      relabeler.define(:http_status) { |v| "#{v.to_i / 100}xx" }
      relabeler.define(:path) { |v| v.gsub(%r{/\d+}, "/:id") }
    end

    it "applies transformation when rule exists" do
      expect(relabeler.apply(:http_status, 200)).to eq("2xx")
      expect(relabeler.apply(:http_status, 404)).to eq("4xx")
      expect(relabeler.apply(:http_status, 500)).to eq("5xx")
    end

    it "returns original value when no rule defined" do
      expect(relabeler.apply(:environment, "production")).to eq("production")
    end

    it "handles error during transformation gracefully" do
      relabeler.define(:failing_rule) { |_v| raise StandardError, "test error" }

      # Should return original value and warn (checked via output)
      result = relabeler.apply(:failing_rule, "test_value")
      expect(result).to eq("test_value")
    end

    it "applies string manipulation rules" do
      expect(relabeler.apply(:path, "/users/123")).to eq("/users/:id")
      expect(relabeler.apply(:path, "/users/123/orders/456")).to eq("/users/:id/orders/:id")
    end

    it "accepts both Symbol and String keys" do
      expect(relabeler.apply("http_status", 200)).to eq("2xx")
    end
  end

  describe "#apply_all" do
    before do
      relabeler.define(:http_status) { |v| "#{v.to_i / 100}xx" }
      relabeler.define(:path) { |v| v.gsub(%r{/\d+}, "/:id") }
    end

    it "applies relabeling to all labels with rules" do
      labels = { http_status: 200, path: "/users/123", env: "production" }
      result = relabeler.apply_all(labels)

      expect(result[:http_status]).to eq("2xx")
      expect(result[:path]).to eq("/users/:id")
      expect(result[:env]).to eq("production") # No rule, unchanged
    end

    it "handles empty labels hash" do
      expect(relabeler.apply_all({})).to eq({})
    end
  end

  describe "#defined?" do
    it "returns true when rule exists" do
      relabeler.define(:http_status) { |v| "#{v.to_i / 100}xx" }
      expect(relabeler.defined?(:http_status)).to be(true)
    end

    it "returns false when rule does not exist" do
      expect(relabeler.defined?(:unknown_label)).to be(false)
    end
  end

  describe "#remove" do
    it "removes existing rule" do
      relabeler.define(:http_status) { |v| "#{v.to_i / 100}xx" }
      expect(relabeler.defined?(:http_status)).to be(true)

      relabeler.remove(:http_status)
      expect(relabeler.defined?(:http_status)).to be(false)
    end
  end

  describe "#keys" do
    it "returns empty array when no rules defined" do
      expect(relabeler.keys).to eq([])
    end

    it "returns all defined rule keys" do
      relabeler.define(:http_status) { |v| "#{v.to_i / 100}xx" }
      relabeler.define(:path) { |v| v.gsub(%r{/\d+}, "/:id") }

      expect(relabeler.keys).to match_array(%i[http_status path])
    end
  end

  describe "#reset!" do
    it "clears all rules" do
      relabeler.define(:http_status) { |v| "#{v.to_i / 100}xx" }
      relabeler.define(:path) { |v| v.gsub(%r{/\d+}, "/:id") }

      relabeler.reset!

      expect(relabeler.keys).to eq([])
      expect(relabeler.size).to eq(0)
    end
  end

  describe "#size" do
    it "returns 0 when no rules defined" do
      expect(relabeler.size).to eq(0)
    end

    it "returns number of defined rules" do
      relabeler.define(:http_status) { |v| "#{v.to_i / 100}xx" }
      relabeler.define(:path) { |v| v.gsub(%r{/\d+}, "/:id") }

      expect(relabeler.size).to eq(2)
    end
  end

  describe "thread safety" do
    it "handles concurrent rule definitions" do
      threads = 10.times.map do |i|
        Thread.new do
          relabeler.define(:"rule_#{i}") { |_v| "value_#{i}" }
        end
      end

      threads.each(&:join)
      expect(relabeler.size).to eq(10)
    end

    it "handles concurrent apply operations" do
      relabeler.define(:http_status) { |v| "#{v.to_i / 100}xx" }

      threads = 10.times.map do
        Thread.new do
          100.times { relabeler.apply(:http_status, 200) }
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
    end
  end
end
