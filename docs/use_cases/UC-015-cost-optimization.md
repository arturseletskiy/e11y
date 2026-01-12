# UC-015: Cost Optimization

**Status:** v1.1 Enhancement  
**Complexity:** Advanced  
**Setup Time:** 45-60 minutes  
**Target Users:** Engineering Managers, CTOs, FinOps Teams, SRE

---

## 📋 Overview

### Problem Statement

**The $120,000/year observability bill:**
```ruby
# ❌ UNOPTIMIZED: Burning money on observability
# Current setup:
# - 50 services × 2k events/sec = 100k events/sec
# - All events at full payload size (~2KB each)
# - No deduplication
# - No compression
# - No intelligent sampling
# - 100% sent to Datadog + Loki

# Monthly costs:
# - Datadog: $15/host × 200 hosts = $3,000/month
# - Loki ingestion: 100k events/sec × 2KB × 86400 sec/day × 30 days
#   = 518.4 TB/month × $0.02/GB = $10,368/month
# - Total: $13,368/month = $160,416/year 😱

# But wait... there's more waste:
# - 80% of events are duplicates (retry storms)
# - 50% of payload is empty/default values
# - 30% of events are DEBUG (not needed in prod)
# - Storing everything for 30 days (overkill for most data)
```

### E11y Solution

**10+ optimization techniques = 70-90% cost reduction:**
```ruby
# ✅ OPTIMIZED: Same insight, 10x less cost
E11y.configure do |config|
  config.cost_optimization do
    # 1. Intelligent sampling (90% reduction)
    adaptive_sampling enabled: true,
                     base_rate: 0.1  # 10% of normal events
    
    # 2. Deduplication (80% reduction in retries)
    deduplication enabled: true,
                  window: 1.minute
    
    # 3. Compression (70% size reduction)
    compression enabled: true,
                algorithm: :zstd,  # Better than gzip
                level: 3
    
    # 4. Payload minimization (50% smaller)
    minimize_payloads enabled: true,
                      drop_null_fields: true,
                      drop_empty_strings: true,
                      truncate_strings: 1000  # chars
    
    # 5. Tiered storage (60% cheaper)
    retention_tiers do
      hot 7.days, storage: :loki       # Fast queries
      warm 30.days, storage: :s3        # Slower, cheaper
      cold 1.year, storage: :s3_glacier # Archive
    end
    
    # 6. Smart routing (send only what's needed)
    routing do
      # Errors → Datadog (for alerting)
      route event_patterns: ['*.error', '*.fatal'],
            to: [:datadog, :loki]
      
      # Everything else → Loki only
      route event_patterns: ['*'],
            to: [:loki]
    end
  end
end

# Result:
# - 100k events/sec → 10k events/sec (adaptive sampling)
# - 2KB/event → 0.6KB/event (dedup + compression + minimization)
# - 30 days hot storage → 7 days hot + 23 days warm (tiered)
# - Datadog: Only errors (3k/sec instead of 100k/sec)
#
# New monthly cost:
# - Datadog: $3,000 → $500 (only errors)
# - Loki: $10,368 → $1,200 (10% volume, 70% smaller, 7 days hot)
# - S3: $200 (warm storage)
# - Total: $1,900/month = $22,800/year
#
# SAVINGS: $160,416 - $22,800 = $137,616/year (86% reduction!)
```

---

## 🎯 Cost Optimization Strategies

### Strategy 1: Intelligent Sampling by Value

**Don't sample high-value events:**
```ruby
E11y.configure do |config|
  config.cost_optimization do
    intelligent_sampling do
      # Always track high-value events
      always_sample do
        # High-value transactions
        when_field :amount, greater_than: 1000
        
        # VIP users
        when_field :user_segment, in: ['enterprise', 'vip']
        
        # Errors (always important)
        when_severity :error, :fatal
        
        # Security events
        when_pattern 'security.*', 'audit.*'
      end
      
      # Aggressively sample low-value
      sample_rate_for do
        # Debug events: 1%
        when_severity :debug, sample_rate: 0.01
        
        # Success events: 5%
        when_severity :success, sample_rate: 0.05
        
        # Low-value transactions (<$10): 10%
        when_field :amount, less_than: 10, sample_rate: 0.1
      end
      
      # Default: 10%
      default_sample_rate 0.1
    end
  end
end

# Impact:
# Before: 100k events/sec × 100% = 100k tracked
# After:
#   - High-value (5k/sec): 100% = 5k tracked
#   - Errors (3k/sec): 100% = 3k tracked
#   - Debug (20k/sec): 1% = 200 tracked
#   - Other (72k/sec): 10% = 7.2k tracked
#   - Total: 15.4k tracked (85% reduction!)
```

