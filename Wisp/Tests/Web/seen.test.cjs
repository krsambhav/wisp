const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const { IDBFactory, IDBKeyRange } = require('fake-indexeddb');
const source = fs.readFileSync(path.join(__dirname, '../../Resources/Web/wisp-seen.js'), 'utf8');
const css = fs.readFileSync(path.join(__dirname, '../../Resources/Web/themes/base.css'), 'utf8');
const wait = (ms = 320) => new Promise((resolve) => setTimeout(resolve, ms));
function collection(items = []) {
  const listeners = new Map();
  return { items, listeners, get: id => items.find(x => String(x.id) === String(id)), getModelsArray: () => items,
    on(events, cb) { events.split(' ').forEach(e => listeners.set(e, cb)); },
    off(events) { events.split(' ').forEach(e => listeners.delete(e)); },
    emit(event) { listeners.get(event)?.(); },
    find() { throw Error('Forbidden query'); }, update() { throw Error('Forbidden update'); } };
}
async function fixture({ readers = [], compound = false, missingDB = false, bareIDs = false, loadedPhoto = false, geometry = false, withReaction = false } = {}) {
  let requests = 0, reads = 0, draws = 0, exports = 0;
  const dom = new JSDOM('<!doctype html><style>' + css + '</style><div id="main"></div>', {
    url: 'https://web.whatsapp.com/', runScripts: 'outside-only', pretendToBeVisual: true, resources: { dispatcher: { dispatch() { requests++; throw Error('Remote resource'); } } } });
  const win = dom.window;
  let focused = true;
  win.document.hasFocus = () => focused;
  win.fetch = win.XMLHttpRequest = win.WebSocket = function () { requests++; throw Error('Network request'); };
  win.navigator.sendBeacon = () => { requests++; throw Error('Beacon'); };
  const id = { id: 'latest', fromMe: true, remote: 'chat@g.us', toString: () => 'true_chat@g.us_latest' }, msg = { id, t: 20 };
  const stores = { Msg: collection([msg]), Chat: collection([{ id: 'chat@g.us', msgs: collection([msg]) }]), MsgInfo: collection(),
    Contact: collection(Array.from({ length: 10 }, (_, i) => ({ id: `${i}@lid`, name: `Reader ${i}` }))),
    ProfilePicThumb: collection([{ id: '1@lid', raw: 'aGVsbG8=' }, { id: '2@lid', eurl: 'https://example.com/never-fetch.jpg' }]) };
  stores.ProfilePicThumb.get = () => { throw Error('Picture lookup may mark stale'); };
  win.require = name => {
    if (name === 'WAWebCollections') return stores;
    if (name === 'WAWebUserPrefsMeUser') return { getMaybeMePnUser: () => 'me@c.us', getMaybeMeLidUser: () => 'me@lid' };
    if (name === 'WAWebProfilePicThumbGetters') return { getMaybeImg: () => 'https://example.com/generated-thumbnail.jpg' };
    throw Error('Unexpected module ' + name);
  };
  const factory = new IDBFactory();
  if (!missingDB) await new Promise((resolve, reject) => {
    const open = factory.open('model-storage', 1);
    open.onupgradeneeded = () => open.result.createObjectStore('message-info', { keyPath: ['msgKey', 'receiverUserJid'] })
      .createIndex('msgKey', compound ? ['msgKey'] : 'msgKey');
    open.onerror = () => reject(open.error);
    open.onsuccess = () => {
      const db = open.result, tx = db.transaction('message-info', 'readwrite');
      readers.forEach(row => tx.objectStore('message-info').put({ msgKey: String(id), ...row }));
      tx.oncomplete = () => { db.close(); resolve(); };
    };
  });
  win.indexedDB = { databases: () => factory.databases(), open(...args) {
    const req = factory.open(...args);
    req.addEventListener('success', () => {
      const db = req.result, transaction = db.transaction.bind(db);
      db.transaction = (name, mode) => { assert.equal(mode, 'readonly'); reads++; return transaction(name, mode); };
    });
    return req;
  } };
  win.IDBKeyRange = IDBKeyRange;
  const main = win.document.querySelector('#main'), message = win.document.createElement('div');
  message.dataset.id = bareIDs ? id.id : String(id); message.innerHTML = '<div data-wisp-bubble="out">Latest sent message</div>'; main.append(message);
  let reaction = null;
  if (geometry) {
    message.getBoundingClientRect = () => ({ left: 100, right: 500, top: 100, bottom: 180, width: 400, height: 80 });
    Object.defineProperty(message, 'offsetWidth', { value: 400 });
    message.firstElementChild.getBoundingClientRect = () => ({ left: 300, right: 480, top: 100, bottom: 160, width: 180, height: 60 });
    const originalRect = win.HTMLElement.prototype.getBoundingClientRect;
    win.HTMLElement.prototype.getBoundingClientRect = function () {
      if (!this.hasAttribute('data-wisp-seen')) return originalRect.call(this);
      // The rendered containing edge is 20px inside the owner's border box.
      const right = 480 - (parseFloat(this.style.insetInlineEnd) || 0);
      const top = 100 + (parseFloat(this.style.top) || 0) + 6;
      return { left: right - 38, right, top, bottom: top + 24, width: 38, height: 24 };
    };
  }
  if (withReaction) {
    reaction = win.document.createElement('button'); reaction.dataset.testid = 'reaction-bubble';
    reaction.innerHTML = '<div><span data-testid="reaction-bubble-item">❤️</span><span data-testid="reaction-bubble-item">😂</span><span data-testid="test-reaction-count">2</span></div>'; message.append(reaction);
    reaction.getBoundingClientRect = () => {
      const shift = parseFloat(reaction.style.getPropertyValue('--wisp-seen-reaction-x')) || 0;
      const y = parseFloat(reaction.style.getPropertyValue('--wisp-seen-reaction-y')) || 0;
      return { left: 452 + shift, right: 490 + shift, top: 150 + y, bottom: 174 + y, width: 38, height: 24 };
    };
  }
  if (loadedPhoto) {
    const img = win.document.createElement('img');
    // Model an already loaded, non-CORS photo without issuing a test request.
    Object.defineProperties(img, {
      currentSrc: { value: 'https://example.com/generated-thumbnail.jpg' },
      complete: { value: true }, naturalWidth: { value: 80 }, naturalHeight: { value: 120 },
    });
    win.document.body.append(img);
    win.HTMLCanvasElement.prototype.getContext = () => ({ drawImage(source, ...rect) {
      assert.equal(source, img); assert.deepEqual(rect, [0, 20, 80, 80, 0, 0, 48, 48]); draws++;
    } });
    win.HTMLCanvasElement.prototype.toDataURL = () => { exports++; throw new Error('Tainted canvas'); };
  }
  win.eval(source); await wait();
  return { win, stores, main, message, msg, factory, reaction, counts: () => ({ requests, reads, draws, exports }), focus: value => { focused = value; win.dispatchEvent(new win.Event(value ? 'focus' : 'blur')); }, close: () => win.close() };
}
test('readers only; no self; cached images only; rightmost fully visible; no unfocused polling', async () => {
  const f = await fixture({ readers: [{ receiverUserJid: '0@lid', delivery: 10 }, { receiverUserJid: '1@lid', read: 12 },
    { receiverUserJid: '2@lid', played: 13 }, { receiverUserJid: 'me@lid', read: 14 }] });
  try {
    const row = f.message.querySelector('[data-wisp-seen]'); assert.ok(row);
    assert.equal(row.querySelectorAll('.wisp-seen-avatar').length, 2); assert.equal(row.querySelectorAll('img').length, 1);
    assert.ok(row.querySelector('img').src.startsWith('data:')); assert.equal(row.title, 'Seen by Reader 1, Reader 2');
    const avatars = row.querySelectorAll('.wisp-seen-avatar'); assert.equal(avatars[1].style.zIndex, '2');
    assert.equal(f.win.getComputedStyle(avatars[1]).marginLeft, '-10px'); assert.equal(f.counts().requests, 0);
    f.focus(false); const reads = f.counts().reads; await wait(600); assert.equal(f.counts().reads, reads, 'no recurring read loop');
  } finally { f.close(); }
});
test('overflow and compound message index', async () => {
  const f = await fixture({ compound: true, readers: Array.from({ length: 8 }, (_, i) => ({ receiverUserJid: `${i}@lid`, read: 10 })) });
  try { assert.equal(f.message.querySelectorAll('.wisp-seen-avatar').length, 5);
    assert.equal(f.message.querySelector('.wisp-seen-overflow').textContent, '+3'); assert.equal(f.counts().requests, 0);
  } finally { f.close(); }
});
test('new sent message removes old row; an offscreen latest never marks an older message', async () => {
  const f = await fixture({ readers: [{ receiverUserJid: '1@lid', read: 10 }] });
  try {
    assert.ok(f.message.querySelector('[data-wisp-seen]'));
    const next = { id: { fromMe: true, remote: 'chat@g.us', toString: () => 'true_chat@g.us_next' }, t: 30 };
    f.stores.Msg.items.push(next); f.stores.Chat.items[0].msgs.items.push(next); f.stores.Msg.emit('add'); await wait();
    assert.equal(f.main.querySelector('[data-wisp-seen]'), null); assert.equal(f.message.hasAttribute('data-wisp-seen-owner'), false);
  } finally { f.close(); }
});
test('normal receipt event refreshes local data; switching chat clears row', async () => {
  const f = await fixture();
  try {
    assert.equal(f.main.querySelector('[data-wisp-seen]'), null);
    await new Promise(resolve => {
      const open = f.factory.open('model-storage'); open.onsuccess = () => {
        const db = open.result, tx = db.transaction('message-info', 'readwrite');
        tx.objectStore('message-info').put({ msgKey: String(f.msg.id), receiverUserJid: '1@lid', read: 5 });
        tx.oncomplete = () => { db.close(); resolve(); };
      };
    });
    f.stores.Msg.emit('change:ack'); await wait(); assert.ok(f.main.querySelector('[data-wisp-seen]'));
    f.main.replaceChildren(); await wait(); assert.equal(f.message.querySelector('[data-wisp-seen]'), null);
    assert.equal(f.counts().requests, 0);
  } finally { f.close(); }
});
test('missing DB is never created; missing modules leave chat intact', async () => {
  const f = await fixture({ missingDB: true });
  try {
    assert.deepEqual(await f.factory.databases(), []); assert.equal(f.main.querySelector('[data-wisp-seen]'), null);
    assert.equal(f.counts().reads, 0); f.win.require = () => { throw Error('Unavailable'); };
    f.win.dispatchEvent(new f.win.Event('focus')); await wait(); assert.equal(f.message.textContent, 'Latest sent message');
    assert.equal(f.counts().requests, 0);
  } finally { f.close(); }
});

