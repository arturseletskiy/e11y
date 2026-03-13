# frozen_string_literal: true

require "spec_helper"
require "e11y/reliability/dlq/base"

RSpec.describe E11y::Reliability::DLQ::Base do
  subject(:dlq) { described_class.new }

  it "raises NotImplementedError for #save" do
    expect { dlq.save({}) }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for #list" do
    expect { dlq.list }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for #stats" do
    expect { dlq.stats }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for #replay" do
    expect { dlq.replay("id") }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for #delete" do
    expect { dlq.delete("id") }.to raise_error(NotImplementedError)
  end

  describe "#replay_batch" do
    it "delegates to replay for each id" do
      subclass = Class.new(described_class) do
        def replay(id) # rubocop:todo Naming/PredicateMethod
          id == "good"
        end
      end
      result = subclass.new.replay_batch(%w[good bad])
      expect(result).to eq({ success_count: 1, failure_count: 1 })
    end
  end
end
