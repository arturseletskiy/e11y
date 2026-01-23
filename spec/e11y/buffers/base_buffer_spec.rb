# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Buffers::BaseBuffer do
  let(:buffer) { described_class.new }

  describe "#push" do
    it "raises NotImplementedError" do
      expect { buffer.push(double("event")) }.to raise_error(NotImplementedError, /push must be implemented/)
    end
  end

  describe "#flush" do
    it "raises NotImplementedError" do
      expect { buffer.flush }.to raise_error(NotImplementedError, /flush must be implemented/)
    end
  end

  describe "#size" do
    it "raises NotImplementedError" do
      expect { buffer.size }.to raise_error(NotImplementedError, /size must be implemented/)
    end
  end
end
