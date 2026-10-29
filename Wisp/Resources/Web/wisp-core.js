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
    let scheme = '';
    // 0. The link/QR landing page is always rendered light, whatever <body> says.
    if ((lastState || computeState()) === 'qr') { scheme = 'light'; }
    // 1. WhatsApp still toggles the legacy `dark` class on <body>.
    else if (document.body && document.body.classList.contains('dark')) { scheme = 'dark'; }
    else if (document.body && document.body.classList.contains('light')) { scheme = 'light'; }
    // 2. Otherwise read a token Wisp never overrides, as computed on <body>
    //    (warm-gray-200 light / warm-gray-800 dark).
    if (!scheme) {
      const wash = getComputedStyle(document.body || root).getPropertyValue('--WDS-app-wash').trim();
      const m = wash.match(/#([0-9a-f]{6})/i);
      if (m) {
        const v = parseInt(m[1], 16);
        const lum = ((v >> 16) & 255) * 0.299 + ((v >> 8) & 255) * 0.587 + (v & 255) * 0.114;
        scheme = lum < 128 ? 'dark' : 'light';
      } else if (window.matchMedia) { scheme = matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'; }
    }
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
  // Every message has at least one of these leaves. The bubble is the ancestor
  // just below the full-width row: climb while the parent is narrower than ~90%
  // of the conversation. Direction: receipts (only on outgoing) or placement.
  const LEAF_SELECTOR = '.copyable-text, [data-testid="msg-meta"], [data-icon^="msg-"], span[data-icon^="tail-"], img[src^="blob:"], video, audio, [role="img"]';
  function bubbleFor(leaf, mainWidth) {
    let el = leaf;
    for (let i = 0; i < 12 && el && el.parentElement; i++) {
      const parent = el.parentElement;
      if (parent.id === 'main' || parent.tagName === 'BODY') { return null; }
      if (parent.getBoundingClientRect().width >= mainWidth * 0.9 && el.getBoundingClientRect().width < mainWidth * 0.9) { return el; }
      el = parent;
    }
    return null;
  }
  function markBubbles() {
    const main = document.querySelector('#main');
    if (!main) { return; }
    const rect = main.getBoundingClientRect();
    if (rect.width === 0) { return; }
    const mid = rect.left + rect.width / 2;
    const leaves = main.querySelectorAll(LEAF_SELECTOR);
    for (const leaf of leaves) {
      if (leaf.closest('[data-wisp-bubble]') || leaf.closest('header, footer')) { continue; }
      const b = bubbleFor(leaf, rect.width);
      if (!b || b.hasAttribute('data-wisp-bubble')) { continue; }
      let dir = '';
      if (b.querySelector('span[data-icon="tail-out"], [data-icon="msg-dblcheck"], [data-icon="msg-check"], [data-icon="msg-time"]')) { dir = 'out'; }
      else if (b.querySelector('span[data-icon="tail-in"]')) { dir = 'in'; }
      else { const r = b.getBoundingClientRect(); dir = (r.left + r.width / 2) > mid ? 'out' : 'in'; }
      // Stickers and bare media have no bubble surface; themes must not paint one.
      // The surface may sit on the wrapper or on its first inner element.
      const isClear = (el) => { const bg = el && getComputedStyle(el).backgroundColor; return !bg || bg === 'transparent' || bg === 'rgba(0, 0, 0, 0)'; };
      if (isClear(b) && isClear(b.querySelector(':scope > div'))) { b.setAttribute('data-wisp-plain', '1'); }
      b.setAttribute('data-wisp-bubble', dir);
    }
  }
  const bubbleSelector = '(leaf-climb)';

  // ------------------------------------------------------------ copy button
  // WhatsApp mounts a hover tray (an absolutely positioned flex row inside the
  // message container) holding the React button. A "Copy message" disc is
  // cloned from that button's tray item, so it inherits WhatsApp's look and
  // every theme's hover-button rules, and sits on the outer side of the tray.
  // Clicks never reach WhatsApp: the clone has no React fiber and stops
  // propagation. Text is read from the message's own .copyable-text block.
  const COPY_SVG = '<svg viewBox="0 0 24 24" height="16" preserveAspectRatio="xMidYMid meet" fill="currentColor"><title>wisp-copy</title><path fill="currentColor" d="M16 1H4a2 2 0 0 0-2 2v14h2V3h12V1zm3 4H8a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2zm0 16H8V7h11v14z"/></svg>';
  const DONE_SVG = '<svg viewBox="0 0 24 24" height="16" preserveAspectRatio="xMidYMid meet" fill="currentColor"><title>wisp-copied</title><path fill="currentColor" d="M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg>';
  const COPY_LABEL = 'Copy message';

  function copyButtonEnabled() { return document.documentElement.getAttribute('data-wisp-copy-button') !== '0'; }

  // Plain text of one message: text nodes plus emoji <img alt>, <br> as a
  // newline. Controls inside the text ("Read more") and the meta row are skipped.
  function messageText(container) {
    const parts = [];
    for (const block of container.querySelectorAll('.copyable-text[data-pre-plain-text]')) {
      let roots = [...block.querySelectorAll('.selectable-text')].filter((s) => !(s.parentElement && s.parentElement.closest('.selectable-text')));
      if (roots.length === 0) { roots = [block]; }
      for (const root of roots) {
        let s = '';
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
          acceptNode(n) {
            if (n.nodeType === 3) { return NodeFilter.FILTER_ACCEPT; }
            if (n.matches('[role="button"], [data-testid="msg-meta"], [aria-hidden="true"]:not(img)')) { return NodeFilter.FILTER_REJECT; }
            return NodeFilter.FILTER_ACCEPT;
          }
        });
        let n;
        while ((n = walker.nextNode())) {
          if (n.nodeType === 3) { s += n.data; }
          else if (n.tagName === 'IMG') { s += n.getAttribute('alt') || ''; }
          else if (n.tagName === 'BR') { s += '\n'; }
        }
        if (s.trim()) { parts.push(s); }
      }
    }
    return parts.join('\n').replace(/ /g, ' ').replace(/[ \t]+\n/g, '\n').trim();
  }

  function writeClipboard(text) {
    const h = globalThis.webkit && globalThis.webkit.messageHandlers && globalThis.webkit.messageHandlers.wispClipboard;
    if (h) { try { h.postMessage({ text: text.slice(0, 200000) }); return true; } catch (_) {} }
    if (navigator.clipboard && navigator.clipboard.writeText) { navigator.clipboard.writeText(text).catch(() => {}); return true; }
    return false;
  }

  function swallow(ev) { ev.stopPropagation(); }
  function onCopyActivate(ev) {
    if (ev.type === 'keydown' && ev.key !== 'Enter' && ev.key !== ' ') { return; }
    ev.preventDefault(); ev.stopPropagation();
    const btn = ev.currentTarget;
    const container = btn.closest('[data-testid="msg-container"], [data-wisp-bubble]');
    const text = container ? messageText(container) : '';
    if (!text || !writeClipboard(text)) { return; }
    const svg = btn.querySelector('svg');
    if (svg) { svg.outerHTML = DONE_SVG; }
    btn.setAttribute('aria-label', 'Copied');
    btn.setAttribute('data-wisp-copied', '1');
    setTimeout(() => {
      if (!btn.isConnected) { return; }
      const done = btn.querySelector('svg');
      if (done) { done.outerHTML = COPY_SVG; }
      btn.setAttribute('aria-label', COPY_LABEL);
      btn.removeAttribute('data-wisp-copied');
    }, 1200);
  }

  function addCopyButtons() {
    if (!copyButtonEnabled()) { return; }
    for (const react of document.querySelectorAll('#main [data-testid="reaction-entry-point"]')) {
      // react → unstyled wrapper → tray item (spacing) → tray (absolute flex row) → message container
      const item = react.parentElement && react.parentElement.parentElement;
      const tray = item && item.parentElement;
      const container = tray && tray.parentElement;
      if (!container || tray.querySelector('[data-wisp-copy]')) { continue; }
      if (!container.querySelector('.copyable-text[data-pre-plain-text]')) { continue; }
      if (getComputedStyle(tray).position !== 'absolute') { continue; } // structure drifted; do nothing
      const clone = item.cloneNode(true);
      const btn = clone.querySelector('[data-testid="reaction-entry-point"]');
      if (!btn) { continue; }
      btn.setAttribute('data-testid', 'wisp-copy-button');
      btn.setAttribute('data-wisp-copy', '1');
      btn.setAttribute('aria-label', COPY_LABEL);
      btn.setAttribute('title', COPY_LABEL);
      const svg = btn.querySelector('svg');
      if (svg) { svg.outerHTML = COPY_SVG; } else { btn.innerHTML = '<span aria-hidden="true">' + COPY_SVG + '</span>'; }
      clone.setAttribute('data-wisp-copy-item', '1');
      btn.addEventListener('click', onCopyActivate);
      btn.addEventListener('keydown', onCopyActivate);
      for (const t of ['mousedown', 'mouseup', 'pointerdown', 'pointerup', 'dblclick', 'contextmenu']) { btn.addEventListener(t, swallow); }
      btn.addEventListener('mousedown', (ev) => ev.preventDefault()); // keep focus in the composer
      // Copy sits between React and the bubble, so React appearing or leaving
      // never shifts it: outgoing trays pack to the right, incoming to the left.
      const dir = container.getAttribute('data-wisp-bubble') || (getComputedStyle(tray).justifyContent === 'flex-end' ? 'out' : 'in');
      if (dir === 'out') { tray.appendChild(clone); } else { tray.insertBefore(clone, tray.firstChild); }
      watchTray(tray);
    }
  }

  // WhatsApp keeps a tray mounted after the pointer leaves and hides or removes
  // its React item. The clone follows: it mirrors React's classes and inline
  // style, and goes away when React does. One observer per tray; trays only
  // exist for hovered messages, so this is a handful at most.
  const trayWatchers = new WeakMap();
  function syncTray(tray) {
    const ours = tray.querySelector(':scope > [data-wisp-copy-item]');
    if (!ours) { return; }
    const react = tray.querySelector('[data-testid="reaction-entry-point"]');
    const theirs = react && react.parentElement && react.parentElement.parentElement;
    if (!theirs || theirs.parentElement !== tray) { ours.remove(); return; }
    if (ours.className !== theirs.className) { ours.className = theirs.className; }
    if (ours.style.cssText !== theirs.style.cssText) { ours.style.cssText = theirs.style.cssText; }
    const ourBtn = ours.querySelector('[data-wisp-copy]');
    if (ourBtn && ourBtn.className !== react.className) { ourBtn.className = react.className; }
  }
  function watchTray(tray) {
    if (trayWatchers.has(tray)) { return; }
    const mo = new MutationObserver(() => {
      if (!tray.isConnected) { mo.disconnect(); trayWatchers.delete(tray); return; }
      syncTray(tray);
    });
    mo.observe(tray, { childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'style'] });
    trayWatchers.set(tray, mo);
  }

  let stateTimer = 0;
  function scheduleState() {
    if (stateTimer) { return; }
    stateTimer = setTimeout(() => {
      stateTimer = 0;
      const s = computeState();
      detectScheme();
      if (s !== lastState) {
        lastState = s;
        if (s === 'chats') { markBubbles(); }
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

  // Bubble tagging walks every message leaf in #main and reads layout for the
  // untagged ones, so it runs at most once per frame (requestAnimationFrame
  // callbacks precede paint, so new bubbles never flash untagged).
  let bubbleFrame = 0;
  let bubbleTimer = 0;
  function runBubblePass() {
    if (bubbleFrame) { cancelAnimationFrame(bubbleFrame); bubbleFrame = 0; }
    if (bubbleTimer) { clearTimeout(bubbleTimer); bubbleTimer = 0; }
    if (lastState === 'chats') { markBubbles(); addCopyButtons(); }
  }
  function tagBubblesBeforePaint() {
    if (bubbleFrame) { return; }
    bubbleFrame = requestAnimationFrame(runBubblePass);
    // Frames pause while the page is hidden (occluded window); keep tags
    // current there too, for window thumbnails and snapshots.
    bubbleTimer = setTimeout(runBubblePass, 300);
  }

  let appObserved = false;
  function observeApp() {
    const root = document.documentElement;
    if (!root || appObserved) { return; }
    appObserved = true;
    // WhatsApp mutates the DOM constantly (hover classes, clocks, typing
    // indicators). Only an added element can be a new bubble, and only the
    // structure or the <html>/<body> class list can change page state or
    // scheme, so everything else is ignored here.
    const mo = new MutationObserver((records) => {
      let added = false;
      let structural = false;
      for (const r of records) {
        if (r.type === 'childList') {
          structural = true;
          if (!added) { for (const n of r.addedNodes) { if (n.nodeType === 1) { added = true; break; } } }
        } else if (r.target === root || r.target === document.body) {
          structural = true;
        }
        if (added) { break; }
      }
      if (structural) { scheduleState(); }
      if (added && lastState === 'chats') { tagBubblesBeforePaint(); }
    });
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
    messageText,
    bubbleInfo: () => ({ selector: bubbleSelector, marked: document.querySelectorAll('#main [data-wisp-bubble]').length, out: document.querySelectorAll('#main [data-wisp-bubble="out"]').length, tails: document.querySelectorAll('#main span[data-icon^="tail-"]').length, scheme: lastScheme }),
    log: (...a) => log('info', a), warn: (...a) => log('warning', a), error: (...a) => log('error', a)
  });
  Object.defineProperty(globalThis, '__wispCore', { value: api, enumerable: false, configurable: false, writable: false });

  // Boot. At document start <head> may not exist yet; wait for it cheaply.
  const boot = () => { observeHead(); observeApp(); ensureOrder(); };
  if (document.head && document.body) { boot(); }
  else { document.addEventListener('DOMContentLoaded', boot, { once: true }); observeApp(); }
})();
