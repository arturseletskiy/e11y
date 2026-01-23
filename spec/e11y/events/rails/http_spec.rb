# frozen_string_literal: true

require "spec_helper"

RSpec.describe "E11y::Events::Rails::Http" do
  describe E11y::Events::Rails::Http::Request do
    it "inherits from E11y::Event::Base" do
      expect(described_class.superclass).to eq(E11y::Event::Base)
    end

    it "has schema defined" do
      expect(described_class).to respond_to(:schema)
    end
  end

  describe E11y::Events::Rails::Http::Redirect do
    it "inherits from E11y::Event::Base" do
      expect(described_class.superclass).to eq(E11y::Event::Base)
    end

    it "has schema defined" do
      expect(described_class).to respond_to(:schema)
    end
  end

  describe E11y::Events::Rails::Http::SendFile do
    it "inherits from E11y::Event::Base" do
      expect(described_class.superclass).to eq(E11y::Event::Base)
    end

    it "has schema defined" do
      expect(described_class).to respond_to(:schema)
    end
  end

  describe E11y::Events::Rails::Http::StartProcessing do
    it "inherits from E11y::Event::Base" do
      expect(described_class.superclass).to eq(E11y::Event::Base)
    end

    it "has schema defined" do
      expect(described_class).to respond_to(:schema)
    end
  end
end
