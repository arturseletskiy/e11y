# frozen_string_literal: true

require "spec_helper"
require "rack/mock"

RSpec.describe E11y::Middleware::DevLogSource do
  subject(:middleware) { described_class.new(inner_app) }

  let(:captured_source) { [] }
  let(:inner_app) do
    lambda do |_env|
      captured_source << Thread.current[:e11y_source]
      [200, { "Content-Type" => "text/html" }, ["OK"]]
    end
  end

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
      tracing_app  = lambda { |e|
        captured_env << e
        [200, {}, ["OK"]]
      }
      described_class.new(tracing_app).call(env_for)
      expect(captured_env.first["e11y.trace_id"]).to eq("trace-abc")
    ensure
      Thread.current[:e11y_trace_id] = nil
    end

    it "returns the response from the inner app unchanged" do
      status, _, body = middleware.call(env_for)
      expect(status).to eq(200)
      expect(body).to eq(["OK"])
    end

    it "sets http_method on Thread.current before calling inner app" do
      seen_method = nil
      app_with_spy = lambda do |_e|
        seen_method = Thread.current[:e11y_http_method]
        [200, {}, []]
      end
      described_class.new(app_with_spy).call(Rack::MockRequest.env_for("/users?page=2", method: "GET"))
      expect(seen_method).to eq("GET")
    end

    it "sets http_path from PATH_INFO before calling inner app" do
      seen_path = nil
      app_with_spy = lambda do |_e|
        seen_path = Thread.current[:e11y_http_path]
        [200, {}, []]
      end
      described_class.new(app_with_spy).call(Rack::MockRequest.env_for("/users?page=2", method: "GET"))
      expect(seen_path).to eq("/users")
    end

    it "clears all http Thread.current keys after call" do
      middleware.call(env_for)
      expect(Thread.current[:e11y_http_method]).to be_nil
      expect(Thread.current[:e11y_http_path]).to be_nil
      expect(Thread.current[:e11y_http_status]).to be_nil
      expect(Thread.current[:e11y_http_duration_ms]).to be_nil
      expect(Thread.current[:e11y_source]).to be_nil
    end

    it "clears Thread.current keys even when app raises" do
      raising_app = ->(_e) { raise "boom" }
      expect { described_class.new(raising_app).call(env_for) }.to raise_error("boom")
      expect(Thread.current[:e11y_http_method]).to be_nil
      expect(Thread.current[:e11y_http_status]).to be_nil
      expect(Thread.current[:e11y_http_duration_ms]).to be_nil
    end

    it "does not raise when inner app responds normally" do
      expect { middleware.call(env_for) }.not_to raise_error
    end
  end
end
