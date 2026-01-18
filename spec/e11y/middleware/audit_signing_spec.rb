# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe E11y::Middleware::AuditSigning do
  let(:app) { ->(event_data) { event_data } }
  let(:middleware) { described_class.new(app) }

  describe "Audit Event Signing" do
    context "with audit event" do
      let(:audit_event_class) do
        Class.new(E11y::Event::Base) do
          def self.name
            "Events::UserDeleted"
          end

          audit_event true

          schema do
            required(:user_id).filled(:integer)
            required(:deleted_by).filled(:integer)
            required(:ip_address).filled(:string)
          end
        end
      end

      it "signs audit event with HMAC-SHA256" do
        event_data = {
          event_class: audit_event_class,
          event_name: "Events::UserDeleted",
          payload: {
            user_id: 123,
            deleted_by: 456,
            ip_address: "192.168.1.1"
          },
          timestamp: Time.now.utc.iso8601(6),
          version: 1
        }

        result = middleware.call(event_data)

        expect(result[:audit_signature]).not_to be_nil
        expect(result[:audit_signature]).to match(/^[a-f0-9]{64}$/) # SHA256 hex = 64 chars
        expect(result[:audit_signed_at]).not_to be_nil
        expect(result[:audit_canonical]).not_to be_nil
      end

      it "creates deterministic signatures (same data = same signature)" do
        event_data = {
          event_class: audit_event_class,
          event_name: "Events::UserDeleted",
          payload: {
            user_id: 123,
            deleted_by: 456,
            ip_address: "192.168.1.1"
          },
          timestamp: "2026-01-18T00:00:00.000000Z",
          version: 1
        }

        result1 = middleware.call(event_data.dup)
        result2 = middleware.call(event_data.dup)

        expect(result1[:audit_signature]).to eq(result2[:audit_signature])
      end

      it "signs BEFORE PII filtering (original IP address)" do
        event_data = {
          event_class: audit_event_class,
          event_name: "Events::UserDeleted",
          payload: {
            user_id: 123,
            deleted_by: 456,
            ip_address: "192.168.1.1" # Original IP
          },
          timestamp: Time.now.utc.iso8601(6),
          version: 1
        }

        result = middleware.call(event_data)

        # Canonical representation should contain original IP
        canonical = JSON.parse(result[:audit_canonical])
        expect(canonical["payload"]["ip_address"]).to eq("192.168.1.1")
      end

      it "verifies signature successfully" do
        event_data = {
          event_class: audit_event_class,
          event_name: "Events::UserDeleted",
          payload: {
            user_id: 123,
            deleted_by: 456,
            ip_address: "192.168.1.1"
          },
          timestamp: Time.now.utc.iso8601(6),
          version: 1
        }

        result = middleware.call(event_data)

        expect(described_class.verify_signature(result)).to be true
      end

      it "detects tampered data" do
        event_data = {
          event_class: audit_event_class,
          event_name: "Events::UserDeleted",
          payload: {
            user_id: 123,
            deleted_by: 456,
            ip_address: "192.168.1.1"
          },
          timestamp: Time.now.utc.iso8601(6),
          version: 1
        }

        result = middleware.call(event_data)

        # Tamper with canonical (which is what signature is based on)
        tampered_canonical = result[:audit_canonical].gsub('"user_id":123', '"user_id":999')
        result[:audit_canonical] = tampered_canonical

        expect(described_class.verify_signature(result)).to be false
      end
    end

    context "with non-audit event" do
      let(:regular_event_class) do
        Class.new(E11y::Event::Base) do
          def self.name
            "Events::PageView"
          end

          # No audit_event flag

          schema do
            required(:user_id).filled(:integer)
            required(:page_url).filled(:string)
          end
        end
      end

      it "does not sign regular events" do
        event_data = {
          event_class: regular_event_class,
          event_name: "Events::PageView",
          payload: {
            user_id: 123,
            page_url: "/dashboard"
          },
          timestamp: Time.now.utc.iso8601(6),
          version: 1
        }

        result = middleware.call(event_data)

        expect(result[:audit_signature]).to be_nil
        expect(result[:audit_signed_at]).to be_nil
        expect(result[:audit_canonical]).to be_nil
      end
    end

    context "with skip_signing flag" do
      let(:audit_event_class) do
        Class.new(E11y::Event::Base) do
          def self.name
            "Events::UserDeleted"
          end

          audit_event true

          schema do
            required(:user_id).filled(:integer)
            required(:deleted_by).filled(:integer)
            required(:ip_address).filled(:string)
          end
        end
      end

      let(:audit_event_without_signing) do
        Class.new(E11y::Event::Base) do
          def self.name
            "Events::AuditLogViewed"
          end

          audit_event true
          signing enabled: false # ← Согласованный DSL с конфигом

          schema do
            required(:log_id).filled(:integer)
            required(:viewed_by).filled(:integer)
          end
        end
      end

      it "does not sign audit event when signing disabled" do
        event_data = {
          event_class: audit_event_without_signing,
          event_name: "Events::AuditLogViewed",
          payload: {
            log_id: 123,
            viewed_by: 456
          },
          timestamp: Time.now.utc.iso8601(6),
          version: 1
        }

        result = middleware.call(event_data)

        expect(result[:audit_signature]).to be_nil
        expect(result[:audit_signed_at]).to be_nil
        expect(result[:audit_canonical]).to be_nil
      end

      it "signs audit event when signing explicitly enabled" do
        audit_event_with_signing = Class.new(E11y::Event::Base) do
          def self.name
            "Events::CriticalAction"
          end

          audit_event true
          signing enabled: true # ← Согласованный DSL: явно включаем

          schema do
            required(:action).filled(:string)
          end
        end

        event_data = {
          event_class: audit_event_with_signing,
          event_name: "Events::CriticalAction",
          payload: {
            action: "delete_user"
          },
          timestamp: Time.now.utc.iso8601(6),
          version: 1
        }

        result = middleware.call(event_data)

        expect(result[:audit_signature]).not_to be_nil
        expect(result[:audit_signed_at]).not_to be_nil
        expect(result[:audit_canonical]).not_to be_nil
      end

      it "signs audit event by default (no signing declaration)" do
        # This is the existing audit_event_class from above
        event_data = {
          event_class: audit_event_class,
          event_name: "Events::UserDeleted",
          payload: {
            user_id: 123,
            deleted_by: 456,
            ip_address: "192.168.1.1"
          },
          timestamp: Time.now.utc.iso8601(6),
          version: 1
        }

        result = middleware.call(event_data)

        expect(result[:audit_signature]).not_to be_nil
      end
    end
  end

  describe "Canonical Representation" do
    let(:audit_event_class) do
      Class.new(E11y::Event::Base) do
        def self.name
          "Events::TestEvent"
        end

        audit_event true

        schema do
          required(:data).filled(:hash)
        end
      end
    end

    it "sorts hash keys for deterministic JSON" do
      # Same data, different key order
      event_data1 = {
        event_class: audit_event_class,
        event_name: "Events::TestEvent",
        payload: { z: 1, a: 2, m: 3 },
        timestamp: "2026-01-18T00:00:00.000000Z",
        version: 1
      }

      event_data2 = {
        event_class: audit_event_class,
        event_name: "Events::TestEvent",
        payload: { a: 2, m: 3, z: 1 },
        timestamp: "2026-01-18T00:00:00.000000Z",
        version: 1
      }

      result1 = middleware.call(event_data1)
      result2 = middleware.call(event_data2)

      # Same signature despite different key order
      expect(result1[:audit_signature]).to eq(result2[:audit_signature])
    end

    it "handles nested hashes" do
      event_data = {
        event_class: audit_event_class,
        event_name: "Events::TestEvent",
        payload: {
          nested: {
            z: 1,
            a: { y: 2, x: 3 }
          }
        },
        timestamp: "2026-01-18T00:00:00.000000Z",
        version: 1
      }

      result = middleware.call(event_data)

      canonical = JSON.parse(result[:audit_canonical])
      # Keys should be sorted at all levels
      expect(canonical["payload"]["nested"].keys).to eq(%w[a z])
    end
  end
end
