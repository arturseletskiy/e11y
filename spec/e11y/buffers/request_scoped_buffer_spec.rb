# frozen_string_literal: true

require "spec_helper"
require "e11y/buffers/request_scoped_buffer"

RSpec.describe E11y::Buffers::RequestScopedBuffer do
  # Reset thread-local storage before each test
  before do
    described_class.reset_all
  end

  after do
    described_class.reset_all
  end

  describe ".initialize!" do
    it "initializes empty buffer" do
      described_class.initialize!

      expect(described_class.buffer).to eq([])
      expect(described_class.active?).to be true
      expect(described_class.error_occurred?).to be false
    end

    it "generates request ID if not provided" do
      described_class.initialize!

      expect(described_class.request_id).to be_a(String)
      expect(described_class.request_id).to match(/\A[0-9a-f-]{36}\z/) # UUID format
    end

    it "accepts custom request ID" do
      described_class.initialize!(request_id: "custom-req-123")

      expect(described_class.request_id).to eq("custom-req-123")
    end

    it "accepts custom buffer limit" do
      described_class.initialize!(buffer_limit: 200)

      # Fill buffer with 150 events (within limit)
      150.times do |i|
        result = described_class.add_event({ event_name: "test#{i}", severity: :debug })
        expect(result).to be true
      end

      expect(described_class.size).to eq(150)
    end
  end

  describe ".add_event" do
    before do
      described_class.initialize!
    end

    context "when buffer is active" do
      it "buffers debug events" do
        event = { event_name: "test", severity: :debug, payload: { id: 1 } }

        result = described_class.add_event(event)

        expect(result).to be true
        expect(described_class.size).to eq(1)
        expect(described_class.buffer.first).to include(event)
        expect(described_class.buffer.first[:request_id]).to be_a(String)
      end

      it "does not buffer info events" do
        event = { event_name: "test", severity: :info }

        result = described_class.add_event(event)

        expect(result).to be false
        expect(described_class.size).to eq(0)
      end

      it "does not buffer success events" do
        event = { event_name: "test", severity: :success }

        result = described_class.add_event(event)

        expect(result).to be false
        expect(described_class.size).to eq(0)
      end

      it "does not buffer warn events" do
        event = { event_name: "test", severity: :warn }

        result = described_class.add_event(event)

        expect(result).to be false
        expect(described_class.size).to eq(0)
      end

      it "triggers flush on error severity" do
        # Add debug events first
        described_class.add_event({ event_name: "debug1", severity: :debug })
        described_class.add_event({ event_name: "debug2", severity: :debug })

        expect(described_class.size).to eq(2)

        # Error event should trigger flush
        error_event = { event_name: "error", severity: :error }
        result = described_class.add_event(error_event)

        expect(result).to be false # Error not buffered
        expect(described_class.error_occurred?).to be true
        expect(described_class.size).to eq(0) # Buffer flushed
      end

      it "triggers flush on fatal severity" do
        described_class.add_event({ event_name: "debug", severity: :debug })

        fatal_event = { event_name: "fatal", severity: :fatal }
        described_class.add_event(fatal_event)

        expect(described_class.error_occurred?).to be true
        expect(described_class.size).to eq(0)
      end

      it "respects buffer limit (default 100)" do
        # Fill buffer to limit
        100.times do |i|
          result = described_class.add_event({ event_name: "test#{i}", severity: :debug })
          expect(result).to be true
        end

        # Next event should be dropped
        result = described_class.add_event({ event_name: "overflow", severity: :debug })

        expect(result).to be false
        expect(described_class.size).to eq(100) # Still at limit
      end
    end

    context "when buffer is not active" do
      before do
        described_class.reset_all
      end

      it "returns false" do
        event = { event_name: "test", severity: :debug }

        result = described_class.add_event(event)

        expect(result).to be false
        expect(described_class.active?).to be false
      end
    end
  end

  describe ".flush_on_error" do
    before do
      described_class.initialize!
    end

    it "flushes all buffered events" do
      # Add 3 debug events
      described_class.add_event({ event_name: "debug1", severity: :debug })
      described_class.add_event({ event_name: "debug2", severity: :debug })
      described_class.add_event({ event_name: "debug3", severity: :debug })

      expect(described_class.size).to eq(3)

      # Flush
      flushed_count = described_class.flush_on_error

      expect(flushed_count).to eq(3)
      expect(described_class.size).to eq(0)
    end

    it "returns 0 for empty buffer" do
      flushed_count = described_class.flush_on_error

      expect(flushed_count).to eq(0)
    end

    it "returns 0 for inactive buffer" do
      described_class.reset_all

      flushed_count = described_class.flush_on_error

      expect(flushed_count).to eq(0)
    end
  end

  describe ".discard" do
    before do
      described_class.initialize!
    end

    it "discards all buffered events" do
      # Add events
      described_class.add_event({ event_name: "debug1", severity: :debug })
      described_class.add_event({ event_name: "debug2", severity: :debug })

      expect(described_class.size).to eq(2)

      # Discard
      discarded_count = described_class.discard

      expect(discarded_count).to eq(2)
      expect(described_class.size).to eq(0)
    end

    it "returns 0 for empty buffer" do
      discarded_count = described_class.discard

      expect(discarded_count).to eq(0)
    end
  end

  describe ".active?" do
    it "returns false when not initialized" do
      expect(described_class.active?).to be false
    end

    it "returns true when initialized" do
      described_class.initialize!

      expect(described_class.active?).to be true
    end

    it "returns false after reset" do
      described_class.initialize!
      described_class.reset_all

      expect(described_class.active?).to be false
    end
  end

  describe ".error_occurred?" do
    before do
      described_class.initialize!
    end

    it "returns false initially" do
      expect(described_class.error_occurred?).to be false
    end

    it "returns true after error severity detected" do
      described_class.add_event({ event_name: "error", severity: :error })

      expect(described_class.error_occurred?).to be true
    end

    it "returns true after fatal severity detected" do
      described_class.add_event({ event_name: "fatal", severity: :fatal })

      expect(described_class.error_occurred?).to be true
    end
  end

  describe ".size" do
    it "returns 0 when not initialized" do
      expect(described_class.size).to eq(0)
    end

    it "returns 0 for empty buffer" do
      described_class.initialize!

      expect(described_class.size).to eq(0)
    end

    it "returns correct count for buffered events" do
      described_class.initialize!
      described_class.add_event({ event_name: "debug1", severity: :debug })
      described_class.add_event({ event_name: "debug2", severity: :debug })

      expect(described_class.size).to eq(2)
    end
  end

  describe "thread safety" do
    it "isolates buffers between threads" do
      # Thread 1: Initialize and buffer events
      thread1 = Thread.new do
        described_class.initialize!(request_id: "req-1")
        described_class.add_event({ event_name: "thread1", severity: :debug })
        described_class.size
      end

      # Thread 2: Initialize with different buffer
      thread2 = Thread.new do
        described_class.initialize!(request_id: "req-2")
        described_class.add_event({ event_name: "thread2", severity: :debug })
        described_class.add_event({ event_name: "thread2-2", severity: :debug })
        described_class.size
      end

      thread1_size = thread1.value
      thread2_size = thread2.value

      # Each thread should have its own isolated buffer
      expect(thread1_size).to eq(1)
      expect(thread2_size).to eq(2)
    end

    it "does not leak buffer between requests" do
      # Request 1
      described_class.initialize!(request_id: "req-1")
      described_class.add_event({ event_name: "req1", severity: :debug })
      expect(described_class.size).to eq(1)
      described_class.reset_all

      # Request 2 (new thread-local context)
      described_class.initialize!(request_id: "req-2")
      expect(described_class.size).to eq(0) # Should be empty
    end
  end

  describe "UC-001 compliance" do
    before do
      described_class.initialize!
    end

    it "implements severity-based buffering (debug only)" do
      described_class.add_event({ event_name: "debug", severity: :debug })
      described_class.add_event({ event_name: "info", severity: :info })
      described_class.add_event({ event_name: "success", severity: :success })

      # Only debug event buffered
      expect(described_class.size).to eq(1)
      expect(described_class.buffer.first[:event_name]).to eq("debug")
    end

    it "implements auto-flush on error" do
      # Simulate request with debug events
      described_class.add_event({ event_name: "debug1", severity: :debug })
      described_class.add_event({ event_name: "debug2", severity: :debug })

      # Error triggers flush
      described_class.add_event({ event_name: "error", severity: :error })

      # Buffer should be empty (flushed)
      expect(described_class.size).to eq(0)
      expect(described_class.error_occurred?).to be true
    end

    it "implements discard on successful request" do
      # Simulate successful request with debug events
      described_class.add_event({ event_name: "debug1", severity: :debug })
      described_class.add_event({ event_name: "debug2", severity: :debug })

      # Success path - discard buffer
      described_class.discard unless described_class.error_occurred?

      # Buffer should be empty (discarded)
      expect(described_class.size).to eq(0)
    end

    it "achieves zero debug logs in success requests" do
      # Simulate 100 successful requests
      successful_requests = 100
      total_debug_events = 0
      discarded_events = 0

      successful_requests.times do
        described_class.initialize!
        described_class.add_event({ event_name: "debug", severity: :debug })
        described_class.add_event({ event_name: "debug", severity: :debug })
        described_class.add_event({ event_name: "debug", severity: :debug })

        total_debug_events += 3

        # Success - discard
        discarded_events += described_class.discard
        described_class.reset_all
      end

      # All 300 debug events should be discarded (not flushed to adapters)
      expect(total_debug_events).to eq(300)
      expect(discarded_events).to eq(300)
      # In real implementation, discarded events would NOT be sent to adapters
      # Thus achieving "zero debug logs in success requests"
    end

    it "flushes debug events only on error" do
      # Simulate 99 successful + 1 failed request
      99.times do
        described_class.initialize!
        3.times { described_class.add_event({ event_name: "debug", severity: :debug }) }
        described_class.discard
        described_class.reset_all
      end

      # 1 failed request
      described_class.initialize!
      described_class.add_event({ event_name: "debug1", severity: :debug })
      described_class.add_event({ event_name: "debug2", severity: :debug })
      flushed_count = described_class.flush_on_error

      # Only 2 debug events flushed (from failed request)
      expect(flushed_count).to eq(2)
    end
  end
end
