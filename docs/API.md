# S-UI Plus HTTP API

This document describes how to automate the **web panel** over HTTP. In API terms, a **client** is a sing-box proxy user (row in the `clients` table), **not** a panel administrator.

- **Panel base path** — Configurable (default `/app/`). All URLs below are relative to your panel origin, for example `https://example.com:2095/app/`.
- **Session API** — `{base}api/...` after browser login (cookie session).
- **Token API** — `{base}apiv2/...` with header `Token: <token>` (tokens are created in the panel or via `api/addToken`).

## Response envelope

JSON responses use this shape ([`api/utils.go`](../api/utils.go)):

```json
{
  "success": true,
  "msg": "",
  "obj": { }
}
```

- On failure, `success` is `false` and `msg` contains the error text.
- Many successful `save` calls set `msg` to `"save"` or the affected object name.

## Content types

| Endpoint style | Content-Type |
| --------------- | ------------- |
| `api/save`, `api/login`, `api/addToken`, … | `application/x-www-form-urlencoded` (same as the web UI) |
| `api/importdb` | `multipart/form-data` |

The bundled frontend sets `Content-Type` automatically ([`frontend/src/plugins/api.ts`](../frontend/src/plugins/api.ts)).

---

## Session authentication (`api/`)

1. `POST {base}api/login` with form fields `user` and `pass`.
2. The server sets a session cookie; reuse that cookie for subsequent `GET`/`POST` under `{base}api/`.

---

## Token authentication (`apiv2/`)

1. Log into the panel and create an API token (or call `POST {base}api/addToken` with fields `expiry` (Unix seconds, `0` = no expiry) and optional `desc` while logged in).
2. For each request to `{base}apiv2/*`, send header:

```http
Token: <your-token-string>
```

Invalid or expired tokens return `success: false` with an `invalid token` style message.

---

## Load panel state

```http
GET {base}api/load?lu=<lastUpdateUnix>
GET {base}apiv2/load?lu=<lastUpdateUnix>
```

- `lu` — Last `lastLoad` you saw (integer Unix seconds). When nothing changed, the response may only include fresh `onlines` data.
- On full refresh, `obj` includes `config`, `clients`, `inbounds`, `outbounds`, `endpoints`, `services`, `tls`, `subURI`, `enableTraffic`, `onlines`, etc.

---

## Partial reads

```http
GET {base}api/clients?id=<id>
GET {base}api/inbounds?id=<id1,id2>
```

Same paths work under `apiv2/` with a `Token` header. Omit `id` to list all clients or inbounds.

---

## Save (create / update / delete)

```http
POST {base}api/save
```

Form fields:

| Field | Required | Description |
| ----- | -------- | ----------- |
| `object` | Yes | `clients`, `inbounds`, `outbounds`, `endpoints`, `services`, `tls`, `config`, `settings` |
| `action` | Yes | Depends on `object` (see below) |
| `data` | Usually | JSON string payload |
| `initUsers` | Sometimes | Comma-separated client **numeric IDs** when creating a **new** inbound (`object=inbounds`, `action=new`) |

### Proxy clients (`object=clients`)

| Action | `data` body | Notes |
| ------ | ----------- | ----- |
| `new` | One client object (JSON) | Include `inbounds` as a JSON array of **inbound numeric IDs** from `GET .../inbounds`. Include a `config` object whose keys match inbound types you use (see [`frontend/src/types/clients.ts`](../frontend/src/types/clients.ts) `randomConfigs` for field names per protocol). |
| `edit` | Full client object including `id` | Same shape as the UI edit form. |
| `del` | JSON **number**: database `id` of the client | Example body: `42` (not `"42"`). |
| `addbulk` | JSON array of clients | Bulk create; first element’s `inbounds` drives link generation. |
| `editbulk` | JSON array of clients | Bulk update. |
| `delbulk` | JSON array of numeric ids | Example: `[1,2,3]`. |

