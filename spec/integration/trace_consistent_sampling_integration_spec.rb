# frozen_string_literal: true

# Trace-consistent sampling (ADR-005 §7, F-023) integration tests.
require "rails_helper"

RSpec.describe "Trace-Consistent Sampling Integration", :integration do
  before do
    E11y.configure do |config|
      config.tracing_default_sample_rate = 0.0 # 0% for deterministic "not sampled"
      config.tracing_respect_parent_sampling = true
    end
  end

  describe "Request middleware + traceparent" do
    it "sets E11y::Current.sampled from traceparent flags" do
      app = lambda do |_env|
        [200, {}, [E11y::Current.sampled.inspect]]
      end
      middleware = E11y::Middleware::Request.new(app)

      # traceparent with flags 00 = not sampled
      env = Rack::MockRequest.env_for(
        "/",
        "HTTP_TRACEPARENT" => "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-00"
      )
      _status, _headers, body = middleware.call(env)
      expect(body.join).to eq("false")
    end

    it "sets E11y::Current.sampled true when traceparent has flags 01" do
      app = lambda do |_env|
        [200, {}, [E11y::Current.sampled.inspect]]
      end
      middleware = E11y::Middleware::Request.new(app)

      env = Rack::MockRequest.env_for(
        "/",
        "HTTP_TRACEPARENT" => "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01"
      )
      _status, _headers, body = middleware.call(env)
      expect(body.join).to eq("true")
    end
  end

  describe "Propagator uses E11y::Current.sampled" do
    it "builds traceparent with flags 00 when sampled is false" do
      E11y::Current.trace_id = "abc123def456"
      E11y::Current.span_id = "span789"
      E11y::Current.sampled = false

      result = E11y::Tracing::Propagator.build_traceparent
      expect(result).to end_with("-00")
    ensure
      E11y::Current.reset
    end

    it "builds traceparent with flags 01 when sampled is true" do
      E11y::Current.trace_id = "abc123def456"
      E11y::Current.span_id = "span789"
      E11y::Current.sampled = true

      result = E11y::Tracing::Propagator.build_traceparent
      expect(result).to end_with("-01")
    ensure
      E11y::Current.reset
    end
  end

  describe "Sampling middleware prefers E11y::Current.sampled" do
    it "drops events when Current.sampled is false and trace_aware" do
      E11y::Current.trace_id = "trace123"
      E11y::Current.span_id = "span456"
      E11y::Current.sampled = false

      app = ->(ed) { ed }
      sampling = E11y::Middleware::Sampling.new(
        app,
        default_sample_rate: 1.0,
        trace_aware: true
      )

      event_data = {
        event_name: "test.event",
        event_class: Class.new(E11y::Event::Base),
        trace_id: "trace123",
        payload: {}
      }
      result = sampling.call(event_data)
      expect(result).to be_nil
    ensure
      E11y::Current.reset
    end

    it "passes events when Current.sampled is true and trace_aware" do
      E11y::Current.trace_id = "trace123"
      E11y::Current.span_id = "span456"
      E11y::Current.sampled = true

      app = ->(ed) { ed }
      sampling = E11y::Middleware::Sampling.new(
        app,
        default_sample_rate: 0.0,
        trace_aware: true
      )

      event_data = {
        event_name: "test.event",
        event_class: Class.new(E11y::Event::Base),
        trace_id: "trace123",
        payload: {}
      }
      result = sampling.call(event_data)
      expect(result).not_to be_nil
      expect(result[:sampled]).to be true
    ensure
      E11y::Current.reset
    end
  end

  describe "always_sample_if proc" do
    it "always samples when proc returns true (request_path)" do
      E11y.configure do |config|
        config.tracing_default_sample_rate = 0.0
        config.tracing_always_sample_if = ->(ctx) { ctx[:request_path]&.include?("admin") }
      end

      app = lambda do |_env|
        [200, {}, [E11y::Current.sampled.inspect]]
      end
      middleware = E11y::Middleware::Request.new(app)

      env = Rack::MockRequest.env_for("/admin/users")
      _status, _headers, body = middleware.call(env)
      expect(body.join).to eq("true")
    end

    it "does not sample when proc returns false" do
      E11y.configure do |config|
        config.tracing_default_sample_rate = 0.0
        config.tracing_always_sample_if = ->(ctx) { ctx[:request_path]&.include?("admin") }
      end

      app = lambda do |_env|
        [200, {}, [E11y::Current.sampled.inspect]]
      end
      middleware = E11y::Middleware::Request.new(app)

      env = Rack::MockRequest.env_for("/api/users")
      _status, _headers, body = middleware.call(env)
      expect(body.join).to eq("false")
    end
  end

  describe "Sidekiq propagates e11y_sampled" do
    it "injects e11y_sampled into job metadata" do
      E11y::Current.trace_id = "trace_abc"
      E11y::Current.span_id = "span_xyz"
      E11y::Current.sampled = true

      job = {}
      E11y::Instruments::Sidekiq::ClientMiddleware.new.call("TestWorker", job, "default", nil) { nil }

      expect(job["e11y_sampled"]).to be true
    ensure
      E11y::Current.reset
    end

    it "restores E11y::Current.sampled from job metadata in server" do
      job = {
        "e11y_parent_trace_id" => "parent123",
        "e11y_sampled" => false,
        "jid" => "job456"
      }

      captured_sampled = nil
      E11y::Instruments::Sidekiq::ServerMiddleware.new.call(nil, job, "default") do
        captured_sampled = E11y::Current.sampled
      end
      expect(captured_sampled).to be false
    end
  end
end
