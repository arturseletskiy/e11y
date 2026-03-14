# Limitations & Tradeoffs

> Back to [README](../README.md#documentation)

E11y trades generality for Rails-specific ergonomics. Know what you're getting:

| Limitation | Detail |
|------------|--------|
| **Rails only** | No Sinatra, Hanami, or pure-Ruby support. Railtie is required. |
| **Ruby 3.2+** | Older projects can't use it without upgrading Ruby. |
| **Rails 7.0–8.0** | Rails 8.1 excluded (sqlite3 bug in test environment). |
| **Memory overhead** | Debug buffer holds events in RAM per request. Under heavy load with large payloads, monitor heap usage. |
| **No distributed tracing UI** | OTel adapter emits spans, but e11y has no built-in trace visualization. Use Grafana Tempo or Jaeger. |
