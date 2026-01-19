# Implementation Plan: Critical Architecture Questions & Improvements

**Date:** 2026-01-17  
**Status:** 🚨 REQUIRES DECISION  
**Priority:** CRITICAL (must be resolved BEFORE Phase 1)

---

## 🔴 CRITICAL QUESTIONS FROM CODE REVIEW

### Q1: ActiveSupport::Notifications - Bidirectional vs Unidirectional?

**Current Plan (ADR-008 §4.1):** Bidirectional bridge
- E11y → ActiveSupport::Notifications
- ActiveSupport::Notifications → E11y

**Your Question:** "Не лучше ли однонаправленный поток данных?"

---

#### 🤔 ANALYSIS:

**Unidirectional Design:**
```ruby
# ТОЛЬКО ASN → E11y (подписка на Rails события)
ActiveSupport::Notifications.subscribe('sql.active_record') do |...|
  Events::Rails::Database::Query.track(...)
end

# E11y события идут ТОЛЬКО в adapters, не в ASN
Events::OrderCreated.track(...)
# → Middleware Pipeline → Adapters (Loki, Sentry)
```

---

#### ✅ DESIGN: **UNIDIRECTIONAL FLOW (ASN → E11y)**

**Причины:**

1. **Избежание циклов:**
   - ASN → E11y (ТОЛЬКО захват Rails internal events)
   - E11y → Adapters (ТОЛЬКО отправка в бэкенды)
   - Нет обратного пути (no cycles)

2. **Простота рассуждений (Single Direction):**
   - Нет двунаправленной синхронизации
   - Clear data flow

3. **Separation of Concerns:**
   - ASN = Rails instrumentation (database, views, controllers)
   - E11y = Business events + adapters
   - Нет пересечения (clear boundary)

4. **Performance:**
   - Unidirectional = 1x overhead (only subscribe from ASN)

---

#### 📋 IMPLEMENTATION:

**Unidirectional:**
```ruby
# lib/e11y/instruments/rails_instrumentation.rb
class RailsInstrumentation
  # ActiveSupport::Notifications → E11y ✅
  def self.subscribe_from_asn
    ...
  end
end
```

**Implementation:**
```ruby
# lib/e11y/instruments/rails_instrumentation.rb
class RailsInstrumentation
  # ONLY ActiveSupport::Notifications → E11y
  def self.setup!
    RAILS_EVENT_MAPPING.each do |asn_pattern, e11y_event_class|
      ActiveSupport::Notifications.subscribe(asn_pattern) do |...|
        e11y_event_class.track(...)
      end
    end
  end
end
```

---

### Q2: Built-In Event Classes - Можно ли переопределять?

**Current Plan:**
```ruby
# Built-in classes (hard-coded in gem)
Events::Rails::Database::Query
Events::Rails::Http::Request
Events::Rails::Job::Enqueued
Events::Rails::Job::Started
Events::Rails::Job::Completed
Events::Rails::Job::Failed
```

**Your Question:** "Вот эти классы событий можно будет переопределять в конфиге? По аналогии с devise controllers?"

---

#### ✅ RECOMMENDATION: **YES, OVERRIDABLE (Devise-style)**

**Design:**

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.rails_instrumentation do
    # Override default event classes (Devise-style)
    event_class_for 'sql.active_record', MyApp::Events::CustomDatabaseQuery
    event_class_for 'process_action.action_controller', MyApp::Events::CustomHttpRequest
    
    # Or disable specific events
    ignore_event 'cache_read.active_support'  # Don't track cache reads
    
    # Or use custom mapping
    custom_mapping do
      'my_custom_event' => MyApp::Events::CustomEvent
    end
  end
end
```

**Implementation:**

```ruby
# lib/e11y/configuration/rails_instrumentation.rb
module E11y
  module Configuration
    class RailsInstrumentation
      # Default mapping (can be overridden)
      DEFAULT_EVENT_MAPPING = {
        'sql.active_record' => Events::Rails::Database::Query,
        'process_action.action_controller' => Events::Rails::Http::Request,
        # ...
      }.freeze
      
      def initialize
        @event_mapping = DEFAULT_EVENT_MAPPING.dup
        @ignored_events = []
      end
      
      # Override event class (Devise-style)
      def event_class_for(asn_pattern, custom_event_class)
        @event_mapping[asn_pattern] = custom_event_class
      end
      
      # Disable event
      def ignore_event(asn_pattern)
        @ignored_events << asn_pattern
      end
      
      # Get final mapping (after overrides)
      def event_mapping
        @event_mapping.except(*@ignored_events)
      end
    end
  end
