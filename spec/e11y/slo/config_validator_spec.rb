# frozen_string_literal: true

require "spec_helper"
require "e11y/slo/config_validator"

RSpec.describe E11y::SLO::ConfigValidator do
  describe ".validate" do
    it "returns error when config is nil" do
      result = described_class.validate(nil)
      expect(result).to eq(["Config is nil or empty"])
    end

    it "returns error when config is empty" do
      result = described_class.validate({})
      expect(result).to eq(["Config is nil or empty"])
    end

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

    it "accepts endpoint with controller only" do
      config = { "version" => 1, "endpoints" => [{ "controller" => "Api::UsersController" }] }
      result = described_class.validate(config)
      expect(result).to eq([])
    end

    it "accepts endpoint with pattern only" do
      config = { "version" => 1, "endpoints" => [{ "pattern" => "/api/users/:id" }] }
      result = described_class.validate(config)
      expect(result).to eq([])
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

    it "returns error when app_wide enabled but strategy missing" do
      config = {
        "version" => 1,
        "endpoints" => [],
        "app_wide" => {
          "aggregated_slo" => {
            "enabled" => true,
            "components" => [{ "name" => "http", "weight" => 0.5 }]
          }
        }
      }
      result = described_class.validate(config)
      expect(result).to include(a_string_matching(/strategy/))
    end

    it "returns error when app_wide enabled but components empty" do
      config = {
        "version" => 1,
        "endpoints" => [],
        "app_wide" => {
          "aggregated_slo" => {
            "enabled" => true,
            "strategy" => "weighted_average"
          }
        }
      }
      result = described_class.validate(config)
      expect(result).to include(a_string_matching(/components/))
    end
  end
end
