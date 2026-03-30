# Sentry Adapter Graceful DSN Handling — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `required:` config option to `E11y::Adapters::Sentry` so that missing DSN triggers a `warn` (not a raise) by default, while `required: true` preserves strict enforcement for production.

**Architecture:** Add `@required` and `@active` instance variables in `initialize`. Move DSN validation logic into `validate_config!` with a conditional: raise if `required: true`, warn otherwise. Skip `initialize_sentry!` when DSN is absent. `write()` returns `true` early when `@active` is false. One `warn` at init, zero noise at write time.

**Tech Stack:** Ruby 3.2+, RSpec, sentry-ruby gem (stubbed in tests).

---

### Task 1: Update `validate_config!` — conditional raise vs warn

**Files:**
- Modify: `lib/e11y/adapters/sentry.rb:113-120`
- Test: `spec/e11y/adapters/sentry_spec.rb:175-178`

**Step 1: Run the existing "requires :dsn" test to confirm current behavior**

```bash
bundle exec rspec spec/e11y/adapters/sentry_spec.rb -e "requires :dsn" --format documentation
```

Expected: 1 example, PASS (raises `ArgumentError`).

**Step 2: Replace the existing test with a full `"when DSN is absent"` describe block**

In `spec/e11y/adapters/sentry_spec.rb`, find the `describe "Configuration"` block (around line 175). Replace:

```ruby
it "requires :dsn parameter" do
  expect { described_class.new({}) }.to raise_error(ArgumentError, /requires :dsn/)
end
```

With:

```ruby
describe "when DSN is absent" do
  before do
    allow(Sentry).to receive(:initialized?).and_return(false)
  end

  it "raises ArgumentError when required: true" do
    expect { described_class.new(required: true) }
      .to raise_error(ArgumentError, /requires :dsn/)
  end

  it "does not raise when required: false (default)" do
    expect { described_class.new({}) }.not_to raise_error
  end

  it "emits a warning to stderr when DSN is absent" do
    expect { described_class.new({}) }
      .to output(/Sentry adapter: no DSN configured/).to_stderr
  end

  it "write is a no-op returning true" do
    adapter = described_class.new({})
    expect(Sentry).not_to receive(:capture_message)
    expect(Sentry).not_to receive(:capture_exception)
    expect(Sentry).not_to receive(:add_breadcrumb)
    expect(adapter.write(error_event)).to be true
  end

  it "healthy? returns false" do
    adapter = described_class.new({})
    expect(adapter.healthy?).to be false
  end
end
```

**Step 3: Run new tests to confirm they fail**

```bash
bundle exec rspec spec/e11y/adapters/sentry_spec.rb -e "when DSN is absent" --format documentation
```

Expected: 5 examples, all FAIL (adapter still raises on nil DSN).

**Step 4: Update `validate_config!` in `lib/e11y/adapters/sentry.rb`**

Replace the existing `validate_config!` method (around line 113):

```ruby
# Validate configuration
def validate_config!
  if @dsn.nil? || @dsn.empty?
    if @required
      raise ArgumentError, "Sentry adapter requires :dsn (required: true is set)"
    else
      warn "[E11y] Sentry adapter: no DSN configured — adapter inactive. " \
           "Pass required: true to enforce DSN in production."
    end
    return
  end

  return if SEVERITY_LEVELS.include?(@severity_threshold)

  raise ArgumentError,
        "Invalid severity_threshold: #{@severity_threshold}"
end
```

**Step 5: Run new tests — expect them to partially pass**

```bash
bundle exec rspec spec/e11y/adapters/sentry_spec.rb -e "when DSN is absent" --format documentation
```

Expected: 2 pass (raise + no-raise), 1 pass (stderr), 2 fail (write + healthy? — `@active` not yet set).

---

### Task 2: Add `@required` and `@active` flags to `initialize`

**Files:**
- Modify: `lib/e11y/adapters/sentry.rb:58-67`

**Step 1: Update `initialize` in `lib/e11y/adapters/sentry.rb`**

Replace the existing `initialize` method:

