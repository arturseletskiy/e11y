# UC-007 PII Filtering - Test Plan

**Task:** FEAT-5383  
**Date:** 2026-01-26  
**Phase:** Planning (Phase 2 of 4)

---

## Test Scenarios (7 scenarios)

### Scenario 1: Password Filtering from Form Params

**Goal:** Verify Rails form params filtered in real request cycle

**Setup:**
```ruby
# spec/dummy/app/controllers/users_controller.rb
class UsersController < ApplicationController
  def create
    # Simulates user registration
    render json: { status: 'created', user_id: SecureRandom.uuid }
  end
end

# spec/dummy/config/routes.rb
post '/users', to: 'users#create'

# spec/dummy/config/application.rb
config.filter_parameters += [:password, :password_confirmation]
```

**Test Data:**
```ruby
params = {
  user: {
    email: 'newuser@example.com',
    password: 'MySecurePass123!',
    password_confirmation: 'MySecurePass123!',
    name: 'Jane Smith'
  }
}
```

**Actions:**
1. POST `/users` with params
2. Wait for E11y event to be tracked
3. Inspect event payload

**Assertions:**
```ruby
expect(response).to have_http_status(:success)
expect(e11y_events.last.payload[:password]).to eq('[FILTERED]')
expect(e11y_events.last.payload[:password_confirmation]).to eq('[FILTERED]')
expect(e11y_events.last.payload[:email]).to eq('newuser@example.com') # Not in filter_parameters
expect(e11y_events.last.payload[:name]).to eq('Jane Smith')
```

**Acceptance Criteria:**
- ✅ Request succeeds (200/201 status)
- ✅ Password fields filtered
- ✅ Non-sensitive fields unchanged
- ✅ Event tracked with filtered payload
- ✅ Response not affected by filtering

**Complexity:** Low (2/10)  
**Time Estimate:** 1h

---

### Scenario 2: Credit Card in JSON API

**Goal:** Verify JSON request body filtered for CC patterns

**Setup:**
```ruby
# spec/dummy/app/controllers/api/v1/payments_controller.rb
class Api::V1::PaymentsController < ApplicationController
  def create
    render json: { payment_id: SecureRandom.uuid, status: 'processing' }
  end
end

# Routes
namespace :api do
  namespace :v1 do
    post '/payments', to: 'payments#create'
  end
end

# Config: Add CC pattern filter
E11y.configure do |config|
  config.pii_filter.filter_pattern(
    /\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/,
    replacement: '[CARD]'
  )
end
```

**Test Data:**
```ruby
json_body = {
  payment: {
    card_number: '4111-1111-1111-1111',
    cvv: '123',
    amount: 99.99,
    currency: 'USD',
    billing: {
      email: 'billing@company.com',
      address: '123 Main St, City, State 12345'
    }
  }
}.to_json
```

**Actions:**
1. POST `/api/v1/payments` with JSON body
2. Headers: `Content-Type: application/json`
3. Capture E11y HTTP request event

**Assertions:**
```ruby
expect(response).to have_http_status(:success)
expect(e11y_events.last.payload[:card_number]).to eq('[CARD]')
expect(e11y_events.last.payload[:cvv]).to eq('[FILTERED]') # Rails filter
expect(e11y_events.last.payload[:amount]).to eq(99.99)
expect(e11y_events.last.payload.dig(:billing, :email)).to match(/\[FILTERED\]|\[EMAIL\]/)
```

**Acceptance Criteria:**
- ✅ JSON parsed correctly
- ✅ CC pattern detected and filtered
- ✅ Nested PII filtered
- ✅ Non-sensitive data preserved
- ✅ Response unaffected

**Complexity:** Medium (4/10)  
**Time Estimate:** 1.5h

---

### Scenario 3: Authorization Header Filtering

**Goal:** Verify request headers filtered without breaking auth

**Setup:**
```ruby
# spec/dummy/app/controllers/api/v1/protected_controller.rb
class Api::V1::ProtectedController < ApplicationController
  before_action :authenticate!
  
  def index
    render json: { data: 'protected resource' }
  end
  
  private
  
  def authenticate!
    token = request.headers['Authorization']&.remove('Bearer ')
    head :unauthorized unless token == 'valid_token_123'
  end
end

# Config
config.filter_parameters += [:authorization, :api_key]
```

