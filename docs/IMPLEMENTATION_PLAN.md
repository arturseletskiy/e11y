# E11y Gem: 6-Level Implementation Plan

**Created:** 2026-01-17  
**Updated:** 2026-01-17 (Added Phase 0: Gem Best Practices Research)  
**Based On:** 38 documents analysis (22 UC + 16 ADR), 21 conflicts resolved  
**Target Scale:** Small (1K events/sec) → Medium (10K) → Large (100K)  
**Strategy:** Maximum parallelization + Minimal integration overhead  
**Quality Standard:** Professional Rails gem (Rails 8+ compatibility)

---

## 📊 EXECUTIVE SUMMARY

### Key Metrics
- **Total Phases:** 6 phases (Phase 0: Gem Setup → Phase 5: Scale)
- **Parallelizable Streams:** 4-6 developers can work simultaneously
- **Critical Path:** Phase 0 → Foundation → Core → Rails (phases 0-3 sequential)
- **Estimated Effort:** ~23-27 weeks (with proper parallelization)
- **ADR Coverage:** 16 ADRs fully implemented
- **UC Coverage:** 22 Use Cases fully implemented

### Parallelization Strategy
- **Phase 0 (Gem Setup):** 1-2 devs, Week -1 (BEFORE Phase 1)
- **Phase 1 (Foundation):** 3 parallel streams
- **Phase 2 (Core):** 5 parallel streams
- **Phase 3 (Rails):** 4 parallel streams
- **Phase 4 (Production):** 6 parallel streams
- **Phase 5 (Scale):** 3 parallel streams

### Integration Points (CRITICAL for Parallel Work)
1. **Event::Base Interface** (Level 2.1) - Contract for всех components
2. **Middleware::Base Contract** (Level 2.2) - Pipeline interface
3. **Adapter::Base Contract** (Level 2.4) - Adapter interface
4. **Buffer Interface** (Level 2.3) - Buffering contract

---

## 🎯 PLAN STRUCTURE

### Level 1: PHASES (6 Strategic Phases)

```
PHASE 0: GEM SETUP & BEST PRACTICES (Week -1) 🆕
  ├─ Research: Devise, Sidekiq, Puma, Dry-rb, Yabeda, Sentry
  ├─ Gem Structure & Conventions
  ├─ CI/CD Setup (GitHub Actions, RSpec, Rubocop)
  └─ Documentation Standards (YARD, README, Guides)

PHASE 1: FOUNDATION (Weeks 1-4)
  ├─ Zero-Allocation Event Base
  ├─ Adaptive Buffer (C20)
  └─ Middleware Pipeline

PHASE 2: CORE FEATURES (Weeks 5-10)
  ├─ PII Filtering & Security (C01, C19)
  ├─ Adapter Architecture (C04, C06)
  ├─ Metrics & Yabeda (C03, C11)
  └─ Sampling & Cost Optimization (C05, C11)

PHASE 3: RAILS INTEGRATION (Weeks 11-14)
  ├─ Railtie & Auto-Configuration
  ├─ ActiveSupport::Notifications Bridge (Unidirectional!)
  ├─ Sidekiq/ActiveJob Integration (C17, C18)
  └─ Rails.logger Migration (UC-016)

PHASE 4: PRODUCTION HARDENING (Weeks 15-20)
  ├─ Reliability & Error Handling (C02, C06, C18)
  ├─ OpenTelemetry Integration (C08)
  ├─ Event Evolution & Versioning (C15)
  └─ SLO Tracking & Self-Monitoring (C11, C14)

PHASE 5: SCALE & OPTIMIZATION (Weeks 21-26)
  ├─ High Cardinality Protection (C13)
  ├─ Tiered Storage Migration (UC-019)
  ├─ Performance Optimization (1K → 10K → 100K)
  └─ Production Deployment & Documentation
```

---

## 📋 LEVEL 2-6 BREAKDOWN

### Legend:
- 🔴 **CRITICAL** - Blocking dependency for other tasks
- 🟠 **HIGH** - Important for feature completeness
- 🟡 **MEDIUM** - Nice-to-have, can be deferred
- ⚙️ **PARALLELIZABLE** - Can be worked on simultaneously
- 🔗 **DEPENDS ON** - Explicit dependency
- ✅ **DoD** - Definition of Done (acceptance criteria)

---

## PHASE 0: GEM SETUP & BEST PRACTICES (Week -1) 🆕

**Purpose:** Research and setup professional gem structure BEFORE coding  
**Timeline:** Week -1 (1 week, BEFORE Phase 1 starts)  
**Team:** 1-2 developers  
**Critical:** ⚠️ MUST COMPLETE BEFORE PHASE 1

---

### L2.0: Gem Structure & Best Practices Research 🔴

**Purpose:** Learn from successful gems, establish conventions  
**Depends On:** None (foundation)  
**Parallelizable:** ⚙️ 1-2 devs (can split research + setup)

---

#### L3.0.1: Best Practices Research

**Tasks:**

1. **Study Successful Rails Gems (20 hours)**
   - **Devise** (authentication)
     - Controller/view overrides pattern
     - Modular design (strategies, modules)
     - Configuration DSL
     - ✅ DoD: Document 5+ patterns in `docs/research/devise_patterns.md`
   
   - **Sidekiq** (background jobs)
     - Middleware pattern
     - Configuration DSL (simple blocks)
     - Redis integration patterns
     - Error handling & retry logic
     - ✅ DoD: Document 5+ patterns in `docs/research/sidekiq_patterns.md`
   
   - **Puma** (web server)
     - Configuration DSL
     - Plugin system
     - Thread safety patterns
     - ✅ DoD: Document 5+ patterns in `docs/research/puma_patterns.md`
   
   - **Dry-rb gems** (dry-schema, dry-validation, dry-types)
     - Functional design
     - Composition patterns
     - Type system
     - Schema DSL
     - ✅ DoD: Document 5+ patterns in `docs/research/dry_rb_patterns.md`
   
   - **Yabeda** (metrics)
     - DSL design (counter, histogram, gauge)
     - Extensibility (adapters, collectors)
     - Rails integration
     - ✅ DoD: Document 5+ patterns in `docs/research/yabeda_patterns.md`
   
   - **Sentry-ruby** (error tracking)
     - Rails integration (Railtie)
     - Configuration management
     - Context propagation
     - Async processing
     - ✅ DoD: Document 5+ patterns in `docs/research/sentry_patterns.md`

2. **Gem Structure Analysis (8 hours)**
   - Directory structure conventions
   - File naming patterns
   - Module organization (E11y::, E11y::Instruments::, etc.)
   - Autoloading strategy (Zeitwerk best practices)
   - Gemspec best practices
   - ✅ DoD: `docs/research/gem_structure_template.md`

3. **Configuration DSL Patterns (8 hours)**
   - Block-based DSL (`E11y.configure { |config| ... }`)
   - Nested configuration (`config.adapters do ... end`)
   - Type validation (dry-types integration?)
   - Environment-specific config
   - Override patterns (Devise-style)
   - ✅ DoD: `docs/research/configuration_dsl_design.md`

4. **Testing Strategies (6 hours)**
   - RSpec setup (spec_helper, rails_helper)
   - Test organization (unit, integration, system)
   - Test factories (FactoryBot vs Plain Ruby)
   - Contract tests for public APIs
   - Rails integration testing patterns
   - Load testing setup
   - Coverage requirements (aim for 100%)
   - ✅ DoD: `docs/research/testing_strategy.md`

5. **Documentation Standards (6 hours)**
   - YARD documentation (inline docs)
   - README structure (badges, quick start, examples)
   - Guides vs API reference
   - Code examples quality
   - Changelog format (Keep a Changelog)
   - GitHub wiki vs docs/ folder
   - ✅ DoD: `docs/research/documentation_standards.md`

6. **CI/CD Best Practices (4 hours)**
   - GitHub Actions setup
   - Matrix testing (Ruby 3.2, 3.3, Rails 8.0+)
   - Code coverage (SimpleCov)
   - Linting (Rubocop, StandardRB)
   - Security scanning (Brakeman, Bundler Audit)
   - Release automation
   - ✅ DoD: `docs/research/ci_cd_setup.md`

7. **Gem Release Process (4 hours)**
   - Semantic versioning strategy
   - Changelog generation
   - RubyGems release checklist
   - GitHub releases with notes
   - Deprecation warnings strategy
   - Breaking change communication
   - ✅ DoD: `docs/research/gem_release_process.md`

**Verification (L6):**
- All research documents created and reviewed
- Team meeting: Present findings (1 hour)
- Consensus on patterns to use

---

#### L3.0.2: Project Skeleton Setup

**Tasks:**

1. **Initialize Gem (1 hour)**
   ```bash
   bundle gem e11y --mit --test=rspec --ci=github --linter=rubocop
   ```
   - MIT License
   - RSpec testing
   - GitHub Actions CI
   - Rubocop linting
   - ✅ DoD: Gem skeleton created, `git init` done

