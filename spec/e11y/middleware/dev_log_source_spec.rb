# frozen_string_literal: true

require "spec_helper"
require "rack/mock_request"

RSpec.describe E11y::Middleware::DevLogSource do
  let(:captured_source) { [] }
  let(:inner_app) do
    lambda do |_env|
      captured_source << Thread.current[:e11y_source]
      [200, { "Content-Type" => "text/html" }, ["OK"]]
    end
  end

  subject(:middleware) { described_class.new(inner_app) }

  def env_for(path = "/")
    Rack::MockRequest.env_for(path)
  end

  describe "#call" do
    it "sets Thread.current[:e11y_source] to 'web' during the request" do
      middleware.call(env_for)
      expect(captured_source).to eq(["web"])
    end

    it "clears Thread.current[:e11y_source] after the request" do
      middleware.call(env_for)
      expect(Thread.current[:e11y_source]).to be_nil
    end

    it "clears Thread.current[:e11y_source] even when the app raises" do
      raising_app = ->(_env) { raise "boom" }
      mw = described_class.new(raising_app)
      expect { mw.call(env_for) }.to raise_error("boom")
      expect(Thread.current[:e11y_source]).to be_nil
    end

    it "passes env['e11y.trace_id'] from Thread.current[:e11y_trace_id]" do
      Thread.current[:e11y_trace_id] = "trace-abc"
      captured_env = []
      tracing_app  = ->(e) { captured_env << e; [200, {}, ["OK"]] }
      described_class.new(tracing_app).call(env_for)
      expect(captured_env.first["e11y.trace_id"]).to eq("trace-abc")
    ensure
      Thread.current[:e11y_trace_id] = nil
    end

    it "returns the response from the inner app unchanged" do
      status, headers, body = middleware.call(env_for)
      expect(status).to eq(200)
      expect(body).to eq(["OK"])
    end
  end
end