test('focused local refresh catches partial receipts without an ack event, then stops on blur', async () => {
  const f = await fixture();
  try {
    await new Promise(resolve => {
      const open = f.factory.open('model-storage'); open.onsuccess = () => {
        const db = open.result, tx = db.transaction('message-info', 'readwrite');
        tx.objectStore('message-info').put({ msgKey: String(f.msg.id), receiverUserJid: '3@lid', read: 12 });
        tx.oncomplete = () => { db.close(); resolve(); };
      };
    });
    await wait(5300);
    assert.equal(f.main.querySelector('[data-wisp-seen]').title, 'Seen by Reader 3');
    f.focus(false); const reads = f.counts().reads; await wait(5300);
    assert.equal(f.counts().reads, reads); assert.equal(f.counts().requests, 0);
  } finally { f.close(); }
});

test('current WhatsApp bare stanza DOM IDs resolve old read receipts', async () => {
  const f = await fixture({ bareIDs: true, readers: [{ receiverUserJid: '1@lid', read: 12 }, { receiverUserJid: '2@lid', read: 13 }] });
  try {
    assert.equal(f.message.dataset.id, 'latest');
    assert.equal(f.message.querySelectorAll('.wisp-seen-avatar').length, 2);
    assert.equal(f.counts().requests, 0);
  } finally { f.close(); }
});

