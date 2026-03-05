# Fix @wip Bugs Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** Fix all 30+ @wip-tagged Cucumber scenarios by resolving known bugs in E11y's codebase, making the gem's actual behavior match its documented API.

**Architecture:** Each task corresponds to one or more @wip scenarios. Workflow: remove @wip from the scenario → run to confirm failure → fix the minimal code → run to confirm pass → commit. Tests are Cucumber integration tests in `features/`. All code fixes are inside `lib/e11y/`.

**Tech Stack:** Ruby 3.2+, Cucumber (integration tests), RSpec (unit tests), E11y gem internals (middleware pipeline, adapters, buffers, sampling)

---

## Quick Reference: All @wip Scenarios

| Feature file | @wip lines | Task |
|---|---|---|
| `features/adaptive_sampling.feature` | 29, 39 | Task 2 |
| `features/adaptive_sampling.feature` | 77 | Task 1 (already passes) |
| `features/adapter_configurations.feature` | 20 | Task 13 |
| `features/adapter_configurations.feature` | 51 | Task 12 |
| `features/adapter_configurations.feature` | 67 | Task 1 (already passes) |
| `features/audit_encrypted.feature` | 36 | Task 11 |
| `features/auto_metrics.feature` | 36, 43 | Task 14 |
| `features/default_pipeline.feature` | 36, 42, 61 | Task 8 |
| `features/dlq.feature` | 25, 34 | Task 5 |
| `features/dlq.feature` | 46 | Task 1 (already passes) |
| `features/event_tracking.feature` | 33 | Task 6 |
| `features/event_versioning.feature` | 42 | Task 3 |
| `features/in_memory_adapter.feature` | 39, 51, 60 | Task 4 |
| `features/pii_filtering.feature` | 56, 78, 87 | Task 9 |
| `features/presets.feature` | 18, 26 | Task 10 |
| `features/rails_integration.feature` | 18 | Task 7 |
| `features/request_scoped_buffer.feature` | 28, 36, 46 | Task 15 |
| `features/slo_tracking.feature` | 21, 28, 52 | Task 16 |

---

### Task 1: Remove @wip from 3 already-passing scenarios

**Context:** Three scenarios have @wip but already pass. The `After` hook warns when a @wip scenario passes unexpectedly — we just need to remove the tag so they run cleanly.

**Files:**
- Modify: `features/adaptive_sampling.feature` (line 77)
- Modify: `features/adapter_configurations.feature` (line 67)
- Modify: `features/dlq.feature` (line 46)

**Step 1: Run the 3 scenarios to confirm they pass with @wip warnings**

```bash
bundle exec cucumber features/adaptive_sampling.feature:77 features/adapter_configurations.feature:67 features/dlq.feature:46 2>&1 | tail -15
```

Expected output: something like `3 scenarios (3 passed)` with `@wip scenario passed` warnings in `After` hooks.

**Step 2: Remove @wip from adaptive_sampling.feature**

In `features/adaptive_sampling.feature`, find the `@wip` tag on the scenario that starts around line 77 (titled something like "Trace ID consistency..."). Remove only `@wip`.

**Step 3: Remove @wip from adapter_configurations.feature**

In `features/adapter_configurations.feature`, find `@wip` on line 67 (the Sentry reinit scenario). Remove it.

**Step 4: Remove @wip from dlq.feature**

In `features/dlq.feature`, find `@wip` on line 46 (the FileStorage Rails path scenario). Remove it.

**Step 5: Run all 3 to confirm clean pass**

```bash
bundle exec cucumber features/adaptive_sampling.feature:77 features/adapter_configurations.feature:67 features/dlq.feature:46
```

Expected: `3 scenarios (3 passed)` — no warnings.

**Step 6: Commit**

```bash
git add features/adaptive_sampling.feature features/adapter_configurations.feature features/dlq.feature
git commit -m "test: remove @wip from 3 scenarios that already pass"
```

---

### Task 2: Fix LoadMonitor off-by-one

**Scenarios:** `features/adaptive_sampling.feature` lines 29 and 39

**Bug:** `lib/e11y/sampling/load_monitor.rb` around line 104:
```ruby
elsif rate >= @thresholds[:normal]
  :high   # BUG: when rate == :normal threshold, returns :high instead of :normal
```
When `rate` exactly equals the `:normal` threshold, it should return `:normal`, but `>=` causes it to return `:high`.

**Files:**
- Modify: `lib/e11y/sampling/load_monitor.rb` (line ~104)
- Modify: `features/adaptive_sampling.feature` (remove @wip from lines 29 and 39)

**Step 1: Remove @wip from both scenarios**

In `features/adaptive_sampling.feature`, remove `@wip` tags from the scenarios at lines 29 and 39.

**Step 2: Run to confirm they fail**

```bash
bundle exec cucumber features/adaptive_sampling.feature:29 features/adaptive_sampling.feature:39
```

Expected: 2 scenarios FAIL with something like "expected :normal but got :high".

**Step 3: Read the file to find the exact line**

```bash
grep -n "rate >= @thresholds\[:normal\]" lib/e11y/sampling/load_monitor.rb
```

**Step 4: Fix the comparison**

In `lib/e11y/sampling/load_monitor.rb`, change the `elsif` from `>=` to `>`:

```ruby
# Before:
elsif rate >= @thresholds[:normal]
  :high

# After:
elsif rate > @thresholds[:normal]
  :high
```

**Step 5: Run to confirm both pass**

```bash
bundle exec cucumber features/adaptive_sampling.feature:29 features/adaptive_sampling.feature:39
```

Expected: 2 scenarios PASS.

**Step 6: Run the full feature to catch regressions**

