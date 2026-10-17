# Self-hosting the push relay

The push relay ships two ways from the **same** `src/worker.js`:

- **Cloudflare Worker** (`wrangler deploy`) — the original; KV + global `fetch`.
- **Self-hosted Node process** (`bin/push-relay.js`) — this doc; SQLite for KV,
  HTTP/2 for APNs. Built because the free Workers plan caps KV writes at
  **1,000/day**, which a reconnect storm can exhaust — after which genuine
  registrations can't be persisted and every push 403s `bad secret`.

The Node host is a thin platform shim; the request logic is unchanged. See
`host/kv.js` (KV→SQLite), `host/apns.js` (APNs over `node:http2`), and
`host/server.js` (Node HTTP → `worker.fetch`).

## Before you move: the client URL is the real work

Both apps hard-code the relay origin in
`sources/Companion/Shared/CompanionPushRelay.swift`:

```swift
static let baseURL = URL(string: "https://iterm2-push-relay.gnachman.workers.dev")!
```

That `*.workers.dev` host **can't be repointed** to your box, so cutover requires
shipping a **Mac + iOS app update** that changes `baseURL` to a hostname you
control (e.g. `https://push.iterm2.com`). Point it at a **domain you own** so any
future backend move needs no further app release.

Recommended sequence:

1. **Hotfix now, no client change:** the idempotent `/register` write (already in
   `src/worker.js`) collapses steady-state KV writes to ~0, so `wrangler deploy`
   alone keeps you under the free-plan cap. (The daily counter also resets at
   00:00 UTC.) This buys time without an app release.

   > **Deploying the Worker needs Node ≥22 and Cloudflare auth**, neither of
   > which the relay box necessarily has (it runs Node 20 for the services, and
   > `wrangler login` needs a browser). Deploy from a machine that already ran
   > `wrangler deploy` (auth in `~/.config/.wrangler`). If you must deploy from
   > the headless box: `npx wrangler@3 deploy` runs on Node 20, and pass auth as
   > `CLOUDFLARE_API_TOKEN=…` (an "Edit Cloudflare Workers" token) instead of
   > `wrangler login`. Do NOT upgrade the box's system Node — the services run
   > under `/usr/bin/node`.
2. **Then migrate deliberately:** stand up this Node host, ship the app update
   pointing `baseURL` at your domain, and **run both in parallel** during the
   transition so installs on the old build keep working until they update.

## Install (same box as the companion relay)

Layout mirrors the companion relay: a plain file copy in `/opt`, a systemd unit,
an `EnvironmentFile`, loopback bind behind the existing TLS reverse proxy. The
service listens on `127.0.0.1:8790` (companion relay is 8788, dashboard 8789).

**Use `ops/deploy.sh`** — it does all of the below idempotently, only ever
touches push-relay paths (it aborts on anything else), and refuses to start the
service until the config is real, so it can't crash-loop on the placeholder env:

```sh
# From the PushRelay checkout. Installs code+deps into /opt/iterm2-push-relay,
# the .p8 credential, the env template, and the systemd unit.
APNS_P8_SRC=~/AuthKey_XXXXXXXXXX.p8 ./ops/deploy.sh
```

On a first run it installs everything but leaves the service **stopped**, because
the env file (`/etc/iterm2-push-relay.env`) still has placeholder identifiers.
Finish and start it:

```sh
sudo $EDITOR /etc/iterm2-push-relay.env   # set APNS_TEAM_ID (Membership) and
                                          # APNS_KEY_ID (the 10-char id in the
                                          # AuthKey_<id>.p8 filename). Topic is
                                          # pre-filled.
./ops/deploy.sh                           # re-run bare: detects config, starts,
                                          # and prints "HEALTHY" after a loopback
                                          # check. (Keeps the already-installed key.)
```

