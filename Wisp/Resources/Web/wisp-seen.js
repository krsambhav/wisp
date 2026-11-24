/* Latest-message readers. Passive: readonly IndexedDB + existing model events.
 * Never call find/query/update on WhatsApp collections, load a remote image,
 * open Message Info, or send anything. Missing/changed schemas fail closed.
 */
(() => {
  'use strict';
  if (window.__wispSeen) { return; }
  window.__wispSeen = true;

  const LIMIT = 5;
  let timer = 0, localTimer = 0, revision = 0, currentRow = null, collections = null;
  let subscribed = null;
  let shiftedReaction = null;
  const subscriptions = [];

  function schedule() {
    clearTimeout(localTimer); localTimer = 0;
    // Invalidate in-flight reads immediately, including when switching chats.
    revision++;
    if (!timer) { timer = setTimeout(() => { timer = 0; refresh(); }, 200); }
  }
  function listen(target, events) {
    if (typeof target?.on !== 'function' || typeof target?.off !== 'function') { return; }
    target.on(events, schedule);
    subscriptions.push(() => target.off(events, schedule));
  }
  function stores() {
    try {
      // These modules are already part of the running client. Only synchronous
      // in-memory accessors are used; never collection.find() or picture.get().
      const value = window.require?.('WAWebCollections');
      if (value?.Msg && value?.Chat) { collections = value; }
      if (collections && subscribed !== collections) {
        subscriptions.splice(0).forEach((off) => off());
        subscribed = collections;
        listen(collections.Msg, 'add remove reset change:ack');
        listen(collections.MsgInfo, 'add remove reset change');
        listen(collections.ProfilePicThumb, 'add remove reset change:raw');
      }
    } catch (_) { /* Logged out or module not ready. */ }
    return collections;
  }
  const keyOf = (id) => typeof id === 'string' ? id : id?.toString?.();
  const models = (collection) => collection?.getModelsArray?.() || [];

  function latest() {
    const store = stores();
    if (!store) { return null; }
    const main = document.querySelector('#main');
    const elements = main?.querySelectorAll('[data-id]');
    if (!elements?.length) { return null; }
    // Current Web uses the bare stanza ID in data-id; older builds used the
    // serialized key. Resolve both without querying/loading a missing model.
    const byStanza = new Map();
    for (const msg of models(store.Msg)) {
      const stanza = msg.id?.id;
      if (!stanza) { continue; }
      if (!byStanza.has(stanza)) { byStanza.set(stanza, msg); }
      else if (keyOf(byStanza.get(stanza)?.id) !== keyOf(msg.id)) {
        byStanza.set(stanza, null); // ambiguous across chats: fail closed
      }
    }
    // Resolve the current chat from a rendered message, not its display name.
    let chat;
    for (let i = elements.length - 1; i >= 0 && !chat; i--) {
      const domID = elements[i].getAttribute('data-id');
      const msg = store.Msg.get(domID) || byStanza.get(domID);
      if (msg?.id?.remote) { chat = store.Chat.get(msg.id.remote); }
    }
    if (!chat) { return null; }
    const sent = models(chat.msgs).filter((msg) => msg.id?.fromMe && !msg.isRevoked && msg.type !== 'revoked');
    const msg = sent.reduce((last, item) => !last || item.t >= last.t ? item : last, null);
    if (!msg) { return null; }
    const key = keyOf(msg.id);
    const element = Array.from(elements).find((el) => {
      const domID = el.getAttribute('data-id');
      return domID === key || (domID === msg.id.id && keyOf(byStanza.get(domID)?.id) === key);
    });
    // Do not move the indicator to an older message when the latest is offscreen.
    if (!element) { return null; }
    return { element, msg, key };
  }

  async function readLocalReceipts(key) {
    // databases() avoids creating a database on a fresh/logged-out session.
    if (!window.indexedDB?.databases) { return []; }
    const databases = await indexedDB.databases();
    if (!databases.some((db) => db.name === 'model-storage')) { return []; }
    return new Promise((resolve) => {
      const request = indexedDB.open('model-storage');
      request.onupgradeneeded = () => { request.transaction.abort(); };
      request.onerror = () => resolve([]);
      request.onblocked = () => resolve([]);
      request.onsuccess = () => {
        const db = request.result;
        db.onversionchange = () => db.close();
        if (!db.objectStoreNames.contains('message-info')) { db.close(); resolve([]); return; }
        try {
          const tx = db.transaction('message-info', 'readonly');
          const table = tx.objectStore('message-info');
          const index = Array.from(table.indexNames).map((name) => table.index(name)).find((i) =>
            i.keyPath === 'msgKey' || (Array.isArray(i.keyPath) && i.keyPath.length === 1 && i.keyPath[0] === 'msgKey'));
          let rows = [];
          tx.oncomplete = () => { db.close(); resolve(rows); };
          tx.onabort = tx.onerror = () => { db.close(); resolve([]); };
          if (!index) { return; }
          const read = index.getAll(IDBKeyRange.only(Array.isArray(index.keyPath) ? [key] : key));
          read.onsuccess = () => { rows = read.result.filter((row) => row.msgKey === key &&
            typeof row.receiverUserJid === 'string' &&
            ((Number.isFinite(row.read) && row.read > 0) || (Number.isFinite(row.played) && row.played > 0))); };
        } catch (_) { db.close(); resolve([]); }
      };
    });
  }

  function person(id, includeImage) {
    const contact = collections.Contact?.get(id);
    const name = contact?.name || contact?.pushname || contact?.shortName || id.split('@')[0];
    // ProfilePicThumb.get() itself can mark a picture stale. Read its existing
    // models instead. Use embedded bytes only, never eurl/previewEurl/http URLs.
    const picture = includeImage && models(collections.ProfilePicThumb).find((item) => keyOf(item.id) === id);
    let image = null, loaded = null;
    if (typeof picture?.raw === 'string' && picture.raw.length < 300000 && /^[A-Za-z0-9+/=\s]+$/.test(picture.raw)) {
      image = 'data:image/jpeg;base64,' + picture.raw;
    } else if (picture) {
      // Copy pixels from an image WhatsApp has ALREADY loaded. Assigning its
      // remote src to another <img> could revalidate it, so we never do that.
      const urls = [picture.eurl, picture.previewEurl].filter(Boolean);
      try {
        // This getter only formats the in-memory thumbnail URL. It does not
        // query a profile or fetch an image (unlike collection.find/update).
        const url = window.require('WAWebProfilePicThumbGetters').getMaybeImg(picture);
        if (url) { urls.push(url); }
      } catch (_) {}
      loaded = Array.from(document.images).find((img) => img.complete && img.naturalWidth && urls.includes(img.currentSrc || img.src)) || null;
    }
    return { id, name: String(name), image, loaded };
  }

  function clear() {
    resetReaction();
    if (currentRow) {
      currentRow.removeAttribute('data-wisp-seen-owner');
      currentRow.querySelector('[data-wisp-seen]')?.remove();
      currentRow = null;
    }
  }
  function resetReaction() {
    if (!shiftedReaction) { return; }
    shiftedReaction.removeAttribute('data-wisp-seen-reaction');
    shiftedReaction.style.removeProperty('--wisp-seen-reaction-x');
    shiftedReaction.style.removeProperty('--wisp-seen-reaction-y');
    shiftedReaction = null;
  }
  function align(row, owner) {
    const bubble = owner.querySelector('[data-wisp-bubble="out"]');
    if (!bubble) { return; }
    const rect = owner.getBoundingClientRect();
    const scale = (owner.offsetWidth ? rect.width / owner.offsetWidth : 1) || 1;
    const bubbleRect = bubble.getBoundingClientRect();
    const before = row.getBoundingClientRect();
    // Native message rows can offset their children with margins. Correct
    // against the rendered edge rather than assuming the owner's border box
    // is the absolute-position containing block's right edge.
    const inset = parseFloat(row.style.insetInlineEnd) || 0;
    row.style.insetInlineEnd = inset + (before.right - bubbleRect.right) / scale + 'px';
    const rowHeight = row.getBoundingClientRect().height;
    // Center the circles on the message edge, independent of the lower
    // native reaction pill, so the pictures visibly overlap the bubble.
    row.style.top = (bubbleRect.bottom - rect.top - rowHeight / 2) / scale + 'px';
    const rowRect = row.getBoundingClientRect();
    const reaction = owner.querySelector('[data-testid="reaction-bubble"]');
    if (shiftedReaction && shiftedReaction !== reaction) { resetReaction(); }
    if (reaction) {
      reaction.setAttribute('data-wisp-seen-reaction', '');
      const reactionRect = reaction.getBoundingClientRect();
      const previousShift = parseFloat(reaction.style.getPropertyValue('--wisp-seen-reaction-x')) || 0;
      const previousY = parseFloat(reaction.style.getPropertyValue('--wisp-seen-reaction-y')) || 0;
      const originalRight = reactionRect.right - previousShift * scale;
      const originalTop = reactionRect.top - previousY * scale;
      // The reaction container reserves 20px after its icons; placing its
      // edge 10px into the reader row leaves a 10px visible gap.
      const shift = Math.min(0, (rowRect.left + 10 * scale - originalRight) / scale);
      reaction.style.setProperty('--wisp-seen-reaction-x', shift + 'px');
      reaction.style.setProperty('--wisp-seen-reaction-y', (rowRect.top - originalTop) / scale + 'px');
      shiftedReaction = reaction;
    }
  }
  function render(target, people) {
    if (currentRow !== target.element) { clear(); }
    if (!people.length) { clear(); return; }
    currentRow = target.element;
    const signature = JSON.stringify(people.map(({ id, name, image, loaded }) =>
      [id, name, image, loaded && (loaded.currentSrc || loaded.src)]));
    let row = currentRow.querySelector('[data-wisp-seen]');
    if (row?.dataset.signature === signature) { align(row, currentRow); return; }
    row?.remove();
    row = document.createElement('div');
    row.setAttribute('data-wisp-seen', '');
    row.dataset.signature = signature;
    row.setAttribute('role', 'group');
    const names = people.map((p) => p.name).join(', ');
    row.setAttribute('aria-label', 'Seen by ' + names);
    row.title = 'Seen by ' + names;
    if (people.length > LIMIT) {
      const overflow = document.createElement('span');
      overflow.className = 'wisp-seen-overflow';
      overflow.textContent = '+' + (people.length - LIMIT);
      row.appendChild(overflow);
    }
    people.slice(-LIMIT).forEach((p, i) => {
      const avatar = document.createElement('span');
      avatar.className = 'wisp-seen-avatar';
      avatar.style.zIndex = String(i + 1); // rightmost circle stays fully visible
      avatar.title = p.name;
      let hasPhoto = false;
      if (p.loaded) {
        try {
          // A cross-origin image may taint a canvas: drawing is permitted,
          // exporting with toDataURL/getImageData is not. Display it directly.
          const canvas = document.createElement('canvas');
          canvas.width = canvas.height = 48;
          canvas.setAttribute('role', 'img');
          canvas.setAttribute('aria-label', p.name);
          const side = Math.min(p.loaded.naturalWidth, p.loaded.naturalHeight);
          canvas.getContext('2d').drawImage(p.loaded,
            (p.loaded.naturalWidth - side) / 2, (p.loaded.naturalHeight - side) / 2, side, side, 0, 0, 48, 48);
          avatar.appendChild(canvas);
          hasPhoto = true;
        } catch (_) { /* Detached/unavailable image: keep the initials. */ }
      } else if (p.image) {
        const img = document.createElement('img');
        img.alt = p.name;
        img.src = p.image; // data: bytes only; never makes a network request
        avatar.appendChild(img);
        hasPhoto = true;
      }
      if (!hasPhoto) {
        avatar.textContent = p.name.trim().split(/\s+/).slice(0, 2).map((s) => Array.from(s)[0] || '').join('').toUpperCase();
        avatar.setAttribute('aria-label', p.name);
      }
      row.appendChild(avatar);
    });
    currentRow.setAttribute('data-wisp-seen-owner', '');
    currentRow.appendChild(row);
    align(row, currentRow);
  }

  async function refresh() {
    const token = revision;
    let target = null;
    try {
      if (document.hidden || !document.hasFocus()) { return; }
      target = latest();
      if (!target) { clear(); return; }
      if (currentRow && currentRow !== target.element) { clear(); }
      const key = keyOf(target.msg.latestEditMsgKey) || target.key;
      const records = await readLocalReceipts(key);
      if (token !== revision || !target.element.isConnected) { return; }
      const me = window.require('WAWebUserPrefsMeUser');
      const self = new Set([keyOf(me.getMaybeMePnUser?.()), keyOf(me.getMaybeMeLidUser?.())]);
      records.sort((a, b) => (a.read || a.played) - (b.read || b.played));
      const ids = Array.from(new Set(records.map((row) => row.receiverUserJid))).filter((id) => !self.has(id));
      render(target, ids.map((id, i) => person(id, i >= ids.length - LIMIT)));
    } catch (_) { if (token === revision) { clear(); } }
    finally {
      // Partial group reads need not change a message's aggregate ack. Refresh
      // ONLY the local readonly database while this chat is on screen. This
      // timer never calls a WhatsApp query or uses any network transport.
      if (target && token === revision && !document.hidden && document.hasFocus()) {
        clearTimeout(localTimer);
        localTimer = setTimeout(() => { localTimer = 0; schedule(); }, 5000);
      }
    }
  }
  const observer = new MutationObserver((records) => {
    if (records.some((record) => {
      const el = record.target.nodeType === 1 ? record.target : record.target.parentElement;
      if (el?.closest('[data-wisp-seen]')) { return false; }
      // Our own row insertion/removal must not schedule another database read.
      if (record.type === 'childList' && [...record.addedNodes, ...record.removedNodes].every((n) => n.nodeType === 1 && n.hasAttribute('data-wisp-seen'))) { return false; }
      return !!el?.closest('#main') || (record.type === 'childList' &&
        [...record.addedNodes, ...record.removedNodes].some((n) => n.nodeType === 1 && (n.id === 'main' || n.querySelector?.('#main'))));
    })) { schedule(); }
  });
  function boot() {
    observer.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['data-id', 'aria-label'] });
    schedule();
  }
  document.addEventListener('visibilitychange', schedule);
  window.addEventListener('focus', schedule);
  window.addEventListener('resize', schedule);
  window.addEventListener('blur', schedule);
  document.addEventListener('load', (event) => { if (event.target?.tagName === 'IMG' && !event.target.closest('[data-wisp-seen]')) { schedule(); } }, true);
  window.addEventListener('pagehide', () => {
    revision++;
    clearTimeout(timer); timer = 0;
    clearTimeout(localTimer); localTimer = 0;
    subscriptions.splice(0).forEach((off) => off());
    subscribed = null;
    observer.disconnect(); clear();
  });
  window.addEventListener('pageshow', () => { if (document.body) { boot(); } });
  if (document.body) { boot(); } else { document.addEventListener('DOMContentLoaded', boot, { once: true }); }
})();