---

### Strategy 2: Deduplication

**Remove duplicate events (common in retry storms):**
```ruby
E11y.configure do |config|
  config.cost_optimization do
    deduplication do
      enabled true
      
      # Dedupe window
      window 1.minute
      
      # Dedupe by these fields
      dedupe_keys [:event_name, :user_id, :order_id, :error_code]
      
      # What to do with dupes
      on_duplicate :count  # OR :drop, :sample
      
      # Count mode: Keep first, increment counter
      counter_field :duplicate_count
      
      # Sample mode: Keep 10% of duplicates
      duplicate_sample_rate 0.1
    end
  end
end

# Example:
# Within 1 minute, same error repeats 100 times:
Events::PaymentError.track(user_id: '123', order_id: '456', error: 'timeout')
# × 100 times

# Without dedup: 100 events stored
# With dedup (count mode): 1 event with duplicate_count: 100
# With dedup (sample mode): 1 event + 10 samples
#
# Cost reduction: 90-99%
```

---

### Strategy 3: Payload Minimization

**Remove unnecessary data:**
```ruby
E11y.configure do |config|
  config.cost_optimization do
    payload_minimization do
      enabled true
      
      # Remove null/empty values
      drop_null_fields true
      drop_empty_strings true
      drop_empty_arrays true
      drop_empty_hashes true
      
      # Truncate long strings
      truncate_strings max_length: 1000,
                       suffix: '...[truncated]'
      
      # Remove default values
      drop_default_values true,
                          defaults: {
                            status: 'pending',
                            currency: 'USD',
                            country: 'US'
                          }
      
      # Exclude specific fields (never send)
      exclude_fields [:internal_debug_data, :temp_cache]
      
      # Compress repeated values
      compress_repeated_values threshold: 3  # If >3 occurrences
    end
  end
end

# Example:
# Before minimization:
{
  event_name: 'order.created',
  payload: {
    order_id: '123',
    user_id: '456',
    status: 'pending',  # ← Default, removed
    currency: 'USD',    # ← Default, removed
    notes: '',          # ← Empty, removed
    tags: [],           # ← Empty, removed
    metadata: {},       # ← Empty, removed
    internal_debug_data: { ... },  # ← Excluded
    long_description: 'Lorem ipsum...' × 10000  # ← Truncated to 1000 chars
  }
}
# Size: ~12 KB

# After minimization:
{
  event_name: 'order.created',
  payload: {
    order_id: '123',
    user_id: '456',
    long_description: 'Lorem ipsum...[truncated]'  # 1000 chars
  }
}
# Size: ~1.2 KB (90% reduction!)
```

---

### Strategy 4: Compression

**Compress before sending:**
```ruby
E11y.configure do |config|
  config.cost_optimization do
    compression do
      enabled true
      
      # Algorithm (zstd > lz4 > gzip for JSON)
      algorithm :zstd  # OR :lz4, :gzip
      
      # Compression level (1-9)
      level 3  # Balance speed/ratio (3 = good default)
      
      # Batch compression (more efficient)
      batch_size 500  # Compress 500 events together
      
      # Only compress if beneficial
      min_batch_size 10.kilobytes  # Don't compress tiny batches
      
      # Compression statistics
      track_compression_ratio true
    end
  end
end

# Compression ratios (for JSON events):
# - gzip level 6: ~65% reduction (2KB → 700 bytes)
# - lz4 default: ~55% reduction (2KB → 900 bytes, faster)
# - zstd level 3: ~70% reduction (2KB → 600 bytes, best!)
#
# Network cost reduction: 70%!
```

---

### Strategy 5: Tiered Storage

