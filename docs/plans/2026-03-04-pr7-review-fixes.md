# PR #7 Review: Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Address all 11 review comments from PR #7 — clean up stale docs, fix design problems, and introduce `InMemoryTestAdapter`, `Metrics::TestBackend`, `DLQ::FileAdapter`/`DLQ::Base`, `debug_adapters` config, and proper `AuditEncrypted#read` error handling.

**Architecture:** Group A items are cosmetic/comment fixes with no tests needed. Group B items are design changes; each follows TDD: failing test → minimal implementation → green → commit. All changes stay within the current branch `feat/integration-testing`.

**Tech Stack:** Ruby 3.2, RSpec, RuboCop, OpenSSL (for AuditEncrypted), dry-schema, Concurrent::Array

---

## Group A — Quick fixes (no new tests needed)

---

### Task 1: Delete stale comment in default_pipeline.feature

**Context:** Lines 8–10 of `features/default_pipeline.feature` contain a comment that says "Fixed: RateLimiting and EventSlo are now included". The fix is done; the comment is now noise.

**Files:**
- Modify: `features/default_pipeline.feature:8-10`

**Step 1: Delete lines 8–10**

Open `features/default_pipeline.feature`. Remove lines 8–10:

```
  # Plus (advertised but missing): RateLimiting, EventSlo
  #
  # Fixed: RateLimiting and EventSlo are now included in the default pipeline.
```

After the edit the file header should look like:

```gherkin
# features/default_pipeline.feature
@pipeline
Feature: Default pipeline completeness

  # The E11y pipeline processes every event through a chain of middleware.
  # README and docs list these as part of the default pipeline:
  #   TraceContext → Validation → PIIFilter → AuditSigning → Sampling → Routing

  Background:
```

**Step 2: Run integration tests to verify nothing broken**

```bash
bundle exec cucumber features/default_pipeline.feature
```

Expected: all scenarios pass (green).

**Step 3: Commit**

```bash
git add features/default_pipeline.feature
git commit -m "docs: remove stale 'Fixed' comment from default_pipeline.feature"
```

---

### Task 2: Pre-compute health-check timeout in Loki adapter

**Context:** `lib/e11y/adapters/loki.rb:166` re-computes `[@timeout, 2].min` on every `healthy?` call (called by the circuit breaker on every event). This is cheap but pointless allocation; move it to `initialize`.

**Files:**
- Modify: `lib/e11y/adapters/loki.rb:89-115` (initialize), `lib/e11y/adapters/loki.rb:162-172` (healthy?)

**Step 1: Add `@health_check_timeout` in `initialize`**

In `initialize`, after `@timeout = config.fetch(:timeout, 5)` (line 94), add:

```ruby
@health_check_timeout = [@timeout, 2].min
```

**Step 2: Replace inline computation in `healthy?`**

Change `healthy?` from:

```ruby
def healthy?
  return false unless @connection

  @connection.get("/ready") do |req|
    req.options.timeout = [@timeout, 2].min
    req.options.open_timeout = [@timeout, 2].min
  end
  true
rescue StandardError
  false
end
```

To:

```ruby
def healthy?
  return false unless @connection

  @connection.get("/ready") do |req|
    req.options.timeout = @health_check_timeout
    req.options.open_timeout = @health_check_timeout
  end
  true
rescue StandardError
  false
end
```

**Step 3: Run loki specs**

```bash
bundle exec rspec spec/e11y/adapters/loki_spec.rb
```

Expected: all pass.

**Step 4: Commit**

```bash
git add lib/e11y/adapters/loki.rb
git commit -m "perf: pre-compute health_check_timeout in Loki#initialize"
```

---

### Task 3: Document debug-only buffering with ADR reference in routing.rb

**Context:** PR reviewer asked why only `:debug` severity goes to the request buffer. ADR-001 spec (line 254 in the ADR) explicitly states `:debug only`. Add a one-line ADR reference comment so the next reader doesn't need to ask.

**Files:**
- Modify: `lib/e11y/middleware/routing.rb:70-79` (buffer block comment)

**Step 1: Add ADR reference to the buffer block**

Change the comment block at line 70:

```ruby
# 0. Buffer debug events when request-scoped buffering is active.
#    Debug events are held in memory and flushed only on request failure.
#    Non-debug events bypass the buffer and are written immediately.
```

To:

