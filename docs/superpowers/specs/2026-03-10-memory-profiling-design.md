# Memory Profiling & Leak Detection — Design Spec

**Date:** 2026-03-10
**Branch:** `feat/integration-testing`
**Status:** Approved

---

## Goal

Add `memory_profiler` as a dev dependency and verify that E11y meets its documented memory guarantees:

- **Zero-allocation design**: `Event.track` returns a plain Hash, not an Event instance
- **No memory leaks**: 0 retained objects after N events
- **Minimal allocations**: ≤ 5/event (`validation_mode :never`), ≤ 15/event (`:always`/`:sampled`)
- **Memory consumption**: < 100MB for 1K events/sec (Small Scale target per `benchmarks/README.md`)

---

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Approach | Single `spec/e11y/memory_spec.rb` | One entry point, easy to find and extend |
| Bundle group | `:test` | No Rails needed; always available without flags |
| Assertion strategy | Hybrid (C) | `total_retained == 0` is strict (CI fails), allocations are soft (warn + print) |
| Rake task | `spec:memory` | Consistent with existing `spec:unit`, `spec:benchmark` pattern |

---

## Allocation Thresholds

Derived from `benchmarks/allocation_profiling.rb` (existing script) and `docs/ADR-001-architecture.md`:

| `validation_mode` | Max allocations/event | retained |
|---|---|---|
| `:never` | ≤ 5 | 0 (strict) |
| `:always` | ≤ 15 | 0 (strict) |
| `:sampled` (1%) | ≤ 15 | 0 (strict) |

The Ruby theoretical minimum is 2 allocations/event (kwargs Hash + return Hash). `validation_mode :never` should be close to that; `:always` adds dry-schema overhead.

Memory consumption: < 100MB allocated for 1K events (Small Scale per `benchmarks/README.md`).

---

## Files Changed

### New files

**`spec/support/memory_helpers.rb`**
Module `MemoryHelpers` with `measure_allocations(count:, warmup:, &block)` helper — encapsulates warmup, GC, and `MemoryProfiler.report` call to avoid duplication across tests.

**`spec/e11y/memory_spec.rb`**
7 tests, tag `:memory`. Structure:

```
E11y Memory Profile
  Event.track allocations
    validation_mode :never   → ≤5 alloc/event, 0 retained [strict]
    validation_mode :always  → ≤15 alloc/event, 0 retained [strict]
    validation_mode :sampled → ≤15 alloc/event, 0 retained [strict]
  Memory leaks at scale
    1K events → 0 retained objects [strict]
    10K events → 0 retained objects [strict]
  Memory consumption
    1K events < 100MB allocated [strict]
```

All tests print actual measured values to stdout for observability even when passing.

### Modified files

**`Gemfile`**
Add to `:test` group:
```ruby
gem "memory_profiler", "~> 1.0"
```

**`Rakefile`**
Add `spec:memory` task; add it to `spec:all` dependencies:
```ruby
desc "Run memory profiling specs (allocations, leaks, consumption)"
RSpec::Core::RakeTask.new("spec:memory") do |t|
  t.pattern = "spec/e11y/memory_spec.rb"
  t.rspec_opts = "--tag memory --format documentation"
end

task "spec:all" => %w[spec:unit spec:memory spec:integration]
```

**`spec/spec_helper.rb`**
Add `require "memory_profiler"` and `include MemoryHelpers` so the helper is available in all spec contexts.

**`spec/e11y/event/base_benchmark_spec.rb`**
Add `require "memory_profiler"`. Upgrade "zero-allocation verification" section with 2 new tests tagged `:benchmark, :memory`:
- `"allocates ≤5 objects per event (MemoryProfiler)"` — real allocation count
- `"retains 0 objects after 100 events"` — strict leak check

Existing structural tests ("does not create Event objects", "returns same Hash structure") are kept unchanged.

**`spec/integration/high_cardinality_protection_integration_spec.rb`**
Remove `skip` guard from `"maintains acceptable memory usage under high cardinality load"` (line 556). Add `require "memory_profiler"` at top of file. Test logic is already written — only the `skip` was blocking it.

---

## Test Commands

```bash
# New memory suite
bundle exec rake spec:memory

# Full suite (now includes memory)
bundle exec rake spec:all

# Single test
bundle exec rspec spec/e11y/memory_spec.rb --tag memory

# Benchmark suite (now includes memory tests too via dual tag)
bundle exec rake spec:benchmark
```

---

## Out of Scope

- Buffer memory tests (request-scoped buffer leak under concurrent load) — future work
- Adapter-specific memory profiles (Loki, OTel) — not part of zero-allocation claim
- Baseline recording / regression tracking over time — v1.1 backlog
