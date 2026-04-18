# spec/e11y/adapters/action_mailer_adapter_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "e11y/store/memory"
require "e11y/adapters/action_mailer_adapter"

# Minimal ActionMailer stub (no Rails required for unit tests)
class FakeMailer
  class << self
    attr_accessor :last_alert, :last_digest, :last_recipients, :last_instance

    def critical_alert(event_data, recipients)
      @last_alert = event_data
      @last_recipients = recipients
      @last_instance = new
    end

    def digest(digest_data, recipients)
      @last_digest = digest_data
      @last_recipients = recipients
      @last_instance = new
    end
  end

  # rubocop:disable Naming/PredicateMethod
  def deliver_now = true
  def deliver_later = true
  # rubocop:enable Naming/PredicateMethod
end

RSpec.describe E11y::Adapters::ActionMailerAdapter do
  let(:store)      { E11y::Store::Memory.new }
  let(:recipients) { ["ops@example.com"] }

  let(:adapter) do
    described_class.new(
      mailer: FakeMailer,
      alert_method: :critical_alert,
      digest_method: :digest,
      recipients: recipients,
      delivery: :now,
      store: store
    )
  end

  let(:error_event) do
    {
      event_name: "payment.failed",
      severity: :error,
      payload: { order_id: "ORD-1" },
      notify: { alert: { throttle_window: 1800, fingerprint: [:event_name] } }
    }
  end

  before do
    FakeMailer.last_alert = nil
    FakeMailer.last_digest = nil
    FakeMailer.last_recipients = nil
    FakeMailer.last_instance = nil
  end

  describe "#initialize" do
    it "raises without :mailer" do
      expect do
        described_class.new(
          alert_method: :critical_alert, digest_method: :digest,
          recipients: recipients, store: store
        )
      end.to raise_error(ArgumentError, /mailer/)
    end

    it "raises without :store" do
      expect do
        described_class.new(
          mailer: FakeMailer, alert_method: :critical_alert,
          digest_method: :digest, recipients: recipients
        )
      end.to raise_error(ArgumentError, /store/)
    end

    it "defaults delivery to :later" do
      a = described_class.new(
        mailer: FakeMailer, alert_method: :critical_alert,
        digest_method: :digest, recipients: recipients, store: store
      )
      expect(a.instance_variable_get(:@delivery)).to eq(:later)
    end
  end

  describe "#write — alert delivery" do
    it "calls alert_method on mailer with event_data and recipients" do
      adapter.write(error_event)
      expect(FakeMailer.last_alert).to eq(error_event)
      expect(FakeMailer.last_recipients).to eq(recipients)
    end

    it "calls deliver_now when delivery: :now" do
      mail_spy = instance_spy(FakeMailer)
      allow(FakeMailer).to receive(:critical_alert).and_return(mail_spy)
      adapter.write(error_event)
      expect(mail_spy).to have_received(:deliver_now)
    end

    it "calls deliver_later when delivery: :later" do
      later_adapter = described_class.new(
        mailer: FakeMailer, alert_method: :critical_alert,
        digest_method: :digest, recipients: recipients,
        delivery: :later, store: store
      )
      mail_spy = instance_spy(FakeMailer)
      allow(FakeMailer).to receive(:critical_alert).and_return(mail_spy)
      later_adapter.write(error_event)
      expect(mail_spy).to have_received(:deliver_later)
    end

    it "suppresses duplicate within throttle window" do
      mail_spy = instance_spy(FakeMailer)
      allow(FakeMailer).to receive(:critical_alert).and_return(mail_spy)
      adapter.write(error_event)
      adapter.write(error_event)
      expect(mail_spy).to have_received(:deliver_now).once
    end

    it "returns true for event without notify config" do
      expect(adapter.write(error_event.except(:notify))).to be(true)
    end
  end

  describe "#adapter_id_source" do
    it "is stable across instances with same config" do
      a1 = described_class.new(
        mailer: FakeMailer, alert_method: :critical_alert,
        digest_method: :digest, recipients: recipients, store: store
      )
      a2 = described_class.new(
        mailer: FakeMailer, alert_method: :critical_alert,
        digest_method: :digest, recipients: recipients, store: store
      )
      expect(a1.send(:adapter_id)).to eq(a2.send(:adapter_id))
    end
  end
end