**Expiry** — `expiry` is Unix time in **seconds** (`0` means no expiry).

**Single source IP** — Boolean `singleSourceIp` on the client. When `true`, the core tries to keep only one **source IP** active per client name (sing-box user tag). See limitations below.

### Example: create a client with inbound IDs 1 and 2

```http
POST /app/api/save
Content-Type: application/x-www-form-urlencoded

object=clients&action=new&data=%7B%22enable%22%3Atrue%2C%22name%22%3A%22user1%22%2C%22inbounds%22%3A%5B1%2C2%5D%2C%22volume%22%3A0%2C%22expiry%22%3A0%2C%22singleSourceIp%22%3Afalse%2C%22config%22%3A%7B%22vless%22%3A%7B%22name%22%3A%22user1%22%2C%22uuid%22%3A%22...%22%2C%22flow%22%3A%22xtls-rprx-vision%22%7D%7D%7D
```

(URL-decode `data` for readability.) Prefer generating `config` keys to match each selected inbound’s `type`.

### Example: delete client id 5

```http
object=clients&action=del&data=5
```

### Example: set expiry on an existing client

1. `GET {base}api/clients?id=5` to read the current row.
2. `POST {base}api/save` with `object=clients`, `action=edit`, and `data=` full JSON with updated `expiry`.

---

## Subscription URLs

The subscription HTTP server listens on the **subscription port** (default `2096`) with path prefix **`/sub/`** (unless you changed them in settings).

- **Client identifier** — The client’s `name` field is the subscription path segment (`subId`).
- **Base URL** — `GET .../load` returns `obj.subURI` when set in panel settings; otherwise it is derived from request host, subscription port, TLS flags, and `subPath`.

**Plain subscription (default)**

```text
{subURI}{clientName}
```

Example: `http://example.com:2096/sub/user1`

**JSON sing-box outbound**

```text
{subURI}{clientName}?format=json
```

**Clash**

```text
{subURI}{clientName}?format=clash
```

`HEAD` on the same URL returns subscription metadata headers ([`sub/subHandler.go`](../sub/subHandler.go)).

The `links` array on each client (from `load` / `clients`) lists generated URIs and external sources used to build the subscription.

---

## Other useful endpoints

| Method | Path | Purpose |
| ------ | ---- | ------- |
| GET | `{base}api/users` | Panel admin accounts (not proxy clients). |
| GET | `{base}api/settings` | Panel settings map. |
| GET | `{base}api/singbox-config` | Export merged sing-box JSON. |
| POST | `{base}api/restartSb` | Restart sing-box core. |

---

## Single source IP limitation

- Enforcement happens in the panel’s [`ConnTracker`](../core/tracker_conn.go) using **`metadata.User`** (client name) and a client IP derived from **`metadata.Source`** when it is an IP, otherwise from the socket address on TCP.
- If `metadata.User` is empty for a flow, that traffic is **not** limited.
- **UDP / QUIC (including Hysteria2)** — The tracker prefers **`metadata.Source`** (the client address set by the inbound, e.g. [Hysteria2 `NewPacketConnectionEx`](https://github.com/SagerNet/sing-box/blob/dev/protocol/hysteria2/inbound.go)) when it carries an IP, instead of relying on `PacketConn.RemoteAddr()` alone. If `metadata.User` or a usable source IP is missing, enforcement is skipped for that flow.
- Carrier-grade NAT and mobile networks can share one public IP across many devices; this feature limits **observed source addresses**, not physical devices.

When `singleSourceIp` is enabled, a **new** connection from IP **B** causes existing sessions for the same client from other source IPs to be closed so that only **B** remains (last IP wins).

---

## References

- Router registration: [`web/web.go`](../web/web.go)
- Save dispatch: [`service/config.go`](../service/config.go), [`service/client.go`](../service/client.go)
- Subscription routing: [`sub/subHandler.go`](../sub/subHandler.go)
