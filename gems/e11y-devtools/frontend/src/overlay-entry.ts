import { mount } from "svelte"
import App from "./App.svelte"
import "./overlay.css"

const ROOT_ID = "e11y-devtools-root"

function boot(): void {
  if (typeof document === "undefined") return
  if (document.getElementById(ROOT_ID)) return

  const target = document.createElement("div")
  target.id = ROOT_ID
  document.body.appendChild(target)

  mount(App, { target })
}

if (typeof document !== "undefined") {
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () => boot())
  } else {
    boot()
  }
}
