# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/SpecFilePathFormat
# Organized under configuration/ directory for logical grouping.
RSpec.describe E11y::ErrorHandlingConfig do
  let(:config) { described_class.new }

  describe "#initialize" do
    it "defaults fail_on_error to true" do
      expect(config.fail_on_error).to be true
    end
  end

  describe "#fail_on_error=" do
    it "allows setting fail_on_error to false" do
      config.fail_on_error = false
      expect(config.fail_on_error).to be false
    end

    it "allows setting fail_on_error to true" do
      config.fail_on_error = true
      expect(config.fail_on_error).to be true
    end
  end

  describe "C18 Resolution: Non-Failing Event Tracking in Background Jobs" do
    context "when fail_on_error = true (default)" do
      it "represents web request context (fast feedback)" do
        expect(config.fail_on_error).to be true
      end
    end

    context "when fail_on_error = false (background jobs)" do
      before { config.fail_on_error = false }

      # rubocop:disable RSpec/RepeatedExample
      # Documenting different aspects of same configuration (context and behavior)
      it "represents background job context (don't fail business logic)" do
        expect(config.fail_on_error).to be false
      end

      it "allows event tracking failures to be swallowed" do
        # This test documents the expected behavior:
        # In background jobs, E11y errors should NOT raise exceptions
        expect(config.fail_on_error).to be false
      end
      # rubocop:enable RSpec/RepeatedExample
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
