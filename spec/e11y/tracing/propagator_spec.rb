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
end
