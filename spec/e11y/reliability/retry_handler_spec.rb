# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/e11y/reliability/retry_handler"

RSpec.describe E11y::Reliability::RetryHandler do
  let(:config) do
    {
      max_attempts: 3,
      base_delay_ms: 10, # Short delay for tests
      max_delay_ms: 100,
      jitter_factor: 0.1,
      fail_on_error: true
    }
  end
  let(:retry_handler) { described_class.new(config: config) }
  let(:adapter) { double("Adapter", class: double(name: "TestAdapter")) }
  let(:event_data) { { event_name: "test.event", severity: :info } }

  describe "#with_retry" do
    context "when block succeeds immediately" do
      it "returns result without retry" do
        result = retry_handler.with_retry(adapter: adapter, event: event_data) do
          "success"
        end

        expect(result).to eq("success")
      end

      it "does not sleep" do
        allow(retry_handler).to receive(:sleep)

        retry_handler.with_retry(adapter: adapter, event: event_data) do
          "success"
        end

        expect(retry_handler).not_to have_received(:sleep)
      end
    end

    context "when block fails with retriable error" do
      it "retries on Timeout::Error" do
        attempt = 0

        result = retry_handler.with_retry(adapter: adapter, event: event_data) do
          attempt += 1
          raise Timeout::Error if attempt < 2

          "recovered"
        end

        expect(result).to eq("recovered")
        expect(attempt).to eq(2)
      end

      it "retries on ECONNREFUSED" do
        attempt = 0

        result = retry_handler.with_retry(adapter: adapter, event: event_data) do
          attempt += 1
          raise Errno::ECONNREFUSED if attempt < 2

          "recovered"
        end

        expect(result).to eq("recovered")
        expect(attempt).to eq(2)
      end

      it "retries on 5xx HTTP errors" do
        http_error = StandardError.new("Server Error")
        response = double(code: 503)
        allow(http_error).to receive(:response).and_return(response)

        attempt = 0

        result = retry_handler.with_retry(adapter: adapter, event: event_data) do
          attempt += 1
          raise http_error if attempt < 2

          "recovered"
        end

        expect(result).to eq("recovered")
        expect(attempt).to eq(2)
      end

      it "uses exponential backoff with jitter" do
        attempt = 0
        sleep_durations = []

        allow(retry_handler).to receive(:sleep) do |duration|
          sleep_durations << duration
        end

        retry_handler.with_retry(adapter: adapter, event: event_data) do
          attempt += 1
          raise Timeout::Error if attempt < 3

          "recovered"
        end

        # Should have 2 sleeps (before attempts 2 and 3)
        expect(sleep_durations.size).to eq(2)

        # First delay: ~10ms (base_delay_ms)
        expect(sleep_durations[0]).to be_within(0.002).of(0.01)

        # Second delay: ~20ms (base_delay_ms * 2^1)
        expect(sleep_durations[1]).to be_within(0.004).of(0.02)
      end
    end

    context "when block fails with permanent error" do
      it "does not retry on ArgumentError" do
        attempt = 0

        expect do
          retry_handler.with_retry(adapter: adapter, event: event_data) do
            attempt += 1
            raise ArgumentError, "bad argument"
          end
        end.to raise_error(E11y::Reliability::RetryHandler::RetryExhaustedError)

        expect(attempt).to eq(1) # No retries
      end

      it "does not retry on 4xx HTTP errors" do
        http_error = StandardError.new("Bad Request")
        response = double(code: 400)
        allow(http_error).to receive(:response).and_return(response)

        attempt = 0

        expect do
          retry_handler.with_retry(adapter: adapter, event: event_data) do
            attempt += 1
            raise http_error
          end
        end.to raise_error(E11y::Reliability::RetryHandler::RetryExhaustedError)

        expect(attempt).to eq(1)
      end
    end

    context "when max attempts exceeded" do
      it "raises RetryExhaustedError" do
        attempt = 0

        expect do
          retry_handler.with_retry(adapter: adapter, event: event_data) do
            attempt += 1
            raise Timeout::Error, "always fails"
          end
          # rubocop:todo Style/MultilineBlockChain
        end.to raise_error(E11y::Reliability::RetryHandler::RetryExhaustedError) do |error|
          # rubocop:enable Style/MultilineBlockChain
          expect(error.retry_count).to eq(3)
          expect(error.original_error).to be_a(Timeout::Error)
        end

        expect(attempt).to eq(3)
      end

      it "includes original error in message" do
        expect do
          retry_handler.with_retry(adapter: adapter, event: event_data) do
            raise Timeout::Error, "connection timeout"
          end
        end.to raise_error(E11y::Reliability::RetryHandler::RetryExhaustedError, /connection timeout/)
      end
    end

    context "with fail_on_error: false" do
      let(:config) { { max_attempts: 2, base_delay_ms: 1, fail_on_error: false } }

      it "returns nil instead of raising on max retries" do
        attempt = 0

        result = retry_handler.with_retry(adapter: adapter, event: event_data) do
          attempt += 1
          raise Timeout::Error
        end

        expect(result).to be_nil
        expect(attempt).to eq(2)
      end

      it "returns nil instead of raising on permanent error" do
        result = retry_handler.with_retry(adapter: adapter, event: event_data) do
          raise ArgumentError
        end

        expect(result).to be_nil
      end
    end

    context "with retry_rate_limiter (BUG-002: thundering herd prevention)" do
      let(:rate_limiter) { E11y::Reliability::RetryRateLimiter.new(limit: 2, window: 1.0) }
      let(:rate_limited_handler) do
        described_class.new(
          config: { max_attempts: 5, base_delay_ms: 1, fail_on_error: false },
          retry_rate_limiter: rate_limiter
        )
      end

      it "accepts retry_rate_limiter kwarg without error" do
        expect do
          described_class.new(
            config: { max_attempts: 3 },
            retry_rate_limiter: rate_limiter
          )
        end.not_to raise_error
      end

      it "stops retrying when rate limiter blocks (prevents thundering herd)" do
        attempt = 0

        result = rate_limited_handler.with_retry(adapter: adapter, event: event_data) do
          attempt += 1
          raise Timeout::Error
        end

        # limit: 2 means only 2 retries allowed, so total attempts should be <= 3 (1 initial + 2 retries)
        expect(attempt).to be <= 3
        expect(result).to be_nil
      end
    end
  end

  describe "backoff calculation" do
    it "calculates exponential backoff correctly" do
      delays = []

      allow(retry_handler).to receive(:sleep) do |duration|
        delays << (duration * 1000).round # Convert to ms
      end

      retry_handler.with_retry(adapter: adapter, event: event_data) do
        raise Timeout::Error if delays.size < 2

        "success"
      end

      # Attempt 1: 10ms * 2^0 = 10ms
      expect(delays[0]).to be_within(2).of(10)

      # Attempt 2: 10ms * 2^1 = 20ms
      expect(delays[1]).to be_within(3).of(20)
    end

    it "caps delay at max_delay_ms" do
      config_with_cap = config.merge(base_delay_ms: 50, max_delay_ms: 60, max_attempts: 5)
      handler = described_class.new(config: config_with_cap)

      delays = []
      allow(handler).to receive(:sleep) do |duration|
        delays << (duration * 1000).round
      end

      handler.with_retry(adapter: adapter, event: event_data) do
        raise Timeout::Error if delays.size < 4

        "success"
      end

      # All delays should be <= max_delay_ms
      expect(delays).to all(be <= 70) # Allow jitter margin
    end

    it "adds random jitter to prevent thundering herd" do
      delays1 = []
      delays2 = []

      # First run
      handler1 = described_class.new(config: config)
      allow(handler1).to receive(:sleep) { |d| delays1 << d }

      handler1.with_retry(adapter: adapter, event: event_data) do
        raise Timeout::Error if delays1.size < 2

        "success"
      end

      # Second run
      handler2 = described_class.new(config: config)
      allow(handler2).to receive(:sleep) { |d| delays2 << d }

      handler2.with_retry(adapter: adapter, event: event_data) do
        raise Timeout::Error if delays2.size < 2

        "success"
      end

      # Delays should be different due to jitter
      expect(delays1).not_to eq(delays2)
    end
  end

  describe "real-world scenario: transient network failure" do
    it "recovers from temporary network issues" do
      # Simulate flaky network: fail twice, then succeed
      attempt = 0

      result = retry_handler.with_retry(adapter: adapter, event: event_data) do
        attempt += 1

        case attempt
        when 1
          raise Errno::ECONNREFUSED, "connection refused"
        when 2
          raise Timeout::Error, "timeout"
        when 3
          { sent: true, duration_ms: 45 }
        end
      end

      expect(result).to eq({ sent: true, duration_ms: 45 })
      expect(attempt).to eq(3)
    end

    it "gives up after persistent failures" do
      # Simulate complete outage
      attempt = 0

      expect do
        retry_handler.with_retry(adapter: adapter, event: event_data) do
          attempt += 1
          raise Errno::EHOSTUNREACH, "host unreachable"
        end
      end.to raise_error(E11y::Reliability::RetryHandler::RetryExhaustedError)

      expect(attempt).to eq(3) # All attempts exhausted
    end
  end

  describe "thread safety" do
    it "handles concurrent retries safely" do
      threads = Array.new(5) do |i|
        Thread.new do
          adapter_i = double("Adapter#{i}", class: double(name: "Adapter#{i}"))

          begin
            retry_handler.with_retry(adapter: adapter_i, event: event_data) do
              raise Timeout::Error if rand < 0.3

              "success"
            end
          rescue E11y::Reliability::RetryHandler::RetryExhaustedError
            # Expected
          end
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
    end
  end

  describe "BUG-002: rate_limiter integration (thundering herd prevention)" do
    let(:short_config) do
      {
        max_attempts: 3,
        base_delay_ms: 1,
        max_delay_ms: 10,
        jitter_factor: 0.0,
        fail_on_error: true
      }
    end

    it "accepts rate_limiter: keyword argument in initialize" do
      rate_limiter = E11y::Reliability::RetryRateLimiter.new
      handler = described_class.new(config: short_config, rate_limiter: rate_limiter)
      expect(handler.instance_variable_get(:@rate_limiter)).to be(rate_limiter)
    end

    it "works normally when no rate_limiter is provided" do
      handler = described_class.new(config: short_config)
      expect(handler.instance_variable_get(:@rate_limiter)).to be_nil

      attempt = 0
      result = handler.with_retry(adapter: adapter, event: event_data) do
        attempt += 1
        raise Timeout::Error if attempt < 2

        "success"
      end
      expect(result).to eq("success")
    end

    context "when rate_limiter allows the retry (allow? returns true)" do
      let(:permissive_limiter) do
        limiter = instance_double(E11y::Reliability::RetryRateLimiter)
        allow(limiter).to receive(:allow?).and_return(true)
        allow(limiter).to receive(:instance_variable_get).with(:@on_limit_exceeded).and_return(:delay)
        limiter
      end

      let(:handler_with_limiter) do
        described_class.new(config: short_config, rate_limiter: permissive_limiter)
      end

      it "performs the retry when rate limiter allows" do
        allow(handler_with_limiter).to receive(:sleep)

        attempt = 0
        result = handler_with_limiter.with_retry(adapter: adapter, event: event_data) do
          attempt += 1
          raise Timeout::Error if attempt < 2

          "recovered"
        end

        expect(result).to eq("recovered")
        expect(attempt).to eq(2)
      end
    end

    context "when rate_limiter blocks the retry (allow? returns false, on_limit_exceeded: :dlq)" do
      let(:blocking_limiter) do
        limiter = instance_double(E11y::Reliability::RetryRateLimiter)
        allow(limiter).to receive(:allow?).and_return(false)
        allow(limiter).to receive(:instance_variable_get).with(:@on_limit_exceeded).and_return(:dlq)
        limiter
      end

      let(:handler_with_blocking_limiter) do
        described_class.new(config: short_config, rate_limiter: blocking_limiter)
      end

      it "aborts retry and raises RetryExhaustedError when fail_on_error is true" do
        expect do
          handler_with_blocking_limiter.with_retry(adapter: adapter, event: event_data) do
            raise Timeout::Error, "transient"
          end
        end.to raise_error(E11y::Reliability::RetryHandler::RetryExhaustedError)
      end

      it "executes the block only once before rate limit kicks in" do
        allow(handler_with_blocking_limiter).to receive(:sleep)
        attempt = 0

        expect do
          handler_with_blocking_limiter.with_retry(adapter: adapter, event: event_data) do
            attempt += 1
            raise Timeout::Error
          end
        end.to raise_error(E11y::Reliability::RetryHandler::RetryExhaustedError)

        # First attempt is made, then rate limiter blocks retrying
        expect(attempt).to eq(1)
      end
    end

    context "when rate_limiter blocks with :delay strategy" do
      let(:delay_limiter) do
        limiter = instance_double(E11y::Reliability::RetryRateLimiter)
        allow(limiter).to receive(:allow?).and_return(false)
        allow(limiter).to receive(:instance_variable_get).with(:@on_limit_exceeded).and_return(:delay)
        allow(limiter).to receive(:instance_variable_get).with(:@window).and_return(0.001)
        limiter
      end

      let(:handler_with_delay_limiter) do
        described_class.new(config: short_config, rate_limiter: delay_limiter)
      end

      it "sleeps (extra delay) before eventually exhausting retries" do
        allow(handler_with_delay_limiter).to receive(:sleep)

        attempt = 0
        expect do
          handler_with_delay_limiter.with_retry(adapter: adapter, event: event_data) do
            attempt += 1
            raise Timeout::Error
          end
        end.to raise_error(E11y::Reliability::RetryHandler::RetryExhaustedError)

        # sleep is called for rate-limiter delay AND for normal backoff
        expect(handler_with_delay_limiter).to have_received(:sleep).at_least(:once)
      end
    end
  end
end