2. **Setup Directory Structure (2 hours)**
   ```
   e11y/
   ├── lib/
   │   ├── e11y.rb                      # Main entry point
   │   └── e11y/
   │       ├── version.rb
   │       ├── configuration.rb
   │       ├── event/
   │       │   └── base.rb
   │       ├── middleware/
   │       │   └── base.rb
   │       ├── adapters/
   │       │   └── base.rb
   │       ├── buffers/
   │       │   └── base_buffer.rb
   │       ├── instruments/
   │       │   └── rails_instrumentation.rb
   │       └── railtie.rb               # Rails integration
   ├── spec/
   │   ├── spec_helper.rb
   │   ├── rails_helper.rb
   │   ├── support/
   │   │   ├── shared_examples/
   │   │   └── helpers/
   │   └── e11y/
   │       ├── event/
   │       ├── middleware/
   │       └── adapters/
   ├── benchmarks/
   │   ├── e11y_benchmarks.rb
   │   └── load_tests.rb
   ├── docs/
   │   ├── guides/
   │   ├── research/                    # Research from L3.0.1
   │   └── (existing ADR, UC files)
   ├── bin/
   │   ├── console                      # IRB with E11y loaded
   │   └── setup                        # Setup script
   ├── .github/
   │   └── workflows/
   │       ├── ci.yml
   │       └── release.yml
   ├── docker-compose.yml               # Test backends
   ├── Gemfile
   ├── e11y.gemspec
   ├── Rakefile
   ├── .rubocop.yml
   ├── .gitignore
   └── README.md
   ```
   - ✅ DoD: Professional gem structure

3. **Setup Zeitwerk Autoloading (1 hour)**
   ```ruby
   # lib/e11y.rb
   require 'zeitwerk'
   
   loader = Zeitwerk::Loader.for_gem
   loader.setup
   
   module E11y
     # Gem entry point
   end
   ```
   - Test autoloading works
   - ✅ DoD: `require 'e11y'` loads all files correctly

4. **Setup CI/CD - GitHub Actions (2 hours)**
   ```yaml
   # .github/workflows/ci.yml
   name: CI
   on: [push, pull_request]
   
   jobs:
     test:
       runs-on: ubuntu-latest
       strategy:
         fail-fast: false
         matrix:
           ruby: ['3.2', '3.3']
           rails: ['8.0']
       
       steps:
         - uses: actions/checkout@v4
         
         - name: Set up Ruby
           uses: ruby/setup-ruby@v1
           with:
             ruby-version: ${{ matrix.ruby }}
             bundler-cache: true
         
         - name: Run tests
           run: bundle exec rspec
         
         - name: Run linter
           run: bundle exec rubocop
         
         - name: Check coverage
           run: |
             bundle exec rspec
             cat coverage/.last_run.json | jq '.result.line'
   ```
   - ✅ DoD: CI runs on every commit, badge in README

5. **Setup Docker Compose (Test Backends) (2 hours)**
   ```yaml
   # docker-compose.yml
   version: '3.8'
   services:
     loki:
       image: grafana/loki:2.9.0
       ports:
         - "3100:3100"
       volumes:
         - ./config/loki-local-config.yaml:/etc/loki/local-config.yaml
     
     prometheus:
       image: prom/prometheus:v2.45.0
       ports:
         - "9090:9090"
     
     elasticsearch:
       image: elasticsearch:8.9.0
       ports:
         - "9200:9200"
       environment:
         - discovery.type=single-node
         - xpack.security.enabled=false
     
     redis:
       image: redis:7-alpine
       ports:
         - "6379:6379"
   ```
   - ✅ DoD: `docker-compose up` runs all backends

6. **Setup SimpleCov (Code Coverage) (1 hour)**
   ```ruby
   # spec/spec_helper.rb
   require 'simplecov'
   
   SimpleCov.start do
     add_filter '/spec/'
     add_filter '/benchmarks/'
     
     minimum_coverage 100  # Enforce 100% coverage!
     refuse_coverage_drop  # Fail if coverage decreases
   end
   ```
   - ✅ DoD: Coverage enforced in CI

7. **Setup Rubocop (Linting) (1 hour)**
   ```yaml
   # .rubocop.yml
   require:
     - rubocop-performance
     - rubocop-rspec
   
   AllCops:
     TargetRubyVersion: 3.2
     NewCops: enable
     Exclude:
       - 'vendor/**/*'
       - 'benchmarks/**/*'
   
   Style/Documentation:
     Enabled: true  # Enforce YARD docs!
   
   Metrics/BlockLength:
     Exclude:
       - 'spec/**/*'
   
   Metrics/MethodLength:
     Max: 15
   
   Metrics/ClassLength:
     Max: 100
   ```
   - ✅ DoD: Linting passes in CI

8. **Setup Gemspec (1 hour)**
   ```ruby
   # e11y.gemspec
   Gem::Specification.new do |spec|
     spec.name = "e11y"
     spec.version = E11y::VERSION
     spec.authors = ["Your Team"]
     spec.email = ["team@example.com"]
     
     spec.summary = "Event-driven observability gem for Rails 8+"
     spec.description = "Structured business events with request-scoped buffering, pattern-based metrics, and zero-config SLO tracking"
     spec.homepage = "https://github.com/yourorg/e11y"
     spec.license = "MIT"
     spec.required_ruby_version = ">= 3.2.0"
     
     spec.metadata["homepage_uri"] = spec.homepage
     spec.metadata["source_code_uri"] = spec.homepage
     spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
     
     spec.files = Dir["{lib,docs}/**/*", "LICENSE.txt", "README.md", "CHANGELOG.md"]
     spec.require_paths = ["lib"]
     
     # Runtime dependencies
     spec.add_dependency "rails", ">= 8.0.0"
     spec.add_dependency "zeitwerk", "~> 2.6"
     spec.add_dependency "dry-schema", "~> 1.13"
     spec.add_dependency "concurrent-ruby", "~> 1.2"
     
     # Development dependencies
     spec.add_development_dependency "rspec", "~> 3.12"
     spec.add_development_dependency "rubocop", "~> 1.57"
     spec.add_development_dependency "rubocop-performance", "~> 1.19"
     spec.add_development_dependency "rubocop-rspec", "~> 2.25"
     spec.add_development_dependency "simplecov", "~> 0.22"
   end
   ```
   - ✅ DoD: `gem build e11y.gemspec` succeeds

**Verification (L6):**
- Gem builds: `gem build e11y.gemspec`
- Tests run: `bundle exec rspec` (even if empty)
- Linting passes: `bundle exec rubocop`
- CI green: GitHub Actions badge
- Docker Compose: `docker-compose up` runs all services

---

#### L3.0.3: Research Documentation Deliverables

**Deliverables:**

1. **`docs/research/devise_patterns.md`** - Controller overrides, modular design
2. **`docs/research/sidekiq_patterns.md`** - Middleware, configuration, error handling
3. **`docs/research/puma_patterns.md`** - Configuration DSL, plugins, thread safety
4. **`docs/research/dry_rb_patterns.md`** - Functional design, composition, types
5. **`docs/research/yabeda_patterns.md`** - Metrics DSL, extensibility
6. **`docs/research/sentry_patterns.md`** - Rails integration, context propagation
7. **`docs/research/gem_structure_template.md`** - Directory conventions, autoloading
8. **`docs/research/configuration_dsl_design.md`** - DSL patterns, type validation
9. **`docs/research/testing_strategy.md`** - RSpec setup, coverage, factories
10. **`docs/research/documentation_standards.md`** - YARD, README, guides
11. **`docs/research/ci_cd_setup.md`** - GitHub Actions, matrix testing
12. **`docs/research/gem_release_process.md`** - Versioning, changelog, deprecation

**Review Meeting (2 hours):**
- Present research findings to team
- Decide which patterns to adopt
- Update ADRs if needed (architectural decisions from research)

---

## PHASE 1: FOUNDATION (Weeks 1-4)

### L2.1: Zero-Allocation Event Base 🔴

**ADR:** ADR-001 §2 (Zero-Allocation Design)  
**UC:** UC-002 (Business Event Tracking)  
**Depends On:** None (foundation)  
**Parallelizable:** ⚙️ Core team (1 dev)

#### L3.1.1: Event::Base Class Implementation

**Tasks:**
1. **Create Event::Base Class Structure**
   - File: `lib/e11y/event/base.rb`
   - Zero-allocation design (class methods only)
   - Schema DSL (dry-schema integration)
   - Severity levels (:debug, :info, :success, :warn, :error, :fatal)
   - Version tracking
   - ✅ DoD: All 22 severity-based tests pass

2. **Implement track() Method (Zero-Allocation)**
   - `self.track(**payload)` class method
   - Payload validation (dry-schema)
   - Hash-based event creation (no object instantiation)
   - Return event hash (for testing/debugging)
   - ✅ DoD: <50μs per track() call (benchmark)

3. **Configuration DSL (Event-Level)**
   - `severity(value)` class method
   - `schema(&block)` class method
   - `version(value)` class method
   - `adapters(list)` class method (references)
   - Resolution logic (precedence: explicit > preset > base > convention)
   - ✅ DoD: All 15 configuration tests pass

4. **Convention-Based Defaults (CONTRADICTION_01 Solution)**
   - Severity from event name (`*Failed` → :error, `*Paid` → :success)
   - Adapter from severity (`:error` → `[:sentry]`, others → `[:loki]`)
   - Sample rate from severity (error: 1.0, success: 0.1, debug: 0.01)
   - Retention from severity (error: 90d, success: 30d, debug: 7d)
   - ✅ DoD: Zero config for 90% of events (only schema required)

