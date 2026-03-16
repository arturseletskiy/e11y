# frozen_string_literal: true

require "spec_helper"
require "e11y/linters/pii/pii_declaration_linter"

RSpec.describe E11y::Linters::PII::PiiDeclarationLinter do
  # Event with contains_pii true and all fields declared
  let(:pii_ok_event) do
    Class.new(E11y::Event::Base) do
      schema do
        required(:user_id).filled(:string)
        required(:email).filled(:string)
      end

      contains_pii true
      pii_filtering do
        allows :user_id
        hashes :email
      end

      def self.name
        "Events::PiiOk"
      end

      def self.event_name
        "pii.ok"
      end
    end
  end

  # Event with contains_pii true but missing field declarations
  let(:pii_missing_event) do
    Class.new(E11y::Event::Base) do
      schema do
        required(:user_id).filled(:string)
        required(:email).filled(:string)
        required(:ip_address).filled(:string)
      end

      contains_pii true
      pii_filtering do
        allows :user_id
        hashes :email
      end

      def self.name
        "Events::PiiMissing"
      end

      def self.event_name
        "pii.missing"
      end
    end
  end

  # Event with contains_pii false (skipped)
  let(:no_pii_event) do
    Class.new(E11y::Event::Base) do
      schema { required(:id).filled(:string) }
      contains_pii false

      def self.name
        "Events::NoPii"
      end

      def self.event_name
        "no.pii"
      end
    end
  end

  # Event with no contains_pii (default, skipped)
  let(:default_pii_event) do
    Class.new(E11y::Event::Base) do
      schema { required(:id).filled(:string) }

      def self.name
        "Events::DefaultPii"
      end

      def self.event_name
        "default.pii"
      end
    end
  end

  # Event with contains_pii true, no schema (skip)
  let(:pii_no_schema_event) do
    Class.new(E11y::Event::Base) do
      contains_pii true

      def self.name
        "Events::PiiNoSchema"
      end

      def self.event_name
        "pii.no_schema"
      end
    end
  end

  # Event with invalid strategy
  let(:pii_invalid_strategy_event) do
    Class.new(E11y::Event::Base) do
      schema { required(:email).filled(:string) }

      contains_pii true
      pii_filtering do
        field :email do
          strategy :invalid_strategy
        end
      end

      def self.name
        "Events::PiiInvalidStrategy"
      end

      def self.event_name
        "pii.invalid_strategy"
      end
    end
  end

  describe ".validate!" do
    context "when contains_pii is not true" do
      it "skips validation for contains_pii false" do
        expect { described_class.validate!(no_pii_event) }.not_to raise_error
      end

      it "skips validation when contains_pii not set" do
        expect { described_class.validate!(default_pii_event) }.not_to raise_error
      end
    end

    context "when contains_pii true and all schema fields declared" do
      it "does not raise" do
        expect { described_class.validate!(pii_ok_event) }.not_to raise_error
      end
    end

    context "when contains_pii true but schema fields missing from pii_filtering" do
      it "raises PiiDeclarationError with missing fields" do
        expect { described_class.validate!(pii_missing_event) }.to raise_error(
          E11y::Linters::PII::PiiDeclarationError,
          /Missing fields:.*ip_address/
        )
      end

      it "includes fix suggestion in error message" do
        expect { described_class.validate!(pii_missing_event) }.to raise_error(
          E11y::Linters::PII::PiiDeclarationError,
          /pii_filtering do/
        )
      end
    end

    context "when contains_pii true but no schema" do
      it "does not raise (nothing to validate)" do
        expect { described_class.validate!(pii_no_schema_event) }.not_to raise_error
      end
    end

    context "when field has invalid strategy" do
      it "raises PiiDeclarationError" do
        expect { described_class.validate!(pii_invalid_strategy_event) }.to raise_error(
          E11y::Linters::PII::PiiDeclarationError,
          /invalid_strategy/
        )
      end
    end
  end

  describe ".validate_all!" do
    it "does not raise when all events pass" do
      allow(E11y::Registry).to receive(:event_classes).and_return([pii_ok_event, no_pii_event])

      expect { described_class.validate_all! }.not_to raise_error
    end

    it "raises PiiDeclarationError when any event fails" do
      allow(E11y::Registry).to receive(:event_classes).and_return([pii_ok_event, pii_missing_event])

      expect { described_class.validate_all! }.to raise_error(
        E11y::Linters::PII::PiiDeclarationError,
        /ip_address/
      )
    end

    it "collects all errors when multiple events fail" do
      allow(E11y::Registry).to receive(:event_classes).and_return([pii_missing_event, pii_invalid_strategy_event])

      expect { described_class.validate_all! }.to raise_error(
        E11y::Linters::PII::PiiDeclarationError
      ) do |e|
        expect(e.message).to include("ip_address")
        expect(e.message).to include("invalid_strategy")
      end
    end

    it "does not raise when registry is empty" do
      allow(E11y::Registry).to receive(:event_classes).and_return([])

      expect { described_class.validate_all! }.not_to raise_error
    end
  end
end
