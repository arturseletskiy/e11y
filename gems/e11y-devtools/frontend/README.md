# e11y browser overlay — frontend (Svelte)

Prototype and production bundle for the dev-only overlay injected into Rails apps at `/_e11y/overlay.js`.

## API mocks (Phase 1)

Static JSON mirrors the target `/_e11y/v1/` contract:

| Path | File |
|------|------|
| `GET /v1/events/recent` | `public/mocks/v1/events/recent.json` |
| `GET /v1/interactions` | `public/mocks/v1/interactions.json` |
| `GET /v1/traces/:trace_id/events` | `public/mocks/v1/traces/<trace_id>/events.json` |

Trace ids in mocks: `tr-aaa` (matches first interaction row), `sample-trace` (standalone demo file from the plan).

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