5. **Base Event Classes & Presets (Inheritance)**
   - `Events::BaseAuditEvent` (audit config)
   - `Events::BasePaymentEvent` (high-value config)
   - `E11y::Presets::HighValueEvent` module
   - `E11y::Presets::DebugEvent` module
   - `E11y::Presets::AuditEvent` module
   - ✅ DoD: 1-5 lines config per event (schema + inheritance)

**Verification (L6):**
- Unit tests: `spec/e11y/event/base_spec.rb` (100+ tests)
- Benchmark: `<50μs` per track() call (p99)
- Memory: Zero allocations (verified via allocation_tracer)
- ADR Compliance: ADR-001 §2 checklist
- UC Compliance: UC-002 §3 (Event DSL requirements)

---

### L2.2: Adaptive Buffer (C20 Resolution) 🔴

**ADR:** ADR-001 §3.3 (Adaptive Buffer with Memory Limits)  
**UC:** UC-001 (Request-Scoped Debug Buffering)  
**Depends On:** None  
**Parallelizable:** ⚙️ Can run parallel to L2.1

#### L3.2.1: RingBuffer (Lock-Free)

**Tasks:**
1. **Implement RingBuffer Class**
   - File: `lib/e11y/buffers/ring_buffer.rb`
   - Fixed capacity SPSC (Single-Producer, Single-Consumer)
   - Atomic operations (`Concurrent::AtomicFixnum`)
   - Backpressure strategies: `:block`, `:drop`, `:throttle`
   - `push(event)`, `pop()`, `flush_all()` methods
   - ✅ DoD: 100K events/sec throughput (benchmark)

2. **Write RingBuffer Tests**
   - Thread safety tests (100+ threads)
   - Backpressure tests (overflow scenarios)
   - Flush tests (partial/full)
   - Memory tests (no leaks)
   - ✅ DoD: 100% code coverage, all concurrency tests pass

**Verification (L6):**
- Unit tests: `spec/e11y/buffers/ring_buffer_spec.rb`
- Concurrency tests: 100+ threads, no data races
- Benchmark: `100K events/sec` throughput (1KB events)
- Memory: No memory leaks (valgrind check)

#### L3.2.2: AdaptiveBuffer (C20 Resolution)

**Tasks:**
1. **Implement AdaptiveBuffer Class**
   - File: `lib/e11y/buffers/adaptive_buffer.rb`
   - Global memory tracking (`@@total_memory_bytes`)
   - Event size estimation (`estimate_size(event)`)
   - Memory limit enforcement (100MB default)
   - Early flush at 80% threshold
   - Backpressure on memory limit exceeded
   - ✅ DoD: Memory <100MB under 10K events/sec load

2. **Memory Size Estimation**
   - `estimate_size(event_hash)` method
   - String size calculation
   - Hash overhead estimation (~40 bytes per key-value)
   - Array overhead estimation
   - ✅ DoD: ±10% accuracy vs actual memory usage

3. **Backpressure Strategies**
   - `:block` - Block track() until memory frees up
   - `:drop` - Drop event, increment drop counter
   - `:throttle` - Sleep 1ms before retry (5 retries max)
   - Metrics: `e11y.buffer.events_dropped`, `e11y.buffer.backpressure_triggered`
   - ✅ DoD: No memory exhaustion under 10K+ events/sec

**Verification (L6):**
- Unit tests: `spec/e11y/buffers/adaptive_buffer_spec.rb`
- Load tests: 10K events/sec for 60 seconds
- Memory tests: Memory stays <100MB (verified)
- ADR Compliance: ADR-001 §3.3 checklist

#### L3.2.3: Request-Scoped Buffer (UC-001)

**Tasks:**
1. **Implement RequestScopedBuffer**
   - File: `lib/e11y/buffers/request_scoped_buffer.rb`
   - Thread-local storage (`ActiveSupport::CurrentAttributes`)
   - Severity-based buffering (`:debug` events only)
   - Auto-flush on error (severity >= `:error`)
   - Auto-flush on request end
   - ✅ DoD: Debug events flushed only on error

2. **Rails Middleware Integration**
   - File: `lib/e11y/middleware/request.rb`
   - Setup request buffer at request start
   - Flush on error (exception caught)
   - Flush on request end (ensure cleanup)
   - Metrics: `e11y.buffer.request_flushes`, `e11y.buffer.debug_events_dropped`
   - ✅ DoD: Zero debug logs in success requests

**Verification (L6):**
- Unit tests: `spec/e11y/buffers/request_scoped_buffer_spec.rb`
- Integration tests: Rails request simulation
- UC Compliance: UC-001 §4 (Auto-Flush Logic)

---

### L2.3: Middleware Pipeline 🔴

**ADR:** ADR-001 §2.2 (Middleware Chain), ADR-015 (Middleware Order)  
**UC:** UC-001, UC-007, UC-011  
**Depends On:** L2.1 (Event::Base), L2.2 (Buffers)  
**Parallelizable:** ⚙️ Can run parallel to L2.2

#### L3.3.1: Middleware::Base Contract

**Tasks:**
1. **Create Middleware::Base Class**
   - File: `lib/e11y/middleware/base.rb`
   - `call(event_data)` method contract
   - `@app.call(event_data)` chain pattern
   - Middleware zones support (`:pre_processing`, `:security`, `:routing`, `:post_processing`, `:adapters`)
   - `middleware_zone(zone)` class method
   - ✅ DoD: All middlewares inherit from Base

2. **Pipeline Builder**
   - File: `lib/e11y/pipeline/builder.rb`
   - `use(middleware_class, *args, **options)` method
   - Zone-based organization
   - Middleware ordering validation
   - Boot-time validation (`validate_zones!`)
   - ✅ DoD: Pipeline builds correctly, zones validated

**Verification (L6):**
- Unit tests: `spec/e11y/middleware/base_spec.rb`
- Pipeline tests: `spec/e11y/pipeline/builder_spec.rb`
- ADR Compliance: ADR-015 §3.4 (Middleware Zones)

#### L3.3.2: Core Middlewares (Minimal Set)

**Tasks:**
1. **TraceContext Middleware**
   - File: `lib/e11y/middleware/trace_context.rb`
   - Add `trace_id`, `span_id`, `timestamp` (ISO8601)
   - Zone: `:pre_processing`
   - ✅ DoD: All events have trace_id

2. **Validation Middleware**
   - File: `lib/e11y/middleware/validation.rb`
   - Schema validation (dry-schema)
   - Original class name validation
   - Zone: `:pre_processing`
   - ✅ DoD: Invalid events rejected with clear error

3. **Versioning Middleware (LAST!)**
   - File: `lib/e11y/middleware/versioning.rb`
   - Normalize event_name (`Events::OrderPaidV2` → `Events::OrderPaid`)
   - Add `v: 2` to payload
   - Zone: `:post_processing` (LAST before routing!)
   - ✅ DoD: All business logic uses original class name

4. **Routing Middleware**
   - File: `lib/e11y/middleware/routing.rb`
   - Route to buffer (main, request-scoped, audit)
   - Adapter routing based on event config
   - Zone: `:adapters`
   - ✅ DoD: Events routed to correct buffer

**Verification (L6):**
- Unit tests: Each middleware has 100% coverage
- Integration tests: Full pipeline execution
- ADR Compliance: ADR-015 §3.1 (Correct Order)

---

## PHASE 2: CORE FEATURES (Weeks 5-10)

### L2.4: PII Filtering & Security (C01, C19) 🔴

**ADR:** ADR-006 (Security & Compliance), ADR-015 §3.3 (Audit Pipeline)  
**UC:** UC-007 (PII Filtering), UC-012 (Audit Trail)  
**Depends On:** L2.1, L2.3 (Middleware Pipeline)  
**Parallelizable:** ⚙️ Stream A (1-2 devs)

#### L3.4.1: PII Filtering Middleware

**Tasks:**
1. **PIIFiltering Middleware**
   - File: `lib/e11y/middleware/pii_filtering.rb`
   - 3-tier filtering strategy (Tier 1: no PII, Tier 2: hash, Tier 3: mask)
   - Field-level strategies (`:mask`, `:hash`, `:redact`, `:allow`)
   - Pattern-based detection (`/email|password|ssn|card/i`)
   - Zone: `:security` (CRITICAL!)
   - ✅ DoD: All PII fields filtered before adapters

2. **Event-Level PII Configuration**
   - `contains_pii(boolean)` class method
   - `pii_filtering(&block)` DSL
   - `masks(*fields)` shortcut
   - `hashes(*fields)` shortcut
   - `allows(*fields)` shortcut
   - ✅ DoD: Per-event PII rules work correctly

3. **Global PII Patterns**
   - File: `lib/e11y/pii/patterns.rb`
   - Universal patterns (email, password, ssn, credit_card, ip_address)
   - Custom patterns support
   - ✅ DoD: 95%+ PII detection rate (test dataset)

**Verification (L6):**
- Unit tests: `spec/e11y/middleware/pii_filtering_spec.rb`
- Integration tests: Full pipeline with PII events
- UC Compliance: UC-007 §3 (3-Tier Strategy)
- Security audit: GDPR compliance checklist

#### L3.4.2: Audit Pipeline (C01 Resolution)

**Tasks:**
1. **AuditSigning Middleware**
   - File: `lib/e11y/middleware/audit_signing.rb`
   - HMAC-SHA256 signature on original data (pre-PII filtering!)
   - Signature metadata (timestamp, key_id, algorithm)
   - Zone: `:security` (runs INSTEAD of PIIFiltering for audit events)
   - ✅ DoD: Audit events have valid signatures

