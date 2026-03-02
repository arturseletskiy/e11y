# UC-007 PII Filtering - Integration Test Analysis

**Task:** FEAT-5382  
**Date:** 2026-01-26  
**Phase:** Analysis (Phase 1 of 4)

---

## 1. Unit Test Coverage Analysis

### Current Coverage
- **File:** `spec/e11y/middleware/pii_filtering_spec.rb`
- **Size:** 813 lines
- **Test cases:** 31 examples, 0 failures
- **Test blocks:** 48 (describe/context/it)

### What's Tested (Unit Level)

#### ✅ 3-Tier Strategy
1. **Tier 1** - No PII (`contains_pii false`) - skip filtering
2. **Tier 2** - Rails filters (default) - use `Rails.application.config.filter_parameters`
3. **Tier 3** - Explicit PII (`contains_pii true`) - deep field-level filtering

#### ✅ Field Strategies (5 types)
1. `:mask` - Replace with `[FILTERED]`
2. `:hash` - One-way hash (consistent, irreversible)
3. `:partial` - Keep first/last chars (`us***com`)
4. `:redact` - Remove entirely (`nil`)
5. `:allow` - Keep as-is (whitelist)

#### ✅ Pattern-Based Filtering
- Email regex
- SSN regex
- Credit card regex
- IP address regex

#### ✅ Nested Data
- Nested hashes (deep recursion)
- Arrays with PII
- Nested arrays

#### ✅ Edge Cases
- `nil` values
- Empty strings
- Empty hashes/arrays
- Unknown strategies (fallback to `:allow`)
- Invalid tier (fallback to no filtering)

### What's NOT Tested (Integration Gaps)

#### ❌ Real Rails Request/Response Flow
- No tests with actual `ActionDispatch::Request`
- No tests with Rails controller actions
- No tests with `params` from forms/JSON
- No tests with request headers
- No tests with multipart/form-data (file uploads)

#### ❌ Middleware Stack Integration
- Not tested as part of Rails middleware chain
- No tests with other middlewares (order matters)
- No tests with `ActionDispatch::Cookies`
- No tests with `ActionDispatch::Session`

#### ❌ Performance in Real Requests
- Unit tests measure isolated middleware call (~0.05-0.2ms)
- No measurement of actual request overhead in Rails
- No load testing with concurrent requests
- No profiling of memory allocation

#### ❌ Real PII Data Scenarios
- Unit tests use simple strings (`"secret123"`, `"user@example.com"`)
- No tests with real credit card formats (Luhn validation)
- No tests with international phone numbers
- No tests with non-ASCII PII (Cyrillic emails, etc.)

#### ❌ Configuration Scenarios
- No tests verifying `Rails.application.config.filter_parameters` actually used
- No tests with custom replacement text
- No tests with filter conflicts (Rails vs E11y)

#### ❌ Error Scenarios
- No tests with malformed JSON
- No tests with encoding errors (non-UTF8)
- No tests with very large payloads (>1MB)
- No tests with circular references

---

## 2. Real-World Usage Patterns

### Pattern 1: User Registration Flow
```ruby
# POST /users/register
params = {
  user: {
    email: 'user@example.com',
    password: 'MySecure123!',
    password_confirmation: 'MySecure123!',
    name: 'John Doe',
    profile: {
      phone: '+1-555-123-4567',
      ssn: '123-45-6789'
    }
  }
}

# Expected filtering:
# - password → [FILTERED]
# - password_confirmation → [FILTERED]
# - email → [FILTERED] or hashed
# - phone → [FILTERED]
# - ssn → [FILTERED]
# - name → kept (not PII per se)
```

**Integration test needed:** Full Rails request cycle with form params.

### Pattern 2: API Authentication Headers
```ruby
# API request with sensitive headers
headers = {
  'Authorization' => 'Bearer sk_live_abc123xyz',
  'X-API-Key' => 'api_secret_key_12345',
  'User-Agent' => 'MyApp/1.0'
}

# Expected filtering:
# - Authorization header → [FILTERED]
# - X-API-Key header → [FILTERED]
# - User-Agent → kept (not sensitive)
```

**Integration test needed:** Rails middleware capturing request headers.

### Pattern 3: JSON API with Nested PII
```ruby
# POST /api/v1/orders (JSON body)
{
  "order": {
    "items": [...],
    "payment": {
      "card_number": "4111-1111-1111-1111",
      "cvv": "123",
      "billing": {
        "email": "billing@company.com",
        "phone": "+1-555-999-8888"
      }
    }
  }
}

# Expected filtering:
# - card_number → [FILTERED]
# - cvv → [FILTERED]
# - email → [FILTERED]
# - phone → [FILTERED]
# - items → kept
```

**Integration test needed:** JSON API request with deep nesting.

