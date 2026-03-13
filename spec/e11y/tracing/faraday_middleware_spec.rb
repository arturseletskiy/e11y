# frozen_string_literal: true

require "spec_helper"
require "faraday"
require "e11y/tracing/faraday_middleware"

RSpec.describe E11y::Tracing::FaradayMiddleware do
  before do
    skip "Faraday not available" unless defined?(::Faraday)

    E11y::Current.reset
  end

  after do
    E11y::Current.reset
  end

  # Build a minimal Faraday app that captures request headers
  let(:captured_headers) { {} }

  let(:faraday_app) do
    captured = captured_headers
    proc do |env|
      captured.merge!(env.request_headers)
      ::Faraday::Response.new(env)
    end
  end

  let(:middleware) { described_class.new(faraday_app) }

  def build_env(headers = {})
    ::Faraday::Env.from(
      method: :get,
      url: URI("http://example.com/"),
      request_headers: ::Faraday::Utils::Headers.new(headers)
    )
  end

  context "when trace context is set" do
    before do
      E11y::Current.trace_id = "0af7651916cd43dd8448eb211c80319c"
      E11y::Current.span_id  = "00f067aa0ba902b7"
    end

    it "injects traceparent into request headers" do
      env = build_env
      middleware.call(env)
      expect(captured_headers["traceparent"]).to eq("00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01")
    end

    it "preserves other request headers" do
      env = build_env("Authorization" => "Bearer token")
      middleware.call(env)
      expect(captured_headers["Authorization"]).to eq("Bearer token")
    end
  end

  context "when no trace context is set" do
    it "does not inject traceparent" do
      env = build_env
      middleware.call(env)
      expect(captured_headers["traceparent"]).to be_nil
    end
  end

  context "when traceparent is already present" do
    before do
      E11y::Current.trace_id = "0af7651916cd43dd8448eb211c80319c"
      E11y::Current.span_id  = "00f067aa0ba902b7"
    end

    it "does not override the existing traceparent" do
      existing = "00-existingtraceidddddddddddddddddd-existingspan0000-01"
      env = build_env("traceparent" => existing)
      middleware.call(env)
      expect(captured_headers["traceparent"]).to eq(existing)
    end
  end

  describe "E11y::Tracing.install_faraday_middleware!" do
    it "registers :e11y_tracing middleware with Faraday" do
      E11y::Tracing.install_faraday_middleware!
      expect(::Faraday::Request.lookup_middleware(:e11y_tracing)).to eq(described_class)
    end

    it "is idempotent — calling twice does not raise" do
      E11y::Tracing.install_faraday_middleware!
      expect { E11y::Tracing.install_faraday_middleware! }.not_to raise_error
    end
  end
end
