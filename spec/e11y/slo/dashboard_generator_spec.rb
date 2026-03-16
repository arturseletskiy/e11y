# frozen_string_literal: true

require "spec_helper"
require "e11y/slo/dashboard_generator"

RSpec.describe E11y::SLO::DashboardGenerator do
  describe ".generate" do
    it "returns Grafana dashboard JSON with title" do
      config = { "version" => 1, "endpoints" => [] }
      result = described_class.generate(config)
      json = JSON.parse(result)
      expect(json["title"]).to include("E11y")
      expect(json["panels"]).to be_an(Array)
    end

    it "includes app-wide panel when app_wide.aggregated_slo enabled" do
      config = {
        "version" => 1,
        "endpoints" => [],
        "app_wide" => {
          "aggregated_slo" => {
            "enabled" => true,
            "strategy" => "weighted_average",
            "components" => [
              { "name" => "http", "weight" => 0.5, "metric" => "sum(rate(x[30d]))/sum(rate(y[30d]))" }
            ]
          }
        }
      }
      result = described_class.generate(config)
      json = JSON.parse(result)
      titles = json["panels"].map { |p| p["title"] }
      expect(titles.any? { |t| t =~ /[Aa]pp-[Ww]ide|[Aa]ggregat/ }).to be true
    end
  end
end