### Pattern 4: File Upload with PII in Metadata
```ruby
# POST /documents (multipart/form-data)
params = {
  document: {
    file: <binary Rack::Multipart::UploadedFile>,
    filename: 'resume_john_doe_SSN_123-45-6789.pdf',
    metadata: {
      uploaded_by: 'user@example.com'
    }
  }
}

# Expected filtering:
# - filename → filter SSN pattern
# - uploaded_by → [FILTERED]
# - file binary data → not scanned (too expensive)
```

**Integration test needed:** Multipart upload with PII in filenames.

### Pattern 5: Background Job with Sensitive Args
```ruby
# Sidekiq/ActiveJob with PII
SendEmailJob.perform_later(
  to: 'user@example.com',
  subject: 'Password reset',
  token: 'reset_token_abc123',
  user_id: '12345'
)

# Expected filtering in job events:
# - to → [FILTERED] (email)
# - token → [FILTERED] (Rails filter_parameters)
# - user_id → kept (whitelisted)
```

**Integration test needed:** ActiveJob/Sidekiq instrumentation with PII args.

### Pattern 6: Rails Logger Integration
```ruby
# Rails.logger calls with PII
Rails.logger.info "User #{user_id} logged in from IP #{ip_address}"
Rails.logger.error "Payment failed for card #{card_number}"

# Expected filtering:
# - IP address pattern → [IP]
# - Card number pattern → [CARD]
# - user_id → kept (not PII)
```

**Integration test needed:** Logger bridge with pattern scanning.

### Pattern 7: Exceptions with PII in Backtrace
```ruby
# Exception contains PII in message
begin
  process_payment(card: '4111-1111-1111-1111')
rescue => e
  # e.message might contain card number
  # e.backtrace might contain variable values
end

# Expected filtering:
# - Exception message scanned for patterns
# - Backtrace NOT scanned (too expensive)
```

**Integration test needed:** Error tracking with PII in exception messages.

---

## 3. Edge Cases Identified

### Edge Case 1: Very Deep Nesting (>10 levels)
```ruby
params = {
  level1: { level2: { level3: { ... level10: {
    password: 'secret'
  }}}}
}
```
**Risk:** Stack overflow, performance degradation  
**Test:** Verify filtering works at depth 15+, measure performance

### Edge Case 2: Very Large Payloads (>1MB)
```ruby
params = {
  data: 'A' * 2_000_000, # 2MB string
  password: 'secret'
}
```
**Risk:** Memory explosion, timeout  
**Test:** Verify filtering doesn't copy large strings unnecessarily

### Edge Case 3: Binary Data (File Uploads)
```ruby
params = {
  file: "\x89PNG\r\n\x1a\n..." # Binary PNG data
}
```
**Risk:** Pattern matching on binary corrupts data  
**Test:** Verify binary data passed through unchanged

### Edge Case 4: Non-UTF8 Encoding
```ruby
params = {
  text: "Привет мир".encode('Windows-1251'),
  password: 'secret'
}
```
**Risk:** Encoding::CompatibilityError  
**Test:** Verify handles encoding gracefully

### Edge Case 5: Malformed JSON
```ruby
# POST with Content-Type: application/json
body = '{"email": "user@example.com", invalid json'
```
**Risk:** JSON parse error before filtering  
**Test:** Verify filtering happens even with parse errors

### Edge Case 6: Concurrent Requests with Shared State
```ruby
# 100 simultaneous requests with different PII
threads = 100.times.map do |i|
  Thread.new { post :create, params: { password: "secret#{i}" } }
end
```
**Risk:** Thread-safety issues, cross-request data leakage  
**Test:** Verify no data leakage between concurrent requests

### Edge Case 7: Custom Rails Filter (Proc)
```ruby
# config/application.rb
config.filter_parameters << ->(key, value) {
  value.replace('[CUSTOM]') if key.to_s.include?('secret')
}
```
**Risk:** E11y might not support Proc filters  
**Test:** Verify Proc-based filters work or gracefully degrade

### Edge Case 8: Circular References
```ruby
hash = { a: 1 }
hash[:self] = hash # Circular reference
```
**Risk:** Infinite loop in recursion  
**Test:** Verify circular refs detected and handled

### Edge Case 9: Filter Bypass with Symbol vs String Keys
```ruby
params = {
  password: 'secret',      # String key
  :api_key => 'key123'     # Symbol key
}
```
**Risk:** Filtering misses symbol keys if looking for strings  
**Test:** Verify both string and symbol keys filtered

### Edge Case 10: Performance Regression on High-Traffic Endpoints
```ruby
# Endpoint with 1000 req/sec
# Each request has 50 fields in params
# 10% have PII that needs filtering
```
**Risk:** Filtering adds >5ms latency, degrading P95/P99  
**Test:** Benchmark real request throughput with/without filter

