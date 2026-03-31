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

    it "can track event with valid payload" do
      result = described_class.track(
        event_name: "process_action.action_controller",
        duration: 125.5,
        controller: "UsersController",
        action: "index",
        method: "GET",
        path: "/users",
        status: 200
      )
      expect(result).to be_a(Hash)
      expect(result[:payload][:controller]).to eq("UsersController")
    end
  end

  describe E11y::Events::Rails::Http::Redirect do
    it "inherits from E11y::Event::Base" do
      expect(described_class.superclass).to eq(E11y::Event::Base)
    end

    it "has schema defined" do
      expect(described_class).to respond_to(:schema)
    end

    it "can track event with valid payload" do
      result = described_class.track(
        event_name: "redirect_to.action_controller",
        duration: 1.2,
        location: "/dashboard",
        status: 302
      )
      expect(result).to be_a(Hash)
      expect(result[:payload][:location]).to eq("/dashboard")
    end
  end

  describe E11y::Events::Rails::Http::SendFile do
    it "inherits from E11y::Event::Base" do
      expect(described_class.superclass).to eq(E11y::Event::Base)
    end

    it "has schema defined" do
      expect(described_class).to respond_to(:schema)
    end

    it "can track event with valid payload" do
      result = described_class.track(
        event_name: "send_file.action_controller",
        duration: 45.3,
        path: "/tmp/report.pdf"
      )
      expect(result).to be_a(Hash)
      expect(result[:payload][:path]).to eq("/tmp/report.pdf")
    end
  end

  describe E11y::Events::Rails::Http::StartProcessing do
    it "inherits from E11y::Event::Base" do
      expect(described_class.superclass).to eq(E11y::Event::Base)
    end

    it "has schema defined" do
      expect(described_class).to respond_to(:schema)
    end

    it "can track event with valid payload" do
      result = described_class.track(
        event_name: "start_processing.action_controller",
        duration: 0.5,
        controller: "HomeController",
        action: "index",
        method: "GET",
        path: "/",
        format: "html"
      )
      expect(result).to be_a(Hash)
      expect(result[:payload][:controller]).to eq("HomeController")
    end

    it "accepts Symbol format as passed by Rails (regression)" do
      # Rails passes format as Symbol (request.format.ref => :html)
      # coerce_symbol_values in RailsInstrumentation converts it before schema validation
      result = described_class.track(
        event_name: "start_processing.action_controller",
        duration: 0.5,
        controller: "HomeController",
        action: "index",
        method: "GET",
        path: "/",
        format: :html
      )
      expect(result).to be_a(Hash)
    end
  end
end
