# spec/e11y/store/rails_cache_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "active_support/cache"
require "active_support/cache/memory_store"
require "e11y/store/rails_cache"

RSpec.describe E11y::Store::RailsCache do
  # MemoryStore used in tests only (not prod/staging)
  subject(:store) { described_class.new(cache_store: cache) }

  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  describe "#initialize validation" do
    context "when MemoryStore used in production" do
      before { allow(described_class).to receive(:rails_env).and_return("production") }

      it "raises ArgumentError" do
        expect { described_class.new(cache_store: cache) }.to raise_error(
          ArgumentError, /MemoryStore.*production.*Redis/
        )
      end
    end

    context "when NullStore used in staging" do
      let(:cache) { ActiveSupport::Cache::NullStore.new }

      before { allow(described_class).to receive(:rails_env).and_return("staging") }

      it "raises ArgumentError" do
        expect { described_class.new(cache_store: cache) }.to raise_error(ArgumentError)
      end
    end

    context "when MemoryStore in test environment" do
      before { allow(described_class).to receive(:rails_env).and_return("test") }

      it "does not raise" do
        expect { described_class.new(cache_store: cache) }.not_to raise_error
      end
    end
  end

  describe "#get / #set" do
    it "returns nil for missing key" do
      expect(store.get("missing")).to be_nil
    end

    it "stores and retrieves a value" do
      store.set("key", "value")
      expect(store.get("key")).to eq("value")
    end

    it "expires after TTL" do
      store.set("key", "value", ttl: 0.01)
      sleep(0.05)
      expect(store.get("key")).to be_nil
    end
  end

  describe "#increment" do
    it "initialises counter when key absent" do
      expect(store.increment("counter")).to eq(1)
    end

    it "increments existing counter" do
      store.increment("counter")
      store.increment("counter")
      expect(store.increment("counter")).to eq(3)
    end

    it "increments by custom amount" do
      expect(store.increment("counter", by: 5)).to eq(5)
    end

    it "expires counter after TTL and resets on next increment" do
      store.increment("ctr", ttl: 0.01)
      sleep(0.05)
      expect(store.increment("ctr")).to eq(1)
    end
  end

  describe "#set_if_absent" do
    it "writes and returns true when absent" do
      expect(store.set_if_absent("key", true, ttl: 60)).to be(true)
    end

    it "returns false when already present" do
      store.set("key", "original")
      expect(store.set_if_absent("key", "new", ttl: 60)).to be(false)
    end
  end

  describe "#fetch" do
    it "computes and stores value when absent" do
      result = store.fetch("key", ttl: 60) { "computed" }
      expect(result).to eq("computed")
    end

    it "returns existing without block call" do
      store.set("key", "existing")
      called = false
      result = store.fetch("key", ttl: 60) { called = true; "new" } # rubocop:disable Style/Semicolon
      expect(result).to eq("existing")
      expect(called).to be(false)
    end
  end

  describe "namespace isolation" do
    it "prefixes keys with e11y namespace" do
      store.set("mykey", "val")
      # Raw cache stores under namespaced key, not bare key
      expect(cache.read("mykey")).to be_nil
      expect(cache.read("e11y:mykey")).to eq("val")
    end
  end

  describe "#delete" do
    it "removes the key" do
      store.set("key", "value")
      store.delete("key")
      expect(store.get("key")).to be_nil
    end

    it "deletes the namespaced key, not the bare key" do
      store.set("mykey", "val")
      store.delete("mykey")
      expect(cache.read("e11y:mykey")).to be_nil
    end
  end
end