2. **Audit Pipeline Configuration**
   - `audit_event(boolean)` class method on Event::Base
   - Separate pipeline for audit events (skip PII filtering, rate limiting, sampling)
   - Auto-route to encrypted storage adapter
   - ✅ DoD: Audit events use audit pipeline

3. **AuditEncryptedAdapter**
   - File: `lib/e11y/adapters/audit_encrypted.rb`
   - AES-256-GCM encryption
   - Signature verification before storage
   - File-based storage with encryption
   - ✅ DoD: Audit events stored encrypted with valid signatures

**Verification (L6):**
- Unit tests: `spec/e11y/middleware/audit_signing_spec.rb`
- Integration tests: Full audit pipeline
- Security tests: Signature verification, encryption validation
- ADR Compliance: ADR-015 §3.3 (C01 Resolution)
- UC Compliance: UC-012 §3 (Non-Repudiation)

#### L3.4.3: Middleware Zones (C19 Resolution)

**Tasks:**
1. **Zone Validation**
   - File: `lib/e11y/pipeline/zone_validator.rb`
   - Boot-time zone order validation
   - Runtime zone violation detection
   - Warning system (dev/staging) vs. error (production)
   - ✅ DoD: Invalid middleware order rejected at boot

2. **Custom Middleware Constraints**
   - Zone declaration (`middleware_zone :pre_processing`)
   - `modifies_fields(*fields)` declaration
   - PII bypass detection
   - ✅ DoD: Custom middleware cannot bypass PII filtering

**Verification (L6):**
- Unit tests: `spec/e11y/pipeline/zone_validator_spec.rb`
- Integration tests: Safe vs. unsafe middleware scenarios
- ADR Compliance: ADR-015 §3.4 (C19 Resolution)

---

### L2.5: Adapter Architecture 🟠

**ADR:** ADR-004 (Adapter Architecture)  
**UC:** UC-005 (Sentry), UC-008 (OpenTelemetry)  
**Depends On:** L2.1 (Event::Base)  
**Parallelizable:** ⚙️ Stream B (2-3 devs, can work in parallel with Stream A)

#### L3.5.1: Adapter::Base Contract

**Tasks:**
1. **Create Adapter::Base Class**
   - File: `lib/e11y/adapters/base.rb`
   - `write(event_data)` method
   - `write_batch(events)` method (default: loop `write`)
   - `healthy?()` method
   - `close()` method
   - `capabilities()` method (returns supported features)
   - ✅ DoD: All adapters inherit from Base

2. **Adapter Registry**
   - File: `lib/e11y/adapters/registry.rb`
   - `register(name, adapter_instance)` method
   - `resolve(name)` method
   - Thread-safe registry
   - ✅ DoD: Adapters registered and resolved correctly

**Verification (L6):**
- Unit tests: `spec/e11y/adapters/base_spec.rb`
- Contract tests: All adapters pass contract tests
- ADR Compliance: ADR-004 §2 (Base Adapter Contract)

#### L3.5.2: Built-In Adapters

**Tasks (Parallelizable - Each adapter can be built independently):**

1. **StdoutAdapter** (Priority: HIGH, for dev)
   - File: `lib/e11y/adapters/stdout.rb`
   - Pretty-print events to STDOUT
   - Colorization support (severity-based colors)
   - JSON formatting
   - ✅ DoD: Events printed correctly, colors work

2. **FileAdapter** (Priority: HIGH, for local dev)
   - File: `lib/e11y/adapters/file.rb`
   - JSONL format
   - Log rotation support (size/time-based)
   - Compression support (gzip)
   - ✅ DoD: Events written to file, rotation works

3. **LokiAdapter** (Priority: CRITICAL, main adapter)
   - File: `lib/e11y/adapters/loki.rb`
   - Loki Push API integration
   - Batching (500 events or 5s timeout)
   - Compression (gzip)
   - Label extraction (severity, event_name)
   - ✅ DoD: Events sent to Loki successfully

4. **SentryAdapter** (Priority: HIGH, error tracking)
   - File: `lib/e11y/adapters/sentry.rb`
   - Sentry SDK integration
   - Severity mapping (error/fatal → Sentry)
   - Breadcrumb support
   - Context enrichment
   - ✅ DoD: Errors reported to Sentry with context

5. **ElasticsearchAdapter** (Priority: MEDIUM, optional)
   - File: `lib/e11y/adapters/elasticsearch.rb`
   - Elasticsearch bulk API
   - Index rotation (daily/weekly)
   - Type mapping
   - ✅ DoD: Events indexed in Elasticsearch

6. **InMemoryAdapter** (Priority: HIGH, for tests)
   - File: `lib/e11y/adapters/in_memory.rb`
   - Store events in array
   - Query methods for RSpec assertions
   - ✅ DoD: Test events captured and queryable

**Verification (L6):**
- Unit tests: Each adapter has 100% coverage
- Integration tests: Real backend tests (Docker Compose)
- ADR Compliance: ADR-004 §3 (Built-In Adapters)

#### L3.5.3: Connection Pooling & Retry

**Tasks:**
1. **ConnectionPool**
   - File: `lib/e11y/adapters/connection_pool.rb`
   - Pool size configuration (default: 5)
   - Checkout/checkin pattern
   - Idle timeout
   - ✅ DoD: Connections reused efficiently

2. **RetryHandler (Exponential Backoff + Jitter)**
   - File: `lib/e11y/adapters/retry_handler.rb`
   - Exponential backoff (1s, 2s, 4s, 8s, 16s)
   - Jitter (+/-20%)
   - Retriable errors (network, timeout, 5xx)
   - ✅ DoD: Transient errors retried successfully

3. **CircuitBreaker**
   - File: `lib/e11y/adapters/circuit_breaker.rb`
   - Failure threshold (5 failures → open)
   - Half-open state (test 1 request)
   - Timeout (30s before half-open)
   - ✅ DoD: Cascading failures prevented

**Verification (L6):**
- Unit tests: `spec/e11y/adapters/retry_handler_spec.rb`
- Integration tests: Network failure scenarios
- ADR Compliance: ADR-004 §5 (Error Handling)

#### L3.5.4: Adaptive Batching

**Tasks:**
1. **AdaptiveBatcher**
   - File: `lib/e11y/adapters/adaptive_batcher.rb`
   - Batch size: 500 events (default)
   - Timeout: 5 seconds (default)
   - Flush on batch full or timeout
   - ✅ DoD: Events batched efficiently, latency <5s

**Verification (L6):**
- Unit tests: `spec/e11y/adapters/adaptive_batcher_spec.rb`
- Performance tests: Batching efficiency vs. latency trade-off
- ADR Compliance: ADR-004 §6 (Performance & Batching)

---

### L2.6: Metrics & Yabeda Integration 🟠

**ADR:** ADR-002 (Metrics & Yabeda Integration)  
**UC:** UC-003 (Pattern-Based Metrics), UC-013 (High Cardinality Protection)  
**Depends On:** L2.1 (Event::Base), L2.3 (Middleware Pipeline)  
**Parallelizable:** ⚙️ Stream C (1-2 devs, parallel to Stream A & B)

#### L3.6.1: Yabeda Integration

**Tasks:**
1. **YabedaIntegration Setup**
   - File: `lib/e11y/metrics/yabeda_integration.rb`
   - Yabeda group `:e11y`
   - Auto-register metrics (counters, histograms, gauges)
   - Metric naming convention (`e11y.events.tracked`, `e11y.events.dropped`)
   - ✅ DoD: Metrics exported to Prometheus

2. **Pattern-Based Metrics**
   - File: `lib/e11y/metrics/pattern_matcher.rb`
   - Glob pattern to regex conversion
   - Pattern matching (e.g., `payment.*` matches `payment.succeeded`)
   - Metric configuration DSL
   - ✅ DoD: Patterns match events correctly

3. **Metrics Middleware**
   - File: `lib/e11y/middleware/metrics.rb`
   - Pattern matching
   - Label extraction (from payload)
   - Metric update (counter/histogram/gauge)
   - Zone: `:post_processing`
   - ✅ DoD: Metrics updated for matched events

**Verification (L6):**
- Unit tests: `spec/e11y/metrics/yabeda_integration_spec.rb`
- Integration tests: Full metric collection pipeline
- UC Compliance: UC-003 §3 (Pattern-Based Metrics)
- ADR Compliance: ADR-002 §3 (Yabeda Integration)

#### L3.6.2: Cardinality Protection

**Tasks:**
1. **CardinalityProtection**
   - File: `lib/e11y/metrics/cardinality_protection.rb`
   - 4-layer defense (Denylist, Allowlist, Per-Metric Limits, Dynamic Actions)
   - `FORBIDDEN_LABELS` constant (user_id, email, ip, etc.)
   - `SAFE_LABELS` constant (severity, env, service)
   - Cardinality tracker (per-metric unique values)
   - ✅ DoD: High-cardinality labels rejected

2. **CardinalityTracker**
   - File: `lib/e11y/metrics/cardinality_tracker.rb`
   - Per-metric cardinality tracking
   - Limit enforcement (default: 100 unique values)
   - Metrics: `e11y.metrics.cardinality_exceeded`
   - ✅ DoD: Cardinality explosions prevented