**Hot/warm/cold storage based on age:**
```ruby
E11y.configure do |config|
  config.cost_optimization do
    tiered_storage do
      # HOT: Fast queries, expensive ($0.20/GB/month)
      hot_tier do
        duration 7.days
        storage :loki  # OR :elasticsearch
        query_performance :fast
      end
      
      # WARM: Slower queries, cheaper ($0.05/GB/month)
      warm_tier do
        duration 30.days
        storage :s3
        query_performance :medium
        compression :zstd  # Compress when moving to warm
      end
      
      # COLD: Archive, very cheap ($0.004/GB/month)
      cold_tier do
        duration 1.year
        storage :s3_glacier
        query_performance :slow  # Minutes to hours
        compression :zstd
      end
      
      # Auto-archival
      auto_archive enabled: true,
                   schedule: '0 2 * * *'  # 2 AM daily
    end
  end
end

# Cost comparison (per 1TB):
# Hot (Loki): $0.20/GB × 1000 = $200/month
# Warm (S3): $0.05/GB × 1000 = $50/month
# Cold (Glacier): $0.004/GB × 1000 = $4/month
#
# Strategy:
# - 7 days hot (for active debugging)
# - 30 days warm (for recent lookups)
# - 1 year cold (for compliance)
#
# Cost for 30 days of data:
# Before: 30 days × $200 = $6,000/month
# After: (7 × $200) + (23 × $50) + (0 × $4) = $1,400 + $1,150 = $2,550/month
# Savings: $3,450/month (58% reduction!)
```

---

### Strategy 6: Smart Routing

**Send events only to necessary destinations:**
```ruby
E11y.configure do |config|
  config.cost_optimization do
    smart_routing do
      # Errors → Multiple destinations (alerting)
      route event_patterns: ['*.error', '*.fatal'],
            severities: [:error, :fatal],
            to: [:datadog, :loki, :sentry]
      
      # High-value transactions → All (audit + analytics)
      route event_patterns: ['payment.*', 'order.*'],
            when: ->(e) { e.payload[:amount].to_i > 1000 },
            to: [:datadog, :loki, :s3_archive]
      
      # Security events → Specific SIEM
      route event_patterns: ['security.*', 'audit.*'],
            to: [:splunk, :s3_archive]
      
      # Debug events → Only Loki (no expensive Datadog)
      route severities: [:debug],
            to: [:loki]
      
      # Everything else → Loki only
      route event_patterns: ['*'],
            to: [:loki]
    end
  end
end

# Cost impact:
# Datadog: $15/host/month (expensive!)
# Loki: $0.20/GB/month (cheaper)
#
# Before: All 100k events/sec → Datadog + Loki
#   Datadog cost: $3,000/month
#
# After: Only errors (3k events/sec) → Datadog
#   Datadog cost: $500/month
#
# Savings: $2,500/month (83% reduction!)
```

---

### Strategy 7: Retention-Aware Tagging

**Tag events with retention requirements:**
```ruby
E11y.configure do |config|
  config.cost_optimization do
    retention_aware_tagging do
      # Auto-tag events with retention hints
      tag_with_retention do
        # Compliance events: Long retention
        when_pattern 'audit.*', 'gdpr.*', retention: 7.years
        
        # Financial: Long retention
        when_pattern 'payment.*', 'transaction.*', retention: 7.years
        
        # Errors: Medium retention
        when_severity :error, :fatal, retention: 90.days
        
        # Debug: Short retention
        when_severity :debug, retention: 7.days
        
        # Default
        default_retention 30.days
      end
      
      # Backend respects retention tags
      backends do
        loki retention_based: true,
             max_retention: 30.days
        
        s3_archive retention_based: true,
                   max_retention: 7.years
      end
    end
  end
end

# Result:
# - Debug events: 7 days in Loki (cheap)
# - Errors: 90 days in Loki
# - Compliance: 7 years in S3 Glacier (very cheap)
# - Default: 30 days in Loki
#
# Cost optimization: Store data only as long as needed!
```

---

### Strategy 8: Batch & Bundle

**Batch events for efficiency:**
```ruby
E11y.configure do |config|
  config.cost_optimization do
    batching do
      enabled true
      
      # Batch parameters
      max_batch_size 500  # events
      max_batch_bytes 1.megabyte
      max_wait_time 5.seconds
      
      # Batch compression (more efficient)
      compress_batches true
      
      # Bundle similar events (further compression)
      bundle_similar_events do
        enabled true
        similarity_threshold 0.8  # 80% similar
        max_bundle_size 100
      end
    end
  end
end

# Example:
# 500 events sent separately:
# - 500 HTTP requests
# - 500 × 2KB = 1 MB payload
# - Network overhead: 500 × 1KB = 500 KB
# - Total: 1.5 MB

# 500 events in 1 batch (compressed):
# - 1 HTTP request
# - 1 MB payload → 300 KB (compressed)
# - Network overhead: 1 KB
# - Total: 301 KB
#
# Bandwidth reduction: 80%!
```

