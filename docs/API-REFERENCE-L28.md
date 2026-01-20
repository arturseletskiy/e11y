# API Reference: Advanced Sampling (Phase 2.8)

**Version:** 1.0  
**Date:** January 20, 2026  
**Applies to:** E11y gem v0.8.0+

---

## 📋 Overview

This document provides complete API reference for all classes, modules, and methods introduced in Phase 2.8 (Advanced Sampling Strategies):

- **FEAT-4838**: Error-Based Adaptive Sampling
- **FEAT-4842**: Load-Based Adaptive Sampling
- **FEAT-4846**: Value-Based Sampling
- **FEAT-4850**: Stratified Sampling for SLO Accuracy

---

## 🔍 Table of Contents

1. [E11y::Sampling::ErrorSpikeDetector](#e11ysamplingerrorspikedetector)
2. [E11y::Sampling::LoadMonitor](#e11ysamplingloadmonitor)
3. [E11y::Sampling::ValueExtractor](#e11ysamplingvalueextractor)
4. [E11y::Event::ValueSamplingConfig](#e11yeventvaluesamplingconfig)
5. [E11y::Sampling::StratifiedTracker](#e11ysamplingrifiedtracker)
6. [E11y::Middleware::Sampling](#e11ymiddlewaresampling)
7. [E11y::Event::Base (Extended DSL)](#e11yeventbase-extended-dsl)

---

## E11y::Sampling::ErrorSpikeDetector

Detects error rate spikes using sliding windows and configurable absolute/relative thresholds.

### Location

```
lib/e11y/sampling/error_spike_detector.rb
```

### Class Definition

```ruby
module E11y
  module Sampling
    class ErrorSpikeDetector
      include MonitorMixin
    end
  end
end
```

### Constructor

```ruby
def initialize(config = {})
```

**Parameters:**
- `config` (Hash): Configuration options
  - `:window` (Integer): Sliding window duration in seconds (default: 60)
  - `:absolute_threshold` (Integer): Absolute error threshold (errors/min) (default: 100)
  - `:relative_threshold` (Float): Relative threshold (ratio to baseline) (default: 3.0)
  - `:spike_duration` (Integer): How long to maintain 100% sampling (default: 300)

**Example:**
```ruby
detector = E11y::Sampling::ErrorSpikeDetector.new(
  window: 60,
  absolute_threshold: 100,
  relative_threshold: 3.0,
  spike_duration: 300
)
```

---

### Instance Methods

#### `#error_spike?` → Boolean

Determines if an error spike is currently occurring.

**Returns:**
- `true` if error spike detected
- `false` otherwise

**Example:**
```ruby
if detector.error_spike?
  # Increase sampling to 100%
end
```

---

#### `#record_event(event_data)` → void

Records an event for error rate calculation.

**Parameters:**
- `event_data` (Hash): Event data with `:severity` key

**Example:**
```ruby
detector.record_event({ severity: :error, message: "Payment failed" })
```

---

#### `#current_error_rate` → Float

Calculates current error rate (errors per minute).

**Returns:**
- Float: Current error rate

**Example:**
```ruby
detector.current_error_rate  # => 150.5 (errors/min)
```

---

#### `#baseline_error_rate` → Float

Returns the baseline error rate (exponential moving average).

**Returns:**
- Float: Baseline error rate

**Example:**
```ruby
detector.baseline_error_rate  # => 50.0 (errors/min)
```

---

#### `#reset!` → void

Resets the detector state (clears all events and baseline).

**Example:**
```ruby
detector.reset!
```

---

### Thread Safety

This class uses `MonitorMixin` for thread-safe operations. All public methods acquire a mutex before accessing shared state.

---

## E11y::Sampling::LoadMonitor

Tracks event volume over a sliding window and determines load levels with recommended sampling rates.

### Location

```
lib/e11y/sampling/load_monitor.rb
```

### Class Definition

```ruby
module E11y
  module Sampling
    class LoadMonitor
      include MonitorMixin
    end
  end
end
```

### Constructor

```ruby
def initialize(config = {})
```

**Parameters:**
- `config` (Hash): Configuration options
  - `:window` (Integer): Sliding window duration in seconds (default: 60)
  - `:normal_threshold` (Integer): Normal load threshold (events/sec) (default: 1,000)
  - `:high_threshold` (Integer): High load threshold (events/sec) (default: 10,000)
  - `:very_high_threshold` (Integer): Very high load threshold (events/sec) (default: 50,000)
  - `:overload_threshold` (Integer): Overload threshold (events/sec) (default: 100,000)

**Example:**
```ruby
monitor = E11y::Sampling::LoadMonitor.new(
  window: 60,
  normal_threshold: 1_000,
  high_threshold: 10_000,
  very_high_threshold: 50_000,
  overload_threshold: 100_000
)
```

---

### Instance Methods

#### `#record_event` → void

Records an event for load calculation.

**Example:**
```ruby
monitor.record_event
```

---

#### `#current_rate` → Float

Calculates current event rate (events per second).

**Returns:**
- Float: Current event rate

**Example:**
```ruby
monitor.current_rate  # => 15_000.5 (events/sec)
```

---

#### `#load_level` → Symbol

Determines current load level based on event rate.

**Returns:**
- Symbol: One of `:normal`, `:high`, `:very_high`, or `:overload`

**Example:**
```ruby
monitor.load_level  # => :high
```

---

#### `#recommended_sample_rate` → Float

Gets recommended sample rate for current load level.

**Returns:**
- Float: Recommended sample rate (0.0 - 1.0)

| Load Level | Sample Rate |
|-----------|-------------|
| `:normal` | 1.0 (100%) |
| `:high` | 0.5 (50%) |
| `:very_high` | 0.1 (10%) |
| `:overload` | 0.01 (1%) |

**Example:**
```ruby
monitor.recommended_sample_rate  # => 0.5 (50%)
```

---

#### `#overloaded?` → Boolean

Checks if system is currently overloaded.

**Returns:**
- `true` if load level is `:overload`
- `false` otherwise

**Example:**
```ruby
if monitor.overloaded?
  # Apply aggressive sampling
end
```

---

#### `#stats` → Hash

Returns statistics about current load.

**Returns:**
- Hash with keys:
  - `:current_rate` (Float): Events per second
  - `:load_level` (Symbol): Current load level
  - `:recommended_sample_rate` (Float): Recommended rate

**Example:**
```ruby
monitor.stats
# => {
#   current_rate: 15000.5,
#   load_level: :high,
#   recommended_sample_rate: 0.5
# }
```

---

#### `#reset!` → void

Resets the monitor state (clears all events).

**Example:**
```ruby
monitor.reset!
```

---

## E11y::Sampling::ValueExtractor

Extracts numeric values from nested event payloads for value-based sampling.

### Location

```
lib/e11y/sampling/value_extractor.rb
```

### Class Methods

#### `.extract(payload, field_path)` → Float

Extracts a numeric value from a (potentially nested) payload.

**Parameters:**
- `payload` (Hash): Event payload
- `field_path` (String): Dot-separated field path (e.g., `"order.amount"`)

**Returns:**
- Float: Extracted value (or 0.0 if not found/nil)

**Type Coercion:**
- Numeric strings → Float (e.g., `"5000"` → `5000.0`)
- Nil/missing → `0.0`
- Non-numeric → `0.0` (fallback)

**Examples:**

```ruby
# Flat field
E11y::Sampling::ValueExtractor.extract({ "amount" => 5000 }, "amount")
# => 5000.0

# Nested field (dot notation)
E11y::Sampling::ValueExtractor.extract(
  { "order" => { "amount" => 1500 } },
  "order.amount"
)
# => 1500.0

# Numeric string (type coercion)
E11y::Sampling::ValueExtractor.extract({ "amount" => "5000" }, "amount")
# => 5000.0

# Nil/missing value
E11y::Sampling::ValueExtractor.extract({ "foo" => "bar" }, "amount")
# => 0.0
```

---

## E11y::Event::ValueSamplingConfig

Configuration for value-based sampling rules per event class.

### Location

```
lib/e11y/event/value_sampling_config.rb
```

### Class Definition

```ruby
module E11y
  module Event
    class ValueSamplingConfig
      attr_reader :field, :operator, :threshold, :sample_rate
    end
  end
end
```

### Constructor

```ruby
def initialize(field:, operator:, threshold:, sample_rate: 1.0)
```

**Parameters:**
- `field` (String): Dot-separated field path
- `operator` (Symbol): Comparison operator (`:greater_than`, `:less_than`, `:equals`, `:in_range`)
- `threshold` (Numeric, Range, String): Value or range to compare against
- `sample_rate` (Float): Sample rate to apply if criteria met (default: 1.0)

**Example:**
```ruby
config = E11y::Event::ValueSamplingConfig.new(
  field: "amount",
  operator: :greater_than,
  threshold: 1000,
  sample_rate: 1.0
)
```

---

### Instance Methods

#### `#matches?(event_data)` → Boolean

Determines if an event's value meets the sampling criteria.

**Parameters:**
- `event_data` (Hash): Event data with payload

**Returns:**
- `true` if value meets criteria (should sample)
- `false` otherwise

**Examples:**

```ruby
# Greater than
config = ValueSamplingConfig.new(field: "amount", operator: :greater_than, threshold: 1000)
config.matches?({ payload: { "amount" => 5000 } })  # => true
config.matches?({ payload: { "amount" => 500 } })   # => false

# Equals
config = ValueSamplingConfig.new(field: "user_segment", operator: :equals, threshold: "enterprise")
config.matches?({ payload: { "user_segment" => "enterprise" } })  # => true
config.matches?({ payload: { "user_segment" => "free" } })        # => false

# In range
config = ValueSamplingConfig.new(field: "amount", operator: :in_range, threshold: 100..500)
config.matches?({ payload: { "amount" => 250 } })   # => true
config.matches?({ payload: { "amount" => 750 } })   # => false
```

---

### Supported Operators

| Operator | Description | Threshold Type | Example |
|----------|-------------|---------------|---------|
| `:greater_than` | Value > threshold | Numeric | `amount > 1000` |
| `:less_than` | Value < threshold | Numeric | `latency_ms < 100` |
| `:equals` | Value == threshold | Any | `user_segment == "enterprise"` |
| `:in_range` | Value in range | Range | `amount in 100..500` |

---

## E11y::Sampling::StratifiedTracker

Tracks sampled and total counts per severity stratum for SLO sampling correction.

### Location

```
lib/e11y/sampling/stratified_tracker.rb
```

### Class Definition

```ruby
module E11y
  module Sampling
    class StratifiedTracker
      include MonitorMixin
    end
  end
end
```

### Constructor

```ruby
def initialize
```

**Example:**
```ruby
tracker = E11y::Sampling::StratifiedTracker.new
```

---

### Instance Methods

#### `#record_sample(severity:, sample_rate:)` → void

Records a sampled event with its original sample rate.

**Parameters:**
- `severity` (Symbol): Event severity (`:debug`, `:info`, `:warn`, `:error`, `:fatal`)
- `sample_rate` (Float): Original sample rate (0.0 - 1.0)

**Example:**
```ruby
tracker.record_sample(severity: :info, sample_rate: 0.1)  # 10% sampled
tracker.record_sample(severity: :error, sample_rate: 1.0)  # 100% sampled
```

---

#### `#sampling_correction(severity)` → Float

Calculates sampling correction factor for a given severity.

**Parameters:**
- `severity` (Symbol): Event severity

**Returns:**
- Float: Correction factor (1.0 / average_sample_rate)

**Formula:**
```
correction_factor = total_sampled_count / sum_of_sample_rates
```

**Examples:**

```ruby
# 100 events sampled at 10% rate
100.times { tracker.record_sample(severity: :info, sample_rate: 0.1) }

tracker.sampling_correction(:info)  # => 10.0
# Interpretation: Multiply observed count by 10 to get true count
# Observed: 100 sampled, True: 100 × 10 = 1,000 total

# 50 events sampled at 100% rate (errors)
50.times { tracker.record_sample(severity: :error, sample_rate: 1.0) }

tracker.sampling_correction(:error)  # => 1.0
# Interpretation: No correction needed (100% sampled)
```

---

#### `#reset!` → void

Resets all tracked data.

**Example:**
```ruby
tracker.reset!
```

---

### Thread Safety

This class uses `MonitorMixin` for thread-safe operations.

---

## E11y::Middleware::Sampling

Extended sampling middleware with all 4 advanced strategies.

### Location

```
lib/e11y/middleware/sampling.rb
```

### Class Definition

```ruby
module E11y
  module Middleware
    class Sampling
      def initialize(config = {})
      def call(event_data)
      def capabilities
    end
  end
end
```

### Configuration Options

```ruby
config = {
  # Base sampling
  default_sample_rate: 0.1,          # Fallback rate (default: 0.1)
  
  # Error-Based Adaptive (FEAT-4838)
  error_based_adaptive: true,        # Enable error spike detection
  error_spike_config: {
    window: 60,
    absolute_threshold: 100,
    relative_threshold: 3.0,
    spike_duration: 300
  },
  
  # Load-Based Adaptive (FEAT-4842)
  load_based_adaptive: true,         # Enable load monitoring
  load_monitor_config: {
    window: 60,
    normal_threshold: 1_000,
    high_threshold: 10_000,
    very_high_threshold: 50_000,
    overload_threshold: 100_000
  }
}
```

---

### Instance Methods

#### `#call(event_data)` → Hash or nil

Processes an event through the sampling pipeline.

**Parameters:**
- `event_data` (Hash): Event data

**Returns:**
- Hash: Event data (if sampled)
- nil: (if dropped)

**Sampling Decision Logic (Precedence Order):**

1. **Audit events**: Always processed (100%)
2. **Error spike override**: If detected → 100% for ALL events
3. **Value-based sampling**: If event has `sample_by_value` config and value meets criteria → 100%
4. **Load-based sampling**: Base rate from `LoadMonitor` (100%/50%/10%/1%)
5. **Event-level rate**: From `event_class.resolve_sample_rate`
6. **Default rate**: From `config[:default_sample_rate]`

**Example:**
```ruby
sampling = E11y::Middleware::Sampling.new(config)

event_data = {
  event_name: "order.paid",
  severity: :info,
  payload: { amount: 5000 }
}

result = sampling.call(event_data)
# => { event_name: "order.paid", ... } (sampled)
# OR
# => nil (dropped)
```

---

#### `#capabilities` → Hash

Returns middleware capabilities.

**Returns:**
- Hash with capability flags:
  - `:error_spike_aware` (Boolean)
  - `:load_based_adaptive` (Boolean)
  - `:value_based_sampling` (Boolean)
  - `:stratified_tracking` (Boolean)

**Example:**
```ruby
sampling.capabilities
# => {
#   error_spike_aware: true,
#   load_based_adaptive: true,
#   value_based_sampling: true,
#   stratified_tracking: true
# }
```

---

## E11y::Event::Base (Extended DSL)

Extended event base class with `sample_by_value` DSL.

### Location

```
lib/e11y/event/base.rb
```

### Class Methods

#### `.sample_by_value(field:, operator:, threshold:, sample_rate: 1.0)` → ValueSamplingConfig

Configures value-based sampling for this event class.

**Parameters:**
- `field` (String): Dot-separated field path in payload
- `operator` (Symbol): Comparison operator
- `threshold` (Numeric, Range, String): Value or range to compare
- `sample_rate` (Float): Sample rate if criteria met (default: 1.0)

**Returns:**
- `ValueSamplingConfig` instance

**Examples:**

```ruby
class Events::OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
  end
  
  # Strategy 1: Always sample high-value orders
  sample_by_value field: "amount",
                  operator: :greater_than,
                  threshold: 1000,
                  sample_rate: 1.0
  
  # Strategy 2: Sample range (50%)
  sample_by_value field: "amount",
                  operator: :in_range,
                  threshold: 100..500,
                  sample_rate: 0.5
end

class Events::ApiRequest < E11y::Event::Base
  schema do
    required(:endpoint).filled(:string)
    required(:latency_ms).filled(:integer)
  end
  
  # Always sample slow requests
  sample_by_value field: "latency_ms",
                  operator: :greater_than,
                  threshold: 1000,
                  sample_rate: 1.0
end

class Events::UserAction < E11y::Event::Base
  schema do
    required(:action).filled(:string)
    required(:user_segment).filled(:string)
  end
  
  # Always sample enterprise users
  sample_by_value field: "user_segment",
                  operator: :equals,
                  threshold: "enterprise",
                  sample_rate: 1.0
end
```

---

#### `.value_sampling_config` → ValueSamplingConfig or nil

Returns the value sampling configuration for this event class.

**Returns:**
- `ValueSamplingConfig` instance (if `sample_by_value` was called)
- `nil` (if no value-based sampling configured)

**Example:**
```ruby
Events::OrderPaid.value_sampling_config
# => #<E11y::Event::ValueSamplingConfig @field="amount" @operator=:greater_than ...>

Events::DebugEvent.value_sampling_config
# => nil (no value-based sampling)
```

---

## 📊 Usage Examples

### Example 1: Production Configuration

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.pipeline.use E11y::Middleware::Sampling,
    default_sample_rate: 0.1,
    
    # Error-Based Adaptive
    error_based_adaptive: true,
    error_spike_config: {
      window: 60,
      absolute_threshold: 100,
      relative_threshold: 3.0,
      spike_duration: 300
    },
    
    # Load-Based Adaptive
    load_based_adaptive: true,
    load_monitor_config: {
      window: 60,
      normal_threshold: 1_000,
      high_threshold: 10_000,
      very_high_threshold: 50_000,
      overload_threshold: 100_000
    }
end

# Event with value-based sampling
class Events::OrderPaid < E11y::Event::Base
  schema { required(:amount).filled(:decimal) }
  
  sample_by_value field: "amount",
                  operator: :greater_than,
                  threshold: 1000
end
```

---

### Example 2: Manual Detector Usage

```ruby
# Create detector
detector = E11y::Sampling::ErrorSpikeDetector.new(
  window: 60,
  absolute_threshold: 100,
  relative_threshold: 3.0
)

# Record events
1000.times do |i|
  event = {
    severity: i % 10 == 0 ? :error : :info,  # 10% error rate
    message: "Event #{i}"
  }
  
  detector.record_event(event)
end

# Check if spike detected
if detector.error_spike?
  puts "ERROR SPIKE DETECTED!"
  puts "Current rate: #{detector.current_error_rate} errors/min"
  puts "Baseline: #{detector.baseline_error_rate} errors/min"
end
```

---

### Example 3: SLO Calculation with Stratified Sampling

```ruby
# Track events with sampling
tracker = E11y::Sampling::StratifiedTracker.new

# Simulate 1000 events (950 success, 50 errors)
# Stratified sampling: errors 100%, success 10%
950.times { tracker.record_sample(severity: :info, sample_rate: 0.1) }
50.times { tracker.record_sample(severity: :error, sample_rate: 1.0) }

# Calculate corrected success rate
success_correction = tracker.sampling_correction(:info)   # => 10.0
error_correction = tracker.sampling_correction(:error)     # => 1.0

observed_success = 95   # 10% of 950
observed_errors = 50    # 100% of 50

corrected_success = observed_success * success_correction  # => 950
corrected_errors = observed_errors * error_correction      # => 50

corrected_success_rate = corrected_success / (corrected_success + corrected_errors)
# => 0.95 (95%) ✅ ACCURATE!
```

---

## 🧪 Testing

All classes include comprehensive RSpec tests:

```bash
# Error-Based Adaptive
bundle exec rspec spec/e11y/sampling/error_spike_detector_spec.rb

# Load-Based Adaptive
bundle exec rspec spec/e11y/sampling/load_monitor_spec.rb

# Value-Based Sampling
bundle exec rspec spec/e11y/sampling/value_extractor_spec.rb
bundle exec rspec spec/e11y/event/value_sampling_config_spec.rb

# Stratified Sampling
bundle exec rspec spec/e11y/sampling/stratified_tracker_spec.rb

# Integration Tests
bundle exec rspec spec/e11y/middleware/sampling_spec.rb
bundle exec rspec spec/e11y/slo/stratified_sampling_integration_spec.rb
```

---

## 📚 Related Documentation

- **[Migration Guide](./guides/MIGRATION-L27-L28.md)** - Upgrade from L2.7 to L2.8
- **[Performance Benchmarks](./guides/PERFORMANCE-BENCHMARKS.md)** - Benchmark results
- **[ADR-009: Cost Optimization](./ADR-009-cost-optimization.md)** - Architecture details
- **[UC-014: Adaptive Sampling](./use_cases/UC-014-adaptive-sampling.md)** - Use cases

---

**API Reference Version:** 1.0  
**Last Updated:** January 20, 2026  
**Test Coverage:** 117 tests (all passing)