```bash
bundle exec cucumber features/adaptive_sampling.feature
```

Expected: all scenarios pass.

**Step 7: Commit**

```bash
git add lib/e11y/sampling/load_monitor.rb features/adaptive_sampling.feature
git commit -m "fix: LoadMonitor off-by-one — use > instead of >= for normal threshold"
```

---

### Task 3: Fix Versioning middleware — preserve custom event_name

**Scenario:** `features/event_versioning.feature` line 42

**Bug:** `lib/e11y/middleware/versioning.rb` around line 75 unconditionally overwrites `event_data[:event_name]` with the normalized class-derived name, even when the event class defines a custom `event_name` override.

**Files:**
- Modify: `lib/e11y/middleware/versioning.rb`
- Modify: `features/event_versioning.feature` (remove @wip from line 42)

**Step 1: Read the versioning middleware**

Read `lib/e11y/middleware/versioning.rb` completely. Find the `call` method where `event_data[:event_name]` is set. It will look something like:

```ruby
class_name = event_data[:event_class]&.name.to_s
event_data[:event_name] = normalize_event_name(class_name)   # BUG: always overwrites
```

Also find out how `normalize_event_name` works (likely strips `Events::` prefix, underscores CamelCase).

Also find how a custom event_name is stored — likely the event class stores it as a class-level attribute accessible via `event_data[:event_class].event_name` or similar.

**Step 2: Remove @wip from event_versioning.feature:42**

**Step 3: Run to confirm it fails**

```bash
bundle exec cucumber features/event_versioning.feature:42
```

Expected: FAIL — custom event_name is overwritten.

**Step 4: Fix the middleware**

The fix should only normalize when no custom event_name has been set. Read how the event class stores a custom `event_name` (check `lib/e11y/event/base.rb` for the DSL macro). Then:

```ruby
class_name = event_data[:event_class]&.name.to_s
normalized = normalize_event_name(class_name)

# Only overwrite if the event class has NOT set a custom event_name
custom_name = event_data[:event_class]&.event_name
if custom_name.nil? || custom_name.to_s == normalized
  event_data[:event_name] = normalized
end
# If custom_name differs from normalized, leave event_data[:event_name] as-is
```

**Important:** Adapt this to the actual code — read the file before editing. The key insight is: only write `normalized` if there is no explicit custom name overriding it.

**Step 5: Run to confirm it passes**

```bash
bundle exec cucumber features/event_versioning.feature
```

Expected: all scenarios pass.

**Step 6: Commit**

```bash
git add lib/e11y/middleware/versioning.rb features/event_versioning.feature
git commit -m "fix: versioning middleware preserves custom event_name overrides"
```

---

### Task 4: Fix InMemory adapter — missing APIs

**Scenarios:** `features/in_memory_adapter.feature` lines 39, 51, 60

**Three bugs in `lib/e11y/adapters/in_memory.rb`:**
1. `event_count` only takes keyword arg `event_name:` — calling `event_count("string")` raises `ArgumentError`
2. `last_event` (singular, no bang) method is missing
3. `clear` (without bang) method/alias is missing

**Files:**
- Modify: `lib/e11y/adapters/in_memory.rb`
- Modify: `features/in_memory_adapter.feature` (remove @wip from lines 39, 51, 60)

**Step 1: Read in_memory.rb**

Read `lib/e11y/adapters/in_memory.rb` completely to understand all current public methods and their implementations.

**Step 2: Remove @wip from the 3 scenarios**

**Step 3: Run to confirm they fail**

```bash
bundle exec cucumber features/in_memory_adapter.feature:39 features/in_memory_adapter.feature:51 features/in_memory_adapter.feature:60
```

Expected: 3 scenarios FAIL.

**Step 4: Fix `event_count` to accept positional arg**

Change:
```ruby
def event_count(event_name: nil)
  # ...
end
```

To:
```ruby
def event_count(event_name = nil, **kwargs)
  event_name ||= kwargs[:event_name]
  # rest of implementation unchanged
end
```

**Step 5: Add `last_event` method**

```ruby
def last_event
  events.last
end
```

Add this near the other query methods in the file.

**Step 6: Add `clear` alias**

After the existing `clear!` method definition, add:
```ruby
alias clear clear!
```

**Step 7: Run to confirm all 3 pass**

```bash
bundle exec cucumber features/in_memory_adapter.feature
```

Expected: all scenarios pass.

**Step 8: Commit**

```bash
git add lib/e11y/adapters/in_memory.rb features/in_memory_adapter.feature
git commit -m "fix: InMemory adapter adds last_event, clear alias, and positional event_count arg"
```

---

### Task 5: Fix DLQ FileStorage — implement replay and delete

**Scenarios:** `features/dlq.feature` lines 25 and 34

**Two bugs in `lib/e11y/reliability/dlq/file_storage.rb`:**
1. `replay(event_id)` is a stub — reads the entry but does nothing (TODO comment), always returns `true`
2. `delete(event_id)` always returns `false` — never actually removes the entry

**Files:**
- Modify: `lib/e11y/reliability/dlq/file_storage.rb`
- Modify: `features/dlq.feature` (remove @wip from lines 25 and 34)

**Step 1: Read file_storage.rb completely**

