# E11y Unified DSL Specification

**Version:** 1.1.0  
**Date:** January 16, 2026  
**Status:** ✅ Final Specification  
**Purpose:** Single source of truth for all E11y event-level DSL methods

---

## 📋 Table of Contents

1. [Core Configuration](#1-core-configuration)
2. [Adapters](#2-adapters)
3. [Sampling](#3-sampling)
4. [Rate Limiting](#4-rate-limiting)
5. [PII Filtering](#5-pii-filtering)
6. [Metrics](#6-metrics)
7. [Cardinality Protection](#7-cardinality-protection)
8. [Audit & Compliance](#8-audit--compliance)
9. [Inheritance & Presets](#9-inheritance--presets)
10. [Validations](#10-validations)
11. [Precedence Rules](#11-precedence-rules)
12. [Environment-Specific Config](#12-environment-specific-config)

---

## 1. Core Configuration

### 1.1. `severity`

**Signature:**
```ruby
severity(level)
```

**Parameters:**
- `level` (Symbol, required): Severity level

**Valid Values:**
- `:debug` - Debug information
- `:info` - Informational messages
- `:success` - Successful operations (NEW in E11y!)
- `:warn` - Warning messages
- `:error` - Error messages
- `:fatal` - Fatal errors

**Default:** Inferred from event name (convention)

**Convention Rules:**
```ruby
*Failed, *Error, *Timeout → :error
*Succeeded, *Paid, *Completed → :success
*Started, *Processing, *Queued, *Pending → :info
*Cancelled, *Skipped → :warn
Debug* → :debug
```

**Inheritance:** Yes (from base class)

**Validation:** ✅ **REQUIRED** - Validates at class load
```ruby
VALID_SEVERITIES = [:debug, :info, :success, :warn, :error, :fatal]

def self.severity(level)
  unless VALID_SEVERITIES.include?(level)
    raise ArgumentError, "Invalid severity: #{level}. Valid: #{VALID_SEVERITIES.join(', ')}"
  end
  self._severity = level
end
```

**Examples:**
```ruby
# Convention (auto-detected):
class Events::OrderCreated < E11y::Event::Base
  # ← Auto: severity = :success (from name)
end

# Explicit:
class Events::OrderCreated < E11y::Event::Base
  severity :success
end

# Override convention:
class Events::PaymentFailed < E11y::Event::Base
  severity :warn  # Override (unusual case)
end
```

---

### 1.2. `rate_limit`

**Signature:**
```ruby
rate_limit(limit, window: 1.second)
```

**Parameters:**
- `limit` (Integer, required): Max events per window
- `window` (Duration, optional): Time window (default: `1.second`)

**Default:** `1000` events per second

**Type:** Integer + ActiveSupport::Duration

**Inheritance:** Yes (from base class)

**Examples:**
```ruby
# Default window (1 second):
rate_limit 1000

# Custom window:
rate_limit 100, window: 1.minute

# High-volume event:
rate_limit 10_000

# Low-volume event:
rate_limit 50, window: 1.minute
```

**Related:** `on_exceeded` (action when limit exceeded)

---

### 1.3. `sample_rate`

**Signature:**
```ruby
sample_rate(rate)
```

**Parameters:**
- `rate` (Float, required): Sample rate (0.0 to 1.0)

**Default:** By severity (convention)

**Convention Rules:**
```ruby
:error/:fatal → 1.0 (100%, never sample errors!)
:warn → 0.5 (50%)
:success/:info → 0.1 (10%)
:debug → 0.01 (1%)
```

**Type:** Float (0.0-1.0)

**Inheritance:** Yes (from base class)

**Examples:**
```ruby
# Convention (auto):
class Events::OrderCreated < E11y::Event::Base
  severity :success
  # ← Auto: sample_rate = 0.1 (10%)
end

# Override:
class Events::PaymentSucceeded < E11y::Event::Base
  sample_rate 1.0  # Never sample payments
end

# Debug event:
class Events::DebugQuery < E11y::Event::Base
  sample_rate 0.01  # 1% sampling
end
```

---

### 1.4. `retention`

**Signature:**
```ruby
retention(duration)
```

**Parameters:**
- `duration` (Duration, required): Retention period

**Default:** By severity (convention)

**Convention Rules:**
```ruby
:error/:fatal → 90.days
:info/:success → 30.days
:debug → 7.days
audit_event true → E11y.config.audit_retention (default: 7.years, configurable per jurisdiction!)
```

**Type:** ActiveSupport::Duration

**Inheritance:** Yes (from base class)

**Examples:**
```ruby
# Convention (auto):
class Events::OrderCreated < E11y::Event::Base
  severity :success
  # ← Auto: retention = 30.days
end

# Financial records:
class Events::PaymentSucceeded < E11y::Event::Base
  retention 7.years
end

# Audit event (auto retention from config):
class Events::UserDeleted < E11y::Event::Base
  audit_event true
  # ← Auto: retention = E11y.config.audit_retention (default: 7.years)
  # Configurable per jurisdiction (GDPR: 7 years, other: custom)
end

# Override audit retention (if needed):
class Events::UserDeleted < E11y::Event::Base
  audit_event true
  retention 10.years  # ← Explicit override (e.g., financial regulations)
end
```

---

### 1.5. `schema`

**Signature:**
```ruby
schema(&block)
```

**Parameters:**
- Block with Dry::Schema DSL

**Required:** ✅ **YES** - Every event MUST have schema

**Validation:** ✅ **REQUIRED** - Validates at class load
```ruby
class E11y::Event::Base
  def self.inherited(subclass)
    super
    at_exit do
      unless subclass.instance_variable_defined?(:@_schema)
        raise "#{subclass} missing schema! Every event must define schema."
      end
    end
  end
end
```

**Examples:**
```ruby
# Simple schema:
schema do
  required(:order_id).filled(:string)
  required(:amount).filled(:decimal)
end

# Complex schema:
schema do
  required(:order_id).filled(:string)
  required(:user_id).filled(:string)
  required(:items).array(:hash) do
    required(:product_id).filled(:string)
    required(:quantity).filled(:integer)
  end
  optional(:coupon_code).filled(:string)
end

# One-liner (for simple schemas):
schema do; required(:transaction_id).filled(:string); end
```

---

## 2. Adapters

### 2.1. `adapters`

**Signature:**
```ruby
adapters(adapter_list)
```

**Parameters:**
- `adapter_list` (Array<Symbol>, required): List of adapter names

**Default:** By severity (convention)

**Convention Rules:**
```ruby
:error/:fatal → [:sentry]
:success/:info/:warn → [:loki]
:debug → [:file] (dev), [:loki] (prod with sampling)
```

**Type:** Array<Symbol>

**Inheritance:** Yes (from base class)

**Validation:** ✅ **REQUIRED** - Validates at class load
```ruby
def self.adapters(list)
  list.each do |adapter|
    unless E11y.registered_adapters.include?(adapter)
      raise ArgumentError, "Unknown adapter: #{adapter}. Registered: #{E11y.registered_adapters.keys.join(', ')}"
    end
  end
  self._adapters = list
end
```

**Examples:**
```ruby
# Convention (auto):
class Events::OrderCreated < E11y::Event::Base
  severity :success
  # ← Auto: adapters = [:loki]
end

# Override:
class Events::PaymentSucceeded < E11y::Event::Base
  adapters [:loki, :sentry, :s3_archive]
end

# Audit event:
class Events::UserDeleted < E11y::Event::Base
  adapters [:audit_encrypted]
end

# Environment-specific:
class Events::DebugQuery < E11y::Event::Base
  adapters Rails.env.production? ? [:loki] : [:file]
end
```

---

### 2.2. `adapters_strategy`

**Signature:**
```ruby
adapters_strategy(strategy)
```

**Parameters:**
- `strategy` (Symbol, required): `:replace` or `:append`

**Default:** `:replace`

**Type:** Symbol

**Inheritance:** Yes (from base class)

**Examples:**
```ruby
# Replace (default):
class Events::PaymentSucceeded < Events::BasePaymentEvent
  adapters [:loki, :sentry]  # Replaces base adapters
end

# Append:
class Events::PaymentSucceeded < Events::BasePaymentEvent
  adapters_strategy :append
  adapters [:slack_business]  # Adds to base adapters
  # Result: [:loki, :sentry, :s3, :slack_business]
end
```

---

## 3. Sampling

### 3.1. `adaptive_sampling`

**Signature:**
```ruby
adaptive_sampling(enabled: true, &block)
```

**Parameters:**
- `enabled` (Boolean, optional): Enable/disable adaptive sampling (default: `true`)
- Block with DSL: `base_rate`, `sample_by_value`, `on_error_spike`, `on_high_load`

**Default:** Disabled (uses static `sample_rate`)

**Type:** Boolean + Block

**Inheritance:** Yes (from base class)

**⚠️ FIXED:** Boolean now uses keyword argument (not positional!)

**Examples:**
```ruby
# Enable with defaults:
adaptive_sampling

# Enable with config:
adaptive_sampling do
  base_rate 0.1
  
  sample_by_value do
    field :amount
    threshold 1000  # Always sample >$1000
  end
  
  on_error_spike sample_rate: 1.0, duration: 5.minutes
  on_high_load sample_rate: 0.01, threshold: 50_000
end

# Disable (explicit):
adaptive_sampling enabled: false

# Disable (no method call = disabled by default)
```

**Nested DSL Methods:**

#### `base_rate`
```ruby
base_rate(rate)  # Float (0.0-1.0)
```

#### `sample_by_value`
```ruby
sample_by_value do
  field :amount  # Field to check
  threshold 1000  # Threshold value
end
```

#### `on_error_spike`
```ruby
# ✅ FLATTENED (no nested block):
on_error_spike sample_rate: 1.0, duration: 5.minutes, error_rate_threshold: 0.05
```

#### `on_high_load`
```ruby
# ✅ FLATTENED (no nested block):
on_high_load sample_rate: 0.01, threshold: 50_000
```

---

## 4. Rate Limiting

### 4.1. `on_exceeded`

**Signature:**
```ruby
on_exceeded(action, sample_rate: nil)
```

**Parameters:**
- `action` (Symbol, required): Action when rate limit exceeded
- `sample_rate` (Float, optional): Sample rate if action is `:sample`

**Valid Actions:**
- `:drop` - Drop events (default)
- `:sample` - Sample events (keep `sample_rate` %)
- `:throttle` - Slow down (backpressure) **⚠️ RENAMED from `:backpressure`**

**Default:** `:drop`

**Type:** Symbol + Float (optional)

**Inheritance:** Yes (from base class)

**Examples:**
```ruby
# Drop (default):
on_exceeded :drop

# Sample:
on_exceeded :sample, sample_rate: 0.2  # Keep 20%

# Throttle (slow down):
on_exceeded :throttle
```

---

## 5. PII Filtering

### 5.1. `contains_pii`

**Signature:**
```ruby
contains_pii(boolean)
```

**Parameters:**
- `boolean` (Boolean, required): `true` or `false`

**Default:** None (Tier 2 default if not specified)

**Type:** Boolean

**Recommended:** ✅ YES (linter warns if missing)

**Inheritance:** Yes (from base class)

**Examples:**
```ruby
# No PII:
contains_pii false

# With PII:
contains_pii true
pii_filtering do
  # ... strategies
end
```

---

### 5.2. `pii_filtering`

**Signature:**
```ruby
pii_filtering(&block)
```

**Parameters:**
- Block with DSL: `masks`, `hashes`, `allows`, `partials`, `field`

**Required:** If `contains_pii true`

**Type:** Block

**Inheritance:** Yes (accumulated from base class)

**DSL Shortcuts:**

```ruby
pii_filtering do
  # Shortcuts (for simple cases):
  masks :password, :token          # → strategy: :mask (replace with ***)
  hashes :email, :phone            # → strategy: :hash (SHA256)
  allows :user_id, :order_id       # → strategy: :allow (no filtering)
  partials :phone, last_digits: 4  # → strategy: :partial (show last 4)
  
  # Detailed config (for complex cases):
  field :credit_card do
    strategy :partial
    show_last 4
    mask_char '*'
  end
end
```

**Examples:**
```ruby
# Simple (shortcuts):
class Events::UserLogin < E11y::Event::Base
  contains_pii true
  pii_filtering do
    masks :password, :token
    hashes :email, :phone
    allows :user_id, :action
  end
end

# Complex (field blocks):
class Events::PaymentProcessed < E11y::Event::Base
  contains_pii true
  pii_filtering do
    field :email do
      strategy :hash
      algorithm :sha256
    end
    
    field :credit_card do
      strategy :partial
      show_last 4
      mask_char '*'
    end
  end
end

# Mix shortcuts + field blocks:
class Events::UserRegistered < E11y::Event::Base
  contains_pii true
  pii_filtering do
    masks :password  # Shortcut
    hashes :email    # Shortcut
    
    field :phone do  # Detailed
      strategy :partial
      show_last 4
    end
  end
end
```

---

## 6. Metrics

### 6.1. `metric`

**Signature:**
```ruby
metric(type, name:, tags: [], **options)
```

**Parameters:**
- `type` (Symbol, required): Metric type
- `name` (String, required): Metric name
- `tags` (Array<Symbol>, optional): Tag names (default: `[]`)
- `**options`: Additional options

**Valid Types:**
- `:counter` - Monotonically increasing counter
- `:histogram` - Distribution of values
- `:gauge` - Current value

**Options:**
- `comment` (String): Metric description
- `value` (Proc): Value extractor (for histogram/gauge)
- `tag_extractors` (Hash<Symbol, Proc>): Tag value extractors
- `cardinality_limit` (Integer): Max series for this metric

**Type:** Symbol + Hash

**Inheritance:** Yes (accumulated from base class)

**Examples:**
```ruby
# Counter:
metric :counter,
       name: 'orders.created.total',
       tags: [:currency],
       comment: 'Total orders created'

# Histogram with value:
metric :histogram,
       name: 'payments.amount',
       tags: [:currency],
       value: ->(event) { event.payload[:amount] },
       comment: 'Payment amount distribution'

# With tag extractors:
metric :counter,
       name: 'user_actions.total',
       tags: [:user_segment, :action_type],
       tag_extractors: {
         user_segment: ->(event) { 
           User.find(event.payload[:user_id]).segment 
         }
       },
       cardinality_limit: 100
```

---

## 7. Cardinality Protection

### 7.1. `forbidden_metric_labels`

**Signature:**
```ruby
forbidden_metric_labels(*labels)
```

**Parameters:**
- `*labels` (Symbols): List of forbidden label names

**Default:** Global defaults: `:user_id`, `:order_id`, `:session_id`, `:trace_id`, `:request_id`, `:email`, `:ip_address`, `:uuid`

**Type:** Array<Symbol>

**Inheritance:** Yes (accumulated from base class)

**Examples:**
```ruby
# Event-level:
forbidden_metric_labels :user_id, :session_id

# Base class:
class Events::BaseUserEvent < E11y::Event::Base
  forbidden_metric_labels :user_id, :email, :ip_address
end
```

---

### 7.2. `safe_metric_labels`

**Signature:**
```ruby
safe_metric_labels(*labels)
```

**Parameters:**
- `*labels` (Symbols): List of safe label names

**Default:** None

**Type:** Array<Symbol>

**Inheritance:** Yes (accumulated from base class)

**Examples:**
```ruby
# Event-level:
safe_metric_labels :user_segment, :action_type, :status

# Base class:
class Events::BaseUserEvent < E11y::Event::Base
  safe_metric_labels :user_segment, :country, :plan
end
```

---

### 7.3. `default_cardinality_limit`

**Signature:**
```ruby
default_cardinality_limit(limit)
```

**Parameters:**
- `limit` (Integer, required): Max series per metric

**Default:** `100`

**Type:** Integer

**Inheritance:** Yes (from base class)

**Examples:**
```ruby
# Event-level:
default_cardinality_limit 50

# Base class:
class Events::BaseUserEvent < E11y::Event::Base
  default_cardinality_limit 100
end
```

---

## 8. Audit & Compliance

### 8.1. `audit_event`

**Signature:**
```ruby
audit_event(boolean)
```

**Parameters:**
- `boolean` (Boolean, required): `true` or `false`

**Default:** `false`

**Type:** Boolean

**Inheritance:** Yes (from base class)

**Side Effects:**
- If `true` → `retention = E11y.config.audit_retention` (auto, default: 7.years, configurable!)
- If `true` → `rate_limiting = false` (auto, **LOCKED** - override raises error!)
- If `true` → `sampling = false` (auto, **LOCKED** - override raises error!)

**Examples:**
```ruby
class Events::BaseAuditEvent < E11y::Event::Base
  audit_event true
  # ← Auto: retention = E11y.config.audit_retention (configurable!)
  #          rate_limiting = false (LOCKED!)
  #          sampling = false (LOCKED!)
end

# ❌ INVALID: Attempt to override locked settings
class Events::UserDeleted < E11y::Event::Base
  audit_event true
  rate_limiting true  # ← ERROR! Cannot override audit event rate_limiting
  sampling true       # ← ERROR! Cannot override audit event sampling
end

# ✅ VALID: Override retention (allowed)
class Events::UserDeleted < E11y::Event::Base
  audit_event true
  retention 10.years  # ← OK! Retention is configurable
end
```

**Validation (for gem developers):**
```ruby
def self.rate_limiting(enabled)
  if self._audit_event && enabled
    raise ArgumentError, "Cannot enable rate_limiting for audit events! Audit events must never be rate limited."
  end
  self._rate_limiting = enabled
end

def self.sampling(enabled)
  if self._audit_event && enabled
    raise ArgumentError, "Cannot enable sampling for audit events! Audit events must never be sampled."
  end
  self._sampling = enabled
end
```

---

### 8.2. `signing`

**Signature:**
```ruby
signing(&block)
```

**Parameters:**
- Block with DSL: `enabled`, `algorithm`

**Default:** Disabled

**Type:** Block

**Inheritance:** Yes (from base class)

**Examples:**
```ruby
signing do
  enabled true
  algorithm :ed25519  # :ed25519, :rsa, :hmac
end
```

---

## 9. Inheritance & Presets

### 9.1. Base Classes

**Pattern:**
```ruby
# Define base class:
module Events
  class BasePaymentEvent < E11y::Event::Base
    severity :success
    sample_rate 1.0
    retention 7.years
    adapters [:loki, :sentry, :s3]
  end
end

# Inherit from base:
class Events::PaymentSucceeded < Events::BasePaymentEvent
  schema do; required(:transaction_id).filled(:string); end
  # ← Inherits ALL config from BasePaymentEvent
end
```

**Implementation (for gem developers):**
```ruby
# lib/e11y/event/base.rb
class E11y::Event::Base
  class_attribute :_severity, instance_writer: false, default: nil
  class_attribute :_sample_rate, instance_writer: false, default: nil
  class_attribute :_adapters, instance_writer: false, default: []
  
  def self.severity(level = nil)
    return self._severity if level.nil?
    # Validation here
    self._severity = level
  end
end
```

---

### 9.2. Preset Modules

**Pattern:**
```ruby
# Define preset:
module E11y::Presets
  module HighValueEvent
    extend ActiveSupport::Concern
    
    included do
      rate_limit 10_000
      sample_rate 1.0
      retention 7.years
      adapters [:loki, :sentry, :s3_archive]
    end
  end
end

# Use preset:
class Events::PaymentProcessed < E11y::Event::Base
  include E11y::Presets::HighValueEvent  # ← All config inherited!
  schema do; required(:transaction_id).filled(:string); end
end
```

**Built-in Presets:**
- `E11y::Presets::HighValueEvent`
- `E11y::Presets::DebugEvent`
- `E11y::Presets::AuditEvent`
- `E11y::Presets::PiiAwareEvent`
- `E11y::Presets::MetricSafeEvent`

---

## 10. Validations

### 10.1. Schema Validation

**✅ REQUIRED** - Every event MUST have schema

```ruby
class E11y::Event::Base
  def self.inherited(subclass)
    super
    at_exit do
      unless subclass.instance_variable_defined?(:@_schema)
        raise "#{subclass} missing schema! Every event must define schema."
      end
    end
  end
end
```

---

### 10.2. Severity Validation

**✅ REQUIRED** - Validates severity at class load

```ruby
VALID_SEVERITIES = [:debug, :info, :success, :warn, :error, :fatal]

def self.severity(level)
  unless VALID_SEVERITIES.include?(level)
    raise ArgumentError, "Invalid severity: #{level}. Valid: #{VALID_SEVERITIES.join(', ')}"
  end
  self._severity = level
end
```

---

### 10.3. Adapter Validation

**✅ REQUIRED** - Validates adapters at class load

```ruby
def self.adapters(list)
  list.each do |adapter|
    unless E11y.registered_adapters.include?(adapter)
      raise ArgumentError, "Unknown adapter: #{adapter}. Registered: #{E11y.registered_adapters.keys.join(', ')}"
    end
  end
  self._adapters = list
end
```

---

## 11. Precedence Rules

**When multiple sources define same config, precedence (highest to lowest):**

1. **Event-level explicit config** (highest priority)
2. **Preset module** (`include E11y::Presets::HighValueEvent`)
3. **Base class inheritance** (`class < BasePaymentEvent`)
4. **Convention** (severity → adapters, sample_rate, retention)
5. **Global default** (config.default_adapters) (lowest priority)

**Example:**
```ruby
# Global config:
E11y.configure do |config|
  config.default_adapters = [:loki]  # 5. Global default
end

# Base class:
class Events::BasePaymentEvent < E11y::Event::Base
  adapters [:loki, :sentry]  # 3. Base class
end

# Preset:
module E11y::Presets::HighValueEvent
  included do
    adapters [:loki, :sentry, :s3]  # 2. Preset
  end
end

# Event:
class Events::PaymentSucceeded < Events::BasePaymentEvent
  include E11y::Presets::HighValueEvent
  adapters [:loki, :sentry, :pagerduty]  # 1. Event-level (WINS!)
end

# Result: [:loki, :sentry, :pagerduty]
```

**Mixing Inheritance + Presets:**
```ruby
class Events::CriticalPayment < Events::BasePaymentEvent
  include E11y::Presets::HighValueEvent
  
  # Precedence:
  # 1. Event-level (if specified)
  # 2. Preset (HighValueEvent)
  # 3. Base class (BasePaymentEvent)
  # 4. Convention
  # 5. Global default
end
```

---

## 12. Environment-Specific Config

**Pattern:**
```ruby
# Development vs Production:
class Events::DebugQuery < E11y::Event::Base
  severity :debug
  adapters Rails.env.production? ? [:loki] : [:file]
  sample_rate Rails.env.production? ? 0.01 : 1.0
end

# Using Rails.env helper:
class Events::DebugSqlQuery < E11y::Event::Base
  severity :debug
  
  if Rails.env.production?
    adapters [:loki]
    sample_rate 0.01
  else
    adapters [:file]
    sample_rate 1.0
  end
end

# Using config/environments/*.rb:
# config/environments/production.rb
E11y.configure do |config|
  config.debug_adapters = [:loki]
  config.debug_sample_rate = 0.01
end

# config/environments/development.rb
E11y.configure do |config|
  config.debug_adapters = [:file]
  config.debug_sample_rate = 1.0
end

# Event:
class Events::DebugQuery < E11y::Event::Base
  severity :debug
  adapters E11y.config.debug_adapters
  sample_rate E11y.config.debug_sample_rate
end
```

---

## 📊 Quick Reference

### Zero-Config Event (90% of cases)

```ruby
class Events::OrderCreated < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
  end
  # ← That's it! All config from conventions
end
```

### With Inheritance

```ruby
class Events::PaymentSucceeded < Events::BasePaymentEvent
  schema do; required(:transaction_id).filled(:string); end
  # ← Inherits: severity, sample_rate, retention, adapters, PII rules
end
```

### With Preset

```ruby
class Events::PaymentProcessed < E11y::Event::Base
  include E11y::Presets::HighValueEvent  # ← 1-line config!
  schema do; required(:transaction_id).filled(:string); end
end
```

### Full Custom Config

```ruby
class Events::CriticalEvent < E11y::Event::Base
  # Core:
  severity :error
  rate_limit 10_000, window: 1.minute
  sample_rate 1.0
  retention 7.years
  
  # Adapters:
  adapters [:loki, :sentry, :pagerduty]
  
  # Sampling:
  adaptive_sampling do
    base_rate 1.0
    on_error_spike sample_rate: 1.0, duration: 10.minutes
  end
  
  # PII:
  contains_pii true
  pii_filtering do
    masks :password
    hashes :email
  end
  
  # Metrics:
  metric :counter, name: 'critical_events.total', tags: [:severity]
  
  # Schema:
  schema do
    required(:error_code).filled(:string)
    required(:error_message).filled(:string)
  end
end
```

---

**Status:** ✅ Unified DSL Specification Complete  
**Version:** 1.1.0  
**Next:** Apply to all documentation (UC-002, UC-007, UC-011, UC-013, UC-014, ADR-004, COMPREHENSIVE-CONFIGURATION, QUICK-START)
