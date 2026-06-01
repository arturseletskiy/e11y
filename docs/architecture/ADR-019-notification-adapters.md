# ADR-019: Notification Adapters (Mattermost, ActionMailer)

**Status:** ✅ Implemented
**Date:** 2026-04-17
**Covers:** MattermostAdapter, ActionMailerAdapter, E11y::Store abstraction
**Depends On:** ADR-004 (Adapter Architecture), ADR-015 (Middleware Order)

---

## 1. Context & Problem

E11y routes events to logging/metrics adapters (Loki, Sentry, OTel). There was no built-in way to deliver human-facing notifications (chat messages, emails) with alert deduplication or periodic digest rollups.

Key constraints:
- Public gem — must work in single-process (Puma 1 worker), multi-worker, and multi-pod (K8s) deployments
- No assumptions about background job framework (Sidekiq optional)
- No new mandatory dependencies

## 2. Decisions

### 2.1 Notification behaviour declared on the event, not the adapter

`alert` / `digest` config lives in a `notify` DSL block on the event class. Adapters are pure transport — they read `event_data[:notify]` set by the pipeline.

```ruby
class Events::PaymentFailed < E11y::Event::Base
  notify do
    alert throttle_window: 30.minutes, fingerprint: [:event_name]
    digest interval: 1.hour
  end
end
```

### 2.2 E11y::Store abstraction for cross-process state

`Store::Base` defines the shared state interface. Implementations:
- `Store::Memory` — Mutex+Hash with TTL. Single-process only. For tests and simple deployments.
- `Store::RailsCache` — delegates to `Rails.cache`. Raises `ArgumentError` at init if `MemoryStore`/`NullStore` in production/staging.

Store is injected explicitly per adapter — no global `config.store`.

### 2.3 Store is required at adapter initialisation — no silent fallback

Notification adapters raise `ArgumentError` if `:store` absent. Silent fallback to Memory would cause notification floods in multi-process production.

### 2.4 Digest flush is lazy — no background threads

Previous-window flush happens on the first event of a new window. A distributed lock (`set_if_absent` on the flush key) ensures exactly one process flushes each window. No threads, no Sidekiq dependency.

### 2.5 TTL on all store keys

Every key written to the store has an explicit TTL. Self-cleanup without maintenance jobs.

### 2.6 ActionMailerAdapter is do_not_eager_load

ActionMailer is not a required dependency of the gem. The adapter file is excluded from Zeitwerk eager loading to avoid `NameError` in environments without ActionMailer.

## 3. Store Key Schema

```
e11y:alert:{adapter_id}:{fingerprint}           TTL = throttle_window
e11y:d:{adapter_id}:{window}:{name}:seen        TTL = interval × 2
e11y:d:{adapter_id}:{window}:{name}:count       TTL = interval × 2
e11y:d:{adapter_id}:{window}:{name}:severity    TTL = interval × 2
e11y:d:{adapter_id}:{window}:__index__          TTL = interval × 2
e11y:d:{adapter_id}:{window}:__overflow__       TTL = interval × 2
e11y:d:{adapter_id}:{window}:__lock__           TTL = interval
```

## 4. Trade-offs

| Decision | Pro | Con |
|---|---|---|
| Notify config on event | Locality, reuse via inheritance | Pipeline must carry :notify in event_data |
| Explicit store per adapter | Explicit, no hidden global state | More verbose config |
| Raise on MemoryStore in prod | Fail fast, no silent floods | Config error visible at boot |
| Lazy digest flush | No threads, works anywhere | Flush delayed until next event arrives |
| ActionMailer as delegate (no template) | User keeps full control of email format | User must implement mailer methods |
