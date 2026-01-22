# AUDIT-032: UC-008 OpenTelemetry Integration - OTel Adapter Implementation

**Audit ID:** FEAT-5034  
**Parent Audit:** FEAT-5033 (AUDIT-032: UC-008 OpenTelemetry Integration verified)  
**Auditor:** AI Assistant (Claude Sonnet 4.5)  
**Date:** 2026-01-21  
**Complexity:** 6/10 (Medium)

---

## 📋 Executive Summary

**Audit Objective:** Verify OTel adapter implementation (LogRecord export, field mapping, resources).

**Overall Status:** ⚠️ **PARTIAL PASS** (67%)

**DoD Compliance:**
- ✅ **Adapter**: lib/e11y/adapters/otel_logs.rb exports LogRecord
- ✅ **Mapping**: Event fields → OTel attributes, levels → severity
- ⚠️ **Resources**: service.name included, service.version NOT included

**Critical Findings:**
- ✅ OTel Logs adapter works (exports LogRecord via emit_log_record)
- ✅ Severity mapping complete (E11y → OTel severity numbers)
- ✅ Attributes mapping works (event.* prefix, cardinality protection)
- ⚠️ service.version NOT included (DoD expects service.version resource)
- ✅ Comprehensive tests (282 lines, integration tests)

**Production Readiness:** ⚠️ **PARTIAL** (adapter works, service.version missing)
**Recommendation:** Add service.version attribute (R-196, MEDIUM)

---

## 🎯 Audit Scope

### DoD Requirements (from FEAT-5034)

**Requirement 1: Adapter**
- **Expected:** lib/e11y/adapters/otel_logs.rb exports LogRecord
- **Verification:** Check code, verify emit_log_record calls
- **Evidence:** Implementation, LogRecord creation

**Requirement 2: Mapping**
- **Expected:** Event fields → OTel attributes, levels → severity
- **Verification:** Check build_attributes, map_severity methods
- **Evidence:** Mapping logic, tests

**Requirement 3: Resources**
- **Expected:** E11y includes service.name, service.version resources
- **Verification:** Check build_attributes for service metadata
- **Evidence:** service.name, service.version attributes

---

## 🔍 Detailed Findings

### Finding F-461: OTel LogRecord Export ✅ PASS

**Requirement:** lib/e11y/adapters/otel_logs.rb exports LogRecord.

**Implementation:**

**Code Evidence (lib/e11y/adapters/otel_logs.rb):**
```ruby
# Line 1-18: Dependencies and LoadError handling
begin
  require "opentelemetry/sdk"
  require "opentelemetry/logs"
rescue LoadError
  raise LoadError, <<~ERROR
    OpenTelemetry SDK not available!
    
    To use E11y::Adapters::OTelLogs, add to your Gemfile:
    
      gem 'opentelemetry-sdk'
      gem 'opentelemetry-logs'
  ERROR
end

# Line 94-105: write() method exports LogRecord
def write(event_data)
  log_record = build_log_record(event_data)  # ← Build LogRecord
  @logger.emit_log_record(log_record)        # ← Export to OTel
  true
rescue StandardError => e
  warn "[E11y::OTelLogs] Failed to write event: #{e.message}"
  false
end

# Line 137-153: build_log_record() creates OpenTelemetry::SDK::Logs::LogRecord
def build_log_record(event_data)
  OpenTelemetry::SDK::Logs::LogRecord.new(
    timestamp: event_data[:timestamp] || Time.now.utc,
    observed_timestamp: Time.now.utc,
    severity_number: map_severity(event_data[:severity]),
    severity_text: event_data[:severity].to_s.upcase,
    body: event_data[:event_name],
    attributes: build_attributes(event_data),
    trace_id: event_data[:trace_id],
    span_id: event_data[:span_id],
    trace_flags: nil
  )
end
```

**OTel SDK Integration:**
```ruby
# Line 128-135: setup_logger_provider()
def setup_logger_provider
  @logger_provider = OpenTelemetry::SDK::Logs::LoggerProvider.new
  @logger = @logger_provider.logger(
    name: "e11y",
    version: E11y::VERSION  # ← OTel logger version
  )
end
```