**Test Data:**
```ruby
headers = {
  'Authorization' => 'Bearer valid_token_123',
  'X-API-Key' => 'sk_live_secret_key',
  'User-Agent' => 'TestClient/1.0'
}
```

**Actions:**
1. GET `/api/v1/protected` with headers
2. Verify auth succeeds
3. Check E11y event headers

**Assertions:**
```ruby
expect(response).to have_http_status(:ok)
expect(e11y_events.last.payload[:headers]['Authorization']).to eq('[FILTERED]')
expect(e11y_events.last.payload[:headers]['X-API-Key']).to eq('[FILTERED]')
expect(e11y_events.last.payload[:headers]['User-Agent']).to eq('TestClient/1.0')
```

**Acceptance Criteria:**
- ✅ Auth works (request succeeds)
- ✅ Sensitive headers filtered in events
- ✅ Non-sensitive headers preserved
- ✅ Original request headers unchanged (filtering non-destructive)

**Complexity:** Low (3/10)  
**Time Estimate:** 1h

---

### Scenario 4: Nested Params (Deep Nesting)

**Goal:** Verify filtering works at arbitrary depth

**Setup:**
```ruby
# Controller accepts deeply nested params
class OrdersController < ApplicationController
  def create
    # Process nested order data
    render json: { order_id: SecureRandom.uuid }
  end
end

# No special config - Rails filter_parameters applies recursively
```

**Test Data:**
```ruby
params = {
  order: {
    customer: {
      contact: {
        details: {
          credentials: {
            password: 'secret',
            api_key: 'key123'
          },
          payment: {
            method: {
              card: {
                number: '4111-1111-1111-1111'
              }
            }
          }
        },
        name: 'Customer Name' # 5 levels deep
      }
    },
    items: [...]
  }
}
```

**Actions:**
1. POST with 7-level nested params
2. Verify all PII filtered at all depths

**Assertions:**
```ruby
expect(e11y_events.last.payload.dig(:order, :customer, :contact, :details, :credentials, :password)).to eq('[FILTERED]')
expect(e11y_events.last.payload.dig(:order, :customer, :contact, :details, :payment, :method, :card, :number)).to match(/\[FILTERED\]|\[CARD\]/)
expect(e11y_events.last.payload.dig(:order, :customer, :contact, :name)).to eq('Customer Name')
```

**Performance:**
```ruby
# Measure filtering time for deep nesting
expect {
  post :create, params: params
}.to perform_under(5).ms # Max 5ms overhead
```

**Acceptance Criteria:**
- ✅ All PII filtered regardless of nesting depth (up to 15 levels)
- ✅ Non-PII data preserved
- ✅ Performance < 5ms for 10-level nesting
- ✅ No stack overflow errors

**Complexity:** Medium (5/10)  
**Time Estimate:** 1.5h

---

### Scenario 5: File Upload with PII in Metadata

**Goal:** Verify multipart/form-data handled correctly

**Setup:**
```ruby
# spec/dummy/app/controllers/documents_controller.rb
class DocumentsController < ApplicationController
  def create
    file = params[:document][:file]
    render json: { 
      filename: file.original_filename,
      size: file.size,
      uploaded: true
    }
  end
end

# Pattern filter for SSN in filenames
E11y.configure do |config|
  config.pii_filter.filter_pattern(/\d{3}-\d{2}-\d{4}/, replacement: '[SSN]')
end
```

**Test Data:**
```ruby
# Create temp file
file = Rack::Test::UploadedFile.new(
  StringIO.new('PDF binary content...'),
  'application/pdf',
  original_filename: 'resume_john_doe_SSN_123-45-6789.pdf'
)

params = {
  document: {
    file: file,
    metadata: {
      uploaded_by: 'user@example.com',
      department: 'HR'
    }
  }
}
```

**Actions:**
1. POST `/documents` with multipart upload
2. Verify file processed
3. Check E11y event metadata

**Assertions:**
```ruby
expect(response).to have_http_status(:created)
expect(e11y_events.last.payload[:filename]).to eq('resume_john_doe_SSN_[SSN].pdf')
expect(e11y_events.last.payload.dig(:metadata, :uploaded_by)).to match(/\[FILTERED\]|\[EMAIL\]/)
expect(e11y_events.last.payload.dig(:metadata, :department)).to eq('HR')
# Binary file content not included in event (too large)
expect(e11y_events.last.payload).not_to have_key(:file_content)
```

