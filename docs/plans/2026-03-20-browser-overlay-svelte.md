# Browser Overlay (Svelte) — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the dev-only browser overlay with a Svelte-built, fullscreen-capable viewer aligned with the TUI navigation model (interactions → events → detail), fed by a versioned JSON API and shared Ruby data layer; collapsed FAB pulses briefly only when **new** error/fatal or warn events appear.

**Architecture:** Phase 1 ships a **Svelte + Vite** app against **mock JSON** matching the target `/_e11y/v1/` contract (three-level navigation, no keyboard shortcuts in MVP). Phase 2 **extracts** trace aggregation + grouping behind a neutral Ruby module (stop duplicating logic between TUI and HTTP), adds **v1 routes** while keeping legacy `events`/`recent` usable during transition. Phase 3 **builds** the bundle into the engine assets directory and switches the middleware loader to the new script. Pulse logic compares successive poll payloads by **event `id`** when present, else a stable composite key.

**Tech Stack:** Svelte 5 + Vite + TypeScript (recommended); Rails Engine (`gems/e11y-devtools`); existing `E11y::Adapters::DevLog::Query`; RSpec for Ruby.

**Out of MVP scope:** TUI-style keyboard shortcuts; deep-linking / URL sync for overlay state (optional later).

---

## Context (read first)

| Item | Location |
|------|----------|
| Injected loader | `gems/e11y-devtools/lib/e11y/devtools/overlay/middleware.rb` — loads `/_e11y/overlay.js` |
| Current overlay | `gems/e11y-devtools/lib/e11y/devtools/overlay/assets/overlay.js` |
| JSON routes | `gems/e11y-devtools/config/routes.rb`, `.../overlay/rails_controller.rb`, `.../overlay/controller.rb` |
| TUI navigation model | `gems/e11y-devtools/lib/e11y/devtools/tui/app.rb` (`:interactions` → `:events` → `:detail`; drill uses **first** `trace_id` of group) |
| Grouping | `gems/e11y-devtools/lib/e11y/devtools/tui/grouping.rb` (to be moved to neutral namespace) |
| Dev log query + `interactions` | `lib/e11y/adapters/dev_log/query.rb` — events have `"id"` for `find_event` |
| Host mount | Apps mount `E11y::Devtools::Overlay::Engine => "/_e11y"` (see `docs/architecture/ADR-010-developer-experience.md`) |

**Tests:** `bundle exec rspec gems/e11y-devtools/spec/e11y/devtools/overlay/` and `gems/e11y-devtools/spec/e11y/devtools/tui/` from repo root (adjust path if your setup uses `cd gems/e11y-devtools`).

---

## Target API contract (`/_e11y/v1/`)