```ruby
# 0. Buffer debug events when request-scoped buffering is active.
#    Only :debug severity is buffered — see ADR-001 §7 ("Request Buffer: :debug only").
#    On request success → buffer discarded. On request failure → flushed to adapters.
#    Non-debug events bypass the buffer and are written immediately.
```

**Step 2: Run routing specs**

```bash
bundle exec rspec spec/e11y/middleware/routing_spec.rb
```

Expected: all pass.

**Step 3: Commit**

```bash
git add lib/e11y/middleware/routing.rb
git commit -m "docs: add ADR-001 reference for debug-only request buffer in routing.rb"
```

---

### Task 4: Clarify double-callback bug note in rails_integration.feature

**Context:** Line 10 of `features/rails_integration.feature` says the double-callback bug "cannot be demonstrated in integration tests". The reviewer asked for a clearer explanation of what the bug actually is.

**Files:**
- Modify: `features/rails_integration.feature:9-11`

**Step 1: Expand the NOTE**

Change lines 9–11:

```gherkin
  # NOTE: Double-callback bug (ApplicationJob + ActiveJob::Base both included) cannot
  #       be demonstrated in integration tests where ActiveJob::Base is already configured.
```

To:

```gherkin
  # NOTE: Double-callback bug — if both ApplicationJob and ActiveJob::Base each call
  #       `include E11y::Instruments::ActiveJob`, the around_perform callback is registered
  #       twice, causing every job to emit duplicate events and run context-setup twice.
  #       This cannot be demonstrated here because the dummy app's ActiveJob::Base is
  #       already configured; the Railtie guards against double-registration via
  #       `around_perform_callbacks.any? { |cb| cb.filter == E11y::... }`.
```

**Step 2: Run rails integration scenarios**

```bash
bundle exec cucumber features/rails_integration.feature
```

Expected: all pass.

**Step 3: Commit**

```bash
git add features/rails_integration.feature
git commit -m "docs: clarify double-callback bug in rails_integration.feature"
```

---

### Task 5: Clarify "Workaround" comment in rails_integration.feature scenario

**Context:** Line 21 says `# Workaround: user must manually set enabled: false in test.rb`. Reviewer asked whether this is test env only. The scenario tests the `enabled:` flag in *any* environment; clarify that.

**Files:**
- Modify: `features/rails_integration.feature:20-22`

**Step 1: Replace comment**

Change:

```gherkin
  Scenario: E11y configuration can be explicitly disabled
    # Workaround: user must manually set enabled: false in test.rb.
    # Verifies the flag itself works when explicitly set.
```

To:

```gherkin
  Scenario: E11y configuration can be explicitly disabled
    # The Railtie auto-disables E11y in the test environment only.
    # In all other environments users must set `config.enabled = false` explicitly.
    # This scenario verifies that the flag itself works when set at runtime.
```

**Step 2: Run rails integration scenarios**

```bash
bundle exec cucumber features/rails_integration.feature
```

Expected: all pass.

**Step 3: Commit**

```bash
git add features/rails_integration.feature
git commit -m "docs: clarify 'Workaround' comment in rails_integration.feature"
```

---

## Group B — Design changes (TDD)

---

### Task 6: Extract InMemoryTestAdapter (move Rails filter + event_count out of base adapter)