**Acceptance Criteria:**
- ✅ File upload succeeds
- ✅ Filename patterns filtered
- ✅ Metadata PII filtered
- ✅ Binary content excluded from events
- ✅ No data corruption

**Complexity:** Medium (6/10)  
**Time Estimate:** 2h

---

### Scenario 6: Custom Pattern (Company-Specific PII)

**Goal:** Verify custom regex patterns work in production context

**Setup:**
```ruby
# spec/dummy/config/initializers/e11y.rb
E11y.configure do |config|
  config.pii_filter do
    # Custom pattern: Employee IDs (EMP-12345)
    filter_pattern(/EMP-\d{5}/, replacement: '[EMPLOYEE_ID]')
    
    # Custom pattern: Internal account codes (ACC-ABC-123)
    filter_pattern(/ACC-[A-Z]{3}-\d{3}/, replacement: '[ACCOUNT_CODE]')
  end
end

# Controller
class ReportsController < ApplicationController
  def create
    render json: { report_id: SecureRandom.uuid }
  end
end
```

**Test Data:**
```ruby
params = {
  report: {
    title: 'Q4 Performance Review',
    description: 'Report for EMP-12345 regarding account ACC-ABC-789',
    author: 'manager@company.com',
    employee_ids: ['EMP-11111', 'EMP-22222', 'EMP-33333']
  }
}
```

**Actions:**
1. POST `/reports` with custom PII patterns
2. Verify patterns detected in string content
3. Verify patterns detected in arrays

**Assertions:**
```ruby
expect(e11y_events.last.payload[:description]).to eq('Report for [EMPLOYEE_ID] regarding account [ACCOUNT_CODE]')
expect(e11y_events.last.payload[:employee_ids]).to all(eq('[EMPLOYEE_ID]'))
expect(e11y_events.last.payload[:title]).to eq('Q4 Performance Review')
```

**Acceptance Criteria:**
- ✅ Custom patterns registered correctly
- ✅ Patterns detected in strings
- ✅ Patterns detected in arrays
- ✅ Standard patterns (email, CC) still work
- ✅ No false positives

**Complexity:** Medium (4/10)  
**Time Estimate:** 1h

---

### Scenario 7: Performance Benchmark (Real Request Load)

**Goal:** Verify no performance regression under realistic load

**Setup:**
```ruby
# High-throughput endpoint
class HealthController < ApplicationController
  def index
    render json: { status: 'ok', timestamp: Time.current }
  end
end

# Event with no PII (Tier 1 - should be fast)
class Events::HealthCheck < E11y::Event::Base
  contains_pii false
  schema { required(:status).filled(:string) }
end

# Event with PII (Tier 3 - slower but acceptable)
class Events::UserAction < E11y::Event::Base
  contains_pii true
  schema do
    required(:user_id).filled(:string)
    required(:email).filled(:string)
  end
  pii_filtering { hashes :email; allows :user_id }
end
```

**Test Data:**
```ruby
# Scenario A: No PII (baseline)
1000.times { get '/health' }

# Scenario B: With PII filtering
1000.times do
  Events::UserAction.track(
    user_id: "u-#{rand(1000)}",
    email: "user#{rand(1000)}@example.com"
  )
end
```

**Actions:**
1. Benchmark requests without PII filtering (Tier 1)
2. Benchmark requests with PII filtering (Tier 3)
3. Calculate overhead
4. Profile memory allocation

**Assertions:**
```ruby
# Performance
tier1_p95 = benchmark_tier1.percentile(95)
tier3_p95 = benchmark_tier3.percentile(95)
overhead = tier3_p95 - tier1_p95

expect(overhead).to be < 5.0 # Max 5ms overhead

# Throughput
expect(tier1_rps).to be > 100 # Requests/sec
expect(tier3_rps).to be > 95  # <5% degradation

# Memory
expect(memory_increase).to be < 10 # MB for 1000 events
```

**Acceptance Criteria:**
- ✅ Tier 1 (no PII): <1ms per request
- ✅ Tier 3 (with PII): <5ms overhead
- ✅ Throughput degradation <5%
- ✅ No memory leaks
- ✅ Stable RSS under load

