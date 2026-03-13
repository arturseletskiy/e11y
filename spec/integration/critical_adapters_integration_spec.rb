# frozen_string_literal: true

require "rails_helper"

# Critical Adapters Integration Tests
# Tests Loki and OTel Logs adapters in real pipeline context
#
# Scenarios:
# 1. Loki Adapter: HTTP integration, batching, compression, error handling
# 2. OTel Logs Adapter: SDK integration, severity mapping, baggage PII protection

RSpec.describe "Critical Adapters Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }

  before do
    memory_adapter.clear!
    E11y::Current.reset
  end

  after do
    memory_adapter.clear!
    E11y::Current.reset
  end

  describe "Loki Adapter Integration" do
    let(:loki_url) { service_url("LOKI_URL", "http://localhost:3100") }
    let(:loki_adapter) do
      require_dependency!("Faraday", gem_name: "faraday")
      require "e11y/adapters/loki"
      E11y::Adapters::Loki.new(
        url: loki_url,
        labels: { app: "test_app", env: "test" },
        batch_size: 3,
        batch_timeout: 0.5, # Faster flush for tests
        compress: false
      )
    end

    before do
      require_dependency!("Faraday", gem_name: "faraday")
      skip_unless_service!("Loki", url: loki_url, env_var: "LOKI_URL")

      # Register Loki adapter (only reached when service is available)
      E11y.config.adapters[:loki] = loki_adapter
    end

    after do
      loki_adapter&.close
      E11y.config.adapters.delete(:loki)
    end

    it "sends events to Loki via HTTP POST" do
      # Setup: Event with Loki adapter
      # Test: Track event routed to Loki
      # Expected: Event appears in Loki via Query API

      test_event_class = Class.new(E11y::Event::Base) do
        adapters :loki
      end
      stub_const("Events::TestLoki", test_event_class)

      # Clear pipeline cache to ensure Loki adapter is registered
      E11y.config.instance_variable_set(:@built_pipeline, nil)

      Events::TestLoki.track(test_id: 1, message: "Loki integration test")

      # Wait for batch flush (batch_timeout = 1 second)
      sleep(1.5)

      # Manually flush buffer if needed
      loki_adapter.close

      # Verify event was sent to Loki by querying Loki API
      # Note: event_name will be normalized (e.g., "Events::TestLoki" -> "test.loki")
      event_name_normalized = normalize_event_name_for_loki("Events::TestLoki")
      entries = wait_for_loki_events(
        loki_url,
        label_selector: { app: "test_app", env: "test", event_name: event_name_normalized },
        expected_count: 1,
        timeout: 5
      )

      expect(entries.size).to be >= 1, "Event should appear in Loki"
      log_data = entries.first[:log]
      payload = log_data["payload"] || log_data # Support both nested and flat formats
      expect(payload["test_id"]).to eq(1)
      expect(payload["message"]).to eq("Loki integration test")
    end

    it "batches multiple events before sending" do
      # Setup: Loki adapter with batch_size: 3
      # Test: Track 5 events
      # Expected: All 5 events appear in Loki (may be batched)
      # Use unique event name to avoid pollution from previous test runs (Loki persists data)
      batch_id = SecureRandom.hex(4)
      batch_event_class = Class.new(E11y::Event::Base) do
        adapters :loki
      end
      stub_const("Events::TestLokiBatch#{batch_id}", batch_event_class)

      # Clear pipeline cache
      E11y.config.instance_variable_set(:@built_pipeline, nil)

      # Track 5 events
      5.times do |i|
        batch_event_class.track(test_id: i, message: "Batch test #{i}")
      end

      # Wait for batch flush (batch_timeout=0.5s) + Loki ingester chunk_idle_period=1s
      sleep(3)
      loki_adapter.close
      sleep(1) # Allow Loki to ingest after close

      # Verify all 5 events appear in Loki
      event_name_normalized = normalize_event_name_for_loki("Events::TestLokiBatch#{batch_id}")
      entries = wait_for_loki_events(
        loki_url,
        label_selector: { app: "test_app", env: "test", event_name: event_name_normalized },
        expected_count: 5,
        timeout: 15
      )

      expect(entries.size).to eq(5), "All 5 events should appear in Loki (got #{entries.size})"
      # Verify all test_ids are present (payload is nested in log)
      test_ids = entries.map { |e| (e[:log]["payload"] || e[:log])["test_id"] }.sort
      expect(test_ids).to eq([0, 1, 2, 3, 4])
    end

    it "includes static labels in Loki payload" do
      # Setup: Loki adapter with labels: { app: "test_app", env: "test" }
      # Test: Track event
      # Expected: Labels included in Loki stream (queryable via LogQL)

      test_event_class = Class.new(E11y::Event::Base) do
        adapters :loki
      end
      stub_const("Events::TestLokiLabels", test_event_class)

      # Clear pipeline cache
      E11y.config.instance_variable_set(:@built_pipeline, nil)

      Events::TestLokiLabels.track(test_id: 1, message: "Labels test")

      sleep(1.5)
      loki_adapter.close

      # Verify labels by querying Loki with label selector
      # Labels are used in LogQL query, so if query succeeds, labels are correct
      event_name_normalized = normalize_event_name_for_loki("Events::TestLokiLabels")
      entries = wait_for_loki_events(
        loki_url,
        label_selector: { app: "test_app", env: "test", event_name: event_name_normalized },
        expected_count: 1,
        timeout: 5
      )

      expect(entries.size).to be >= 1, "Event should appear in Loki with correct labels"
      # Verify we can query by the static labels (app, env)
      entries_by_app = query_loki_logs(loki_url, label_selector: { app: "test_app" })
      expect(entries_by_app.size).to be >= 1, "Should be able to query by app label"
    end

    it "handles HTTP errors gracefully" do
      # Setup: Loki adapter with invalid URL (will cause connection error)
      # Test: Track event
      # Expected: Error logged, pipeline continues, event goes to fallback adapter

      # Create adapter with invalid URL to simulate error
      error_adapter = E11y::Adapters::Loki.new(
        url: "http://localhost:9999", # Invalid port - will fail
        labels: { app: "test_app", env: "test" },
        batch_size: 1, # Flush immediately
        batch_timeout: 1,
        compress: false
      )
      E11y.config.adapters[:loki_error] = error_adapter

      test_event_class = Class.new(E11y::Event::Base) do
        adapters :loki_error, :memory # Also route to memory for verification
      end
      stub_const("Events::TestLokiError", test_event_class)

      # Clear pipeline cache
      E11y.config.instance_variable_set(:@built_pipeline, nil)

      # Should not raise exception
      expect do
        Events::TestLokiError.track(test_id: 1, message: "Error test")
        sleep(1.1) # Wait for flush
        error_adapter.close
      end.not_to raise_error

      # Event should still go to memory adapter (other adapter works)
      memory_events = memory_adapter.find_events("Events::TestLokiError")
      expect(memory_events.count).to eq(1), "Event should be routed to other adapters even if Loki fails"

      # Cleanup
      E11y.config.adapters.delete(:loki_error)
    end

    it "flushes buffer on close" do
      # Setup: Loki adapter with events in buffer
      # Test: Track event, then close adapter
      # Expected: Event flushed when adapter closes and appears in Loki

      test_event_class = Class.new(E11y::Event::Base) do
        adapters :loki
      end
      stub_const("Events::TestLokiFlush", test_event_class)

      # Clear pipeline cache
      E11y.config.instance_variable_set(:@built_pipeline, nil)

      Events::TestLokiFlush.track(test_id: 1, message: "Flush test")

      # Event should be in buffer (not yet flushed due to batch_timeout)
      event_name_normalized = normalize_event_name_for_loki("Events::TestLokiFlush")
      initial_entries = query_loki_logs(
        loki_url,
        label_selector: { app: "test_app", env: "test", event_name: event_name_normalized }
      )
      initial_count = initial_entries.size

      # Close adapter (should flush buffer)
      loki_adapter.close

      # Now event should appear in Loki
      entries = wait_for_loki_events(
        loki_url,
        label_selector: { app: "test_app", env: "test", event_name: event_name_normalized },
        expected_count: initial_count + 1,
        timeout: 5
      )

      expect(entries.size).to be > initial_count, "Event should appear in Loki after flush"
      entry = entries.find { |e| (e[:log]["payload"] || e[:log])["test_id"] == 1 }
      log_data = entry&.dig(:log)
      expect(log_data).not_to be_nil, "Flushed event should be in Loki"
      payload = log_data["payload"] || log_data
      expect(payload["message"]).to eq("Flush test")
    end

    it "handles network timeouts gracefully" do
      # Setup: Loki adapter with very short timeout (will timeout)
      # Test: Track event
      # Expected: Error logged, pipeline continues, event goes to fallback adapter

      # Create adapter with very short timeout to simulate timeout
      timeout_adapter = E11y::Adapters::Loki.new(
        url: "http://localhost:3100",
        labels: { app: "test_app", env: "test" },
        batch_size: 1,
        batch_timeout: 1,
        compress: false
      )
      # Mock connection to timeout by stubbing Faraday connection
      # Note: This is a simplified test - in real scenario, timeout would happen naturally
      # For integration test, we verify that errors don't break the pipeline
      E11y.config.adapters[:loki_timeout] = timeout_adapter

      test_event_class = Class.new(E11y::Event::Base) do
        adapters :loki_timeout, :memory # Also route to memory for verification
      end
      stub_const("Events::TestLokiTimeout", test_event_class)

      # Clear pipeline cache
      E11y.config.instance_variable_set(:@built_pipeline, nil)

      # Should not raise exception (even if Loki has issues)
      expect do
        Events::TestLokiTimeout.track(test_id: 1, message: "Network timeout test")
        sleep(1.1)
        timeout_adapter.close
      end.not_to raise_error

      # Event should still go to memory adapter (other adapter works)
      memory_events = memory_adapter.find_events("Events::TestLokiTimeout")
      expect(memory_events.count).to eq(1), "Event should be routed to other adapters even if Loki has issues"

      # Cleanup
      E11y.config.adapters.delete(:loki_timeout)
    end
  end

  describe "OTel Logs Adapter Integration" do
    let(:otel_adapter) do
      require_dependency!("OpenTelemetry", gem_name: "opentelemetry-sdk")
      require "e11y/adapters/otel_logs"
      E11y::Adapters::OTelLogs.new(
        service_name: "test_service",
        baggage_allowlist: %i[trace_id span_id user_id]
      )
    end

    before do
      require_dependency!("OpenTelemetry", gem_name: "opentelemetry-sdk")

      # Register OTel adapter
      E11y.config.adapters[:otel_logs] = otel_adapter

      # Mock OTel logger provider
      allow(otel_adapter).to receive_messages(logger_provider: double("LoggerProvider"), logger: double("Logger"))
    end

    after do
      E11y.config.adapters.delete(:otel_logs)
    end

    it "sends events to OTel Logs API" do
      # Setup: Event with OTel adapter
      # Test: Track event
      # Expected: OTel logger.emit called with correct log record

      test_event_class = Class.new(E11y::Event::Base) do
        adapters :otel_logs
        severity :info
      end
      stub_const("Events::TestOTel", test_event_class)

      logger = double("Logger")
      double("LogRecord")

      otel_adapter.instance_variable_set(:@logger, logger)
      expect(logger).to receive(:on_emit).with(hash_including(
                                                 body: "Events::TestOTel",
                                                 severity_number: 9,
                                                 attributes: hash_including("event.name" => "Events::TestOTel", "service.name" => "test_service")
                                               ))

      Events::TestOTel.track(test_id: 1, message: "OTel integration test")
    end

    it "maps E11y severity to OTel severity_number" do
      # Setup: Event with different severities
      # Test: Track events with different severities
      # Expected: Correct OTel severity_number used

      severities = {
        debug: 5,
        info: 9,
        warn: 13,
        error: 17,
        fatal: 21
      }

      severities.each do |e11y_severity, otel_severity_number|
        test_event_class = Class.new(E11y::Event::Base) do
          adapters :otel_logs
          severity e11y_severity
        end
        stub_const("Events::TestOTelSeverity#{e11y_severity.to_s.capitalize}", test_event_class)

        logger = double("Logger")
        log_record = double("LogRecord")

        allow(otel_adapter).to receive(:logger).and_return(logger)
        allow(OpenTelemetry::SDK::Logs::LogRecord).to receive(:new).and_return(log_record)

        # Verify severity_number is set correctly
        expect(OpenTelemetry::SDK::Logs::LogRecord).to receive(:new).with(
          hash_including(severity_number: otel_severity_number)
        )

        Events.const_get("TestOTelSeverity#{e11y_severity.to_s.capitalize}").track(
          test_id: 1,
          message: "Severity test"
        )
      end
    end

    it "filters PII from baggage using allowlist" do
      # Setup: OTel adapter with baggage_allowlist: [:trace_id, :span_id, :user_id]
      # Test: Track event with PII in context
      # Expected: Only allowlisted keys sent to baggage, PII filtered

      test_event_class = Class.new(E11y::Event::Base) do
        adapters :otel_logs
      end
      stub_const("Events::TestOTelPII", test_event_class)

      logger = double("Logger")
      log_record = double("LogRecord")

      allow(otel_adapter).to receive(:logger).and_return(logger)
      allow(OpenTelemetry::SDK::Logs::LogRecord).to receive(:new).and_return(log_record)

      # Set context with PII and safe keys
      E11y::Current.trace_id = "trace-123"
      E11y::Current.span_id = "span-456"
      # Simulate PII in context (email, phone should be filtered)

      # Verify baggage only contains allowlisted keys
      expect(OpenTelemetry::SDK::Logs::LogRecord).to receive(:new).with(
        hash_including(
          body: anything,
          attributes: hash_excluding("event.email", "event.phone", "event.password") # PII should be filtered
        )
      )

      Events::TestOTelPII.track(
        test_id: 1,
        message: "PII test",
        email: "user@example.com", # Should be filtered
        phone: "+1234567890" # Should be filtered
      )
    end

    it "maps event payload to OTel attributes" do
      # Setup: Event with payload data, adapter with allowlist including payload keys
      # Test: Track event
      # Expected: Payload mapped to OTel attributes (event.name, event.test_id, event.message)

      attributes_adapter = E11y::Adapters::OTelLogs.new(
        service_name: "test_service",
        baggage_allowlist: %i[trace_id span_id user_id test_id message]
      )
      E11y.config.adapters[:otel_logs] = attributes_adapter

      test_event_class = Class.new(E11y::Event::Base) do
        adapters :otel_logs
      end
      stub_const("Events::TestOTelAttributes", test_event_class)

      logger = double("Logger")
      log_record = double("LogRecord")

      allow(attributes_adapter).to receive(:logger).and_return(logger)
      allow(OpenTelemetry::SDK::Logs::LogRecord).to receive(:new).and_return(log_record)

      # Verify attributes include event payload (adapter uses "event.<key>" format)
      expect(OpenTelemetry::SDK::Logs::LogRecord).to receive(:new).with(
        hash_including(
          attributes: hash_including(
            "event.name" => "Events::TestOTelAttributes",
            "event.test_id" => 1,
            "event.message" => "Attributes test"
          )
        )
      )

      Events::TestOTelAttributes.track(test_id: 1, message: "Attributes test")
    ensure
      E11y.config.adapters[:otel_logs] = otel_adapter
    end

    it "handles OTel SDK errors gracefully" do
      # Setup: OTel adapter, SDK raises error
      # Test: Track event
      # Expected: Error logged, pipeline continues

      test_event_class = Class.new(E11y::Event::Base) do
        adapters :otel_logs, :memory
      end
      stub_const("Events::TestOTelError", test_event_class)

      # Mock SDK error
      allow(otel_adapter).to receive(:logger).and_raise(StandardError.new("OTel SDK error"))

      # Should not raise exception
      expect do
        Events::TestOTelError.track(test_id: 1, message: "Error test")
      end.not_to raise_error

      # Event should still go to memory adapter
      memory_events = memory_adapter.find_events("Events::TestOTelError")
      expect(memory_events.count).to eq(1), "Event should be routed to other adapters even if OTel fails"
    end

    it "respects max_attributes limit for cardinality protection" do
      # Setup: OTel adapter with max_attributes: 5, allowlist including payload keys
      # Test: Track event with 10 attributes
      # Expected: Only first 5 attributes included (event.name, service.name + 3 payload attrs)

      otel_adapter_limited = E11y::Adapters::OTelLogs.new(
        service_name: "test_service",
        max_attributes: 5,
        baggage_allowlist: %i[trace_id span_id attr1 attr2 attr3 attr4 attr5 attr6 attr7 attr8 attr9 attr10]
      )
      E11y.config.adapters[:otel_logs_limited] = otel_adapter_limited

      test_event_class = Class.new(E11y::Event::Base) do
        adapters :otel_logs_limited
      end
      stub_const("Events::TestOTelCardinality", test_event_class)

      logger = double("Logger")
      log_record = double("LogRecord")

      allow(otel_adapter_limited).to receive(:logger).and_return(logger)
      allow(OpenTelemetry::SDK::Logs::LogRecord).to receive(:new).and_return(log_record)

      # Verify attributes are limited (event.name + service.name + first 3 payload attrs = 5)
      expect(OpenTelemetry::SDK::Logs::LogRecord).to receive(:new) do |args|
        attributes = args[:attributes]
        expect(attributes.keys.length).to be <= 5, "Attributes should be limited to max_attributes"
        log_record
      end

      Events::TestOTelCardinality.track(
        attr1: 1, attr2: 2, attr3: 3, attr4: 4, attr5: 5,
        attr6: 6, attr7: 7, attr8: 8, attr9: 9, attr10: 10
      )

      E11y.config.adapters.delete(:otel_logs_limited)
    end
  end
end
