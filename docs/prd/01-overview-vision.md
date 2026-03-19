# PRD-01: Overview & Vision

**Document Type:** Product Requirements Document (PRD)  
**Status:** Active  
**Version:** 1.0  
**Last Updated:** January 12, 2026

---

## 📋 Executive Summary

**E11y** (easy telemetry) - production-ready Ruby gem для структурированных бизнес-событий с уникальными killer features:

1. **Request-scoped debug buffering** - debug events только при ошибках (89% reduction)
2. **Event-level metrics DSL** - автоматические метрики без boilerplate
3. **Zero-config SLO tracking** - built-in monitoring одной строкой конфига

**Target Market:** Ruby/Rails teams (5-100 engineers)  
**Problem:** Observability сложна, дорога и перегружена шумом  
**Solution:** Простой, Rails-first gem с production-ready defaults

---

## 🎯 Vision

### Long-Term Vision (3 years)

**"The default observability solution for Ruby/Rails applications"**

- ✅ **Installed in 50%+ new Rails apps**
- ✅ **Referenced in official Rails guides**
- ✅ **Community standard for business events**
- ✅ **Lower barrier to production-grade observability**

### Short-Term Vision (1 year)

**"Production-ready alternative to expensive SaaS tools"**

- ✅ **1,000+ RubyGems downloads/month**
- ✅ **500+ production deployments**
- ✅ **Cost savings: $10k-100k/year per company**

---

## 🔴 Problem Statement

### Current Pain Points

#### 1. Observability is Too Complex

**Problem:**
- OpenTelemetry: 5+ docs pages just to get started
- Sentry: expensive, only errors
- ELK: complex setup, maintenance burden
- Datadog: $10k+/month, lock-in

