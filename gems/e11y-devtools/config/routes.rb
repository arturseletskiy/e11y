# frozen_string_literal: true

E11y::Devtools::Overlay::Engine.routes.draw do
  get    "overlay.js",    to: "e11y/devtools/overlay/rails#overlay_js"
  get    "events",        to: "e11y/devtools/overlay/rails#events"
  get    "events/recent", to: "e11y/devtools/overlay/rails#recent"
  delete "events",        to: "e11y/devtools/overlay/rails#clear"
  get    "stats",         to: "e11y/devtools/overlay/rails#stats"

  scope "v1" do
    get "interactions", to: "e11y/devtools/overlay/rails#v1_interactions"
    get "traces/:trace_id/events", to: "e11y/devtools/overlay/rails#v1_trace_events"
    get "events/recent", to: "e11y/devtools/overlay/rails#v1_events_recent"
  end
end