**Complexity:** High (7/10)  
**Time Estimate:** 3h

---

## Test Data Fixtures

### File: spec/fixtures/pii_samples.yml

```yaml
emails:
  valid:
    - user@example.com
    - test+alias@gmail.com
    - user.name@company.co.uk
    - admin_123@test-domain.org
  international:
    - юзер@пример.рф # Cyrillic
    - 用户@例え.jp # Japanese (if supported)
  edge_cases:
    - a@b.co # Shortest
    - very.long.local.part.with.many.dots@subdomain.example.com
    - user@localhost # No TLD
    
passwords:
  weak:
    - password123
    - qwerty
  strong:
    - MyS3cur3P@ssw0rd!
    - "aB3#fG7*kL9&mN2"
  edge:
    - "" # Empty
    - "p" # Single char
    - "лошадь-батарея-скоба" # Cyrillic passphrase

credit_cards:
  visa:
    - "4111111111111111" # No dashes
    - "4111-1111-1111-1111" # With dashes
    - "4111 1111 1111 1111" # With spaces
  mastercard:
    - "5500000000000004"
  amex:
    - "378282246310005"
  invalid:
    - "1234567890123456" # Fails Luhn
    - "4111-1111-1111-111X" # Non-digit

ssns:
  valid_format:
    - "123-45-6789"
    - "987-65-4321"
  no_dashes:
    - "123456789"
  invalid:
    - "000-00-0000" # All zeros
    - "666-45-6789" # Invalid area number
    
phones:
  us:
    - "+1-555-123-4567"
    - "(555) 123-4567"
    - "555.123.4567"
  international:
    - "+44-20-7946-0958" # UK
    - "+7-495-123-45-67" # Russia
    - "+81-3-1234-5678" # Japan

api_keys:
  stripe:
    - "sk_live_4eC39HqLyjWDarjtT1zdp7dc"
    - "pk_test_TYooMQauvdEDq54NiTphI7jx"
  aws:
    - "AKIAIOSFODNN7EXAMPLE"
  custom:
    - "api_key_abc123xyz_secret"

employee_ids:
  - "EMP-12345"
  - "EMP-99999"
  - "EMP-00001"
```

### File: spec/support/integration/pii_helpers.rb

```ruby
module PIIHelpers
  # Generate random PII for testing
  def random_email
    "user#{rand(1000)}@example.com"
  end
  
  def random_cc
    # Visa test card with valid Luhn
    "4111-1111-1111-#{rand(1111..9999)}"
  end
  
  def random_ssn
    "#{rand(100..999)}-#{rand(10..99)}-#{rand(1000..9999)}"
  end
  
  # Sample PII datasets
  def pii_samples
    @pii_samples ||= YAML.load_file(
      Rails.root.join('../../fixtures/pii_samples.yml')
    )
  end
  
  # Create request with PII
  def request_with_pii(type:, pii_fields: {})
    case type
    when :form
      { user: pii_fields.merge(name: 'Test User') }
    when :json
      { payment: pii_fields }.to_json
    when :multipart
      # Multipart builder
    end
  end
end

RSpec.configure do |config|
  config.include PIIHelpers, type: :integration
end
```

### File: spec/support/integration/e11y_event_helpers.rb

```ruby
module E11yEventHelpers
  # Get all tracked events in this test
  def e11y_events
    E11y::Adapters::InMemory.events
  end
  
  # Get last event of specific type
  def last_event(event_class)
    e11y_events.reverse.find { |e| e.is_a?(event_class) }
  end
  
  # Clear events between tests
  def clear_e11y_events
    E11y::Adapters::InMemory.clear!
  end
  
  # Wait for event to be tracked (async)
  def wait_for_event(event_class, timeout: 1)
    Timeout.timeout(timeout) do
      sleep 0.01 until last_event(event_class)
    end
  end
end

RSpec.configure do |config|
  config.include E11yEventHelpers, type: :integration
  config.before(:each, type: :integration) { clear_e11y_events }
end
```

---

## Assertions & Matchers

### Custom RSpec Matchers