---

## 4. Dependencies & Test Infrastructure

### Required Dependencies

#### 4.1. Rails Test Environment
```ruby
# Already exists in spec/dummy/
- Dummy Rails app with controllers
- Routes configured
- Database (SQLite)
```

#### 4.2. Request Testing Tools
```ruby
# Gemfile (test group)
gem 'rack-test'           # ✅ For request simulation
gem 'rspec-rails'         # ✅ For request specs
gem 'climate_control'     # ✅ For ENV manipulation
```

#### 4.3. Sample PII Data
```ruby
# Need to create: spec/fixtures/pii_samples.yml
emails:
  - user@example.com
  - test+alias@gmail.com
  - Иван@example.ru # Cyrillic

credit_cards:
  - 4111-1111-1111-1111 # Visa test
  - 5500-0000-0000-0004 # Mastercard test

ssns:
  - 123-45-6789 # Valid format
  - 000-00-0000 # Invalid (not real)

phones:
  - +1-555-123-4567 # US
  - +44-20-7946-0958 # UK
  - +7-495-123-45-67 # Russia
```

#### 4.4. Performance Benchmarking
```ruby
# Gemfile (test group)
gem 'rspec-benchmark' # ✅ Already installed
gem 'benchmark-ips'   # For iterations/sec measurement
```

#### 4.5. Dummy Controllers for Integration
```ruby
# spec/dummy/app/controllers/
- users_controller.rb       # User registration with PII
- api/v1/orders_controller  # JSON API with nested PII
- files_controller.rb       # File uploads with PII metadata
```

#### 4.6. Helpers for Integration Tests
```ruby
# spec/support/integration/
- pii_helpers.rb          # Sample PII data generators
- request_helpers.rb      # HTTP request builders
- assertion_helpers.rb    # Custom matchers for PII filtering
```

---

## 5. Integration Test Scenarios (Detailed)

### Scenario 1: Password Filtering from Form Params
**Setup:**
- Dummy controller: `POST /users`
- Form params: `{ user: { email: '...', password: '...', name: '...' } }`

**Test:**
- Submit form with password
- Verify Rails processes request normally
- Verify E11y event has `password: '[FILTERED]'`
- Verify other fields unchanged

**Assertions:**
- `expect(event.payload[:password]).to eq('[FILTERED]')`
- `expect(event.payload[:email]).to match(/hashed_[a-f0-9]{16}/)`
- `expect(event.payload[:name]).to eq('John Doe')`

**Edge cases in this scenario:**
- Password in nested params
- Password as query string param
- Password in request body (JSON)

---

### Scenario 2: Credit Card in JSON API
**Setup:**
- API controller: `POST /api/v1/payments`
- JSON body: `{ payment: { card_number: '...', cvv: '...', amount: 100 } }`

**Test:**
- Send JSON with CC number
- Verify API response successful
- Verify E11y event has CC filtered
- Verify pattern matching works

**Assertions:**
- `expect(event.payload[:card_number]).to eq('[FILTERED]')`
- `expect(event.payload[:cvv]).to eq('[FILTERED]')`
- `expect(event.payload[:amount]).to eq(100)`

---

### Scenario 3: Authorization Header Filtering
**Setup:**
- API request with `Authorization: Bearer <token>`
- Rails action requires authentication

**Test:**
- Request with auth header
- Verify auth works (request succeeds)
- Verify E11y event has header filtered
- Verify other headers present

**Assertions:**
- `expect(response).to be_successful`
- `expect(event.payload[:headers]['Authorization']).to eq('[FILTERED]')`
- `expect(event.payload[:headers]['User-Agent']).to be_present`

---

### Scenario 4: Nested Params (5+ Levels Deep)
**Setup:**
- Form with deeply nested structure
- PII at different levels

**Test:**
- Submit nested params
- Verify all PII filtered regardless of depth
- Verify performance acceptable

**Assertions:**
- `expect(event.payload.dig(:user, :profile, :payment, :card)).to eq('[FILTERED]')`
- Filtering time < 5ms for 10-level nesting

---

### Scenario 5: File Upload with PII in Filename
**Setup:**
- Multipart upload: `resume_SSN_123-45-6789.pdf`
- File contains binary data

**Test:**
- Upload file with PII in filename
- Verify filename pattern filtered
- Verify binary data unchanged

**Assertions:**
- `expect(event.payload[:filename]).to eq('resume_SSN_[SSN].pdf')`
- File content checksum matches original

---

### Scenario 6: Custom PII Pattern (Company-Specific)
**Setup:**
- Configure custom pattern: `/EMP-\d{5}/` (employee IDs)
- Send request with employee ID