> **The auth key must cover BOTH APNs environments** ("Sandbox & Production" in
> the Apple Developer portal). A Sandbox-only key silently works for development
> builds but 403s (`BadEnvironmentKeyInToken`) on every push to a release/App
> Store device. See [Troubleshooting](#troubleshooting).

`deploy.sh` deliberately does NOT touch the reverse proxy (the one piece of
shared Apache config the companion relay depends on) — that's the next section.

Health check (loopback):

```sh
curl -s -X POST localhost:8790/nope        # {"error":"no such endpoint"} => up
```

## Reverse proxy — push.iterm2.com via Cloudflare

Routes `push.iterm2.com` (CF edge :443) → this box `:8443` → `127.0.0.1:8790`,
a sibling of `relay.iterm2.com` on the SAME already-Cloudflare-firewalled :8443
listener. `ops/push-relay-cf.conf` is the vhost.

Cloudflare side (one-time):

1. **DNS:** `push.iterm2.com` A + AAAA → this box, **proxied (orange)**.
2. **Origin port → 8443:** CF connects to origin on :443 by default, but the
   vhost lives on :8443. Add/extend the same **Origin Rule** that already sends
   `relay.iterm2.com` to origin port 8443 so it also matches `push.iterm2.com`
   (or broaden it to `*.iterm2.com`). Without this, CF hits origin :443 and lands
   on the wrong vhost.
3. **Origin cert:** none needed — the companion relay's origin cert is a
   `*.iterm2.com` wildcard (SAN `DNS:*.iterm2.com, iterm2.com`), so the vhost
   reuses `/etc/ssl/cloudflare/companion-relay.{pem,key}` and already covers
   `push.iterm2.com`. SSL/TLS mode is zone-wide (Full/strict already set for
   iterm2.com). The :8443 firewall already admits only Cloudflare, so this name
   inherits it — nothing to open.

On the box (safe, additive — never `restart`; gate on configtest):

```sh
sudo cp ops/push-relay-cf.conf /etc/apache2/sites-available/
sudo a2ensite push-relay-cf         # symlinks into sites-enabled
sudo apache2ctl configtest          # MUST print "Syntax OK" before reloading
sudo systemctl reload apache2       # graceful: in-flight relay/dashboard conns survive
```

`configtest` catches a bad edit before the reload, so a mistake can't drop the
companion relay. Validate end-to-end once DNS/cert propagate:

```sh
curl -s -X POST https://push.iterm2.com/register -d '{}'    # {"error":"bad token or secretHash"} = reached node
curl -s https://push.iterm2.com/nope                        # {"error":"no such endpoint"}, NOT the mcnachman.cloud page
```

Reading the failures (both observed while bringing this up):

- **`mcnachman.cloud` HTML / wrong site** → the Origin Rule isn't sending
  `push.iterm2.com` to origin port 8443; CF is hitting origin :443 (step 2 above).
- **Apache `503 Service Unavailable` whose footer says `Server at
  push.iterm2.com`** → routing is correct (it reached *this* vhost), but the
  backend on `127.0.0.1:8790` is down — i.e. the service isn't started (usually
  the placeholder-env case above). Check `systemctl is-active iterm2-push-relay`
  and `ss -tln | grep 8790`.

The `baseURL` in `sources/Companion/Shared/CompanionPushRelay.swift` then becomes
`https://push.iterm2.com`.

## Redundancy (two instances)

The apps list several relay hostnames (`baseURLs` in
`sources/Companion/Shared/CompanionPushRelay.swift`, currently `push.iterm2.com`
then `push2.iterm2.com`). The phone registers with the first that answers; the
Mac pushes through the first that delivers. Both move on to the next host for
any failure except a 400 (the request itself is bad) whose body is the relay's
own `{"error": ...}` JSON, because anything else may come from that host alone
(an unknown device, a misrouted proxy or vhost, a WAF, an outage). The Mac also
stops on the relay's 429 (its per-device push limit, which failing over would
dodge); the phone's registration doesn't, since that 429 is each instance's own
per-IP limit. After a push had to fail over, the Mac tries
the host that worked first for 5 minutes, so a dead primary doesn't delay every
push by its timeout. An APNs rejection that any relay would get too (410
Unregistered, 400 BadDeviceToken, 429 TooManyRequests) is answered as a 422
rather than the worker's 502, because Cloudflare replaces an origin 502 with
its own page and the Mac couldn't tell; on a 422 it stops instead of retrying
on the other relay. APNs reasons that come from a relay's own `APNS_TOPIC`
(BadTopic, TopicDisallowed, MissingTopic, DeviceTokenNotForTopic) stay 502 and
fail over, since the other relay may be configured correctly.