Read `lib/e11y/reliability/dlq/file_storage.rb`. Pay attention to:
- How events are stored (JSONL format, each line is a JSON object)
- The `store` method — shows the write format
- The `replay` method (stub around lines 143-157)
- The `delete` method (stub around lines 187-193)
- How to read all entries (there's likely a `read_all_entries` or `all_events` method)
- What fields each stored entry has (`:id`, `:event_data`, etc.)

**Step 2: Read the step definitions for DLQ**

```bash
grep -n -A5 "replay\|replayed" features/step_definitions/dlq_steps.rb
```

This shows what "replay" is expected to DO — likely dispatch the event and confirm it arrives in an adapter.

**Step 3: Remove @wip from dlq.feature lines 25 and 34**

**Step 4: Run to confirm they fail**

```bash
bundle exec cucumber features/dlq.feature:25 features/dlq.feature:34
```

Expected: 2 scenarios FAIL.

**Step 5: Implement `replay`**

Look at how `E11y::Event::Base.track` dispatches events (through pipeline). The replay should re-dispatch the stored event_data:

```ruby
def replay(event_id)
  entry = find_entry(event_id)   # use whatever read method exists
  return false unless entry

  event_data = entry[:event_data] || entry["event_data"]
  # Re-dispatch through pipeline — find the correct method by reading how
  # Event::Base.track ends up calling adapters
  E11y.configuration.pipeline.call(event_data)
  true
rescue => e
  E11y.logger.error("DLQ replay failed for #{event_id}: #{e.message}")
  false
end
```

**Note:** The exact dispatch call depends on the pipeline API. Read how `Event::Base.track` dispatches (in `lib/e11y/event/base.rb`) and use the same mechanism.

**Step 6: Implement `delete`**

Read all entries, reject the one with matching id, rewrite the file:

```ruby
def delete(event_id)
  all_lines = File.readlines(file_path).map(&:chomp).reject(&:empty?)
  original_count = all_lines.length

  remaining = all_lines.reject do |line|
    entry = JSON.parse(line, symbolize_names: true)
    entry[:id].to_s == event_id.to_s
  end

  return false if remaining.length == original_count

  File.write(file_path, remaining.join("\n") + (remaining.empty? ? "" : "\n"))
  true
rescue => e
  E11y.logger.error("DLQ delete failed for #{event_id}: #{e.message}")
  false
end
```

**Important:** Adapt to how the file is actually written — read `store` to know the exact JSON format.

**Step 7: Run to confirm both pass**

```bash
bundle exec cucumber features/dlq.feature:25 features/dlq.feature:34
```

Expected: 2 scenarios PASS.

**Step 8: Run full DLQ feature**

```bash
bundle exec cucumber features/dlq.feature
```

Expected: all scenarios pass.

**Step 9: Commit**

```bash
git add lib/e11y/reliability/dlq/file_storage.rb features/dlq.feature
git commit -m "fix: DLQ FileStorage implements replay dispatch and delete rewrite"
```

---

### Task 6: Implement E11y.track

**Scenario:** `features/event_tracking.feature` line 33

**Bug:** `lib/e11y.rb` around line 66-69:
```ruby
def track(event)
  raise NotImplementedError, "E11y.track will be implemented in Phase 1"
end
```

The integration test step does:
```ruby
event_instance = Events::OrderCreated.new
E11y.track(event_instance)
```

`Events::OrderCreated` has all-optional fields, so dispatching with empty payload `{}` will pass validation.

**Files:**
- Modify: `lib/e11y.rb` (the `track` method, ~line 66)
- Modify: `features/event_tracking.feature` (remove @wip from line 33)

**Step 1: Read lib/e11y.rb lines 60-85**

Find the `track` method stub. Also note the surrounding API methods to understand the module structure.

**Step 2: Read Event::Base.track**

Read `lib/e11y/event/base.rb` lines 70-140 to understand how `Base.track(**payload)` works — it builds an `event_data` Hash and runs it through the pipeline. Our `E11y.track` just needs to delegate to this.

**Step 3: Remove @wip from event_tracking.feature:33**

**Step 4: Run to confirm it fails**

```bash
bundle exec cucumber features/event_tracking.feature:33
```

Expected: FAIL with `NotImplementedError`.

**Step 5: Implement E11y.track**

Replace the `NotImplementedError` stub:

```ruby
def track(event_or_class, **payload)
  event_class = event_or_class.is_a?(Class) ? event_or_class : event_or_class.class
  event_class.track(**payload)
end
```

This handles both:
- `E11y.track(event_instance)` → gets class from instance, calls `EventClass.track()`
- `E11y.track(EventClass, order_id: "x")` → calls `EventClass.track(order_id: "x")`

**Step 6: Run to confirm it passes**

```bash
bundle exec cucumber features/event_tracking.feature:33
```

Expected: PASS.

**Step 7: Run full feature**

```bash
bundle exec cucumber features/event_tracking.feature
```

Expected: all scenarios pass.

**Step 8: Commit**

```bash
git add lib/e11y.rb features/event_tracking.feature
git commit -m "feat: implement E11y.track delegating to event class"
```

---

### Task 7: Fix Railtie auto-disable in test environment

**Scenario:** `features/rails_integration.feature` line 18

**Bug:** `lib/e11y.rb` around line 130 — the configuration object initializes `@enabled = true`. The Railtie has a guard:
```ruby
config.enabled = !Rails.env.test? if config.enabled.nil?
```
But since `@enabled` is already `true` (not `nil`), the nil-check never fires and E11y stays enabled in test environments.

**Files:**
- Modify: `lib/e11y.rb` (around line 130 — find `@enabled = true` inside the config initializer)
- Modify: `features/rails_integration.feature` (remove @wip from line 18)

**Step 1: Find the exact location**

```bash
grep -n "@enabled = true" lib/e11y.rb
```

Confirm it's inside a config initializer method (not the Railtie).

**Step 2: Remove @wip from rails_integration.feature:18**

**Step 3: Run to confirm it fails**

```bash
bundle exec cucumber features/rails_integration.feature:18
```

Expected: FAIL — E11y is active in test env when it should auto-disable.

**Step 4: Change the default**

Change `@enabled = true` to `@enabled = nil` in the config class initializer.

The Railtie will then execute `config.enabled = !Rails.env.test? if config.enabled.nil?` and properly set `false` in test environments.

**Step 5: Check other integration tests still pass**

Most other integration tests explicitly enable E11y in their background steps (e.g., `Given the application is running` likely re-enables E11y). Run a few:

```bash
bundle exec cucumber features/event_tracking.feature features/pii_filtering.feature
```

If they now fail because E11y is disabled, read those background step definitions — they should be explicitly enabling E11y. If not, the fix is to add explicit enablement in the background steps (not to revert our change).

**Step 6: Run rails_integration feature**

```bash
bundle exec cucumber features/rails_integration.feature
```

Expected: all scenarios pass.

**Step 7: Commit**

```bash
git add lib/e11y.rb features/rails_integration.feature
git commit -m "fix: E11y config defaults enabled=nil so Railtie auto-disables in test env"
```

---

### Task 8: Add RateLimiting and EventSlo to default pipeline

**Scenarios:** `features/default_pipeline.feature` lines 36, 42, 61

**Bug:** `lib/e11y.rb` — the `configure_default_pipeline` method (around lines 201-215) doesn't add `E11y::Middleware::RateLimiting` or `E11y::Middleware::EventSlo` to the pipeline.

**Files:**
- Modify: `lib/e11y.rb` (configure_default_pipeline method)
- Modify: `features/default_pipeline.feature` (remove @wip from lines 36, 42, 61)

**Step 1: Read the middleware ordering ADR**

```bash
cat docs/ADR-015-middleware-order.md
```

This is **critical** — wrong middleware order breaks the pipeline. Note where RateLimiting and EventSlo belong in the chain.

**Step 2: Read configure_default_pipeline**

```bash
grep -n "configure_default_pipeline\|pipeline.use\|Middleware::" lib/e11y.rb | head -30
```

See which middleware are already in the pipeline and their order.

**Step 3: Read the middleware constructors**

Check if `RateLimiting` and `EventSlo` require any arguments:

```bash
head -30 lib/e11y/middleware/rate_limiting.rb
head -30 lib/e11y/middleware/event_slo.rb
```

**Step 4: Remove @wip from the 3 scenarios in default_pipeline.feature**

**Step 5: Run to confirm they fail**

```bash
bundle exec cucumber features/default_pipeline.feature:36 features/default_pipeline.feature:42 features/default_pipeline.feature:61
```

Expected: 3 scenarios FAIL.

**Step 6: Add the missing middleware**

In `lib/e11y.rb`, in `configure_default_pipeline`, add `RateLimiting` and `EventSlo` in the position specified by ADR-015 (likely after `Routing`):

```ruby
@pipeline.use E11y::Middleware::RateLimiting
@pipeline.use E11y::Middleware::EventSlo
```

**Step 7: Run to confirm all 3 pass**

```bash
bundle exec cucumber features/default_pipeline.feature
```

Expected: all scenarios pass.

**Step 8: Run integration suite broadly to catch regressions**

```bash
bundle exec cucumber
```

If any previously-passing scenario breaks, debug: the new middleware might be processing events it shouldn't. Check their `call` implementations — they should pass through by default when not triggered.

**Step 9: Commit**

```bash
git add lib/e11y.rb features/default_pipeline.feature
git commit -m "fix: add RateLimiting and EventSlo middleware to default pipeline"
```

---

### Task 9: Fix PII filtering — word boundaries and :allow strategy bypass

**Scenarios:** `features/pii_filtering.feature` lines 56, 78, 87

**Two bugs:**

**Bug A** — `lib/e11y/pii/patterns.rb` line ~18:
```ruby
PASSWORD_FIELDS = /password|passwd|pwd|secret|token|api[_-]?key/i
```
This matches substrings: a field named `process_token_renewal` matches `token` → value gets masked/hashed even though it's not a sensitive field.

**Bug B** — `lib/e11y/middleware/pii_filter.rb` in `apply_deep_filtering`:
After `apply_field_strategies` runs (which applies `:allow` for explicitly-allowed fields), the code calls `apply_pattern_filtering` which re-scans ALL fields including explicitly-allowed ones, overriding the `:allow` strategy.

**Files:**
- Modify: `lib/e11y/pii/patterns.rb` (line ~18)
- Modify: `lib/e11y/middleware/pii_filter.rb` (apply_deep_filtering method)
- Modify: `features/pii_filtering.feature` (remove @wip from lines 56, 78, 87)

**Step 1: Read both files**

```bash
cat lib/e11y/pii/patterns.rb
grep -n "apply_deep_filtering\|apply_field_strategies\|apply_pattern_filtering" lib/e11y/middleware/pii_filter.rb
```

Then read the full `apply_deep_filtering` method in `lib/e11y/middleware/pii_filter.rb`.

**Step 2: Remove @wip from the 3 scenarios**

**Step 3: Run to confirm they fail**

```bash
bundle exec cucumber features/pii_filtering.feature:56 features/pii_filtering.feature:78 features/pii_filtering.feature:87
```

Expected: 3 scenarios FAIL.

**Step 4: Fix Bug A — add word boundaries**

In `lib/e11y/pii/patterns.rb`, change:
```ruby
PASSWORD_FIELDS = /password|passwd|pwd|secret|token|api[_-]?key/i
```
to:
```ruby
PASSWORD_FIELDS = /\b(?:password|passwd|pwd|secret|token|api[_-]?key)\b/i
```

The `\b` word boundary anchors prevent matching inside longer field names.

**Step 5: Fix Bug B — skip pattern filtering for explicitly-configured fields**

In `lib/e11y/middleware/pii_filter.rb`, modify `apply_deep_filtering` to collect field names that have explicit strategies and pass them as exclusions to `apply_pattern_filtering`:

```ruby
def apply_deep_filtering(payload, config)
  # Collect fields with any explicit strategy (including :allow)
  configured_fields = Set.new(
    (config.field_strategies || {}).keys.map { |k| k.to_s }
  )

  apply_field_strategies(payload, config)
  apply_pattern_filtering(payload, config, skip_fields: configured_fields)
end
```

Then in `apply_pattern_filtering`, add a `skip_fields:` parameter and skip those keys:

```ruby
def apply_pattern_filtering(payload, config, skip_fields: Set.new)
  payload.each do |key, value|
    next if skip_fields.include?(key.to_s)
    # ... existing pattern matching logic unchanged ...
  end
end
```

**Important:** Read the actual implementations before editing — adapt to the real code structure. The key invariant: fields with `:allow` (or any explicit strategy) must not be touched by pattern scanning.

**Step 6: Run to confirm all 3 pass**

```bash
bundle exec cucumber features/pii_filtering.feature
```

Expected: all scenarios pass.

**Step 7: Commit**

```bash
git add lib/e11y/pii/patterns.rb lib/e11y/middleware/pii_filter.rb features/pii_filtering.feature
git commit -m "fix: PII — word boundaries on PASSWORD_FIELDS, :allow strategy not overridden by pattern scan"
```

---

### Task 10: Fix AuditEvent preset — empty class_eval

**Scenarios:** `features/presets.feature` lines 18 and 26

**Bug:** `lib/e11y/presets/audit_event.rb` around lines 39-47:
```ruby
def self.included(base)
  base.class_eval do
    # Empty block — audit_event true is never called!
  end
end
```

**Files:**
- Modify: `lib/e11y/presets/audit_event.rb`
- Modify: `features/presets.feature` (remove @wip from lines 18 and 26)

**Step 1: Read audit_event.rb and understand the DSL**

Read `lib/e11y/presets/audit_event.rb` completely.

Also confirm that `audit_event` is a valid DSL macro in `lib/e11y/event/base.rb`:
```bash
grep -n "def audit_event\|def self.audit_event" lib/e11y/event/base.rb
```

**Step 2: Remove @wip from presets.feature lines 18 and 26**

**Step 3: Run to confirm they fail**

```bash
bundle exec cucumber features/presets.feature:18 features/presets.feature:26
```

Expected: 2 scenarios FAIL.

**Step 4: Fix the class_eval**

```ruby
def self.included(base)
  base.class_eval do
    audit_event true
  end
end
```

**Step 5: Run to confirm they pass**

```bash
bundle exec cucumber features/presets.feature
```

Expected: all scenarios pass.

**Step 6: Commit**

```bash
git add lib/e11y/presets/audit_event.rb features/presets.feature
git commit -m "fix: AuditEvent preset calls audit_event true in class_eval"
```

---

### Task 11: Fix AuditEncrypted — stable encryption key

**Scenario:** `features/audit_encrypted.feature` line 36

**Bug:** `lib/e11y/adapters/audit_encrypted.rb` around lines 218-230:
```ruby
def default_encryption_key
  # ...
  OpenSSL::Random.random_bytes(32)  # BUG: new key on every instantiation!
end
```

Every time the adapter is instantiated, a different key is generated. Events encrypted with one boot's key can't be verified by another boot's key.

**Files:**
- Modify: `lib/e11y/adapters/audit_encrypted.rb` (default_encryption_key method)
- Modify: `features/audit_encrypted.feature` (remove @wip from line 36)

**Step 1: Read audit_encrypted.rb lines 210-240**

Understand the full context of `default_encryption_key` and how it's called.

**Step 2: Remove @wip from audit_encrypted.feature:36**

**Step 3: Run to confirm it fails**

```bash
bundle exec cucumber features/audit_encrypted.feature:36
```

Expected: FAIL.

**Step 4: Fix default_encryption_key to use a stable key**

```ruby
def default_encryption_key
  # Use ENV var if provided (required in production)
  env_key = ENV["E11Y_AUDIT_ENCRYPTION_KEY"]
  return env_key if env_key

  # In production without ENV var, raise a clear error
  if defined?(::Rails) && ::Rails.env.production?
    raise E11y::ConfigurationError,
      "E11Y_AUDIT_ENCRYPTION_KEY must be set in production. " \
      "Generate with: openssl rand -hex 32"
  end

  # Development/test: derive a stable key from a fixed seed
  # This is NOT secure for production — only for development/testing
  OpenSSL::PKCS5.pbkdf2_hmac_sha1(
    "e11y-development-key-not-for-production",
    "e11y-static-salt",
    1000,
    32
  )
end
```

**Step 5: Run to confirm it passes**

```bash
bundle exec cucumber features/audit_encrypted.feature
```

Expected: all scenarios pass.

**Step 6: Commit**

```bash
git add lib/e11y/adapters/audit_encrypted.rb features/audit_encrypted.feature
git commit -m "fix: AuditEncrypted uses stable derived dev key instead of random bytes per instance"
```

---

### Task 12: Fix Loki healthy? — perform real HTTP check

**Scenario:** `features/adapter_configurations.feature` line 51

**Bug:** `lib/e11y/adapters/loki.rb` around lines 161-163:
```ruby
def healthy?
  @connection&.respond_to?(:get)  # Always true — Faraday objects always respond to :get
end
```

**Files:**
- Modify: `lib/e11y/adapters/loki.rb`
- Modify: `features/adapter_configurations.feature` (remove @wip from line 51)

**Step 1: Read loki.rb around the healthy? method and connection setup**

```bash
grep -n "def healthy\|@connection\|def initialize\|faraday\|base_url" lib/e11y/adapters/loki.rb | head -20
```

Understand how `@connection` is built (Faraday) and what base URL it uses.

**Step 2: Remove @wip from adapter_configurations.feature:51**

**Step 3: Run to confirm it fails**

```bash
bundle exec cucumber features/adapter_configurations.feature:51
```

Expected: FAIL — `healthy?` returns `true` for unreachable host `http://localhost:19998`.

**Step 4: Fix healthy?**

```ruby
def healthy?
  return false unless @connection

  response = @connection.get("/ready")
  response.status == 200
rescue Faraday::ConnectionFailed, Faraday::TimeoutError
  false
rescue => e
  E11y.logger.warn("Loki health check error: #{e.class}: #{e.message}")
  false
end
```

Note: The Loki readiness endpoint is `/ready` (standard Loki API). If the scenario uses a different endpoint, check the step definitions:
```bash
grep -n "healthy\|/ready\|/health" features/step_definitions/
```

**Step 5: Run to confirm it passes**

```bash
bundle exec cucumber features/adapter_configurations.feature
```

Expected: all scenarios pass (including the non-@wip "should not raise" scenario — rescue ensures no exception).

**Step 6: Commit**

```bash
git add lib/e11y/adapters/loki.rb features/adapter_configurations.feature
git commit -m "fix: Loki#healthy? performs real HTTP GET to /ready instead of duck-type check"
```

---

### Task 13: Fix Stdout adapter — support :format config key

**Scenario:** `features/adapter_configurations.feature` line 20

**Bug:** The Stdout adapter reads the `:pretty_print` config key but the documented API uses `:format`. When a user passes `format: :compact`, the adapter ignores it and uses the `:pretty_print` default (true = multi-line).

**Files:**
- Modify: `lib/e11y/adapters/stdout.rb`
- Modify: `features/adapter_configurations.feature` (remove @wip from line 20)

**Step 1: Read stdout.rb**

```bash
cat lib/e11y/adapters/stdout.rb
```

Find where `pretty_print` is read from config. Find where the output format is determined.

**Step 2: Read the failing scenario**

```bash
sed -n '17,27p' features/adapter_configurations.feature
```

Confirm: passing `format: :compact` should produce single-line JSON output.

**Step 3: Remove @wip from adapter_configurations.feature:20**

**Step 4: Run to confirm it fails**

```bash
bundle exec cucumber features/adapter_configurations.feature:20
```

Expected: FAIL — output is multi-line despite `format: :compact`.

**Step 5: Fix the adapter**

Make the adapter accept both `:format` and `:pretty_print`:

```ruby
def pretty_print?
  # Support :format key (:compact means no pretty print) in addition to :pretty_print
  if @options.key?(:format)
    @options[:format] != :compact
  else
    @options.fetch(:pretty_print, true)
  end
end
```

Then use `pretty_print?` everywhere instead of reading `@options[:pretty_print]` directly.

**Important:** Read the actual code — the method/ivar names may differ. Adapt accordingly.

**Step 6: Run to confirm it passes**

```bash
bundle exec cucumber features/adapter_configurations.feature
```

Expected: all scenarios pass.

**Step 7: Commit**

```bash
git add lib/e11y/adapters/stdout.rb features/adapter_configurations.feature
git commit -m "fix: Stdout adapter supports :format key (:compact for single-line output)"
```

---

### Task 14: Fix auto-metrics — add NullBackend

**Scenarios:** `features/auto_metrics.feature` lines 36 and 43

**Bug:** `lib/e11y/metrics.rb` — `E11y::Metrics.backend` returns `nil` when no Yabeda adapter is configured. All `Metrics.increment` / `Metrics.histogram` calls silently fail or raise `NoMethodError` on nil.

**Files:**
- Modify: `lib/e11y/metrics.rb`
- Modify: `features/auto_metrics.feature` (remove @wip from lines 36 and 43)

**Step 1: Read lib/e11y/metrics.rb completely**

Understand:
- The `detect_backend` method
- The `backend` accessor
- The interface backends must implement (likely `increment`, `histogram`, `gauge`, `counter`)

**Step 2: Remove @wip from auto_metrics.feature lines 36 and 43**

**Step 3: Run to confirm they fail**

```bash
bundle exec cucumber features/auto_metrics.feature:36 features/auto_metrics.feature:43
```

Expected: 2 scenarios FAIL.

**Step 4: Define NullBackend**

Add inside `lib/e11y/metrics.rb` (or at the top of the file):

```ruby
module E11y
  module Metrics
    # Null backend — silently no-ops all metric operations.
    # Used when no real metrics backend (Yabeda, Prometheus) is configured.
    class NullBackend
      def increment(_metric, _labels = {}); end
      def histogram(_metric, _value, _labels = {}, **_opts); end
      def gauge(_metric, _value, _labels = {}); end
      def counter(_metric, _labels = {}); end
    end
  end
end
```

**Step 5: Use NullBackend as fallback**

In `lib/e11y/metrics.rb`, find the `backend` method or wherever `detect_backend` result is used. Change it to:

```ruby
def backend
  @backend ||= detect_backend || NullBackend.new
end
```

**Step 6: Run to confirm both pass**

```bash
bundle exec cucumber features/auto_metrics.feature
```

Expected: all scenarios pass.

**Step 7: Commit**

```bash
git add lib/e11y/metrics.rb features/auto_metrics.feature
git commit -m "fix: E11y::Metrics defaults to NullBackend instead of nil"
```

---

### Task 15: Fix RequestScopedBuffer — implement flush_event

**Scenarios:** `features/request_scoped_buffer.feature` lines 28, 36, 46

**Bug:** `lib/e11y/buffers/request_scoped_buffer.rb` line 226 — `flush_event` is a stub:
```ruby
def flush_event(_event_data, target: nil)
  # Placeholder — only increments a metric, never writes to adapters!
  increment_metric("e11y.request_buffer.event_flushed")
end
```

Buffered debug events are permanently lost on request failure.

**Files:**
- Modify: `lib/e11y/buffers/request_scoped_buffer.rb` (flush_event method)
- Modify: `features/request_scoped_buffer.feature` (remove @wip from lines 28, 36, 46)

**Step 1: Read request_scoped_buffer.rb completely**

Read `lib/e11y/buffers/request_scoped_buffer.rb` fully to understand:
- How `flush_event` is called (from `flush_all` or rack middleware on request end)
- How `flush_all` iterates buffered events
- How adapters are accessed (via config or injected)

**Step 2: Read how Event::Base dispatches to adapters**

Read `lib/e11y/event/base.rb` lines 80-150. Find the section after `event_data` is built — that's the dispatch mechanism `flush_event` should replicate.

**Step 3: Read the step definitions**

```bash
grep -n -B2 -A5 "debug.*adapter\|flushed.*adapter\|adapter.*debug" features/step_definitions/request_scoped_buffer_steps.rb 2>/dev/null || \
grep -rn "debug.*adapter\|flushed" features/step_definitions/
```

Confirm which adapter (InMemory) receives the flushed events and what format they arrive in.

**Step 4: Remove @wip from request_scoped_buffer.feature lines 28, 36, 46**

**Step 5: Run to confirm they fail**

```bash
bundle exec cucumber features/request_scoped_buffer.feature:28 features/request_scoped_buffer.feature:36 features/request_scoped_buffer.feature:46
```

Expected: 3 scenarios FAIL.

**Step 6: Implement flush_event**

Replace the stub with a real dispatch. Use the same mechanism as `Event::Base.track` — route through the pipeline:

```ruby
def flush_event(event_data, target: nil)
  # Dispatch through the configured pipeline so adapters receive it
  # Use the same dispatch mechanism as Event::Base.track
  E11y.configuration.pipeline.call(event_data)
rescue => e
  E11y.logger.error("RequestScopedBuffer flush failed for #{event_data[:event_name]}: #{e.message}")
ensure
  increment_metric("e11y.request_buffer.event_flushed")
end
```

**Note:** If `E11y.configuration.pipeline.call` isn't the right API, read `lib/e11y/pipeline/builder.rb` and `lib/e11y.rb` to find the correct call to dispatch an already-built `event_data` hash through the pipeline.

**Step 7: Run to confirm all 3 pass**

```bash
bundle exec cucumber features/request_scoped_buffer.feature
```

Expected: all scenarios pass.

**Step 8: Commit**

```bash
git add lib/e11y/buffers/request_scoped_buffer.rb features/request_scoped_buffer.feature
git commit -m "fix: RequestScopedBuffer flush_event dispatches events through pipeline"
```

---

### Task 16: Fix SLO tracking — default enabled + Tracker.status

**Scenarios:** `features/slo_tracking.feature` lines 21, 28, 52

**Three bugs:**

1. **BUG-005** (`lib/e11y.rb` — `SLOTrackingConfig`): `@enabled = false` by default, but README says "Zero-Config SLO Tracking". Fix: change default to `true`.

2. **BUG-006** (`lib/e11y/slo/tracker.rb`): `E11y::SLO::Tracker.status` doesn't exist → `NoMethodError`. Fix: add a `.status` class method that returns accumulated request data.

3. **BUG-007** (already fixed in Task 8): `EventSlo` middleware not in default pipeline. The Task 8 fix covers this.

**⚠️ Important conflict:** `slo_tracking.feature` line 65 (currently passing, NOT @wip) says:
```gherkin
Then E11y.configuration.slo_tracking.enabled should be false
```
This scenario documents the buggy state. After fixing BUG-005, this scenario will break. **We must update it** along with fixing the bug.

**Files:**
- Modify: `lib/e11y.rb` (SLOTrackingConfig — find `@enabled = false`)
- Modify: `lib/e11y/slo/tracker.rb` (add `.status` + request accumulation)
- Modify: `features/slo_tracking.feature` (remove @wip from lines 21, 28, 52; update scenario at line 65)

**Step 1: Read slo_tracking.feature carefully**

```bash
cat features/slo_tracking.feature
```

Identify all scenarios. In particular, read the non-@wip scenario at line ~65 that says `enabled should be false` — we'll update it.

**Step 2: Find SLOTrackingConfig in lib/e11y.rb**

```bash
grep -n "SLOTrackingConfig\|@enabled = false\|slo_tracking" lib/e11y.rb | head -20
```

**Step 3: Read lib/e11y/slo/tracker.rb**

It currently has `track_http_request` and `track_background_job` but no `status` method.

**Step 4: Read the step definitions for Tracker.status**

```bash
grep -n -A5 "Tracker.status\|slo status" features/step_definitions/
```

Understand: what key format does the returned Hash use? (likely `"orders#create"` based on controller/action labels in `track_http_request`)

**Step 5: Remove @wip from slo_tracking.feature lines 21, 28, 52**

**Step 6: Update the conflicting non-@wip scenario at line ~65**

The scenario currently says `enabled should be false`. Update it to reflect the new desired behavior (`enabled should be true` by default). Also update the last step "And enabling SLO tracking requires setting slo_tracking.enabled to true" to "And SLO tracking can be disabled by setting slo_tracking.enabled to false".

**Step 7: Run to see current state of failures**

```bash
bundle exec cucumber features/slo_tracking.feature
```

Expected: multiple failures (BUG-005 and BUG-006 still present).

**Step 8: Fix BUG-005 — change SLOTrackingConfig default**

In `lib/e11y.rb`, inside `SLOTrackingConfig#initialize`, change `@enabled = false` to `@enabled = true`.

**Step 9: Fix BUG-006 — add Tracker.status**

In `lib/e11y/slo/tracker.rb`, add request accumulation and the `.status` method:

```ruby
module Tracker
  class << self
    def request_log
      @request_log ||= {}
    end

    def track_http_request(controller:, action:, status:, duration_ms:)
      return unless enabled?

      key = "#{controller}##{action}"
      request_log[key] ||= { total: 0, statuses: {} }
      request_log[key][:total] += 1
      status_category = normalize_status(status)
      request_log[key][:statuses][status_category] ||= 0
      request_log[key][:statuses][status_category] += 1

      # ... keep all existing E11y::Metrics calls below ...
    end

    # Returns accumulated SLO data keyed by "controller#action"
    def status
      request_log.dup
    end

    def reset!
      @request_log = nil
    end

    # ... keep existing enabled?, track_background_job, normalize_status ...
  end
end
```

**Important:** Don't remove existing code — add the accumulation to `track_http_request` and add `status` and `reset!` as new methods.

**Step 10: Ensure reset! is called in background setup**

The feature has `Given SLO tracking is reset to its default state` — find that step definition and confirm it calls `Tracker.reset!` or otherwise resets the log.

**Step 11: Run to confirm all pass**

```bash
bundle exec cucumber features/slo_tracking.feature
```

Expected: all scenarios pass.

**Step 12: Commit**

```bash
git add lib/e11y.rb lib/e11y/slo/tracker.rb features/slo_tracking.feature
git commit -m "fix: SLO tracking defaults enabled=true, adds Tracker.status with request accumulation"
```

---

### Final Task: Full verification and PR

**Step 1: Run all unit tests**

```bash
rake spec:unit
```

Expected: all pass. Our changes are in `lib/` — confirm no unit test regressions.

**Step 2: Run all integration tests**

```bash
rake spec:integration
```

Expected: all pass.

**Step 3: Run full Cucumber suite**

```bash
bundle exec cucumber 2>&1 | tail -20
```

Expected: 0 @wip scenarios remaining, all scenarios pass.

**Step 4: Lint with autocorrect**

```bash
bundle exec rubocop -a
git add -u
git diff --cached --stat
```

If rubocop changed files, commit:
```bash
git commit -m "style: rubocop autocorrect after @wip bug fixes"
```

**Step 5: Verify current branch and base**

```bash
git log --oneline feat/integration-testing..HEAD | head -20
```

Should show all the fix commits from this plan.

**Step 6: Create pull request**

```bash
gh pr create \
  --base feat/integration-testing \
  --head feat/fix-wip-bugs \
  --title "fix: resolve all @wip bugs — 30+ Cucumber scenarios now passing" \
  --body "$(cat <<'EOF'
## Summary

Fixes all known @wip-tagged bugs across 16 feature areas:

- **LoadMonitor off-by-one** (adaptive_sampling): `>=` → `>` for normal threshold
- **Versioning** (event_versioning): preserve custom `event_name` overrides
- **InMemory adapter** (in_memory_adapter): add `last_event`, `clear`, positional `event_count`
- **DLQ FileStorage** (dlq): implement `replay` dispatch and `delete` rewrite
- **E11y.track** (event_tracking): implement by delegating to event class
- **Railtie @enabled** (rails_integration): default `nil` so test env auto-disables
- **Default pipeline** (default_pipeline): add `RateLimiting` and `EventSlo` middleware
- **PII filtering** (pii_filtering): word boundaries on `PASSWORD_FIELDS`, respect `:allow` strategy
- **AuditEvent preset** (presets): call `audit_event true` in `class_eval`
- **AuditEncrypted** (audit_encrypted): stable derived key for dev/test
- **Loki healthy?** (adapter_configurations): real HTTP `/ready` check
- **Stdout adapter** (adapter_configurations): support `:format` config key
- **Auto-metrics** (auto_metrics): `NullBackend` fallback instead of `nil`
- **SLO tracking** (slo_tracking): default `enabled=true`, add `Tracker.status`
- **RequestScopedBuffer** (request_scoped_buffer): implement `flush_event` dispatch

## Test plan

- [ ] `rake spec:unit` — all unit tests pass
- [ ] `rake spec:integration` — all integration tests pass
- [ ] `bundle exec cucumber` — 0 @wip scenarios, all pass
- [ ] `bundle exec rubocop` — no offenses

🤖 Generated with [Claude Code](https://claude.ai/claude-code)
EOF
)"
```

---

## Implementation Notes

### Running individual Cucumber scenarios

```bash
# Run one scenario by line number
bundle exec cucumber features/adaptive_sampling.feature:29

# Run multiple scenarios
bundle exec cucumber features/adaptive_sampling.feature:29 features/adaptive_sampling.feature:39

# Run entire feature file
bundle exec cucumber features/adaptive_sampling.feature

# Run all features
bundle exec cucumber
```

### Checking which @wip scenarios remain

```bash
grep -rn "@wip" features/*.feature | grep -v "^Binary"
```

### Running tests after each change (quick sanity check)

```bash
# Unit tests (fast, no Rails)
rake spec:unit

# Full integration
bundle exec cucumber
```
