# frozen_string_literal: true

require "e11y/opentelemetry/semantic_conventions"

RSpec.describe E11y::OpenTelemetry::SemanticConventions do
  describe ".map_key" do
    it "maps http keys for HTTP events" do
      expect(described_class.map_key("http.request", "method")).to eq("http.method")
      expect(described_class.map_key("http.request", "status_code")).to eq("http.status_code")
      expect(described_class.map_key("request.received", "path")).to eq("http.target")
    end

    it "maps database keys for DB events" do
      expect(described_class.map_key("database.query", "query")).to eq("db.statement")
      expect(described_class.map_key("sql.executed", "operation")).to eq("db.operation")
    end

    it "maps exception keys for error events" do
      expect(described_class.map_key("error.occurred", "error_message")).to eq("exception.message")
      expect(described_class.map_key("exception.raised", "error_class")).to eq("exception.type")
    end

    it "uses event. prefix for unknown keys" do
      expect(described_class.map_key("order.paid", "order_id")).to eq("event.order_id")
      expect(described_class.map_key("http.request", "custom_key")).to eq("event.custom_key")
    end
  end

  describe ".map" do
    it "maps full payload for HTTP events" do
      payload = { "method" => "GET", "status_code" => 200, "path" => "/api" }
      result = described_class.map("http.request", payload)

      expect(result).to eq(
        "http.method" => "GET",
        "http.status_code" => 200,
        "http.target" => "/api"
      )
    end

    it "uses event. prefix for non-convention events" do
      payload = { order_id: "123", amount: 99.99 }
      result = described_class.map("order.paid", payload)

      expect(result).to eq("event.order_id" => "123", "event.amount" => 99.99)
    end

    it "handles mixed convention and custom keys" do
      payload = { "method" => "POST", "order_id" => "abc" }
      result = described_class.map("http.request", payload)

      expect(result["http.method"]).to eq("POST")
      expect(result["event.order_id"]).to eq("abc")
    end
  end

  describe ".detect_convention_type" do
    it "detects http for request/response events" do
      expect(described_class.detect_convention_type("http.request")).to eq(:http)
      expect(described_class.detect_convention_type("request.received")).to eq(:http)
    end

    it "detects database for query/sql events" do
      expect(described_class.detect_convention_type("database.query")).to eq(:database)
      expect(described_class.detect_convention_type("sql.executed")).to eq(:database)
    end

    it "detects exception for error events" do
      expect(described_class.detect_convention_type("error.occurred")).to eq(:exception)
      expect(described_class.detect_convention_type("exception.raised")).to eq(:exception)
    end

    it "returns nil for unknown event types" do
      expect(described_class.detect_convention_type("order.paid")).to be_nil
      expect(described_class.detect_convention_type("user.signup")).to be_nil
    end
  end
end