end
```

**Usage Example:**

```ruby
# Custom event class (override default)
module MyApp
  module Events
    class CustomDatabaseQuery < E11y::Event::Base
      schema do
        required(:query).filled(:string)
        required(:duration).filled(:float)
        required(:connection_name).filled(:string)
        
        # Custom field (not in default Event::Rails::Database::Query)
        optional(:database_shard).filled(:string)
      end
      
      # Custom adapter routing
      adapters [:loki, :elasticsearch]  # Override: also send to ES
      
      # Custom PII filtering
      pii_filtering do
        masks :query  # Mask SQL queries (more aggressive than default)
      end
    end
  end
end

# config/initializers/e11y.rb
E11y.configure do |config|
  config.rails_instrumentation do
    event_class_for 'sql.active_record', MyApp::Events::CustomDatabaseQuery
  end
end
```

**Benefits:**
- ✅ Flexibility (custom schema, PII rules, adapters)
- ✅ Familiar pattern (Devise-style)
- ✅ Opt-in (defaults work for 90% cases)
- ✅ No monkey-patching (clean override)

---

### Q3: Gem Best Practices - Отсутствует в плане!

**Your Question:** "Не увидел в начале плана задачи про инициализацию гема и поиск лучших практик написания и оформления гемов (прежде всего популярных и успешных)"

**Current Plan:** Week -1 "Setup project skeleton" (но нет детализации!)

---

#### ✅ RECOMMENDATION: **ADD NEW TASK TO PHASE 0 (Week -1)**

**NEW PHASE 0: GEM INITIALIZATION & BEST PRACTICES (Week -1)**

---

#### 📋 PROPOSED NEW SECTION FOR PLAN:

```markdown
## PHASE 0: GEM INITIALIZATION & BEST PRACTICES (Week -1)

### L2.0: Gem Structure & Best Practices Research 🔴

**Purpose:** Research and setup professional gem structure BEFORE coding  
**Depends On:** None (foundation)  
**Parallelizable:** ⚙️ 1-2 devs

#### L3.0.1: Best Practices Research

**Tasks:**

1. **Study Successful Rails Gems**
   - **Devise** (authentication) - controller overrides, modular design
   - **Sidekiq** (background jobs) - middleware pattern, configuration DSL
   - **Puma** (web server) - configuration DSL, plugin system
   - **Dry-rb gems** (dry-schema, dry-validation) - functional design, composition
   - **Yabeda** (metrics) - DSL design, extensibility
   - **Sentry-ruby** (error tracking) - Rails integration, configuration
   - ✅ DoD: Document 10+ patterns from each gem

2. **Gem Structure Analysis**
   - Directory structure (lib/, spec/, bin/, docs/)
   - File naming conventions
   - Module organization (E11y::, E11y::Instruments::, etc.)
   - Autoloading strategy (Zeitwerk vs manual requires)
   - ✅ DoD: Documented gem structure template

3. **Configuration DSL Patterns**
   - Study: Devise, Sidekiq, Sentry configuration patterns
   - Block-based DSL (E11y.configure { |config| ... })
   - Nested configuration (config.adapters do ... end)
   - Type validation (dry-types?)
   - Environment-specific config
   - ✅ DoD: Configuration DSL design document

4. **Testing Strategies**
   - RSpec setup (spec_helper, rails_helper)
   - Test factories (FactoryBot? Plain Ruby?)
   - Contract tests for public APIs
   - Integration tests with Rails
   - Load testing setup
   - ✅ DoD: Testing strategy document

5. **Documentation Standards**
   - YARD documentation (inline docs)
   - README structure
   - Guides vs API reference
   - Code examples
   - Changelog format (Keep a Changelog)
   - ✅ DoD: Documentation template

6. **CI/CD Best Practices**
   - GitHub Actions setup
   - Matrix testing (Ruby 3.2, 3.3, Rails 8.0+)
   - Code coverage (SimpleCov)
   - Linting (Rubocop, StandardRB?)
   - Security scanning (Brakeman, Bundler Audit)
   - ✅ DoD: CI/CD pipeline configured