Add namespaced routes (legacy routes stay until removed):

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/v1/interactions?source=web\|job\|all&limit=&window_ms=` | Newest-first interactions (same semantics as TUI `reload!` + filter) |
| GET | `/v1/traces/:trace_id/events` | Events for one trace (chronological, JSON array) |
| GET | `/v1/events/recent?limit=` | Flat recent list (badge + backward-compatible list; same as today’s use case) |

**Interaction JSON (example):**

```json
{
  "started_at": "2026-03-20T12:00:00.000Z",
  "trace_ids": ["abc", "def"],
  "has_error": true,
  "source": "web",
  "traces_count": 2
}
```

**Event JSON:** pass through stored event hashes from `Query` (ensure `id`, `trace_id`, `severity`, `event_name`, `timestamp` present for UI and pulse diff).

---

### Task 1: Design doc + mock fixtures

**Files:**

- Create: `gems/e11y-devtools/frontend/README.md` (how to run dev server)
- Create: `gems/e11y-devtools/frontend/public/mocks/v1/interactions.json`
- Create: `gems/e11y-devtools/frontend/public/mocks/v1/traces/sample-trace/events.json`
- Create: `gems/e11y-devtools/frontend/public/mocks/v1/events/recent.json`

**Step 1:** Add mock JSON files with 5–10 realistic events (mix severities including `warn`, `error`, `info`) and 2–3 grouped interactions.

**Step 2:** Document in `frontend/README.md`: `npm install`, `npm run dev`, open demo page.

**Step 3: Commit**

```bash
git add gems/e11y-devtools/frontend/public/mocks gems/e11y-devtools/frontend/README.md
git commit -m "docs(devtools): add overlay v1 API mocks for Svelte prototype"
```

---

### Task 2: Svelte + Vite scaffold (Phase 1 frontend)

**Files:**

- Create: `gems/e11y-devtools/frontend/package.json`
- Create: `gems/e11y-devtools/frontend/vite.config.ts`
- Create: `gems/e11y-devtools/frontend/tsconfig.json`
- Create: `gems/e11y-devtools/frontend/index.html` (fake host page + mount point)
- Create: `gems/e11y-devtools/frontend/src/main.ts`
- Create: `gems/e11y-devtools/frontend/src/App.svelte` (placeholder)

**Step 1:** Initialize Vite Svelte + TS (`npm create vite@latest` pattern): output **IIFE or single bundle** suitable for one `<script src>` (configure `build.lib` or `rollupOptions.output` as needed so final file is `overlay.js`).

**Step 2:** Run `cd gems/e11y-devtools/frontend && npm install && npm run dev` — confirm demo loads.

**Step 3:** Add `npm run build` producing `../lib/e11y/devtools/overlay/assets/overlay.js` (or `dist/overlay.js` + copy step documented until Task 7).

**Step 4: Commit**

```bash
git add gems/e11y-devtools/frontend
git commit -m "feat(devtools): scaffold Svelte+Vite overlay frontend"
```

---

### Task 3: Navigation shell + fullscreen animation (mocks only)

**Files:**

- Create: `gems/e11y-devtools/frontend/src/lib/router.ts` (typed view: `interactions | events | detail`, stack, `source` filter)
- Create/modify: `gems/e11y-devtools/frontend/src/components/Fab.svelte`
- Create/modify: `gems/e11y-devtools/frontend/src/components/FullscreenPanel.svelte`
- Modify: `gems/e11y-devtools/frontend/src/App.svelte`

**Step 1:** Implement FAB bottom-right; click toggles fullscreen overlay (`position: fixed; inset: 0`; inner content `transform-origin: bottom right` + open/close animation; respect `prefers-reduced-motion`).

**Step 2:** Header: title + close button + **source chips** `web | job | all` (click switches filter and refetches mocks).

**Step 3:** Wire three screens: Interactions list → click row → Events list (use **first** `trace_ids[0]` as in TUI) → click row → Detail (pretty JSON or key fields + “Copy JSON” button).

**Step 4:** Run `npm run dev`, click through mocks; fix layout/z-index issues.

**Step 5: Commit**

```bash
git commit -am "feat(devtools): overlay navigation shell and fullscreen animation (mocks)"
```

---

### Task 4: Pulse-on-new-error/warn (collapsed FAB only)

**Files:**

- Create: `gems/e11y-devtools/frontend/src/lib/eventIdentity.ts` — `eventKey(e): string` using `e.id` if truthy, else stable composite (`trace_id`, `timestamp`, `event_name`, index).
- Modify: `gems/e11y-devtools/frontend/src/App.svelte` (or store module)

**Step 1:** Keep `Set` of keys from **previous** `recent` poll (or last interactions aggregate — for MVP use **`/v1/events/recent`** payload only for pulse to match current overlay behavior).

**Step 2:** On each successful fetch, compute **newly seen** events whose `severity` is in `error|fatal` → add class `pulse-error` for ~3s; `warn` → `pulse-warn`. If both in same tick, prefer error styling.

**Step 3:** CSS: short keyframe (opacity/box-shadow); `@media (prefers-reduced-motion: reduce)` skip animation, optional single flash of border color.

**Step 4:** Badge text: show total count + error count + warn count (compact, e.g. `e11y 12 · 2⚠ · 1✕` — tune for readability).

**Step 5: Commit**

```bash
git commit -am "feat(devtools): pulse FAB on new error/warn events"
```

---

### Task 5: Extract neutral Ruby module for interactions pipeline

**Goal:** One place for “load events → build trace map → `Grouping.group`” used by TUI and HTTP.

**Files:**

- Create: `gems/e11y-devtools/lib/e11y/devtools/log_view.rb` (or `interaction_index.rb`) — class methods or instance taking `E11y::Adapters::DevLog::Query`
- Modify: `gems/e11y-devtools/lib/e11y/devtools/tui/grouping.rb` — **move** `Grouping` to `E11y::Devtools::Grouping` (new file `lib/e11y/devtools/grouping.rb`), leave thin `require` + alias in old path **or** update all requires in one commit
- Modify: `gems/e11y-devtools/lib/e11y/devtools/tui/app.rb` — call shared module
- Modify: `gems/e11y-devtools/lib/e11y/devtools/mcp/tools/interactions.rb` if it duplicates logic (align with `Query#interactions` or shared module)
- Test: `gems/e11y-devtools/spec/e11y/devtools/tui/grouping_spec.rb` — update path if needed

**Step 1:** Write failing spec for `E11y::Devtools::LogView.interactions(query, source:, limit:, window_ms:)` returning serializable hashes matching v1 JSON.

**Step 2:** Run `bundle exec rspec gems/e11y-devtools/spec/.../log_view_spec.rb` — expect RED.

**Step 3:** Implement by extracting from `Tui::App#reload!` / `build_traces` or delegating to `Query#interactions` if equivalent; ensure **source** filter semantics match TUI (`:all` → nil source filter).