**Impact:**
- Small teams skip observability (can't debug production)
- Medium teams over-invest in setup (1-2 weeks)
- Large teams pay high costs ($50k-$200k/year)

---

#### 2. Logs are Noisy

**Problem:**
- Debug logs in production = 99% noise
- "Solved" by disabling debug → blind debugging
- No middle ground: either noise or blindness

**Impact:**
- Searching 1M log lines for 1 error
- High storage costs ($500+/month)
- Slow queries (30+ seconds to search)

**Real Example:**
```
[DEBUG] Query: SELECT * FROM orders WHERE...  ← 99% useless
[DEBUG] Cache miss for key: order_123         ← 99% useless
[DEBUG] Rendering template: orders/show       ← 99% useless
[INFO] Order created: 123                     ← Useful
[DEBUG] Query: SELECT * FROM ...              ← 99% useless
[ERROR] Payment failed: Stripe timeout        ← Useful!
```

**99 successful requests:** 297 debug lines (useless) + 99 info lines = 396 lines  
**1 failed request:** 3 debug lines (useful!) + 1 error = 4 lines  
**Total noise:** 297/400 = 74%

---

#### 3. Metrics are Manual & Error-Prone

**Problem:**
```ruby
# Current approach: manual duplication
Rails.logger.info "Order #{order.id} paid"
OrderMetrics.increment('orders.paid.total')   # ← Forgot to add currency tag!
OrderMetrics.observe('orders.paid.amount', order.amount)  # ← Different field name!
```

**Impact:**
- Inconsistent metrics (typos, missing tags)
- Code duplication (event + metrics)
- High cardinality explosions ($68k/month Datadog bills)

---

#### 4. No Business Context in Tech Logs

**Problem:**
- Rails.logger mixes tech + business events
- Hard to answer business questions:
  - "How many orders paid today?"
  - "What's our payment success rate?"
  - "Which users are most active?"

**Impact:**
- Can't build funnels, cohorts, retention
- Need separate analytics tool (Mixpanel, Amplitude)
- Duplicate instrumentation

---

## ✅ Solution: E11y Gem

### Core Value Proposition

**"Production-grade observability in 5 minutes, not 5 weeks"**

### How E11y Solves Each Problem

#### 1. Simplicity

**One-line install:**
```bash
gem install e11y
rails g e11y:install
```

**One-line config:**
```ruby
E11y.configure { |config| config.slo_tracking = true }
```

**Result:** Full observability (logs, metrics, traces) in 5 minutes.

---

#### 2. Intelligent Noise Reduction

**Request-scoped debug buffering:**
- Debug events buffered in memory
- Success → drop buffer (zero noise)
- Error → flush buffer (full context)

**Result:** 89% log volume reduction, debug only when needed.

---

#### 3. Automatic Metrics

**Event-level metrics DSL:**
```ruby
# Define event once with metrics
class Events::OrderPaid < E11y::Event::Base
  schema { required(:order_id).filled(:string); required(:amount).filled(:float); optional(:currency).maybe(:string) }
  metrics do
    counter :orders_paid_total, tags: [:currency]
    histogram :order_amount, value: :amount, tags: [:currency]
  end
end

Events::OrderPaid.track(order_id: '123', amount: 99, currency: 'USD')
# → orders_paid_total{currency="USD"} = 1, order_amount{currency="USD"} = 99
```

**Result:** No boilerplate, no duplication, consistent.

---

#### 4. Business-Friendly Events

**Structured events with schemas:**
```ruby
class Events::OrderPaid < E11y::Event
  attribute :order_id, Types::String
  attribute :amount, Types::Decimal
  attribute :currency, Types::String
  default_severity :success  # ← Easy to filter!
end
```

**Result:** Queryable, type-safe, answers business questions.

---

## 🎯 Target Market & ICP

### Primary: Small Teams (5-20 engineers)

**Characteristics:**
- 1-5 Rails apps
- 1K-50K users
- Limited DevOps resources
- Cost-sensitive ($0-$1k/month budget)

**Needs:**
- Zero-config defaults
- Simple setup (<1 hour)
- Low maintenance
- Predictable costs

**Buying Signals:**
- "Can't afford Datadog"
- "Need better production debugging"
- "Rails.logger is not enough"

---

### Secondary: Medium Teams (20-100 engineers)

**Characteristics:**
- 5-20 microservices
- 50K-500K users
- Dedicated DevOps team
- Observability budget $5k-20k/month

**Needs:**
- Standardization across services
- Cost optimization (cardinality protection)
- Multi-adapter support
- Team-wide conventions

**Buying Signals:**
- "Our Datadog bill is $10k/month"
- "High cardinality killed Prometheus"
- "Need business metrics, not just tech"

---

## 🚀 Key Differentiators

### vs OpenTelemetry Ruby

| Feature | OTel | E11y |
|---------|------|------|
| **Setup complexity** | High (5+ pages) | Low (1 line) |
| **Rails integration** | Manual | Automatic |
| **Request-scoped buffering** | ❌ | ✅ |
| **Event-level metrics DSL** | ❌ | ✅ |
| **SLO tracking** | Manual setup | One-line config |
| **Target audience** | Polyglot teams | Rails teams |

**When to use OTel:** Multi-language services, need industry standard  
**When to use E11y:** Rails-focused, want simplicity

---

### vs Sentry

| Feature | Sentry | E11y |
|---------|--------|------|
| **Focus** | Errors only | Events + metrics + traces |
| **Business events** | ❌ | ✅ |
| **Metrics** | Limited | Full Prometheus |
| **Cost** | $29-$999+/month | Free (OSS) |
| **Vendor lock-in** | ✅ | ❌ (pluggable adapters) |

**When to use Sentry:** Only need error tracking  
**When to use E11y:** Need full observability

---

### vs Datadog/New Relic

| Feature | Datadog | E11y |
|---------|---------|------|
| **Cost** | $10k-$200k/year | Free (OSS) + infra costs |
| **Setup** | Agent + SDK | One gem |
| **Cardinality** | $68k/month explosions | Built-in protection |
| **Customization** | Limited | Full control (OSS) |
| **Data ownership** | Vendor | Your infrastructure |

**When to use Datadog:** Enterprise, need support contract  
**When to use E11y:** Want control, reduce costs

---

## 💰 Business Model

### Free Tier (OSS) - Primary Focus

**Features:**
- ✅ Full gem functionality
- ✅ Community support (GitHub, Discord)
- ✅ All documentation
- ✅ Self-hosted

**Target:** Small to medium teams

**Revenue:** $0 (community building phase)

---

### Future Monetization (v2.0+)

**Pro Tier ($99/month):**
- Zero-code instrumentation
- Advanced sampling (tail-based)
- Audit trails with signing
- Priority support

**Enterprise Tier (Custom):**
- SLA guarantees
- Custom integrations
- Training & consulting
- White-labeling

---

## 📊 Success Metrics

### Adoption Metrics

**Month 1 (July 2025):**
- RubyGems downloads: >1,000
- GitHub stars: >200
- Production deployments: >10

**Month 6 (December 2025):**
- RubyGems downloads: >10,000
- GitHub stars: >1,000
- Production deployments: >200

**Month 12 (June 2026):**
- RubyGems downloads: >50,000
- GitHub stars: >2,000
- Production deployments: >500

---

### Customer Success Metrics

**Technical:**
- Time to first event: <15 minutes (target)
- P95 adoption (>10 events tracked): <1 hour
- Production readiness: <1 day

**Business:**
- Log volume reduction: >80%
- Storage cost savings: >$400/month
- Observability cost reduction: >50% (vs Datadog)
- Developer satisfaction: NPS >40

---

## 🎯 Goals & Non-Goals

### Goals (In Scope)

**MVP (Phase 1):**
✅ Event DSL with type safety  
✅ Request-scoped debug buffering  
✅ PII filtering (Rails-compatible)  
✅ Multiple adapters (Stdout, File, Loki, Sentry)  
✅ Rate limiting  
✅ <1ms p99 latency

**v1.0 (Phase 5):**
✅ Event-level metrics (Yabeda)  
✅ Zero-config SLO tracking  
✅ OpenTelemetry integration  
✅ Cardinality protection  
✅ Self-monitoring  
✅ Production-grade documentation

---

### Non-Goals (Out of Scope)

**MVP:**
❌ Zero-code instrumentation (v2.0)  
❌ Audit trails with signing (v2.0)  
❌ Tail-based sampling (v1.1)  
❌ ML-based anomaly detection (v2.0+)  
❌ Multi-language SDKs (focus on Ruby)

**Ever:**
❌ SaaS hosted solution (OSS focus)  
❌ Frontend/browser instrumentation (backend-focused)  
❌ APM features (latency profiling) - use dedicated tools

---

## 🚦 Launch Strategy

### Phase 1: Early Adopters (Months 1-3)

**Target:** 10-50 teams

**Strategy:**
- Personal outreach (Ruby influencers)
- Blog posts (Dev.to, Medium)
- Reddit (r/ruby, r/rails)
- Twitter threads

---

### Phase 2: Community Growth (Months 4-6)

**Target:** 50-200 teams

**Strategy:**
- Customer case studies
- YouTube tutorials
- Podcast appearances
- Integration partners

---

### Phase 3: Mainstream (Months 7-12)

**Target:** 200-500 teams

**Strategy:**
- Conference talks (RailsConf, RubyKaigi)
- Official Rails guides (if accepted)
- Training courses (Gorails)
- Enterprise support offering

---

## 📚 Related Documents

- **[PRD-02: Functional Requirements](./02-functional-requirements.md)** - What the gem does
- **[PRD-03: User Stories](./03-user-stories.md)** - By persona
- **[PRD-05: Competitive Analysis](./05-competitive-analysis.md)** - Detailed comparison
- **[00. ICP & Timeline](../00-ICP-AND-TIMELINE.md)** - Target users, roadmap

---

**Document Version:** 1.0  
**Status:** ✅ Complete  
**Next Review:** March 2025 (after MVP beta)
