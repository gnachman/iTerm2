# iTerm2 iPhone Companion — Relay Sharding Design

**Status:** Draft
**Author:** George Nachman
**Last updated:** 2026-07-12

---

## 1. Overview

The iPhone companion device lets a user view a live iTerm2 session on their phone. Two kinds of data flow from the Mac to the phone:

- **Live video** of the active window, streamed in real time.
- **Static PNG tiles** of scrollback history.

Neither device can generally reach the other directly, so traffic is brokered by a **relay**: the Mac and the phone each open a WebSocket-over-TLS (`wss://`) connection to a relay process, which splices the two together. The relay is a **stateful pairing point** — for a given session, the Mac and the phone must terminate on the *same relay process* so their sockets can be joined — but sessions are independent of one another, so the relay is **horizontally shardable**.

Session payloads are **end-to-end encrypted (E2EE)**: the relay forwards ciphertext and cannot read session content. It still terminates TLS on each hop (the transport), so it can authenticate and route the signaling/pairing traffic.

This document describes how the relay process works and how to **shard it horizontally** so that both endpoints of a pairing always rendezvous on the same host — durably across reconnections — while hosts can be added, removed, and rebalanced, and while user-run (self-hosted) relays keep working unchanged.

---

## 2. Goals and non-goals

**Goals**

- Both endpoints of a pairing reliably reach the same relay process, on every reconnect, indefinitely.
- Scale horizontally by adding hosts; drain and remove hosts without breaking existing pairings.
- Fail safe: transient disagreement during operations resolves to a retry, never to a silent split or a wrong pairing.
- Keep the control plane (the thing that decides "which host") from becoming a load-bearing service that must be run HA.
- Terminate TLS on infrastructure we control (signaling trust).
- Support **user-run (self-hosted) relays** as a first-class mode, alongside the managed, sharded fleet.

**Non-goals**

- Peer-to-peer / NAT traversal. There is intentionally no ICE/STUN; **everything goes through the relay**.
- Reading or transcoding session content. The relay is a byte forwarder; media handling stays on the endpoints.
- Server-side persistence of session state. A reconnect re-establishes the splice from scratch.
- Geo-aware placement. Sharding is geography-blind by construction (see §11); a per-geo cluster layer is deferred.

---

## 3. Background: current state

- `relay.iterm2.com` resolves to a single VPS IP. One relay process; no sharding.
- The Mac generates a QR code containing a pairing URL that the mobile client scans:

  ```
  iterm2://pair?v=1&proto=Noise_XK_25519_ChaChaPoly_BLAKE2s&rs=<public key>&pid=<pairing ID>&relay=<relay URL>
  ```

  - `proto` — the E2EE handshake: **Noise XK** (Curve25519 / ChaChaPoly / BLAKE2s). The session is end-to-end encrypted between Mac and phone; the relay only forwards ciphertext.
  - `rs` — the responder's **static public key** (the Mac's). Noise XK pins `rs` in the QR, so the phone authenticates the Mac cryptographically and no party in the middle can impersonate it.
  - `pid` — the **pairing ID**, the durable identifier shared by both devices.
  - `relay` — the relay URL the client connects to **directly**.
- In this mode (`v=1`) the client always connects **directly to the `relay` URL**. Existing beta users are already paired this way.

Direct-to-`relay` is simple and correct for a **single relay**, including **user-run (self-hosted) relays** — a user running their own box just points `relay=` at it, and this format is retained for exactly that (§6.1). What it does not do by itself is support sharding across a fleet, or let a managed service rebalance and survive host loss — which is what the rest of this document adds.

---

## 4. Requirements and constraints

| # | Constraint | Source |
|---|---|---|
| R1 | Adoption is highly uncertain; must be able to scale quickly if it takes off. | Product |
| R2 | Both endpoints of a pairing must land on the same relay process, every reconnect, durably. | Correctness |
| R3 | Must be able to reshard: add/remove/rebalance hosts without breaking pairings. | Ops |
| R4 | TLS terminates on hosts we control; signaling must be trustworthy. | Security |

---

## 5. The Node relay process

The relay is a Node.js process. Because payloads are E2EE, it cannot inspect content — it forwards bytes over WebSocket. Two per-byte costs remain:

1. **WebSocket unmasking.** The protocol requires client→server frames to be XOR-masked, so the relay unmasks every inbound byte on the device→relay leg (relay→device frames are unmasked per spec). Cheap, and native-accelerated if `bufferutil` is installed.
2. **TLS termination.** `wss://` means the relay decrypts inbound TLS and re-encrypts outbound TLS on each hop, even though the *payload* underneath stays E2EE. Bulk TLS is AES-GCM; with **AES-NI** (every modern server CPU) OpenSSL runs it at multiple GB/s per core. Filling a gigabit costs a single-digit percentage of a core, even doing decrypt + re-encrypt.

The expensive part of TLS is the **handshake** (asymmetric crypto at connection setup), but the relay holds long-lived streaming connections, so per-byte handshake cost amortizes to ~nothing. The exception is **reconnect churn** (flaky mobile networks, or a mass reconnect during a reshard) — that's a spiky handshake-CPU event, addressed in §7.

**Conclusion: CPU is not the bottleneck; the port is.** One core roughly fills a gigabit for this workload.

### 5.1 Implementation notes

- **Run one relay process per gigabit box.** Then "same process" ≡ "same box," and there is no intra-box sharding problem — the entire sharding question reduces to "which box." (Only revisit on 10 Gbps boxes; see §11.)
- **Install `bufferutil` (and `utf-8-validate`)** so `ws` unmasks via the native path.
- **Disable `permessage-deflate`** (`perMessageDeflate: false`). Payloads are already-encrypted and incompressible; deflate burns CPU for zero gain and tanks throughput.
- **Honor backpressure.** Watch `socket.write()`'s return / `ws.bufferedAmount`; pause the source when the destination is slow. For live video, shed rather than buffer unboundedly.
- **Optionally offload TLS to nginx/HAProxy** on the box, with Node speaking plain `ws://` on loopback. Native proxies handle TLS termination and handshakes more efficiently and keep the Node event loop lean. TLS still terminates on hardware we control (R4). This on-box proxy is **per box** and only ever handles its own host's traffic; it is not the central, all-seeing load balancer §6 deliberately avoids. No component carries aggregate fleet bandwidth.
- **Set generous idle timeouts.** A parked Mac holds a long-idle socket while it waits for a phone to connect; the app keepalives about every 15 seconds, so the box's proxy and Node idle-reap timeouts must comfortably exceed that, or parked Macs are silently dropped and the failure surfaces only as "the phone cannot connect."