**Test:**
- Request contains `EMP-12345`
- Verify custom pattern filtered
- Verify standard patterns still work

**Assertions:**
- `expect(event.payload[:description]).not_to match(/EMP-\d{5}/)`
- `expect(event.payload[:description]).to include('[EMPLOYEE_ID]')`

---

### Scenario 7: Performance Benchmark
**Setup:**
- Endpoint with typical params (20 fields)
- 5 fields contain PII
- Measure with/without filter

**Test:**
- Send 1000 requests
- Measure P50, P95, P99 latency
- Calculate overhead

**Assertions:**
- Overhead < 5ms (P95)
- No memory leaks (stable RSS)
- Throughput degradation < 5%

---

## 6. Coverage Gaps Summary

### Unit Tests Cover:
✅ Middleware logic in isolation  
✅ Field strategies (mask, hash, partial, redact, allow)  
✅ Pattern matching (email, SSN, CC, IP)  
✅ Nested data recursion  
✅ Edge cases (nil, empty, unknown)

### Integration Tests Should Cover:
❌ **Real Rails request/response cycle**  
❌ **Middleware stack integration**  
❌ **Actual params/headers/cookies filtering**  
❌ **File uploads (multipart/form-data)**  
❌ **Performance under load**  
❌ **Configuration from Rails.application.config**  
❌ **Thread safety / concurrent requests**  
❌ **Error scenarios (malformed JSON, encoding)**  
❌ **Custom patterns in production context**  
❌ **Memory/performance profiling**

---

## 7. Test Data Requirements

### PII Samples (spec/fixtures/pii_samples.yml)
```yaml
emails:
  valid:
    - user@example.com
    - test+alias@gmail.com
    - user.name@company.co.uk
  international:
    - юзер@пример.рф # Cyrillic
    - 用户@例え.jp # Japanese
  edge_cases:
    - a@b.c # Shortest valid
    - very.long.email.address.with.many.dots@subdomain.example.com

credit_cards:
  visa: 4111-1111-1111-1111
  mastercard: 5500-0000-0000-0004
  amex: 3782-822463-10005
  invalid: 1234-5678-9012-3456 # Fails Luhn

ssns:
  valid_format: 123-45-6789
  no_dashes: 123456789
  invalid: 000-00-0000

api_keys:
  stripe: sk_live_4eC39HqLyjWDarjtT1zdp7dc
  aws: AKIAIOSFODNN7EXAMPLE
  custom: api_key_abc123xyz_secret
```

### Request Fixtures (spec/fixtures/requests/)
```
pii_requests/
├── user_registration.json      # Full user signup
├── payment_checkout.json        # CC processing
├── api_authenticated.json       # With auth headers
├── file_upload.multipart        # Binary upload
└── nested_deep.json             # 15-level nesting
```

---

## 8. Integration Test File Structure

```ruby
# spec/integration/pii_filtering_integration_spec.rb

RSpec.describe 'PII Filtering Integration', :integration do
  # Setup: Load dummy Rails app, configure routes
  
  describe 'Scenario 1: Form params filtering' do
    # Test implementation
  end
  
  describe 'Scenario 2: JSON API filtering' do
    # Test implementation
  end
  
  # ... 7 scenarios total
  
  describe 'Performance benchmarks' do
    # Benchmark tests
  end
end
```

---

## 9. Risks & Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| False positives (filter non-PII) | High | Low | Extensive testing with real data |
| Performance regression | High | Medium | Benchmark in CI, alert if >5ms |
| Memory leaks in production | Critical | Low | Profiling, load testing |
| Encoding errors crash requests | High | Low | Handle encoding gracefully |
| Thread-safety issues | Critical | Low | Concurrent request tests |
| Circular ref infinite loops | High | Very Low | Detect and break cycles |

---

## 10. Definition of Done (Phase 1)

This analysis document is complete when:

- ✅ Unit test coverage documented (what's tested, what's not)
- ✅ 5+ real-world usage patterns identified and documented
- ✅ 8+ edge cases identified with risk assessment
- ✅ Dependencies list complete (gems, fixtures, helpers)
- ✅ 7 integration scenarios detailed with setup/assertions
- ✅ Test data requirements specified
- ✅ Test file structure planned
- ✅ Risks documented with mitigations

**File:** `docs/integration-tests/UC-007-analysis.md` ✅ Created

**Next Phase:** Planning (design test implementation details)

---

## Summary

**Unit tests:** 31 examples covering middleware logic in isolation  
**Integration gaps:** Real Rails request/response, performance, threading  
**Scenarios:** 7 detailed scenarios + performance benchmarks  
**Edge cases:** 10 identified (deep nesting, large payloads, encoding, concurrency)  
**Dependencies:** Rails dummy app, fixtures, helpers (all available)  
**Ready for:** Phase 2 - Planning
