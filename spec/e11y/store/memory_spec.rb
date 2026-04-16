# spec/e11y/store/memory_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "e11y/store/base"
require "e11y/store/memory"

RSpec.describe E11y::Store::Memory do
  subject(:store) { described_class.new }

  describe "#get / #set" do
    it "returns nil for missing key" do
      expect(store.get("missing")).to be_nil
    end

    it "stores and retrieves a value" do
      store.set("key", "value")
      expect(store.get("key")).to eq("value")
    end

    it "returns nil after TTL expires" do
      store.set("key", "value", ttl: 0.01)
      sleep(0.02)
      expect(store.get("key")).to be_nil
    end

    it "does not expire before TTL" do
      store.set("key", "value", ttl: 60)
      expect(store.get("key")).to eq("value")
    end
  end

  describe "#increment" do
    it "initialises to by value when key absent" do
      expect(store.increment("counter")).to eq(1)
    end

    it "increments existing value atomically" do
      store.increment("counter")
      store.increment("counter")
      expect(store.increment("counter")).to eq(3)
    end

    it "increments by custom amount" do
      expect(store.increment("counter", by: 5)).to eq(5)
    end

    it "sets TTL only on first increment, preserves on subsequent" do
      store.increment("counter", by: 1, ttl: 0.05)
      store.increment("counter", by: 1) # no ttl — should preserve first TTL
      sleep(0.06)
      expect(store.get("counter")).to be_nil # expired based on first TTL
    end
  end

  describe "#set_if_absent" do
    it "writes and returns true when key absent" do
      expect(store.set_if_absent("key", true, ttl: 60)).to be(true)
      expect(store.get("key")).to be(true)
    end

    it "returns false without overwriting when key present" do
      store.set("key", "original")
      expect(store.set_if_absent("key", "new", ttl: 60)).to be(false)
      expect(store.get("key")).to eq("original")
    end

    it "writes after previous TTL expires" do
      store.set_if_absent("key", "v1", ttl: 0.01)
      sleep(0.02)
      expect(store.set_if_absent("key", "v2", ttl: 60)).to be(true)
      expect(store.get("key")).to eq("v2")
    end

    it "can store false as a value" do
      store.set_if_absent("key", false, ttl: 60)
      expect(store.get("key")).to be(false)
    end
  end

  describe "#fetch" do
    it "calls block and stores result when key absent" do
      result = store.fetch("key", ttl: 60) { "computed" }
      expect(result).to eq("computed")
      expect(store.get("key")).to eq("computed")
    end

    it "returns existing value without calling block" do
      store.set("key", "existing")
      calls = 0
      result = store.fetch("key", ttl: 60) do
        calls += 1
        "computed"
      end
      expect(result).to eq("existing")
      expect(calls).to eq(0)
    end

    it "can store false without re-calling block" do
      store.fetch("key", ttl: 60) { false }
      calls = 0
      result = store.fetch("key", ttl: 60) do
        calls += 1
        "other"
      end
      expect(result).to be(false)
      expect(calls).to eq(0)
    end
  end

  describe "#delete" do
    it "removes the key" do
      store.set("key", "value")
      store.delete("key")
      expect(store.get("key")).to be_nil
    end
  end

  describe "thread safety" do
    it "handles concurrent increments correctly" do
      threads = Array.new(10) { Thread.new { 100.times { store.increment("counter") } } }
      threads.each(&:join)
      expect(store.get("counter")).to eq(1000)
    end
  end
end