3. **Relabeling Rules**
   - File: `lib/e11y/metrics/relabeling.rb`
   - HTTP status code → class (200-299 → 2xx)
   - Path pattern matching (`/users/123` → `/users/:id`)
   - Regex-based relabeling
   - ✅ DoD: High-cardinality labels transformed

**Verification (L6):**
- Unit tests: `spec/e11y/metrics/cardinality_protection_spec.rb`
- Load tests: High-cardinality scenario (10K+ unique values)
- UC Compliance: UC-013 §3 (4-Layer Defense)
- ADR Compliance: ADR-002 §4 (Cardinality Protection)

---

### L2.7: Sampling & Cost Optimization 🟠

**ADR:** ADR-009 (Cost Optimization), UC-014 (Adaptive Sampling)  
**UC:** UC-014 (Adaptive Sampling), UC-015 (Cost Optimization)  
**Depends On:** L2.1, L2.3 (Middleware Pipeline)  
**Parallelizable:** ⚙️ Stream D (1 dev, parallel to A/B/C)

#### L3.7.1: Sampling Middleware

**Tasks:**
1. **Sampling Middleware**
   - File: `lib/e11y/middleware/sampling.rb`
   - Per-event sample rate (from event config)
   - Severity-based sampling (error: 1.0, success: 0.1, debug: 0.01)
   - Pattern-based sampling (e.g., `debug.*` → 0.01)
   - Zone: `:routing`
   - ✅ DoD: Events sampled according to config

2. **Trace-Aware Sampling (C05 Resolution)**
   - File: `lib/e11y/sampling/trace_aware.rb`
   - Trace-level sampling decision (not per-event)
   - Decision cache (TTL: 60s)
   - W3C Trace Context propagation
   - ✅ DoD: Distributed traces stay intact (all events sampled or none)

3. **Stratified Sampling for SLO (C11 Resolution)**
   - File: `lib/e11y/sampling/stratified.rb`
   - Sample by severity (error: 100%, success: 10%)
   - Sampling correction for metrics
   - ✅ DoD: SLO metrics accurate despite sampling

**Verification (L6):**
- Unit tests: `spec/e11y/middleware/sampling_spec.rb`
- Integration tests: Sampling scenarios
- ADR Compliance: ADR-009 §3.6 (C05), §3.7 (C11)
- UC Compliance: UC-014 §3 (Adaptive Sampling)

---

## PHASE 3: RAILS INTEGRATION (Weeks 11-14)

### L2.8: Railtie & Auto-Configuration 🔴

**ADR:** ADR-008 (Rails Integration)  
**UC:** UC-016 (Rails Logger Migration), UC-017 (Local Development)  
**Depends On:** L2.1-L2.7 (all core features)  
**Parallelizable:** ⚙️ Stream A (1-2 devs)

#### L3.8.1: Railtie Implementation

**Tasks:**
1. **E11y::Railtie**
   - File: `lib/e11y/railtie.rb`
   - Auto-initialization on Rails boot
   - Middleware insertion (`E11y::Middleware::Request`)
   - ActiveSupport::Notifications integration
   - Sidekiq/ActiveJob hooks
   - Rails.logger bridge setup
   - ✅ DoD: E11y auto-configures in Rails app

2. **Quick Start Configuration**
   - `E11y.quick_start!` method
   - Environment detection (development, test, production)
   - Auto-register default adapters (stdout in dev, loki in prod)
   - Sensible defaults (sampling, rate limits)
   - ✅ DoD: Zero-config Rails app with E11y

**Verification (L6):**
- Integration tests: Rails app with E11y auto-configured
- UC Compliance: UC-017 §3 (Local Development Setup)
- ADR Compliance: ADR-008 §2 (Railtie Implementation)

#### L3.8.2: Rails Instrumentation (Unidirectional Flow)

**Design Update (2026-01-17):** Unidirectional flow (ASN → E11y), no reverse publishing.

**Tasks:**

1. **Rails Instrumentation Setup**
   - File: `lib/e11y/instruments/rails_instrumentation.rb`
   - ONLY subscribe to ActiveSupport::Notifications (ASN → E11y)
   - Subscribe to `*.action_controller`, `*.active_record`, `*.active_job`
   - Convert Rails events to E11y events
   - Selective instrumentation (configure which events to track)
   - ✅ DoD: Rails internal events tracked as E11y events (unidirectional)

2. **Built-In Event Classes (Overridable!)**
   - `Events::Rails::Database::Query` (sql.active_record)
   - `Events::Rails::Http::Request` (process_action.action_controller)
   - `Events::Rails::Job::Enqueued` (enqueue.active_job)
   - `Events::Rails::Job::Started` (perform_start.active_job)
   - `Events::Rails::Job::Completed` (perform.active_job)
   - `Events::Rails::Job::Failed` (perform.active_job with exception)
   - ✅ DoD: All critical Rails events captured

3. **Devise-Style Overrides Configuration**
   - Configuration DSL: `event_class_for` method
   - Example: `event_class_for 'sql.active_record', MyApp::CustomDatabaseQuery`
   - `ignore_event` method for disabling specific events
   - ✅ DoD: Event classes can be overridden in config

**Verification (L6):**
- Integration tests: Rails app with E11y tracking Rails events
- Override test: Custom event class used instead of default
- ADR Compliance: ADR-008 §4 (Rails Instrumentation, Updated)

---

### L2.9: Sidekiq/ActiveJob Integration 🟠

**ADR:** ADR-008 §4 (Sidekiq Integration), ADR-005 §8.3 (C17 Resolution)  
**UC:** UC-010 (Background Job Tracking)  
**Depends On:** L2.8 (Railtie)  
**Parallelizable:** ⚙️ Stream B (1 dev, parallel to Stream A)

#### L3.9.1: Sidekiq Integration

**Tasks:**
1. **Sidekiq Server Middleware**
   - File: `lib/e11y/instruments/sidekiq/server_middleware.rb`
   - Job-scoped buffer setup
   - Trace context propagation (C17 hybrid model)
   - Job execution tracking (start, complete, fail)
   - Auto-flush on job end
   - ✅ DoD: Job events tracked with trace context

2. **Sidekiq Client Middleware**
   - File: `lib/e11y/instruments/sidekiq/client_middleware.rb`
   - Track job enqueuing
   - Propagate trace context to job
   - ✅ DoD: Job enqueue events tracked

**Verification (L6):**
- Integration tests: Sidekiq job execution with E11y
- ADR Compliance: ADR-008 §4 (Sidekiq Integration)
- UC Compliance: UC-010 §3 (Job-Scoped Buffering)

#### L3.9.2: ActiveJob Integration

**Tasks:**
1. **ActiveJob Callbacks**
   - File: `lib/e11y/instruments/active_job/callbacks.rb`
   - `before_perform` callback (setup buffer)
   - `after_perform` callback (flush buffer)
   - `around_perform` callback (exception handling)
   - ✅ DoD: ActiveJob events tracked

**Verification (L6):**
- Integration tests: ActiveJob with E11y
- ADR Compliance: ADR-008 §5 (ActiveJob Integration)

#### L3.9.3: Hybrid Background Job Tracing (C17 Resolution)

**Tasks:**
1. **Hybrid Tracing Strategy**
   - File: `lib/e11y/trace/background_job.rb`
   - New `trace_id` per job
   - `parent_trace_id` link to originating request
   - Bounded traces (max 50 events per job)
   - ✅ DoD: Jobs have own trace_id + link to parent

**Verification (L6):**
- Integration tests: Multi-service job tracing
- ADR Compliance: ADR-005 §8.3 (C17 Resolution)

---

### L2.10: Rails.logger Migration 🟡

**ADR:** ADR-008 §6 (Rails.logger Migration)  
**UC:** UC-016 (Rails Logger Migration)  
**Depends On:** L2.8 (Railtie)  
**Parallelizable:** ⚙️ Stream C (1 dev, parallel to A & B)

#### L3.10.1: Logger Bridge

**Tasks:**
1. **E11y::Logger::Bridge**
   - File: `lib/e11y/logger/bridge.rb`
   - Drop-in replacement for `Rails.logger`
   - Method delegation (debug, info, warn, error, fatal)
   - Structured logging (convert string to event)
   - Dual logging (E11y + original logger)
   - ✅ DoD: `Rails.logger = E11y::Logger::Bridge.new` works

2. **Structured Event Conversion**
   - Parse log string to structured event
   - Extract severity from method (`.debug()` → severity: :debug)
   - Add context (trace_id, request_id)
   - ✅ DoD: Log strings converted to structured events

**Verification (L6):**
- Integration tests: Rails app with logger bridge
- UC Compliance: UC-016 §3 (Drop-In Replacement)
- ADR Compliance: ADR-008 §6 (Logger Bridge)

---

## PHASE 4: PRODUCTION HARDENING (Weeks 15-20)

### L2.11: Reliability & Error Handling 🔴

**ADR:** ADR-013 (Reliability & Error Handling)  
**UC:** UC-021 (Error Handling, Retry, DLQ)  
**Depends On:** L2.5 (Adapters)  
**Parallelizable:** ⚙️ Stream A (2 devs)

#### L3.11.1: Dead Letter Queue (DLQ)