test('ambiguous bare IDs across chats never borrow another chat’s receipts', async () => {
  const f = await fixture({ bareIDs: true, readers: [{ receiverUserJid: '1@lid', read: 12 }] });
  try {
    f.stores.Msg.items.push({ id: { id: 'latest', fromMe: true, remote: 'other@g.us', toString: () => 'true_other@g.us_latest' }, t: 40 });
    f.stores.Msg.emit('add'); await wait();
    assert.equal(f.message.querySelector('[data-wisp-seen]'), null);
    assert.equal(f.counts().requests, 0);
  } finally { f.close(); }
});

test('already loaded cross-origin DP is drawn directly without export or another request', async () => {
  const f = await fixture({ loadedPhoto: true, readers: [{ receiverUserJid: '2@lid', read: 12 }] });
  try {
    const canvas = f.message.querySelector('[data-wisp-seen] canvas');
    assert.ok(canvas);
    assert.equal(canvas.getAttribute('aria-label'), 'Reader 2');
    assert.equal(f.message.querySelector('[data-wisp-seen] img'), null);
    assert.equal(f.counts().draws, 1);
    assert.equal(f.counts().exports, 0);
    assert.equal(f.counts().requests, 0);
  } finally { f.close(); }
});

test('readers share the reaction line, shift reactions left without drift, and restore on removal', async () => {
  const f = await fixture({ geometry: true, withReaction: true, readers: [{ receiverUserJid: '1@lid', read: 12 }, { receiverUserJid: '2@lid', read: 13 }] });
  try {
    const row = f.message.querySelector('[data-wisp-seen]');
    assert.equal(row.style.top, '48px');
    assert.equal(row.getBoundingClientRect().right, 480);
    assert.equal(f.reaction.style.getPropertyValue('--wisp-seen-reaction-x'), '-38px');
    assert.equal(f.reaction.style.getPropertyValue('--wisp-seen-reaction-y'), '4px');
    assert.equal(f.win.getComputedStyle(f.reaction.querySelector('[data-testid=test-reaction-count]')).display, 'none');
    assert.equal(f.win.getComputedStyle(f.reaction.querySelector('[data-testid=reaction-bubble-item]')).width, '24px');
    let clicked = 0; f.reaction.onclick = () => clicked++; f.reaction.click(); assert.equal(clicked, 1);
    f.stores.Msg.emit('change:ack'); await wait();
    assert.equal(f.reaction.style.getPropertyValue('--wisp-seen-reaction-x'), '-38px');
    f.reaction.remove(); await wait();
    assert.equal(row.style.top, '48px');
    assert.equal(f.reaction.hasAttribute('data-wisp-seen-reaction'), false);
    assert.equal(f.reaction.style.getPropertyValue('--wisp-seen-reaction-x'), '');
    assert.equal(f.reaction.style.getPropertyValue('--wisp-seen-reaction-y'), '');
    assert.equal(f.counts().requests, 0);
  } finally { f.close(); }
});

test('readers alone overlap the bubble edge and reserve room for the next message', async () => {
  const f = await fixture({ geometry: true, readers: [{ receiverUserJid: '1@lid', read: 12 }] });
  try {
    assert.equal(f.message.querySelector('[data-wisp-seen]').style.top, '48px');
    assert.equal(f.win.getComputedStyle(f.message).paddingBottom, '18px');
    assert.equal(f.counts().requests, 0);
  } finally { f.close(); }
});
