# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "e11y/adapters/dev_log/query"
require "e11y/devtools/tui/app"

RSpec.describe E11y::Devtools::Tui::App do
  subject(:app) { described_class.new(log_path: "/dev/null") }

  describe "#initialize" do
    it "starts in :interactions view" do
      expect(app.current_view).to eq(:interactions)
    end

    it "starts with source_filter :web" do
      expect(app.source_filter).to eq(:web)
    end
  end

  describe "#handle_key" do
    context "in :interactions view" do
      it "drills into :events on Enter" do
        query = instance_double(E11y::Adapters::DevLog::Query, events_by_trace: [])
        app.instance_variable_set(:@query, query)
        allow(app).to receive(:selected_interaction).and_return(
          double(trace_ids: ["t1"])
        )
        app.handle_key("enter")
        expect(app.current_view).to eq(:events)
      end

      it "toggles source to :job on 'j'" do
        app.handle_key("j")
        expect(app.source_filter).to eq(:job)
      end

      it "toggles source to :all on 'a'" do
        app.handle_key("a")
        expect(app.source_filter).to eq(:all)
      end

      it "toggles source back to :web on 'w'" do
        app.handle_key("a")
        app.handle_key("w")
        expect(app.source_filter).to eq(:web)
      end
    end

    context "in :events view" do
      before do
        app.instance_variable_set(:@current_view, :events)
        app.instance_variable_set(:@current_trace_id, "t1")
        app.instance_variable_set(:@events, [{ "id" => "e1", "event_name" => "x" }])
      end

      it "goes back to :interactions on Esc" do
        app.handle_key("esc")
        expect(app.current_view).to eq(:interactions)
      end

      it "drills into :detail on Enter" do
        app.handle_key("enter")
        expect(app.current_view).to eq(:detail)
      end
    end

    context "in :detail view" do
      before { app.instance_variable_set(:@current_view, :detail) }

      it "goes back to :events on Esc" do
        app.handle_key("esc")
        expect(app.current_view).to eq(:events)
      end

      it "goes back to :events on 'b'" do
        app.handle_key("b")
        expect(app.current_view).to eq(:events)
      end
    end
  end
end
