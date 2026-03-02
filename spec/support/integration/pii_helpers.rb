# frozen_string_literal: true

# Helper methods for PII integration testing
module PIIHelpers
  # Load PII samples from fixtures
  def pii_samples
    @pii_samples ||= YAML.load_file(
      File.expand_path("../../fixtures/pii_samples.yml", __dir__)
    )
  end

  # Generate random email
  def random_email
    "user#{rand(1000)}@example.com"
  end

  # Generate random credit card (Visa test)
  def random_cc
    "4111-1111-1111-#{rand(1111..9999)}"
  end

  # Generate random SSN
  def random_ssn
    "#{rand(100..999)}-#{rand(10..99)}-#{rand(1000..9999)}"
  end

  # Generate random phone
  def random_phone
    "+1-555-#{rand(100..999)}-#{rand(1000..9999)}"
  end

  # Get sample PII by type
  def sample_pii(type, variant: :valid)
    case type
    when :email
      pii_samples.dig("emails", variant.to_s)&.sample || random_email
    when :password
      pii_samples.dig("passwords", variant.to_s)&.sample || "password123"
    when :credit_card
      pii_samples.dig("credit_cards", variant.to_s)&.sample || random_cc
    when :ssn
      pii_samples.dig("ssns", variant.to_s)&.sample || random_ssn
    when :phone
      pii_samples.dig("phones", variant.to_s)&.sample || random_phone
    end
  end
end
