# Unified DevLog Routing in Development — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Auto-alias `:logs` and `:errors_tracker` adapter slots to the DevLog instance in development, so events never silently drop and TUI/Overlay/MCP work out of the box.

**Architecture:** Split `e11y.setup_development` into two independent Railtie initializers — one for adapter registration + slot aliasing (dev only), one for middleware insertion (dev only, always runs regardless of custom `:dev_log`). Extract the aliasing logic into a testable class method `E11y::Railtie.setup_development_adapters`.

**Tech Stack:** Ruby, Rails Railtie, RSpec (unit + integration). No new dependencies.

---

### Task 1: Write failing unit tests for slot aliasing logic

**Files:**
- Modify: `spec/e11y/railtie_unit_spec.rb` (append new `describe` block)

**Step 1: Write the failing tests**

Append this describe block at the end of `spec/e11y/railtie_unit_spec.rb` (before the final closing `end`):

```ruby
describe ".setup_development_adapters" do
  let(:dev_log) { instance_double("E11y::Adapters::DevLog") }

  before { E11y.reset! }

  it "registers :dev_log adapter" do
    E11y::Railtie.setup_development_adapters(dev_log)
    expect(E11y.config.adapters[:dev_log]).to eq(dev_log)
  end

  it "aliases :logs slot to dev_log when unset" do
    E11y::Railtie.setup_development_adapters(dev_log)
    expect(E11y.config.adapters[:logs]).to eq(dev_log)
  end

  it "aliases :errors_tracker slot to dev_log when unset" do
    E11y::Railtie.setup_development_adapters(dev_log)
    expect(E11y.config.adapters[:errors_tracker]).to eq(dev_log)
  end

  it "does not overwrite :logs if already set by user" do
    custom = double("custom_logs_adapter")
    E11y.configure { |c| c.adapters[:logs] = custom }
    E11y::Railtie.setup_development_adapters(dev_log)
    expect(E11y.config.adapters[:logs]).to eq(custom)
  end

  it "does not overwrite :errors_tracker if already set by user" do
    custom = double("custom_errors_adapter")
    E11y.configure { |c| c.adapters[:errors_tracker] = custom }
    E11y::Railtie.setup_development_adapters(dev_log)
    expect(E11y.config.adapters[:errors_tracker]).to eq(custom)
  end

  it "sets fallback_adapters to [:dev_log] when still at default [:stdout]" do
    expect(E11y.config.fallback_adapters).to eq([:stdout]) # verify default
    E11y::Railtie.setup_development_adapters(dev_log)
    expect(E11y.config.fallback_adapters).to eq([:dev_log])
  end

  it "does not overwrite fallback_adapters when user changed it" do
    E11y.configure { |c| c.fallback_adapters = [:loki] }
    E11y::Railtie.setup_development_adapters(dev_log)
    expect(E11y.config.fallback_adapters).to eq([:loki])
  end
end
```

**Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/e11y/railtie_unit_spec.rb --tag '' -e "setup_development_adapters" -f doc
```

Expected: 7 failures with `undefined method 'setup_development_adapters' for E11y::Railtie`

---

### Task 2: Implement `setup_development_adapters` class method

**Files:**
- Modify: `lib/e11y/railtie.rb` — add class method after `setup_active_job`

**Step 1: Add the class method**

In `lib/e11y/railtie.rb`, after the `setup_active_job` method (around line 178), add:

```ruby
# Setup development adapter slots — aliases :logs and :errors_tracker to
# the DevLog instance unless the user has already configured those slots.
# Also updates fallback_adapters when still at the default [:stdout].
#
# @param dev_log [E11y::Adapters::DevLog] The DevLog instance to alias
# @return [void]
def self.setup_development_adapters(dev_log)
  E11y.configure do |config|
    config.register_adapter :dev_log, dev_log
    config.adapters[:logs]           ||= dev_log
    config.adapters[:errors_tracker] ||= dev_log
    config.fallback_adapters = [:dev_log] if config.fallback_adapters == [:stdout]
  end
end
```

**Step 2: Run tests to verify they pass**

```bash
bundle exec rspec spec/e11y/railtie_unit_spec.rb -e "setup_development_adapters" -f doc
```

Expected: 7 examples, 0 failures

**Step 3: Run full unit suite to catch regressions**

```bash
rake spec:unit
```

Expected: 0 failures

**Step 4: Commit**

```bash
git add lib/e11y/railtie.rb spec/e11y/railtie_unit_spec.rb
git commit -m "feat: add Railtie.setup_development_adapters — alias :logs/:errors_tracker to DevLog"
```

---

### Task 3: Split the railtie initializer

**Files:**
- Modify: `lib/e11y/railtie.rb` — replace `e11y.setup_development` with two initializers

**Step 1: Replace the existing initializer**

Find the existing block:

```ruby
# Auto-register DevLog adapter in development and test environments.
# Skipped if the user has already registered :dev_log in their initializer.
initializer "e11y.setup_development", after: :load_config_initializers do |app|
  next unless Rails.env.development? || Rails.env.test?
  next if E11y.configuration.adapters.key?(:dev_log)

  E11y.configure do |config|
    config.register_adapter :dev_log, E11y::Adapters::DevLog.new(
      path: Rails.root.join("log", "e11y_dev.jsonl"),
      max_lines: ENV.fetch("E11Y_MAX_EVENTS", "10000").to_i,
      max_size: ENV.fetch("E11Y_MAX_SIZE", "50").to_i * 1024 * 1024,
      keep_rotated: ENV.fetch("E11Y_KEEP_ROTATED", "5").to_i,
      enable_watcher: !Rails.env.test?
    )
  end

  require "e11y/middleware/dev_log_source"
  app.middleware.use E11y::Middleware::DevLogSource
