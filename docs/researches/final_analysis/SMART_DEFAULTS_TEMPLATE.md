# Smart Defaults & Simplified Initializer Template

**Created:** 2026-01-15  
**Purpose:** Zero-config starting point

---

## 🎯 Minimal Configuration Template (<100 Lines)

```ruby
# config/initializers/e11y.rb (~80 lines)

E11y.configure do |config|
  # ===== ADAPTERS (30 lines) =====
  config.adapters do
    register :loki, E11y::Adapters::Loki.new(url: ENV['LOKI_URL'])
    register :sentry, E11y::Adapters::Sentry.new(dsn: ENV['SENTRY_DSN'])
    default_adapters [:loki]
  end
  
  # ===== GLOBAL LIMITS (20 lines) =====
  config.rate_limiting.global_limit 10_000  # events/sec
  config.buffering.adaptive.memory_limit_mb 100
  
  # ===== OPTIONAL OVERRIDES (30 lines) =====
  # Only if defaults don't fit:
  # config.defaults.sample_rate_for_severity do
  #   success 0.05  # 5% instead of 10%
  # end
end
```

---

## 📋 Smart Defaults Reference

All defaults built into gem (NO config needed):

| Feature | Convention | Default Value |
|---------|-----------|---------------|
| **Severity** | From event name (`*Paid` → :success) | :info |
| **Adapters** | From severity (:error → [:sentry]) | [:loki] |
| **Sample Rate** | From severity (:success → 0.1) | 0.1 |
| **Rate Limit** | Global default | 1000/sec |
| **Retention** | From severity (:error → 90d) | 30 days |

---

**Total:** ~80 lines (vs. 1400+ before) = **94% reduction for common case!**
