# frozen_string_literal: true

require "spec_helper"
require "e11y/linters/base"
require "e11y/linters/slo/slo_status_from_linter"

RSpec.describe E11y::Linters::SLO::SloStatusFromLinter do
  def event_double(name:, slo_enabled:, slo_status_proc: nil, contributes_to_value: nil)
    slo_config = instance_double(
      E11y::SLO::EventDriven::SLOConfig,
      slo_status_proc: slo_status_proc,
      contributes_to_value: contributes_to_value
    )
    event_class = instance_double(EventClass, name: name)
    allow(event_class).to receive_messages(slo_enabled?: slo_enabled, slo_config: slo_enabled ? slo_config : nil)
    event_class
  end

  describe ".validate!" do
    context "when event has slo enabled with slo_status_from and contributes_to" do
      it "does not raise" do
        valid_event = event_double(
          name: "Events::Valid",
          slo_enabled: true,
          slo_status_proc: proc { "success" },
          contributes_to_value: "payment_success_rate"
        )
        allow(E11y::Registry).to receive(:event_classes).and_return([valid_event])

        expect { described_class.validate! }.not_to raise_error
      end
    end

    context "when event has slo enabled but missing slo_status_from" do
      it "raises LinterError with 'slo_status_from'" do
        event = event_double(
          name: "Events::MissingSloStatusFrom",
          slo_enabled: true,
          slo_status_proc: nil,
          contributes_to_value: "payment_success_rate"
        )
        allow(E11y::Registry).to receive(:event_classes).and_return([event])

        expect { described_class.validate! }.to raise_error(
          E11y::Linters::LinterError,
          /slo_status_from/
        )
      end
    end

    context "when event has slo enabled but missing contributes_to" do
      it "raises LinterError with 'contributes_to'" do
        event = event_double(
          name: "Events::MissingContributesTo",
          slo_enabled: true,
          slo_status_proc: proc { "success" },
          contributes_to_value: nil
        )
        allow(E11y::Registry).to receive(:event_classes).and_return([event])

        expect { described_class.validate! }.to raise_error(
          E11y::Linters::LinterError,
          /contributes_to/
        )
      end
    end

    context "when event has slo disabled" do
      it "does not raise (skips validation)" do
        slo_disabled_event = event_double(
          name: "Events::SloDisabled",
          slo_enabled: false,
          slo_status_proc: nil,
          contributes_to_value: nil
        )
        allow(E11y::Registry).to receive(:event_classes).and_return([slo_disabled_event])

        expect { described_class.validate! }.not_to raise_error
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
