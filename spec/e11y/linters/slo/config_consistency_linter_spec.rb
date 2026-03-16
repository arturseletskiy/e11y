# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require "e11y/linters/base"
require "e11y/linters/slo/config_consistency_linter"
require "e11y/slo/config_loader"
require "e11y/slo/event_driven"

RSpec.describe E11y::Linters::SLO::ConfigConsistencyLinter do
  # Event with SLO enabled and contributes_to matching slo_name
  let(:valid_event_class) do
    Class.new(E11y::Event::Base) do
      schema { required(:id).filled(:string) }
      slo do
        enabled true
        contributes_to "payment_success_rate"
        slo_status_from { |p| p[:status] == "ok" ? "success" : "failure" }
      end

      def self.name
        "Events::PaymentProcessed"
      end

      def self.event_name
        "payment.processed"
      end
    end
  end

  # Event with SLO disabled
  let(:slo_disabled_event_class) do
    Class.new(E11y::Event::Base) do
      schema { required(:id).filled(:string) }
      slo { enabled false }

      def self.name
        "Events::SloDisabled"
      end

      def self.event_name
        "slo.disabled"
      end
    end
  end

  # Event with SLO enabled but contributes_to mismatch
  let(:mismatch_contributes_to_event_class) do
    Class.new(E11y::Event::Base) do
      schema { required(:id).filled(:string) }
      slo do
        enabled true
        contributes_to "other_slo_name"
        slo_status_from { |p| "success" }
      end

      def self.name
        "Events::OrderCreated"
      end

      def self.event_name
        "order.created"
      end
    end
  end

  before do
    stub_const("Events::PaymentProcessed", valid_event_class)
    stub_const("Events::SloDisabled", slo_disabled_event_class)
    stub_const("Events::OrderCreated", mismatch_contributes_to_event_class)
  end

  describe ".validate!" do
    context "when slo.yml has custom_slos with events, each event has slo enabled with matching contributes_to" do
      it "does not raise" do
        config = {
          "custom_slos" => [
            { "name" => "payment_success_rate", "events" => ["Events::PaymentProcessed"] }
          ]
        }
        allow(E11y::SLO::ConfigLoader).to receive(:load).and_return(config)

        expect { described_class.validate! }.not_to raise_error
      end

      it "does not raise when using ConfigLoader.load with search_paths (temp dir)" do
        Dir.mktmpdir do |dir|
          slo_yml = <<~YAML
            custom_slos:
              - name: payment_success_rate
                events:
                  - Events::PaymentProcessed
          YAML
          File.write(File.join(dir, "slo.yml"), slo_yml)

          expect { described_class.validate!(search_paths: [dir]) }.not_to raise_error
        end
      end
    end

    context "when event in slo.yml references Event class that has slo disabled" do
      it "raises LinterError" do
        config = {
          "custom_slos" => [
            { "name" => "some_slo", "events" => ["Events::SloDisabled"] }
          ]
        }
        allow(E11y::SLO::ConfigLoader).to receive(:load).and_return(config)

        expect { described_class.validate! }.to raise_error(
          E11y::Linters::LinterError,
          /slo disabled|SloDisabled/
        )
      end
    end

    context "when event in slo.yml has contributes_to that does not match slo_name" do
      it "raises LinterError" do
        config = {
          "custom_slos" => [
            { "name" => "order_creation_success_rate", "events" => ["Events::OrderCreated"] }
          ]
        }
        allow(E11y::SLO::ConfigLoader).to receive(:load).and_return(config)

        expect { described_class.validate! }.to raise_error(
          E11y::Linters::LinterError,
          /contributes_to|order_creation_success_rate|other_slo_name/
        )
      end
    end

    context "when event class in slo.yml does not exist (constantize fails)" do
      it "raises LinterError" do
        config = {
          "custom_slos" => [
            { "name" => "payment_success_rate", "events" => ["Events::NonExistentEvent"] }
          ]
        }
        allow(E11y::SLO::ConfigLoader).to receive(:load).and_return(config)

        expect { described_class.validate! }.to raise_error(
          E11y::Linters::LinterError,
          /NonExistentEvent|does not exist|constantize/
        )
      end
    end

    context "when config is nil" do
      it "does not raise" do
        allow(E11y::SLO::ConfigLoader).to receive(:load).and_return(nil)

        expect { described_class.validate! }.not_to raise_error
      end
    end

    context "when config has no custom_slos" do
      it "does not raise" do
        allow(E11y::SLO::ConfigLoader).to receive(:load).and_return({})

        expect { described_class.validate! }.not_to raise_error
      end

      it "does not raise when custom_slos is empty array" do
        allow(E11y::SLO::ConfigLoader).to receive(:load).and_return("custom_slos" => [])

        expect { described_class.validate! }.not_to raise_error
      end
    end
  end
end
