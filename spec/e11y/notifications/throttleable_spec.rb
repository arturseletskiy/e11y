# spec/e11y/notifications/throttleable_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "e11y/store/memory"
require "e11y/notifications/throttleable"

RSpec.describe E11y::Notifications::Throttleable do
  # Minimal concrete class that includes the concern
  let(:adapter_class) do
    Class.new do
      include E11y::Notifications::Throttleable

      attr_reader :delivered_alerts, :delivered_digests

      def initialize(store:, max_event_types: 20)
        @store = store
        @max_event_types = max_event_types
        @delivered_alerts  = []
        @delivered_digests = []
      end

      def adapter_id_source
        "test:adapter"
      end

      # rubocop:disable Naming/PredicateMethod
      def deliver_alert(event_data)
        @delivered_alerts << event_data
        true
      end

      # rubocop:disable Metrics/ParameterLists
      def deliver_digest(events:, window_start:, window_end:, total_count:, truncated:, truncated_count:) # rubocop:disable Lint/UnusedMethodArgument
        @delivered_digests << {
          events: events,
          window_start: window_start,
          total_count: total_count,
          truncated: truncated,
          truncated_count: truncated_count
        }
        true
      end
      # rubocop:enable Metrics/ParameterLists
      # rubocop:enable Naming/PredicateMethod
    end
  end

  let(:store) { E11y::Store::Memory.new }
  let(:adapter) { adapter_class.new(store: store) }

  def event(name: "payment.failed", severity: :error, notify: nil)
    {
      event_name: name,
      severity: severity,
      payload: { amount: 100 },
      timestamp: Time.now.utc,
      notify: notify
    }.compact
  end

  describe "drop behaviour (no notify config)" do
    it "returns true but delivers nothing" do
      result = adapter.write(event)
      expect(result).to be(true)
      expect(adapter.delivered_alerts).to be_empty
    end
  end

  describe "alert throttling" do
    let(:notify_cfg) do
      { alert: { throttle_window: 300, fingerprint: [:event_name] } }
    end

    it "delivers first event immediately" do
      adapter.write(event(notify: notify_cfg))
      expect(adapter.delivered_alerts.size).to eq(1)
    end

    it "suppresses duplicate within throttle window" do
      adapter.write(event(notify: notify_cfg))
      adapter.write(event(notify: notify_cfg))
      adapter.write(event(notify: notify_cfg))
      expect(adapter.delivered_alerts.size).to eq(1)
    end

    it "delivers again after throttle window expires" do
      short_cfg = { alert: { throttle_window: 0.01, fingerprint: [:event_name] } }
      adapter.write(event(notify: short_cfg))
      sleep(0.02)
      adapter.write(event(notify: short_cfg))
      expect(adapter.delivered_alerts.size).to eq(2)
    end

    it "treats different fingerprints as independent" do
      cfg = { alert: { throttle_window: 300, fingerprint: [:event_name] } }
      adapter.write(event(name: "payment.failed",   notify: cfg))
      adapter.write(event(name: "order.timeout",    notify: cfg))
      expect(adapter.delivered_alerts.size).to eq(2)
    end

    it "supports nested fingerprint field 'payload.amount'" do
      cfg = { alert: { throttle_window: 300, fingerprint: ["payload.amount"] } }
      adapter.write(event(notify: cfg))
      adapter.write(event(notify: cfg))
      expect(adapter.delivered_alerts.size).to eq(1)
    end
  end

  describe "digest accumulation" do
    let(:interval) { 3600 }
    let(:notify_cfg) { { digest: { interval: interval } } }

    it "does not deliver immediately" do
      adapter.write(event(notify: notify_cfg))
      expect(adapter.delivered_digests).to be_empty
    end

    it "accumulates counts per event_name" do
      3.times { adapter.write(event(name: "slow.query",  notify: notify_cfg)) }
      2.times { adapter.write(event(name: "cache.miss",  notify: notify_cfg)) }

      now = Time.now.to_i
      current_window  = (now / interval) * interval
      previous_window = current_window - interval

      adapter.send(:copy_window_to_previous!, current_window, previous_window, notify_cfg)

      allow(Time).to receive(:now).and_return(Time.at(current_window + interval + 1))
      adapter.write(event(notify: notify_cfg))

      expect(adapter.delivered_digests.size).to eq(1)
      names = adapter.delivered_digests.first[:events].map { |e| e[:event_name] }
      expect(names).to include("slow.query", "cache.miss")
    end

    it "flushes only once per window across multiple calls (distributed lock)" do
      now = Time.now.to_i
      current_window  = (now / interval) * interval
      previous_window = current_window - interval

      adapter.send(:copy_window_to_previous!, current_window, previous_window, notify_cfg)

      allow(Time).to receive(:now).and_return(Time.at(current_window + interval + 1))
      5.times { adapter.write(event(notify: notify_cfg)) }
      expect(adapter.delivered_digests.size).to eq(1)
    end

    it "copy_window_to_previous! accepts inner digest_cfg format { interval: N }" do
      now = Time.now.to_i
      current_window  = (now / interval) * interval
      previous_window = current_window - interval

      adapter.write(event(name: "inner.format", notify: notify_cfg))
      # Pass inner hash directly (not the full notify hash)
      inner_cfg = { interval: interval }
      adapter.send(:copy_window_to_previous!, current_window, previous_window, inner_cfg)

      allow(Time).to receive(:now).and_return(Time.at(current_window + interval + 1))
      adapter.write(event(notify: notify_cfg))
      expect(adapter.delivered_digests.size).to eq(1)
    end
  end

  describe "max_event_types cap" do
    let(:adapter_capped) { adapter_class.new(store: store, max_event_types: 2) }

    it "tracks only max_event_types unique names, marks overflow" do
      cfg = { digest: { interval: 3600 } }
      adapter_capped.write(event(name: "a.event", notify: cfg))
      adapter_capped.write(event(name: "b.event", notify: cfg))
      adapter_capped.write(event(name: "c.event", notify: cfg)) # overflow

      now = Time.now.to_i
      current_window  = (now / 3600) * 3600
      previous_window = current_window - 3600
      adapter_capped.send(:copy_window_to_previous!, current_window, previous_window, cfg)

      allow(Time).to receive(:now).and_return(Time.at(current_window + 3601))
      adapter_capped.write(event(notify: cfg))

      digest = adapter_capped.delivered_digests.first
      expect(digest[:events].size).to eq(2)
      expect(digest[:truncated]).to be(true)
      expect(digest[:truncated_count]).to eq(1)
    end
  end
end
