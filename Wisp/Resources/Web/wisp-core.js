/*
 * Wisp — isolated-world core (runs at document start, main frame only).
 *
 * Responsibilities:
 *  - Own the <style> elements Wisp injects (theme tokens, theme CSS, user CSS).
 *  - Detect coarse page state (loading / qr / chats) with one debounced observer.
 *  - Run a one-shot selector health check so the app can report when WhatsApp's
 *    DOM has drifted away from the hooks a theme relies on.
 *  - Provide a tiny logging API for Wisp-authored scripts in this world.
 *
 * This world is isolated from WhatsApp's JavaScript: WhatsApp cannot see
 * `__wispCore`, and this file never reads page state beyond DOM structure.
 */
(() => {
  'use strict';
  if (globalThis.__wispCore) { return; }

  const post = (name, payload) => {
    try {
      const h = globalThis.webkit && globalThis.webkit.messageHandlers && globalThis.webkit.messageHandlers[name];
      if (h) { h.postMessage(payload); }
    } catch (_) {}
  };

  // ---------------------------------------------------------------- styles
  const STYLE_PREFIX = 'wisp-style-';
  const order = ['tokens', 'theme', 'density', 'user']; // cascade order, last wins

  function styleHost() { return document.head || document.documentElement; }

  function setStyle(id, css) {
    const host = styleHost();
    if (!host) { return false; }
    let el = document.getElementById(STYLE_PREFIX + id);
    if (!el) {
      el = document.createElement('style');
      el.id = STYLE_PREFIX + id;
      el.setAttribute('data-wisp', id);
      host.appendChild(el);
    }
    if (el.textContent !== css) { el.textContent = css; }
    ensureOrder();
    return true;
  }

  function removeStyle(id) {
    const el = document.getElementById(STYLE_PREFIX + id);
    if (el) { el.remove(); }
  }

  // Keep Wisp styles last in <head> (and in a stable relative order) so they win
  // against stylesheets WhatsApp appends later. Only touches the DOM when needed.
  function ensureOrder() {
    const host = styleHost();
    if (!host) { return; }
    const els = order.map((k) => document.getElementById(STYLE_PREFIX + k)).filter(Boolean);
    if (els.length === 0) { return; }
    const last = host.lastElementChild;
    const alreadyLast = els[els.length - 1] === last &&
      els.every((el, i) => i === 0 || els[i - 1].nextElementSibling === el);
    if (alreadyLast) { return; }
    for (const el of els) { host.appendChild(el); }
  }

  // Re-pin after WhatsApp injects its own <style>/<link> nodes. Head mutations are
  // rare after startup, so this observer is effectively idle.
  let headObserved = false;
  function observeHead() {
    if (headObserved || !document.head) { return; }
    headObserved = true;
    const mo = new MutationObserver(() => ensureOrder());
    mo.observe(document.head, { childList: true });
  }

  // ----------------------------------------------------------- page state
  let lastState = null;
  function computeState() {
    if (!document.body) { return 'loading'; }
    if (document.querySelector('#pane-side, [data-wisp-chat-list]')) { return 'chats'; }
    if (document.querySelector('canvas[aria-label], [data-ref], [data-link-code]')) { return 'qr'; }
    if (document.querySelector('#app [role="progressbar"], #app progress')) { return 'loading'; }
    if (document.querySelector('#app *')) { return 'unknown'; }
    return 'loading';
  }

  // ------------------------------------------------------------ scheme
  // WhatsApp switches dark mode with a hashed class on <html>, so we read a
  // token Wisp never overrides (--WDS-app-wash: warm-gray-200 light / -800 dark).
  let lastScheme = '';
  function detectScheme() {
    const root = document.documentElement;
    if (!root) { return ''; }
    const wash = getComputedStyle(root).getPropertyValue('--WDS-app-wash').trim();
    const m = wash.match(/#([0-9a-f]{6})/i);
    let scheme = '';
    if (m) {
      const v = parseInt(m[1], 16);
      const lum = ((v >> 16) & 255) * 0.299 + ((v >> 8) & 255) * 0.587 + (v & 255) * 0.114;
      scheme = lum < 128 ? 'dark' : 'light';
    } else if (document.body && document.body.classList.contains('dark')) { scheme = 'dark'; }
    if (scheme && scheme !== lastScheme) {
      lastScheme = scheme;
      root.setAttribute('data-wisp-scheme', scheme);
      post('wispState', { state: lastState || computeState(), scheme });
    }
    return scheme;
  }

  // ------------------------------------------------------------ bubbles
  // WhatsApp no longer marks .message-in/.message-out. The bubble is the parent
  // of the tail icon, and all bubbles share its (hashed) class list — learned at
  // runtime, never hard-coded. Direction comes from horizontal placement.
  let bubbleSelector = '';
  function markBubbles() {
    const main = document.querySelector('#main');
    if (!main) { return; }
    if (!bubbleSelector) {
      const tail = main.querySelector('span[data-icon="tail-in"], span[data-icon="tail-out"]');
      const bubble = tail && tail.parentElement;
      if (!bubble || !bubble.className || typeof bubble.className !== 'string') { return; }
      const cls = bubble.className.trim().split(/\s+/).filter(Boolean);
      if (cls.length === 0) { return; }
      bubbleSelector = '#main .' + cls.map((c) => CSS.escape(c)).join('.');
    }
    let nodes;
    try { nodes = main.querySelectorAll(bubbleSelector + ':not([data-wisp-bubble])'); } catch (_) { bubbleSelector = ''; return; }
    if (nodes.length === 0) { return; }
    const mid = main.getBoundingClientRect().left + main.getBoundingClientRect().width / 2;
    for (const el of nodes) {
      let dir = '';
      if (el.querySelector(':scope > span[data-icon="tail-out"]')) { dir = 'out'; }
      else if (el.querySelector(':scope > span[data-icon="tail-in"]')) { dir = 'in'; }
      else {
        const r = el.getBoundingClientRect();
        if (r.width === 0) { continue; }
        dir = (r.left + r.width / 2) > mid ? 'out' : 'in';
      }
      el.setAttribute('data-wisp-bubble', dir);
    }
  }

  let stateTimer = 0;
  function scheduleState() {
    if (stateTimer) { return; }
    stateTimer = setTimeout(() => {
      stateTimer = 0;
      const s = computeState();
      detectScheme();
      if (s === 'chats') { markBubbles(); }
      if (s !== lastState) {
        lastState = s;
        post('wispState', { state: s, scheme: lastScheme });
      }
      // Chat-panel hooks (#main, bubbles) only exist once a chat is open; run the
      // one-shot check the first time both the list and a conversation are present.
      if (s === 'chats' && !healthChecked && document.querySelector('#main')) {
        healthChecked = true;
        setTimeout(runHealthCheck, 1500);
      }
    }, 350);
  }

  let appObserved = false;
  function observeApp() {
    const root = document.documentElement;
    if (!root || appObserved) { return; }
    appObserved = true;
    const mo = new MutationObserver(scheduleState);
    mo.observe(root, { childList: true, subtree: true, attributes: true, attributeFilter: ['class'] });
    scheduleState();
  }

  // --------------------------------------------------------- health check
  // The native side passes the list of selectors each theme relies on.
  let healthSelectors = [];
  let healthChecked = false;
  function setHealthSelectors(list) { healthSelectors = Array.isArray(list) ? list.slice(0, 64) : []; }
  function runHealthCheck() {
    if (healthSelectors.length === 0) { return; }
    const missing = [];
    for (const sel of healthSelectors) {
      try { if (!document.querySelector(sel)) { missing.push(sel); } }
      catch (_) { missing.push(sel + ' (invalid)'); }
    }
    post('wispDiag', { kind: 'selectors', total: healthSelectors.length, missing });
  }

  // ------------------------------------------------------------ focus search
  function focusSearch() {
    const candidates = [
      '#side [contenteditable="true"][role="textbox"]',
      '#side div[contenteditable="true"]',
      '#side input[type="text"]',
      '[aria-label="Search input textbox"]',
      '[data-tab="3"]'
    ];
    for (const sel of candidates) {
      const el = document.querySelector(sel);
      if (el) { el.focus(); return true; }
    }
    const btn = document.querySelector('#side button[aria-label="Search"], #side [role="button"][aria-label*="Search"]');
    if (btn) { btn.click(); return true; }
    // Last resort: WhatsApp's own shortcut (⌘⌥/). React keyboard handlers accept synthetic events.
    const ev = new KeyboardEvent('keydown', { key: '/', code: 'Slash', metaKey: true, altKey: true, bubbles: true, cancelable: true });
    document.dispatchEvent(ev);
    return false;
  }

  // ---------------------------------------------------------------- logging
  const log = (level, args) => {
    const text = args.map((a) => {
      try { return typeof a === 'string' ? a : JSON.stringify(a); } catch (_) { return String(a); }
    }).join(' ').slice(0, 2000);
    post('wispLog', { level, source: 'core', message: text });
  };

  const api = Object.freeze({
    version: 1,
    setStyle, removeStyle, ensureOrder,
    state: () => lastState || computeState(),
    setHealthSelectors, runHealthCheck,
    focusSearch,
    log: (...a) => log('info', a), warn: (...a) => log('warning', a), error: (...a) => log('error', a)
  });
  Object.defineProperty(globalThis, '__wispCore', { value: api, enumerable: false, configurable: false, writable: false });

  // Boot. At document start <head> may not exist yet; wait for it cheaply.
  const boot = () => { observeHead(); observeApp(); ensureOrder(); };
  if (document.head && document.body) { boot(); }
  else { document.addEventListener('DOMContentLoaded', boot, { once: true }); observeApp(); }
})();