7. **Gem Release Process**
   - Semantic versioning strategy
   - Changelog generation
   - RubyGems release checklist
   - GitHub releases with notes
   - Deprecation warnings strategy
   - ✅ DoD: Release process documented

**Verification (L6):**
- Research notes: `docs/research/gem_best_practices.md`
- Gem structure template: `docs/research/gem_structure_template.md`
- Configuration DSL design: `docs/research/configuration_dsl_design.md`

---

#### L3.0.2: Project Skeleton Setup

**Tasks:**

1. **Initialize Gem**
   ```bash
   bundle gem e11y --mit --test=rspec --ci=github --linter=rubocop
   ```
   - ✅ DoD: Gem skeleton created

2. **Setup Directory Structure**
   ```
   e11y/
   ├── lib/
   │   ├── e11y.rb (main entry point)
   │   ├── e11y/
   │   │   ├── version.rb
   │   │   ├── configuration.rb
   │   │   ├── event/
   │   │   │   └── base.rb
   │   │   ├── middleware/
   │   │   │   └── base.rb
   │   │   ├── adapters/
   │   │   │   └── base.rb
   │   │   ├── buffers/
   │   │   │   └── base_buffer.rb
   │   │   ├── instruments/
   │   │   │   └── rails_instrumentation.rb
   │   │   └── railtie.rb (if Rails)
   │   └── e11y/
   ├── spec/
   │   ├── spec_helper.rb
   │   ├── rails_helper.rb (for Rails integration tests)
   │   ├── support/
   │   └── e11y/
   ├── benchmarks/
   │   ├── e11y_benchmarks.rb
   │   └── load_tests.rb
   ├── docs/
   │   ├── README.md
   │   ├── ADR-*.md
   │   ├── use_cases/
   │   └── guides/
   ├── bin/
   │   └── console (IRB with E11y loaded)
   ├── .github/
   │   └── workflows/
   │       ├── ci.yml
   │       └── release.yml
   ├── docker-compose.yml (Loki, Prometheus, Elasticsearch)
   ├── Gemfile
   ├── e11y.gemspec
   ├── Rakefile
   ├── .rubocop.yml
   └── README.md
   ```
   - ✅ DoD: Professional gem structure

3. **Setup Zeitwerk Autoloading**
   ```ruby
   # lib/e11y.rb
   require 'zeitwerk'
   
   loader = Zeitwerk::Loader.for_gem
   loader.setup
   ```
   - ✅ DoD: Autoloading works correctly

4. **Setup CI/CD (GitHub Actions)**
   ```yaml
   # .github/workflows/ci.yml
   name: CI
   on: [push, pull_request]
   jobs:
     test:
       runs-on: ubuntu-latest
       strategy:
         matrix:
           ruby: ['3.2', '3.3']
           rails: ['8.0']
       steps:
         - uses: actions/checkout@v3
         - uses: ruby/setup-ruby@v1
           with:
             ruby-version: ${{ matrix.ruby }}
             bundler-cache: true
         - run: bundle exec rspec
         - run: bundle exec rubocop
   ```
   - ✅ DoD: CI runs on every commit

5. **Setup Docker Compose (Test Backends)**
   ```yaml
   # docker-compose.yml
   version: '3.8'
   services:
     loki:
       image: grafana/loki:2.9.0
       ports:
         - "3100:3100"
     
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
   ```
   - ✅ DoD: Adapters can test against real backends

6. **Setup SimpleCov (Code Coverage)**
   ```ruby
   # spec/spec_helper.rb
   require 'simplecov'
   SimpleCov.start do
     add_filter '/spec/'
     minimum_coverage 100  # Enforce 100% coverage!
   end
   ```
   - ✅ DoD: Coverage enforced

7. **Setup Rubocop (Linting)**
   ```yaml
   # .rubocop.yml
   require:
     - rubocop-performance
     - rubocop-rspec
   
   AllCops:
     TargetRubyVersion: 3.2
     NewCops: enable
   
   Style/Documentation:
     Enabled: true  # Enforce YARD docs!
   ```
   - ✅ DoD: Linting enforced

**Verification (L6):**
- Gem builds: `gem build e11y.gemspec`
- Tests run: `bundle exec rspec`
- Linting passes: `bundle exec rubocop`
- Coverage 100%: `open coverage/index.html`
- CI green: GitHub Actions badge

---

#### L3.0.3: Research Documentation

**Deliverables:**

