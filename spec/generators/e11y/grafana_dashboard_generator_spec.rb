# frozen_string_literal: true

require "spec_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/e11y/grafana_dashboard/grafana_dashboard_generator"
require "fileutils"
require "minitest"
require "json"

RSpec.describe E11y::Generators::GrafanaDashboardGenerator, type: :generator do
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
  destination File.expand_path("../../../tmp/generators/grafana", __dir__)

  before do
    self.assertions = 0
    prepare_destination
  end

  describe "config/grafana/ directory" do
    it "creates config/grafana directory" do
      run_generator
      assert_directory "config/grafana"
    end
  end

  describe "config/grafana/e11y_dashboard.json" do
    it "creates the dashboard JSON file" do
      run_generator
      assert_file "config/grafana/e11y_dashboard.json"
    end

    it "the file contains valid JSON" do
      run_generator
      assert_file "config/grafana/e11y_dashboard.json" do |content|
        expect { JSON.parse(content.force_encoding("UTF-8")) }.not_to raise_error
      end
    end

    it "dashboard has the correct title" do
      run_generator
      assert_file "config/grafana/e11y_dashboard.json" do |content|
        parsed = JSON.parse(content.force_encoding("UTF-8"))
        expect(parsed["title"]).to eq("E11y Observability")
      end
    end

    it "dashboard has panels array" do
      run_generator
      assert_file "config/grafana/e11y_dashboard.json" do |content|
        parsed = JSON.parse(content.force_encoding("UTF-8"))
        expect(parsed["panels"]).to be_an(Array)
        expect(parsed["panels"]).not_to be_empty
      end
    end

    it "dashboard panels include Events / sec panel" do
      run_generator
      assert_file "config/grafana/e11y_dashboard.json" do |content|
        parsed = JSON.parse(content.force_encoding("UTF-8"))
        titles = parsed["panels"].map { |p| p["title"] }
        expect(titles).to include("Events / sec")
      end
    end

    it "dashboard panels include Error rate panel" do
      run_generator
      assert_file "config/grafana/e11y_dashboard.json" do |content|
        parsed = JSON.parse(content.force_encoding("UTF-8"))
        titles = parsed["panels"].map { |p| p["title"] }
        expect(titles).to include("Error rate")
      end
    end

    it "dashboard panels include Circuit breaker trips panel" do
      run_generator
      assert_file "config/grafana/e11y_dashboard.json" do |content|
        parsed = JSON.parse(content.force_encoding("UTF-8"))
        titles = parsed["panels"].map { |p| p["title"] }
        expect(titles).to include("Circuit breaker trips")
      end
    end

    it "dashboard panels include DLQ queue depth panel" do
      run_generator
      assert_file "config/grafana/e11y_dashboard.json" do |content|
        parsed = JSON.parse(content.force_encoding("UTF-8"))
        titles = parsed["panels"].map { |p| p["title"] }
        expect(titles).to include("DLQ queue depth")
      end
    end

    it "dashboard references e11y_events_total metric" do
      run_generator
      assert_file "config/grafana/e11y_dashboard.json" do |content|
        expect(content.force_encoding("UTF-8")).to match(/e11y_events_total/)
      end
    end

    it "dashboard has uid field" do
      run_generator
      assert_file "config/grafana/e11y_dashboard.json" do |content|
        parsed = JSON.parse(content.force_encoding("UTF-8"))
        expect(parsed["uid"]).to eq("e11y-overview")
      end
    end

    it "dashboard has schemaVersion field" do
      run_generator
      assert_file "config/grafana/e11y_dashboard.json" do |content|
        parsed = JSON.parse(content.force_encoding("UTF-8"))
        expect(parsed["schemaVersion"]).to be_a(Integer)
      end
    end

    it "dashboard has e11y tag" do
      run_generator
      assert_file "config/grafana/e11y_dashboard.json" do |content|
        parsed = JSON.parse(content.force_encoding("UTF-8"))
        expect(parsed["tags"]).to include("e11y")
      end
    end
  end
end