**Step 4:** Refactor TUI to use shared module; run `bundle exec rspec gems/e11y-devtools/spec/e11y/devtools/tui/`.

**Step 5: Commit**

```bash
git commit -am "refactor(devtools): shared log view for interactions grouping"
```

---

### Task 6: HTTP v1 endpoints + controller tests

**Files:**

- Modify: `gems/e11y-devtools/config/routes.rb` — scope `v1` routes
- Modify: `gems/e11y-devtools/lib/e11y/devtools/overlay/rails_controller.rb` — actions `interactions`, `trace_events` (names TBD)
- Modify: `gems/e11y-devtools/lib/e11y/devtools/overlay/controller.rb` — delegate to `LogView` + `Query`
- Create: `gems/e11y-devtools/spec/e11y/devtools/overlay/v1_controller_spec.rb` (or extend `controller_spec.rb`)

**Step 1:** Request specs or controller specs: `GET /_e11y/v1/interactions` returns 200 JSON array; `GET /_e11y/v1/traces/:id/events` returns array; 404 for unknown trace returns `[]` or 404 — **pick one and document** (recommend `[]` for simpler UI).

**Step 2:** Run `bundle exec rspec gems/e11y-devtools/spec/e11y/devtools/overlay/`.

**Step 3: Commit**

```bash
git commit -am "feat(devtools): v1 JSON API for overlay interactions and trace events"
```

---

### Task 7: Production build pipeline + replace legacy overlay bundle

**Files:**

- Modify: `gems/e11y-devtools/frontend/vite.config.ts` — output filename `overlay.js` into `../lib/e11y/devtools/overlay/assets/`
- Delete or archive: inline-only `overlay.js` **after** Svelte bundle verified (git history retains old file)
- Modify: `gems/e11y-devtools/README.md` — document `npm run build` before release / CI note
- Optional: `Rakefile` in `gems/e11y-devtools` task `devtools:build`

**Step 1:** `npm run build` — confirm `assets/overlay.js` exists and defines the custom element or mounts into a host (match current behavior: auto-append `e11y-overlay` or equivalent).

**Step 2:** Boot dummy/integration app if available, load page, confirm script loads and API calls hit `/_e11y/v1/...`.

**Step 3:** Run overlay middleware specs: `bundle exec rspec gems/e11y-devtools/spec/e11y/devtools/overlay/middleware_spec.rb`.

**Step 4: Commit**

```bash
git commit -am "build(devtools): ship Svelte overlay bundle as overlay.js"
```

---

### Task 8: Wire Svelte app to real API + remove mock default

**Files:**

- Modify: `gems/e11y-devtools/frontend/src/...` — `API_BASE = '/_e11y'` + `/v1/...` paths; dev server proxy in `vite.config.ts` to Rails `localhost:3000` optional
- Modify: `gems/e11y-devtools/lib/e11y/devtools/overlay/assets/overlay.js` — **generated**; ensure CORS not required (same origin)

**Step 1:** Replace `fetch('/mocks/...')` with real endpoints; keep env flag `import.meta.env.DEV` for mocks if useful.

**Step 2:** Manual QA: trigger errors/warns in a Rails app, confirm pulse once per new event, fullscreen navigation matches TUI order.

**Step 3: Commit**

```bash
git commit -am "feat(devtools): connect overlay UI to v1 API"
```

---

### Task 9: Documentation + ADR touch-up

**Files:**

- Modify: `gems/e11y-devtools/README.md` — Browser Overlay section: Svelte build, v1 API, pulse behavior, no keyboard in MVP
- Modify: `docs/architecture/ADR-010-developer-experience.md` — mention v1 routes and bundle build if needed

**Step 1:** Proofread commands and paths.

**Step 2: Commit**

```bash
git commit -am "docs(devtools): document new overlay and v1 API"
```

---

## Verification checklist (before claiming done)

- [ ] `cd gems/e11y-devtools/frontend && npm run build` succeeds
- [ ] `bundle exec rspec gems/e11y-devtools/spec/e11y/devtools/overlay/` green
- [ ] `bundle exec rspec gems/e11y-devtools/spec/e11y/devtools/tui/` green
- [ ] Collapsed FAB: static styling for ongoing errors/warns; **pulse only** when new matching events appear since last poll
- [ ] Fullscreen open/close animation; reduced-motion respected
- [ ] Navigation: interactions → events (first trace_id) → detail; source filter chips work

---

## Plan complete

Saved to `docs/plans/2026-03-20-browser-overlay-svelte.md`.

**Execution options:**

1. **Subagent-driven (this session)** — fresh subagent per task, review between tasks (`superpowers:subagent-driven-development`).
2. **Parallel session** — new session with `superpowers:executing-plans` and checkpoints.

Which approach do you want?
