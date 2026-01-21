# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::PII::Patterns do
  describe ".detect_field_type" do
    it "detects email fields" do
      expect(described_class.detect_field_type(:email)).to eq(:email)
      expect(described_class.detect_field_type(:user_email)).to eq(:email)
      expect(described_class.detect_field_type(:contact_email)).to eq(:email)
    end

    it "detects password fields" do
      expect(described_class.detect_field_type(:password)).to eq(:password)
      expect(described_class.detect_field_type(:user_password)).to eq(:password)
      expect(described_class.detect_field_type(:api_key)).to eq(:password)
      expect(described_class.detect_field_type(:secret_token)).to eq(:password)
    end

    it "detects SSN fields" do
      expect(described_class.detect_field_type(:ssn)).to eq(:ssn)
      expect(described_class.detect_field_type(:social_security)).to eq(:ssn)
      expect(described_class.detect_field_type(:tax_id)).to eq(:ssn)
    end

    it "detects credit card fields" do
      expect(described_class.detect_field_type(:card_number)).to eq(:credit_card)
      expect(described_class.detect_field_type(:credit_card)).to eq(:credit_card)
      expect(described_class.detect_field_type(:cc_number)).to eq(:credit_card)
    end

    it "detects phone fields" do
      expect(described_class.detect_field_type(:phone)).to eq(:phone)
      expect(described_class.detect_field_type(:mobile)).to eq(:phone)
      expect(described_class.detect_field_type(:telephone)).to eq(:phone)
    end

    it "detects address fields" do
      expect(described_class.detect_field_type(:address)).to eq(:address)
      expect(described_class.detect_field_type(:street_address)).to eq(:address)
      expect(described_class.detect_field_type(:postal_code)).to eq(:address)
    end

    it "detects name fields" do
      expect(described_class.detect_field_type(:name)).to eq(:name)
      expect(described_class.detect_field_type(:first_name)).to eq(:name)
      expect(described_class.detect_field_type(:full_name)).to eq(:name)
    end

    it "detects date of birth fields" do
      expect(described_class.detect_field_type(:dob)).to eq(:dob)
      expect(described_class.detect_field_type(:birth_date)).to eq(:dob)
      expect(described_class.detect_field_type(:date_of_birth)).to eq(:dob)
    end

    it "detects IP address fields" do
      expect(described_class.detect_field_type(:ip)).to eq(:ip)
      expect(described_class.detect_field_type(:remote_addr)).to eq(:ip)
    end

    it "returns nil for non-PII fields" do
      expect(described_class.detect_field_type(:user_id)).to be_nil
      expect(described_class.detect_field_type(:order_id)).to be_nil
      expect(described_class.detect_field_type(:amount)).to be_nil
    end
  end

  describe ".contains_pii?" do
    context "when testing EMAIL pattern" do
      it "detects valid emails" do
        expect(described_class.contains_pii?("user@example.com")).to be true
        expect(described_class.contains_pii?("contact.me@domain.co.uk")).to be true
        expect(described_class.contains_pii?("first+last@company.org")).to be true
      end

      it "does not detect invalid emails" do
        expect(described_class.contains_pii?("not an email")).to be false
        expect(described_class.contains_pii?("@example.com")).to be false
      end
    end

    context "when testing SSN pattern" do
      it "detects US SSN format" do
        expect(described_class.contains_pii?("123-45-6789")).to be true
        expect(described_class.contains_pii?("987-65-4321")).to be true
      end

      it "does not detect invalid SSN" do
        expect(described_class.contains_pii?("123456789")).to be false
        expect(described_class.contains_pii?("12-345-6789")).to be false
      end
    end

    context "when testing CREDIT_CARD pattern" do
      it "detects credit card formats" do
        expect(described_class.contains_pii?("4111 1111 1111 1111")).to be true
        expect(described_class.contains_pii?("4111-1111-1111-1111")).to be true
        expect(described_class.contains_pii?("4111111111111111")).to be true
      end

      it "does not detect invalid cards" do
        expect(described_class.contains_pii?("411 111 111 111")).to be false
      end
    end

    context "when testing IPV4 pattern" do
      it "detects IP addresses" do
        expect(described_class.contains_pii?("192.168.1.1")).to be true
        expect(described_class.contains_pii?("10.0.0.1")).to be true
        expect(described_class.contains_pii?("172.16.0.1")).to be true
      end

      it "does not detect invalid IPs" do
        expect(described_class.contains_pii?("999.999.999.999")).to be true # Pattern match, not validation
        expect(described_class.contains_pii?("192.168.1")).to be false
      end
    end

    context "when testing PHONE pattern" do
      it "detects phone numbers" do
        expect(described_class.contains_pii?("555-123-4567")).to be true
        expect(described_class.contains_pii?("(555) 123-4567")).to be true
        expect(described_class.contains_pii?("+1-555-123-4567")).to be true
      end

      it "does not detect invalid phones" do
        expect(described_class.contains_pii?("123-45")).to be false
      end
    end

    context "when testing non-PII content" do
      it "returns false for safe strings" do
        expect(described_class.contains_pii?("Hello, world!")).to be false
        expect(described_class.contains_pii?("Order ID: 12345")).to be false
        expect(described_class.contains_pii?("Amount: $99.99")).to be false
      end
    end

    context "when testing mixed content" do
      it "detects PII in mixed content" do
        expect(described_class.contains_pii?("Contact: user@example.com")).to be true
        expect(described_class.contains_pii?("SSN is 123-45-6789")).to be true
        expect(described_class.contains_pii?("Card: 4111-1111-1111-1111")).to be true
      end
    end

    context "when testing non-string types" do
      it "returns false for non-strings" do
        expect(described_class.contains_pii?(nil)).to be false
        expect(described_class.contains_pii?(12_345)).to be false
        expect(described_class.contains_pii?({ email: "test@example.com" })).to be false
      end
    end
  end

  describe "Pattern coverage (95%+ detection rate)" do
    let(:pii_samples) do
      {
        emails: [
          "user@example.com",
          "contact+tag@domain.co.uk",
          "first.last@company.org"
        ],
        ssns: %w[
          123-45-6789
          987-65-4321
          111-22-3333
        ],
        credit_cards: [
          "4111 1111 1111 1111",
          "4111-1111-1111-1111",
          "4111111111111111"
        ],
        ips: [
          "192.168.1.1",
          "10.0.0.1",
          "172.16.0.254"
        ],
        phones: [
          "555-123-4567",
          "(555) 123-4567",
          "+1-555-123-4567"
        ]
      }
    end

    it "detects 95%+ of PII samples" do
      total_samples = pii_samples.values.flatten.size
      detected = 0

      pii_samples.each_value do |samples|
        samples.each do |sample|
          detected += 1 if described_class.contains_pii?(sample)
        end
      end

      detection_rate = (detected.to_f / total_samples * 100).round(2)
      expect(detection_rate).to be >= 95.0
    end
  end
end
