# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/SpecFilePathFormat
# Organized under configuration/ directory for logical grouping.
# Tests flat error_handling_fail_on_error on E11y::Configuration (Task 2 refactor).
RSpec.describe "E11y::Configuration#error_handling_fail_on_error" do
  let(:config) { E11y.config }

  before { E11y.reset! }
  after { E11y.reset! }

  describe "default" do
    it "defaults error_handling_fail_on_error to true" do
      expect(config.error_handling_fail_on_error).to be true
    end
  end

  describe "#error_handling_fail_on_error=" do
    it "allows setting error_handling_fail_on_error to false" do
      config.error_handling_fail_on_error = false
      expect(config.error_handling_fail_on_error).to be false
    end

    it "allows setting error_handling_fail_on_error to true" do
      config.error_handling_fail_on_error = true
      expect(config.error_handling_fail_on_error).to be true
    end
  end

  describe "C18 Resolution: Non-Failing Event Tracking in Background Jobs" do
    context "when error_handling_fail_on_error = true (default)" do
      it "represents web request context (fast feedback)" do
        expect(config.error_handling_fail_on_error).to be true
      end
    end

    context "when error_handling_fail_on_error = false (background jobs)" do
      before { config.error_handling_fail_on_error = false }

      # rubocop:disable RSpec/RepeatedExample
      # Documenting different aspects of same configuration (context and behavior)
      it "represents background job context (don't fail business logic)" do
        expect(config.error_handling_fail_on_error).to be false
      end

      it "allows event tracking failures to be swallowed" do
        # This test documents the expected behavior:
        # In background jobs, E11y errors should NOT raise exceptions
        expect(config.error_handling_fail_on_error).to be false
      end
      # rubocop:enable RSpec/RepeatedExample
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