**Verification:**
✅ **PASS** (LogRecord export works)

**Evidence:**
1. **Correct class:** OpenTelemetry::SDK::Logs::LogRecord (line 142)
2. **All required fields:** timestamp, severity_number, severity_text, body, attributes, trace_id, span_id
3. **Export method:** @logger.emit_log_record(log_record) (line 100)
4. **Logger provider:** OpenTelemetry::SDK::Logs::LoggerProvider (line 130)
5. **Error handling:** rescue block prevents failures (lines 102-104)

**Test Evidence (spec/e11y/adapters/otel_logs_spec.rb):**
```ruby
# Line 64-66: Export test
it "emits log record to OTel logger" do
  expect(adapter.write(event_data)).to be true
end

# Line 23: Adapter initialized with service_name
let(:adapter) { described_class.new(service_name: "test-service") }
```

**Conclusion:** ✅ **PASS** (OTel LogRecord export works as expected)

---

### Finding F-462: Field Mapping (Event → OTel Attributes) ✅ PASS

**Requirement:** Event fields → OTel attributes, levels → severity.

**Implementation:**

**Attributes Mapping (lib/e11y/adapters/otel_logs.rb):**
```ruby
# Line 163-192: build_attributes() method
def build_attributes(event_data)
  attributes = {}

  # Add event metadata
  attributes["event.name"] = event_data[:event_name]     # ← Event name
  attributes["event.version"] = event_data[:v] if event_data[:v]  # ← Event version
  attributes["service.name"] = @service_name if @service_name  # ← Service name

  # Add payload (with cardinality protection)
  payload = event_data[:payload] || {}
  payload.each do |key, value|
    # C04: Cardinality protection - limit attributes
    break if attributes.size >= @max_attributes  # ← Max 50 attributes

    # C08: Baggage PII protection - only allowlisted keys
    next unless baggage_allowed?(key)  # ← PII filtering

    attributes["event.#{key}"] = value  # ← Generic 'event.' prefix
  end

  attributes
end
```

**Severity Mapping (lib/e11y/adapters/otel_logs.rb):**
```ruby
# Line 62-69: SEVERITY_MAPPING constant
SEVERITY_MAPPING = {
  debug: OpenTelemetry::SDK::Logs::Severity::DEBUG,
  info: OpenTelemetry::SDK::Logs::Severity::INFO,
  success: OpenTelemetry::SDK::Logs::Severity::INFO, # OTel has no "success"
  warn: OpenTelemetry::SDK::Logs::Severity::WARN,
  error: OpenTelemetry::SDK::Logs::Severity::ERROR,
  fatal: OpenTelemetry::SDK::Logs::Severity::FATAL
}.freeze

# Line 155-161: map_severity() method
def map_severity(severity)
  SEVERITY_MAPPING[severity] || OpenTelemetry::SDK::Logs::Severity::INFO
end
```

**Verification:**
✅ **PASS** (field mapping works)

**Evidence:**
1. **Event metadata mapped:** event.name, event.version, service.name (lines 175-177)
2. **Payload mapped:** payload keys → event.{key} attributes (lines 179-189)
3. **Severity mapped:** E11y severity → OTel severity numbers (lines 62-69)
4. **Cardinality protection:** max_attributes limit (line 183)
5. **PII protection:** baggage_allowlist filtering (line 186)

**Test Evidence (spec/e11y/adapters/otel_logs_spec.rb):**
```ruby
# Line 96-112: Severity mapping test (all 6 severities)
it "maps E11y severities to OTel severity numbers" do
  {
    debug: OpenTelemetry::SDK::Logs::Severity::DEBUG,
    info: OpenTelemetry::SDK::Logs::Severity::INFO,
    success: OpenTelemetry::SDK::Logs::Severity::INFO,  # ← Maps to INFO
    warn: OpenTelemetry::SDK::Logs::Severity::WARN,
    error: OpenTelemetry::SDK::Logs::Severity::ERROR,
    fatal: OpenTelemetry::SDK::Logs::Severity::FATAL
  }.each do |e11y_severity, otel_severity|
    result = adapter.send(:map_severity, e11y_severity)
    expect(result).to eq(otel_severity)
  end
end

# Line 115-133: Attributes mapping test
it "includes event metadata in attributes" do
  attributes = adapter.send(:build_attributes, event_data)
  expect(attributes["event.name"]).to eq("order.paid")
  expect(attributes["service.name"]).to eq("test-service")
end

it "prefixes payload attributes with 'event.'" do
  attributes = adapter.send(:build_attributes, event_data)
  expect(attributes).to have_key("event.order_id")
  expect(attributes).to have_key("event.amount")
end
```

