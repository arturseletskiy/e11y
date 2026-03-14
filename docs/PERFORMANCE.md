# Performance

> Back to [README](../README.md#documentation)

## Design Principles

E11y is designed for performance:

- **Hash-based events** - Events are Hashes, not objects, minimizing allocations
- **Configurable validation** - Choose validation mode based on performance needs
- **Batching** - Loki and other adapters support batching to reduce network overhead
- **Sampling** - Adaptive sampling reduces event volume under high load

## Benchmarks (Ruby 3.3, measured via `rake spec:benchmark` and `rake spec:memory`)

| Metric | Value | Notes |
|--------|-------|-------|
| Event tracking latency (p99, `:always`) | <70µs | Full dry-schema validation per event |
| Event tracking latency (p99, `:sampled` 1%) | <10µs | Schema runs ~1% of events |
| Event tracking latency (p99, `:never`) | <50µs | Pipeline overhead, no validation |
| Memory allocations (`:always` mode) | ~47 objects/event | Baseline; threshold ≤72 |
| Memory allocations (`:never` mode) | ~33 objects/event | Baseline; threshold ≤50 |
| Memory retained after 10K events | 0 objects | No leaks detected |
| Memory consumption (1K events) | <100 MB allocated | Small-scale benchmark target |

## Validation Mode Trade-offs

```ruby
# Fastest — skip schema checks in production hot paths
validation_mode :never    # ~33 allocs/event, <50µs p99

# Balanced — validate 1% of traffic for regression detection
validation_mode :sampled, sample_rate: 0.01  # <10µs p99

# Safest — validate every event (default, recommended for dev/staging)
validation_mode :always   # ~47 allocs/event, <70µs p99
```

## Running Benchmarks

```bash
rake spec:benchmark   # latency benchmarks (~44 examples)
rake spec:memory      # allocation and leak checks
```

See `spec/e11y/event/base_benchmark_spec.rb` and `spec/e11y/memory_spec.rb` for the full test suite.

## Cardinality Protection

Optional cardinality protection prevents high-cardinality labels from overwhelming metrics systems:

```ruby
E11y::Adapters::Loki.new(
  url: "http://loki:3100",
  enable_cardinality_protection: true,
  max_label_cardinality: 100
)
```

When enabled, high-cardinality labels (e.g., `user_id`, `order_id`) are filtered from metric tags.
