# Feature: Cloudflare Turnstile Anti-Bot Internals & Vendor Store Bundle

**Status:** Reference Architecture — extracted from Chess.com's `turnstile/v0/api.js` and `pinia.JlH1PbuzUC.js` vendor chunks.

## Overview

This document captures the internal mechanisms of the two chunks in this batch:
1. **Cloudflare Turnstile Client SDK (`api.js`)** — used by Chess.com's `UserActivityService` and login/registration flows to verify human sessions.
2. **Vue Pinia & DevTools Vendor Bundle (`pinia.JlH1PbuzUC.js`)** — third-party state management (`pinia`), fast deep cloning (`rfdc`), lifecycle hooks (`hookable`), and slug transliteration (`speakingurl`).

---

## 1. Cloudflare Turnstile Client Internals

### A. Closed Shadow DOM & "Watchcat" Heartbeat (`Go`, `qo = 900ms`)
- **Closed Shadow Root:** Every Turnstile widget mounts its `<iframe>` inside `Gt.attachShadow({ mode: "closed" })` so external scripts cannot inspect or manipulate the challenge iframe.
- **The `"meow"` / `"food"` Watchcat Timer:**
  - Every **900ms** (`qo`), `Go(state)` increments `watchCatSeq` and sends a `postMessage` to the challenge iframe:
    ```js
    { event: "meow", seq: state.watchCatSeq, source: "cloudflare-challenge", widgetId }
    ```
  - The iframe must reply with `{ event: "food", seq }`, which updates `watchcat.lastAckedSeq`.
  - **Hang Detection (`Jo = 45` ticks ≈ 40.5s):** If `lastAckedSeq < seq - 46`, the widget is declared **hung** and fails with error code `300030` (`Zt`).
  - **Crash Detection (`jo = 50` ticks ≈ 45s):** If `isOverrunning` is true and `overrunBeginSeq < seq - 51`, the widget is declared **crashed** and fails with error code `300031` (`er`).

### B. `djb2` Form Classification Fingerprinting (`Qr`, `io`, `xa`, `Sa`)
When the iframe requests `extraParams` (`requestExtraParams`), Turnstile inspects the surrounding `<form>` (or up to 5 parent elements if not inside a `<form>`) without sending raw user PII:
1. **`djb2` Hash (`Qr`):**
   ```js
   let hash = 5381;
   for (let i = 0; i < str.length; i++) {
     hash = (hash * 33) ^ str.charCodeAt(i);
   }
   return hash >>> 0;
   ```
2. **N-Gram Hashing (`io`):** Tokenizes form `id`, `class`, `name`, `action` pathname, `<label>` text, and input attributes (`id`, `name`, `type`, `placeholder`, `aria-label`, `autocomplete`) into lowercase alphanumeric words, then hashes all **1-grams** and **2-grams** (`word1 word2`) using `djb2`.
3. **Semantic Form Classification (`xa` / `pac`):** Matches the token hashes against precomputed `djb2` hash tables (`ao`) and input type counts (email, file, password, textarea) to classify the form into a 1–2 letter code (`pac`):
   - `"l"` (`Kr`) — Login form (1 password input + login keywords)
   - `"r"` (`Gr`) — Registration form
   - `"s"` (`Xr`) — Sign-up / change-password form (>1 password input)
   - `"c"` (`qr`) — Checkout / payment form
   - `"cp"` (`Jr`) — Comment / post form (`<textarea>` present)
   - `"ct"` (`jr`) — Contact form
   - `"nl"` (`zr`) — Newsletter form (email input + newsletter keywords)
   - `"up"` (`Yr`) — File upload form (`<input type="file">`)
   - `"u"` (`Ki`) — Unknown form
   - `"n"` (`Wr`) — No form found

### C. DOM Structure Fingerprint (`Aa` / `pfp` & `ha` / `xp`)
- **Page Fingerprint (`pfp`):** Uses `document.createNodeIterator(document, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT)` up to depth `3` (`sa`) and max length `500` chars (`fa`), encoding each element as `<3-char tag>_<2-char attrName>...>` and text nodes as `-t`.
- **Widget XPath (`xp`):** `ha(wrapper)` walks up `parentElement` and `previousElementSibling` to produce a compact 3-letter tag XPath (e.g., `/div[1]/for[2]/div[1]`).

### D. CSS Visibility & Transform Tamper Detection (`oi`, `en`, `wo`)
Walks up `12` ancestor elements (`Za = 12`) from the widget wrapper/iframe to detect clickjacking or hidden-widget abuse (`unexpectedHidden`), reporting reason codes (`vDrs`):
- `dn` — `display === "none"`
- `vh` / `vc` — `visibility === "hidden"` or `"collapse"`
- `op` — `Number(opacity) <= 0.01`
- `cv` — `contentVisibility === "hidden"`
- `dt` — Element is detached (`!isConnected`)
- `zs` — Zero width or height (`rect.w === 0 || rect.h === 0`)
- `tf` — Element is pushed outside the viewport solely by a 2D CSS translation matrix (`new DOMMatrixReadOnly(style.transform)`).

### E. Session Continuity & Hot Self-Upgrade (`_cftscs_`, `Ei`, `Ti`)
- **Session Continuity (`_cftscs_<sitekey>`):** Stores `i.scs` in `localStorage` (up to 512 bytes) when `session-continuity-persist` is enabled.
- **Hot Script Upgrade (`Ei`, `Ti`):** Every 1 hour (`ia = 3600000ms`) or on `reloadApiJsRequest` (with exponential backoff `30s..180s` + ±20% jitter `pu()`), Turnstile stashes its live `widgetMap` on `window.turnstile` behind an unenumerable `Symbol()` (`vn`), replaces its own `<script>` tag with `?_upgrade=true&_cb=<timestamp>`, and seamlessly migrates all active widgets to the new script instance without losing state.

---

## 2. Vue Pinia & DevTools Vendor Chunk (`pinia.JlH1PbuzUC.js`)

The second half of the snippet is a standard vendor bundle containing:
- **`rfdc@1.4.1` ("Really Fast Deep Clone"):** Clones nested objects, arrays, `Date`, `Map`, `Set`, and `ArrayBuffer` views with circular reference tracking (`circles: true`).
- **`hookable`:** Nuxt/Vue async and parallel hook registry (`hook`, `hookOnce`, `callHook`, `callHookParallel`, `beforeEach`, `afterEach`) integrated with Chrome DevTools `console.createTask` for async stack traces.
- **`speakingurl@14.0.1`:** Character transliteration table (Latin, Arabic, Burmese, Czech, Dhivehi, Georgian, Greek, Latvian, Macedonian, Polish, Ukrainian, Romanian, Russian, Serbian, Slovak, Turkish, Vietnamese, and currency symbols) for URL slug generation.
- **`@vue/devtools-kit` & `pinia`:** State store runtime for Vue 3.