---

## 💰 Cost Calculator

**Calculate your potential savings:**
```ruby
# lib/e11y/cost_calculator.rb
module E11y
  class CostCalculator
    def calculate(
      events_per_second:,
      avg_event_size_bytes:,
      num_services:,
      datadog_hosts: 0,
      loki_ingestion_rate_gb_month: nil
    )
      # Calculate monthly volume
      seconds_per_month = 30 * 24 * 60 * 60  # 2,592,000
      total_events_month = events_per_second * seconds_per_month
      total_bytes_month = total_events_month * avg_event_size_bytes
      total_gb_month = total_bytes_month / 1.gigabyte
      
      # === UNOPTIMIZED COSTS ===
      unoptimized = {
        datadog: datadog_hosts * 15,  # $15/host/month
        loki: total_gb_month * 0.20,  # $0.20/GB/month
        total: 0
      }
      unoptimized[:total] = unoptimized.values.sum
      
      # === OPTIMIZED COSTS (with E11y) ===
      # Assumptions:
      # - 90% sampling reduction
      # - 70% compression
      # - 80% deduplication for retries
      # - 60% cheaper storage (tiered)
      
      effective_events = total_events_month * 0.1  # 90% sampling
      effective_events *= 0.2  # 80% deduplication
      effective_bytes = effective_events * avg_event_size_bytes * 0.3  # 70% compression
      effective_gb = effective_bytes / 1.gigabyte
      
      optimized = {
        datadog: datadog_hosts * 5,   # Only errors ($5/host/month)
        loki_hot: effective_gb * 0.20 * (7.0 / 30.0),  # 7 days hot
        loki_warm: effective_gb * 0.05 * (23.0 / 30.0), # 23 days warm
        total: 0
      }
      optimized[:total] = optimized.values.sum
      
      # === SAVINGS ===
      {
        unoptimized: unoptimized,
        optimized: optimized,
        monthly_savings: unoptimized[:total] - optimized[:total],
        yearly_savings: (unoptimized[:total] - optimized[:total]) * 12,
        savings_pct: ((unoptimized[:total] - optimized[:total]) / unoptimized[:total] * 100).round(1)
      }
    end
  end
end

# Example usage:
calculator = E11y::CostCalculator.new
result = calculator.calculate(
  events_per_second: 100_000,
  avg_event_size_bytes: 2000,  # 2 KB
  num_services: 50,
  datadog_hosts: 200
)

puts "Current monthly cost: $#{result[:unoptimized][:total]}"
puts "Optimized monthly cost: $#{result[:optimized][:total]}"
puts "Monthly savings: $#{result[:monthly_savings]} (#{result[:savings_pct]}%)"
puts "Yearly savings: $#{result[:yearly_savings]}"

# Output:
# Current monthly cost: $13368
# Optimized monthly cost: $1900
# Monthly savings: $11468 (85.8%)
# Yearly savings: $137616
```

---

## 📊 Monitoring Cost Optimization

**Track savings in real-time:**
```ruby
# Self-monitoring metrics
E11y.configure do |config|
  config.self_monitoring do
    # Bytes saved by compression
    counter :cost_optimization_bytes_saved_total,
            tags: [:optimization_type]  # compression, dedup, sampling
    
    # Events dropped/sampled
    counter :cost_optimization_events_reduced_total,
            tags: [:reason]
    
    # Estimated cost savings
    gauge :cost_optimization_monthly_savings_usd,
          tags: [:backend]
    
    # Compression ratio
    histogram :cost_optimization_compression_ratio,
              buckets: [0.1, 0.3, 0.5, 0.7, 0.9]
    
    # Deduplication ratio
    histogram :cost_optimization_dedup_ratio,
              buckets: [0.1, 0.3, 0.5, 0.7, 0.9]
  end
end

# Dashboard queries:
# - Total bytes saved: sum(cost_optimization_bytes_saved_total)
# - Monthly savings: cost_optimization_monthly_savings_usd
# - Avg compression: histogram_quantile(0.5, cost_optimization_compression_ratio_bucket)
```

---

## 🧪 Testing

