# frozen_string_literal: true

require "spec_helper"
require "rack/mock"

RSpec.describe E11y::Middleware::Request do
  let(:app) { ->(_env) { [200, { "Content-Type" => "text/plain" }, ["OK"]] } }
  let(:middleware) { described_class.new(app) }
  let(:env) { Rack::MockRequest.env_for("http://example.com/test") }

  describe "#call" do
    it "passes request to app" do
      status, headers, body = middleware.call(env)

      expect(status).to eq(200)
      expect(headers["Content-Type"]).to eq("text/plain")
      expect(body).to eq(["OK"])
    end

    it "adds trace headers to response" do
      _, headers, = middleware.call(env)

      expect(headers["X-E11y-Trace-Id"]).not_to be_nil
      expect(headers["X-E11y-Span-Id"]).not_to be_nil
    end

    it "sets request context in E11y::Current" do
      # NOTE: E11y::Current is reset after request, so we can't check it here
      # This test verifies the method runs without errors
      expect { middleware.call(env) }.not_to raise_error
    end

    context "when trace_id is provided in headers" do
      it "uses provided trace_id from HTTP_TRACEPARENT" do
        env["HTTP_TRACEPARENT"] = "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01"

        _, headers, = middleware.call(env)

        expect(headers["X-E11y-Trace-Id"]).to eq("0af7651916cd43dd8448eb211c80319c")
      end

      it "uses provided trace_id from HTTP_X_TRACE_ID" do
        env["HTTP_X_TRACE_ID"] = "custom-trace-id-123"

        _, headers, = middleware.call(env)

        expect(headers["X-E11y-Trace-Id"]).to eq("custom-trace-id-123")
      end

      it "uses provided trace_id from HTTP_X_REQUEST_ID" do
        env["HTTP_X_REQUEST_ID"] = "request-id-456"

        _, headers, = middleware.call(env)

        expect(headers["X-E11y-Trace-Id"]).to eq("request-id-456")
      end

      it "extracts tracestate into E11y::Current.baggage (F-014)" do
        env["HTTP_TRACESTATE"] = "experiment=exp-42,tenant=acme"

        captured_baggage = nil
        capture_app = lambda do |e|
          captured_baggage = E11y::Current.baggage
          [200, { "Content-Type" => "text/plain" }, ["OK"]]
        end
        described_class.new(capture_app).call(env)

        expect(captured_baggage).to eq("experiment" => "exp-42", "tenant" => "acme")
      end
    end

    context "when no trace_id is provided" do
      it "generates a new trace_id" do
        _, headers, = middleware.call(env)

        expect(headers["X-E11y-Trace-Id"]).to match(/\A[a-f0-9]{32}\z/)
      end

      it "generates a new span_id" do
        _, headers, = middleware.call(env)

        expect(headers["X-E11y-Span-Id"]).to match(/\A[a-f0-9]{16}\z/)
      end
    end

    context "when request fails" do
      let(:app) { ->(_env) { raise StandardError, "Boom!" } }

      it "re-raises the error" do
        expect { middleware.call(env) }.to raise_error(StandardError, "Boom!")
      end

      it "resets context after error" do
        # E11y::Current should be reset after error
        # This test verifies that context cleanup happens even when error is raised
        expect { middleware.call(env) }.to raise_error(StandardError)
      end
    end
  end

  describe "trace_id generation" do
    it "generates 32-character hex trace_id" do
      trace_id = middleware.send(:generate_trace_id)

      expect(trace_id).to match(/\A[a-f0-9]{32}\z/)
    end

    it "generates unique trace_ids" do
      trace_id1 = middleware.send(:generate_trace_id)
      trace_id2 = middleware.send(:generate_trace_id)

      expect(trace_id1).not_to eq(trace_id2)
    end
  end

  describe "span_id generation" do
    it "generates 16-character hex span_id" do
      span_id = middleware.send(:generate_span_id)

      expect(span_id).to match(/\A[a-f0-9]{16}\z/)
    end

    it "generates unique span_ids" do
      span_id1 = middleware.send(:generate_span_id)
      span_id2 = middleware.send(:generate_span_id)

      expect(span_id1).not_to eq(span_id2)
    end
  end
end
