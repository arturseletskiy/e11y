# spec/e11y/adapters/mattermost_adapter_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"
require "e11y/store/memory"
require "e11y/adapters/mattermost_adapter"

RSpec.describe E11y::Adapters::MattermostAdapter do
  let(:webhook_url) { "https://mattermost.example.com/hooks/abc123" }
  let(:store) { E11y::Store::Memory.new }

  let(:adapter) do
    described_class.new(
      webhook_url: webhook_url,
      store: store
    )
  end

  let(:error_event) do
    {
      event_name: "payment.failed",
      severity: :error,
      message: "Card declined",
      payload: { order_id: "ORD-123", amount: 99 },
      context: { trace_id: "trace-abc" },
      notify: { alert: { throttle_window: 1800, fingerprint: [:event_name] } }
    }
  end

  before { WebMock.enable! }
  after  { WebMock.reset! }

  describe "#initialize" do
    it "raises without :webhook_url" do
      expect { described_class.new(store: store) }.to raise_error(ArgumentError, /webhook_url/)
    end

    it "raises without :store" do
      expect { described_class.new(webhook_url: webhook_url) }.to raise_error(ArgumentError, /store/)
    end

    it "accepts optional channel and username" do
      adapter = described_class.new(
        webhook_url: webhook_url,
        channel: "#alerts",
        username: "E11y Bot",
        store: store
      )
      expect(adapter).to be_a(described_class)
    end
  end

  describe "#write — alert delivery" do
    it "POSTs JSON to webhook on first occurrence" do
      stub = stub_request(:post, webhook_url).to_return(status: 200)
      adapter.write(error_event)
      expect(stub).to have_been_requested
    end

    it "sends valid JSON with text field" do
      captured = nil
      stub_request(:post, webhook_url).with do |req|
        captured = req
        true
      end.to_return(status: 200)
      adapter.write(error_event)

      body = JSON.parse(captured.body)
      expect(body).to have_key("text")
      expect(body["text"]).to include("payment.failed")
    end

    it "includes channel when configured" do
      adapter_with_channel = described_class.new(
        webhook_url: webhook_url,
        channel: "#prod-alerts",
        store: store
      )
      captured = nil
      stub_request(:post, webhook_url).with do |req|
        captured = req
        true
      end.to_return(status: 200)
      adapter_with_channel.write(error_event)

      body = JSON.parse(captured.body)
      expect(body["channel"]).to eq("#prod-alerts")
    end

    it "suppresses duplicate within throttle window" do
      stub = stub_request(:post, webhook_url).to_return(status: 200)
      adapter.write(error_event)
      adapter.write(error_event)
      expect(stub).to have_been_requested.once
    end

    it "returns false on HTTP error, does not raise" do
      stub_request(:post, webhook_url).to_return(status: 500)
      expect(adapter.write(error_event)).to be(false)
    end

    it "returns false on network error, does not raise" do
      stub_request(:post, webhook_url).to_raise(Errno::ECONNREFUSED)
      expect(adapter.write(error_event)).to be(false)
    end

    it "returns true and delivers nothing for event without notify" do
      stub = stub_request(:post, webhook_url)
      event_no_notify = error_event.except(:notify)
      result = adapter.write(event_no_notify)
      expect(result).to be(true)
      expect(stub).not_to have_been_requested
    end
  end

  describe "alert message format" do
    it "includes severity emoji, event name, and payload fields" do
      captured = nil
      stub_request(:post, webhook_url).with do |req|
        captured = req
        true
      end.to_return(status: 200)
      adapter.write(error_event)

      text = JSON.parse(captured.body)["text"]
      expect(text).to include("🔴")
      expect(text).to include("payment.failed")
      expect(text).to include("order_id")
    end

    it "includes trace_id when present" do
      captured = nil
      stub_request(:post, webhook_url).with do |req|
        captured = req
        true
      end.to_return(status: 200)
      adapter.write(error_event)

      text = JSON.parse(captured.body)["text"]
      expect(text).to include("trace-abc")
    end
  end

  describe "#healthy?" do
    it "returns true when webhook_url set and store present" do
      expect(adapter.healthy?).to be(true)
    end
  end
end