A relay's 403 "bad secret" is final on the Mac: it means the phone re-paired,
and failing over would let the revoked Mac push through a relay the new secret
hasn't reached yet. The cost is the mirror case: if the phone re-paired via
`push2` while `push.iterm2.com` was down, the new Mac's pushes fail on
`push.iterm2.com` until `push2` delivers the new secret, which it does as soon
as it hears from `push.iterm2.com` again. (A 403 "unknown device token" fails
over: the registration may just not have arrived yet.) The one exception is
the relay the Mac tried first only because of its 5-minute failover
preference: right after a re-pair that's the relay most likely to be behind
(the phone registers with the primary first), so there "bad secret" moves on
to the primary, and the preference is dropped. No load balancer is involved, so nothing is billed per
request.

Run the instances on different providers. Both hostnames are proxied by the same
Cloudflare zone, so Cloudflare itself (and any WAF or Bot Fight rule there)
remains a shared dependency. A challenge on `/peer/register` shows up as a
stalled outbox with 403s in the log.

Each instance passes every registration it handles on to its peer
(`host/peer.js`), so both can authorize every device:

- Forwarded to `https://<peer>/peer/register`, authenticated with a shared secret
  of at least 32 characters (peering is refused with a shorter one, since the
  endpoint is public; the relay won't start with a non-https `PUSH_PEER_URL`
  other than loopback). A forward counts as delivered only when the answer is
  the peer's own (it carries `x-push-peer: 1` and `{"ok":true}`), so a
  misrouted URL whose site answers 200 keeps the rows queued. A skipped (unchanged) registration is forwarded too
  unless the peer is known to hold that exact record (it acknowledged it, or
  sent it here, since this relay started), so a peer that missed one catches up
  on the phone's next connection, while an in-sync peer costs nothing on a
  reconnect storm.
- Each forward is first written to the SQLite file (`peer_outbox`, one row per
  device) before the phone gets its reply. A single drain loop then sends
  queued rows one at a time and deletes each once the peer accepts it. It runs
  after each queued registration and every minute, and picks the next row by
  query after each send: live registrations first, then the startup backlog.
  A row that fails is retried with backoff (1, 2, 4... minutes, up to 15), so
  it moves behind the others. A pass gives up after 3 failures in a row, and
  no new pass starts for 5 seconds after one gives up, so against a dead peer
  a registration storm costs at most about 3 sends (and 3 small writes) every
  5 seconds, and an idle relay about 3 a minute. A row the peer is up and
  refusing (its 409 for a stamp in its future) is retried later but doesn't
  count toward giving up. A 500 from the peer means its database is failing:
  20 in a row end the pass (so a few rows it can't handle don't block the
  rest), but the peer is still counted as up. When the peer answers again after a pass gave up or a hello
  failed, rows that were backing off are retried right away. Failures are
  logged as one summary line per pass, not one per row. A row the peer's own code
  refuses as malformed (a 400 carrying `x-push-peer: 1`) is dropped
  (`pushrelay_peer_forward_dropped_total`); a 400 from anything in between
  (wrong scheme or port in `PUSH_PEER_URL`, a WAF) keeps the row. The database
  runs `synchronous = FULL`, so a registration the phone was told succeeded
  survives a power loss too.
- At startup every live registration is queued, which repairs anything both
  relays missed while each had an outage. The cost: one request per live device
  to the peer, sent one at a time, so draining takes about devices x round-trip
  time (e.g. 1,000 devices at 100ms is under 2 minutes). New registrations go
  ahead of that backlog. The backlog includes records received from the peer,
  so each restart echoes those back once. An echo carries the same stamp the
  peer already has, so the peer doesn't rewrite it: it costs a request but no
  write.
