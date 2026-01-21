# E11y Performance Optimization Strategies

**Status:** Conditional (apply only if benchmarks fail)

This document outlines optimization strategies to apply if performance benchmarks don't meet targets.

## 📊 Benchmark First

**ALWAYS run benchmarks before optimizing:**

```bash
bundle exec ruby benchmarks/e11y_benchmarks.rb
```

If all targets are met → **no optimization needed** ✅

If some targets fail → apply strategies below ⚙️

## 🎯 Optimization Strategies

### 1. Memory Optimization

**If memory usage exceeds targets:**

#### 1.1 Reduce Object Allocations

```ruby
# BAD: Creates new hash on every call
def event_data
  { name: @name, value: @value, timestamp: Time.now }
end

# GOOD: Reuse hash
def event_data
  @event_data ||= {}
  @event_data[:name] = @name
  @event_data[:value] = @value
  @event_data[:timestamp] = Time.now
  @event_data
end
```

#### 1.2 Optimize Buffer Size

Current default: 10,000 events

```ruby
# Tune buffer size based on scale
E11y.configure do |config|
  config.buffer_size = case scale
                       when :small then 1_000
                       when :medium then 5_000
                       when :large then 10_000
                       end
end
```

#### 1.3 Pool Reusable Objects

```ruby
# Event object pooling
class EventPool
  def initialize(size: 100)
    @pool = Array.new(size) { E11y::Event::Base.new }
    @mutex = Mutex.new
  end

  def checkout
    @mutex.synchronize { @pool.pop || E11y::Event::Base.new }
  end

  def checkin(event)
    @mutex.synchronize { @pool.push(event) if @pool.size < 100 }
  end
end
```

### 2. CPU Optimization

**If CPU overhead exceeds targets:**

#### 2.1 Reduce Regex Matches

```ruby
# BAD: Regex on hot path
def matches_pattern?(name)
  name =~ /^user\./
end

# GOOD: String prefix check
def matches_pattern?(name)
  name.start_with?("user.")
end
```

#### 2.2 Cache Pattern Compilation

```ruby
# BAD: Compile regex every time
def filter_events(events)
  events.select { |e| e.name =~ /^(user|admin)\./ }
end

# GOOD: Compile once
PATTERN = /^(user|admin)\./

def filter_events(events)
  events.select { |e| e.name =~ PATTERN }
end
```

#### 2.3 Optimize JSON Serialization

```ruby
# Use Oj gem for faster JSON
require "oj"

module E11y
  module Adapters
    class File < Base
      def format_event(event_data)
        Oj.dump(event_data, mode: :compat)
      end
    end
  end
end

# Add to gemspec:
# spec.add_dependency "oj", "~> 3.16"
```

### 3. I/O Optimization

**If adapter latency exceeds targets:**

#### 3.1 Increase Batching

```ruby
E11y.configure do |config|
  # Increase batch size for better I/O efficiency
  config.flush_threshold = 1000  # Flush every 1000 events
  config.flush_interval = 5.0    # Or every 5 seconds
end
```

#### 3.2 Connection Pooling Tuning

```ruby
# For LokiAdapter
E11y::Adapters::Loki.new(
  url: "http://loki:3100",
  connection_pool_size: 10,  # Increase for high throughput
  timeout: 5
)
```

#### 3.3 Compression Optimization

```ruby
# Use faster compression level
E11y.configure do |config|
  config.compression = {
    enabled: true,
    algorithm: :zstd,  # Faster than gzip
    level: 1           # Fast compression (vs level 3)
  }
end
```

### 4. Profiling Tools

**Use Ruby profilers to find bottlenecks:**

#### 4.1 Memory Profiler

```ruby
require "memory_profiler"

report = MemoryProfiler.report do
  10_000.times { MyEvent.track(user_id: "123") }
end

report.pretty_print
```

#### 4.2 Stackprof (CPU profiler)

```bash
gem install stackprof

# Add to benchmark:
require "stackprof"

StackProf.run(mode: :cpu, out: "tmp/stackprof.dump") do
  # Your benchmark code
end

# Analyze:
stackprof tmp/stackprof.dump --text
```

#### 4.3 RubyProf

```ruby
require "ruby-prof"

result = RubyProf.profile do
  # Your benchmark code
end

printer = RubyProf::FlatPrinter.new(result)
printer.print(STDOUT)
```

## 🔧 Implementation Checklist

If benchmarks fail, apply optimizations in this order:

1. **Identify bottleneck** (use profilers)
2. **Apply targeted fix** (don't optimize everything)
3. **Re-run benchmarks** (verify improvement)
4. **Repeat** (until targets met)

## 📈 Performance Targets Reminder

- **Small (1K/sec)**: track() <50μs p99, Buffer 10K/sec, Memory <100MB
- **Medium (10K/sec)**: track() <1ms p99, Buffer 50K/sec, Memory <500MB
- **Large (100K/sec)**: track() <5ms p99, Buffer 200K/sec, Memory <2GB

## ⚠️ Anti-Patterns

**Don't optimize prematurely:**
- ❌ Don't apply optimizations "just in case"
- ❌ Don't micro-optimize without profiling
- ✅ Measure first, optimize second

**Don't sacrifice readability:**
- ❌ Don't make code unreadable for 1% gain
- ✅ Keep code maintainable, profile-driven optimizations only

## 📚 Additional Resources

- [Ruby Performance Optimization (Book)](https://pragprog.com/titles/adrpo/ruby-performance-optimization/)
- [benchmark-ips gem](https://github.com/evanphx/benchmark-ips)
- [memory_profiler gem](https://github.com/SamSaffron/memory_profiler)
- [stackprof gem](https://github.com/tmm1/stackprof)
