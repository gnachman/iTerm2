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
