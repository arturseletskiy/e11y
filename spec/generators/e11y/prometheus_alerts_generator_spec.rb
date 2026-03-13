# frozen_string_literal: true

require "spec_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/e11y/prometheus_alerts/prometheus_alerts_generator"
require "fileutils"
require "minitest"
require "yaml"

RSpec.describe E11y::Generators::PrometheusAlertsGenerator, type: :generator do
  include FileUtils
  include Minitest::Assertions
  include Rails::Generators::Testing::Assertions
  include Rails::Generators::Testing::Behavior

  attr_accessor :assertions

  # assert_nothing_raised was removed in Minitest 5; define a passthrough so
  # Rails::Generators::Testing::Assertions#assert_file (which calls it) works.
  def assert_nothing_raised
    yield
  end

  tests described_class
  destination File.expand_path("../../../tmp/generators/prometheus", __dir__)

  before do
    self.assertions = 0
    prepare_destination
  end

  describe "config/prometheus/ directory" do
    it "creates config/prometheus directory" do
      run_generator
      assert_directory "config/prometheus"
    end
  end

  describe "config/prometheus/e11y_alerts.yml" do
    it "creates the alerts YAML file" do
      run_generator
      assert_file "config/prometheus/e11y_alerts.yml"
    end

    it "the file contains valid YAML" do
      run_generator
      assert_file "config/prometheus/e11y_alerts.yml" do |content|
        expect { YAML.safe_load(content.force_encoding("UTF-8")) }.not_to raise_error
      end
    end

    it "the YAML has groups key" do
      run_generator
      assert_file "config/prometheus/e11y_alerts.yml" do |content|
        parsed = YAML.safe_load(content.force_encoding("UTF-8"))
        expect(parsed).to have_key("groups")
      end
    end

    it "groups contain at least one rule group named e11y" do
      run_generator
      assert_file "config/prometheus/e11y_alerts.yml" do |content|
        parsed = YAML.safe_load(content.force_encoding("UTF-8"))
        group_names = parsed["groups"].map { |g| g["name"] }
        expect(group_names).to include("e11y")
      end
    end

    it "the e11y group has rules" do
      run_generator
      assert_file "config/prometheus/e11y_alerts.yml" do |content|
        parsed = YAML.safe_load(content.force_encoding("UTF-8"))
        e11y_group = parsed["groups"].find { |g| g["name"] == "e11y" }
        expect(e11y_group["rules"]).to be_an(Array)
        expect(e11y_group["rules"]).not_to be_empty
      end
    end

    it "alerts file contains E11yHighAdapterErrorRate alert" do
      run_generator
      assert_file "config/prometheus/e11y_alerts.yml" do |content|
        expect(content.force_encoding("UTF-8")).to match(/E11yHighAdapterErrorRate/)
      end
    end

    it "alerts file contains E11yHighValidationFailureRate alert" do
      run_generator
      assert_file "config/prometheus/e11y_alerts.yml" do |content|
        expect(content.force_encoding("UTF-8")).to match(/E11yHighValidationFailureRate/)
      end
    end

    it "each alert rule has a required expr field" do
      run_generator
      assert_file "config/prometheus/e11y_alerts.yml" do |content|
        parsed = YAML.safe_load(content.force_encoding("UTF-8"))
        e11y_group = parsed["groups"].find { |g| g["name"] == "e11y" }
        e11y_group["rules"].each do |rule|
          expect(rule).to have_key("expr"), "Rule #{rule['alert'].inspect} is missing expr"
        end
      end
    end

    it "each alert rule has annotations with summary" do
      run_generator
      assert_file "config/prometheus/e11y_alerts.yml" do |content|
        parsed = YAML.safe_load(content.force_encoding("UTF-8"))
        e11y_group = parsed["groups"].find { |g| g["name"] == "e11y" }
        e11y_group["rules"].each do |rule|
          expect(rule["annotations"]).to have_key("summary"),
                                         "Rule #{rule['alert'].inspect} is missing annotations.summary"
        end
      end
    end

    it "alerts reference e11y metrics" do
      run_generator
      assert_file "config/prometheus/e11y_alerts.yml" do |content|
        c = content.force_encoding("UTF-8")
        expect(c).to match(
          /e11y_adapter_writes_total|e11y_middleware_validation_total/
        )
      end
    end
  end
end