1. **`docs/research/gem_best_practices.md`**
   - Patterns from Devise, Sidekiq, Puma, Dry-rb, Yabeda, Sentry
   - Configuration DSL patterns
   - Testing strategies
   - Documentation standards

2. **`docs/research/gem_structure_template.md`**
   - Directory structure
   - File naming conventions
   - Module organization
   - Autoloading strategy

3. **`docs/research/configuration_dsl_design.md`**
   - Block-based DSL design
   - Nested configuration
   - Type validation
   - Environment-specific config

4. **`docs/research/gem_release_process.md`**
   - Semantic versioning
   - Changelog generation
   - RubyGems release checklist
   - Deprecation strategy

**Verification (L6):**
- Documents reviewed by team
- Patterns applied to Phase 1 tasks
```

---

### Q4: Rails.logger - Wrapper vs Replacement?

**Your Question:** "Может просто нужно сделать wrapper для rails логгера, а не переопределять?"

**Current ADR-008 §7:** Bridge pattern (wrapper + replacement)

---

#### ✅ CURRENT DESIGN IS CORRECT (Wrapper + Opt-In Replacement)

**ADR-008 already uses wrapper pattern!**

```ruby
# lib/e11y/logger/bridge.rb
class Bridge
  def initialize(original_logger = nil)
    @original_logger = original_logger  # ← Keep original!
  end
  
  def info(message)
    # 1. Send to E11y
    Events::Rails::Log.track(message: message, severity: :info)
    
    # 2. Mirror to original logger (optional)
    @original_logger.info(message) if @original_logger && mirror_enabled?
  end
end

# Opt-in replacement:
Rails.logger = E11y::Logger::Bridge.new(Rails.logger)
```

**Benefits of Current Design:**
- ✅ Wrapper pattern (delegates to original logger)
- ✅ Opt-in replacement (`Rails.logger = Bridge.new(...)`)
- ✅ Mirroring support (dual logging during migration)
- ✅ Gradual migration (3-phase strategy)

**No changes needed!** Current design is correct.

---

## 📋 SUMMARY OF REQUIRED CHANGES TO PLAN

### ✅ APPROVED CHANGES:

1. **Q1: Unidirectional Flow (ASN → E11y)** ✅ COMPLETED
   - Changed bidirectional bridge to unidirectional
   - **Files updated:**
     - `docs/ADR-008-rails-integration.md` §4

2. **Q2: Overridable Event Classes (Devise-style)**
   - Add configuration DSL for event class overrides
   - Add `ignore_event` for disabling specific events
   - **Files to update:**
     - `docs/IMPLEMENTATION_PLAN_6_LEVELS.md` §L3.8.2
     - `docs/ADR-008-rails-integration.md` §4

3. **Q3: Add Phase 0 (Gem Best Practices Research)**
   - New phase: Week -1 (BEFORE Phase 1)
   - Research successful gems (Devise, Sidekiq, Puma, etc.)
   - Setup professional gem structure
   - **Files to update:**
     - `docs/IMPLEMENTATION_PLAN_6_LEVELS.md` (insert Phase 0)
     - `docs/IMPLEMENTATION_PLAN_EXECUTIVE_SUMMARY.md` (update timeline)
     - `docs/IMPLEMENTATION_PLAN_DEPENDENCY_MAP.md` (add Phase 0)

### ❌ NO CHANGES NEEDED:

4. **Q4: Rails.logger Wrapper**
   - Current design already uses wrapper pattern
   - No changes required

---

## 🚨 ACTION ITEMS (BEFORE PHASE 1 STARTS)

### Immediate (This Week):

- [ ] **Review this document** with team/user
- [ ] **Approve architectural decisions** (Q1, Q2, Q3)
- [ ] **Update implementation plan** with Phase 0
- [ ] **Update ADR-008** with unidirectional flow + overridable classes
- [ ] **Research gems** (Devise, Sidekiq, Puma, Dry-rb, Yabeda, Sentry)
- [ ] **Setup project skeleton** (gem structure, CI/CD)

### Next Week (Week 0):

- [ ] **Team kickoff** (review Phase 0 research)
- [ ] **Assign streams** (A/B/C/D)
- [ ] **Start Phase 1** (Foundation)

---

**Status:** 🚨 AWAITING APPROVAL  
**Priority:** CRITICAL (blocks Phase 1 start)  
**Created:** 2026-01-17  
**Estimated Resolution Time:** 1-2 days
