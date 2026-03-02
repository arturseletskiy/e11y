# features/request_scoped_buffer.feature
#
# Verifies request-scoped debug buffering behaviour.
# E11y's flagship feature: buffer debug events during a request,
# flush them to adapters ONLY if the request fails.
# README: "Buffer debug logs in memory, flush ONLY if request fails"
# Result: -90% noise, full context on errors.
#
# BUG: flush_event in lib/e11y/buffers/request_scoped_buffer.rb:226 is a stub.
# Buffered events are permanently lost — flush does nothing.
@request_buffer
Feature: Request-scoped debug buffering

  Background:
    Given the application is running
    And the memory adapter is empty

  Scenario: Request buffering is disabled by default
    # Config: RequestBufferConfig.enabled defaults to false
    # This means the "automatically captures" claim in docs is wrong.
    When I GET "/posts"
    Then request buffering should be disabled in the configuration

  Scenario: Request buffering can be enabled via configuration
    Given request buffering is enabled in the configuration
    Then request buffering should be enabled in the configuration

  @wip
  Scenario: Successful request — debug events are NOT written to adapter
    # With buffering enabled, debug events should be held in memory
    # and discarded (not written) when the request succeeds.
    Given request buffering is enabled in the configuration
    When I GET "/posts"
    Then 0 events with severity "debug" should be in the adapter

  @wip
  Scenario: Failed request — buffered debug events ARE flushed to adapter
    # This is the core feature: on error, all buffered debug events
    # are flushed so developers get full context.
    # BUG: flush_event is a stub — 0 events will appear even after failure.
    Given request buffering is enabled in the configuration
    When I GET "/test_error"
    Then events with severity "debug" should be in the adapter
    And those debug events should have been generated during that request

  @wip
  Scenario: Error-level events bypass the buffer and are written immediately
    # Non-debug events (info, error, fatal) must NOT be buffered —
    # they should reach the adapter immediately regardless of buffer state.
    Given request buffering is enabled in the configuration
    When I GET "/test_error"
    Then at least 1 event with severity "error" should be in the adapter

  Scenario: Buffer is cleared after a successful request — no memory leak
    # After a successful request, the per-request buffer must be discarded.
    # A subsequent request should start with a clean buffer.
    # Verified: Thread.current[:e11y_request_buffer] is nil/empty after request.
    Given request buffering is enabled in the configuration
    When I GET "/posts"
    And I GET "/posts" again
    Then the request buffer should be empty between requests