- Seeding: each database has a random instance id, and each process a boot
  id, returned on every authenticated `/peer/*` response. When a relay sees
  either change (the peer was rebuilt, restarted, or restored from a backup),
  it forgets what it thought the peer held and queues everything for it again
  at low priority (`pushrelay_peer_rebuilt_total` counts rebuilds). An idle
  relay sends a `/peer/hello` once a minute, so this happens within a minute
  or two. To force a full resend anyway:
  `sudo systemctl kill -s USR2 iterm2-push-relay` (or restart it).
- The receiver keeps the record with the later `registeredAt`, compared as
  stamped, so **both hosts must run NTP** (their clocks then agree to within
  milliseconds). A phone registration is stamped at least a second after any
  record the relay already held, in the same transaction, which covers a
  peer's clock being slightly ahead. Clocks that disagree by more than the time
  between a user's unpair and re-pair can order those two registrations
  wrongly, so alert on `pushrelay_peer_clock_skew_ms` (the fleet monitor warns
  at 2s and is critical at 30s). That gauge is the peer's clock minus ours,
  estimated NTP-style from each round trip (error at most half the round
  trip) on both relays. A stamp more than a minute in the receiver's future
  is refused with a 409 and retried until the clock catches up; that also
  happens after a burst of changed registrations for one device faster than
  one per second (a client bug, or someone who knows the token), since each
  moves its stamp a second ahead. A peer whose clock is more than an hour off
  is refused the same way.
- A forwarded record keeps the sender's expiry (its `registeredAt` plus the
  sender's `REGISTRATION_TTL_SECONDS`, sent with the record), capped at the
  receiver's own TTL. Keep that setting the same on both instances.

Setup, on BOTH instances, each naming the other, with the same secret
(`openssl rand -hex 32`, generated once). Add to `/etc/iterm2-push-relay.env`:

```sh
PUSH_PEER_URL=https://<the other instance's hostname>
PUSH_PEER_SECRET=<the shared secret>
```

then `sudo systemctl restart iterm2-push-relay`. The startup log line names the
peer (`peer=https://...`). `/peer/register` goes through the public vhost like
`/register`; without peer config it 404s. Watch
`pushrelay_peer_last_ok_timestamp_seconds` (when the peer last answered an
authenticated request; with the minutely hello, more than a few minutes old
means it's down or misconfigured), `pushrelay_peer_outbox` (rows still to
send; a large startup backlog drains in minutes), and
`pushrelay_peer_forward_failed_total`.

## Metrics

The Node host exposes aggregate, zero-PII metrics in Prometheus text on a
**loopback-only** `/metrics` (the same posture as the companion relay — a scrape
must be a direct 127.0.0.1 peer with no proxy headers, so the public vhost can't
reach it):

```sh
curl -s 127.0.0.1:8790/metrics        # pushrelay_* counters + devices gauge
```

Counters mirror the worker's decisions — `pushrelay_register_written_total` vs
`pushrelay_register_skipped_total` (the idempotency signal), and
`pushrelay_push_delivered_total` vs `pushrelay_push_bad_secret_total` /
`_unknown_token_total` / `_apns_error_total` — plus a `pushrelay_devices` gauge
(live registrations). The Cloudflare Worker does not expose this (observability is
off there); it's a host-only feature for the on-box dashboard.

**Delivery outcome and APNs health** (what to look at when pushes fail):

| Series | Meaning |
|---|---|
| `pushrelay_push_failed_total` | Pushes that failed on our side or Apple's (502 reject + 500 transport error). Client faults (bad secret, unknown token) are excluded. |
| `pushrelay_apns_rejected_total{reason}` | Apple's rejections by reason (`BadDeviceToken`, `Unregistered`, `TooManyRequests`, …; unknown reasons fold into `other`). Bounded, non-identifying. |
| `pushrelay_apns_latency_seconds` | Histogram of the round trip to Apple, incl. connect and any reconnect-throttle wait. |
| `pushrelay_apns_request_timeouts_total` | Requests Apple never answered (10 s). The signature of a dead connection. |
| `pushrelay_apns_connects_total`, `_connect_throttled_total`, `_session_errors_total`, `_discarded_idle_total`, `_discarded_timeout_total` | Connection churn: how often we reconnect, are held to the 1/sec floor, or throw a session away. |
| `pushrelay_apns_sessions`, `_apns_oldest_session_age_seconds` | Open HTTP/2 sessions to Apple and how old the oldest is (gauges). |
| `pushrelay_last_delivery_timestamp_seconds` | Unix time of the last accepted push; `0` until one succeeds after a restart (gauge). |