**Conclusion:** ✅ **PASS** (field mapping works as expected)

---

### Finding F-463: Resources (service.name, service.version) ⚠️ PARTIAL

**Requirement:** E11y includes service.name, service.version resources.

**Implementation:**

**Code Evidence (lib/e11y/adapters/otel_logs.rb):**
```ruby
# Line 177: service.name attribute
attributes["service.name"] = @service_name if @service_name  # ✅ Present

# ❌ NO service.version attribute!
# Expected: attributes["service.version"] = @service_version
```

**What's Included:**
```ruby
# service.name:
attributes["service.name"] = @service_name  # ✅ From config
# Example: "test-service", "my-app", "payment-service"

# ❌ service.version NOT included!
```

**Where E11y::VERSION is Used:**
```ruby
# Line 133: OTel logger version (NOT service.version!)
@logger = @logger_provider.logger(
  name: "e11y",
  version: E11y::VERSION  # ← E11y gem version (e.g., "1.0.0")
)

# This is the E11y gem version, NOT the service/app version!
```

**DoD Expectation:**
```ruby
# DoD expects service.version as OTel resource:
attributes["service.version"] = "1.2.3"  # ← App version (e.g., from Rails app VERSION)
```

**OTel Semantic Conventions (service.version):**
- **Definition:** "The version string of the service API or implementation"
- **Example:** "1.2.3", "2.4.0-beta", "v3.1.0"
- **Specification:** OTel Semantic Conventions for Resources
- **Type:** Resource attribute (not regular attribute)

**NOTE: Attributes vs Resources in OTel:**

**Attributes (Current Implementation):**
```ruby
# lib/e11y/adapters/otel_logs.rb:177
attributes["service.name"] = @service_name  # ← Attribute (not Resource!)
```

**Resources (OTel Standard):**
```ruby
# OTel SDK standard pattern (NOT implemented in E11y):
resource = OpenTelemetry::SDK::Resources::Resource.create(
  "service.name" => "my-app",
  "service.version" => "1.2.3"  # ← Should be Resource, not attribute
)

logger_provider = OpenTelemetry::SDK::Logs::LoggerProvider.new(
  resource: resource  # ← Resources attached to LoggerProvider
)
```

**Verification:**
⚠️ **PARTIAL PASS** (service.name as attribute, service.version missing)

**Evidence:**
1. **service.name present:** Added as attribute (line 177)
2. **service.version missing:** No service.version attribute
3. **E11y::VERSION used for logger:** Logger version, not service version (line 133)
4. **Resources NOT used:** No OpenTelemetry::SDK::Resources::Resource
5. **Attributes vs Resources:** service.name should be Resource, but it's an attribute

**Test Evidence (spec/e11y/adapters/otel_logs_spec.rb):**
```ruby
# Line 116-120: service.name test (as attribute)
it "includes event metadata in attributes" do
  attributes = adapter.send(:build_attributes, event_data)
  expect(attributes["event.name"]).to eq("order.paid")
  expect(attributes["service.name"]).to eq("test-service")  # ✅ Tested
end

# ❌ NO test for service.version!
```

**Conclusion:** ⚠️ **PARTIAL PASS**
- **Rationale:**
  - DoD expects: service.name AND service.version resources
  - Implementation: service.name as attribute (line 177), service.version missing
  - OTel standard: service.name/version should be Resources (not attributes)
  - Impact: service.version missing, service.name not following OTel conventions
- **Severity:** MEDIUM (service.name works, but service.version missing)

---

## 📊 DoD Compliance Matrix

