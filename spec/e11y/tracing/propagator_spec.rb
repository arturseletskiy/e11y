# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Tracing::Propagator do
  before do
    E11y::Current.reset
  end

  after do
    E11y::Current.reset
  end

  describe ".build_traceparent" do
    context "when E11y::Current has trace_id set" do
      before do
        E11y::Current.trace_id = "0af7651916cd43dd8448eb211c80319c"
        E11y::Current.span_id  = "00f067aa0ba902b7"
      end

      it "returns a valid W3C traceparent string" do
        result = described_class.build_traceparent
        expect(result).to eq("00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01")
      end

      it "uses version 00" do
        expect(described_class.build_traceparent).to start_with("00-")
      end

      it "uses sampled flag 01" do
        expect(described_class.build_traceparent).to end_with("-01")
      end
    end

    context "when explicit trace_id and span_id are provided" do
      it "uses the provided ids instead of Current" do
        result = described_class.build_traceparent(
          trace_id: "aabbccddee001122334455667788aabb",
          span_id: "1122334455667788"
        )
        expect(result).to eq("00-aabbccddee001122334455667788aabb-1122334455667788-01")
      end

      it "ignores E11y::Current when explicit ids are given" do
        E11y::Current.trace_id = "ffffffffffffffffffffffffffffffff"
        result = described_class.build_traceparent(
          trace_id: "aabbccddee001122334455667788aabb",
          span_id: "deadbeefcafebabe"
        )
        expect(result).to start_with("00-aabbccddee001122334455667788aabb-")
      end
    end

    context "when no trace_id is available" do
      it "returns nil" do
        expect(described_class.build_traceparent).to be_nil
      end
    end

    context "when trace_id is empty string" do
      before { E11y::Current.trace_id = "" }

      it "returns nil" do
        expect(described_class.build_traceparent).to be_nil
      end
    end

    context "when trace_id is present but span_id is nil" do
      before do
        E11y::Current.trace_id = "0af7651916cd43dd8448eb211c80319c"
        E11y::Current.span_id  = nil
      end

      it "generates a random span_id" do
        result = described_class.build_traceparent
        expect(result).not_to be_nil
        parts = result.split("-")
        expect(parts[2].length).to eq(16)
      end
    end

    context "when trace_id is present but span_id is empty" do
      before do
        E11y::Current.trace_id = "0af7651916cd43dd8448eb211c80319c"
        E11y::Current.span_id  = ""
      end

      it "generates a random span_id" do
        result = described_class.build_traceparent
        parts = result.split("-")
        expect(parts[2]).not_to be_empty
        expect(parts[2].length).to eq(16)
      end
    end
  end

  describe ".inject" do
    context "when trace context is available" do
      before do
        E11y::Current.trace_id = "0af7651916cd43dd8448eb211c80319c"
        E11y::Current.span_id  = "00f067aa0ba902b7"
      end

      it "adds traceparent header to headers hash" do
        headers = {}
        described_class.inject(headers)
        expect(headers["traceparent"]).to eq("00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01")
      end

      it "returns the mutated headers hash" do
        headers = { "Content-Type" => "application/json" }
        result = described_class.inject(headers)
        expect(result).to be(headers)
      end

      it "preserves existing headers" do
        headers = { "Authorization" => "Bearer token" }
        described_class.inject(headers)
        expect(headers["Authorization"]).to eq("Bearer token")
        expect(headers["traceparent"]).not_to be_nil
      end
    end

    context "when traceparent is already set" do
      before do
        E11y::Current.trace_id = "0af7651916cd43dd8448eb211c80319c"
        E11y::Current.span_id  = "00f067aa0ba902b7"
      end

      it "does not override the existing traceparent" do
        existing = "00-existingtraceid000000000000000000-existingspanid0-01"
        headers = { "traceparent" => existing }
        described_class.inject(headers)
        expect(headers["traceparent"]).to eq(existing)
      end
    end

    context "when baggage is present (F-014)" do
      before do
        E11y::Current.trace_id = "0af7651916cd43dd8448eb211c80319c"
        E11y::Current.span_id  = "00f067aa0ba902b7"
        E11y::Current.baggage = { "experiment" => "exp-42", "tenant" => "acme" }
      end

      it "adds tracestate header with baggage" do
        headers = {}
        described_class.inject(headers)
        expect(headers["tracestate"]).to eq("experiment=exp-42,tenant=acme")
      end

      it "does not override existing tracestate" do
        headers = { "tracestate" => "existing=value" }
        described_class.inject(headers)
        expect(headers["tracestate"]).to eq("existing=value")
      end
    end

    context "when no trace context is available" do
      it "returns headers unchanged" do
        headers = { "Accept" => "application/json" }
        result = described_class.inject(headers)
        expect(result).to eq("Accept" => "application/json")
        expect(result["traceparent"]).to be_nil
      end
    end
  end

  describe ".parse" do
    it "parses a valid W3C traceparent header" do
      result = described_class.parse("00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01")
      expect(result).to eq(
        trace_id: "0af7651916cd43dd8448eb211c80319c",
        parent_span_id: "00f067aa0ba902b7",
        sampled: true
      )
    end

    it "returns sampled: false when flags are not 01" do
      result = described_class.parse("00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-00")
      expect(result[:sampled]).to be false
    end

    it "returns nil for nil input" do
      expect(described_class.parse(nil)).to be_nil
    end

    it "returns nil for empty string" do
      expect(described_class.parse("")).to be_nil
    end

    it "returns nil when format has wrong number of parts" do
      expect(described_class.parse("00-traceid-spanid")).to be_nil
      expect(described_class.parse("00-traceid-spanid-01-extra")).to be_nil
    end

    it "returns nil when trace_id part is empty" do
      expect(described_class.parse("00--00f067aa0ba902b7-01")).to be_nil
    end

    it "returns nil for non-string input" do
      expect(described_class.parse(12_345)).to be_nil
      expect(described_class.parse(:symbol)).to be_nil
    end

    it "includes trace_id in parsed result" do
      result = described_class.parse("00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01")
      expect(result[:trace_id]).to eq("0af7651916cd43dd8448eb211c80319c")
    end

    it "includes parent_span_id in parsed result" do
      result = described_class.parse("00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01")
      expect(result[:parent_span_id]).to eq("00f067aa0ba902b7")
    end
  end

  describe ".parse_tracestate" do
    it "parses key=value pairs" do
      result = described_class.parse_tracestate("experiment=exp-42,tenant=acme")
      expect(result).to eq("experiment" => "exp-42", "tenant" => "acme")
    end

    it "returns empty hash for nil" do
      expect(described_class.parse_tracestate(nil)).to eq({})
    end

    it "returns empty hash for empty string" do
      expect(described_class.parse_tracestate("")).to eq({})
    end

    it "handles single entry" do
      expect(described_class.parse_tracestate("key=value")).to eq("key" => "value")
    end
  end

  describe ".build_tracestate" do
    it "builds key=value string from hash" do
      result = described_class.build_tracestate("experiment" => "exp-42", "tenant" => "acme")
      expect(result).to eq("experiment=exp-42,tenant=acme")
    end

    it "returns empty string for empty hash" do
      expect(described_class.build_tracestate({})).to eq("")
    end

    it "returns empty string for nil" do
      expect(described_class.build_tracestate(nil)).to eq("")
    end
  end

  describe ".baggage_for_propagation_from_current" do
    it "includes user_id from Current.user_id" do
      E11y::Current.user_id = 42
      expect(described_class.baggage_for_propagation_from_current).to eq("user_id" => "42")
    end

    it "merges Current.baggage with user_id" do
      E11y::Current.baggage = { "experiment" => "exp-1" }
      E11y::Current.user_id = 7
      expect(described_class.baggage_for_propagation_from_current).to eq(
        "experiment" => "exp-1",
        "user_id" => "7"
      )
    end
  end

  describe ".hydrate_current_from_job_baggage!" do
    it "sets baggage and user_id on Current" do
      described_class.hydrate_current_from_job_baggage!("user_id" => "12", "experiment" => "e")
      expect(E11y::Current.baggage).to eq("user_id" => "12", "experiment" => "e")
      expect(E11y::Current.user_id).to eq("12")
    end
  end

  describe ".filter_baggage_for_propagation" do
    it "filters to allowed keys only when baggage_protection enabled" do
      E11y::Current.baggage = { "experiment" => "exp-42", "user_email" => "user@example.com" }

      cfg = instance_double(E11y::Configuration)
      allow(cfg).to receive(:filter_baggage_for_propagation).and_return("experiment" => "exp-42")
      allow(E11y).to receive(:config).and_return(cfg)

      result = described_class.filter_baggage_for_propagation(E11y::Current.baggage)
      expect(result).to eq("experiment" => "exp-42")
    end

    it "returns full hash when config is nil" do
      allow(E11y).to receive(:config).and_return(nil)
      hash = { "user_email" => "x" }
      expect(described_class.filter_baggage_for_propagation(hash)).to eq(hash)
    end
  end
end
