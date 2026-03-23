# e11y browser overlay — frontend (Svelte)

Prototype and production bundle for the dev-only overlay injected into Rails apps at `/_e11y/overlay.js`.

## API mocks (Phase 1)

Static JSON mirrors the target `/_e11y/v1/` contract:

| Path | File |
|------|------|
| `GET /v1/events/recent` | `public/mocks/v1/events/recent.json` |
| `GET /v1/interactions` | `public/mocks/v1/interactions.json` |
| `GET /v1/traces/:trace_id/events` | `public/mocks/v1/traces/<trace_id>/events.json` |

Trace ids are 32-char hex strings (like `DevLog` / OpenTelemetry). Files live under `public/mocks/v1/traces/<trace_id>/events.json`.

**Regenerate mocks** (deterministic `Random.new(42)`):

```bash
npm run generate-mocks
# or: E11Y_MOCK_TRACES=52 ruby scripts/generate_mocks.rb   # stress (~300+ events)
```

Default is `E11Y_MOCK_TRACES=24` (~150 events). `interactions.json` is rebuilt using the same 500ms window grouping as `E11y::Adapters::DevLog::Query`.

**Overlay UX (dev):** Problems tab includes a stacked **volume bar** over `recent` (UTC time scale, drag to **brush** a range and narrow the error list, double-click or **Clear range** to reset), search, and expandable payload rows. Trace event lists support **severity + text filters**, inline **payload expand**, **±2 context** highlight after opening an event and going back, and detail **Copy trace_id / request_id** plus collapsible payload / metadata / full JSON.

## Setup

```bash
cd gems/e11y-devtools/frontend
npm install
```

## Dev server

```bash
npm run dev
```

Open the URL Vite prints (default `http://localhost:5173`) to load `index.html` with a fake host page and the overlay.

## Production build

After the Svelte app is scaffolded (plan Task 2+):

```bash
npm run build
```

Output is written to `../lib/e11y/devtools/overlay/assets/overlay.js` for the Rails engine to serve.
