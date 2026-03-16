# SLO Linters + Self-Monitoring Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Three SLO linters in lib/e11y/linters/slo/, plus e11y_self_monitoring in slo.yml with optional emit of e11y_events_tracked_total at pipeline end.

**Architecture:** Linters under linters/slo/ (future: linters/pii/, etc.). ConfigLoader reads e11y_self_monitoring from slo.yml. New middleware SelfMonitoringEmit runs last, emits when enabled.

**Tech Stack:** Ruby, RSpec, E11y::Registry, E11y::Metrics.

---

## Part A: SLO Linters

### Task A1: Add slo_enabled? and slo_disabled? to Event classes

**Files:**
- Modify: `lib/e11y/slo/event_driven.rb`
- Modify: `spec/e11y/slo/event_driven_spec.rb`

**Step 1:** Add to EventDriven::DSL (after slo_config):

```ruby
def slo_enabled?
  slo_config&.enabled? == true
end

def slo_disabled?
  slo_config && !slo_config.enabled?
end
```

**Step 2:** Add spec examples for slo_enabled? and slo_disabled?

**Step 3:** Run `bundle exec rspec spec/e11y/slo/event_driven_spec.rb -v` — must pass

**Step 4:** Commit "feat(slo): add slo_enabled? and slo_disabled? to Event DSL"

---

### Task A2: ExplicitDeclarationLinter

**Files:**
- Create: `lib/e11y/linters/slo/explicit_declaration.rb`
- Create: `lib/e11y/linters/base.rb` (optional base for LinterError)
- Create: `spec/e11y/linters/slo/explicit_declaration_spec.rb`

**Step 1:** Create LinterError in lib/e11y/linters/base.rb:

```ruby
# frozen_string_literal: true

module E11y
  module Linters
    class LinterError < StandardError; end
  end
end
```

**Step 2:** Create spec — validate! raises when Event has no slo declaration, passes when all have slo

**Step 3:** Implement ExplicitDeclarationLinter — iterates E11y::Registry.event_classes, checks slo_enabled? || slo_disabled?, raises LinterError with messages

**Step 4:** Run rspec, commit "feat(linters): add SLO ExplicitDeclarationLinter"

---

### Task A3: SloStatusFromLinter

**Files:**
- Create: `lib/e11y/linters/slo/slo_status_from.rb`
- Create: `spec/e11y/linters/slo/slo_status_from_spec.rb`

**Step 1:** Spec — when slo enabled, requires slo_status_from and contributes_to; raises when missing

**Step 2:** Implement — iterate event_classes, for slo_enabled? check slo_config.slo_status_proc and contributes_to_value

**Step 3:** Run rspec, commit "feat(linters): add SLO SloStatusFromLinter"

---

### Task A4: ConfigConsistencyLinter

**Files:**
- Create: `lib/e11y/linters/slo/config_consistency.rb`
- Create: `spec/e11y/linters/slo/config_consistency_spec.rb`

**Step 1:** Spec — when slo.yml has custom_slos with events, each event must have slo enabled and contributes_to match slo_name

**Step 2:** Implement — load config via ConfigLoader, iterate custom_slos[].events, constantize, check slo_enabled? and contributes_to

**Step 3:** Run rspec, commit "feat(linters): add SLO ConfigConsistencyLinter"

---

### Task A5: Wire linters into rake e11y:slo:validate

**Files:**
- Modify: `lib/tasks/e11y_slo.rake`

**Step 1:** After ConfigValidator.validate, run the three linters (when config present and not empty). Require linter files. Call each validate! — rescue LinterError, add to errors, exit 1.

**Step 2:** Add rake e11y:slo:lint as alias or separate task that runs only linters (no config validation)

**Step 3:** Test with dummy app, commit "feat(slo): wire SLO linters into rake e11y:slo:validate"

---

## Part B: Self-Monitoring (e11y_events_tracked_total)

### Task B1: ConfigLoader.self_monitoring_enabled?

**Files:**
- Modify: `lib/e11y/slo/config_loader.rb`
- Modify: `spec/e11y/slo/config_loader_spec.rb`

**Step 1:** Add class method .self_monitoring_enabled? — loads config (cached in @cached_config), returns config.dig("e11y_self_monitoring", "enabled") == true

**Step 2:** Add spec for self_monitoring_enabled?

**Step 3:** Run rspec, commit "feat(slo): add ConfigLoader.self_monitoring_enabled?"

---

### Task B2: Register e11y_events_tracked_total metric

**Files:**
- Modify: `lib/e11y/adapters/yabeda.rb`

**Step 1:** Add to self-monitoring metrics list: `{ name: :e11y_events_tracked_total, tags: %i[result event_name] }`

**Step 2:** Run rspec, commit "feat(metrics): register e11y_events_tracked_total"

---

### Task B3: SelfMonitoringEmit middleware

**Files:**
- Create: `lib/e11y/middleware/self_monitoring_emit.rb`
- Create: `spec/e11y/middleware/self_monitoring_emit_spec.rb`

**Step 1:** Middleware — call(event_data). If event_data nil, pass through. If ConfigLoader.self_monitoring_enabled?, emit E11y::Metrics.increment(:e11y_events_tracked_total, result: :success, event_name: event_data[:event_name]). Then @app.call(event_data).

**Step 2:** Spec — when enabled, increments metric; when disabled, does not; when event_data nil, does not emit

**Step 3:** Run rspec, commit "feat(middleware): add SelfMonitoringEmit"

---

### Task B4: Add SelfMonitoringEmit to pipeline (last)

**Files:**
- Modify: `lib/e11y.rb` (configure_default_pipeline)

**Step 1:** After EventSlo, add: @pipeline.use E11y::Middleware::SelfMonitoringEmit

**Step 2:** Update pipeline comment. Run full rspec.

**Step 3:** Commit "feat(pipeline): add SelfMonitoringEmit as last middleware"

---

### Task B5: ConfigValidator for e11y_self_monitoring

**Files:**
- Modify: `lib/e11y/slo/config_validator.rb`

**Step 1:** Add validate_e11y_self_monitoring — when e11y_self_monitoring present and enabled, optionally validate targets structure (no errors for now, just allow)

**Step 2:** Run rspec, commit "feat(slo): validate e11y_self_monitoring in ConfigValidator"

---

### Task B6: DashboardGenerator app-wide panel for e11y self-monitoring

**Files:**
- Modify: `lib/e11y/slo/dashboard_generator.rb`

**Step 1:** When config has e11y_self_monitoring.enabled, add panel "E11y Self-Monitoring Reliability" with PromQL: sum(rate(e11y_events_tracked_total{result="success"}[30d])) / sum(rate(e11y_events_tracked_total[30d]))

**Step 2:** Run rspec, commit "feat(slo): add e11y self-monitoring panel to dashboard"

---

## Summary

- **Part A:** lib/e11y/linters/slo/{explicit_declaration, slo_status_from, config_consistency}.rb + rake integration
- **Part B:** ConfigLoader.self_monitoring_enabled?, e11y_events_tracked_total, SelfMonitoringEmit middleware, pipeline, dashboard panel

**slo.yml schema for e11y_self_monitoring:**

```yaml
e11y_self_monitoring:
  enabled: true
  targets:
    reliability: 0.999
    latency_p99_ms: 1
```
