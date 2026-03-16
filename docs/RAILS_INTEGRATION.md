# Rails Integration

> Back to [README](../README.md#documentation)

E11y integrates with Rails via Railtie.

## Auto-Instrumented Components

E11y includes event definitions for common Rails components:

| Component | Event Classes | Location |
|-----------|--------------|----------|
| **HTTP Requests** | Request, StartProcessing, Redirect, SendFile | `lib/e11y/events/rails/http/` |
| **ActiveRecord** | Query | `lib/e11y/events/rails/database/` |
| **ActiveJob** | Enqueued, Started, Completed, Failed, Scheduled | `lib/e11y/events/rails/job/` |
| **Cache** | Read, Write, Delete | `lib/e11y/events/rails/cache/` |
| **View** | Render | `lib/e11y/events/rails/view/` |

Enable instrumentation in your configuration as needed.

## Sidekiq Integration

E11y includes Sidekiq instrumentation support. Configure in your initializer:

```ruby
E11y.configure do |config|
  config.rails_instrumentation_enabled = true
end
```