**Tasks:**
1. **DLQ Implementation**
   - File: `lib/e11y/dlq/queue.rb`
   - File-based storage (JSONL format)
   - Failed event metadata (error, retry_count, timestamp)
   - DLQ size limit (1GB default)
   - ✅ DoD: Failed events stored in DLQ

2. **DLQ Replay**
   - File: `lib/e11y/dlq/replayer.rb`
   - Replay events from DLQ
   - Schema migration support (V1 → V2)
   - Batch replay (100 events at a time)
   - ✅ DoD: DLQ events replayed successfully

**Verification (L6):**
- Unit tests: `spec/e11y/dlq/queue_spec.rb`
- Integration tests: Failed adapter → DLQ → Replay
- UC Compliance: UC-021 §3 (DLQ & Retry)
- ADR Compliance: ADR-013 §4 (DLQ Implementation)

#### L3.11.2: Rate Limiting (C02, C06 Resolution)

**Tasks:**
1. **RateLimiting Middleware**
   - File: `lib/e11y/middleware/rate_limiting.rb`
   - Global rate limit (10K events/sec)
   - Per-event rate limit (1K events/sec default)
   - Redis-based (optional, fallback to in-memory)
   - Zone: `:routing`
   - ✅ DoD: Rate limits enforced correctly

2. **Critical Events Bypass (C02 Resolution)**
   - Critical events bypass rate limiting
   - Route to DLQ (not dropped)
   - ✅ DoD: Critical events never dropped

3. **Retry Rate Limiting (C06 Resolution)**
   - Separate rate limiter for retries
   - Staged batching (prevent thundering herd)
   - ✅ DoD: Retry storms prevented

**Verification (L6):**
- Unit tests: `spec/e11y/middleware/rate_limiting_spec.rb`
- Load tests: High-load scenario (10K+ events/sec)
- ADR Compliance: ADR-013 §3.5 (C06 Resolution)

#### L3.11.3: Non-Failing Event Tracking (C18 Resolution)

**Tasks:**
1. **Error Handling in Jobs**
   - File: `lib/e11y/error_handling/job_wrapper.rb`
   - Rescue E11y errors
   - Job continues despite E11y failure
   - Metrics: `e11y.errors.job_failures`
   - ✅ DoD: Jobs don't fail due to E11y errors

**Verification (L6):**
- Integration tests: Job with E11y error
- ADR Compliance: ADR-013 §3.6 (C18 Resolution)

---

### L2.12: OpenTelemetry Integration 🟠

**ADR:** ADR-007 (OpenTelemetry Integration)  
**UC:** UC-008 (OpenTelemetry Integration)  
**Depends On:** L2.5 (Adapters)  
**Parallelizable:** ⚙️ Stream B (1-2 devs, parallel to Stream A)

#### L3.12.1: OpenTelemetry Logs Integration

**Tasks:**
1. **OTelLogsAdapter**
   - File: `lib/e11y/adapters/otel_logs.rb`
   - OpenTelemetry Logs API integration
   - Severity mapping (E11y → OTel)
   - Attributes mapping
   - ✅ DoD: Events sent to OTel Collector

2. **Baggage PII Protection (C08 Resolution)**
   - File: `lib/e11y/trace/baggage_filter.rb`
   - Baggage allowlist (only safe keys)
   - PII detection in baggage
   - Drop PII baggage keys
   - ✅ DoD: No PII in OTel baggage

**Verification (L6):**
- Integration tests: OTel Collector integration
- Security tests: Baggage PII filtering
- UC Compliance: UC-008 §3 (OTel Logs)
- ADR Compliance: ADR-007 §4 (OTel Integration)

#### L3.12.2: Universal Cardinality Protection (C04 Resolution)

**Tasks:**
1. **Cardinality Protection for OTel**
   - Apply cardinality protection to OTel attributes
   - Prometheus, Loki, OTel all protected
   - ✅ DoD: Cardinality protection universal

**Verification (L6):**
- Integration tests: High-cardinality OTel attributes
- ADR Compliance: ADR-009 §8 (C04 Resolution)

---

### L2.13: Event Evolution & Versioning 🟠

**ADR:** ADR-012 (Event Evolution), ADR-015 (Middleware Order - Versioning LAST!)  
**UC:** UC-020 (Event Versioning)  
**Depends On:** L2.1 (Event::Base), L2.11 (DLQ)  
**Parallelizable:** ⚙️ Stream C (1 dev, parallel to A & B)

#### L3.13.1: Event Versioning

**Tasks:**
1. **Versioning Support**
   - `version(value)` class method on Event::Base
   - Versioned event classes (`Events::OrderPaidV2`)
   - Middleware normalization (LAST in pipeline!)
   - ✅ DoD: V1 and V2 events coexist

2. **Schema Migrations (C15 Resolution)**
   - File: `lib/e11y/schema/migration.rb`
   - Migration rules (V1 → V2 transformation)
   - DLQ replay with migration
   - ✅ DoD: Old events replayed with new schema

**Verification (L6):**
- Unit tests: `spec/e11y/schema/migration_spec.rb`
- Integration tests: V1 → V2 migration
- UC Compliance: UC-020 §3 (Schema Evolution)
- ADR Compliance: ADR-012 §8 (C15 Resolution)

---

### L2.14: SLO Tracking & Self-Monitoring 🟠

**ADR:** ADR-003 (SLO Tracking), ADR-016 (Self-Monitoring)  
**UC:** UC-004 (Zero-Config SLO), UC-014 (Event-Driven SLO)  
**Depends On:** L2.6 (Metrics)  
**Parallelizable:** ⚙️ Stream D (1 dev, parallel to A/B/C)

#### L3.14.1: SLO Tracking

**Tasks:**
1. **Zero-Config SLO Tracking**
   - File: `lib/e11y/slo/tracker.rb`
   - Auto-detect SLI events (success/error ratio)
   - Pattern-based SLO definitions
   - SLO metrics (success rate, error budget)
   - ✅ DoD: SLO metrics tracked automatically

2. **Event-Driven SLO**
   - File: `lib/e11y/slo/event_driven.rb`
   - SLO events (`Events::SLO::Request`, `Events::SLO::Job`)
   - SLO aggregation
   - ✅ DoD: SLO calculated from events

**Verification (L6):**
- Unit tests: `spec/e11y/slo/tracker_spec.rb`
- Integration tests: SLO tracking in Rails app
- UC Compliance: UC-004 §3 (Zero-Config SLO)
- ADR Compliance: ADR-003 §4 (SLO Tracking)

#### L3.14.2: Self-Monitoring

**Tasks:**
1. **E11y Internal Metrics**
   - File: `lib/e11y/self_monitoring/metrics.rb`
   - Internal metrics (events tracked, dropped, latency)
   - Buffer metrics (size, flushes, overflows)
   - Adapter metrics (writes, errors, latency)
   - ✅ DoD: E11y monitors itself

2. **Internal SLO for E11y**
   - <1ms p99 latency (track() method)
   - <0.01% drop rate
   - 100% adapter success rate (with retries)
   - ✅ DoD: E11y meets its own SLO

**Verification (L6):**
- Unit tests: `spec/e11y/self_monitoring/metrics_spec.rb`
- Load tests: Verify SLO under load
- ADR Compliance: ADR-016 §3 (Self-Monitoring)

---

## PHASE 5: SCALE & OPTIMIZATION (Weeks 21-26)

### L2.15: High Cardinality Protection (Full) 🟡

**ADR:** ADR-002 §4 (Cardinality Protection)  
**UC:** UC-013 (High Cardinality Protection)  
**Depends On:** L2.6 (Metrics), L2.12 (OTel)  
**Parallelizable:** ⚙️ Stream A (1 dev)

#### L3.15.1: Advanced Cardinality Protection

**Tasks:**
1. **Dynamic Actions**
   - File: `lib/e11y/metrics/cardinality_dynamic.rb`
   - Auto-relabeling on cardinality explosion
   - Alert on limit exceeded
   - ✅ DoD: Cardinality auto-managed

**Verification (L6):**
- Load tests: High-cardinality scenario
- UC Compliance: UC-013 §4 (Dynamic Actions)

---

### L2.16: Tiered Storage Migration 🟡

**ADR:** None (UC-015 only)  
**UC:** UC-015 (Tiered Storage Migration)  
**Depends On:** L2.5 (Adapters)  
**Parallelizable:** ⚙️ Stream B (1 dev, parallel to Stream A)

#### L3.16.1: Retention-Based Routing (Implemented)

**Tasks:**
1. **Routing by retention_until** (✅ implemented)
   - `config.routing_rules` — route to adapters based on retention_until
   - Short retention → stdout (free), long → Loki
   - `retention_period` DSL in event classes
2. **Archival** (external job)
   - Separate process filters Loki by retention_until
   - No TieredStorage adapter — archival is external

**Verification (L6):**
- UC Compliance: UC-015 §4 (Routing by retention_until)

---

### L2.17: Performance Optimization (Scale: 1K → 10K → 100K) 🔴

**ADR:** ADR-001 §5 (Performance Requirements)  
**UC:** None (implicit from scale requirements)  
**Depends On:** All previous phases  
**Parallelizable:** ❌ Sequential (requires all features complete)

#### L3.17.1: Performance Benchmarks

**Tasks:**
1. **Benchmark Suite**
   - File: `benchmarks/e11y_benchmarks.rb`
   - track() latency (p50, p99, p99.9)
   - Buffer throughput (events/sec)
   - Memory usage (MB per 1K events)
   - Adapter latency
   - ✅ DoD: Benchmarks meet targets (see below)

