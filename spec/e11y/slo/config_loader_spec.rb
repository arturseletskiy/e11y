# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require "e11y/slo/config_loader"

RSpec.describe E11y::SLO::ConfigLoader do
  describe ".load" do
    it "returns nil when slo.yml not found" do
      result = described_class.load(search_paths: ["/nonexistent"])
      expect(result).to be_nil
    end

    it "returns {} for empty file" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "slo.yml")
        File.write(path, "")
        result = described_class.load(search_paths: [dir])
        expect(result).to eq({})
      end
    end

    it "raises Psych::SyntaxError for invalid YAML" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "slo.yml")
        File.write(path, "invalid: yaml: : :")
        expect { described_class.load(search_paths: [dir]) }.to raise_error(Psych::SyntaxError)
      end
    end

    it "loads and parses YAML when file exists" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "slo.yml")
        File.write(path, "version: 1\nendpoints: []")
        result = described_class.load(search_paths: [dir])
        expect(result).to eq("version" => 1, "endpoints" => [])
      end
    end

    it "searches paths in order, returns first found" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "slo.yml")
        File.write(path, "version: 1\nkey: first")
        other = File.join(dir, "other")
        FileUtils.mkdir_p(other)
        File.write(File.join(other, "slo.yml"), "version: 1\nkey: second")
        result = described_class.load(search_paths: [dir, other])
        expect(result["key"]).to eq("first")
      end
    end
  end

  describe ".self_monitoring_enabled?" do
    it "returns false when slo.yml not found" do
      expect(described_class).to receive(:load).and_return(nil)
      expect(described_class.self_monitoring_enabled?).to be false
    end

    it "returns false when e11y_self_monitoring is absent" do
      expect(described_class).to receive(:load).and_return({})
      expect(described_class.self_monitoring_enabled?).to be false
    end

    it "returns false when e11y_self_monitoring.enabled is false" do
      expect(described_class).to receive(:load).and_return("e11y_self_monitoring" => { "enabled" => false })
      expect(described_class.self_monitoring_enabled?).to be false
    end

    it "returns true when e11y_self_monitoring.enabled is true" do
      expect(described_class).to receive(:load).and_return("e11y_self_monitoring" => { "enabled" => true })
      expect(described_class.self_monitoring_enabled?).to be true
    end

    it "returns false when e11y_self_monitoring.enabled is not exactly true" do
      expect(described_class).to receive(:load).and_return("e11y_self_monitoring" => { "enabled" => "true" })
      expect(described_class.self_monitoring_enabled?).to be false
    end
  end
end
