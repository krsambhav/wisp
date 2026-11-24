# Reader-avatar tests

Run `npm ci && npm test` in this directory (Node 24 or newer).

The DOM/IndexedDB fixtures verify read versus delivered receipts, self exclusion,
cached-photo-only rendering, rightmost avatar stacking, overflow, chat/message
changes, missing storage, readonly transactions, and no polling while unfocused. Focused chats check local storage every five seconds.
Network and remote-resource entry points throw if the feature tries to use them.

`wisp-seen.js` reads the existing `model-storage` database's `message-info` store
through its `msgKey` index. It never creates/upgrades a database or writes records.
The schema and the synchronous collection accessors were checked against the
installed WhatsApp Web bundle. If those internal shapes change, the indicator
stays hidden. Do not add collection `find`, `query`, `update`, picture `get`, or
remote `<img src>` fallbacks: those can trigger requests or refreshes.
