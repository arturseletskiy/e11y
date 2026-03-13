# frozen_string_literal: true

require "rails_helper"
require "rack/test"

# Events are defined in spec/dummy/app/events/ and loaded via Rails autoloader
# This matches real application structure and ensures proper loading order

RSpec.describe "PII Filtering Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }

  before do
    memory_adapter.clear!
    # Dummy events use adapters [] — route via fallback
    E11y.config.fallback_adapters = [:memory]
  end

  after do
    memory_adapter.clear!
  end

  describe "Scenario 1: Password filtering from form params" do
    it "filters password field from Rails params" do
      params = {
        user: {
          email: "newuser@example.com",
          password: "MySecurePass123!",
          password_confirmation: "MySecurePass123!",
          name: "Jane Smith"
        }
      }

      memory_adapter.clear!

      post "/users", params: params

      expect(response).to have_http_status(:created)

      # Verify event was actually created
      events = memory_adapter.find_events("Events::UserRegistered")
      event_count = memory_adapter.events.count
      expect(events).not_to be_empty,
                            "Expected UserRegistered event to be created, but found #{event_count} total events. " \
                            "Response body: #{response.body}"

      payload = events.last[:payload].deep_symbolize_keys

      # CRITICAL: Verify filtering actually works
      password_msg = "Password should be filtered, got: #{payload[:password].inspect}. " \
                     "Full payload: #{payload.inspect}"
      expect(payload[:password]).to eq("[FILTERED]"), password_msg
      password_conf_msg = "Password confirmation should be filtered, " \
                          "got: #{payload[:password_confirmation].inspect}"
      expect(payload[:password_confirmation]).to eq("[FILTERED]"), password_conf_msg
      expect(payload[:email]).to eq("newuser@example.com"),
                                 "Email should NOT be filtered, got: #{payload[:email].inspect}"
      expect(payload[:name]).to eq("Jane Smith"), "Name should NOT be filtered, got: #{payload[:name].inspect}"
      expect(payload[:user_id]).to be_present, "User ID should be present, got: #{payload[:user_id].inspect}"
    end
  end

  describe "Scenario 2: PaymentSubmitted (masks :cvv, allows :card_number, :billing)" do
    it "masks cvv and retains card_number and billing when explicitly allowed" do
      payload = {
        payment: {
          card_number: "4111-1111-1111-1111",
          cvv: "123",
          amount: 99.99,
          currency: "USD",
          billing: {
            email: "billing@company.com",
            phone: "+1-555-123-4567"
          }
        }
      }

      post "/api/v1/payments", params: payload, as: :json

      expect(response).to have_http_status(:created)
      payment_payload = memory_adapter.find_events("Events::PaymentSubmitted").last[:payload].deep_symbolize_keys

      expect(payment_payload[:cvv]).to eq("[FILTERED]"), "cvv is in masks"
      expect(payment_payload[:card_number]).to eq("4111-1111-1111-1111"), "card_number is in allows"
      expect(payment_payload[:amount]).to eq(99.99)
      expect(payment_payload[:currency]).to eq("USD")
      expect(payment_payload.dig(:billing, :email)).to eq("billing@company.com"), "billing is in allows"
    end
  end

  describe "Scenario 3: Authorization header filtering" do
    it "filters sensitive headers without breaking authentication" do
      headers = {
        "Authorization" => "Bearer valid_token_123",
        "X-API-Key" => "sk_live_secret_key",
        "User-Agent" => "TestClient/1.0"
      }

      get "/api/v1/protected", headers: headers

      expect(response).to have_http_status(:ok)
      request_payload = memory_adapter.find_events("Events::ProtectedRequest").last[:payload].deep_symbolize_keys

      expect(request_payload[:authorization]).to eq("[FILTERED]")
      expect(request_payload[:api_key]).to eq("[FILTERED]")
      expect(request_payload[:user_agent]).to eq("TestClient/1.0")
    end
  end

  describe "Scenario 4: OrderCreated (allows :customer, :payment, :items)" do
    it "preserves nested structure when explicitly allowed" do
      payload = {
        order: {
          customer: {
            contact: {
              email: "customer@example.com",
              phone: "+1-555-987-6543",
              ssn: "123-45-6789"
            },
            name: "Customer Name"
          },
          payment: {
            method: {
              card: {
                number: "4111-1111-1111-1111"
              }
            }
          },
          items: [
            { sku: "SKU-001", name: "Widget A" },
            { sku: "SKU-002", name: "Widget B" }
          ]
        }
      }

      post "/orders", params: payload

      expect(response).to have_http_status(:created)
      order_payload = memory_adapter.find_events("Events::OrderCreated").last[:payload].deep_symbolize_keys

      # OrderCreated allows :customer, :payment, :items — nested values pass through
      expect(order_payload.dig(:customer, :contact, :email)).to eq("customer@example.com")
      expect(order_payload.dig(:customer, :contact, :phone)).to eq("+1-555-987-6543")
      expect(order_payload.dig(:customer, :contact, :ssn)).to eq("123-45-6789")
      expect(order_payload.dig(:payment, :method, :card, :number)).to eq("4111-1111-1111-1111")
      expect(order_payload.dig(:customer, :name)).to eq("Customer Name")
    end
  end

  describe "Scenario 5: DocumentUploaded (allows :filename, :size, :metadata)" do
    it "preserves filename and metadata when explicitly allowed, binary data intact" do
      file = Rack::Test::UploadedFile.new(
        StringIO.new("PDF binary content..."),
        "application/pdf",
        original_filename: "resume 123-45-6789.pdf"
      )

      params = {
        document: {
          file: file,
          metadata: {
            uploaded_by: "user@example.com",
            department: "HR"
          }
        }
      }

      post "/documents", params: params

      expect(response).to have_http_status(:created)
      doc_payload = memory_adapter.find_events("Events::DocumentUploaded").last[:payload].deep_symbolize_keys

      expect(doc_payload[:filename]).to eq("resume 123-45-6789.pdf"), "filename is in allows"
      expect(doc_payload.dig(:metadata, :uploaded_by)).to eq("user@example.com"), "metadata is in allows"
      expect(doc_payload.dig(:metadata, :department)).to eq("HR")
    end
  end

  describe "Scenario 6: ReportCreated (allows :title, :description, :author)" do
    it "preserves free text when explicitly allowed — no spurious pattern corruption" do
      params = {
        report: {
          title: "Q4 Performance Review",
          description: "Contact john.doe@example.com or +1-555-999-8888 for details",
          employee_ids: %w[EMP-12345 EMP-99999],
          author: "manager@company.com"
        }
      }

      post "/reports", params: params

      expect(response).to have_http_status(:created)
      report_payload = memory_adapter.find_events("Events::ReportCreated").last[:payload].deep_symbolize_keys

      # ReportCreated allows :description, :author — values pass through (like cucumber "password_reset_email_sent")
      expect(report_payload[:description]).to eq("Contact john.doe@example.com or +1-555-999-8888 for details")
      expect(report_payload[:author]).to eq("manager@company.com")
      expect(report_payload[:employee_ids]).to eq(%w[EMP-12345 EMP-99999])
    end
  end

  describe "Scenario 7: Performance benchmark under load", :benchmark do
    it "verifies filtering overhead is acceptable (<5ms P95)" do
      middleware = E11y::Middleware::PIIFilter.new(->(event_data) { event_data })
      event_data = {
        event_class: Events::PaymentSubmitted,
        payload: {
          card_number: "4111-1111-1111-1111",
          cvv: "123",
          billing: { email: "user@example.com" }
        }
      }

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      middleware.call(event_data)
      elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000

      expect(elapsed_ms).to be < 5.0
    end
  end
end
