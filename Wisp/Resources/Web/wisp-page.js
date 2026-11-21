/*
 * Wisp — page-world bridge (runs at document start, main frame only).
 *
 * WKWebView does not implement the Web Notifications API, so WhatsApp Web
 * would believe notifications are unsupported. This file installs a minimal,
 * spec-shaped `Notification` constructor whose only side effect is to forward
 * {title, body, tag, icon} to the native app, which shows a macOS notification.
 *
 * Security notes:
 *  - The only native handler reachable from here is `wispNotify`.
 *  - Chat mute shortcuts use the clicked row’s WhatsApp chat model.
 *  - Icons are converted to small data URLs so the native side never needs
 *    access to blob: URLs. Payload size is capped.
 */
(() => {
  'use strict';
  if (window.__wispNotify) { return; }

  const MAX_LIVE = 64;
  const MAX_ICON_BYTES = 200 * 1024;
  const live = new Map();      // id -> notification instance
  const iconCache = new Map(); // url -> data URL
  let seq = 0;

  const post = (payload) => {
    try {
      const h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.wispNotify;
      if (h) { h.postMessage(payload); }
    } catch (_) { /* bridge unavailable; never throw into the page */ }
  };

  // A row can be recycled. Resolve the live chat component from its native
  // chevron on each activation so duplicate display names are unambiguous.
  function rowMuteModel(button) {
    const trigger = button.parentElement?.nextElementSibling;
    if (!trigger?.matches('button[data-testid="context-btn"]')) { return; }
    const fiberKey = Object.keys(trigger).find((key) => key.startsWith('__reactFiber$'));
    for (let fiber = trigger[fiberKey]; fiber; fiber = fiber.return) {
      const model = fiber.stateNode?.props?.chat?.mute;
      if (typeof model?.mute === 'function') { return model; }
    }
  }

  const muteSelector = '#pane-side :is([data-wisp-chat-action="hour"], [data-wisp-chat-action="always"])';
  function updateMuteLabels(button) {
    const model = rowMuteModel(button);
    if (!model) { return; }
    const muted = window.require('WAWebMuteGetters').getIsMuted(model);
    for (const shortcut of button.parentElement.querySelectorAll(muteSelector)) {
      const label = muted ? 'Unmute notifications' : shortcut.dataset.wispChatAction === 'hour' ? 'Mute for 1 hour' : 'Mute always';
      shortcut.title = label;
      shortcut.setAttribute('aria-label', label);
    }
  }

  for (const type of ['pointerover', 'focusin']) {
    document.addEventListener(type, (event) => {
      const button = event.target.closest?.(muteSelector);
      if (button) { updateMuteLabels(button); }
    }, true);
  }

  const pendingMutes = new WeakSet();
  document.addEventListener('click', async (event) => {
    if (!event.isTrusted) { return; }
    const button = event.target.closest?.(muteSelector);
    if (!button) { return; }
    const model = rowMuteModel(button);
    if (!model) {
      window.alert('Could not find this chat. Please try again.');
      return;
    }
    if (pendingMutes.has(model)) { return; }
    try {
      pendingMutes.add(model);
      if (window.require('WAWebMuteGetters').getIsMuted(model)) {
        await model.unmute({ sendDevice: true, showToast: true });
      } else {
        const hours = button.dataset.wispChatAction === 'hour' ? 1 : Infinity;
        const expiration = window.require('WAWebMuteExpirations').calculateMuteExpiration(hours);
        await model.mute({ expiration, sendDevice: true, showToast: true });
      }
      if (button.isConnected) { updateMuteLabels(button); }
    } catch (_) {
      window.alert('Could not change notifications for this chat. Please try again.');
    } finally {
      pendingMutes.delete(model);
    }
  }, true);

  async function resolveIcon(url) {
    if (!url || typeof url !== 'string') { return ''; }
    if (url.startsWith('data:')) { return url.length <= MAX_ICON_BYTES ? url : ''; }
    if (iconCache.has(url)) { return iconCache.get(url); }
    try {
      const res = await fetch(url);
      const blob = await res.blob();
      if (blob.size > MAX_ICON_BYTES) { return ''; }
      const dataURL = await new Promise((resolve, reject) => {
        const r = new FileReader();
        r.onload = () => resolve(String(r.result || ''));
        r.onerror = () => reject(r.error);
        r.readAsDataURL(blob);
      });
      if (iconCache.size > 48) { iconCache.delete(iconCache.keys().next().value); }
      iconCache.set(url, dataURL);
      return dataURL;
    } catch (_) {
      return '';
    }
  }

  class WispNotification extends EventTarget {
    static get permission() { return 'granted'; }
    static get maxActions() { return 0; }
    static requestPermission(callback) {
      if (typeof callback === 'function') { try { callback('granted'); } catch (_) {} }
      return Promise.resolve('granted');
    }

    constructor(title, options) {
      super();
      const opts = options && typeof options === 'object' ? options : {};
      this.title = String(title == null ? '' : title).slice(0, 512);
      this.body = String(opts.body == null ? '' : opts.body).slice(0, 2048);
      this.tag = opts.tag == null ? '' : String(opts.tag).slice(0, 256);
      this.icon = opts.icon == null ? '' : String(opts.icon);
      this.data = opts.data;
      this.silent = !!opts.silent;
      this.renotify = !!opts.renotify;
      this.requireInteraction = !!opts.requireInteraction;
      this.dir = opts.dir || 'auto';
      this.lang = opts.lang || '';
      this.timestamp = typeof opts.timestamp === 'number' ? opts.timestamp : Date.now();
      this.onclick = null; this.onclose = null; this.onerror = null; this.onshow = null;

      const id = ++seq;
      Object.defineProperty(this, '__wispID', { value: id, enumerable: false });
      live.set(id, this);
      if (live.size > MAX_LIVE) { live.delete(live.keys().next().value); }

      resolveIcon(this.icon).then((icon) => {
        post({ kind: 'show', id, title: this.title, body: this.body, tag: this.tag, icon, silent: this.silent, ts: this.timestamp });
      });
      queueMicrotask(() => {
        const ev = new Event('show');
        this.dispatchEvent(ev);
        if (typeof this.onshow === 'function') { try { this.onshow(ev); } catch (_) {} }
      });
    }

    close() {
      if (live.delete(this.__wispID)) {
        post({ kind: 'close', id: this.__wispID, tag: this.tag });
        const ev = new Event('close');
        this.dispatchEvent(ev);
        if (typeof this.onclose === 'function') { try { this.onclose(ev); } catch (_) {} }
      }
    }
  }

  Object.defineProperty(window, 'Notification', { value: WispNotification, configurable: true, writable: true });

  // Native -> page entry points (called with evaluateJavaScript in the page world).
  Object.defineProperty(window, '__wispNotify', {
    enumerable: false, configurable: false, writable: false,
    value: Object.freeze({
      click(id) {
        const n = live.get(id);
        if (!n) { return false; }
        try { window.focus(); } catch (_) {}
        const ev = new Event('click');
        n.dispatchEvent(ev);
        if (typeof n.onclick === 'function') { try { n.onclick(ev); } catch (_) {} }
        live.delete(id);
        return true;
      },
      close(id) {
        const n = live.get(id);
        if (!n) { return false; }
        live.delete(id);
        const ev = new Event('close');
        n.dispatchEvent(ev);
        if (typeof n.onclose === 'function') { try { n.onclose(ev); } catch (_) {} }
        return true;
      },
      liveCount() { return live.size; }
    })
  });
})();
