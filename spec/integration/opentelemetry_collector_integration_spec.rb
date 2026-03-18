# frozen_string_literal: true

require "rails_helper"

# OpenTelemetry Collector adapter integration (ADR-007 §3, F1)
# Requires: Faraday, integration bundle
RSpec.describe "OpenTelemetry Collector Adapter Integration", :integration do
  let(:collector_url) { ENV["OTEL_COLLECTOR_URL"] || "http://localhost:4318" }

  before do
    require_dependency!("Faraday", gem_name: "faraday")
    require "e11y/adapters/opentelemetry_collector"
  end

  describe "OpenTelemetryCollector adapter" do
    let(:adapter) do
      E11y::Adapters::OpenTelemetryCollector.new(
        endpoint: collector_url,
        service_name: "e11y-integration-test",
        compress: false # Stub expects JSON; production uses compress: true (default)
      )
    end

    let(:event_data) do
      {
        event_name: "order.paid",
        severity: :info,
        timestamp: Time.now.utc,
        trace_id: "a1b2c3d4e5f6789012345678abcdef01",
        span_id: "1234567890abcdef",
        payload: { order_id: "ord-123", amount: 99.99 }
      }
    end

    it "sends OTLP HTTP request to /v1/logs" do
      request_body = nil
      stub_request(:post, "#{collector_url}/v1/logs")
        .to_return(status: 200, body: "")
        .with do |req|
        request_body = JSON.parse(req.body)
        true
      end

      result = adapter.write(event_data)

      expect(result).to be true
      expect(request_body).to have_key("resourceLogs")
      expect(request_body["resourceLogs"].first["scopeLogs"].first["logRecords"].first).to include(
        "severityNumber" => 9,
        "body" => { "stringValue" => "order.paid" }
      )
    end

    it "includes resource attributes" do
      request_body = nil
      stub_request(:post, "#{collector_url}/v1/logs")
        .to_return(status: 200, body: "")
        .with do |req|
        request_body = JSON.parse(req.body)
        true
      end

      adapter.write(event_data)

      resource = request_body["resourceLogs"].first["resource"]
      attrs = resource["attributes"].map { |a| a["key"] }
      expect(attrs).to include("service.name", "service.version", "deployment.environment", "host.name", "process.pid")
    end

    it "maps payload to OTel attributes via SemanticConventions" do
      request_body = nil
      stub_request(:post, "#{collector_url}/v1/logs")
        .to_return(status: 200, body: "")
        .with do |req|
        request_body = JSON.parse(req.body)
        true
      end

      adapter.write(event_data)

      log_record = request_body["resourceLogs"].first["scopeLogs"].first["logRecords"].first
      attrs = log_record["attributes"].to_h { |a| [a["key"], a["value"]] }
      expect(attrs).to have_key("event.name")
      expect(attrs).to have_key("event.order_id")
    end

    it "sends gzip-compressed body when compress: true (default)" do
      compressed_adapter = E11y::Adapters::OpenTelemetryCollector.new(
        endpoint: collector_url,
        service_name: "e11y-integration-test",
        compress: true
      )

      request_received = nil
      stub_request(:post, "#{collector_url}/v1/logs")
        .to_return(status: 200, body: "")
        .with do |req|
          request_received = req
          true
        end

      compressed_adapter.write(event_data)

      expect(request_received.headers["Content-Encoding"]).to eq("gzip")
      decompressed = Zlib::GzipReader.new(StringIO.new(request_received.body)).read
      parsed = JSON.parse(decompressed)
      expect(parsed).to have_key("resourceLogs")
    end
  end
end
