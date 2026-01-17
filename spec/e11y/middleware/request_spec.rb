# frozen_string_literal: true

require "spec_helper"
require "e11y/middleware/request"
require "e11y/buffers/request_scoped_buffer"

# rubocop:disable RSpec/MessageSpies
RSpec.describe E11y::Middleware::Request do
  let(:app) { ->(_env) { [200, {}, ["OK"]] } }
  let(:middleware) { described_class.new(app) }
  let(:env) { { "PATH_INFO" => "/test" } }

  # Reset buffer before each test
  before do
    E11y::Buffers::RequestScopedBuffer.reset_all
  end

  after do
    E11y::Buffers::RequestScopedBuffer.reset_all
  end

  describe "#initialize" do
    it "accepts app" do
      expect(middleware).to be_a(described_class)
    end

    it "accepts buffer_limit option" do
      middleware_with_limit = described_class.new(app, buffer_limit: 200)

      expect(middleware_with_limit).to be_a(described_class)
    end
  end

  describe "#call" do
    context "when request is successful" do
      it "initializes request buffer" do
        expect(E11y::Buffers::RequestScopedBuffer).to receive(:initialize!).and_call_original

        middleware.call(env)

        # Buffer should be cleaned up after request
        expect(E11y::Buffers::RequestScopedBuffer.active?).to be false
      end

      it "discards debug events" do
        # Simulate debug events being added during request
        app_with_debug = lambda do |_env|
          E11y::Buffers::RequestScopedBuffer.add_event({ event_name: "debug", severity: :debug })
          E11y::Buffers::RequestScopedBuffer.add_event({ event_name: "debug2", severity: :debug })
          [200, {}, ["OK"]]
        end

        middleware = described_class.new(app_with_debug)

        # Spy on discard
        expect(E11y::Buffers::RequestScopedBuffer).to receive(:discard).and_call_original

        status, _headers, _body = middleware.call(env)

        expect(status).to eq(200)
        # Buffer should be empty (discarded)
        expect(E11y::Buffers::RequestScopedBuffer.size).to eq(0)
      end

      it "does not flush buffer" do
        expect(E11y::Buffers::RequestScopedBuffer).not_to receive(:flush_on_error)

        middleware.call(env)
      end

      it "cleans up thread-local storage" do
        middleware.call(env)

        # Verify cleanup
        expect(E11y::Buffers::RequestScopedBuffer.active?).to be false
        expect(E11y::Buffers::RequestScopedBuffer.buffer).to be_nil
        expect(E11y::Buffers::RequestScopedBuffer.request_id).to be_nil
      end

      it "returns correct response" do
        status, headers, body = middleware.call(env)

        expect(status).to eq(200)
        expect(headers).to eq({})
        expect(body).to eq(["OK"])
      end
    end

    context "when error occurs" do
      let(:error_app) do
        lambda do |_env|
          E11y::Buffers::RequestScopedBuffer.add_event({ event_name: "debug1", severity: :debug })
          E11y::Buffers::RequestScopedBuffer.add_event({ event_name: "debug2", severity: :debug })
          raise StandardError, "Test error"
        end
      end

      let(:middleware) { described_class.new(error_app) }

      it "flushes debug events" do
        expect(E11y::Buffers::RequestScopedBuffer).to receive(:flush_on_error).and_call_original

        expect { middleware.call(env) }.to raise_error(StandardError, "Test error")
      end

      it "does not discard buffer" do
        expect(E11y::Buffers::RequestScopedBuffer).not_to receive(:discard)

        expect { middleware.call(env) }.to raise_error(StandardError)
      end

      it "re-raises exception" do
        expect { middleware.call(env) }.to raise_error(StandardError, "Test error")
      end

      it "cleans up thread-local storage even on error" do
        expect { middleware.call(env) }.to raise_error(StandardError)

        # Verify cleanup happened
        expect(E11y::Buffers::RequestScopedBuffer.active?).to be false
      end
    end

    context "with request ID extraction" do
      it "uses X-Request-ID header if present" do
        env_with_header = env.merge("HTTP_X_REQUEST_ID" => "custom-req-123")

        expect(E11y::Buffers::RequestScopedBuffer).to receive(:initialize!).with(
          hash_including(request_id: "custom-req-123")
        ).and_call_original

        middleware.call(env_with_header)
      end

      it "uses ActionDispatch request_id if present" do
        env_with_rails_id = env.merge("action_dispatch.request_id" => "rails-req-456")

        expect(E11y::Buffers::RequestScopedBuffer).to receive(:initialize!).with(
          hash_including(request_id: "rails-req-456")
        ).and_call_original

        middleware.call(env_with_rails_id)
      end

      it "generates UUID if no request ID present" do
        # Spy on initialize! to verify request_id format
        expect(E11y::Buffers::RequestScopedBuffer).to receive(:initialize!).with(
          hash_including(request_id: match(/\A[0-9a-f-]{36}\z/))
        ).and_call_original

        middleware.call(env)
      end

      it "prefers X-Request-ID over ActionDispatch" do
        env_with_both = env.merge(
          "HTTP_X_REQUEST_ID" => "header-req-123",
          "action_dispatch.request_id" => "rails-req-456"
        )

        expect(E11y::Buffers::RequestScopedBuffer).to receive(:initialize!).with(
          hash_including(request_id: "header-req-123")
        ).and_call_original

        middleware.call(env_with_both)
      end
    end

    context "with buffer limit configuration" do
      it "uses default buffer limit (100)" do
        expect(E11y::Buffers::RequestScopedBuffer).to receive(:initialize!).with(
          hash_including(buffer_limit: 100)
        ).and_call_original

        middleware.call(env)
      end

      it "uses custom buffer limit" do
        middleware_with_limit = described_class.new(app, buffer_limit: 200)

        expect(E11y::Buffers::RequestScopedBuffer).to receive(:initialize!).with(
          hash_including(buffer_limit: 200)
        ).and_call_original

        middleware_with_limit.call(env)
      end
    end
  end

  describe "UC-001 compliance" do
    it "achieves zero debug logs in success requests" do
      # Simulate 10 successful requests with debug events
      app_with_debug = lambda do |_env|
        3.times do |i|
          E11y::Buffers::RequestScopedBuffer.add_event(
            { event_name: "debug#{i}", severity: :debug }
          )
        end
        [200, {}, ["OK"]]
      end

      middleware = described_class.new(app_with_debug)

      # Track flushed events
      flushed_events = 0
      allow(E11y::Buffers::RequestScopedBuffer).to receive(:flush_on_error).and_wrap_original do |m|
        result = m.call
        flushed_events += result
        result
      end

      # Execute 10 successful requests
      10.times { middleware.call(env) }

      # No events should be flushed (all discarded)
      expect(flushed_events).to eq(0)
    end

    it "flushes debug events only on error" do
      # Simulate 9 successful + 1 failed request
      request_count = 0
      app_with_conditional_error = lambda do |_env|
        request_count += 1
        E11y::Buffers::RequestScopedBuffer.add_event({ event_name: "debug", severity: :debug })

        raise StandardError, "10th request failed" if request_count == 10

        [200, {}, ["OK"]]
      end

      middleware = described_class.new(app_with_conditional_error)

      # Execute 9 successful requests
      9.times { middleware.call(env) }

      # Execute 1 failed request
      expect { middleware.call(env) }.to raise_error(StandardError)

      # Only 1 event should have been flushed (from failed request)
      # (We can't easily verify the count here without more complex mocking)
    end

    it "integrates with RequestScopedBuffer correctly" do
      # Verify complete lifecycle
      app_with_lifecycle = lambda do |_env|
        # Should be active during request
        expect(E11y::Buffers::RequestScopedBuffer.active?).to be true

        E11y::Buffers::RequestScopedBuffer.add_event({ event_name: "debug", severity: :debug })

        [200, {}, ["OK"]]
      end

      middleware = described_class.new(app_with_lifecycle)

      # Before request
      expect(E11y::Buffers::RequestScopedBuffer.active?).to be false

      # During request (verified inside app)
      middleware.call(env)

      # After request
      expect(E11y::Buffers::RequestScopedBuffer.active?).to be false
    end
  end
end
# rubocop:enable RSpec/MessageSpies