### 5.2 Transport caveat

WebSocket rides TCP, so under packet loss you get head-of-line blocking: a dropped packet stalls the stream until retransmit, showing up as a **stutter/freeze** rather than a graceful quality dip (as UDP/WebRTC would). This is the tax for WS's easy NAT/firewall traversal. The mitigation is app-side (the bitrate/frame-rate throttles, or dropping to tiles under sustained loss).

### 5.3 Bandwidth budget and per-room quota

Bandwidth, not CPU, is the cost that matters, and the motivation for self-hosting is a **predictable** bill. Plan for it explicitly.

- **Budget in egress, not port speed.** Relayed media is 2x on the box's uplink (in from one endpoint, out to the other). Put each box on a plan with a **hard or alertable egress cap**, so a runaway session or an abuse spike cannot produce an unbounded bill. That cap is the whole reason for running our own boxes rather than a metered cloud.
- **Keep the per-room daily byte quota.** It is the per-session cost bound (`DEFAULT_DAILY_BYTE_QUOTA` today). It is host-local and resets on a move or restart, which is safe (§6.7). Tune the default up for video, but keep it finite: it is what caps one pairing's worst-case daily bytes, and it matters more now that the bytes are billed to us.
- **Capacity unit: N concurrent max-bitrate streams per box.** A splice is single-host, so **one video room cannot be split across boxes**; the per-room hotness of §6.2 is the granularity floor. At a few hundred sessions per gigabit box the law of large numbers smooths the count, but a single very heavy room still lands wholly on one box, so size for the heavy case.
- **The control plane carries only kilobytes.** The CDN shard map (and a redirect director, if one is ever added) never touches media, so it cannot contribute to a bandwidth bill. No shared component ever sees aggregate fleet bandwidth.

---

## 6. Sharding architecture

### 6.1 Two rendezvous modes

The pairing URL selects how the client finds a relay:

- **Direct mode (`relay=<url>`, `v=1`).** The client connects straight to the named relay. This is what existing beta users have, and it is ideal for a **self-hosted single relay**: a user running their own box just points `relay=` at it. **Retained unchanged** — no shard map, no resolver.
- **Resolved mode (`resolver=<url>`, `v=2`).** The QR carries a **resolver URL instead of a relay URL**. The client fetches the shard map from that resolver, computes the owning host from the pairing, and connects there. This is the mode the managed iTerm2 fleet uses, and it is what makes horizontal sharding possible. A self-hoster who wants to shard across several of their own relays can likewise run a resolver and emit `v=2`.

Clients understand both; the mode is chosen by which parameter is present (`relay=` → direct, `resolver=` → resolved), with the version bumped to `v=2` for resolved pairings. **The rest of §6 describes resolved mode.**

**Why resolved mode exists (R2/R3).** Both endpoints of a pairing must reach the same relay process, on every reconnect, durably. Baking a specific relay into the QR hard-binds a durable pairing to one box — fine when the user *owns* that box (self-hosting), but wrong for a managed fleet that must rebalance and survive host loss: if that box dies or is retired, every QR that pointed to it is dead. Resolved mode fixes this by carrying a **stable resolver URL** and resolving the host at connect time from **`roomName`** (derived from the `rs` and `pid` already in the QR).

### 6.2 Two-level mapping: roomName → bucket → host

```
roomName = SHA256(canonical("iterm2-room", [rs, pid]))   // already computed by both devices (RelayRoom)
bucket   = uint16be(roomName[30], roomName[31])           // last two digest bytes -> [0, 65535]
host     = shardMap[bucket]                               // mutable; the reshard knob
```

The sharding key is **`roomName`**. Note it is **not** a bare `SHA256(rs ‖ pid)`: it is the existing `RelayRoom` derivation, a SHA256 over a domain-separated, length-prefixed canonical encoding (`CanonicalEncoding.encode` with domain `"iterm2-room"` over the fields `[rs, utf8(pid)]`), rendered lowercase hex. Both devices and the relay already compute exactly this value (it is the `x-relay-room` header), so the shard layer must reuse it verbatim; reimplementing a plain concatenation would silently break rendezvous with every existing client. Because the output is a SHA256 it is uniformly distributed, so the bucket is just a **slice of the digest**: no separate hash function and no modulo bias. Uniformity holds for the **number of pairings** per bucket. It does **not** follow that bytes-per-bucket are uniform: one high-bitrate video room can outweigh many idle ones, so treat buckets as balancing connection count, not bandwidth (see the capacity note in §5.3 and the hotness caveat in §11).