```ruby
# spec/support/matchers/pii_matchers.rb

RSpec::Matchers.define :be_filtered do
  match do |actual|
    actual == '[FILTERED]' ||
    actual =~ /^hashed_[a-f0-9]{16}$/ ||
    actual =~ /\[\w+\]/ # [CARD], [EMAIL], etc.
  end
  
  failure_message do |actual|
    "expected #{actual} to be filtered, but it wasn't"
  end
end

RSpec::Matchers.define :contain_no_pii do
  match do |hash|
    hash.deep_stringify_keys.values.none? do |value|
      case value
      when String
        value =~ /@/ || # Email
        value =~ /\d{3}-\d{2}-\d{4}/ || # SSN
        value =~ /\d{4}.*\d{4}.*\d{4}.*\d{4}/ # CC
      when Hash
        !RSpec::Matchers::BuiltIn::ContainNoPII.new.matches?(value)
      else
        false
      end
    end
  end
end

RSpec::Matchers.define :preserve_structure do |original|
  match do |filtered|
    same_keys?(original, filtered)
  end
  
  def same_keys?(hash1, hash2)
    hash1.keys.sort == hash2.keys.sort &&
    hash1.all? do |key, value|
      if value.is_a?(Hash)
        same_keys?(value, hash2[key])
      else
        hash2.key?(key)
      end
    end
  end
end
```

### Standard Assertions

```ruby
# Filtering assertions
expect(payload[:password]).to be_filtered
expect(payload).to contain_no_pii
expect(filtered).to preserve_structure(original)

# Performance assertions
expect { action }.to perform_under(5).ms
expect { action }.to perform_at_least(100).ips # iterations/sec

# Integration assertions
expect(response).to have_http_status(:ok)
expect(e11y_events).to have_received_event(Events::HttpRequest)
expect(last_event).to have_payload_matching(expected_payload)
```

---

## Test Execution Plan

### Order of Implementation
1. **Scenario 1** (Password form) - Foundation, simplest
2. **Scenario 3** (Headers) - Builds on #1
3. **Scenario 2** (JSON API) - More complex
4. **Scenario 4** (Nested) - Tests recursion
5. **Scenario 6** (Custom patterns) - Tests extensibility
6. **Scenario 5** (File uploads) - Most complex setup
7. **Scenario 7** (Performance) - Validates all scenarios

### Dependencies Between Scenarios
```
Scenario 1 (Foundation)
├── Scenario 3 (Headers) - Uses same test helpers
└── Scenario 2 (JSON) - Uses same controller pattern
    ├── Scenario 4 (Nested) - Extends JSON scenario
    └── Scenario 6 (Custom) - Extends JSON scenario
        └── Scenario 5 (Uploads) - Most complex
            └── Scenario 7 (Perf) - Validates all
```

### Time Estimates
- Scenario 1: 1h
- Scenario 2: 1.5h
- Scenario 3: 1h
- Scenario 4: 1.5h
- Scenario 5: 2h
- Scenario 6: 1h
- Scenario 7: 3h

**Total Implementation: 11h**  
**Buffer for debugging: 2h**  
**Phase 4 Total: 13h**

---

## Complexity Validation

| Phase | Original Estimate | Validated | Reason |
|-------|------------------|-----------|---------|
| Analysis (Phase 1) | 3.5h | ✅ 3h actual | Straightforward, good docs |
| Planning (Phase 2) | 2.5h | ✅ 2h actual | Clear from analysis |
| Skeleton (Phase 3) | 1.5h | TBD | Simple file creation |
| Implementation (Phase 4) | 8h | ⚠️ 13h | More complex than expected |

**Revised Total: 19.5h** (was 15h) - complexity 7/10 accurate

---

## Definition of Done (Phase 2)

- ✅ 7 scenarios detailed with setup/actions/assertions
- ✅ Test data fixtures specified (`pii_samples.yml`)
- ✅ Helper modules designed (`pii_helpers.rb`, `e11y_event_helpers.rb`)
- ✅ Custom matchers designed (`pii_matchers.rb`)
- ✅ Execution plan with dependencies mapped
- ✅ Complexity estimates validated and updated
- ✅ Time estimates refined based on analysis

**File:** `docs/integration-tests/UC-007-test-plan.md` ✅ Created

**Next Phase:** Skeleton (create pending specs with detailed comments)
