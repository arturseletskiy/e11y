# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/e11y/reliability/circuit_breaker"

RSpec.describe E11y::Reliability::CircuitBreaker do
  let(:adapter_name) { "test_adapter" }
  let(:config) do
    {
      failure_threshold: 3,
      timeout_seconds: 1,
      half_open_attempts: 2
    }
  end
  let(:circuit_breaker) { described_class.new(adapter_name: adapter_name, config: config) }

  describe "#initialize" do
    it "initializes in CLOSED state" do
      expect(circuit_breaker.healthy?).to be true
    end

    it "sets default failure threshold" do
      cb = described_class.new(adapter_name: "test")
      # Default threshold is 5
      5.times do
        cb.call { raise "error" }
      rescue StandardError
        # Expected
      end
      expect(cb.healthy?).to be false
    end
  end

  describe "#call" do
    context "when circuit is CLOSED (healthy)" do
      it "executes block successfully" do
        result = circuit_breaker.call { "success" }
        expect(result).to eq("success")
      end

      it "increments failure count on error" do
        expect do
          circuit_breaker.call { raise "error" }
        end.to raise_error(StandardError)

        stats = circuit_breaker.stats
        expect(stats[:failure_count]).to eq(1)
      end

      it "transitions to OPEN after threshold failures" do
        # Fail 3 times (threshold)
        3.times do
          circuit_breaker.call { raise "error" }
        rescue StandardError
          # Expected
        end

        expect(circuit_breaker.healthy?).to be false
        expect(circuit_breaker.stats[:state]).to eq(:open)
      end

      it "resets failure count on success" do
        # Fail once
        begin
          circuit_breaker.call { raise "error" }
        rescue StandardError
          # Expected
        end

        expect(circuit_breaker.stats[:failure_count]).to eq(1)

        # Succeed
        circuit_breaker.call { "success" }

        # Failure count should reset
        expect(circuit_breaker.stats[:failure_count]).to eq(0)
      end
    end

    context "when circuit is OPEN (failing)" do
      before do
        # Open the circuit
        3.times do
          circuit_breaker.call { raise "error" }
        rescue StandardError
          # Expected
        end
      end

      it "raises CircuitOpenError without executing block" do
        block_executed = false

        expect do
          circuit_breaker.call { block_executed = true }
        end.to raise_error(E11y::Reliability::CircuitBreaker::CircuitOpenError)

        expect(block_executed).to be false
      end

      it "includes adapter name in error message" do
        expect do
          circuit_breaker.call { "never executed" }
        end.to raise_error(E11y::Reliability::CircuitBreaker::CircuitOpenError, /test_adapter/)
      end

      it "transitions to HALF_OPEN after timeout" do
        # Wait for timeout
        sleep(config[:timeout_seconds] + 0.1)

        # Next call should transition to HALF_OPEN
        begin
          circuit_breaker.call { raise "still failing" }
        rescue StandardError
          # Expected
        end

        expect(circuit_breaker.stats[:state]).to eq(:open) # Back to OPEN (failed in HALF_OPEN)
      end
    end

    context "when circuit is HALF_OPEN (testing recovery)" do
      before do
        # Open the circuit
        3.times do
          circuit_breaker.call { raise "error" }
        rescue StandardError
          # Expected
        end

        # Wait for timeout to transition to HALF_OPEN
        sleep(config[:timeout_seconds] + 0.1)
      end

      it "transitions to CLOSED after successful attempts" do
        # First success
        circuit_breaker.call { "success" }
        expect(circuit_breaker.stats[:state]).to eq(:half_open)

        # Second success (threshold)
        circuit_breaker.call { "success" }
        expect(circuit_breaker.stats[:state]).to eq(:closed)
        expect(circuit_breaker.healthy?).to be true
      end

      it "transitions back to OPEN on single failure" do
        # Single failure in HALF_OPEN
        expect do
          circuit_breaker.call { raise "still broken" }
        end.to raise_error(StandardError)

        expect(circuit_breaker.stats[:state]).to eq(:open)
        expect(circuit_breaker.healthy?).to be false
      end
    end
  end

  describe "#healthy?" do
    it "returns true when circuit is CLOSED" do
      expect(circuit_breaker.healthy?).to be true
    end

    it "returns false when circuit is OPEN" do
      # Open the circuit
      3.times do
        circuit_breaker.call { raise "error" }
      rescue StandardError
        # Expected
      end

      expect(circuit_breaker.healthy?).to be false
    end

    it "returns false when circuit is HALF_OPEN" do
      # Open the circuit
      3.times do
        circuit_breaker.call { raise "error" }
      rescue StandardError
        # Expected
      end

      # Wait for timeout
      sleep(config[:timeout_seconds] + 0.1)

      # Trigger transition to HALF_OPEN (but don't complete)
      begin
        circuit_breaker.call { "success" }
      rescue StandardError
        # Ignore
      end

      expect(circuit_breaker.healthy?).to be false
    end
  end

  describe "#stats" do
    it "returns circuit breaker statistics" do
      stats = circuit_breaker.stats

      expect(stats).to include(
        adapter: adapter_name,
        state: :closed,
        failure_count: 0,
        success_count: 0,
        last_failure: nil,
        opened_at: nil
      )
    end

    it "tracks failure count" do
      begin
        circuit_breaker.call { raise "error" }
      rescue StandardError
        # Expected
      end

      stats = circuit_breaker.stats
      expect(stats[:failure_count]).to eq(1)
      expect(stats[:last_failure]).to be_a(Time)
    end

    it "tracks success count in HALF_OPEN" do
      # Open the circuit
      3.times do
        circuit_breaker.call { raise "error" }
      rescue StandardError
        # Expected
      end

      # Wait for timeout
      sleep(config[:timeout_seconds] + 0.1)

      # Success in HALF_OPEN
      circuit_breaker.call { "success" }

      stats = circuit_breaker.stats
      expect(stats[:success_count]).to eq(1)
    end

    it "tracks opened_at timestamp" do
      # Open the circuit
      3.times do
        circuit_breaker.call { raise "error" }
      rescue StandardError
        # Expected
      end

      stats = circuit_breaker.stats
      expect(stats[:opened_at]).to be_a(Time)
    end
  end

  describe "thread safety" do
    it "handles concurrent calls safely" do
      threads = 10.times.map do
        Thread.new do
          10.times do
            circuit_breaker.call { "success" }
          rescue E11y::Reliability::CircuitBreaker::CircuitOpenError
            # Expected when circuit opens
          end
        end
      end

      threads.each(&:join)

      # Should not crash or corrupt state
      expect(circuit_breaker.stats).to include(:state, :failure_count, :success_count)
    end
  end

  describe "real-world scenario: adapter recovery" do
    it "allows gradual recovery after outage" do
      # Simulate adapter down (3 failures)
      3.times do
        circuit_breaker.call { raise Timeout::Error, "adapter down" }
      rescue StandardError
        # Expected
      end

      expect(circuit_breaker.stats[:state]).to eq(:open)

      # Wait for timeout (adapter recovers)
      sleep(config[:timeout_seconds] + 0.1)

      # First probe (HALF_OPEN)
      circuit_breaker.call { "recovered" }
      expect(circuit_breaker.stats[:state]).to eq(:half_open)

      # Second probe (should close circuit)
      circuit_breaker.call { "recovered" }
      expect(circuit_breaker.stats[:state]).to eq(:closed)
      expect(circuit_breaker.healthy?).to be true
    end

    it "prevents cascade failures when adapter is flaky" do
      # Adapter consistently failing to trigger circuit breaker
      results = []
      circuit_opened = false

      20.times do |i|
        result = circuit_breaker.call do
          # Fail consistently to trigger circuit (threshold = 3)
          raise "adapter error" if i < 10

          "success"
        end
        results << result
      rescue E11y::Reliability::CircuitBreaker::CircuitOpenError
        results << :circuit_open
        circuit_opened = true
      rescue StandardError
        results << :error
      end

      # Circuit should open after threshold failures
      expect(circuit_opened).to be true
      expect(results).to include(:circuit_open)
    end
  end
end