- **`N_BUCKETS = 2^16 = 65536`**, taken as the low 16 bits of `roomName`. A power of two makes the bit-slice exactly `roomName mod 65536` with zero modulo bias. 65536 buckets is ample granularity (4× Redis Cluster's 16384) — with 8 hosts you move load in ~0.0015% increments — and, like any bucket count, it is **chosen once and immutable**: changing it rehashes every pairing. Buckets are permanent; **hosts are the movable layer underneath.**
- **Pin the extraction exactly and identically** across Swift (Mac + iPhone) and Node (hosts): the two bytes are indices 30 and 31 of the **32 raw digest bytes**, big-endian (`bucket = roomName[30] << 8 | roomName[31]`), i.e. the two bytes whose hex is the last four characters of the 64-char `x-relay-room` header. A mismatch here silently breaks rendezvous, so ship a **test vector** (a fixed `roomName` mapping to an expected bucket) verified in every codebase.

Same `roomName` → same bucket → same host, **by construction**, for both devices — as long as both read the same shard map version. That last clause is what §6.4 makes safe.

### 6.3 The shard map is a static file on a CDN

The "resolver" is **not a service** — it is a **static, versioned JSON file** served from a CDN, mapping bucket ranges → hostnames. Its URL is the `resolver=` value carried in the QR:

```json
{
  "version": 37,
  "ranges": [
    { "low": 0,     "high": 32767, "host": "relay1.iterm2.com" },
    { "low": 32768, "high": 65535, "host": "relay2.iterm2.com" }
  ]
}
```

The `host` is a full relay hostname (the managed fleet names them `relay1.iterm2.com`, `relay2.iterm2.com`, ...; a self-hosted resolver may use any names), so the map is domain-agnostic and no host pattern is baked into the client. The file does **not** carry `n_buckets`: it is fixed forever (Appendix A invariant 1), so the client owns the constant and the ranges simply tile `[0, N_BUCKETS - 1]`. A carried value could only ever be 65536, so it would be a second source of truth that must agree with the compiled-in constant; omitting it removes the mismatch entirely.

This directly retires the "resolver overloaded / unavailable" worry: a tiny static asset on a CDN is effectively always-available and unlimited-throughput. It is the well-trodden "versioned config/shard map on a CDN, polled by clients" pattern.

The bucket space is a **ring**, not a line segment: buckets `0` and `65535` are adjacent (the digest wraps), so `0` is not a special boundary. A host owns one or more **arcs** of that ring, each written as a `{low, high, host}` range. A single arc that crosses the `0`/`65535` seam serializes as two ranges sharing the same host (e.g. `{60000, 65535, H}` and `{0, 5000, H}`); a host may also hold several disjoint arcs for balancing or hot-slice isolation (§7.5). The ranges must partition `[0, 65535]` exactly, with no gap or overlap. This ring framing is what makes churn minimal when hosts change (§7.5).

**One URL, always the latest.** The map lives at a single well-known path under the resolver (`shardmap.json`), served with a short TTL and replaced atomically on publish, so one fetch always returns the current map. There is deliberately **no** separate version pointer and no second round-trip: the map carries its own `version`, so a client or relay that reads a briefly-stale copy from a lagging CDN edge just sees an older version and ignores it (monotonicity, §6.6). A short TTL bounds staleness; atomic replacement prevents torn reads. The immutable-versioned-file trick (keep the big map cached forever at `shardmap-vN.json`, poll a tiny pointer for changes) pays off only when the blob is large; this map is `O(hosts)` ranges, a fraction of a KB, so re-fetching it on every poll costs almost nothing and is not worth a second request or the pointer/map consistency it would introduce. Nothing ever loads an *old* version (rollback is roll-forward, §6.4), so addressing a specific version buys nothing.

### 6.4 Client behavior (both endpoints)

Both the phone (which joins) and the Mac (which parks and waits) run the same resolution. On (re)connect:

1. Compute `roomName` via the `RelayRoom` derivation (§6.2) from the QR fields, then `bucket = uint16be(roomName[30], roomName[31])`.
2. **Connect immediately to the last-known host** for this pairing (a cached `bucket → host` *hint* — epoch-free; the client does not reason about ownership).
3. **In parallel, fetch the shard map** (`shardmap.json`) from the QR's `resolver=` URL. If it names a different host for the bucket, **tear down the old connection and reconnect to the new host.**
4. **Ignore any map older than the newest version already seen** (monotonicity — see §6.6).
5. If a host **rejects** the connection (it doesn't own the bucket), or the connect fails, **re-fetch the map and retry** after a short jittered delay. A re-resolve signal is specifically an **HTTP 421** on connect or a **WS 4421** close on a live socket (§6.9); the other status and close codes listed there mean retry the same host, not re-resolve.

A brand-new pairing has no cached host, so step 2 is a cache miss and it just uses the freshly fetched map.

**The Mac re-parks on a reshard.** Because the Mac holds a long-lived park, moving a bucket must move its park too: the old host closes the Mac's connection for the moved bucket (§6.5), and the Mac re-resolves and re-parks on the new owner. Rendezvous depends on this. If the Mac did not follow the map, a phone that resolved to the new host would find no Mac parked there. The phone's reconnect and the Mac's re-park converge on the new host once propagation completes.

**Persist the highest version seen.** Monotonicity (§6.6) must survive an app relaunch, or a freshly launched client could accept an older map from a stale CDN edge; store the last-seen version durably. A consequence: rollback is roll-forward. A bad map `vN` is corrected by publishing `vN+1`, never by republishing a lower version, which every actor would ignore.

### 6.5 Host behavior

A host is **resharding-aware**: it holds its current owned-set, and on every map reload it diffs the new owned-set against the old one to derive what it just *acquired* and what it just *relinquished*, then treats the two asymmetrically.

- On boot, **fetch the map before accepting connections** (so it knows which buckets it owns).
- **Newly admit a connection only if the host's own copy of the map says it owns that bucket; otherwise reject** ("reject-on-doubt"), signaling the client to re-resolve with **HTTP 421** (§6.9). If the host knows the current owner, it may *redirect* (à la Redis Cluster `MOVED`) by adding an `x-relay-owner` header, to save the client a round-trip.
- **Reload on version bump** (periodic re-fetch of the map, §6.8), then apply the diff:
  - **Newly acquired buckets are usable immediately.** Begin accepting for them at once; there is nothing to ramp, since a client reaches this host only because the map already named it the owner. An established room whose verifier this host lacks simply self-heals on first contact (§6.7).
  - **Relinquished buckets are evicted gradually, and only after a delay.** New joins for a relinquished bucket reject immediately (reject-on-doubt, so the split never grows), but existing spliced rooms keep running untouched for `RESHARD_DRAIN_DELAY` (default **2x the poll interval**, §7.4), by which point the gaining host has almost certainly also polled and is already accepting. Only then does the host begin closing those rooms, at a configured rate of **X rooms/second**, each close using the **WS 4421** re-resolve code (§6.9) to prompt its clients to re-resolve to the new owner.
- **A successfully fetched map that assigns this host zero buckets is a valid state, not an error.** It means "drain to empty" (a decommission): acquire nothing, evict everything gradually, then sit idle while still polling. This must be distinguished from a fetch failure below: a published empty assignment *drains*; an unreachable map does *not*.
- **On fetch failure, keep last-known-good** — never fail-open (accept everything) or fail-closed (reject everything) on a CDN blip, and never confuse "couldn't fetch" (hold) with "fetched, own nothing" (drain).

Each host only needs to know **the buckets it currently owns** (plus the ones it is mid-drain relinquishing) — never the global map, never other hosts' assignments. So there is no distributed map-replication problem; there is a small local view that only has to be *safe when stale*, not *synchronized*.

### 6.6 Why races are safe (the correctness argument)

Separate two properties. The **local rule**, always held: **a host serves a bucket only if its own current map version says it owns it.** The **global property**, a single accepting owner at any instant, holds only under two-phase publish or after propagation converges; single-write publish deliberately relaxes it to a brief self-healing split (§7.2). The local rule is what prevents a *wrong* accept, and it is upheld not by synchronizing views but by:

- **Reject-on-doubt:** a host *newly admits* a bucket only if its own current view says it owns it. Any disagreement between a client's cache, a CDN edge, and a host's view collapses to *reject → retry*, never to a wrong accept. Reject-on-doubt governs new joins; a relinquished bucket's *existing* rooms drain at the eviction rate (§7.4), so their split window is bounded by drain time rather than propagation time. That is a longer but still bounded, still safety-preserving window: a rendezvous glitch at worst, with Noise backstopping security throughout.
- **Monotonic versioning:** every actor ignores any map older than the newest it has seen. Without this, multi-edge CDN version skew (edge A serves v37, edge B still serves v36) makes clients flap between hosts and the system may never visibly settle. With it, every actor moves strictly forward, and once publishing stops, everyone converges on the highest version.

The client's optimistic "connect to cached host, verify in parallel" and the host's reject-on-doubt compose cleanly: the **only** time a cached reconnect misses is during a reshard, and a reshard is an operator/driver-initiated event — so the map (CDN) is by definition being served at that moment. Cache-miss coincides with map-availability. There is no steady-state dependence on the control plane at all.

### 6.7 Relay state model and self-healing reconnect

Each host keeps three kinds of per-room state. Classify them by whether they must survive a host change, and none of them forces migration between hosts.

- **Ephemeral** (single-use tickets, registration tokens, App Attest challenges, live sockets, in-memory rate windows). These do not survive a hibernation or restart today; on a bucket move they are simply gone and the client retries. Nothing to move.
- **Cost** (the per-room daily byte quota, §5.3). Host-local; it resets when the bucket moves or the host restarts. Safe, because a bucket move is an operator-initiated event an attacker cannot trigger, so a reset is not an abuse lever. Worst case a room slightly exceeds its daily budget across a reshard.
- **Reconnect-auth** (`verifier`, `registrantKeyId`, assertion counter). The only durable-looking state, and it is **soft state**. The join verifier is deterministic: `verifier = HKDF(roomSecret)` (`RelayJoin`), and `roomSecret` is persisted on **both** devices (the phone mints it and keeps it; it is couriered to the Mac over the Noise channel and kept there). Both roles sign their joins with that one shared key (over the `(role, nonce, roomName, origin)` transcript of §6.10, not `roomName` alone), and the relay stores only the public verifier. So a host that lacks the verifier just treats the room as unestablished, and the phone re-registers the identical value.

**Self-healing flow.** When a bucket lands on a host that has no verifier for it (a fresh box after a move, restart, or death):

1. The phone reconnects and attempts a signed (established) join.
2. The host, having no verifier, is in pairing mode and answers `"ticket required"` (or the explicit `"unestablished"` signal of §6.5).
3. The phone falls back **silently, with no QR and no SAS**: it runs App Attest to earn a ticket, reconnects with it, receives a registration token, and re-registers `verifier(roomSecret)`. It may mint a fresh App Attest key; the relay lost `registrantKeyId` too, so nothing needs to match, and the new key's assertion counter starts fresh.
4. The **Mac needs no action.** On a verifier-less host its signed park is admitted as a pre-auth park (the signature is ignored in pairing mode), and once the phone re-registers, the Mac's later signed parks verify again against the restored verifier, because both sign with the same `HKDF(roomSecret)` key.

The counter reset is replay-safe: assertions are bound to single-use, server-minted challenges, and each host mints its own, so a captured assertion cannot be replayed on a different host regardless of the counter. The counter is defense in depth on top of challenge freshness, so resetting it opens no window.

**The residual cost (DoS-only).** Each verifier loss reopens the first-registration slot on the new host. In the window between the move and the phone's re-registration, an attacker who both knows the `roomName` and can pass App Attest could register a **bogus** verifier and lock the legitimate devices out: their signed joins would then fail to verify. This is availability-only. Noise XK still authenticates the Mac end to end, so a bogus verifier can block reconnect but cannot read content or impersonate an endpoint. It is doubly gated (roomName secrecy, meaning a scanned QR, plus App Attest, meaning the real app on a real device), and the window shrinks with prompt, jittered phone reconnect (§7.3). Recovery is to re-pair. §11 lists an address binding that would close the race outright.

This is what lets Appendix A invariant 5 hold by construction: the relay keeps no durable per-pairing state that must survive a host change, so a bucket's home is reassignable at will and a dead host hands nothing off.

### 6.8 How relays learn of map changes

Relays learn of a new map the same way clients do, by **periodic polling of the CDN map file** (§6.3), not by a push from a central coordinator. This preserves the "no load-bearing HA control plane" goal: there is no fleet roster to maintain and no host to actively notify, and a rebooting relay just fetches the current map on boot.

- **Poll cadence.** Each relay re-fetches the short-TTL `shardmap.json` every `SHARDMAP_POLL_INTERVAL` (a few seconds to a minute, operator's choice); when the fetched map's `version` exceeds the one it holds, it applies the §6.5 diff (an equal-or-older version, e.g. from a lagging edge, is ignored).
- **Monotonic + integrity, same as clients (§6.6, §9).** A relay polling a multi-edge CDN can read an older version from a lagging edge, so it ignores any version older than the newest it has seen. It fetches over HTTPS from our domain and, if the map is signed, verifies the signature before adopting it, since it enforces ownership from this file.
- **Reload latency bounds reshard convergence.** A relay that has not yet polled keeps accepting for buckets it lost and has not begun draining relinquished ones. Correctness holds (reject-on-doubt + monotonic + bounded split, §6.6), but the reshard has not *taken effect* on that host until it reloads. So `SHARDMAP_POLL_INTERVAL` is the knob for how fast a reshard lands (traded against poll traffic), and it is also what sets the drain-start defer of §7.4.
- **Config, not QR.** Relays get the map base URL and poll interval from their provisioning config; clients get the resolver URL from the QR. A managed relay is also provisioned with its own hostname, the single string that is its TLS-cert name, its map identity (the `host` entries it owns), and the base of its proof origin (§6.10).
- **Optional push is trigger-only.** If lower latency is ever wanted, a push may tell relays "a newer version exists, go fetch," but it must never carry map contents (the CDN stays the single source of truth), and polling stays the floor so a missed push cannot strand a host.

### 6.9 Re-resolution wire codes

Sharding adds one new instruction the relay must be able to give a client: not here, go re-resolve. Every item in the client and relay work lists depends on these numbers being fixed, so they are pinned here rather than left to each implementation to invent. There are two re-resolve codes, because the signal originates from two different places, and every pre-existing code keeps its "retry the same host" meaning.

**Re-resolve (leave this host).** The client must not retry the same host. It uses the owner hint if one is present, otherwise refetches the shard map, then connects to the owner.

| Origin | Code | Cause |
|---|---|---|
| A WebSocket upgrade, or an HTTP data-plane request (`/attest`, `/register`, `/delete`) | **HTTP 421 (Misdirected Request)** | The host does not own this bucket (reject-on-doubt, §6.5), or the bucket currently has no owner (two-phase drain, §7.2). |
| A live, already-spliced WebSocket | **WS close 4421** | The room was evicted by a reshard; its bucket moved (§7.4). |

421 is chosen because RFC 7540's "misdirected request", a request that reached a server unable to produce the response, is precisely reject-on-doubt. 4421 lives in the WebSocket private-use range (4000 to 4999) and deliberately echoes 421, so both re-resolve signals carry the same number across the two code spaces. They remain distinct codes with distinct handling: 421 is returned before or without an open socket (admission time), while 4421 closes a socket that is already spliced (eviction time). A client cannot confuse the two, and neither belongs to the retry-here set below.

Because some client WebSocket stacks (for example `URLSessionWebSocketTask`) expose only a fixed enum of close codes and cannot surface an arbitrary 4xxx number, the 4421 close also carries a machine-readable **reason** that begins with the ASCII sentinel `reshard`. A client detects re-resolve as `closeCode == 4421` OR `reason` begins with `reshard`. This mirrors the existing daily-quota close, already matched on both its `1008` code and a `quota` reason substring (`host/server.js`), so the belt-and-suspenders pattern is not new.

**Owner hint (optional, MOVED-style).** When the rejecting or evicting host knows the current owner from its own map, it may name it so the client can skip the map-refetch round-trip:

- On HTTP 421: an `x-relay-owner: <hostname>` response header.
- On WS 4421: the reason is `reshard <hostname>` (the owner follows the sentinel and a single space).

The hint is advisory. A client that cannot read it, or that receives a bare 421 with no header (or a reason of just `reshard`), must fall back to refetching the map, which resolved mode already does in parallel (§6.4). A host in the two-phase "no owner" state has no owner to name and always sends the bare form. A client that follows a hint still updates its cached `bucket -> host` hint and confirms it against the map it fetches regardless, so a stale hint self-corrects on the next version.

**Retry here (transient; keep the cached host).** Unchanged by sharding, and explicitly not a re-resolve. Back off with jitter and reconnect to the same host.

| Code | Cause | Client action |
|---|---|---|
| WS close 1001 | Host going away (graceful restart or shutdown, §7.1) | Reconnect to the same cached host after a short delay. If the box was actually decommissioned, the map has already moved the bucket and this reconnect earns a 421, which then re-resolves. This is exactly why 1001 stays retry-here: the 421-on-reconnect covers the retire case, so no dedicated retire code is needed. |
| WS close 1011 or 1006 | Internal error or abnormal close | Same host, jittered backoff. |
| HTTP 429 or 503 | Rate limited or at capacity | Same host, jittered backoff. |
| HTTP 500 | Transient internal error | Same host, jittered backoff. |

**Long backoff (host-local exhaustion).**

| Code | Cause | Client action |
|---|---|---|
| WS close 1008 | Daily byte quota exhausted (§5.3) | Same host, but do not hammer: the quota is host-local and resets on the next day or on a bucket move. Back off long. |

**Fatal (do not blind-retry).** HTTP 403 (entry-gate reject) and 413 (payload too large) are client or configuration errors, not transient. Surface them instead of looping.

The rule that ties this together: a re-resolve code (421 or 4421) is the only thing that moves a client to a different host; every other code keeps it on the one it has. That single invariant is what lets cached-host optimism (§6.4) and reject-on-doubt (§6.6) compose, and it is why the retire path needs no code of its own.

### 6.10 Host identity and the proof origin

Three of the relay's checks bind an **origin** into the bytes they verify, and the design has so far been silent on it:

- The **admission (join) transcript** both roles sign is over `(role, nonce, roomName, origin)` (`RelayJoin`), not `roomName` alone.
- The **App Attest clientData** the phone attests and asserts over is `SHA256(challenge ‖ origin)`.
- The **delete-room transcript** that authorizes an unpair is over `(challenge, roomName, origin)`.

In each case the client signs or attests over the origin and the relay recomputes it and verifies. If the two strings differ by a single byte, every signature and attestation fails, and the symptom is not a connection error (the socket connects fine) but "bad signature" on every join. The origin is therefore a correctness-critical shared constant that both sides must derive identically. It is invisible at the level §6.7 and §9 describe the join crypto ("both roles sign their joins"), so a fleet built from that description alone would ship with every signed join failing, which is why it is called out here.

**One provisioned hostname, three uses.** A managed box is provisioned with exactly one hostname (for example `relay1.iterm2.com`), and that single string is the source of truth for three things that must never disagree:

1. Its **TLS certificate**: the cert SAN is that hostname (the on-box proxy of §5.1 obtains a certificate for exactly that name).
2. Its **map identity**: the box owns the buckets of every shard-map range whose `host` field equals this hostname. This is the answer to "which line of the map is mine" (§6.5).
3. Its **proof origin**: `origin = "https://" + hostname`.

Because all three derive from the one provisioned value, they cannot drift on a correctly configured box: the name the client reached over TLS, the name that assigned it the bucket, and the name in the signed transcript are the same name.

**The origin is server-side, never the `Host` header.** The relay takes its origin from provisioning config, not from the incoming request's `Host` header. A client-supplied header must not be able to move the signed bytes, and the on-box proxy may rewrite `Host` anyway. The client does not need to send the name for the relay to agree on it: the client connected to `https://hostname` and TLS validated the certificate whose SAN is that hostname, so the certificate is the shared anchor that pins both ends to the same string with no trusted header in the loop.

**The client's construction rule.** In resolved mode the client forms `origin = "https://" + host`, with the shard-map `host` field taken verbatim and no normalization (`ShardHostResolver`). So the published map `host`, the box's provisioned hostname, and the origin the relay verifies must be byte-identical. To keep them so, the token stays in one canonical form everywhere: lowercase ASCII (punycode a-labels for an IDN), no trailing dot, and no port unless the box serves on a non-443 port, in which case the `host:port` authority is the token in all three places. In direct mode the origin instead comes from the QR's `relay=` value, canonicalized identically on both devices (`PairingCode.canonicalRelayOrigin`), and the self-hosted box is configured to match; no map is involved.

So publishing a box into the map is not only a routing edit. The `host` string written into a range is simultaneously the name that box's certificate must cover and the origin its clients will sign against, so it must equal the box's provisioned identity exactly. A mismatch does not fail at connect time; it silently breaks every proof for that box's buckets.

---

## 7. Resharding and operations

### 7.1 Add / remove / rebalance

To make any sharding change: **update the shard map file, bump the version.** Hosts reload and drop connections for buckets they no longer own; those reconnect and land on the new owner. Clients re-fetch on the version bump (or on rejection) and follow. It doesn't matter if hosts reload at slightly different times — reject-on-doubt + monotonic versioning make the interleaving safe, and it settles once propagation completes.

- **Add a host:** provision it, give it a DNS name under the wildcard, publish a map that carves it some bucket ranges (minimal-churn carve, §7.5).
- **Decommission / drain a host:** reassign its ranges to live hosts in the map (merge into neighbors, §7.5), publish; the draining host closes those connections; retire the box once empty. Draining depends on the host actually observing the new map (it closes moved buckets only on reload); a host partitioned from the CDN keeps serving under last-known-good (§8), so a host that cannot reach the map must be hard-stopped to complete the drain.
- **Rebalance:** move bucket ranges between hosts in the map. Prefer the minimal-churn edits of §7.5; a full re-equalization is a deliberate, higher-churn event.

### 7.2 Split vs unavailability during a move (choose per taste)

When a bucket moves from `H_old` to `H_new`, there is a propagation window bounded by the max staleness of any host's view (map TTL + host poll interval; shrink further with CDN purge-on-publish).

- **Single-write publish (simplest):** brief, self-healing **split** possible — if a client reads the new map before `H_old` has evicted its copy of the room (§7.4), one endpoint can be on `H_old` and the other on `H_new` until `H_old` evicts that room and kicks the straggler. Gradual eviction paces these per room at the drain rate rather than dropping them all at once. For real-time video each is a few-second reconnect glitch during an operator-initiated reshard. Recommended default.
- **Two-phase publish (zero split):** publish the bucket as "draining / no owner" (both hosts reject it with a bare **HTTP 421**, §6.9, so clients re-resolve and retry), wait one reload interval, then publish the new owner. This is break-before-make: brief **unavailability** for that bucket instead of a brief split, and never two accepting owners. Reach for it only if a split-glitch ever proves unacceptable.

Do **not** do make-before-break (assign the new owner before the old relinquishes) — that's the one ordering that permits two simultaneous accepting owners.

### 7.3 Reconnect / handshake storms

A reshard (or a host death) kicks a batch of connections that all reconnect at once, and **each reconnect is a TLS handshake** — the expensive part of TLS. Mitigate by:

- **Resharding gradually** — move a few bucket ranges per publish, not a whole host at once.
- **Jittered client reconnect backoff** — spread the handshake load over time.
- **Rate-limited eviction on the relinquishing host** — the drain of §7.4 is itself a primary handshake-storm control, capping the reconnect rate a move imposes on the new owners.

### 7.4 Gradual eviction of relinquished buckets

Acquiring and relinquishing buckets are deliberately **asymmetric**:

- **Acquire fast.** A newly assigned bucket is usable the instant the host sees the map. There is nothing to ramp: the host is only declaring willingness to serve, and a client reaches it only because the map already named it the owner. Established rooms whose verifier this host lacks self-heal on first contact (§6.7).
- **Release slow.** Relinquishing means actively closing live splices so those rooms reconnect elsewhere, and each reconnect is a TLS handshake on the new owner (§7.3). Dropping a whole host's rooms at once is a handshake storm. So a host **evicts relinquished rooms at a configurable rate, X rooms/second** (`RESHARD_EVICTION_RATE`), rather than all at once.

Mechanics:

- **Defer the start of the drain.** With periodic polling (§6.8), the host that *gained* a range and the host that *lost* it see the new map at different times, up to one poll interval apart. If the loser began evicting the instant it reloaded, it could kick rooms toward a gainer that has not polled yet and would reject them (reject-on-doubt), bouncing those clients until the gainer catches up. So the loser waits `RESHARD_DRAIN_DELAY` (default **2x `SHARDMAP_POLL_INTERVAL`**) after it observes the relinquishment before starting to drain: one interval covers the worst-case poll-phase skew between two hosts reacting to the same publish, and the second is margin for map TTL, CDN edge propagation, and poll jitter. Newly *acquired* buckets are still accepted immediately, there is no downside to accepting early, only to evicting early. Worked example, 1-minute poll: a host that at reload sees it lost buckets 0-1000 and gained 2000-3000 accepts 2000-3000 at once, leaves the 0-1000 rooms running, and only at the 2-minute mark begins draining 0-1000 at X rooms/second. If a newer map arrives during the delay, recompute the deadline from that latest change (or cancel the drain entirely if the bucket is re-acquired, below).
- **Evict per room, atomically.** The unit is a room (both its endpoints), not a socket. Close the Mac and phone sockets for a room together so they re-resolve and re-land on the new owner together; closing one but not the other would strand the peer until it drifts.
- **New joins for a relinquished bucket reject immediately, even during the defer window.** Only *existing* spliced rooms drain slowly; the host never *newly* admits a bucket it no longer owns. The motivation is to avoid the worst outcome, the Mac and the phone ending up on *different* servers. An existing room is already whole on this host (both endpoints were spliced here), so it stays consistent until drained atomically; but if the host accepted a *latecomer* for a relinquished bucket, that endpoint would land here while its peer resolves via the fresh map to the new owner, splitting the pairing across two servers. Worse, that wrongly-placed client would not be corrected until the drain reaches it, which is up to `RESHARD_DRAIN_DELAY` plus its position in the eviction queue later, a long time to sit split. Rejecting immediately instead bounces the newcomer to the new owner at once, so both endpoints converge there together, and keeps reject-on-doubt intact, bounding the split (§6.6) to rooms that were already live at publish time.
- **Signal re-resolve on the close.** Evict with the dedicated **WS close code 4421**, whose reason begins with the sentinel `reshard` and may carry the new owner (§6.9), so the client skips its cached-host optimism and refetches the map (or jumps straight to the named owner), landing on the new owner in one step.
- **Cancel eviction on re-acquire.** If a later map returns a still-draining bucket to this host, drop it from the eviction queue: it is ours again, and its live rooms never needed to move.
- **The rate is the fleet knob.** X bounds the reconnect/handshake load a drain imposes, and that load lands on the new owners, so size X to what a single target host absorbs in handshakes per second. If a drained host's ranges fan out to several new owners the per-target rate is lower still, and jittered client backoff (§7.3) spreads it further.

**Draining a host to empty is just this with every bucket relinquished:** the host acquires nothing, waits `RESHARD_DRAIN_DELAY`, evicts all its rooms at X/second, and once empty sits idle (still polling) until retired (§7.1). A published map assigning it zero buckets is the trigger, and it is a normal state, distinct from a failed fetch (§6.5). End-to-end, a bucket's move takes roughly `RESHARD_DRAIN_DELAY` plus `rooms / X` to fully converge; reshards are not urgent, so this latency is a feature (it paces the handshake load), not a cost.

### 7.5 Minimizing churn when adding or removing a host

The map is edited to move as few buckets as possible, so a membership change disturbs only the buckets that actually changed owner (and, by extension, only their rooms need to re-resolve and drain). This is **consistent hashing**, specialized to the bucket ring of §6.3: each host owns one or more contiguous **arcs**, and the minimal-churn property is a discipline on how the map is *edited*, not a separate algorithm or a live hash function.

Two rules, both operations on the ring:

- **Add a host:** carve its arc out of existing arcs, straddling a boundary so it pulls roughly `1/K` from its neighbors (K = new host count). Only the carved buckets move. Existing boundaries elsewhere on the ring do not move, so their buckets stay put.
- **Remove a host:** merge its arc into an adjacent host (or split it across a few). Only the departed host's buckets move.

Worked example (the ring makes the seam a non-issue):

```
1 host:   H1 owns the whole ring
+H2:      H1 [0..32767]   H2 [32768..65535]                    // ~1/2 moves, to H2
+H3:      H1 [0..21844]   H3 [21845..43689]   H2 [43690..65535]
          // H3 carved straddling the old H1|H2 boundary: ~1/3 moves, split from both.
-H3:      H1 [0..43689]   H2 [43690..65535]                    // only H3's buckets move, into H1
```

Each step moves the theoretical minimum (~`1/K` onto a newcomer is exactly what balance requires), and the map stays `O(hosts)` ranges.

- **The seam is not special.** Because the space is a ring (§6.3), a carve or merge may cross the `0`/`65535` seam; the affected host then holds a wrap arc, written as two ranges. Since buckets are uniform, *which* point is called `0` is immaterial, so you can equally keep every host to a single non-wrapping range by choosing cuts that avoid the seam. That is a cosmetic preference, not a requirement.
- **Multiple ranges per host are normal.** They arise from a wrap arc, from carving a hot sub-range out of the middle of an arc (§6.2 hotness: the original host keeps the two flanking pieces), or as a balancing lever (hand an under-loaded host a second small arc). The map format is already a list, so this needs no schema change.
- **Uniform buckets mean equal width is equal load.** A room's bucket is a slice of a SHA256, so balancing is just sizing arc widths by eye; there is no skew to model.
- **Rendezvous / scatter hashing was rejected on purpose.** It assigns each bucket independently, producing a sprinkle of non-adjacent buckets per host that cannot be expressed as a few contiguous ranges. It would explode the compact range file into thousands of fragments and is harder to reason about and configure. Contiguous arcs keep the map small and operator-legible.
- **The equal-vs-minimal tension.** You cannot keep arcs exactly equal *and* minimize churn: equalizing moves boundaries, and every moved boundary migrates buckets. Day-to-day add/remove follows the minimal-churn rules and lets widths drift slightly; when drift (or an accumulation of hot-slice carve-outs) gets untidy, do a **deliberate rebalance**, republish a cleaned-up, roughly-equal map as one planned, higher-churn event, paced by the same defer + drain machinery (§7.4).

---

## 8. Failure modes

| Scenario | Behavior | Mitigation |
|---|---|---|
| Host dies | Its pairings drop; reconnects to it fail. | Reassign its ranges in the map; clients re-resolve to the new owner and the phone re-establishes the soft verifier on the new host (§6.7). Nothing migrates. |
| Verifier absent on the owning host (after move/restart/death) | Host treats the room as unestablished. | Phone silently re-attests and re-registers the deterministic `HKDF(roomSecret)` verifier (§6.7); the Mac recovers with no action. |
| Attacker grabs the verifier slot during the re-register window | Legit signed joins fail to verify; reconnect blocked. DoS only; content stays safe via Noise. | Gated by roomName secrecy plus App Attest; prompt jittered phone reconnect shrinks the window; recover by re-pairing (§9, §11). |
| Shard map (CDN) briefly unavailable | Steady-state reconnects still work off cached host + host-side ownership check. Only new pairings and reshards need the map. | CDN availability; last-known-good on hosts; monotonic client cache. |
| CDN version skew across edges | Clients could read an older map after a newer one. | **Monotonic versioning** — ignore older-than-seen. |
| Bucket-move window | Brief split (single-write) or brief unavailability (two-phase). | Bound the window (short TTL + purge); pick the publish strategy in §7.2. A single-write split ends when H_old evicts the room with **WS 4421** (§6.9, §7.4). |
| Reconnect/handshake storm on reshard | Spike of TLS handshakes on target hosts. | Gradual reshard + jittered reconnect backoff. |
| Stale client cache after a move | Client reconnects to old host. | Host rejects buckets it no longer owns (**HTTP 421**, §6.9) → client re-resolves. |
| Fetch error on a host | — | Keep last-known-good; never fail-open/closed. |

---

## 9. Security and trust

- **Noise XK pins the Mac's static key.** The QR's `rs` is the Mac's static public key, and the `Noise_XK_25519_ChaChaPoly_BLAKE2s` handshake authenticates it end-to-end. A rogue relay — or a client sent to one by a tampered shard map — cannot impersonate an endpoint, because it lacks the Mac's static private key and the Noise handshake fails. This is the cryptographic backstop that makes a bad map a **DoS-only** event.
- **TLS terminates on hosts (or on-box proxies) we control**, not at a third-party edge — so signaling cleartext and certs live only on our own infrastructure (R4).
- **Serve the shard map over HTTPS** from a domain we control, so it can't be MITM'd to redirect clients to a rogue host. Optionally **sign the JSON** and verify on the client for belt-and-suspenders. (The resolver URL itself arrives inside the QR, so a valid QR already anchors trust in the right resolver.)
- **E2EE bounds the blast radius** of a bad/tampered map to misrouting/DoS: per the Noise point above, a rogue host cannot join a pairing without the Mac's static key, so it cannot compromise content — only availability.
- The **pairing ID (`pid`) is effectively a bearer credential** for routing/pairing; give it sufficient entropy. (It does not gate content, which is protected by Noise/E2EE.)
- **The join verifier is soft state, not a secret the relay must protect.** It equals `HKDF(roomSecret)`, both devices re-derive it, and the relay stores only the public value, so it can be lost (host move, restart, death) with no loss of confidentiality. This is what §6.7's self-healing rests on.
- **The signed transcripts bind the relay origin.** The join and delete transcripts and the App Attest clientData all include `origin = "https://" + host` (§6.10), so a proof made for one relay host cannot be replayed against another, and a box cannot be steered to verify against an origin a client supplied (the origin is server-side, anchored to the box's TLS cert). Client and relay derive the string from the same provisioned hostname (the map `host` in resolved mode, the QR `relay=` value in direct mode); a byte mismatch fails every proof, so it is a configuration invariant, not a runtime negotiation.
- **Self-healing reopens an App-Attest-gated registration race** on each verifier loss. An attacker who knows the `roomName` and can pass App Attest could register a bogus verifier in the window before the phone re-registers, blocking reconnect. It is availability-only (Noise still authenticates the Mac and protects content), doubly gated (roomName secrecy plus App Attest), and recoverable by re-pairing. §11 lists a binding that would close it.

---

## 10. Migration / rollout plan

1. **Ship clients that understand both pairing modes:** direct (`relay=`, `v=1`) and resolved (`resolver=`, `v=2`). Mode is selected by which parameter is present.
2. **Existing beta users keep working** — their `v=1` `relay=` QRs are unchanged and still connect directly. No re-pairing required.
3. **Self-hosting stays on direct mode** — a user running one relay emits `relay=<their box>`; nothing else needed. (A self-hoster wanting sharding can run their own resolver and emit `v=2`.)
4. **Introduce the shard map** as a static CDN file plus a **resolver URL**; the managed service emits `v=2` `resolver=` QRs for new pairings. Bootstrap the map with today's single box as the sole entry (`ranges: [{0..N_BUCKETS-1 → current host}]`).
5. **Add `bufferutil`, disable `permessage-deflate`, add backpressure handling** in the relay (independent of mode; immediate throughput win).
6. **Stand up a second box**, publish a two-range map, exercise a reshard end-to-end on beta traffic.
7. **Add host-side reject-on-doubt and shard-map polling**; validate the reconnect/retry path and the split window under a deliberate bucket move. Add the phone's self-healing re-register fallback (§6.7) and validate it by moving an *established* room's bucket to a fresh host.
8. Grow by adding boxes and republishing the map as real adoption numbers land.

---

## 11. Open questions / future work

- **Geo-aware placement.** Sharding on `roomName` is deliberately geography-blind — the hash picks the bucket and the bucket picks the host, with no notion of where the user is. Honoring latency would require a level *above* the bucket map: separate per-geo clusters, with the client selecting its cluster (e.g. GeoDNS on the resolver URL, or a region tag added to the QR) and each cluster running its own independent shard map. Deferred — not needed while the fleet is small; revisit only if latency complaints appear.
- **10 Gbps boxes.** If one Node process can't fill the port, run multiple workers and reintroduce intra-box routing (per-worker port encoded in the descriptor, or an on-box HAProxy consistent-hashing the room key to a worker). Avoided entirely at gigabit with one process per box.
- **Least-loaded placement.** Initial bucket→host assignment is currently static/manual; a tiny coordinator or load-aware publisher could balance new buckets automatically. Keep it out of the media path.
- **Close the re-registration race by binding the address to the verifier.** A post-establishment address `roomName' = SHA256(canonical("iterm2-room", [rs, pid, verifier]))` would let the relay require any registered `V'` to satisfy `roomName' == H(rs, pid, V')`, so a bogus verifier cannot match the address the devices actually use (§6.7). The cost is that establishment then moves the pairing to a different bucket (the address changes once the phone's verifier exists), an added complication. Ship the App-Attest-gated self-heal first and treat this as hardening only if the DoS window ever proves unacceptable.
- **Session survival across host restart.** Not needed (stateless relay); revisit only if reconnect glitches during planned restarts become a complaint.
- **P2P.** Intentionally out of scope, but the largest possible lever on relay bandwidth if it's ever needed — would remove whatever fraction of connections can go direct from the relay entirely.

---

## Appendix A: Key invariants (don't violate these)

1. **`N_BUCKETS` is immutable** (fixed at 65536 = low 16 bits of `roomName`). Changing it rehashes every pairing. The bit-extraction convention must be byte-for-byte identical across Swift and Node — ship a test vector.
2. **A host newly admits a bucket only if its own current map says it owns it** (reject-on-doubt). Relinquished buckets are not newly admitted; their existing rooms are drained gradually at `RESHARD_EVICTION_RATE` (§7.4), never dropped en masse.
3. **Everyone ignores map versions older than the newest they've seen.** (Monotonicity.)
4. **Old owner relinquishes before new owner accepts** (break-before-make) — or accept a brief self-healing split with single-write publish. Never make-before-break.
5. **The relay holds no durable per-pairing state that must survive a host change.** The join verifier is soft state (`verifier = HKDF(roomSecret)`, re-derivable by both endpoints and re-registered on demand; see §6.7); the assertion counter and per-room byte quota are host-local and reset safely on a move. This is what makes a host's home reassignable at will and a dead host's rooms recoverable with nothing to migrate.
6. **Map edits preserve existing boundaries; re-equalization is a deliberate event.** The bucket space is a ring; a host owns one or more contiguous arcs (§6.3). Adding a host carves its arc out of existing ones and removing a host merges its arc into a neighbor, so a membership change moves only ~`1/K` of buckets (§7.5). Only a planned, higher-churn rebalance may move boundaries wholesale to even out drift.

7. **A managed box's provisioned hostname is one string used three ways, and all three must be byte-identical: its TLS certificate SAN, its shard-map `host` entries (which buckets it owns), and its proof origin (`"https://" + hostname`).** The admission and delete transcripts and the App Attest clientData all bind that origin (§6.10). A mismatched byte does not fail the connection; it silently fails every signed join for that box. The client derives the same origin as `"https://" + host` from the map verbatim (resolved mode) or from the QR `relay=` value (direct mode), so the map `host` must stay in one canonical form (lowercase ASCII, no trailing dot, port only if non-443).

---

## Appendix B: Pairing URL formats

**Direct mode (`v=1`)** — existing beta users and self-hosted single relays:

```
iterm2://pair?v=1&proto=Noise_XK_25519_ChaChaPoly_BLAKE2s&rs=<mac static pubkey>&pid=<pairing ID>&relay=<relay URL>
```

The client connects directly to `relay`. No shard map or resolver is involved.

**Resolved mode (`v=2`)** — the managed, sharded fleet (or a self-hoster running their own resolver):

```
iterm2://pair?v=2&proto=Noise_XK_25519_ChaChaPoly_BLAKE2s&rs=<mac static pubkey>&pid=<pairing ID>&resolver=<resolver URL>
```

The client computes `roomName` via the `RelayRoom` derivation (§6.2), then `bucket = uint16be(roomName[30], roomName[31])` (N_BUCKETS = 65536), fetches the shard map from `resolver`, looks up the owning host, and connects there, with the caching, reject-on-doubt, and monotonic-version behavior of §6 and the self-healing reconnect of §6.7.

`proto`, `rs`, and `pid` are identical across modes; the only differences are `relay=` (direct) vs `resolver=` (resolved) and the version tag. Clients select the mode by which parameter is present, so the two can coexist indefinitely.
