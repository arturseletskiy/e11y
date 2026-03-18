# frozen_string_literal: true

# rubocop:disable RSpec/SpecFilePathFormat -- rspec_matchers matches RSpecMatchers constant
RSpec.describe E11y::Testing::RSpecMatchers do
  let(:event_class) do
    Class.new(E11y::Event::Base) do
      contains_pii false
      event_name "test.matcher"
      schema { required(:id).filled(:integer) }
      adapters :test
    end
  end

  # Helper: write event directly to test adapter (avoids pipeline routing in unit tests)
  def write_event(overrides = {})
    base = {
      event_name: "test.matcher",
      event_class: event_class,
      payload: { id: 1 },
      severity: :info
    }
    E11y.test_adapter.write(base.merge(overrides))
  end

  before { E11y.test_adapter&.clear! }

  describe "have_tracked_event" do
    it "matches when event was tracked" do
      expect { write_event }.to have_tracked_event(event_class)
    end

    it "matches with String pattern" do
      expect { write_event }.to have_tracked_event("test.matcher")
    end

    it "matches with Regexp pattern" do
      expect { write_event }.to have_tracked_event(/test\.matcher/)
    end

    it "fails when no event was tracked" do
      expect do
        expect { nil }.to have_tracked_event(event_class)
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError, /expected to have tracked/)
    end

    it "supports .once" do
      expect { write_event }.to have_tracked_event(event_class).once
    end

    it "fails .once when tracked twice" do
      expect do
        expect do
          write_event
          write_event
        end.to have_tracked_event(event_class).once
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError, /exactly 1 times/)
    end

    it "supports .with(payload)" do
      expect { write_event(payload: { id: 42 }) }.to have_tracked_event(event_class).with(id: 42)
    end

    it "supports .with_severity" do
      expect { write_event(severity: :warn) }.to have_tracked_event(event_class).with_severity(:warn)
    end

    it "supports .exactly(n)" do
      expect { 3.times { write_event } }.to have_tracked_event(event_class).exactly(3)
    end

    it "supports .at_least(n)" do
      expect { 5.times { write_event } }.to have_tracked_event(event_class).at_least(3)
    end
  end

  describe "track_event (alias)" do
    it "works as alias for have_tracked_event" do
      expect { write_event }.to track_event(event_class)
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
