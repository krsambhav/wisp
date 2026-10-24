/*
 * Wisp — user script runtime. Injected once per content world that hosts user
 * scripts. Provides `wisp.log/warn/error` and reports uncaught errors thrown by
 * user scripts so they show up in Settings › Scripts › Logs.
 */
(() => {
  'use strict';
  if (globalThis.wisp && globalThis.wisp.__isWisp) { return; }
  const post = (payload) => {
    try {
      const h = globalThis.webkit && globalThis.webkit.messageHandlers && globalThis.webkit.messageHandlers.wispLog;
      if (h) { h.postMessage(payload); }
    } catch (_) {}
  };
  const fmt = (args) => args.map((a) => {
    try { return typeof a === 'string' ? a : JSON.stringify(a); } catch (_) { return String(a); }
  }).join(' ').slice(0, 2000);
  let current = 'user';
  const api = {
    __isWisp: true,
    version: 1,
    get script() { return current; },
    log: (...a) => post({ level: 'info', source: current, message: fmt(a) }),
    warn: (...a) => post({ level: 'warning', source: current, message: fmt(a) }),
    error: (...a) => post({ level: 'error', source: current, message: fmt(a) }),
    __run(name, fn) {
      const prev = current; current = name;
      try { fn(); post({ level: 'debug', source: name, message: 'ran' }); }
      catch (e) {
        const head = (e && e.message) ? `${e.name || 'Error'}: ${e.message}` : String(e);
        const stack = (e && e.stack) ? String(e.stack).replace(/^.*?\n?/, '') : '';
        post({ level: 'error', source: name, message: (stack ? `${head} (${stack.split('\n')[0].trim()})` : head).slice(0, 2000) });
      } finally { current = prev; }
    }
  };
  Object.defineProperty(globalThis, 'wisp', { value: Object.freeze(api), enumerable: false, configurable: true, writable: false });
})();
