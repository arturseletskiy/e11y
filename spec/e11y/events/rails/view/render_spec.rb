# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Events::Rails::View::Render do
  it "inherits from E11y::Event::Base" do
    expect(described_class.superclass).to eq(E11y::Event::Base)
  end

  it "sets sample_rate to 0.1 (10%)" do
    expect(described_class.resolve_sample_rate).to eq(0.1)
  end

  it "has schema defined" do
    expect(described_class).to respond_to(:schema)
  end
end