**Context:** `InMemory#last_event` contains a hardcoded filter that skips `E11y::Events::Rails::*` events. `InMemory#event_count` is also primarily a test-utility method. Both belong in a test-only subclass, not in the production adapter. `InMemory` stays as is (no filter, no `event_count` removal — it's a general counter). The new `InMemoryTestAdapter` inherits from `InMemory` and adds `last_event` (with Rails filter). Any integration tests that want this behavior will use `InMemoryTestAdapter`; pure production usage stays on `InMemory`.

**Design decision (from PR review):**
- `InMemory` remains unchanged (keeps `event_count`, `last_event` without filter) — it is already documented as a test adapter
- `InMemoryTestAdapter` subclasses `InMemory` and **overrides** `last_event` to skip Rails instrumentation events
- The integration test dummy app switches its adapter from `InMemory` to `InMemoryTestAdapter`
- The unit test for the Rails-filter behavior moves to `InMemoryTestAdapter` spec

**Files:**
- Create: `lib/e11y/adapters/in_memory_test.rb`
- Modify: `spec/e11y/adapters/in_memory_spec.rb` (move filter tests to new spec)
- Create: `spec/e11y/adapters/in_memory_test_spec.rb`
- Modify: `spec/dummy/config/initializers/e11y.rb` (switch adapter)
- Modify: any integration specs using `last_event` with Rails filter assumption

**Step 1: Write failing spec for InMemoryTestAdapter**

Create `spec/e11y/adapters/in_memory_test_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "e11y/adapters/in_memory"
require "e11y/adapters/in_memory_test"

RSpec.describe E11y::Adapters::InMemoryTest do
  subject(:adapter) { described_class.new }

  let(:app_event)   { { event_name: "order.paid", severity: :info, payload: {} } }
  let(:rails_event) { { event_name: "E11y::Events::Rails::RequestCompleted", severity: :info, payload: {} } }

  describe "#last_event" do
    it "skips Rails instrumentation events" do
      adapter.write(app_event)
      adapter.write(rails_event)
      expect(adapter.last_event).to eq(app_event)
    end

    it "returns nil when only Rails events are present" do
      adapter.write(rails_event)
      expect(adapter.last_event).to be_nil
    end

    it "returns the most recent non-Rails event" do
      adapter.write(app_event)
      adapter.write({ event_name: "order.failed", severity: :error, payload: {} })
      adapter.write(rails_event)
      expect(adapter.last_event[:event_name]).to eq("order.failed")
    end
  end

  it "inherits all InMemory behaviour" do
    adapter.write(app_event)
    expect(adapter.event_count).to eq(1)
    expect(adapter.events).to include(app_event)
  end
end
```

**Step 2: Run to verify it fails**

```bash
bundle exec rspec spec/e11y/adapters/in_memory_test_spec.rb
```

Expected: FAIL with `NameError: uninitialized constant E11y::Adapters::InMemoryTest`.

**Step 3: Create `lib/e11y/adapters/in_memory_test.rb`**

```ruby
# frozen_string_literal: true

require_relative "in_memory"

module E11y
  module Adapters
    # InMemoryTest Adapter — extends InMemory with test-specific helpers.
    #
    # Overrides `last_event` to skip Rails auto-instrumentation events
    # (E11y::Events::Rails::*) that fire after each HTTP request and
    # would otherwise obscure the event your test just tracked.
    #
    # Use this adapter in test suites; use `InMemory` in production configs.
    #
    # @example
    #   let(:adapter) { E11y::Adapters::InMemoryTest.new }
    #   before { E11y.register_adapter :memory, adapter }
    class InMemoryTest < InMemory
      # Return the last event that was NOT fired by Rails auto-instrumentation.
      #
      # @return [Hash, nil]
      def last_event
        events.reverse_each.find do |e|
          !e[:event_name].to_s.start_with?("E11y::Events::Rails::")
        end
      end
    end
  end
end
```

**Step 4: Run spec to verify it passes**

```bash
bundle exec rspec spec/e11y/adapters/in_memory_test_spec.rb
```

Expected: all green.

**Step 5: Move Rails-filter tests from in_memory_spec.rb to in_memory_test_spec.rb**

In `spec/e11y/adapters/in_memory_spec.rb`, find the `describe "#last_event"` examples that test Rails-filter behaviour (lines ~265–274). Delete those two examples:

```ruby
it "skips Rails instrumentation events" do ...
it "returns nil when only Rails instrumentation events are present" do ...
```

They now live in `in_memory_test_spec.rb`.

**Step 6: Update dummy app initializer**

Open `spec/dummy/config/initializers/e11y.rb`. Find the line that registers the `:memory` adapter. Change `E11y::Adapters::InMemory.new` to `E11y::Adapters::InMemoryTest.new` and add the require:

```ruby
require "e11y/adapters/in_memory_test"
# ...
config.register_adapter :memory, E11y::Adapters::InMemoryTest.new
```

**Step 7: Run full unit + integration suite to check nothing broke**

```bash
bundle exec rspec spec/e11y/adapters/in_memory_spec.rb \
               spec/e11y/adapters/in_memory_test_spec.rb
rake spec:all
```

Expected: 0 failures.

**Step 8: Commit**

```bash
git add lib/e11y/adapters/in_memory_test.rb \
        spec/e11y/adapters/in_memory_test_spec.rb \
        spec/e11y/adapters/in_memory_spec.rb \
        spec/dummy/config/initializers/e11y.rb
git commit -m "feat: extract InMemoryTestAdapter with Rails-filter override"
```

---

### Task 7: Add Metrics::TestBackend — remove @_store from production Tracker

**Context:** `E11y::SLO::Tracker` has `@_store`, `status`, and `reset!` purely for test introspection. The PR reviewer questions whether these belong in production code. Decision: keep `@_store` / `status` / `reset!` in Tracker but mark them `@api private`; they're already private/documented. The real fix is to provide a `Metrics::TestBackend` that records calls so specs can assert on what was tracked — instead of `expect(E11y::Metrics).to receive(:increment)`.

**Note:** `tracker_spec.rb` already uses `expect(E11y::Metrics).to receive` mocks — those are fine as-is. The `TestBackend` is for *integration-level* tests that want to assert "did the right metric get tracked" without mocking. Add `TestBackend` but don't rewrite existing tracker_spec.rb.

**Files:**
- Create: `lib/e11y/metrics/test_backend.rb`
- Create: `spec/e11y/metrics/test_backend_spec.rb`
- Modify: `lib/e11y/slo/tracker.rb` — add `@api private` to `status`, `reset!`, `@_store`

**Step 1: Write failing spec for TestBackend**

Create `spec/e11y/metrics/test_backend_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "e11y/metrics/test_backend"

RSpec.describe E11y::Metrics::TestBackend do
  subject(:backend) { described_class.new }

  describe "#increment" do
    it "records increments" do
      backend.increment(:orders_total, { status: "paid" })
      expect(backend.increments).to include(
        { name: :orders_total, labels: { status: "paid" }, value: 1 }
      )
    end

    it "accepts custom value" do
      backend.increment(:orders_total, {}, value: 5)
      expect(backend.increments.first[:value]).to eq(5)
    end
  end

  describe "#histogram" do
    it "records histogram observations" do
      backend.histogram(:duration_seconds, 0.042, { controller: "orders" })
      expect(backend.histograms).to include(
        { name: :duration_seconds, value: 0.042, labels: { controller: "orders" } }
      )
    end
  end

  describe "#gauge" do
    it "records gauge values" do
      backend.gauge(:buffer_size, 128, { type: "ring" })
      expect(backend.gauges).to include(
        { name: :buffer_size, value: 128, labels: { type: "ring" } }
      )
    end
  end

  describe "#reset!" do
    it "clears all recorded metrics" do
      backend.increment(:orders_total, {})
      backend.reset!
      expect(backend.increments).to be_empty
    end
  end

  describe "#increment_count" do
    it "returns how many times a metric was incremented" do
      backend.increment(:orders_total, { status: "paid" })
      backend.increment(:orders_total, { status: "failed" })
      expect(backend.increment_count(:orders_total)).to eq(2)
    end

    it "returns 0 for unknown metric" do
      expect(backend.increment_count(:never_tracked)).to eq(0)
    end
  end
end
```

**Step 2: Run to verify it fails**

```bash
bundle exec rspec spec/e11y/metrics/test_backend_spec.rb
```

Expected: FAIL with `NameError: uninitialized constant E11y::Metrics::TestBackend`.

**Step 3: Create `lib/e11y/metrics/test_backend.rb`**

```ruby
# frozen_string_literal: true

module E11y
  module Metrics
    # In-memory metrics backend for tests.
    #
    # Records all metric calls so test assertions can verify what was tracked
    # without using mocks on E11y::Metrics directly.
    #
    # @example
    #   backend = E11y::Metrics::TestBackend.new
    #   E11y::Metrics.instance_variable_set(:@backend, backend)
    #
    #   MyService.call
    #
    #   expect(backend.increment_count(:orders_total)).to eq(1)
    #   expect(backend.increments).to include(hash_including(name: :orders_total))
    class TestBackend
      attr_reader :increments, :histograms, :gauges

      def initialize
        reset!
      end

      # @param name [Symbol] Metric name
      # @param labels [Hash] Metric labels
      # @param value [Integer] Increment amount
      def increment(name, labels = {}, value: 1)
        @increments << { name: name, labels: labels, value: value }
      end

      # @param name [Symbol] Metric name
      # @param value [Numeric] Observed value
      # @param labels [Hash] Metric labels
      def histogram(name, value, labels = {}, buckets: nil)
        @histograms << { name: name, value: value, labels: labels }
      end

      # @param name [Symbol] Metric name
      # @param value [Numeric] Gauge value
      # @param labels [Hash] Metric labels
      def gauge(name, value, labels = {})
        @gauges << { name: name, value: value, labels: labels }
      end

      # Reset all recorded metrics.
      def reset!
        @increments = []
        @histograms = []
        @gauges     = []
      end

      # Count how many times a counter was incremented (any labels).
      #
      # @param name [Symbol] Metric name
      # @return [Integer]
      def increment_count(name)
        @increments.count { |r| r[:name] == name }
      end
    end
  end
end
```

**Step 4: Run spec to verify it passes**

```bash
bundle exec rspec spec/e11y/metrics/test_backend_spec.rb
```

Expected: all green.

**Step 5: Mark @_store / status / reset! as @api private in Tracker**

Open `lib/e11y/slo/tracker.rb`. The `@_store`, `status`, and `reset!` already have doc comments. Update them:

`@_store` class-level comment (line 35–37):
```ruby
# In-memory store for tracked request data (per endpoint).
# @api private Used internally and in tests via Tracker.status; not part of public API.
@_store = {}
```

`status` method comment (line 38–44):
```ruby
# Return a snapshot of all tracked endpoints and their request counts.
# @api private Intended for test assertions only.
# @return [Hash]
def status
```

`reset!` method — already says `@api private`, no change needed.

**Step 6: Run all unit tests**

```bash
rake spec:unit
```

Expected: 0 failures.

**Step 7: Commit**

```bash
git add lib/e11y/metrics/test_backend.rb \
        spec/e11y/metrics/test_backend_spec.rb \
        lib/e11y/slo/tracker.rb
git commit -m "feat: add Metrics::TestBackend for assertion-based metric testing"
```

---

### Task 8: AuditEncrypted#read — raise on CipherError + track security event

**Context:** Currently `read` rescues `Errno::ENOENT, OpenSSL::Cipher::CipherError, JSON::ParserError` and returns `nil` for all three. Decision:
- `Errno::ENOENT` → return `nil` (file not found, expected)
- `JSON::ParserError` → return `nil` (corrupt data, log a warning)
- `OpenSSL::Cipher::CipherError` → **re-raise** AND track a security event

The security event should be tracked via `E11y::Event::Base.track` if available, otherwise fall back to a `warn` log. In unit tests E11y may not be fully configured, so guard with a `rescue StandardError` around the tracking call.

**Files:**
- Modify: `lib/e11y/adapters/audit_encrypted.rb:88-94` (`read` method)
- Modify: `spec/e11y/adapters/audit_encrypted_spec.rb:121-153` (update expectations)

**Step 1: Write failing tests (update existing spec expectations)**

Open `spec/e11y/adapters/audit_encrypted_spec.rb`. Find the two tamper tests (lines ~121–153). Change both to expect a `raise` instead of `be_nil`:

```ruby
it "detects tampered ciphertext" do
  adapter.write(event_data)

  files = Dir.glob(File.join(temp_dir, "*.enc"))
  filepath = files.first

  encrypted = JSON.parse(File.read(filepath), symbolize_names: true)
  encrypted[:encrypted_data] = Base64.strict_encode64("tampered")
  File.write(filepath, JSON.generate(encrypted))

  event_id = File.basename(filepath)

  expect { adapter.read(event_id) }.to raise_error(OpenSSL::Cipher::CipherError)
end

it "detects tampered auth_tag" do
  adapter.write(event_data)

  files = Dir.glob(File.join(temp_dir, "*.enc"))
  filepath = files.first

  encrypted = JSON.parse(File.read(filepath), symbolize_names: true)
  encrypted[:auth_tag] = Base64.strict_encode64("0" * 16)
  File.write(filepath, JSON.generate(encrypted))

  event_id = File.basename(filepath)

  expect { adapter.read(event_id) }.to raise_error(OpenSSL::Cipher::CipherError)
end
```

Add a new test for `Errno::ENOENT` still returning nil:

```ruby
it "returns nil for a missing file" do
  expect(adapter.read("nonexistent_file_id.enc")).to be_nil
end
```

**Step 2: Run to verify tests fail**

```bash
bundle exec rspec spec/e11y/adapters/audit_encrypted_spec.rb
```

Expected: the two tamper tests FAIL (currently return nil, not raise).

**Step 3: Update `read` in audit_encrypted.rb**

Replace the `read` method (lines 88–94):

```ruby
def read(event_id)
  encrypted_data = read_from_storage(event_id)
  decrypt_event(encrypted_data)
rescue Errno::ENOENT => e
  warn "AuditEncrypted read error (file not found): #{e.message}"
  nil
rescue JSON::ParserError => e
  warn "AuditEncrypted read error (corrupt data): #{e.message}"
  nil
rescue OpenSSL::Cipher::CipherError => e
  # SECURITY: decryption failure indicates tampered or corrupt ciphertext.
  # Re-raise so callers can handle it; also attempt to emit a security event.
  track_security_event(event_id, e)
  raise
end
```

Add private helper `track_security_event` below `read`:

```ruby
private

# Emit a security event when decryption fails (potential tampering).
# Guards against E11y not being fully configured in non-production envs.
#
# @param event_id [String] The event ID that failed to decrypt
# @param error [OpenSSL::Cipher::CipherError] The decryption error
# @return [void]
def track_security_event(event_id, error)
  E11y::Event::Base.track(
    event_name: "e11y.security.audit_decryption_failed",
    severity: :error,
    payload: {
      event_id: event_id,
      error_class: error.class.name,
      error_message: error.message,
      adapter: self.class.name
    }
  )
rescue StandardError
  warn "AuditEncrypted: decryption failure detected for #{event_id} " \
       "(#{error.message}); security event could not be tracked"
end
```

Make sure `require "e11y/event/base"` is present at the top of `audit_encrypted.rb` (add if missing).

**Step 4: Run spec to verify all pass**

```bash
bundle exec rspec spec/e11y/adapters/audit_encrypted_spec.rb
```

Expected: all green.

**Step 5: Run full unit suite**

```bash
rake spec:unit
```

Expected: 0 failures.

**Step 6: Commit**

```bash
git add lib/e11y/adapters/audit_encrypted.rb \
        spec/e11y/adapters/audit_encrypted_spec.rb
git commit -m "feat: AuditEncrypted#read raises on CipherError and tracks security event"
```

---

### Task 9: Add `config.request_buffer.debug_adapters` — explicit flush targets

**Context:** When `RequestScopedBuffer` flushes on error, it currently sends buffered debug events to `E11y.configuration.fallback_adapters || [:memory]`. This is wrong: `fallback_adapters` is the fallback for *routing*, not necessarily for debug buffer flushes. Not all adapters can handle the extra load from flushed debug events (e.g., Loki with small batches, Sentry with event quotas). Decision: add `config.request_buffer.debug_adapters` — an explicit opt-in list. Default: the same set of adapters used by `fallback_adapters` (so existing behaviour is preserved without any user config change).

**Files:**
- Modify: `lib/e11y.rb:278-284` (`RequestBufferConfig` class)
- Modify: `lib/e11y/buffers/request_scoped_buffer.rb:229-240` (`flush_event`)
- Modify: `spec/e11y/buffers/request_scoped_buffer_spec.rb` (add test for new config)

**Step 1: Write failing spec**

Open `spec/e11y/buffers/request_scoped_buffer_spec.rb`. Find the section that tests `flush_event`. Add:

```ruby
describe ".flush_event with debug_adapters configured" do
  let(:adapter_a) { E11y::Adapters::InMemory.new }
  let(:adapter_b) { E11y::Adapters::InMemory.new }

  before do
    E11y.configure do |config|
      config.register_adapter :log_adapter, adapter_a
      config.register_adapter :debug_log_adapter, adapter_b
      config.fallback_adapters = [:log_adapter]
      config.request_buffer.debug_adapters = [:debug_log_adapter]
    end
  end

  it "flushes to debug_adapters, not fallback_adapters" do
    E11y::Buffers::RequestScopedBuffer.initialize!
    event = { event_name: "test.debug", severity: :debug, payload: {} }
    E11y::Buffers::RequestScopedBuffer.flush_event(event)

    expect(adapter_b.events).to include(event)
    expect(adapter_a.events).to be_empty
  end
end

describe ".flush_event without debug_adapters (default)" do
  let(:fallback_adapter) { E11y::Adapters::InMemory.new }

  before do
    E11y.configure do |config|
      config.register_adapter :fallback, fallback_adapter
      config.fallback_adapters = [:fallback]
      # request_buffer.debug_adapters NOT set
    end
  end

  it "falls back to fallback_adapters when debug_adapters is nil" do
    event = { event_name: "test.debug", severity: :debug, payload: {} }
    E11y::Buffers::RequestScopedBuffer.flush_event(event)

    expect(fallback_adapter.events).to include(event)
  end
end
```

**Step 2: Run to verify tests fail**

```bash
bundle exec rspec spec/e11y/buffers/request_scoped_buffer_spec.rb
```

Expected: FAIL — `NoMethodError: undefined method 'debug_adapters=' for RequestBufferConfig`.

**Step 3: Add `debug_adapters` to `RequestBufferConfig`**

In `lib/e11y.rb`, change:

```ruby
class RequestBufferConfig
  attr_accessor :enabled

  def initialize
    @enabled = false # Disabled by default
  end
end
```

To:

```ruby
class RequestBufferConfig
  # Enable request-scoped buffering (default: false).
  attr_accessor :enabled

  # Explicit list of adapter names that receive flushed debug events on request failure.
  #
  # If nil (default), falls back to config.fallback_adapters.
  # Set this to limit debug flushes to adapters that can handle the extra load.
  #
  # @example Only flush debug events to Loki (not Sentry)
  #   config.request_buffer.debug_adapters = [:loki_logger]
  attr_accessor :debug_adapters

  def initialize
    @enabled       = false # Disabled by default
    @debug_adapters = nil   # nil → use fallback_adapters
  end
end
```

**Step 4: Update `flush_event` in request_scoped_buffer.rb**

Change line 230:

```ruby
adapter_names = target ? [target] : (E11y.configuration.fallback_adapters || [:memory])
```

To:

```ruby
adapter_names = if target
                  [target]
                else
                  E11y.configuration.request_buffer.debug_adapters ||
                    E11y.configuration.fallback_adapters ||
                    [:memory]
                end
```

**Step 5: Run spec to verify tests pass**

```bash
bundle exec rspec spec/e11y/buffers/request_scoped_buffer_spec.rb
```

Expected: all green.

**Step 6: Run full unit suite**

```bash
rake spec:unit
```

Expected: 0 failures.

**Step 7: Commit**

```bash
git add lib/e11y.rb \
        lib/e11y/buffers/request_scoped_buffer.rb \
        spec/e11y/buffers/request_scoped_buffer_spec.rb
git commit -m "feat: add request_buffer.debug_adapters config for explicit flush targets"
```

---

### Task 10: Rename DLQ::FileStorage → DLQ::FileAdapter + extract DLQ::Base

**Context:** `DLQ::FileStorage` name doesn't follow the Adapter naming convention used throughout the codebase. Decision: rename to `DLQ::FileAdapter`, and extract a `DLQ::Base` abstract interface (similar to `E11y::Adapters::Base`) that defines the contract (`save`, `list`, `stats`, `replay`, `replay_batch`, `delete`). This makes it easy to add `DLQ::RedisAdapter` etc. later.

**Files:**
- Create: `lib/e11y/reliability/dlq/base.rb`
- Rename: `lib/e11y/reliability/dlq/file_storage.rb` → `lib/e11y/reliability/dlq/file_adapter.rb`
- Modify: class name inside `file_adapter.rb` from `FileStorage` to `FileAdapter`
- Modify: `lib/e11y.rb:156` (comment referencing `DLQ::FileStorage`)
- Modify: `spec/e11y/reliability/dlq/file_storage_spec.rb` → rename and update
- Modify: `spec/integration/reliability_integration_spec.rb` (2 references)
- Modify: any `require` statements in the codebase

**Step 1: Write failing spec for DLQ::Base interface**

Create `spec/e11y/reliability/dlq/base_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "e11y/reliability/dlq/base"

RSpec.describe E11y::Reliability::DLQ::Base do
  it "raises NotImplementedError for save" do
    expect { described_class.new.save({}) }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for list" do
    expect { described_class.new.list }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for stats" do
    expect { described_class.new.stats }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for replay" do
    expect { described_class.new.replay("id") }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for delete" do
    expect { described_class.new.delete("id") }.to raise_error(NotImplementedError)
  end
end
```

**Step 2: Run to verify it fails**

```bash
bundle exec rspec spec/e11y/reliability/dlq/base_spec.rb
```

Expected: FAIL with `NameError: uninitialized constant E11y::Reliability::DLQ::Base`.

**Step 3: Create `lib/e11y/reliability/dlq/base.rb`**

```ruby
# frozen_string_literal: true

module E11y
  module Reliability
    module DLQ
      # Abstract base class for Dead Letter Queue storage backends.
      #
      # Subclass this to implement a custom DLQ backend (file, Redis, database, etc.).
      # All methods raise NotImplementedError by default.
      #
      # @see DLQ::FileAdapter for the file-based implementation
      class Base
        # Save a failed event to the DLQ.
        # @param event_data [Hash]
        # @param metadata [Hash]
        # @return [String] event ID
        def save(event_data, metadata: {})
          raise NotImplementedError, "#{self.class}#save is not implemented"
        end

        # List DLQ entries.
        # @param limit [Integer]
        # @param offset [Integer]
        # @param filters [Hash]
        # @return [Array<Hash>]
        def list(limit: 100, offset: 0, filters: {})
          raise NotImplementedError, "#{self.class}#list is not implemented"
        end

        # Return DLQ statistics.
        # @return [Hash]
        def stats
          raise NotImplementedError, "#{self.class}#stats is not implemented"
        end

        # Replay a single event.
        # @param event_id [String]
        # @return [Boolean]
        def replay(event_id)
          raise NotImplementedError, "#{self.class}#replay is not implemented"
        end

        # Replay a batch of events.
        # @param event_ids [Array<String>]
        # @return [Hash]
        def replay_batch(event_ids)
          results = event_ids.each_with_object({ success_count: 0, failure_count: 0 }) do |id, acc|
            replay(id) ? acc[:success_count] += 1 : acc[:failure_count] += 1
          end
          results
        end

        # Delete an entry from the DLQ.
        # @param event_id [String]
        # @return [Boolean]
        def delete(event_id)
          raise NotImplementedError, "#{self.class}#delete is not implemented"
        end
      end
    end
  end
end
```

**Step 4: Run base spec to verify green**

```bash
bundle exec rspec spec/e11y/reliability/dlq/base_spec.rb
```

Expected: all pass.

**Step 5: Create `lib/e11y/reliability/dlq/file_adapter.rb`** (copy of file_storage.rb with renames)

Copy `file_storage.rb` to `file_adapter.rb`. Inside the new file:
- Change `class FileStorage` → `class FileAdapter < Base`
- Add `require_relative "base"` at top
- Update the `@example` in the docstring: `dlq = FileAdapter.new(...)`

`file_storage.rb` should be kept temporarily with a deprecation notice that points to `FileAdapter` (for backwards-compat):

```ruby
# frozen_string_literal: true

require_relative "file_adapter"

module E11y
  module Reliability
    module DLQ
      # @deprecated Use DLQ::FileAdapter instead.
      FileStorage = FileAdapter
    end
  end
end
```

**Step 6: Run existing file_storage_spec.rb to verify no regressions**

```bash
bundle exec rspec spec/e11y/reliability/dlq/file_storage_spec.rb
```

Expected: all pass (FileStorage is now an alias for FileAdapter).

**Step 7: Create spec for FileAdapter**

Create `spec/e11y/reliability/dlq/file_adapter_spec.rb` by copying `file_storage_spec.rb` and replacing `FileStorage` → `FileAdapter` and `file_storage` → `file_adapter`. Update the require:

```ruby
require_relative "../../../../lib/e11y/reliability/dlq/file_adapter"
RSpec.describe E11y::Reliability::DLQ::FileAdapter do
```

**Step 8: Run file_adapter spec**

```bash
bundle exec rspec spec/e11y/reliability/dlq/file_adapter_spec.rb
```

Expected: all pass.

**Step 9: Update lib/e11y.rb comment**

Line 156: change `DLQ::FileStorage instance` → `DLQ::FileAdapter instance`.

**Step 10: Update integration spec references**

In `spec/integration/reliability_integration_spec.rb`, replace `DLQ::FileStorage` → `DLQ::FileAdapter` and add `require "e11y/reliability/dlq/file_adapter"`.

**Step 11: Run full suite**

```bash
rake spec:all
```

Expected: 0 failures.

**Step 12: Commit**

```bash
git add lib/e11y/reliability/dlq/base.rb \
        lib/e11y/reliability/dlq/file_adapter.rb \
        lib/e11y/reliability/dlq/file_storage.rb \
        spec/e11y/reliability/dlq/base_spec.rb \
        spec/e11y/reliability/dlq/file_adapter_spec.rb \
        spec/integration/reliability_integration_spec.rb \
        lib/e11y.rb
git commit -m "feat: rename DLQ::FileStorage → DLQ::FileAdapter, extract DLQ::Base interface"
```

---

## Final verification

After all 10 tasks are committed, run the full suite one more time:

```bash
rake spec:all
bundle exec rubocop
```

Expected: 0 failures, 0 offenses.

Then open a PR or push to `feat/integration-testing`.