2. **Performance Targets (Small Scale - 1K events/sec)**
   - track() latency: <50μs (p99)
   - Buffer throughput: 10K events/sec
   - Memory: <100MB
   - CPU overhead: <5%
   - ✅ DoD: All targets met under 1K events/sec load

3. **Performance Targets (Medium Scale - 10K events/sec)**
   - track() latency: <1ms (p99)
   - Buffer throughput: 50K events/sec
   - Memory: <500MB
   - CPU overhead: <10%
   - ✅ DoD: All targets met under 10K events/sec load

4. **Performance Targets (Large Scale - 100K events/sec)**
   - track() latency: <5ms (p99)
   - Buffer throughput: 200K events/sec
   - Memory: <2GB
   - CPU overhead: <15%
   - ✅ DoD: All targets met under 100K events/sec load

**Verification (L6):**
- Load tests: Sustained load (60 min)
- Stress tests: Burst load (10x normal)
- Memory profiling: No leaks
- ADR Compliance: ADR-001 §5 (Performance Requirements)

#### L3.17.2: Optimization (If benchmarks fail)

**Tasks:**
1. **Memory Optimization**
   - Reduce object allocations
   - Optimize buffer size
   - Pool reusable objects
   - ✅ DoD: Memory usage meets targets

2. **CPU Optimization**
   - Reduce regex matches
   - Cache pattern compilation
   - Optimize JSON serialization
   - ✅ DoD: CPU overhead meets targets

3. **I/O Optimization**
   - Increase batching
   - Connection pooling tuning
   - Compression optimization
   - ✅ DoD: Adapter latency meets targets

**Verification (L6):**
- Re-run benchmarks
- Compare before/after optimization
- ADR Compliance: ADR-009 §9.2 (Optimization Targets)

---

### L2.18: Production Deployment & Documentation 🔴

**ADR:** ADR-010 (Developer Experience)  
**UC:** UC-017 (Local Development), UC-018 (Testing)  
**Depends On:** All previous phases  
**Parallelizable:** ⚙️ 3 parallel streams (docs, tests, deployment)

#### L3.18.1: Documentation (Stream A)

**Tasks:**
1. **README.md**
   - Quick start guide (5 min setup)
   - Installation instructions
   - Configuration examples
   - ✅ DoD: User can setup E11y in <5 min

2. **API Documentation**
   - Event::Base API
   - Middleware API
   - Adapter API
   - Configuration DSL
   - ✅ DoD: All public APIs documented

3. **Guides**
   - Migration from Rails.logger
   - Custom middleware guide
   - Custom adapter guide
   - Performance tuning guide
   - ✅ DoD: All common scenarios documented

4. **ADR Index**
   - Index of all 16 ADRs
   - Cross-references
   - Decision log
   - ✅ DoD: Architecture decisions discoverable

**Verification (L6):**
- Documentation review (peer review)
- User testing (new user tries setup)
- ADR Compliance: ADR-010 §3 (Developer Experience)

#### L3.18.2: Testing Strategy (Stream B)

**Tasks:**
1. **Unit Tests (100% Coverage)**
   - RSpec tests for all classes
   - Edge cases covered
   - ✅ DoD: 100% code coverage

2. **Integration Tests**
   - Full pipeline tests
   - Rails integration tests
   - Sidekiq integration tests
   - Adapter integration tests
   - ✅ DoD: All integration scenarios covered

3. **Contract Tests**
   - Adapter contract tests
   - Middleware contract tests
   - ✅ DoD: All contracts validated

4. **Load Tests**
   - 1K, 10K, 100K events/sec load tests
   - Memory leak detection
   - ✅ DoD: All performance targets met

**Verification (L6):**
- Run full test suite (CI)
- ADR Compliance: ADR-011 §3 (Testing Strategy)

#### L3.18.3: Gem Release (Stream C)

**Tasks:**
1. **Gemspec**
   - File: `e11y.gemspec`
   - Dependencies (dry-schema, yabeda, concurrent-ruby)
   - Version (0.1.0)
   - License (MIT)
   - ✅ DoD: Gem builds successfully

2. **Semantic Versioning**
   - Version file: `lib/e11y/version.rb`
   - Changelog: `CHANGELOG.md`
   - ✅ DoD: Versioning follows SemVer

3. **RubyGems Release**
   - Publish to RubyGems.org
   - GitHub release with notes
   - ✅ DoD: Gem available on RubyGems

**Verification (L6):**
- Test gem installation (`gem install e11y`)
- Test in fresh Rails app
- ADR Compliance: ADR-001 §9 (Deployment & Versioning)

#### L3.18.4: Production Checklist

**Tasks:**
1. **Production Deployment Checklist**
   - File: `docs/PRODUCTION_CHECKLIST.md`
   - Security checklist (PII filtering enabled, audit signing configured)
   - Performance checklist (rate limits, sampling, memory limits)
   - Reliability checklist (retries, circuit breakers, DLQ)
   - Monitoring checklist (metrics, alerts, SLO)
   - ✅ DoD: Production checklist complete

**Verification (L6):**
- Run production checklist on test deployment
- All checks pass
- Documentation: `docs/researches/final_analysis/PRODUCTION_CHECKLIST.md`

---

## 🔗 DEPENDENCY MAP & PARALLELIZATION

### Critical Path (Sequential):
```
L2.1 (Event::Base) 
  → L2.2 (Adaptive Buffer) 
  → L2.3 (Middleware Pipeline)
  → L2.4-L2.7 (Core Features - PARALLEL)
  → L2.8-L2.10 (Rails Integration - PARALLEL)
  → L2.11-L2.14 (Production Hardening - PARALLEL)
  → L2.17 (Performance Optimization)
  → L2.18 (Production Deployment)
```

### Parallelization Windows:

**Window 1 (Phase 1 - Weeks 1-4):**
- Stream A: L2.1 (Event::Base) - 1 dev
- Stream B: L2.2 (Adaptive Buffer) - 1 dev
- Stream C: L2.3 (Middleware Pipeline) - 1 dev
- **Total: 3 devs in parallel**

**Window 2 (Phase 2 - Weeks 5-10):**
- Stream A: L2.4 (PII Filtering & Security) - 2 devs
- Stream B: L2.5 (Adapter Architecture) - 3 devs (adapters parallelizable!)
- Stream C: L2.6 (Metrics & Yabeda) - 2 devs
- Stream D: L2.7 (Sampling & Cost Optimization) - 1 dev
- **Total: 6 devs in parallel**

**Window 3 (Phase 3 - Weeks 11-14):**
- Stream A: L2.8 (Railtie & Auto-Config) - 2 devs
- Stream B: L2.9 (Sidekiq/ActiveJob) - 1 dev
- Stream C: L2.10 (Rails.logger Migration) - 1 dev
- **Total: 4 devs in parallel**

**Window 4 (Phase 4 - Weeks 15-20):**
- Stream A: L2.11 (Reliability & Error Handling) - 2 devs
- Stream B: L2.12 (OpenTelemetry Integration) - 2 devs
- Stream C: L2.13 (Event Evolution & Versioning) - 1 dev
- Stream D: L2.14 (SLO Tracking & Self-Monitoring) - 1 dev
- **Total: 6 devs in parallel**

**Window 5 (Phase 5 - Weeks 21-26):**
- Stream A: L2.15 (High Cardinality Protection) - 1 dev
- Stream B: L2.16 (Tiered Storage Migration) - 1 dev
- Stream C: L2.17 (Performance Optimization) - 2 devs (sequential after others)
- Stream D: L2.18.1 (Documentation) - 1 dev (parallel with optimization)
- Stream E: L2.18.2 (Testing) - 1 dev (parallel with optimization)
- Stream F: L2.18.3 (Gem Release) - 1 dev (parallel with optimization)
- **Total: 6 devs in parallel (optimization blocks release, but docs/tests parallel)**

---

## 📊 INTEGRATION CONTRACTS (CRITICAL for Parallel Work)

### Contract 1: Event::Base Interface
```ruby
# lib/e11y/event/base.rb
module E11y
  class Event
    class Base
      # PUBLIC API (guaranteed stable for all components)
      
      # Track event (zero-allocation)
      # @param [Hash] payload Event data
      # @return [Hash] event_data (for testing/debugging)
      def self.track(**payload)
      
      # Configuration DSL
      def self.severity(value = nil)
      def self.schema(&block)
      def self.version(value = nil)
      def self.adapters(list = nil)
      
      # Resolution methods (read-only)
      def self.resolve_severity
      def self.resolve_adapters
      def self.resolve_sample_rate
      def self.resolve_rate_limit
    end
  end
end
```

**Contract Guarantees:**
- `track()` returns `Hash` with keys: `:event_name`, `:payload`, `:severity`, `:version`, `:adapters`
- All resolution methods return sensible defaults (never nil)
- Schema validation happens inside `track()` (raises `E11y::ValidationError` on invalid payload)

**Consumers:**
- L2.3 (Middleware Pipeline) - calls `track()` internally
- L2.4 (PII Filtering) - reads `event_data[:payload]`
- L2.6 (Metrics) - reads `event_data[:event_name]`, `event_data[:severity]`
- L2.7 (Sampling) - reads `resolve_sample_rate()`

---