The host also logs failures. Each failed push (any 5xx on `/push` or
`/push/mutable`) writes `push-relay: push failed: <path> -> <status> <body>`, which
for an APNs reject carries Apple's status and reason, e.g.
`push-relay: push failed: /push -> 502 {"error":"APNs 410: {\"reason\":\"Unregistered\"}"}`,
and a transport failure reads `-> 500 {"error":"APNs request timed out"}`. APNs
session events (a session discarded after a timeout or idle, a session error) are
logged too. All of it is visible in `journalctl -u iterm2-push-relay`. The body is
the only record of the reason: Cloudflare replaces an origin 502 with its own error
page before the client sees it.

The **relay dashboard** scrapes this endpoint and renders a "Push relay" section
(success vs failure per minute, APNs latency p50/p95, timeouts, reconnects, open
sessions, rejections by reason, time since last delivery); see that service's
`ops/DASHBOARD.md`. It defaults to `http://127.0.0.1:8790/metrics`, so no config
is needed once both run on the same box. On a host that runs only the push relay,
set `DASHBOARD_METRICS_URL=` (empty) to drop the companion-relay half.

APNs connections are kept open and reused. A session is replaced after 5 minutes
idle and thrown away when a request gets no answer, and a new connection to the
same Apple host is opened at most once per second, so an outage cannot turn every
incoming push into a fresh connect attempt (`host/apns.js`).

## Troubleshooting

**`APNs 403: BadEnvironmentKeyInToken` in the log (every push to real devices
fails).** The configured auth key is scoped to Sandbox only, but release/App
Store devices register `sandbox=false` and are pushed via `api.push.apple.com`
(production). The `.p8` doesn't encode its environment, so this can't be caught at
deploy time — only Apple's rejection at push time reveals it. Fix: use a key
enabled for **Sandbox & Production**, then swap it in (Team ID and topic are
unchanged — only the Key ID and `.p8` differ):

```sh
sudo cp -a /etc/iterm2-push-relay/apns.p8 /etc/iterm2-push-relay/apns.p8.bak   # rollback safety
sudo install -o root -g root -m 600 ~/AuthKey_<NEWID>.p8 /etc/iterm2-push-relay/apns.p8
sudo sed -i 's/^APNS_KEY_ID=.*/APNS_KEY_ID=<NEWID>/' /etc/iterm2-push-relay.env
sudo systemctl restart iterm2-push-relay      # reloads the credential + clears the cached provider JWT
```

Verify: `curl -s 127.0.0.1:8790/metrics | grep pushrelay_push_` — `_delivered_total`
climbs, `_apns_error_total` holds. (`api.sandbox.push.apple.com` is used only for
development builds, which register `sandbox=true`.)

## Deploying a code change

- **VPS host:** re-run `./ops/deploy.sh` from the updated checkout. It refreshes
  `/opt/iterm2-push-relay` and the unit and restarts the service (leaving the env
  and `.p8` untouched). It's the same idempotent script used for the first
  install.
- **Cloudflare Worker:** `wrangler deploy` (mind the Node ≥22 + auth note above).

`src/worker.js` is shared by BOTH targets, so keep changes transport-agnostic:
platform specifics belong in `host/` (Node) and the Cloudflare bindings (Worker),
never in `src/worker.js`. The only seam is `env.fetchImpl` (undefined on
Cloudflare → global `fetch`; the Node host injects the HTTP/2 APNs client).

## Tests

- `npm test` — Worker logic in workerd (`vitest.config.js`).
- `npm run test:host` — the Node shim: KV fidelity, the HTTP/2 APNs adapter, and
  an end-to-end `/register`→`/push` through a real listener (`vitest.host.config.js`).
