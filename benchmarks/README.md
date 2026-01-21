# E11y Performance Benchmarks

Performance benchmark suite for E11y gem, testing at 3 scale levels.

## 🎯 Performance Targets

Based on **ADR-001 §5: Performance Requirements**

### Small Scale (1K events/sec)
- `track()` latency: **<50μs** (p99)
- Buffer throughput: **10K events/sec**
- Memory usage: **<100MB**
- CPU overhead: **<5%**

### Medium Scale (10K events/sec)
- `track()` latency: **<1ms** (p99)
- Buffer throughput: **50K events/sec**
- Memory usage: **<500MB**
- CPU overhead: **<10%**

### Large Scale (100K events/sec)
- `track()` latency: **<5ms** (p99)
- Buffer throughput: **200K events/sec**
- Memory usage: **<2GB**
- CPU overhead: **<15%**

## 🚀 Running Benchmarks

### Run all scales

```bash
bundle exec ruby benchmarks/e11y_benchmarks.rb
```

### Run specific scale

```bash
# Small scale (1K events/sec)
SCALE=small bundle exec ruby benchmarks/e11y_benchmarks.rb

# Medium scale (10K events/sec)
SCALE=medium bundle exec ruby benchmarks/e11y_benchmarks.rb

# Large scale (100K events/sec)
SCALE=large bundle exec ruby benchmarks/e11y_benchmarks.rb
```

### Run via runner

```bash
bundle exec ruby benchmarks/run_all.rb
```

## 📊 Metrics Collected

1. **track() Latency**
   - p50, p99, p999 percentiles (microseconds)
   - Min, max, mean values

2. **Buffer Throughput**
   - Events per second
   - Measured over sustained period (3-10 seconds)

3. **Memory Usage**
   - Total allocated memory (MB)
   - Memory per event (KB)
   - Object allocations and retentions

4. **CPU Overhead**
   - Informational only (manual profiling recommended)

## ✅ Success Criteria

Benchmarks **PASS** if all metrics meet targets for each scale.

Exit codes:
- `0` - All benchmarks passed ✅
- `1` - Some benchmarks failed ❌

## 🔧 Dependencies

```ruby
# Required gems (already in gemspec)
gem "benchmark-ips", "~> 2.13"
gem "memory_profiler", "~> 1.0"
```

## 📝 Notes

- Benchmarks use `InMemory` adapter to eliminate I/O overhead
- GC is triggered before memory profiling for clean measurements
- CPU percentage is approximate (use external profilers for accuracy)
- Results may vary based on Ruby version and hardware

## 🎓 CI Integration

In CI/CD:

```yaml
- name: Run performance benchmarks
  run: bundle exec ruby benchmarks/e11y_benchmarks.rb
  # Fails CI if benchmarks don't meet targets
```
