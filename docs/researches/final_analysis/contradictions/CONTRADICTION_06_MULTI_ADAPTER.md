# TRIZ Contradiction #6: Multi-Adapter Routing

**Created:** 2026-01-15  
**Priority:** 🟡 MEDIUM  
**Domain:** Integration

---

## 📋 Technical Contradiction

**Want to improve:** Flexibility (different adapter configs per event: batch_size, timeout)  
**But this worsens:** DRY principle (global adapter registry encourages configure once, reuse)

**From:** ADR-004 (Contradiction #1), UC-002 (Contradiction #1)

---

## 🎯 IFR

"Each event uses optimal adapter configuration without duplicating adapter instance creation code."

---

## 💡 TRIZ Solutions

### 1. **Nested Doll (TRIZ #7)** - Adapter Variants
**Proposed:** Register multiple variants of same adapter:
```ruby
config.register_adapter :loki_fast, Loki.new(batch_size: 10, timeout: 1.second)
config.register_adapter :loki_slow, Loki.new(batch_size: 500, timeout: 10.seconds)

class Events::CriticalError < E11y::Event::Base
  adapters [:loki_fast]  # Uses fast variant
end

class Events::BulkImport < E11y::Event::Base
  adapters [:loki_slow]  # Uses slow variant
end
```

**Evaluation:** ⭐⭐⭐ (3/5) - Defeats DRY but solves flexibility

### 2. **Dynamism (TRIZ #15)** - Dynamic Adapter Config
**Proposed:** Adapter config adapts based on event:
```ruby
config.register_adapter :loki, Loki.new do |event|
  if event[:severity] == :fatal
    { batch_size: 1, timeout: 1.second }  # Immediate flush for fatal
  else
    { batch_size: 500, timeout: 10.seconds }  # Batch for others
  end
end
```

**Evaluation:** ⭐⭐⭐⭐ (4/5) - Flexible but adds complexity

---

## 🏆 Recommendation

**Accept trade-off:** DRY > flexibility (90% of events use same adapter config).  
**For 10% edge cases:** Use Solution #1 (adapter variants).

---

**Status:** ✅ Analysis Complete - **ACCEPT TRADE-OFF**