end
```

Replace with:

```ruby
# Auto-register DevLog adapter and alias standard adapter slots in development.
# Only runs in development. Skipped if user already registered :dev_log.
# Slot aliasing (:logs, :errors_tracker) respects user-set values via ||=.
initializer "e11y.dev_log_adapter", after: :load_config_initializers do
  next unless Rails.env.development?
  next if E11y.configuration.adapters.key?(:dev_log)

  dev_log = E11y::Adapters::DevLog.new(
    path: Rails.root.join("log", "e11y_dev.jsonl"),
    max_lines: ENV.fetch("E11Y_MAX_EVENTS", "10000").to_i,
    max_size: ENV.fetch("E11Y_MAX_SIZE", "50").to_i * 1024 * 1024,
    keep_rotated: ENV.fetch("E11Y_KEEP_ROTATED", "5").to_i,
    enable_watcher: true
  )
  E11y::Railtie.setup_development_adapters(dev_log)
end

# Insert DevLogSource middleware in development.
# Always runs — even if user provided a custom :dev_log adapter —
# because the middleware is needed for overlay/TUI source tagging.
initializer "e11y.dev_log_middleware", after: :load_config_initializers do |app|
  next unless Rails.env.development?

  require "e11y/middleware/dev_log_source"
  app.middleware.use E11y::Middleware::DevLogSource
end
```

**Step 2: Run unit suite**

```bash
rake spec:unit
```

Expected: 0 failures

**Step 3: Commit**

```bash
git add lib/e11y/railtie.rb
git commit -m "refactor: split e11y.setup_development into dev_log_adapter + dev_log_middleware initializers"
```

---

### Task 4: Write failing integration test for event routing in dev

**Files:**
- Modify: `spec/integration/railtie_integration_spec.rb` — add new describe block

**Step 1: Write the failing test**

Append inside the main `RSpec.describe` block of `spec/integration/railtie_integration_spec.rb`:

```ruby
describe "development DevLog slot aliasing" do
  # Simulate what the railtie does in development: register DevLog and alias slots.
  # Integration tests run in test env, so we invoke the class method directly.
  let(:tmp_path) { Tempfile.new(["e11y_test", ".jsonl"]).path }
  let(:dev_log) do
    E11y::Adapters::DevLog.new(path: tmp_path, enable_watcher: false)
  end

  before do
    # Stash and restore adapters/fallback around each example
    @saved_adapters = E11y.configuration.adapters.dup
    @saved_fallback = E11y.configuration.fallback_adapters.dup
    E11y.configuration.adapters.delete(:dev_log)
    E11y.configuration.adapters.delete(:logs)
    E11y.configuration.adapters.delete(:errors_tracker)
    E11y.configuration.fallback_adapters = [:stdout]
    E11y::Railtie.setup_development_adapters(dev_log)
  end

  after do
    E11y.configuration.adapters.merge!(@saved_adapters)
    E11y.configuration.fallback_adapters = @saved_fallback
    File.delete(tmp_path) if File.exist?(tmp_path)
  end

  it "routes events with adapters: [:logs] to DevLog" do
    E11y::Event::Base.track(
      event_name: "test.routing",
      adapters: [:logs],
      severity: :info,
      payload: { msg: "hello" }
    )
    content = File.read(tmp_path)
    expect(content).to include("test.routing")
  end

  it "routes events with adapters: [:logs, :errors_tracker] to DevLog" do
    E11y::Event::Base.track(
      event_name: "test.error_routing",
      adapters: %i[logs errors_tracker],
      severity: :error,
      payload: { msg: "boom" }
    )
    content = File.read(tmp_path)
    expect(content).to include("test.error_routing")
  end

  it "routes unrouted events to DevLog via fallback" do
    E11y::Event::Base.track(
      event_name: "test.fallback",
      severity: :info,
      payload: { msg: "fallback" }
    )
    content = File.read(tmp_path)
    expect(content).to include("test.fallback")
  end
end
```

**Step 2: Run to verify failure**

```bash
INTEGRATION=true bundle exec rspec spec/integration/railtie_integration_spec.rb -e "development DevLog" -f doc
```

Expected: 3 failures (dev_log not set up, events not written)

---

### Task 5: Verify integration tests pass

**Step 1: Run**

```bash
INTEGRATION=true bundle exec rspec spec/integration/railtie_integration_spec.rb -e "development DevLog" -f doc
```

Expected: 3 examples, 0 failures

**Step 2: Run full integration suite**

```bash
INTEGRATION=true rake spec:integration
```

Expected: 0 failures

**Step 3: Commit**

```bash
git add spec/integration/railtie_integration_spec.rb
git commit -m "test: integration coverage for DevLog slot aliasing and event routing"
```

---

### Task 6: Verify and close

**Step 1: Run full test suite**

```bash
rake spec:all
```

Expected: 0 failures, count ≥ previous baseline

**Step 2: Lint**

```bash
bundle exec rubocop lib/e11y/railtie.rb spec/e11y/railtie_unit_spec.rb spec/integration/railtie_integration_spec.rb
```

Fix any offenses with `bundle exec rubocop -a` on those files.

**Step 3: Final commit if lint required fixes**

```bash
git add lib/e11y/railtie.rb spec/e11y/railtie_unit_spec.rb spec/integration/railtie_integration_spec.rb
git commit -m "style: rubocop fixes for DevLog routing changes"
```