| DoD Requirement | Expected | Actual | Status | Evidence |
|-----------------|----------|--------|--------|----------|
| (1) **Adapter** | LogRecord export | ✅ emit_log_record | ✅ **PASS** | F-461 |
| (2) **Mapping** | Fields → attributes, levels → severity | ✅ Works | ✅ **PASS** | F-462 |
| (3) **Resources** | service.name, service.version | ⚠️ service.name only | ⚠️ **PARTIAL** | F-463 |

**Overall Compliance:** 2/3 fully met (67%), 1/3 partial (33%)

---

## 🚨 Critical Issues

### Issue 1: service.version Missing - MEDIUM

**Severity:** MEDIUM  
**Impact:** OTel backends cannot identify service version

**DoD Expectation:**
```ruby
# DoD expects both service.name and service.version
attributes["service.name"] = "my-app"
attributes["service.version"] = "1.2.3"  # ❌ Missing!
```

**Current Implementation:**
```ruby
# Line 177: Only service.name
attributes["service.name"] = @service_name if @service_name
# ❌ NO service.version attribute!
```

**OTel Semantic Conventions:**
- **service.name** (REQUIRED): "Logical name of the service"
- **service.version** (RECOMMENDED): "Version string of the service API or implementation"
- **Both** should be OTel Resources (not attributes)

**Workaround:**
```ruby
# Option 1: Add service.version as attribute (quick fix)
def build_attributes(event_data)
  attributes = {}
  attributes["event.name"] = event_data[:event_name]
  attributes["event.version"] = event_data[:v] if event_data[:v]
  attributes["service.name"] = @service_name if @service_name
  attributes["service.version"] = @service_version if @service_version  # ← ADD
  # ...
end

# Option 2: Use OTel Resources (OTel standard)
def setup_logger_provider
  resource = OpenTelemetry::SDK::Resources::Resource.create(
    "service.name" => @service_name,
    "service.version" => @service_version  # ← Proper OTel Resources
  )
  
  @logger_provider = OpenTelemetry::SDK::Logs::LoggerProvider.new(
    resource: resource  # ← Attach resources
  )
  @logger = @logger_provider.logger(name: "e11y", version: E11y::VERSION)
end
```

**Recommendation:**
- **R-196**: Add service.version attribute (MEDIUM)
  - Add `@service_version` to initializer
  - Add `attributes["service.version"] = @service_version` to build_attributes
  - OR: Use OpenTelemetry::SDK::Resources::Resource (OTel standard)
  - Add test for service.version presence

---

### Issue 2: service.name/version as Attributes (Not Resources) - LOW

**Severity:** LOW  
**Impact:** Not following OTel best practices (but works)

**OTel Standard:**
```ruby
# OTel best practice: service.* as Resources
resource = OpenTelemetry::SDK::Resources::Resource.create(
  "service.name" => "my-app",
  "service.version" => "1.2.3"
)

logger_provider = OpenTelemetry::SDK::Logs::LoggerProvider.new(
  resource: resource  # ← Resources attached to provider (not per-log)
)
```

**E11y Implementation:**
```ruby
# E11y: service.name as attribute (per-log)
attributes["service.name"] = @service_name  # ← Attribute (not Resource)
```

**Difference:**
- **Resources:** Attached to LoggerProvider, shared across all logs (efficient)
- **Attributes:** Added to each LogRecord (repeated data, less efficient)

**Impact:**
- Works in OTel backends (both attributes and resources recognized)
- Less efficient (service.name repeated in every log)
- Not following OTel best practices

**Recommendation:**
- **R-197**: Use OTel Resources for service.* (LOW)
  - Create Resource with service.name, service.version
  - Attach to LoggerProvider (not per-log attributes)
  - Update tests

---

## ✅ Strengths Identified

### Strength 1: Complete LogRecord Implementation ✅

**Implementation:**
- All required fields: timestamp, severity, body, attributes, trace_id, span_id
- Correct OTel SDK types: OpenTelemetry::SDK::Logs::LogRecord
- Error handling prevents failures

**Quality:**
- Clean separation: build_log_record, map_severity, build_attributes
- Proper OTel SDK usage

### Strength 2: Severity Mapping Complete ✅

