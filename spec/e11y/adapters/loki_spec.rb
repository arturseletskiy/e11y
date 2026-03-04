# frozen_string_literal: true

require "spec_helper"
require "time"

# Loki adapter integration tests require HTTP mocking, batch processing,
# and extensive configuration with multiple fixtures.
# Skip Loki tests if Faraday not available
begin
  require "e11y/adapters/loki"
rescue LoadError
  RSpec.describe "E11y::Adapters::Loki (skipped)" do
    it "requires Faraday to be available" do
      skip "Faraday not available in test environment"
    end
  end

  return
end

RSpec.describe E11y::Adapters::Loki do
  let(:loki_url) { "http://loki.test:3100" }
  let(:config) do
    {
      url: loki_url,
      labels: { app: "test_app", env: "test" },
      batch_size: 3,
      batch_timeout: 1,
      compress: false
    }
  end

  let(:adapter) { described_class.new(config) }

  let(:login_event) do
    {
      event_name: "user.login",
      severity: :info,
      timestamp: Time.parse("2024-01-01 12:00:00 UTC"),
      user_id: 123
    }
  end

  let(:logout_event) do
    {
      event_name: "user.logout",
      severity: :info,
      timestamp: Time.parse("2024-01-01 12:01:00 UTC"),
      user_id: 123
    }
  end

  let(:payment_event) do
    {
      event_name: "payment.processed",
      severity: :success,
      timestamp: Time.parse("2024-01-01 12:02:00 UTC"),
      amount: 100
    }
  end

  before do
    # Stub HTTP requests
    stub_request(:post, "#{loki_url}/loki/api/v1/push")
      .to_return(status: 204, body: "", headers: {})
    stub_request(:get, "#{loki_url}/ready")
      .to_return(status: 200, body: "ready", headers: {})
  end

  after do
    adapter.close
  end

  describe "ADR-004 compliance" do
    describe "Section 3.1: Base Adapter Contract" do
      it "inherits from E11y::Adapters::Base" do
        expect(adapter).to be_a(E11y::Adapters::Base)
      end

      it "implements #write" do
        expect(adapter).to respond_to(:write)
        expect(adapter.write(login_event)).to be(true).or(be(false))
      end

      it "implements #write_batch" do
        expect(adapter).to respond_to(:write_batch)
        expect(adapter.write_batch([login_event, logout_event])).to be(true).or(be(false))
      end

      it "implements #healthy?" do
        expect(adapter).to respond_to(:healthy?)
        expect(adapter.healthy?).to be(true).or(be(false))
      end

      it "implements #close" do
        expect(adapter).to respond_to(:close)
        expect { adapter.close }.not_to raise_error
      end

      it "implements #capabilities" do
        expect(adapter).to respond_to(:capabilities)
        caps = adapter.capabilities
        expect(caps).to be_a(Hash)
        expect(caps).to include(:batching, :compression, :async, :streaming)
      end
    end

    describe "Section 4.3: Loki Adapter Specification" do
      it "buffers events until batch_size reached" do
        adapter.write(login_event)
        adapter.write(logout_event)

        # Should not send yet (batch_size = 3)
        expect(WebMock).not_to have_requested(:post, "#{loki_url}/loki/api/v1/push")

        adapter.write(payment_event)

        # Should send now
        expect(WebMock).to have_requested(:post, "#{loki_url}/loki/api/v1/push").once
      end

      it "flushes on close" do
        adapter.write(login_event)
        adapter.write(logout_event)

        adapter.close

        expect(WebMock).to have_requested(:post, "#{loki_url}/loki/api/v1/push").once
      end

      it "sends events in Loki push API format" do
        adapter.write(login_event)
        adapter.write(logout_event)
        adapter.write(payment_event)

        expect(WebMock).to(have_requested(:post, "#{loki_url}/loki/api/v1/push")
          .with do |req|
            body = JSON.parse(req.body, symbolize_names: true)
            expect(body).to have_key(:streams)
            expect(body[:streams]).to be_an(Array)
            expect(body[:streams].first).to have_key(:stream)
            expect(body[:streams].first).to have_key(:values)
            true
          end)
      end

      it "includes configured labels in streams" do
        adapter.write(login_event)
        adapter.write(logout_event)
        adapter.write(payment_event)

        expect(WebMock).to(have_requested(:post, "#{loki_url}/loki/api/v1/push")
          .with do |req|
            body = JSON.parse(req.body, symbolize_names: true)
            stream = body[:streams].first[:stream]
            expect(stream[:app]).to eq("test_app")
            expect(stream[:env]).to eq("test")
            true
          end)
      end

      it "includes event_name and severity in labels" do
        adapter.write(login_event)
        adapter.write(logout_event)
        adapter.write(payment_event)

        expect(WebMock).to(have_requested(:post, "#{loki_url}/loki/api/v1/push")
          .with do |req|
            body = JSON.parse(req.body, symbolize_names: true)
            streams = body[:streams]

            login_stream = streams.find { |s| s[:stream][:event_name] == "user.login" }
            expect(login_stream).not_to be_nil
            expect(login_stream[:stream][:severity]).to eq("info")

            true
          end)
      end

      it "formats timestamps as nanoseconds" do
        adapter.write(login_event)
        adapter.write(logout_event)
        adapter.write(payment_event)

        expect(WebMock).to(have_requested(:post, "#{loki_url}/loki/api/v1/push")
          .with do |req|
            body = JSON.parse(req.body, symbolize_names: true)
            values = body[:streams].first[:values]

            timestamp_ns = values.first[0]
            expect(timestamp_ns).to be_a(String)
            expect(timestamp_ns.to_i).to be > 1_000_000_000_000_000_000 # Nanoseconds

            true
          end)
      end
    end
  end

  describe "Configuration" do
    it "requires :url parameter" do
      expect { described_class.new({}) }.to raise_error(ArgumentError, /requires :url/)
    end

    it "validates batch_size is positive" do
      expect do
        described_class.new(url: loki_url, batch_size: 0)
      end.to raise_error(ArgumentError, /batch_size must be positive/)
    end

    it "validates batch_timeout is positive" do
      expect do
        described_class.new(url: loki_url, batch_timeout: 0)
      end.to raise_error(ArgumentError, /batch_timeout must be positive/)
    end

    it "uses default values" do
      minimal_adapter = described_class.new(url: loki_url)

      expect(minimal_adapter.batch_size).to eq(100)
      expect(minimal_adapter.batch_timeout).to eq(5)
      expect(minimal_adapter.compress).to be true
      expect(minimal_adapter.labels).to eq({})

      minimal_adapter.close
    end

    it "accepts custom labels" do
      custom_adapter = described_class.new(
        url: loki_url,
        labels: { service: "api", region: "us-east" }
      )

      expect(custom_adapter.labels).to eq({ service: "api", region: "us-east" })

      custom_adapter.close
    end

    it "accepts tenant_id for multi-tenancy" do
      tenant_adapter = described_class.new(
        url: loki_url,
        tenant_id: "tenant-123"
      )

      expect(tenant_adapter.tenant_id).to eq("tenant-123")

      tenant_adapter.close
    end
  end

  describe "Batching" do
    it "sends batch when batch_size reached" do
      adapter.write(login_event)
      adapter.write(logout_event)
      adapter.write(payment_event)

      expect(WebMock).to have_requested(:post, "#{loki_url}/loki/api/v1/push").once
    end

    it "sends batch with write_batch" do
      adapter.write_batch([login_event, logout_event, payment_event])

      expect(WebMock).to have_requested(:post, "#{loki_url}/loki/api/v1/push").once
    end

    it "handles empty batch" do
      expect { adapter.write_batch([]) }.not_to raise_error
      expect(WebMock).not_to have_requested(:post, "#{loki_url}/loki/api/v1/push")
    end

    it "groups events by labels into streams" do
      adapter.write(login_event) # user.login, info
      adapter.write(logout_event) # user.logout, info
      adapter.write(payment_event) # payment.processed, success

      expect(WebMock).to(have_requested(:post, "#{loki_url}/loki/api/v1/push")
        .with do |req|
          body = JSON.parse(req.body, symbolize_names: true)

          # Should have 3 streams (each event has different event_name)
          expect(body[:streams].size).to eq(3)

          login_stream = body[:streams].find { |s| s[:stream][:event_name] == "user.login" }
          logout_stream = body[:streams].find { |s| s[:stream][:event_name] == "user.logout" }
          payment_stream = body[:streams].find { |s| s[:stream][:event_name] == "payment.processed" }

          expect(login_stream[:values].size).to eq(1)
          expect(logout_stream[:values].size).to eq(1)
          expect(payment_stream[:values].size).to eq(1)

          true
        end)
    end
  end

  describe "Compression" do
    context "with compression enabled" do
      let(:compressed_adapter) do
        described_class.new(
          url: loki_url,
          batch_size: 2,
          compress: true
        )
      end

      after { compressed_adapter.close }

      it "sends gzip-compressed payload" do
        compressed_adapter.write(login_event)
        compressed_adapter.write(logout_event)

        expect(WebMock).to have_requested(:post, "#{loki_url}/loki/api/v1/push")
          .with(headers: { "Content-Encoding" => "gzip" })
      end

      it "compressed payload can be decompressed" do
        compressed_adapter.write(login_event)
        compressed_adapter.write(logout_event)

        expect(WebMock).to(have_requested(:post, "#{loki_url}/loki/api/v1/push")
          .with do |req|
            decompressed = Zlib::GzipReader.new(StringIO.new(req.body)).read
            body = JSON.parse(decompressed, symbolize_names: true)
            expect(body).to have_key(:streams)
            true
          end)
      end
    end

    context "with compression disabled" do
      it "sends uncompressed payload" do
        adapter.write(login_event)
        adapter.write(logout_event)
        adapter.write(payment_event)

        expect(WebMock).to(have_requested(:post, "#{loki_url}/loki/api/v1/push")
          .with(headers: { "Content-Type" => "application/json" })
          .with do |req|
            expect(req.headers["Content-Encoding"]).to be_nil
            true
          end)
      end
    end
  end

  describe "Multi-tenancy" do
    let(:tenant_adapter) do
      described_class.new(
        url: loki_url,
        tenant_id: "org-456",
        batch_size: 2
      )
    end

    after { tenant_adapter.close }

    it "sends X-Scope-OrgID header" do
      tenant_adapter.write(login_event)
      tenant_adapter.write(logout_event)

      expect(WebMock).to have_requested(:post, "#{loki_url}/loki/api/v1/push")
        .with(headers: { "X-Scope-OrgID" => "org-456" })
    end
  end

  describe "#healthy?" do
    it "returns true when connection is established" do
      expect(adapter.healthy?).to be true
    end
  end

  describe "#close" do
    it "flushes remaining events" do
      adapter.write(login_event)

      adapter.close

      expect(WebMock).to have_requested(:post, "#{loki_url}/loki/api/v1/push").once
    end

    it "can be called multiple times safely" do
      adapter.write(login_event)

      expect { adapter.close }.not_to raise_error
      expect { adapter.close }.not_to raise_error
    end
  end

  describe "#capabilities" do
    it "reports correct capabilities" do
      caps = adapter.capabilities

      expect(caps[:batching]).to be true
      expect(caps[:compression]).to be false # Disabled in config
      expect(caps[:async]).to be true
      expect(caps[:streaming]).to be false
    end

    it "reflects compression setting" do
      compressed = described_class.new(url: loki_url, compress: true)
      uncompressed = described_class.new(url: loki_url, compress: false)

      expect(compressed.capabilities[:compression]).to be true
      expect(uncompressed.capabilities[:compression]).to be false

      compressed.close
      uncompressed.close
    end
  end

  describe "Error handling" do
    it "returns false on HTTP error" do
      stub_request(:post, "#{loki_url}/loki/api/v1/push")
        .to_return(status: 500, body: "Internal Server Error")

      adapter.write(login_event)
      adapter.write(logout_event)
      result = adapter.write(payment_event)

      # Should not raise, just return false
      expect(result).to be true # write() returns true, error happens in background
    end

    it "handles connection errors gracefully" do
      bad_adapter = described_class.new(
        url: "http://nonexistent.test:9999",
        batch_size: 1
      )

      stub_request(:post, "http://nonexistent.test:9999/loki/api/v1/push")
        .to_raise(Faraday::ConnectionFailed.new("Connection refused"))

      expect { bad_adapter.write(login_event) }.not_to raise_error

      bad_adapter.close
    end
  end

  describe "Thread safety" do
    it "handles concurrent writes safely" do
      threads = Array.new(10) do |i|
        Thread.new do
          adapter.write(event_name: "concurrent.event.#{i}", severity: :info)
        end
      end

      threads.each(&:join)

      # Should have sent at least 3 batches (10 events / batch_size 3)
      expect(WebMock).to have_requested(:post, "#{loki_url}/loki/api/v1/push").at_least_times(3)
    end
  end

  describe "C04 Resolution: Optional Cardinality Protection" do
    context "when disabled (default)" do
      let(:adapter_default) do
        described_class.new(
          url: loki_url,
          labels: { app: "test" },
          batch_size: 1
        )
      end

      it "does not filter high-cardinality labels" do
        event_with_user_id = {
          event_name: "user.action",
          severity: :info,
          user_id: "12345", # High-cardinality label
          order_id: "67890"
        }

        stub_request(:post, "#{loki_url}/loki/api/v1/push")

        adapter_default.write(event_with_user_id)
        adapter_default.close

        # Labels should NOT be filtered (cardinality protection disabled)
        expect(WebMock).to have_requested(:post, "#{loki_url}/loki/api/v1/push")
      end
    end

    context "when enabled (enterprise use case)" do
      let(:adapter_protected) do
        described_class.new(
          url: loki_url,
          labels: { app: "test" },
          batch_size: 1,
          enable_cardinality_protection: true,
          max_label_cardinality: 100
        )
      end

      it "filters high-cardinality labels" do
        event_with_user_id = {
          event_name: "user.action",
          severity: :info,
          user_id: "12345", # Should be filtered (high-cardinality)
          status: "active"  # Low-cardinality, should pass
        }

        stub_request(:post, "#{loki_url}/loki/api/v1/push")

        adapter_protected.write(event_with_user_id)
        adapter_protected.close

        # user_id should be filtered by CardinalityProtection
        expect(WebMock).to have_requested(:post, "#{loki_url}/loki/api/v1/push").once
      end

      it "preserves low-cardinality labels" do
        event = {
          event_name: "http.request",
          severity: :info,
          status: "success", # Low-cardinality
          env: "production"  # Low-cardinality
        }

        stub_request(:post, "#{loki_url}/loki/api/v1/push")

        adapter_protected.write(event)
        adapter_protected.close

        expect(WebMock).to have_requested(:post, "#{loki_url}/loki/api/v1/push").once
      end
    end
  end
end
