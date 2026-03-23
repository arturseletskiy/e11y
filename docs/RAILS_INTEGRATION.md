# Rails Integration

> Back to [README](../README.md#documentation)

E11y integrates with Rails via `E11y::Railtie` (`lib/e11y/railtie.rb`). After `bundle install`, requiring the gem in a Rails app loads the Railtie automatically.

## Request middleware

`E11y::Middleware::Request` is inserted into the Rack stack (before `Rails::Rack::Logger` when present). It sets trace and request context on `E11y::Current`, optionally starts the **ephemeral (request-scoped) buffer** for debug events, and adds `X-E11y-Trace-Id` / `X-E11y-Span-Id` response headers.

## Rails instrumentation (`ActiveSupport::Notifications`)

When **`config.rails_instrumentation_enabled = true`**, E11y subscribes to Rails instrumentation and maps notifications to typed events (see `lib/e11y/instruments/rails_instrumentation.rb`).

| Area | Event classes (under `E11y::Events::Rails::`) |
|------|-----------------------------------------------|
| HTTP | `Http::Request`, `Http::StartProcessing`, `Http::Redirect`, `Http::SendFile` |
| Database | `Database::Query` |
| Active Job (notification names) | `Job::Enqueued`, `Job::Scheduled`, `Job::Started`, `Job::Completed`, `Job::Failed` |
| Cache | `Cache::Read`, `Cache::Write`, `Cache::Delete` |
| Views | `View::Render` |

This is **independent** of the Sidekiq and Active Job toggles below: instrumentation listens to Rails; the job toggles add **extra** process integration (buffer lifecycle, middleware, callbacks).

## Sidekiq

Enable **only if** you use Sidekiq:

```ruby
E11y.configure do |config|
  config.sidekiq_enabled = true
end
```

The Railtie registers client and server middleware (`E11y::Instruments::Sidekiq`) so jobs participate in the same **ephemeral buffer** semantics as HTTP requests when `config.ephemeral_buffer_enabled` is true.

On enqueue, **`E11y::Current.user_id`** (when set, e.g. from request middleware) is merged into **`e11y_baggage`** together with any allowed `Current.baggage` keys. The worker restores **`E11y::Current.baggage`** and **`E11y::Current.user_id`** from that hash. Key **`user_id`** is in the default baggage allowlist (`E11y::BAGGAGE_PROTECTION_DEFAULT_ALLOWED_KEYS`).

## Active Job

Enable when you want callbacks and buffer handling on **`ActiveJob::Base`** (and **`ApplicationJob`** when that constant is already defined at hook time):

```ruby
E11y.configure do |config|
  config.active_job_enabled = true
end
```

You can use **both** `rails_instrumentation_enabled` and `active_job_enabled`; they complement each other. If you only enqueue via Sidekiq without Active Job, you may rely on `sidekiq_enabled` alone.

The **`before_enqueue`** callback applies the same **`e11y_baggage`** merge as Sidekiq (including **`user_id`** from `E11y::Current`).

## Rails.logger bridge

Optional wrapper that still delegates to the original logger but also emits **`E11y::Events::Rails::Log::*`** events (`lib/e11y/events/rails/log.rb`):

```ruby
E11y.configure do |config|
  config.logger_bridge_enabled = true
  # Optional: only these severities (Symbol or String); nil / empty = all
  config.logger_bridge_track_severities = %i[warn error fatal]
  # Optional: skip noisy lines (String substrings or Regexp)
  config.logger_bridge_ignore_patterns = [%r{health}]
end
```

Filtering uses **`logger_bridge_track_severities`** and **`logger_bridge_ignore_patterns`** only.

## Configuration reference

| Flag | Purpose |
|------|---------|
| `rails_instrumentation_enabled` | Map `ActiveSupport::Notifications` to E11y events |
| `sidekiq_enabled` | Sidekiq client/server middleware |
| `active_job_enabled` | `ActiveJob::Base` / `ApplicationJob` callbacks |
| `logger_bridge_enabled` | Wrap `Rails.logger` with `E11y::Logger::Bridge` |
| `ephemeral_buffer_enabled` | Request/job-scoped debug buffer (see README) |

Further detail: [ADR-008: Rails integration](architecture/ADR-008-rails-integration.md), [Quick Start](QUICK-START.md).