**Implementation:**
```ruby
# All 6 E11y severities mapped:
SEVERITY_MAPPING = {
  debug: OpenTelemetry::SDK::Logs::Severity::DEBUG,
  info: OpenTelemetry::SDK::Logs::Severity::INFO,
  success: OpenTelemetry::SDK::Logs::Severity::INFO,  # ← Maps to INFO (no "success" in OTel)
  warn: OpenTelemetry::SDK::Logs::Severity::WARN,
  error: OpenTelemetry::SDK::Logs::Severity::ERROR,
  fatal: OpenTelemetry::SDK::Logs::Severity::FATAL
}
```

**Quality:**
- Covers all E11y severities
- Maps :success to :info (reasonable default)
- Fallback to INFO for unknown (safe)

### Strength 3: Protection Layers ✅

**Cardinality Protection (C04):**
```ruby
# Line 183: Max attributes limit
break if attributes.size >= @max_attributes  # Max 50
```

**PII Protection (C08):**
```ruby
# Line 186: Baggage allowlist
next unless baggage_allowed?(key)  # Only allowlisted keys
```

**Benefits:**
- Prevents high cardinality (max 50 attributes)
- Prevents PII leakage (allowlist filtering)

### Strength 4: Comprehensive Tests ✅

**Test Coverage:**
- 282 lines of integration tests
- Severity mapping tested (all 6 severities + unknown)
- Attributes mapping tested (event metadata, payload)
- PII protection tested (C08 baggage allowlist)
- Cardinality protection tested (C04 max_attributes)

**Quality:**
- Integration tests (requires OpenTelemetry SDK)
- Comprehensive coverage
- Tests positive and negative cases

---

## 📋 Gaps and Recommendations

### Recommendation R-196: Add service.version Attribute (MEDIUM)

**Priority:** MEDIUM  
**Description:** Add service.version to OTel attributes  
**Rationale:** DoD expects service.version, currently missing

**Implementation:**

**Option 1: Add as Attribute (Quick Fix)**
```ruby
# lib/e11y/adapters/otel_logs.rb:85-92 (update initializer)
def initialize(service_name: nil, service_version: nil, baggage_allowlist: DEFAULT_BAGGAGE_ALLOWLIST, max_attributes: 50, **)
  super(**)
  @service_name = service_name
  @service_version = service_version  # ← NEW: Add service_version
  @baggage_allowlist = baggage_allowlist
  @max_attributes = max_attributes

  setup_logger_provider
end

# lib/e11y/adapters/otel_logs.rb:177-178 (update build_attributes)
attributes["service.name"] = @service_name if @service_name
attributes["service.version"] = @service_version if @service_version  # ← NEW
```

**Option 2: Use OTel Resources (OTel Standard, Recommended)**
```ruby
# lib/e11y/adapters/otel_logs.rb:128-135 (update setup_logger_provider)
def setup_logger_provider
  # Create OTel Resource with service metadata
  resource = OpenTelemetry::SDK::Resources::Resource.create(
    "service.name" => @service_name || "e11y-app",
    "service.version" => @service_version || E11y::VERSION
  )
  
  @logger_provider = OpenTelemetry::SDK::Logs::LoggerProvider.new(
    resource: resource  # ← Attach resources
  )
  @logger = @logger_provider.logger(
    name: "e11y",
    version: E11y::VERSION
  )
end

# Remove from build_attributes (no longer needed):
# attributes["service.name"] = @service_name  # ← DELETE
```

**Test Update:**
```ruby
# spec/e11y/adapters/otel_logs_spec.rb (add test)
it "includes service.version in attributes" do
  adapter_with_version = described_class.new(
    service_name: "test-service",
    service_version: "1.2.3"
  )
  
  attributes = adapter_with_version.send(:build_attributes, event_data)
  expect(attributes["service.version"]).to eq("1.2.3")
end
```

**Acceptance Criteria:**
- service.version parameter added to initializer
- service.version included in attributes (or resources)
- Test added for service.version
- Defaults to E11y::VERSION if not provided

**Impact:** Matches DoD expectations, follows OTel conventions  
**Effort:** LOW (single parameter, one line change, one test)

---

### Recommendation R-197: Use OTel Resources for service.* (LOW)

**Priority:** LOW  
**Description:** Use OpenTelemetry::SDK::Resources::Resource for service.name, service.version  
**Rationale:** OTel best practice, more efficient than per-log attributes