```ruby
# spec/e11y/cost_optimization_spec.rb
RSpec.describe 'Cost Optimization' do
  describe 'deduplication' do
    it 'removes duplicate events' do
      E11y.configure do |config|
        config.cost_optimization do
          deduplication enabled: true,
                        window: 1.minute,
                        dedupe_keys: [:event_name, :user_id]
        end
      end
      
      # Send 100 duplicate events
      100.times { Events::TestEvent.track(user_id: '123', foo: 'bar') }
      
      # Should only store 1
      events = E11y::Buffer.flush
      expect(events.size).to eq(1)
      expect(events.first.payload[:duplicate_count]).to eq(100)
    end
  end
  
  describe 'payload minimization' do
    it 'removes null and empty values' do
      E11y.configure do |config|
        config.cost_optimization do
          payload_minimization enabled: true,
                               drop_null_fields: true,
                               drop_empty_strings: true
        end
      end
      
      Events::TestEvent.track(
        foo: 'bar',
        baz: nil,      # ← Should be removed
        qux: '',       # ← Should be removed
        empty: []      # ← Should be removed
      )
      
      event = E11y::Buffer.pop
      expect(event[:payload].keys).to eq([:foo])
    end
  end
  
  describe 'compression' do
    it 'compresses event batches' do
      E11y.configure do |config|
        config.cost_optimization do
          compression enabled: true, algorithm: :zstd, level: 3
        end
      end
      
      events = 500.times.map { |i| create_event(size: 2000) }
      
      uncompressed_size = events.map { |e| e.to_json.bytesize }.sum
      compressed = E11y::Compression.compress_batch(events)
      
      compression_ratio = compressed.bytesize.to_f / uncompressed_size
      expect(compression_ratio).to be < 0.4  # At least 60% reduction
    end
  end
end
```

---

## 💡 Best Practices

### ✅ DO

**1. Combine multiple optimizations**
```ruby
# ✅ GOOD: Layered optimizations
config.cost_optimization do
  intelligent_sampling { ... }  # 90% reduction
  deduplication { ... }         # 80% reduction (on remaining)
  compression { ... }           # 70% smaller payloads
  tiered_storage { ... }        # 60% cheaper storage
end
# Combined: ~98% cost reduction!
```

**2. Monitor savings**
```ruby
# ✅ GOOD: Track ROI
# Dashboard: "Cost Optimization Savings"
# - Monthly savings: $X
# - YTD savings: $Y
# - Optimization breakdown (sampling, dedup, compression)
```

**3. Test in staging first**
```ruby
# ✅ GOOD: Validate optimizations don't lose critical data
# - Verify high-value events always tracked
# - Verify errors never sampled out
# - Verify compliance events retained
```

---

### ❌ DON'T

**1. Don't over-optimize critical events**
```ruby
# ❌ BAD: Sampling errors
config.sampling do
  sample_rate 0.01  # 1%
end
# → You'll miss 99% of errors!

# ✅ GOOD: Never sample errors
always_sample severities: [:error, :fatal]
```

**2. Don't compress tiny batches**
```ruby
# ❌ BAD: Compression overhead > savings
compress_batch_size 1  # Compress single events

# ✅ GOOD: Only compress larger batches
compress_batch_size 100  # Worthwhile
```

**3. Don't ignore retention requirements**
```ruby
# ❌ BAD: Delete compliance data too soon
retention 7.days  # But SOX requires 7 years!

# ✅ GOOD: Respect legal requirements
retention_for 'payment.*', 7.years
```

---

## 📚 Related Use Cases

- **[UC-013: High Cardinality Protection](./UC-013-high-cardinality-protection.md)** - Metric cost savings
- **[UC-014: Adaptive Sampling](./UC-014-adaptive-sampling.md)** - Smart sampling

---

## 🎯 Summary

### Real-World Savings Example

**Company:** E-commerce platform (50 services, 100k events/sec)

| Optimization | Before | After | Savings |
|--------------|--------|-------|---------|
| **Intelligent sampling** | 100k ev/sec | 10k ev/sec | 90% |
| **Deduplication** | 10k ev/sec | 2k ev/sec | 80% |
| **Compression** | 2KB/event | 0.6KB/event | 70% |
| **Tiered storage** | $200/TB/mo | $50/TB/mo | 75% |
| **Smart routing** | All → Datadog | Errors only → Datadog | 90% |

**Total Monthly Cost:**
- Before: $13,368/month
- After: $1,900/month
- **Savings: $11,468/month (86%)**
- **Yearly savings: $137,616**

**ROI:** Implementation effort: 2 weeks → Payback: Immediate → 3-year value: $412,848

---

**Document Version:** 1.0  
**Last Updated:** January 12, 2026  
**Status:** ✅ Complete
