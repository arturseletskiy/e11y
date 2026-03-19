# frozen_string_literal: true

E11y::Devtools::Overlay::Engine.routes.draw do
  get    "events",        to: "e11y/devtools/overlay/rails#events"
  get    "events/recent", to: "e11y/devtools/overlay/rails#recent"
  delete "events",        to: "e11y/devtools/overlay/rails#clear"
  get    "stats",         to: "e11y/devtools/overlay/rails#stats"
end