**Benefits:**
1. **Efficient:** Resources attached to LoggerProvider (not repeated per-log)
2. **OTel standard:** Follows OTel Semantic Conventions for Resources
3. **Queryable:** OTel backends optimize resource queries
4. **Aggregatable:** Can group by service.name/version

**Implementation:**
See Option 2 in R-196 above.

**Acceptance Criteria:**
- Use OpenTelemetry::SDK::Resources::Resource
- Attach to LoggerProvider (not per-log)
- Remove service.* from build_attributes
- Update tests

**Impact:** Follows OTel best practices, more efficient  
**Effort:** MEDIUM (refactor setup_logger_provider, update tests)

---

## 🏁 Audit Conclusion

### Summary

**Overall Status:** ⚠️ **PARTIAL PASS** (67%)

**DoD Compliance:**
- ✅ **(1) Adapter**: PASS (LogRecord export works)
- ✅ **(2) Mapping**: PASS (fields → attributes, levels → severity)
- ⚠️ **(3) Resources**: PARTIAL (service.name present, service.version missing)

**Critical Findings:**
- ✅ OTel Logs adapter implemented (exports LogRecord)
- ✅ Severity mapping complete (6 severities mapped)
- ✅ Attributes mapping works (event.* prefix)
- ⚠️ service.version missing (DoD expects service.version)
- ⚠️ service.name as attribute (should be Resource per OTel conventions)
- ✅ Comprehensive tests (282 lines, integration tests)

**Production Readiness Assessment:**
- **OTel Adapter:** ✅ **PRODUCTION-READY** (100%)
  - LogRecord export works
  - Correct OTel SDK integration
  - Error handling robust
- **Field Mapping:** ✅ **PRODUCTION-READY** (100%)
  - Severity mapping complete
  - Attributes mapping works
  - Protection layers applied (cardinality, PII)
- **Resources:** ⚠️ **PARTIAL** (50%)
  - service.name present (as attribute)
  - service.version missing
  - Not using OTel Resources (should)

**Risk:** ⚠️ LOW
- Adapter works (core functionality solid)
- service.version missing (minor metadata gap)
- service.name as attribute (works, but not OTel best practice)

**Confidence Level:** HIGH (100%)
- Verified code implementation (otel_logs.rb lines 60-204)
- Verified test coverage (otel_logs_spec.rb 282 lines)
- Verified OTel SDK integration (LogRecord, Logger, LoggerProvider)

**Recommendations:**
1. **R-196**: Add service.version attribute (MEDIUM) - **SHOULD ADD**
2. **R-197**: Use OTel Resources for service.* (LOW) - **NICE TO HAVE**

**Next Steps:**
1. Continue to FEAT-5035 (Test OTel backend compatibility)
2. Track R-196 as MEDIUM priority (add service.version)
3. Consider R-197 for better OTel compliance

---

**Audit completed:** 2026-01-21  
**Status:** ⚠️ PARTIAL PASS (adapter works, service.version missing)  
**Next task:** FEAT-5035 (Test OTel backend compatibility)

---

## 📎 References

**Implementation:**
- `lib/e11y/adapters/otel_logs.rb` (204 lines)
  - Line 94-105: `write()` method (LogRecord export)
  - Line 137-153: `build_log_record()` (LogRecord creation)
  - Line 163-192: `build_attributes()` (attributes mapping)
  - Line 155-161: `map_severity()` (severity mapping)
  - Line 177: `service.name` attribute (service.version missing)
- `spec/e11y/adapters/otel_logs_spec.rb` (282 lines)
  - Line 64-66: LogRecord export test
  - Line 96-112: Severity mapping test
  - Line 115-133: Attributes mapping test

**Documentation:**
- `docs/use_cases/UC-008-opentelemetry-integration.md` (1154 lines)
  - Line 70-99: OpenTelemetry Collector Adapter section
- `docs/ADR-007-opentelemetry-integration.md` (1314 lines)
  - Previously audited in AUDIT-028

**OTel Semantic Conventions:**
- service.name: "Logical name of the service" (REQUIRED)
- service.version: "Version string of the service" (RECOMMENDED)
- Resources: service.* should be Resources, not attributes
