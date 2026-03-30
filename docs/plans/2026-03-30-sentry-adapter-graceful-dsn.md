# Design: Sentry Adapter — Graceful DSN Handling

**Date:** 2026-03-30
**Issue:** [#22](https://github.com/arturseletskiy/e11y/issues/22)
**Status:** Approved

## Problem

`E11y::Adapters::Sentry` raises `ArgumentError` at initialization when DSN is absent. This
breaks Docker multi-stage builds, `assets:precompile`, and CI pipelines where secrets are
not available.

Silently no-oping (option B) is equally bad: operators lose error reporting in production
without any signal. Neither hard-fail nor silent-drop is acceptable as a universal default.

## Decision

Add a `required:` config option (default `false`) to the adapter:

- `required: false` (default) — adapter initializes without DSN, emits a `warn` once at
  boot, and becomes inactive (`@active = false`). All `write()` calls are no-ops returning
  `true`. No retry or DLQ triggered.
- `required: true` — original strict behavior; raises `ArgumentError` immediately if DSN
  is absent. Intended for production use via `required: Rails.env.production?`.

This places enforcement responsibility at the application layer (initializer), not the gem
layer, which is idiomatic for Ruby gems.

## Why Not Env Flag (Option D)

`E11Y_SENTRY_REQUIRED=true` was considered but rejected:
- Mixes Ruby config and env-var config for the same concern
- Harder to test (requires `ENV` mocking)
- Less readable than `required: Rails.env.production?` inline in the initializer

## Changes

### `lib/e11y/adapters/sentry.rb`

**`initialize`** — read `required:` and track `@active`:

```ruby
def initialize(config = {})
  @required = config.fetch(:required, false)
  @dsn = config[:dsn]
  @environment = config.fetch(:environment, "production")
  @severity_threshold = config.fetch(:severity_threshold, DEFAULT_SEVERITY_THRESHOLD)
  @send_breadcrumbs = config.fetch(:breadcrumbs, true)

  super  # calls validate_config!

  if @dsn
    initialize_sentry!
    @active = true
  else
    @active = false
  end
end
```

**`validate_config!`** — conditional raise vs warn:

```ruby
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

  raise ArgumentError, "Invalid severity_threshold: #{@severity_threshold}"
end
```

**`write`** — early return when inactive:

```ruby
def write(event_data)
  return true unless @active
  # ... existing logic unchanged
end
```

**`healthy?`** — explicit inactive check:

```ruby
def healthy?
  @active && ::Sentry.initialized?
end
```

### `spec/e11y/adapters/sentry_spec.rb`

Replace existing `"requires :dsn parameter"` test with a `"when DSN is absent"` describe
block (5 examples):

1. Raises `ArgumentError` when `required: true`
2. Does not raise when `required: false` (default)
3. Emits warning to stderr when DSN is absent
4. `write()` is a no-op returning `true` when inactive
5. `healthy?` returns `false` when inactive

### `docs/QUICK-START.md`

Add "Enforcing Sentry in production" section:

```ruby
# config/initializers/e11y.rb
config.adapters[:sentry] = E11y::Adapters::Sentry.new(
  dsn: ENV["SENTRY_DSN"],
  required: Rails.env.production?  # raises at boot if DSN missing in production
)
```

## Acceptance Criteria

- [ ] `E11y::Adapters::Sentry.new({})` does not raise; emits one `warn` to stderr
- [ ] `E11y::Adapters::Sentry.new(required: true)` raises `ArgumentError` when DSN absent
- [ ] `write()` on an inactive adapter returns `true`, calls no Sentry methods
- [ ] `healthy?` returns `false` on an inactive adapter
- [ ] All existing tests pass; 5 new tests cover the DSN-absent scenarios
- [ ] QUICK-START.md documents the `required:` pattern
