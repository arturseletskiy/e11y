# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Current do
  # Clean up after each test to ensure isolation
  after do
    described_class.reset
  end

  describe "attribute assignment and retrieval" do
    context "with trace_id" do
      it "can be set and retrieved" do
        described_class.trace_id = "abc123"
        expect(described_class.trace_id).to eq("abc123")
      end

      it "handles nil values correctly" do
        described_class.trace_id = nil
        expect(described_class.trace_id).to be_nil
      end

      it "handles string values" do
        described_class.trace_id = "trace-123-456-789"
        expect(described_class.trace_id).to eq("trace-123-456-789")
      end
    end

    context "with span_id" do
      it "can be set and retrieved" do
        described_class.span_id = "span-456"
        expect(described_class.span_id).to eq("span-456")
      end

      it "handles nil values correctly" do
        described_class.span_id = nil
        expect(described_class.span_id).to be_nil
      end
    end

    context "with parent_trace_id" do
      it "can be set and retrieved" do
        described_class.parent_trace_id = "parent-789"
        expect(described_class.parent_trace_id).to eq("parent-789")
      end

      it "handles nil values correctly" do
        described_class.parent_trace_id = nil
        expect(described_class.parent_trace_id).to be_nil
      end

      it "allows linking background jobs to parent requests" do
        # Simulate HTTP request setting trace_id
        request_trace = "http-request-123"
        described_class.trace_id = request_trace

        # Simulate background job with new trace but parent link
        job_trace = "background-job-456"
        described_class.trace_id = job_trace
        described_class.parent_trace_id = request_trace

        expect(described_class.trace_id).to eq(job_trace)
        expect(described_class.parent_trace_id).to eq(request_trace)
      end
    end

    context "with request_id" do
      it "can be set and retrieved" do
        described_class.request_id = "req-123"
        expect(described_class.request_id).to eq("req-123")
      end

      it "handles nil values correctly" do
        described_class.request_id = nil
        expect(described_class.request_id).to be_nil
      end
    end

    context "with user_id" do
      it "can be set and retrieved" do
        described_class.user_id = 42
        expect(described_class.user_id).to eq(42)
      end

      it "handles nil values correctly" do
        described_class.user_id = nil
        expect(described_class.user_id).to be_nil
      end

      it "handles integer user IDs" do
        described_class.user_id = 12_345
        expect(described_class.user_id).to eq(12_345)
      end

      it "handles string user IDs" do
        described_class.user_id = "user-uuid-123"
        expect(described_class.user_id).to eq("user-uuid-123")
      end
    end

    context "with ip_address" do
      it "can be set and retrieved" do
        described_class.ip_address = "192.168.1.1"
        expect(described_class.ip_address).to eq("192.168.1.1")
      end

      it "handles nil values correctly" do
        described_class.ip_address = nil
        expect(described_class.ip_address).to be_nil
      end

      it "handles IPv4 addresses" do
        described_class.ip_address = "10.0.0.1"
        expect(described_class.ip_address).to eq("10.0.0.1")
      end

      it "handles IPv6 addresses" do
        described_class.ip_address = "2001:0db8:85a3:0000:0000:8a2e:0370:7334"
        expect(described_class.ip_address).to eq("2001:0db8:85a3:0000:0000:8a2e:0370:7334")
      end
    end

    context "with user_agent" do
      it "can be set and retrieved" do
        described_class.user_agent = "Mozilla/5.0"
        expect(described_class.user_agent).to eq("Mozilla/5.0")
      end

      it "handles nil values correctly" do
        described_class.user_agent = nil
        expect(described_class.user_agent).to be_nil
      end

      it "handles complex user agent strings" do
        ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        described_class.user_agent = ua
        expect(described_class.user_agent).to eq(ua)
      end
    end

    context "with request_method" do
      it "can be set and retrieved" do
        described_class.request_method = "GET"
        expect(described_class.request_method).to eq("GET")
      end

      it "handles nil values correctly" do
        described_class.request_method = nil
        expect(described_class.request_method).to be_nil
      end

      it "handles various HTTP methods" do
        %w[GET POST PUT PATCH DELETE HEAD OPTIONS].each do |method|
          described_class.request_method = method
          expect(described_class.request_method).to eq(method)
        end
      end
    end

    context "with baggage" do
      it "can be set and retrieved" do
        described_class.baggage = { "experiment" => "exp-42" }
        expect(described_class.baggage).to eq("experiment" => "exp-42")
      end

      it "handles nil values correctly" do
        described_class.baggage = nil
        expect(described_class.baggage).to be_nil
      end

      it "add_baggage merges and converts to string" do
        described_class.add_baggage(:experiment_id, "exp-42")
        described_class.add_baggage("tenant", "acme")
        expect(described_class.baggage).to eq("experiment_id" => "exp-42", "tenant" => "acme")
      end

      it "get_baggage returns value by key" do
        described_class.baggage = { "experiment" => "exp-42" }
        expect(described_class.get_baggage("experiment")).to eq("exp-42")
        expect(described_class.get_baggage(:experiment)).to eq("exp-42")
        expect(described_class.get_baggage("missing")).to be_nil
      end

      context "when baggage_protection enabled (ADR-006 §5.5)" do
        let(:config_double) do
          instance_double(
            E11y::Configuration,
            security_baggage_protection_enabled: true,
            security_baggage_protection_allowed_keys: %w[trace_id experiment tenant],
            security_baggage_protection_block_mode: :silent
          )
        end

        before do
          allow(E11y).to receive(:config).and_return(config_double)
        end

        it "blocks disallowed keys (user_email) in silent mode" do
          described_class.add_baggage("user_email", "user@example.com")
          expect(described_class.baggage).to be_nil
        end

        it "allows allowed keys" do
          described_class.add_baggage("experiment", "exp-42")
          expect(described_class.baggage).to eq("experiment" => "exp-42")
        end

        it "raises when block_mode is :raise" do
          allow(config_double).to receive(:security_baggage_protection_block_mode).and_return(:raise)
          expect { described_class.add_baggage("user_email", "x") }.to raise_error(
            E11y::BaggagePiiError,
            /Blocked PII from E11y baggage/
          )
        end

        it "warns when block_mode is :warn" do
          allow(config_double).to receive(:security_baggage_protection_block_mode).and_return(:warn)
          expect(E11y.logger).to receive(:warn).with(/Blocked PII from E11y baggage.*user_email/)
          described_class.add_baggage("user_email", "x")
          expect(described_class.baggage).to be_nil
        end
      end

      context "when baggage_protection disabled" do
        before do
          config_double = instance_double(E11y::Configuration, security_baggage_protection_enabled: false)
          allow(E11y).to receive(:config).and_return(config_double)
        end

        it "allows any key" do
          described_class.add_baggage("user_email", "user@example.com")
          expect(described_class.baggage).to eq("user_email" => "user@example.com")
        end
      end
    end

    context "with request_path" do
      it "can be set and retrieved" do
        described_class.request_path = "/api/v1/users"
        expect(described_class.request_path).to eq("/api/v1/users")
      end

      it "handles nil values correctly" do
        described_class.request_path = nil
        expect(described_class.request_path).to be_nil
      end

      it "handles complex paths with query params" do
        path = "/api/v1/users?page=1&per_page=20"
        described_class.request_path = path
        expect(described_class.request_path).to eq(path)
      end

      it "handles root path" do
        described_class.request_path = "/"
        expect(described_class.request_path).to eq("/")
      end
    end

    context "with multiple attributes set simultaneously" do
      it "maintains all values independently" do
        described_class.trace_id = "trace-123"
        described_class.span_id = "span-456"
        described_class.parent_trace_id = "parent-789"
        described_class.request_id = "req-abc"
        described_class.user_id = 42
        described_class.ip_address = "192.168.1.1"
        described_class.user_agent = "Mozilla/5.0"
        described_class.request_method = "POST"
        described_class.request_path = "/api/users"

        expect(described_class.trace_id).to eq("trace-123")
        expect(described_class.span_id).to eq("span-456")
        expect(described_class.parent_trace_id).to eq("parent-789")
        expect(described_class.request_id).to eq("req-abc")
        expect(described_class.user_id).to eq(42)
        expect(described_class.ip_address).to eq("192.168.1.1")
        expect(described_class.user_agent).to eq("Mozilla/5.0")
        expect(described_class.request_method).to eq("POST")
        expect(described_class.request_path).to eq("/api/users")
      end

      it "allows overwriting individual attributes" do
        described_class.trace_id = "old-trace"
        described_class.user_id = 1

        # Overwrite trace_id while keeping user_id
        described_class.trace_id = "new-trace"

        expect(described_class.trace_id).to eq("new-trace")
        expect(described_class.user_id).to eq(1)
      end
    end

    context "with default values" do
      it "returns nil for unset attributes" do
        expect(described_class.trace_id).to be_nil
        expect(described_class.span_id).to be_nil
        expect(described_class.parent_trace_id).to be_nil
        expect(described_class.request_id).to be_nil
        expect(described_class.user_id).to be_nil
        expect(described_class.ip_address).to be_nil
        expect(described_class.user_agent).to be_nil
        expect(described_class.request_method).to be_nil
        expect(described_class.request_path).to be_nil
      end
    end
  end

  describe ".to_context" do
    it "returns hash of set attributes with symbol keys" do
      described_class.trace_id = "trace-123"
      described_class.span_id = "span-456"
      described_class.user_id = 42
      described_class.request_path = "/admin"

      ctx = described_class.to_context
      expect(ctx).to eq(
        trace_id: "trace-123",
        span_id: "span-456",
        user_id: 42,
        request_path: "/admin"
      )
    end

    it "omits nil values (compact)" do
      described_class.trace_id = "trace-123"
      # user_id, request_path, etc. unset

      ctx = described_class.to_context
      expect(ctx).to have_key(:trace_id)
      expect(ctx).not_to have_key(:user_id)
    end

    it "includes baggage when set" do
      described_class.trace_id = "trace-123"
      described_class.baggage = { "experiment" => "exp-42" }
      ctx = described_class.to_context
      expect(ctx[:baggage]).to eq("experiment" => "exp-42")
    end
  end

  describe "hybrid tracing scenarios" do
    context "when in HTTP request scenario" do
      it "sets trace_id without parent_trace_id" do
        described_class.trace_id = "http-trace-123"
        described_class.user_id = 42

        expect(described_class.trace_id).to eq("http-trace-123")
        expect(described_class.parent_trace_id).to be_nil
        expect(described_class.user_id).to eq(42)
      end
    end

    context "when in background job scenario" do
      it "sets trace_id with parent_trace_id linking to enqueuing request" do
        # Simulate enqueuing request context
        enqueuing_trace = "http-request-abc"
        described_class.trace_id = enqueuing_trace

        # Capture parent trace before job starts
        parent_trace = described_class.trace_id

        # Simulate job execution with new trace
        described_class.trace_id = "background-job-xyz"
        described_class.parent_trace_id = parent_trace

        expect(described_class.trace_id).to eq("background-job-xyz")
        expect(described_class.parent_trace_id).to eq("http-request-abc")
      end
    end
  end

  describe "#reset" do
    it "clears all attribute values" do
      # Set all attributes
      described_class.trace_id = "trace-123"
      described_class.span_id = "span-456"
      described_class.parent_trace_id = "parent-789"
      described_class.request_id = "req-abc"
      described_class.user_id = 42
      described_class.ip_address = "192.168.1.1"
      described_class.user_agent = "Mozilla/5.0"
      described_class.request_method = "POST"
      described_class.request_path = "/api/users"

      # Reset
      described_class.reset

      # Verify all attributes are nil
      expect(described_class.trace_id).to be_nil
      expect(described_class.span_id).to be_nil
      expect(described_class.parent_trace_id).to be_nil
      expect(described_class.request_id).to be_nil
      expect(described_class.user_id).to be_nil
      expect(described_class.baggage).to be_nil
      expect(described_class.ip_address).to be_nil
      expect(described_class.user_agent).to be_nil
      expect(described_class.request_method).to be_nil
      expect(described_class.request_path).to be_nil
    end

    it "can be called multiple times safely" do
      described_class.trace_id = "trace-123"
      described_class.reset
      described_class.reset # Second reset should not raise

      expect(described_class.trace_id).to be_nil
    end

    it "allows setting new values after reset" do
      described_class.trace_id = "old-trace"
      described_class.user_id = 1

      described_class.reset

      described_class.trace_id = "new-trace"
      described_class.user_id = 2

      expect(described_class.trace_id).to eq("new-trace")
      expect(described_class.user_id).to eq(2)
    end

    it "resets to nil, not to some default value" do
      described_class.trace_id = "some-value"
      described_class.reset

      # Should be nil, not empty string or anything else
      expect(described_class.trace_id).to be_nil
      expect(described_class.trace_id).not_to eq("")
    end
  end

  describe "thread isolation" do
    it "maintains separate contexts for different threads" do
      # Set values in main thread
      described_class.trace_id = "main-thread-trace"
      described_class.user_id = 1

      # Create a thread that sets different values
      thread_values = {}
      thread = Thread.new do
        described_class.trace_id = "child-thread-trace"
        described_class.user_id = 2
        thread_values[:trace_id] = described_class.trace_id
        thread_values[:user_id] = described_class.user_id
      end
      thread.join

      # Main thread values should be unchanged
      expect(described_class.trace_id).to eq("main-thread-trace")
      expect(described_class.user_id).to eq(1)

      # Child thread had its own values
      expect(thread_values[:trace_id]).to eq("child-thread-trace")
      expect(thread_values[:user_id]).to eq(2)
    end

    it "does not contaminate parent thread from child thread" do
      # Main thread initially has no values
      expect(described_class.trace_id).to be_nil

      # Child thread sets values
      thread = Thread.new do
        described_class.trace_id = "child-trace"
        described_class.user_id = 99
      end
      thread.join

      # Main thread should still have no values
      expect(described_class.trace_id).to be_nil
      expect(described_class.user_id).to be_nil
    end

    it "does not contaminate child thread from parent thread" do
      # Parent thread sets values
      described_class.trace_id = "parent-trace"
      described_class.user_id = 1

      # Child thread should start with nil values
      thread_values = {}
      thread = Thread.new do
        thread_values[:trace_id] = described_class.trace_id
        thread_values[:user_id] = described_class.user_id
      end
      thread.join

      expect(thread_values[:trace_id]).to be_nil
      expect(thread_values[:user_id]).to be_nil
    end

    it "allows multiple threads with independent contexts" do
      results = {}

      threads = Array.new(3) do |i|
        Thread.new do
          trace_id = "thread-#{i}-trace"
          user_id = i * 10

          described_class.trace_id = trace_id
          described_class.user_id = user_id

          # Simulate some work
          sleep 0.001

          # Read values back
          results[i] = {
            trace_id: described_class.trace_id,
            user_id: described_class.user_id
          }
        end
      end

      threads.each(&:join)

      # Each thread should have its own values
      expect(results[0]).to eq({ trace_id: "thread-0-trace", user_id: 0 })
      expect(results[1]).to eq({ trace_id: "thread-1-trace", user_id: 10 })
      expect(results[2]).to eq({ trace_id: "thread-2-trace", user_id: 20 })
    end

    it "maintains isolation after reset in child thread" do
      # Parent sets values
      described_class.trace_id = "parent-trace"

      thread = Thread.new do
        described_class.trace_id = "child-trace"
        described_class.reset
        # After reset in child thread, child should have nil
        expect(described_class.trace_id).to be_nil
      end
      thread.join

      # Parent should still have its value
      expect(described_class.trace_id).to eq("parent-trace")
    end

    it "supports nested thread creation with independent contexts" do
      described_class.trace_id = "main-trace"

      outer_trace = nil
      inner_trace = nil

      outer_thread = Thread.new do
        described_class.trace_id = "outer-trace"
        outer_trace = described_class.trace_id

        inner_thread = Thread.new do
          described_class.trace_id = "inner-trace"
          inner_trace = described_class.trace_id
        end
        inner_thread.join

        # Outer thread should still have its value after inner thread finishes
        expect(described_class.trace_id).to eq("outer-trace")
      end
      outer_thread.join

      # Each context maintained its own value
      expect(described_class.trace_id).to eq("main-trace")
      expect(outer_trace).to eq("outer-trace")
      expect(inner_trace).to eq("inner-trace")
    end
  end
end