### Contract 2: Middleware::Base Interface
```ruby
# lib/e11y/middleware/base.rb
module E11y
  module Middleware
    class Base
      # PUBLIC API
      
      # Initialize middleware with next app in chain
      # @param [Middleware::Base] app Next middleware in chain
      def initialize(app)
      
      # Call middleware (process event)
      # @param [Hash] event_data Event data hash
      # @return [Hash] modified event_data (or nil to drop event)
      def call(event_data)
      
      # Declare middleware zone
      # @param [Symbol] zone Zone name (:pre_processing, :security, :routing, :post_processing, :adapters)
      def self.middleware_zone(zone = nil)
    end
  end
end
```

**Contract Guarantees:**
- `call(event_data)` receives `Hash` with keys: `:event_name`, `:payload`, `:severity`, `:version`, `:trace_id`, `:timestamp`
- `call(event_data)` returns modified `Hash` or `nil` (drop event)
- Middlewares MUST call `@app.call(event_data)` to continue chain
- Middlewares MUST NOT mutate `event_data` without creating new hash (immutability)

**Consumers:**
- L2.4 (PII Filtering Middleware)
- L2.6 (Metrics Middleware)
- L2.7 (Sampling Middleware)
- L2.11 (Rate Limiting Middleware)
- L2.13 (Versioning Middleware)

---

### Contract 3: Adapter::Base Interface
```ruby
# lib/e11y/adapters/base.rb
module E11y
  module Adapters
    class Base
      # PUBLIC API
      
      # Write single event
      # @param [Hash] event_data Event data hash
      # @return [Boolean] true if successful, false otherwise
      def write(event_data)
      
      # Write batch of events (default: loop write)
      # @param [Array<Hash>] events Array of event data hashes
      # @return [Integer] number of successfully written events
      def write_batch(events)
      
      # Health check
      # @return [Boolean] true if adapter is healthy
      def healthy?
      
      # Close adapter (cleanup resources)
      # @return [void]
      def close
      
      # Adapter capabilities
      # @return [Hash] capabilities (:batching, :compression, :encryption)
      def capabilities
    end
  end
end
```

**Contract Guarantees:**
- `write(event_data)` is idempotent (safe to retry)
- `write_batch(events)` returns number of successful writes (for metrics)
- `healthy?` is fast (<10ms) and non-blocking
- Adapters MUST handle retries internally (exponential backoff)

**Consumers:**
- L2.5.2 (Built-In Adapters - Stdout, File, Loki, Sentry, Elasticsearch, InMemory)
- L2.11 (Retry Handler, Circuit Breaker)
- L2.12 (OTelLogsAdapter)

---

### Contract 4: Buffer Interface
```ruby
# lib/e11y/buffers/base_buffer.rb
module E11y
  module Buffers
    class BaseBuffer
      # PUBLIC API
      
      # Push event to buffer
      # @param [Hash] event_data Event data hash
      # @return [Boolean] true if pushed, false if dropped (backpressure)
      def push(event_data)
      
      # Pop event from buffer (non-blocking)
      # @return [Hash, nil] event_data or nil if empty
      def pop
      
      # Flush all events from buffer
      # @return [Array<Hash>] all buffered events
      def flush_all
      
      # Buffer size
      # @return [Integer] number of events in buffer
      def size
      
      # Buffer capacity
      # @return [Integer] maximum number of events buffer can hold
      def capacity
    end
  end
end
```

**Contract Guarantees:**
- `push()` is thread-safe
- `pop()` is non-blocking (returns nil if empty)
- `flush_all()` is atomic (all or nothing)
- Buffer MUST implement backpressure strategy (block/drop/throttle)

**Consumers:**
- L2.2 (RingBuffer, AdaptiveBuffer, RequestScopedBuffer)
- L2.3 (Routing Middleware)
- L2.8 (Rails Middleware)

---

## 🎯 VERIFICATION STRATEGY (Level 6)

### Testing Pyramid:

```
                    ▲
                   / \
                  /   \
                 / E2E \         10% - Full Rails app tests (1-2 per UC)
                /-------\
               / Integr. \       20% - Component integration tests
              /-----------\
             / Unit Tests  \     70% - Unit tests (all methods)
            /--------------\
```

### Test Categories:

1. **Unit Tests (70%):**
   - File: `spec/e11y/**/*_spec.rb`
   - Coverage: 100% (enforced by SimpleCov)
   - Run time: <30 seconds (full suite)
   - ✅ DoD: All classes/methods have unit tests

2. **Integration Tests (20%):**
   - File: `spec/integration/**/*_spec.rb`
   - Coverage: All component interactions
   - Run time: <2 minutes (full suite)
   - ✅ DoD: All integration scenarios tested

3. **E2E Tests (10%):**
   - File: `spec/e2e/**/*_spec.rb`
   - Coverage: Critical user journeys (UC-001, UC-002, UC-007, UC-016)
   - Run time: <5 minutes (full suite)
   - ✅ DoD: All critical UCs have E2E tests

4. **Load Tests:**
   - File: `benchmarks/load_tests.rb`
   - Scenarios: 1K, 10K, 100K events/sec
   - Duration: 60 min sustained load
   - ✅ DoD: All performance targets met

5. **Contract Tests:**
   - File: `spec/contracts/**/*_spec.rb`
   - Coverage: All public APIs (Event::Base, Middleware::Base, Adapter::Base, Buffer)
   - ✅ DoD: All contracts validated

---

## 📋 ADR/UC COMPLIANCE CHECKLIST

### ADR Coverage (16 ADRs):

| ADR | Phase | Component | Verification |
|-----|-------|-----------|--------------|
| ADR-001 | Phase 1 | L2.1, L2.2, L2.3 | Unit tests + benchmarks |
| ADR-002 | Phase 2 | L2.6 | Integration tests + Prometheus |
| ADR-003 | Phase 4 | L2.14 | SLO metrics validation |
| ADR-004 | Phase 2 | L2.5 | Adapter contract tests |
| ADR-005 | Phase 3 | L2.9 | Job tracing tests |
| ADR-006 | Phase 2 | L2.4 | PII filtering tests + security audit |
| ADR-007 | Phase 4 | L2.12 | OTel integration tests |
| ADR-008 | Phase 3 | L2.8, L2.9, L2.10 | Rails integration tests |
| ADR-009 | Phase 2 | L2.7 | Sampling tests + cost analysis |
| ADR-010 | Phase 5 | L2.18 | Documentation review |
| ADR-011 | Phase 5 | L2.18.2 | Testing strategy validation |
| ADR-012 | Phase 4 | L2.13 | Versioning tests |
| ADR-013 | Phase 4 | L2.11 | Reliability tests |
| ADR-014 | Phase 4 | L2.14 | Event-driven SLO tests |
| ADR-015 | Phase 2 | L2.4 | Pipeline order validation |
| ADR-016 | Phase 4 | L2.14 | Self-monitoring metrics |

### UC Coverage (22 UCs):

| UC | Phase | Component | Verification |
|----|-------|-----------|--------------|
| UC-001 | Phase 1 | L2.2 | Request-scoped buffer tests |
| UC-002 | Phase 1 | L2.1 | Event tracking tests |
| UC-003 | Phase 2 | L2.6 | Pattern-based metrics tests |
| UC-004 | Phase 4 | L2.14 | Zero-config SLO tests |
| UC-005 | Phase 2 | L2.5 | Sentry adapter tests |
| UC-006 | Phase 3 | L2.9 | Trace context tests |
| UC-007 | Phase 2 | L2.4 | PII filtering tests |
| UC-008 | Phase 4 | L2.12 | OTel integration tests |
| UC-009 | Phase 3 | L2.9 | Multi-service tracing tests |
| UC-010 | Phase 3 | L2.9 | Background job tracking tests |
| UC-011 | Phase 4 | L2.11 | Rate limiting tests |
| UC-012 | Phase 2 | L2.4 | Audit trail tests |
| UC-013 | Phase 5 | L2.15 | Cardinality protection tests |
| UC-014 | Phase 2 | L2.7 | Adaptive sampling tests |
| UC-015 | Phase 5 | L2.16 | Tiered storage tests |
| UC-016 | Phase 3 | L2.10 | Logger migration tests |
| UC-017 | Phase 3 | L2.8 | Local development setup tests |
| UC-018 | Phase 5 | L2.18 | Testing helpers validation |
| UC-019 | Phase 5 | L2.16 | Tiered storage migration tests |
| UC-020 | Phase 4 | L2.13 | Event versioning tests |
| UC-021 | Phase 4 | L2.11 | Error handling tests |
| UC-022 | Phase 1 | L2.1 | Event registry tests |

---

## 🚀 NEXT STEPS

1. **Review this plan** with team
2. **Assign developers** to parallelizable streams
3. **Setup project skeleton** (gem structure, CI/CD, Docker Compose for adapters)
4. **Start Phase 1** (Foundation) - 3 parallel streams
5. **Weekly sync** - integration point validation
6. **After Phase 1** - validate contracts, adjust plan if needed
7. **Continue** through phases 2-5

---

**Status:** ✅ 6-Level Implementation Plan Complete  
**Last Updated:** 2026-01-17  
**Estimated Total Effort:** 22-26 weeks (with proper parallelization)  
**Maximum Parallelism:** 6 developers  
**Critical Path:** ~14-16 weeks (Foundation → Core → Rails → Performance)

---

