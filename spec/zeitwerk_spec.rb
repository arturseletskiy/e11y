# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Zeitwerk Autoloading" do
  describe "module structure" do
    it "loads E11y module" do
      expect(defined?(E11y)).to eq("constant")
      expect(E11y).to be_a(Module)
    end

    it "loads E11y::Event module" do
      expect(defined?(E11y::Event)).to eq("constant")
      expect(E11y::Event).to be_a(Module)
    end

    it "loads E11y::Event::Base class" do
      expect(defined?(E11y::Event::Base)).to eq("constant")
      expect(E11y::Event::Base).to be_a(Class)
    end

    it "loads E11y::Middleware module" do
      expect(defined?(E11y::Middleware)).to eq("constant")
      expect(E11y::Middleware).to be_a(Module)
    end

    it "loads E11y::Middleware::Base class" do
      expect(defined?(E11y::Middleware::Base)).to eq("constant")
      expect(E11y::Middleware::Base).to be_a(Class)
    end

    it "loads E11y::Adapters module" do
      expect(defined?(E11y::Adapters)).to eq("constant")
      expect(E11y::Adapters).to be_a(Module)
    end

    it "loads E11y::Adapters::Base class" do
      expect(defined?(E11y::Adapters::Base)).to eq("constant")
      expect(E11y::Adapters::Base).to be_a(Class)
    end

    it "loads E11y::Buffers module" do
      expect(defined?(E11y::Buffers)).to eq("constant")
      expect(E11y::Buffers).to be_a(Module)
    end

    it "loads E11y::Buffers::BaseBuffer class" do
      expect(defined?(E11y::Buffers::BaseBuffer)).to eq("constant")
      expect(E11y::Buffers::BaseBuffer).to be_a(Class)
    end

    it "loads E11y::Instruments module" do
      expect(defined?(E11y::Instruments)).to eq("constant")
      expect(E11y::Instruments).to be_a(Module)
    end

    it "loads E11y::Instruments::RailsInstrumentation class" do
      expect(defined?(E11y::Instruments::RailsInstrumentation)).to eq("constant")
      expect(E11y::Instruments::RailsInstrumentation).to be_a(Class)
    end
  end

  describe "Zeitwerk configuration" do
    it "uses Zeitwerk for autoloading" do
      # Zeitwerk loader is set up in lib/e11y.rb
      # We verify it works by checking that constants are accessible
      expect(defined?(E11y::Event::Base)).to eq("constant")
      expect(defined?(E11y::Middleware::Base)).to eq("constant")
    end

    it "follows naming conventions" do
      # Verify file paths match constant names (Zeitwerk requirement)
      expect { E11y::Event::Base }.not_to raise_error
      expect { E11y::Middleware::Base }.not_to raise_error
      expect { E11y::Adapters::Base }.not_to raise_error
      expect { E11y::Buffers::BaseBuffer }.not_to raise_error
      expect { E11y::Instruments::RailsInstrumentation }.not_to raise_error
    end
  end

  describe "require 'e11y'" do
    it "loads all core modules without explicit requires" do
      # Already loaded by spec_helper require 'e11y'
      # Verify we can access nested classes without manual requires
      expect { E11y::Event::Base.new }.to raise_error(NotImplementedError, /Phase 1/)
      expect { E11y::Middleware::Base.new.call(nil) }.to raise_error(NotImplementedError)
      expect { E11y::Adapters::Base.new.send_event(nil) }.to raise_error(NotImplementedError)
      expect { E11y::Buffers::BaseBuffer.new.push(nil) }.to raise_error(NotImplementedError)
    end
  end
end
