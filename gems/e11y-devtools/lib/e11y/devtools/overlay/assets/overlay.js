(function() {
  'use strict';

  const POLL_INTERVAL = 2000;
  const API_BASE = '/_e11y';

  class E11yOverlay extends HTMLElement {
    connectedCallback() {
      const shadow = this.attachShadow({ mode: 'open' });
      shadow.innerHTML = `
        <style>
          :host { position: fixed; bottom: 16px; right: 16px; z-index: 99999; font-family: monospace; }
          .badge { background: #1a1a2e; color: #e0e0e0; border-radius: 6px; padding: 6px 12px;
                   cursor: pointer; font-size: 12px; border: 1px solid #333; }
          .badge.has-error { border-color: #e53e3e; color: #fc8181; }
          .panel { display: none; position: fixed; right: 16px; bottom: 60px; width: 420px;
                   max-height: 70vh; background: #1a1a2e; border: 1px solid #444;
                   border-radius: 8px; overflow: hidden; flex-direction: column; }
          .panel.open { display: flex; }
          .panel-header { padding: 10px 14px; background: #16213e; border-bottom: 1px solid #333;
                          display: flex; justify-content: space-between; align-items: center;
                          font-size: 12px; color: #a0aec0; }
          .panel-title { color: #e0e0e0; font-weight: bold; }
          .close-btn { cursor: pointer; color: #718096; }
          .events { overflow-y: auto; flex: 1; padding: 8px; }
          .event-row { padding: 4px 8px; border-radius: 4px; margin-bottom: 2px;
                       font-size: 11px; cursor: pointer; display: flex; gap: 8px; }
          .event-row:hover { background: #2d3748; }
          .sev-error { color: #fc8181; }
          .sev-warn  { color: #f6ad55; }
          .sev-info  { color: #68d391; }
          .footer { padding: 8px 14px; border-top: 1px solid #333; display: flex;
                    gap: 12px; font-size: 11px; }
          .footer a { color: #63b3ed; cursor: pointer; text-decoration: none; }
          .footer a:hover { text-decoration: underline; }
        </style>
        <div class="badge" id="badge">e11y</div>
        <div class="panel" id="panel">
          <div class="panel-header">
            <span class="panel-title" id="panel-title">e11y devtools</span>
            <span class="close-btn" id="close-btn">x</span>
          </div>
          <div class="events" id="events-list"></div>
          <div class="footer">
            <a id="clear-btn">clear log</a>
            <a id="copy-trace-btn">copy trace_id</a>
          </div>
        </div>
      `;

      this._shadow    = shadow;
      this._panelOpen = false;
      this._traceId   = window.__E11Y_TRACE_ID__ || null;
      this._events    = [];

      shadow.getElementById('badge').addEventListener('click', () => this.togglePanel());
      shadow.getElementById('close-btn').addEventListener('click', () => this.closePanel());
      shadow.getElementById('clear-btn').addEventListener('click', () => this.clearLog());
      shadow.getElementById('copy-trace-btn').addEventListener('click', () => this.copyTrace());

      this.loadEvents();
      this._pollTimer = setInterval(() => this.loadEvents(), POLL_INTERVAL);
    }

    disconnectedCallback() { clearInterval(this._pollTimer); }

    togglePanel() { this._panelOpen ? this.closePanel() : this.openPanel(); }
    openPanel()   { this._panelOpen = true;  this._shadow.getElementById('panel').classList.add('open'); }
    closePanel()  { this._panelOpen = false; this._shadow.getElementById('panel').classList.remove('open'); }

    loadEvents() {
      const url = this._traceId
        ? `${API_BASE}/events?trace_id=${encodeURIComponent(this._traceId)}`
        : `${API_BASE}/events/recent?limit=20`;
      fetch(url)
        .then(r => r.json())
        .then(events => { this._events = events; this.renderBadge(); this.renderEvents(); })
        .catch(() => {});
    }

    renderBadge() {
      const badge    = this._shadow.getElementById('badge');
      const errCount = this._events.filter(e => e.severity === 'error' || e.severity === 'fatal').length;
      badge.textContent = errCount > 0
        ? `e11y  ${this._events.length} * ${errCount}`
        : `e11y  ${this._events.length}`;
      badge.className = errCount > 0 ? 'badge has-error' : 'badge';
    }

    renderEvents() {
      const list = this._shadow.getElementById('events-list');
      list.innerHTML = this._events.map(e => `
        <div class="event-row">
          <span class="sev-${e.severity}">${(e.severity || 'info').toUpperCase().slice(0,4)}</span>
          <span>${e.event_name}</span>
          <span style="color:#718096;margin-left:auto">${(e.metadata && e.metadata.duration_ms) || ''}ms</span>
        </div>`).join('');
    }

    clearLog() {
      fetch(`${API_BASE}/events`, { method: 'DELETE' })
        .then(() => { this._events = []; this.renderBadge(); this.renderEvents(); });
    }

    copyTrace() {
      if (this._traceId) { navigator.clipboard && navigator.clipboard.writeText(this._traceId); }
    }
  }

  customElements.define('e11y-overlay', E11yOverlay);

  if (!document.querySelector('e11y-overlay')) {
    document.body.appendChild(document.createElement('e11y-overlay'));
  }
})();
