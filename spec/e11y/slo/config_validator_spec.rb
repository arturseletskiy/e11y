# frozen_string_literal: true

require "spec_helper"
require "e11y/slo/config_validator"

RSpec.describe E11y::SLO::ConfigValidator do
  describe ".validate" do
    it "returns empty errors for valid minimal config" do
      config = { "version" => 1, "endpoints" => [] }
      result = described_class.validate(config)
      expect(result).to eq([])
    end

    it "returns error when version missing" do
      config = { "endpoints" => [] }
      result = described_class.validate(config)
      expect(result).to include(a_string_matching(/version/))
    end

    it "validates endpoint has required keys" do
      config = { "version" => 1, "endpoints" => [{ "name" => "X" }] }
      result = described_class.validate(config)
      expect(result).to include(a_string_matching(/controller|pattern/))
    end

    it "validates app_wide.aggregated_slo when present" do
      config = {
        "version" => 1,
        "endpoints" => [],
        "app_wide" => {
          "aggregated_slo" => {
            "enabled" => true,
            "strategy" => "weighted_average",
            "components" => [{ "name" => "http", "weight" => 0.5 }]
          }
        }
      }
      result = described_class.validate(config)
      expect(result).to eq([])
    end
  end
end
