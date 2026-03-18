# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/e11y/versioning/version_extractor"

RSpec.describe E11y::Versioning::VersionExtractor do
  describe ".extract_version" do
    it "extracts version from V2 suffix" do
      expect(described_class.extract_version("Events::OrderPaidV2")).to eq(2)
    end

    it "extracts version from V10 suffix" do
      expect(described_class.extract_version("Events::OrderPaidV10")).to eq(10)
    end

    it "returns 1 for no suffix" do
      expect(described_class.extract_version("Events::OrderPaid")).to eq(1)
    end

    it "returns 1 for nil" do
      expect(described_class.extract_version(nil)).to eq(1)
    end

    it "ignores V in middle of name (returns 1 when V2 is not at end)" do
      expect(described_class.extract_version("Events::OrderV2Created")).to eq(1)
    end
  end

  describe ".extract_base_name" do
    it "removes V2 suffix" do
      expect(described_class.extract_base_name("Events::OrderPaidV2")).to eq("Events::OrderPaid")
    end

    it "returns as-is when no suffix" do
      expect(described_class.extract_base_name("Events::OrderPaid")).to eq("Events::OrderPaid")
    end

    it "returns nil for nil" do
      expect(described_class.extract_base_name(nil)).to be_nil
    end
  end
end