```ruby
def initialize(config = {})
  @required = config.fetch(:required, false)
  @dsn = config[:dsn]
  @environment = config.fetch(:environment, "production")
  @severity_threshold = config.fetch(:severity_threshold, DEFAULT_SEVERITY_THRESHOLD)
  @send_breadcrumbs = config.fetch(:breadcrumbs, true)

  super

  if @dsn && !@dsn.empty?
    initialize_sentry!
    @active = true
  else
    @active = false
  end
end
```

Note: `super` calls `Base#initialize` which calls `validate_config!`. The `@required`, `@dsn`, `@severity_threshold` instance variables must be set before `super`.

**Step 2: Run the 5 "when DSN is absent" tests**

```bash
bundle exec rspec spec/e11y/adapters/sentry_spec.rb -e "when DSN is absent" --format documentation
```

Expected: 4 pass, 1 fail (`healthy?` — needs `healthy?` update).

---

### Task 3: Update `write` and `healthy?`

**Files:**
- Modify: `lib/e11y/adapters/sentry.rb:72-89` (write)
- Modify: `lib/e11y/adapters/sentry.rb:106-108` (healthy?)

**Step 1: Add early return to `write`**

At the top of the `write` method, add `return true unless @active` as first line:

```ruby
def write(event_data)
  return true unless @active

  severity = event_data[:severity]
  # ... rest unchanged
end
```

**Step 2: Update `healthy?`**

Replace:

```ruby
def healthy?
  ::Sentry.initialized?
end
```

With:

```ruby
def healthy?
  @active && ::Sentry.initialized?
end
```

**Step 3: Run all 5 "when DSN is absent" tests**

```bash
bundle exec rspec spec/e11y/adapters/sentry_spec.rb -e "when DSN is absent" --format documentation
```

Expected: 5 examples, all PASS.

**Step 4: Run the full Sentry spec to confirm no regressions**

```bash
bundle exec rspec spec/e11y/adapters/sentry_spec.rb --format documentation
```

Expected: all existing examples pass + 5 new = total count increases by 4 (replaced 1, added 5).

**Step 5: Commit**

```bash
git add lib/e11y/adapters/sentry.rb spec/e11y/adapters/sentry_spec.rb
git commit -m "feat: Sentry adapter graceful DSN handling (required: option)

- required: false (default) — warn at init, adapter inactive, write no-ops
- required: true — original strict raise for production enforcement
- healthy? returns false when DSN absent
- Closes #22"
```

---

### Task 4: Update `docs/QUICK-START.md`

**Files:**
- Modify: `docs/QUICK-START.md`

**Step 1: Find the Sentry section in QUICK-START.md**

```bash
grep -n -i "sentry" docs/QUICK-START.md | head -20
```

**Step 2: Add "Enforcing Sentry in production" subsection**

Locate the Sentry adapter documentation block. After the existing Sentry configuration example, add:

```markdown
#### Enforcing Sentry in production

By default, the adapter starts inactive (with a warning) if `SENTRY_DSN` is absent —
useful for Docker builds and CI pipelines where secrets are unavailable.

To make a missing DSN a hard error at boot (recommended for production):

```ruby
config.adapters[:sentry] = E11y::Adapters::Sentry.new(
  dsn: ENV["SENTRY_DSN"],
  required: Rails.env.production?  # raises ArgumentError at boot if DSN missing in prod
)
```

If you see no events in Sentry, check:
1. `SENTRY_DSN` is set in the running environment
2. Adapter is healthy: `E11y.configuration.adapters[:sentry].healthy?`
3. Boot logs for `[E11y] Sentry adapter: no DSN configured` warning
```

**Step 3: Run unit tests to confirm no breakage**

```bash
bundle exec rspec spec/e11y/adapters/sentry_spec.rb --format progress
```

Expected: all green.

**Step 4: Commit**

```bash
git add docs/QUICK-START.md
git commit -m "docs: Sentry adapter — document required: option and production enforcement"
```

---

### Task 5: Run full test suite and verify

**Step 1: Run all unit tests**

```bash
bundle exec rake spec:unit
```

Expected: all green, 0 failures.

**Step 2: Check for any other tests referencing the old Sentry DSN raise behavior**

```bash
grep -rn "requires :dsn\|Sentry.*ArgumentError\|ArgumentError.*Sentry" spec/
```

Expected: no matches (the old test was replaced in Task 1).

**Step 3: Final commit if clean**

If no further changes needed, the branch is ready for PR.

```bash
git log --oneline -5
```
