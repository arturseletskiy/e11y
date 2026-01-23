# frozen_string_literal: true

require "spec_helper"

RSpec.describe "E11y::Events::Rails::Cache" do
  describe E11y::Events::Rails::Cache::Read do
    it "inherits from E11y::Event::Base" do
      expect(described_class.superclass).to eq(E11y::Event::Base)
    end

    it "sets sample_rate to 0.01 (1%)" do
      expect(described_class.resolve_sample_rate).to eq(0.01)
    end

    it "has schema defined" do
      expect(described_class).to respond_to(:schema)
    end

    it "can track event with valid payload" do
      result = described_class.track(
        event_name: "cache_read.active_support",
        duration: 2.5,
        key: "user/123/profile",
        hit: true
      )
      expect(result).to be_a(Hash)
      expect(result[:payload][:key]).to eq("user/123/profile")
    end
  end

  describe E11y::Events::Rails::Cache::Write do
    it "inherits from E11y::Event::Base" do
      expect(described_class.superclass).to eq(E11y::Event::Base)
    end

    it "sets sample_rate to 0.01 (1%)" do
      expect(described_class.resolve_sample_rate).to eq(0.01)
    end

    it "has schema defined" do
      expect(described_class).to respond_to(:schema)
    end

    it "can track event with valid payload" do
      result = described_class.track(
        event_name: "cache_write.active_support",
        duration: 5.3,
        key: "user/456/settings"
      )
      expect(result).to be_a(Hash)
      expect(result[:payload][:key]).to eq("user/456/settings")
    end
  end

  describe E11y::Events::Rails::Cache::Delete do
    it "inherits from E11y::Event::Base" do
      expect(described_class.superclass).to eq(E11y::Event::Base)
    end

    it "sets sample_rate to 0.1 (10%)" do
      expect(described_class.resolve_sample_rate).to eq(0.1)
    end

    it "has schema defined" do
      expect(described_class).to respond_to(:schema)
    end

    it "can track event with valid payload" do
      result = described_class.track(
        event_name: "cache_delete.active_support",
        duration: 1.2,
        key: "user/789/cache"
      )
      expect(result).to be_a(Hash)
      expect(result[:payload][:key]).to eq("user/789/cache")
    end
  end
end
