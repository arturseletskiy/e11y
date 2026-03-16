# frozen_string_literal: true

require "spec_helper"
require "e11y/linters/base"
require "e11y/linters/slo/explicit_declaration_linter"
require "e11y/slo/event_driven"

RSpec.describe E11y::Linters::SLO::ExplicitDeclarationLinter do
  # Event with SLO enabled
  let(:slo_enabled_event) do
    Class.new(E11y::Event::Base) do
      schema { required(:id).filled(:string) }
      slo do
        enabled true
        slo_status_from { |p| p[:status] == "ok" ? "success" : "failure" }
      end

      def self.name
        "Events::SloEnabled"
      end

      def self.event_name
        "slo.enabled"
      end
    end
  end

  # Event with SLO explicitly disabled
  let(:slo_disabled_event) do
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

  # Event with no SLO declaration
  let(:no_slo_event) do
    Class.new(E11y::Event::Base) do
      schema { required(:id).filled(:string) }

      def self.name
        "Events::NoSlo"
      end

      def self.event_name
        "no.slo"
      end
    end
  end

  describe ".validate!" do
    context "when all event classes have slo_enabled? or slo_disabled?" do
      it "does not raise" do
        allow(E11y::Registry).to receive(:event_classes).and_return([slo_enabled_event, slo_disabled_event])

        expect { described_class.validate! }.not_to raise_error
      end
    end

    context "when an event class has neither slo_enabled? nor slo_disabled?" do
      it "raises E11y::Linters::LinterError with message matching 'missing explicit SLO'" do
        allow(E11y::Registry).to receive(:event_classes).and_return([slo_enabled_event, no_slo_event])

        expect { described_class.validate! }.to raise_error(
          E11y::Linters::LinterError,
          /missing explicit SLO/
        )
      end

      it "includes event name in error message" do
        allow(E11y::Registry).to receive(:event_classes).and_return([no_slo_event])

        expect { described_class.validate! }.to raise_error(
          E11y::Linters::LinterError,
          /Event.*NoSlo|no\.slo/
        )
      end

      it "suggests adding slo do ... end or slo false" do
        allow(E11y::Registry).to receive(:event_classes).and_return([no_slo_event])

        expect { described_class.validate! }.to raise_error(
          E11y::Linters::LinterError,
          /slo do \.\.\. end|slo false/
        )
      end
    end

    context "when registry is empty" do
      it "does not raise" do
        allow(E11y::Registry).to receive(:event_classes).and_return([])

        expect { described_class.validate! }.not_to raise_error
      end
    end
  end
end
