# Customization guide

Everything here is in **Settings** (⌘,). Changes apply live to every loaded account; nothing reloads the page except script changes, which need a reload (⌘R or "Save & Reload").

## Appearance Studio

### Themes

| Theme | Character | Mode |
|---|---|---|
| **Default** | WhatsApp's green identity with softer surfaces, hairline borders and a quieter wallpaper. | Follows your Mode setting |
| **Minimal** | Monochrome, shadcn/ui-inspired. Neutral surfaces, 1 px borders, no wallpaper doodle, accent only on badges, buttons and focus rings. | Follows your Mode setting |
| **Midnight** | Deep near-black surfaces, low-contrast dividers, indigo accent. | Always dark |

**Mode** (System / Light / Dark) sets the web view's appearance, which WhatsApp follows when its own theme preference is "System default". If you set a fixed theme inside WhatsApp, that wins and Wisp's colors adapt to it.

### Accent

Pick a preset, any color from the color picker, or "Theme" to use the theme's own accent. The accent drives buttons, unread badges, read receipts, focus rings, and (when **Tint outgoing bubbles with accent** is on) the background of your own messages. Emphasized and deemphasized variants are derived automatically for light and dark.

### Typography and layout

- **Font**: System (SF Pro), Rounded, Serif (New York) or Monospace. Applied to the whole page.
- **Interface scale**: WebKit page zoom, 80–140 %. Also ⌘+ / ⌘− / ⌘0.
- **Message text size**: 85–140 % of WhatsApp's default, message text only.
- **Density**: Comfortable or Compact. Compact tightens message spacing, headers and the composer; chat-list rows keep WhatsApp's height.
- **Rounded message bubbles**: on/off with a 6–24 pt radius. Bubble tails are hidden when on.
- **Sidebar width**: off (WhatsApp's responsive width) or a fixed 300–560 pt.

### Custom CSS

Your stylesheet is injected after the theme, in the same isolated style slot, and saved to `custom.css` in the Wisp data folder. **Live preview** applies as you type (400 ms debounce); turn it off to apply with the button. The editor flags unbalanced braces, the one mistake that silently disables every rule after it. **Enable custom CSS** turns the whole sheet on or off without deleting it.

Use Wisp's variables so your rules follow the active theme and scheme:

```
--wisp-accent  --wisp-accent-emphasized  --wisp-accent-deemphasized  --wisp-on-accent
--wisp-background  --wisp-background-inset
--wisp-surface  --wisp-surface-emphasized  --wisp-surface-elevated  --wisp-surface-highlight
--wisp-text-primary  --wisp-text-secondary  --wisp-text-disabled  --wisp-link
--wisp-divider  --wisp-outline
--wisp-bubble-incoming  --wisp-bubble-outgoing  --wisp-chat-background  --wisp-composer
--wisp-unread-badge  --wisp-unread-badge-text
--wisp-scrollbar  --wisp-scrollbar-hover
--wisp-font-family  --wisp-message-font-scale  --wisp-bubble-radius  --wisp-sidebar-width (only when set)
```

Switches on `<html>` you can key rules off:

```
html[data-wisp-density="comfortable" | "compact"]
html[data-wisp-bubbles="rounded" | "default"]
html[data-wisp-sidebar]        present only when a fixed sidebar width is set
body.dark                      WhatsApp's own dark-mode marker
```

Wisp also overrides WhatsApp's own tokens (`--WDS-accent`, `--WDS-surface-default`, `--incoming-background`, …) with `!important`; override those in your CSS the same way if you need to.

Examples:

```css
/* Narrower, calmer chat list dividers */
#pane-side [role="row"] > div { border-bottom: 1px solid var(--wisp-divider); }

/* Outgoing bubbles with a subtle outline instead of a fill */
.message-out > div:first-child {
  background: var(--wisp-surface) !important;
  box-shadow: inset 0 0 0 1px var(--wisp-accent) !important;
}

/* Larger avatars in the chat list */
#pane-side img { width: 48px !important; height: 48px !important; }

/* Hide the "Download WhatsApp for Mac" login banner */
#app a[href*="download"] { display: none; }
```

Structural hooks (`#app`, `#side`, `#main`, `#pane-side`, `.message-in`, `.message-out`, `.copyable-text`) are stable in practice but not guaranteed; Settings › Advanced shows whether the hooks the current theme relies on were found after login.

### Presets

**Export** writes a JSON file with the appearance settings, your custom CSS and, optionally, your scripts. **Import** applies a preset; imported scripts are added disabled. Format:

```json
{
  "format": "wisp-preset",
  "version": 1,
  "name": "My preset",
  "exportedAt": "2026-10-25T00:00:00Z",
  "appearance": { "themeID": "minimal", "mode": "system", "accentOverride": "#2563EB", "font": "system",
                  "interfaceScale": 1, "messageFontScale": 1, "density": "comfortable",
                  "roundedBubbles": true, "bubbleRadius": 14, "sidebarWidth": null,
                  "customCSSEnabled": true, "livePreview": true, "tintOutgoingBubbles": true },
  "customCSS": "...",
  "scripts": [ { "id": "...", "name": "...", "summary": "", "enabled": false,
                 "injectionTime": "document-end", "world": "isolated", "source": "...",
                 "createdAt": "...", "updatedAt": "..." } ]
}
```

Files with another `format` or a newer `version` are rejected.

### Reset

- Settings › Appearance › **Reset**: back to the Default theme and layout defaults; custom CSS and scripts untouched.
- Settings › Advanced › **Reset all customizations**: defaults, empty custom CSS, every script disabled (files kept). Login sessions are never touched.

## Scripts

Settings › Scripts is a userscript manager for WhatsApp Web.

### Files and header

Each script is a file in the Scripts folder (Settings › Scripts › Open Folder):

```
~/Library/Containers/app.wisp.desktop/Data/Library/Application Support/Wisp/Scripts/<uuid>.js
```

Files start with a header Wisp reads and writes; a plain `.js` dropped into the folder is adopted with defaults (document end, isolated, enabled).

```js
// ==WispScript==
// @name        Hover lift
// @description Lifts message bubbles on hover
// @run-at      document-end        // or document-start
// @world       isolated            // or page
// @enabled     true
// ==/WispScript==
const style = document.createElement('style');
style.textContent = '.message-in > div:first-child:hover { transform: translateY(-1px); }';
document.head.appendChild(style);
wisp.log('hover lift installed');
```

### Worlds and timing

- **Isolated** (recommended): runs in Wisp's `wisp.user` JavaScript world. It sees and can modify the DOM but not WhatsApp's JavaScript objects, and WhatsApp cannot see your globals. Scripts in this world share it with each other.
- **Page context**: runs in WhatsApp's own world. Needed to patch `window`, wrap `fetch`, or touch WhatsApp's objects. A bug here can break the page; use it only when you must.
- **Document start** runs before WhatsApp's scripts (no `<body>` yet); **document end** runs after the DOM is parsed.

### API and error capture

In both worlds a frozen `wisp` object is available:

```js
wisp.log('info'); wisp.warn('warning'); wisp.error('error');   // → Settings › Scripts › Execution log
wisp.script;   // current script name
wisp.version;  // 1
```

Every script runs inside `wisp.__run(name, fn)`. Uncaught exceptions are logged with the script's name and stack and do not affect other scripts or WhatsApp. Scripts that fail the syntax check in the editor are marked with a warning and are not injected.

### Editing, hot reload, import

- The editor checks syntax as you type (JavaScriptCore, without executing). **Save** persists; **Save & Reload** also reloads every account so document-start scripts re-run.
- **Hot reload from disk** watches the Scripts folder; when a file changes externally, scripts are reloaded and WhatsApp is refreshed. Handy with an external editor.
- **Import .js** adds a file (header optional) **disabled**; enable it after reviewing it.
- Reorder scripts by dragging; they inject in list order.

### Security rules

- Scripts are local files you wrote or explicitly imported. Wisp never downloads or executes remote scripts.
- Injected code gets no native APIs beyond logging; the only bridge handlers are logging, page-state and the notification polyfill, and every message is validated natively.
- Wisp never logs or exports message content, cookies or tokens. Keep that in mind in your own `wisp.log` calls.
- **Disable All** and **Reset all customizations** are the quick ways out if a script misbehaves; a script can also be deleted from the Scripts folder while Wisp is closed.
