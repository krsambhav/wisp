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

  // ---------------------------------------------------- hover tray buttons
  // WhatsApp mounts a hover tray (an absolutely positioned flex row inside the
  // message container) holding the React button. Wisp clones that button's
  // tray item for its own discs, so they inherit WhatsApp's look and every
  // theme's hover-button rules. They sit between React and the bubble, so
  // React appearing or leaving never shifts them. Clicks never reach WhatsApp:
  // a clone has no React fiber and stops propagation.
  //   Copy      text messages: reads the message's own .copyable-text block.
  //   Download  anything with media except voice notes: drives WhatsApp's own
  //             "Download" menu entry, so decryption and naming stay theirs.
  const COPY_SVG = '<svg viewBox="0 0 24 24" height="16" preserveAspectRatio="xMidYMid meet" fill="currentColor"><title>wisp-copy</title><path fill="currentColor" d="M16 1H4a2 2 0 0 0-2 2v14h2V3h12V1zm3 4H8a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2zm0 16H8V7h11v14z"/></svg>';
  const DOWNLOAD_SVG = '<svg viewBox="0 0 24 24" height="16" preserveAspectRatio="xMidYMid meet" fill="currentColor"><title>wisp-download</title><path fill="currentColor" d="M5 20h14v-2H5v2zM19 9h-4V3H9v6H5l7 7 7-7z"/></svg>';
  const COPY_FILE_SVG = '<svg viewBox="0 0 24 24" height="16" preserveAspectRatio="xMidYMid meet" fill="currentColor"><title>wisp-copy-file</title><path fill="currentColor" d="M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm-1 4 6 6v10c0 1.1-.9 2-2 2H7.99C6.89 23 6 22.1 6 21l.01-14c0-1.1.89-2 1.99-2H15zm-1 7h5.5L14 6.5V12z"/></svg>';
  const DONE_SVG = '<svg viewBox="0 0 24 24" height="16" preserveAspectRatio="xMidYMid meet" fill="currentColor"><title>wisp-done</title><path fill="currentColor" d="M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg>';
  const MEDIA_SELECTOR = 'img[src^="blob:"], video, [data-testid="image-thumb"], [data-testid="document-thumb"], [data-testid="media-state-download"], [data-testid="sticker"], [data-testid="sticker-container"], [data-testid^="document-"], [data-icon^="document-"], [data-testid="gif"]';
  const VOICE_SELECTOR = 'audio, [data-testid*="audio" i], [data-icon*="audio" i], [data-testid*="ptt" i], [data-icon*="ptt" i], [data-testid*="voice" i]';

  const ACTIONS = {
    copy: {
      label: 'Copy message', done: 'Copied', svg: COPY_SVG,
      enabled: () => document.documentElement.getAttribute('data-wisp-copy-button') !== '0',
      applies: (c) => !!c.querySelector('.copyable-text[data-pre-plain-text]'),
      run: (c) => { const t = messageText(c); return !!t && writeClipboard(t); }
    },
    download: {
      label: 'Download', done: 'Downloading', svg: DOWNLOAD_SVG,
      enabled: () => document.documentElement.getAttribute('data-wisp-download-button') !== '0',
      applies: (c) => !!c.querySelector(MEDIA_SELECTOR) && !c.querySelector(VOICE_SELECTOR),
      run: (c) => downloadMedia(c)
    },
    copyfile: {
      label: (c) => c.querySelector('video') ? 'Copy video' : c.querySelector('[data-testid="image-thumb"], [data-testid="sticker-container"]') ? 'Copy image' : 'Copy file',
      done: 'Copied', svg: COPY_FILE_SVG,
      enabled: () => document.documentElement.getAttribute('data-wisp-copyfile-button') !== '0',
      applies: (c) => !!c.querySelector(MEDIA_SELECTOR) && !c.querySelector(VOICE_SELECTOR),
      // The app catches the download WhatsApp starts and puts the file on the
      // clipboard instead of saving it; disarmed again if no download starts.
      run: (c) => {
        if (!armClipboardCapture(true)) { return false; }
        if (downloadMedia(c, () => armClipboardCapture(false))) { return true; }
        armClipboardCapture(false);
        return false;
      }
    }
  };
  // Outermost first; the last entry sits next to the bubble.
  const ACTION_ORDER = ['download', 'copyfile', 'copy'];
  const actionLabel = (action, container) => typeof action.label === 'function' ? action.label(container) : action.label;

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
    return parts.join('\n').replace(/ /g, ' ').replace(/[ \t]+\n/g, '\n').trim();
  }

  function writeClipboard(text) {
    const h = globalThis.webkit && globalThis.webkit.messageHandlers && globalThis.webkit.messageHandlers.wispClipboard;
    if (h) { try { h.postMessage({ text: text.slice(0, 200000) }); return true; } catch (_) {} }
    if (navigator.clipboard && navigator.clipboard.writeText) { navigator.clipboard.writeText(text).catch(() => {}); return true; }
    return false;
  }

  function armClipboardCapture(armed) {
    const h = globalThis.webkit && globalThis.webkit.messageHandlers && globalThis.webkit.messageHandlers.wispClipboard;
    if (!h) { return false; }
    try { h.postMessage({ captureDownload: !!armed }); return true; } catch (_) { return false; }
  }

  function fireMouse(el, types, extra) {
    const r = el.getBoundingClientRect();
    const init = Object.assign({ bubbles: true, cancelable: true, composed: true, clientX: r.left + r.width / 2, clientY: r.top + r.height / 2, button: 0 }, extra || {});
    for (const t of types) { el.dispatchEvent(new (t.startsWith('pointer') ? PointerEvent : MouseEvent)(t, init)); }
  }
  function clickLike(el) {
    fireMouse(el, ['pointerdown', 'mousedown'], { buttons: 1 });
    fireMouse(el, ['pointerup', 'mouseup', 'click']);
  }

  // Opens the message's own options menu, picks "Download" and closes it. The
  // menu is portalled to the body; it is hidden before its first paint (the
  // observer fires as a microtask) so nothing flashes. If no Download entry
  // shows up within a second the menu is closed again and false is reported
  // through the button state.
  const DOWNLOAD_ITEM = '[data-testid="mi-msg-download"], [data-testid*="download" i], [aria-label="Download" i]';
  function findDownloadItem(root) {
    if (root.matches(DOWNLOAD_ITEM)) { return root; }
    const direct = root.querySelector(DOWNLOAD_ITEM);
    if (direct) { return direct; }
    for (const el of root.querySelectorAll('li, [role="button"], [role="menuitem"]')) {
      if (/^download$/i.test(el.textContent.trim())) { return el; }
    }
    return null;
  }
  function downloadMedia(container, onFail) {
    const chevron = container.querySelector('[data-testid="icon-down-context"], [aria-label="Open message options" i], [data-icon="down-context"]');
    if (!chevron) { return false; }
    const hidden = [];
    const hide = (node) => { if (node.nodeType === 1 && !node.closest('#main, #side')) { node.style.setProperty('visibility', 'hidden', 'important'); hidden.push(node); } };
    let settled = false;
    const finish = (ok) => {
      if (settled) { return; }
      settled = true; mo.disconnect(); clearTimeout(timer);
      if (!ok) {
        document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true }));
        if (onFail) { onFail(); }
      }
      // Let the menu close before anything becomes visible again.
      setTimeout(() => { for (const n of hidden) { n.style.removeProperty('visibility'); } }, 400);
    };
    const mo = new MutationObserver((records) => {
      for (const rec of records) {
        for (const node of rec.addedNodes) {
          if (node.nodeType !== 1 || node.closest('#main, #side')) { continue; }
          const item = findDownloadItem(node);
          if (!item) { continue; }
          hide(node);
          clickLike(item);
          finish(true);
          return;
        }
      }
    });
    mo.observe(document.body, { childList: true, subtree: true });
    const timer = setTimeout(() => finish(false), 1200);
    // The chevron is only laid out while the message is hovered; it is, since
    // the user just clicked a button inside the same container.
    fireMouse(container, ['pointerover', 'mouseover', 'pointermove', 'mousemove']);
    clickLike(chevron);
    return true;
  }

  function swallow(ev) { ev.stopPropagation(); }
  function onActionActivate(ev) {
    if (ev.type === 'keydown' && ev.key !== 'Enter' && ev.key !== ' ') { return; }
    ev.preventDefault(); ev.stopPropagation();
    const btn = ev.currentTarget;
    const action = ACTIONS[btn.getAttribute('data-wisp-action')];
    const container = btn.closest('[data-testid="msg-container"], [data-wisp-bubble]');
    if (!action || !container || !action.run(container)) { return; }
    const svg = btn.querySelector('svg');
    if (svg) { svg.outerHTML = DONE_SVG; }
    btn.setAttribute('aria-label', action.done);
    btn.setAttribute('data-wisp-done', '1');
    setTimeout(() => {
      if (!btn.isConnected) { return; }
      const done = btn.querySelector('svg');
      if (done) { done.outerHTML = action.svg; }
      btn.setAttribute('aria-label', actionLabel(action, container));
      btn.removeAttribute('data-wisp-done');
    }, 1200);
  }

  function addTrayButtons() {
    for (const react of document.querySelectorAll('#main [data-testid="reaction-entry-point"]')) {
      // react → unstyled wrapper → tray item (spacing) → tray (absolute flex row) → message container
      const item = react.parentElement && react.parentElement.parentElement;
      const tray = item && item.parentElement;
      const container = tray && tray.parentElement;
      if (!container) { continue; }
      if (getComputedStyle(tray).position !== 'absolute') { continue; } // structure drifted; do nothing
      const dir = container.getAttribute('data-wisp-bubble') || (getComputedStyle(tray).justifyContent === 'flex-end' ? 'out' : 'in');
      // Re-checked on every pass: a sticker or photo may finish loading after
      // its tray first appeared, and a setting may have been switched on.
      ACTION_ORDER.forEach((key, index) => {
        const action = ACTIONS[key];
        if (tray.querySelector(':scope > [data-wisp-item="' + key + '"]')) { return; }
        if (!action.enabled() || !action.applies(container)) { return; }
        const clone = item.cloneNode(true);
        const btn = clone.querySelector('[data-testid="reaction-entry-point"]');
        if (!btn) { return; }
        btn.setAttribute('data-testid', 'wisp-' + key + '-button');
        btn.setAttribute('data-wisp-action', key);
        const label = actionLabel(action, container);
        btn.setAttribute('aria-label', label);
        btn.setAttribute('title', label);
        const svg = btn.querySelector('svg');
        if (svg) { svg.outerHTML = action.svg; } else { btn.innerHTML = '<span aria-hidden="true">' + action.svg + '</span>'; }
        clone.setAttribute('data-wisp-item', key);
        btn.addEventListener('click', onActionActivate);
        btn.addEventListener('keydown', onActionActivate);
        for (const t of ['mousedown', 'mouseup', 'pointerdown', 'pointerup', 'dblclick', 'contextmenu']) { btn.addEventListener(t, swallow); }
        btn.addEventListener('mousedown', (ev) => ev.preventDefault()); // keep focus in the composer
        // Outgoing trays pack to the right, incoming to the left. Later entries
        // of ACTION_ORDER sit nearer the bubble; earlier ones go outside them.
        const inner = [...tray.querySelectorAll(':scope > [data-wisp-item]')].filter((el) => ACTION_ORDER.indexOf(el.getAttribute('data-wisp-item')) > index);
        if (dir === 'out') { if (inner.length) { tray.insertBefore(clone, inner[0]); } else { tray.appendChild(clone); } }
        else if (inner.length) { inner[inner.length - 1].after(clone); } else { tray.insertBefore(clone, tray.firstChild); }
      });
      watchTray(tray);
    }
  }

  // WhatsApp keeps a tray mounted after the pointer leaves and hides or removes
  // its React item. The clones follow: they mirror React's classes and inline
  // style, and go away when React does. One observer per tray; trays only
  // exist for hovered messages, so this is a handful at most.
  const trayWatchers = new WeakMap();
  function syncTray(tray) {
    const ours = tray.querySelectorAll(':scope > [data-wisp-item]');
    if (ours.length === 0) { return; }
    const react = tray.querySelector('[data-testid="reaction-entry-point"]');
    const theirs = react && react.parentElement && react.parentElement.parentElement;
    if (!theirs || theirs.parentElement !== tray) { for (const o of ours) { o.remove(); } return; }
    for (const o of ours) {
      if (o.className !== theirs.className) { o.className = theirs.className; }
      if (o.style.cssText !== theirs.style.cssText) { o.style.cssText = theirs.style.cssText; }
      const ourBtn = o.querySelector('[data-wisp-action]');
      if (ourBtn && ourBtn.className !== react.className) { ourBtn.className = react.className; }
    }
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

  // ---------------------------------------------------- message info popover
  // Clicking a receipt opens WhatsApp's "Message info" drawer (a third of the
  // window, closed by hand). The script notes where the receipt was clicked,
  // tags <html> with data-wisp-msginfo so base.css floats the drawer as a
  // small card, and anchors the card beside the message. A click anywhere
  // outside, Escape, scrolling the chat, or the card's own Close button closes
  // it (through WhatsApp's Close control, so WhatsApp's state stays correct).
  const MSGINFO_WIDTH = 280;
  const MSGINFO_GAP = 8;
  let msgInfoAnchor = null;        // DOMRect of the receipt last clicked
  let msgInfoPendingUntil = 0;     // a drawer appearing before this is the message info
  let msgInfoDrawer = null;
  let msgInfoResize = null;
  let msgInfoListening = false;
  const msgInfoEnabled = () => document.documentElement.getAttribute('data-wisp-msginfo-popover') !== '0';
  // WhatsApp keeps an empty, zero-width drawer slot in the DOM; the open one has a header.
  const msgInfoDrawerNow = () => { for (const d of document.querySelectorAll('[data-testid="drawer-right"]')) { if (d.querySelector('header')) { return d; } } return null; };
  let msgInfoOpenedAt = 0;
  const isMessageInfo = (drawer) => !!drawer.querySelector('[data-testid="msg-info-title"], [data-testid="kept-by-info"], [data-testid="msg-info"]');

  function onReceiptClick(ev) {
    if (!msgInfoEnabled()) { return; }
    const meta = ev.target && ev.target.closest && ev.target.closest('#main [data-testid="msg-meta"][role="button"]');
    if (!meta) { return; }
    cancelMsgInfoClose();   // another receipt while fading out: WhatsApp swaps the content, the card stays
    msgInfoAnchor = (meta.querySelector('[aria-label]') || meta).getBoundingClientRect();
    msgInfoPendingUntil = performance.now() + 2500;
    document.documentElement.setAttribute('data-wisp-msginfo', 'pending');
    if (msgInfoDrawer) { positionMsgInfo(); }
    scheduleMsgInfoCheck();
  }

  function positionMsgInfo() {
    const drawer = msgInfoDrawer;
    if (!drawer) { return; }
    const root = document.documentElement;
    const vw = root.clientWidth, vh = root.clientHeight;
    const a = msgInfoAnchor || { left: vw - 16, right: vw - 16, top: 72, bottom: 72 };
    const dr = drawer.getBoundingClientRect();
    const w = dr.width || MSGINFO_WIDTH;
    const h = dr.height || 120;
    // WhatsApp's zoom setting scales #app with CSS zoom, so viewport
    // coordinates map to the drawer's own px space through that factor.
    const scale = drawer.offsetWidth ? dr.width / drawer.offsetWidth : 1;
    let left = Math.round(a.right - w);
    left = Math.max(8, Math.min(left, vw - w - 8));
    let top = Math.round(a.bottom + MSGINFO_GAP);
    if (top + h > vh - 8) { top = Math.round(a.top - MSGINFO_GAP - h); }
    if (top < 8) { top = Math.max(8, Math.min(Math.round(a.bottom + MSGINFO_GAP), vh - 8 - h)); }
    root.style.setProperty('--wisp-msginfo-left', (left / scale).toFixed(1) + 'px');
    root.style.setProperty('--wisp-msginfo-top', (top / scale).toFixed(1) + 'px');
  }

  // The card fades out first (base.css animates html[data-wisp-msginfo="closing"]),
  // then WhatsApp's own Close control removes the drawer.
  const MSGINFO_OUT_MS = 140;
  let msgInfoCloseTimer = 0;
  function closeMsgInfo() {
    if (msgInfoCloseTimer) { return; }
    const drawer = msgInfoDrawer || msgInfoDrawerNow();
    const finish = () => {
      msgInfoCloseTimer = 0;
      const live = drawer && drawer.isConnected ? drawer : msgInfoDrawerNow();
      const btn = live && live.querySelector('header button[aria-label], header [role="button"][aria-label]');
      if (btn) { btn.click(); }
      else if (live) { document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true, cancelable: true })); }
      detachMsgInfo();
    };
    if (msgInfoDrawer && document.documentElement.getAttribute('data-wisp-msginfo') === '1') {
      document.documentElement.setAttribute('data-wisp-msginfo', 'closing');
      msgInfoCloseTimer = setTimeout(finish, MSGINFO_OUT_MS);
    } else { finish(); }
  }
  function cancelMsgInfoClose() {
    if (!msgInfoCloseTimer) { return; }
    clearTimeout(msgInfoCloseTimer); msgInfoCloseTimer = 0;
  }

  function onMsgInfoPointerDown(ev) {
    if (!msgInfoDrawer) { return; }
    const t = ev.target;
    if (msgInfoDrawer.contains(t)) { return; }
    // Another receipt: WhatsApp swaps the drawer's content; only the anchor moves.
    if (t && t.closest && t.closest('#main [data-testid="msg-meta"][role="button"]')) { return; }
    closeMsgInfo();
  }
  function onMsgInfoKey(ev) { if (ev.key === 'Escape' && msgInfoDrawer) { closeMsgInfo(); } }
  // Scrolling the chat moves the message away from the card, so the card goes.
  // Trackpad momentum keeps delivering wheel events after the click that opened
  // it, so the first moments after opening are ignored.
  function onMsgInfoScroll(ev) {
    if (!msgInfoDrawer || performance.now() - msgInfoOpenedAt < 1200) { return; }
    const t = ev.target;
    if (!t || (t.nodeType === 1 && (msgInfoDrawer.contains(t) || !t.closest('#main')))) { return; }
    closeMsgInfo();
  }

  function attachMsgInfo(drawer) {
    msgInfoDrawer = drawer;
    msgInfoOpenedAt = performance.now();
    document.documentElement.setAttribute('data-wisp-msginfo', '1');
    positionMsgInfo();
    if (!msgInfoListening) {
      msgInfoListening = true;
      document.addEventListener('pointerdown', onMsgInfoPointerDown, true);
      document.addEventListener('keydown', onMsgInfoKey, true);
      document.addEventListener('scroll', onMsgInfoScroll, { capture: true, passive: true });
      window.addEventListener('resize', positionMsgInfo);
    }
    if (typeof ResizeObserver === 'function') {
      msgInfoResize = new ResizeObserver(() => positionMsgInfo());
      msgInfoResize.observe(drawer);
    }
  }
  function detachMsgInfo() {
    cancelMsgInfoClose();
    msgInfoDrawer = null;
    msgInfoPendingUntil = 0;
    if (msgInfoResize) { msgInfoResize.disconnect(); msgInfoResize = null; }
    if (msgInfoListening) {
      msgInfoListening = false;
      document.removeEventListener('pointerdown', onMsgInfoPointerDown, true);
      document.removeEventListener('keydown', onMsgInfoKey, true);
      document.removeEventListener('scroll', onMsgInfoScroll, { capture: true });
      window.removeEventListener('resize', positionMsgInfo);
    }
    document.documentElement.removeAttribute('data-wisp-msginfo');
  }

  // Runs after DOM changes: adopts a message-info drawer, drops a stale tag.
  let msgInfoFrame = 0;
  let msgInfoTimer = 0;
  function checkMsgInfo() {
    if (msgInfoFrame) { cancelAnimationFrame(msgInfoFrame); msgInfoFrame = 0; }
    if (msgInfoTimer) { clearTimeout(msgInfoTimer); msgInfoTimer = 0; }
    const drawer = msgInfoDrawerNow();
    if (!drawer || !msgInfoEnabled()) { if (msgInfoDrawer || document.documentElement.hasAttribute('data-wisp-msginfo')) { detachMsgInfo(); } return; }
    if (msgInfoDrawer === drawer) { if (!isMessageInfo(drawer) && performance.now() > msgInfoPendingUntil) { detachMsgInfo(); } return; }
    if (msgInfoDrawer) { detachMsgInfo(); }   // the drawer was swapped for another one
    if (isMessageInfo(drawer) || performance.now() < msgInfoPendingUntil) { attachMsgInfo(drawer); }
    else if (document.documentElement.hasAttribute('data-wisp-msginfo')) { document.documentElement.removeAttribute('data-wisp-msginfo'); }
  }
  function scheduleMsgInfoCheck() {
    if (msgInfoFrame) { return; }
    msgInfoFrame = requestAnimationFrame(checkMsgInfo);
    // Frames pause while the page is hidden (occluded window); the timer keeps
    // the tag and position current there too.
    msgInfoTimer = setTimeout(checkMsgInfo, 100);
    // The pending tag must not outlive a click that opened nothing.
    setTimeout(() => { if (!msgInfoDrawer && document.documentElement.getAttribute('data-wisp-msginfo') === 'pending' && performance.now() >= msgInfoPendingUntil) { document.documentElement.removeAttribute('data-wisp-msginfo'); } }, 2600);
  }
  document.addEventListener('click', onReceiptClick, true);

  // Bubble tagging walks every message leaf in #main and reads layout for the
  // untagged ones, so it runs at most once per frame (requestAnimationFrame
  // callbacks precede paint, so new bubbles never flash untagged).
  let bubbleFrame = 0;
  let bubbleTimer = 0;
  function runBubblePass() {
    if (bubbleFrame) { cancelAnimationFrame(bubbleFrame); bubbleFrame = 0; }
    if (bubbleTimer) { clearTimeout(bubbleTimer); bubbleTimer = 0; }
    if (lastState === 'chats') { markBubbles(); addTrayButtons(); }
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
      if (structural) { scheduleState(); if (msgInfoDrawer || msgInfoPendingUntil || added) { scheduleMsgInfoCheck(); } }
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
