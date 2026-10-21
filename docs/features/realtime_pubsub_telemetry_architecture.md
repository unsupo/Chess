# Feature: Real-Time WebSocket PubSub, Protobuf RPCs & Crash Filtering

**Status:** Reference Architecture — extracted from Chess.com's frontend infrastructure chunks.

## Overview

This document captures the non-UI infrastructure reverse-engineered from Chess.com's frontend chunks:
1. **Real-Time WebSocket PubSub Client (`v1.6.0`)** with `pako` (`zlib`) payload decompression.
2. **Offline HTTP Retry Queue (`GL`)** that flushes failed POST requests when `window` fires the `online` event.
3. **Protobuf v3 / Connect-Web RPC Services** (`UserActivityService`, `SocialService`, `UserMessageService`).
4. **Sentry Crash Reporting & Noise Filter** (`@sentry/browser`).

---

## 1. Real-Time WebSocket PubSub Protocol (`v1.6.0`)

### Frame Types (`P`)
| Code | Name | Purpose |
| :--- | :--- | :--- |
| `"0"` | `OPEN` | Initial handshake frame containing `sessionId` (`t[1]`) |
| `"1"` | `CLOSE` | Server-initiated close with reason code (`t[1]`) |
| `"2"` | `PING` | Client keepalive ping (`[2]`) |
| `"3"` | `PONG` | Server keepalive pong response |
| `"4"` | `MESSAGE` | PubSub channel traffic & control messages |
| `"5"` | `PRESENCE` | Online status, capabilities, and active game/battle links |

### Message Subtypes (`en`, inside Frame `"4"`)
| Code | Name | Format / Behavior |
| :--- | :--- | :--- |
| `"1"` | `SUBSCRIBE` | `[4, 1, channelName, options]` |
| `"2"` | `UNSUBSCRIBE` | `[4, 2, channelName]` |
| `"3"` | `ACK` | `[4, 3, sessionOffset]` — acknowledges sequential messages |
| `"5"` | `SUBSCRIBED` | Confirms subscription; triggers queued message flush |
| `"6"` | `UNSUBSCRIBED` | Confirms channel teardown or returns error (`401`, `403`, `404`, `430`) |
| `"7"` | `MESSAGE` | `[4, 7, channel, payload, compressedFlag, sessionOffset]` |
| `"8"` | `POSITION` | `[4, 8, channel, queuePosition]` |

### Zlib Compression (`vt(e)`)
When a `MESSAGE` (`[4, 7, ...]`) frame has `t[4] === 1`:
1. The payload `t[3]` is Base64-decoded into a `Uint8Array` (`js-base64`).
2. Decompressed via `pako.inflate(bytes, { to: "string" })`.
3. Parsed with `JSON.parse()` before dispatching to channel listeners.

---

## 2. Offline POST Retry Queue (`GL()`, `JL`)

In the `play-computer` bundle:
```js
async function GL() {
  if (KL) return;
  let e = Il(); // Reads queued requests from localStorage
  if (e.length) {
    KL = true;
    try {
      for (let t of e) {
        try {
          await Qi(() => cd.post(t.url, t.data), {
            retries: 3,
            delay: 1000,
            shouldRetry: (err) => !(cd.isHTTPError(err) && err.response.status === 400),
          });
          WL(t.id); // Removes succeeded request from queue
        } catch (err) {
          if (cd.isHTTPError(err) && err.response.status === 400) WL(t.id);
        }
      }
    } finally {
      KL = false;
    }
  }
}
```
- Listens to `window.addEventListener("online", ...)` (`JL`) so any game results or progression updates that failed while offline are automatically re-sent with a 3× retry (`1000ms` delay) as soon as connectivity returns, dropping permanently malformed `400 Bad Request` items.

---

## 3. Embedded Protobuf v3 Services (`@bufbuild/protobuf`)

Decoded from the Base64 file descriptors (`qp(...)`) in the bundles:

1. **`chesscom.user_activity.v1.UserActivityService`** (`/rpc` on `api.chess.com`)
   - `LogActivity(LogActivityRequest) returns (LogActivityResponse)`
   - Verified by Cloudflare Turnstile (`cf-turnstile-response` header) on a 2-hour cooldown per user ID (`activity-tracker` in `localStorage`).
2. **`chesscom.user_profile.v1.SocialService`** (`/rpc` on `api.chess.com`)
   - `ListFollowedUsers(ListFollowedUsersRequest) returns (ListFollowedUsersResponse)`
   - `DoesUserFollowOtherUsers(DoesUserFollowOtherUsersRequest) returns (DoesUserFollowOtherUsersResponse)`
3. **`chesscom.inbox.v1.UserMessageService`** (`/rpc` on `www.chess.com`)
   - `BatchSendUserMessage(BatchSendUserMessageRequest) returns (BatchSendUserMessageResponse)`
   - `CheckCanSendUserMessage(CheckCanSendUserMessageRequest) returns (CheckCanSendUserMessageResponse)`
   - Includes `MessageSendNotAllowedReason` enum: `PRIVACY_FRIENDS_ONLY`, `PRIVACY_NOBODY`, `BLOCKED`, `TRUST_LEVEL`, `SAFE_MODE`, `RATE_LIMITED`, `GUEST_ACCOUNT`, `SENDER_PRIVACY`, `CONTENT_HIDDEN`.

---

## 4. Sentry Crash Filtering (`@sentry/browser`)

- **VIP Override (`enableSentryHP`):** Forces telemetry on for streamers (`isStreamer`), titled players (`chessTitle`), or accounts with linked Twitch/YouTube.
- **Stale Document Gate (`maxDocumentAgeHours = 168`):** Uses `performance.timeOrigin` to ignore errors from tabs open longer than 7 days.
- **60-Second Error Deduplicator (`z(r)`):** Caches error messages in a `Map` with timestamps and drops duplicates occurring within `60,000ms`.
