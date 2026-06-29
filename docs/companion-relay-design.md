# iTerm2 Companion Relay: Design

Status: implemented.

Scope: remote communication between a paired Mac and iPhone over the
internet, including pairing on networks that forbid peer-to-peer
traffic.

## Goal

A paired phone and Mac should be able to communicate whenever both
have internet access, with no requirement that they be on the same
network. Pairing must work on client-isolated networks (corporate
WiFi, hotels) and across networks (phone on cellular, Mac on
ethernet). If a network blocks outbound HTTPS to the relay, the
devices cannot reach each other; that case is out of scope.

## Non-goals

- **Peer-to-peer NAT traversal** (ICE/STUN hole punching). It isn't
  worth the complexity here: the traffic is small (chat messages and
  occasional ~100KB session tiles), and the main remote case (phone on
  cellular) sits behind carrier-grade NAT where hole punching usually
  fails anyway. If we ever want it, the relay's Durable Object can
  serve as the ICE signaling channel; nothing here rules that out.
- **Background connectivity on the phone.** iOS kills our sockets when
  the app is backgrounded; push notifications cover that case.
- **Trusting the relay.** The relay only ever sees ciphertext, and the
  design must stay safe even if it doesn't. In particular, every
  protection below must hold even when the Worker runs fully open
  (`ATTEST_REQUIRED=false`; see Bring Your Own Relay). The quota and
  admission machinery is therefore mandatory, not optional tuning.

## Background: what already exists

- **Security.** Every connection runs
  Noise_XK_25519_ChaChaPoly_BLAKE2s. The QR pins the Mac's static
  public key (`rs`), and the handshake prologue binds the pairing id
  (`pid`). The phone's static key crosses the wire only encrypted; the
  Mac's never crosses at all.

## Architecture

The relay is a public server that lets a phone and Mac find each
other and exchange encrypted frames when they are not on the same
network. Its main job is to *splice* their two connections, copying
frames between them, and it cannot read what it carries: all traffic
is end-to-end encrypted. But it is not a pure pipe. Before splicing a
connection it admits the client (checking that it is legitimate), and
throughout it enforces quotas and other limits to protect itself from
abuse. Those checks are detailed in later sections.

The parties:

- **The Mac and the iPhone:** a pair of devices that want to
  communicate, whether or not they are already paired. All traffic
  between them is end-to-end encrypted with Noise, so nothing on the
  path, including the relay, can read or alter it.
- **The relay operator:** whoever runs the relay server. By default
  this is the iTerm2 project's hosted instance, but anyone can run
  their own (see Bring Your Own Relay). The operator sees connection
  metadata (IPs, timing, volume) and can deny service, but cannot read
  traffic or impersonate either device.

The relay is a Cloudflare Worker backed by one Durable Object (DO) per
pairing. Both devices connect outbound to it over WebSocket (wss), so
there are no inbound firewall holes to open on either end. They meet
in a *room* (one DO), which performs the admission checks and then
splices the two connections.

The relay is its own Worker deployment, kept separate from the
project's other services (see `companion-push-relay.md`) so that the
high-traffic, most-exposed splice path cannot reach their secrets if it
is compromised.

### The QR code

The Mac displays a QR that the phone scans to begin pairing. It encodes
an `iterm2://pair` URL with these fields:

- `v` — format version.
- `proto` — the Noise protocol name
  (`Noise_XK_25519_ChaChaPoly_BLAKE2s`).
- `rs` — the Mac's static public key (base64url).
- `pid` — the pairing id (the random nonce mentioned above).
- `relay` — the relay's base URL (an HTTPS origin). Optional; if
  absent, the phone uses the official default relay. This is how a
  self-hoster points a pairing at their own relay.

Everything the phone needs to locate the room (`rs`, `pid`, `relay`)
and to authenticate the Mac end-to-end (`rs`, `proto`) comes from the
QR and nowhere else.

### Room names

Both devices must derive the same room name with no coordination, and
no one else should be able to guess it. The name is a hash of the
pairing's secret material, both halves delivered by the QR: `rs` (the
Mac's static public key) and `pid` (a random nonce the Mac chooses for
the pairing).

    roomName = SHA256(canonical("iterm2-room", [rs, pid]))

`canonical` is a domain-separated, length-prefixed encoding: each
element is prefixed with its 4-byte length, behind the label
`"iterm2-room"`. This makes the `rs`/`pid` boundary unambiguous and
keeps the hash from ever colliding with another use of the same
inputs. Because `rs` only ever travels inside the QR, the room name is
unknowable to anyone who has not scanned it, which rules out room
squatting and probing.

The room name is sent to the Worker in a request header, never in the
URL path. A path like `/room/<name>` would record the pseudonym in
Cloudflare's edge request logs, which no operator setting can disable;
a header keeps it out. (The Worker needs the name before it can
address the DO, so it cannot wait for the first WebSocket message to
carry it.)

On the app side, the relay is reached from two directions:

- **Phone:** connects to the relay, authenticates, and once the room
  splices it through, gets back a transport for the Noise channel to
  run over.
- **Mac:** *parks* in the room, meaning it holds an open connection
  there waiting for the phone to appear. The Mac parks during pairing
  and whenever it is paired but currently disconnected.

The Noise handshake runs end-to-end through the splice on every
connection, so the relay only ever sees ciphertext. (A Noise handshake
also exposes each side's ephemeral public key in the clear, but those
are useless to the relay.)

Framing: one WebSocket binary message carries exactly one frame, since
the WebSocket layer already provides message boundaries. The Noise
channel's existing chunking of payloads larger than 64KB is unchanged.
The relay caps frame size itself, well below Cloudflare's 1 MiB
WebSocket message limit, before splicing.

## App Attest keys

To prove to the relay that a phone is running the real iTerm2 Buddy app
rather than a script abusing it, the phone uses Apple's App Attest.
Each pairing gets its own App Attest key. Over time a phone may pair
more than once (each re-pairing creates a new room on the relay), and
if one App Attest key were reused across those pairings, the relay
would see the same key id in each of that phone's rooms and could link
them as belonging to a single device. A per-pairing key prevents that.
The cost is one extra attestation per pairing and a small, predictable
amount of key churn, low enough to stay within the per-IP limits on
new keys (see Abuse).

## Credentials and gatekeeping

Every connection tells the relay its role, phone or Mac. The relay
needs this because the two roles are admitted differently and occupy
separate slots in the room (described later).

Admission is purely abuse prevention: it controls who may spend the
relay's bandwidth, never who may read the traffic. Confidentiality and
authenticity between the two devices come entirely from the end-to-end
Noise channel, which the relay cannot see into. A wide-open relay with
attestation disabled is therefore still safe for its users; it is only
cheaper to abuse.

The relay admits a connection differently depending on whether the
pairing already exists:

- **Before pairing,** there is no shared secret yet, so the phone
  proves it is running the real iTerm2 Buddy app using App Attest. The Mac
  cannot attest (App Attest is not available off the App Store) and
  simply parks.
- **After pairing,** both devices share a secret established during
  pairing, and each proves it holds that secret to rejoin the room.

### Pairing rooms (no shared secret yet)

App Attest lets the phone authorize itself without anything from the
Mac. Again, this is only an abuse gate, allowing a signed iTerm2 Buddy
install to spend relay resources while turning away a script; it says
nothing about who the phone is talking to.

1. The phone scans the QR and requests an attestation challenge (a
   fresh 32-byte random nonce) from the relay. It refuses non-HTTPS
   relay URLs and refuses redirects, and it reduces the `relay=` URL to
   scheme, host, and port at parse time, rejecting any userinfo, path,
   query, or fragment. (The phone builds its own endpoint paths from
   that origin, so an embedded path or userinfo in the QR could only be
   an attack.)
2. The phone generates its per-pairing key and attests, binding the
   attestation to
   `clientDataHash = SHA256(canonical("iterm2-relay-attest", [challenge, relayOrigin]))`,
   where `relayOrigin` is the origin the phone believes it is talking
   to. (The canonical, length-prefixed encoding makes the
   challenge/origin boundary unambiguous.) The relay verifies the
   attestation chain to Apple's root, checks the app ID, and confirms
   that `relayOrigin` is its own. That last check closes a cross-relay
   forwarding attack: a hostile QR pointing at `relay=evil.example`
   could otherwise pass a valid challenge from the official relay
   through the phone and spend the official instance's resources under
   a victim device's attestation.
3. If verification succeeds, the relay issues the phone a pairing-room
   ticket: a single-use, short-lived (minutes) token bound to the
   attest key id and the room name. The phone presents this ticket when
   it opens its WebSocket to the room. The ticket carries the result of
   the HTTPS attestation over to the WebSocket connection, so the relay
   can admit the phone to the splice without rerunning attestation
   there, and it ties that admission to this one room.
4. The Mac parks in the room it named. The DO begins splicing only once
   a ticketed phone arrives.

The tickets, challenges, and their single-use and expiry state all
live in the room's DO, which is already addressed by the room name.
They are deliberately not kept in Workers KV (Cloudflare's key-value
store), because KV is eventually consistent and cannot enforce
single-use. Outstanding challenges are capped in number and expire on
their own, so issuing challenges cannot be used to fill the DO's
storage.

### Pairing confirmation (the anti-hijack step)

Because the relay works from anywhere, the QR no longer has to be near
the Mac to be used. A photograph of it is enough for an attacker to
attempt pairing from anywhere, using a real phone and a valid
attestation (the attacker's phone is running the real iTerm2 Buddy too,
so attestation does not distinguish it), by racing the real phone into
the handshake. The mitigations below, all required, defend against it.

**Short pairing validity.** The QR (and its `pid`) expires after two
minutes of inactivity; the pairing window then regenerates it.

**Mac-side verification with a short authentication string (SAS).**
Completing the Noise handshake does not finalize pairing. Both ends
derive the same SAS from the Noise handshake hash, which commits to
both static keys, using a fixed label and a fixed length (6 decimal
digits). The user confirms it, and the UI is deliberately asymmetric:
the phone displays the SAS, and the Mac only accepts input. The user
reads the digits off the phone and types them into the Mac, which
compares them against its own derived SAS. The Mac must never display
the code itself: if it did, the user could read the Mac's number and
type it straight back, which always matches and defeats the check.
Typed entry (rather than a single Accept button, or a
pick-the-matching-code list) forces the user to engage with the actual
digits, which resists blind clicking. (A picker was considered and
rejected: its best case is still a 1-in-N chance for an attacker to
win by blind guessing.)

**The SAS commits to one handshake.** While the confirmation UI is up,
a new connection can take over the phone's slot in the room (the room
keeps only the newest connection in each role; see admission below):
an attacker displacing the real phone, or the real phone displacing an
attacker. The relay closes the displaced socket. On the Mac, the
replacement surfaces as a fatal error on the Noise channel, because the
new connection's bytes cannot decrypt against the handshake already in
progress, and an AEAD failure tears the channel down rather than being
skipped (see Reconnection). That voids the pending confirmation, which
was bound to one specific handshake hash; the Mac re-parks, and the
next phone produces a fresh handshake and a freshly derived SAS. The
phone that loses the race does not sit silently: it keeps showing its
own SAS along with guidance ("your Mac is showing a code; if it does
not match this, reject"), so a hijacker's SAS on the Mac will visibly
fail to match the code on the real phone in the user's hand.

**The phone blanks its SAS the instant its connection drops.** A
6-digit SAS is only about 20 bits. Without this rule, an attacker who
photographed the QR could reconnect over and over during the pairing
window, getting a fresh handshake hash (and so a fresh SAS) each time,
and keep trying until one happened to match the victim phone's
still-displayed, by then stale, code, which the user might then type
into the Mac. Clearing the phone's SAS the moment its connection dies
removes that target.

**The DO caps phone-slot turnover per room** at eight cycles
(`MAX_PAIRING_CYCLES`). The DO cannot see the end-to-end Noise
handshake, but it counts how many times the phone slot is taken while
the Mac is parked, and each new phone connection is one more handshake
attempt. The count resets on every fresh Mac park, and when it exceeds
eight the room is killed and the QR must regenerate. Counting per park
rather than per QR matters because a confirmed-but-not-yet-established
Mac re-parks in pairing mode without a QR (see the lifecycle section),
and each fresh park gets its own budget. Together with
blank-on-disconnect, this makes grinding through the roughly 2^20
possible SAS values hopeless even when attestation is off.

**Wrong SAS entries regenerate the QR.** The Mac accepts three typed
attempts; a code still wrong after that (the other visible sign of a
hijack, or just a typo) is treated as a failed pairing: the Mac voids
it and regenerates the pid, invalidating the photographed QR.

**Mac-to-phone accept/reject.** The SAS is checked only on the Mac, so
the phone cannot tell on its own whether it succeeded; without a signal
it would sit on the pairing screen forever, even after a success. So
once the typed code matches, the Mac sends an explicit "pairing
accepted" control message to the phone over the now-active Noise
channel. This is the first application message on the channel, and it
is the phone's cue to stop showing the SAS, move into the chat list,
and only then begin the work that turns the pairing into an
established room (the next section). The phone does none of that
beforehand. On a wrong code, an abort, or a timeout, the Mac instead
sends "pairing rejected" so the phone fails fast rather than waiting
out its own timeout. The phone keeps an independent pairing-window
timeout regardless (no accept means failure) and blanks its SAS on
disconnect or timeout. It can trust the accept because the channel is
end-to-end authenticated by the completed handshake: the message
provably came from the device the phone handshook with, and only the
phone whose code the user typed correctly on the Mac ever receives one.
The human's trust decision happened on the Mac.

**Either side can abort at any time.** Both the Mac's confirmation
screen and the phone's SAS screen show a Cancel control throughout the
pairing window. Aborting on the Mac sends "pairing rejected" and tears
down; aborting on the phone closes its connection, which the Mac sees
as its slot dying, voiding any pending confirmation. Either way nothing
is committed: the pairing is not finalized and the room is not
established, and the QR regenerates for a fresh attempt. No half-paired
state is left on either side.

The phone's confirmation screen also shows the relay host whenever
`relay=` differs from the official default, so a camera-scanned hostile
QR pointing at an attacker's relay is disclosed to the user. The host
is shown as ASCII/punycode, never its Unicode form, so a lookalike of
the official hostname cannot be made to read as legitimate.

### Established rooms

Once pairing is confirmed, the room becomes established, and from then
on either device can rejoin it without pairing again. Rejoining is
authenticated, and the credential is built so that the relay can check
a join but never forge one.

It all starts from the `roomSecret`: a 32-byte random value the phone
mints. From it, both devices independently derive the same Ed25519
signing keypair. (The private key seed is
`HKDF-SHA256(roomSecret, info = "relay-auth-ed25519")`; the label keeps
this key distinct from any other use of `roomSecret`.) The public half
of that keypair is the verifier, `V`.

The two halves are used in opposite places:

- The relay stores only `V`. To rejoin, a device signs a challenge from
  the relay with its private signing key, and the relay checks the
  signature against `V`. (The full join exchange is described below.)
- Because the relay holds only the public `V`, it can verify a join but
  never produce one. A one-time relay compromise or storage dump leaks
  only public keys and authorizes nothing, then or later.

(A symmetric key stored at the relay would be far worse: a single dump
would let an attacker occupy and displace devices in every room until
the key rotated, which in practice happens only on unpair. Storing only
`V` also closes a TLS-MITM concern, since even an enterprise root that
captured the registration traffic would see nothing but `V`.)

Establishing the room runs during the first confirmed session, in this
order:

1. The phone mints the 32-byte `roomSecret` (kept in the Keychain,
   rotated on unpair) and derives the signing keypair.
2. The phone sends `roomSecret` to the Mac inside the Noise channel, as
   a field of the connection-time status message (resent on every
   connect, so it self-heals and re-keys automatically), and waits for
   the Mac's in-channel ack. The Mac now derives the same keypair, so
   both sides can sign joins.
3. Only after that ack does the phone register `V` with the relay, over
   HTTPS (a separate connection from the splice), which flips the room
   to established.

   The order matters. Establishing a room permanently closes
   pairing-mode admission, and the Mac can only join an established
   room once it holds `roomSecret`. If the phone registered `V` first
   and the session died before `roomSecret` reached the Mac, the room
   would be established but the Mac would have no signing key: it could
   not park, and the room would be stranded until the user re-paired.
   Acking before registering avoids this. The reverse failure is
   harmless: if the Mac acks but registration then fails, the room
   simply stays in pairing mode and the phone retries on its next
   connect.

   This first registration is tied to the pairing session. At phone
   admission the DO mints a one-time registration token; the phone
   presents that token alongside `V`, and the DO accepts a room's first
   `V` only with a valid, unused token. That bounds the open-mode race
   over who gets to register `V` to the pairing room's lifetime, even
   though registration does not ride the spliced connection. With
   attestation enabled, the phone also proves it is the same device
   that attested during pairing: it signs the relay's challenge with
   its per-pairing App Attest key (an App Attest assertion), and the
   relay checks that signature against the public key it recorded at
   attestation, with a counter that must strictly increase to block
   replay.
4. The relay accepts only the first registration of `V` for a room and
   refuses any later one ("already registered"). This keeps
   registration from becoming an overwrite channel: otherwise anyone
   who learned the room name could register their own `V` and take over
   the room. As a result, `V` cannot be replaced today, and the way to
   get a new one is to re-pair.

The pairing-to-established switch happens atomically inside the DO, and
once it does, pairing-mode admission is closed for good: no second
ticketed phone can ever join.

From then on, every connection to the room, by either device, is
authenticated the same way: a signature challenge-response. The DO
sends a fresh nonce; the device replies with a signature over a
fixed-length transcript of (protocol version, role, nonce, room name,
relay origin), which the DO verifies against the stored `V`. Binding
the room name and origin into the signed bytes makes the signing key
useless on any other room or relay, even if some future change reused
it. Since the relay holds nothing that can authorize a join, even a
fully compromised or dumped relay cannot mint one, and `roomSecret`
never leaves the Noise channel between the two devices.

All signature and ticket comparisons on the relay are constant-time.

In short, the Mac's standing rests entirely on holding a secret that
only the confirmed phone could have minted and only the paired Mac
could have received.

### The confirmed-but-not-yet-established window

Between SAS confirmation and the phone registering `V`, the room is
confirmed but not yet established. Normally this window is tiny: the
phone registers `V` as soon as the Mac acks `roomSecret`, within the
same session. But if the session drops in between, the Mac is paired
yet has never seen the room established, and two things follow.

First, the Mac parks in pairing mode, because it has no established
room to park in yet. Pairing-mode rooms expire after a couple of
minutes, so the Mac does not hold one open indefinitely; it re-parks
opportunistically rather than keeping a permanent presence. Once the
phone registers `V` on a later connect, the room becomes established
and the Mac parks persistently as normal.

Second, this is the one moment a paired Mac sits in a room whose
admission still says "new pairings welcome," so the DO could splice
some other admitted connection to it (any ticketed phone under
attestation, or any peer in open mode). The Mac defends by pinning the
phone static key it recorded at confirmation: it rejects any Noise
handshake from a different static, and it never re-enters the
pairing/SAS UI, completing the handshake only with the already-confirmed
phone. (Noise XK provides the rejection; the requirement is just that
this Mac not treat a new static as a new pairing.)

### Deletion, revocation, and expiry

Unpairing, on either side, sends the relay an explicit delete-room
request and deletes the device's local `roomSecret`. The request is
authenticated: before discarding `roomSecret`, the device signs a fresh
DO-issued nonce with the room's signing key (the private half of `V`,
derived from `roomSecret`), exactly like a join. That keeps a captured
delete signature from being replayed, and because it is an ordinary
signature it works in open mode too. Without this authentication,
anyone who knew a room name could destroy rooms.

Delete is best-effort, though: the relay might be unreachable at
unpair, or the device wiped, or the app deleted. So established rooms
also carry a 30-day idle TTL. This is housekeeping for the operator,
not a security control: the retained record authorizes nothing, so the
TTL exists only to keep dead rooms from accumulating in storage. Every
authenticated connection (a device joining, or the Mac re-parking)
refreshes the room's last-activity stamp, so the TTL never reaps a room
still in use; only a room left untouched for 30 days is deleted. The
retained record is pseudonymous: the room name is a derived hash, `V`
is a public verifier, and the attest key id (when present) is opaque.

A device that comes back after its room was reaped simply re-pairs. Its
reconnect finds no verifier (its signed join is refused, or in open
mode the room is just empty), and the app surfaces a "remote access
needs re-pairing" prompt rather than failing silently. Re-pairing mints
a fresh pid and room, so a leaked-QR holder who squats the reaped room
in the meantime gains nothing: the real devices never join it (their
signing key does not match the squatter's verifier) and move to a new
room anyway.

## Pairing flow

This is the end-to-end sequence with the real requests and
cryptographic values. Participants: the **phone**, the **relay** (its
Worker and the room's DO), **Apple's App Attest service**, and the
**Mac**. Every HTTP and WebSocket request to the relay carries the room
name in an `x-relay-room` header (64 lowercase hex chars) and a fixed
User-Agent, and the relay rejects any request bearing an `Origin`
header (only browsers send one).

**0. The Mac sets up the room and parks.** It loads or generates its
Noise static keypair, mints a random `pid`, computes
`roomName = SHA256(canonical("iterm2-room", [rs, pid]))`, and opens a
`wss` connection to the relay to *park*: it runs the admission
handshake declaring itself the Mac, then holds the socket open waiting
for the phone.

```
Mac -> DO:  Hello { v, role: "mac" }
DO -> Mac:  Challenge { nonce }
Mac -> DO:  Proof { }                 # a pairing-mode Mac is pre-auth:
                                      # no ticket, no signature
DO -> Mac:  Result { ok: true }
```

It then blocks reading the socket, waiting for the phone's first frame,
and displays the QR from "The QR code" (expires after two minutes of
inactivity, then regenerates).

(The DO sends a `Challenge` nonce on every admission, but only
established-room joins use it, where the proof is a signature over a
transcript binding the nonce. In pairing mode neither the Mac's empty
proof nor the phone's ticket consumes it; the DO sends it regardless so
an observer cannot tell from the reply whether a room is in pairing or
established mode.)

**1. The phone ingests the QR.** Either camera works, the system Camera
app or the in-app scanner, and a scan pairs directly. A pairing link
(`iterm2://pair?...`) opened from somewhere else, such as a webpage,
instead lands on a confirmation screen that shows the relay host first
(in punycode when it is not the official `companion-relay.iterm2.com`),
so a page cannot silently aim the phone at an attacker's relay. The
phone canonicalizes `relay=` to a bare https origin and stores `rs`,
`pid`, and that origin.

**2. The phone attests** (HTTPS, separate from the splice):

```
phone -> relay:  POST /attest/challenge          (x-relay-room: <roomName>)
relay -> phone:  { challenge }                    # fresh 32-byte nonce, base64

phone:           keyId = AppAttest.generateKey()             # contacts Apple
                 cdh   = SHA256(canonical("iterm2-relay-attest",
                                          [challenge, relayOrigin]))
                 att   = AppAttest.attestKey(keyId, cdh)      # Apple signs it

phone -> relay:  POST /attest { challenge, attestationObject: att }
relay:           verify att chain to Apple root, app id, AAGUID environment,
                 and that cdh embeds the relay's own origin
relay -> phone:  { ticket }                       # 24 random bytes
```

On success the DO stores the ticket (`ticket:<ticket>` -> keyId, 5-min
TTL) and returns a copy to the phone. The ticket is in effect a
single-use shared secret between the phone and this DO: the phone
presents it in step 3, and the DO checks it against the stored copy and
deletes it. The phone also pins `keyId` to this room so the step-6
assertion reuses the same attested key. (In open mode the relay answers
`/attest` with `400 attestation disabled` and the phone continues with
no ticket.)

**3. The phone joins the room** (WebSocket upgrade, room header),
running the admission handshake with the DO:

```
phone -> DO:  Hello { v, role: "phone" }
DO -> phone:  Challenge { nonce }
phone -> DO:  Proof { ticket }                    # ticket from step 2
DO:           look up ticket:<ticket>, check unexpired, delete it (single-use)
DO -> phone:  Result { ok: true, registrationToken }   # one-time, used in step 6
```

With both slots now filled, the DO starts splicing and from here copies
frames between the two sockets blindly.

**4. Noise XK handshake** (end-to-end through the splice). The phone is
the initiator, since it knows the Mac's static `rs` from the QR; the
prologue on both ends is `"iterm2-companion/v1/pid:" + pid`:

```
phone -> Mac:  msg1:  e
Mac -> phone:  msg2:  e, ee
phone -> Mac:  msg3:  s, se          # phone's static, sent encrypted
```

The Mac's static is never transmitted (the phone already had it); the
phone's crosses only inside msg3's encryption. A wrong `rs` or `pid`
makes the two sides' handshake hashes diverge and the handshake fails
its MAC. After msg3 both hold the same transport keys and the same
handshake hash `h`.

**5. SAS confirmation.** Both sides derive
`SAS = HKDF(h, "iterm2-sas-v1")` reduced to 6 decimal digits. The phone
shows it; the user types it into the Mac, which compares it against its
own. On a match the Mac sends the first application message over the
now-encrypted channel:

```
Mac -> phone:  {"pairing":"accepted"}             # or {"pairing":"rejected"}
```

Nothing in step 6 happens before this arrives.

**6. The phone establishes the room.** Over the Noise channel the phone
sends `roomSecret` (32 random bytes) in its connection-time status
message and waits for the Mac's in-channel ack, so both derive the join
keypair: a private signing key and its public verifier `V`. Only then
does the phone register `V`. Under attestation it must also prove it is
the same device that attested in step 2, so it fetches a fresh
challenge and has its Secure Enclave produce an App Attest assertion
(which signs the challenge and carries a monotonic counter):

```
phone -> relay:  POST /attest/challenge ; { challenge }   # fresh, for the assertion
phone:           assertion = AppAttest.generateAssertion(keyId,
                   SHA256(canonical("iterm2-relay-attest", [challenge, relayOrigin])))
phone -> relay:  POST /register {
                   registrationToken,             # from step 3
                   verifier: V,
                   challenge, assertion            # both omitted in open mode
                 }
relay:           token unused?; verify the assertion against the key attested in
                 step 2; counter strictly greater than the last one seen
relay -> phone:  ok                               # room now established
```

The room flips to established atomically, and pairing-mode admission
closes for good.

Nothing here requires the two devices to share a network. Physical
proximity matters only for showing the QR to the phone's camera and
reading the SAS off the phone; everything else runs through the relay
from anywhere.

## Reconnection

After pairing, either device reconnects on its own. The Mac parks in
the established room whenever it is paired but disconnected, retrying by
itself if the connection drops; the phone reconnects on app open or
after losing its connection. Both authenticate the same way, as
established-room joins: each signs the DO's challenge with its private
signing key (`signingKey`, the private half of `V`, derived from
`roomSecret` during pairing), and the DO verifies the signature against
the stored `V`. There is no SAS after the first pairing, since both
static keys were pinned then.

A reconnect (here, the Mac parking) looks like:

```
Mac -> DO:  Hello { v, role: "mac" }
DO -> Mac:  Challenge { nonce }
Mac:        sig = Sign(signingKey,
                       canonical("iterm2-relay-join",
                                 [v, "mac", nonce, roomName, relayOrigin]))
Mac -> DO:  Proof { sig }
DO:         verify sig against the stored V; refresh last-activity
DO -> Mac:  Result { ok: true }
```

The phone's join is identical with `role: "phone"`. Binding the role,
room name, and origin into the signed transcript keeps a captured
signature from being replayed into a different role, room, or relay,
and binding the fresh `nonce` keeps it from being replayed at all. Once
both slots are filled the DO splices, and the two run a fresh Noise XK
handshake (step 4 of Pairing flow), after which the channel is live. No
SAS, no accept/reject.

**Hibernation keeps a parked Mac nearly free.** Cloudflare evicts the
DO from memory while the WebSocket stays open, and billing accrues only
while frames actually flow. Parked connections still need keepalive
pings to survive NAT timeouts; these are answered by the hibernation
API's auto-response, so they never wake the DO or bill duration. This is
what makes an always-parked Mac affordable.

**AEAD failure is fatal.** The relay can drop, reorder, or replay
frames; with Noise's counter-based nonces, any of those shows up as an
AEAD decryption failure after the handshake. A single such failure
tears the transport down completely and forces a fresh handshake,
rather than skipping the offending frame. That turns any relay
frame-tampering into a clean reconnect instead of undefined behavior.
(The rule is stated explicitly because the lenient default would be to
skip and continue.)

## DO admission and connection hygiene

These controls run in every configuration, including a fully open relay
with attestation off, so they are load-bearing, not tuning. Some are
cost-motivated; the strategic view of cost and abuse is in Abuse and
cost control below.

**Admission is the first traffic, and it is bounded.** The
Hello/Challenge/Proof/Result exchange must complete before anything is
spliced; pre-auth bytes are never buffered or forwarded. Each pre-auth
control frame is capped at 8KB, the exchange has a 15-second deadline,
and a violation closes the socket silently. A room holds at most 4
simultaneous pre-auth sockets; when a fifth arrives the oldest is
dropped (close 1008), bounding per-room memory and wake cost during the
deadline window. The Hello carries a protocol version byte, so a future
admission change can never be mistaken for v1.

**The first reply is uniform, to avoid a mode oracle.** A naive DO
would answer differently for a pairing-mode, established, or absent room
(different challenge types), letting anyone who knows a room name probe
its state. Instead the DO always replies to Hello with a generic
`Challenge { nonce }` and branches only on what the client then
presents (a ticket or a signature). This matters little, since only
someone who already holds the unguessable name can reach it, but it
costs nothing to close.

**WS upgrades carrying an `Origin` header are rejected.** Browsers
attach `Origin` to every WebSocket upgrade and there is no CORS gate on
WS, so any webpage could otherwise conscript its visitors' browsers
into burning the relay's daily request cap against guessed room names,
from residential IPs that per-IP limits never catch. Native clients
send no `Origin`, so one header check removes the entire in-browser
attack surface for free.

**Two slots per room, one per role; newest wins, but displacement is
auth-gated.** Each room has exactly one phone slot and one Mac slot.
When a second connection arrives for a slot that is already taken, the
newer one wins, but only if it presents the credential that slot
requires, checked by the DO before any splice: a valid join signature
for an established room, or a valid pairing ticket for a pairing room.
(It has to be a DO-checkable, pre-splice credential. The DO is blind to
the end-to-end Noise handshake, so it cannot gate displacement on that:
a challenger cannot handshake until it is spliced, and cannot be
spliced until it displaces.)

- *Established room, phone slot:* the join signature is checked by the
  DO before splicing, so displacement gates on it directly. A new
  connection takes the slot only after verifying against `V`.
- *Pairing room, phone slot:* the DO gates displacement on the pairing
  ticket (also DO-checkable, checked before splicing). Under
  attestation this preserves the intent: only another attested,
  ticketed phone can disturb a mid-pairing victim, never a random
  pre-auth socket. In open mode there is no ticket, so it degrades to
  displace-on-connect, which the per-park cycle cap and SAS voiding
  already bound.
- *Mac slot (always pre-auth, since the Mac cannot attest):* the newest
  Mac-role parker wins. First-wins would be worse: the real Mac's
  silently-dead socket (NAT timeouts can lag WS close detection by
  minutes) would block the real Mac from reclaiming its slot for the
  rest of the window. Newest-wins is self-healing, since the real Mac
  just re-parks. A QR-photo squatter flapping the Mac slot is only a
  nuisance: it lacks the Mac's static private key, so the phone's XK
  handshake against it fails and the attempt burns a cycle against the
  kill cap.

The dangerous shortcut would be to replace a slot on connect
unconditionally; the phone-slot rules above must gate it. A
legitimately displaced device simply reconnects.

**A per-room failed-auth limiter.** A room accepts at most 40 admission
attempts per 10-second window (counted in DO memory, reset on
hibernation). This bounds someone who knows the room name from grinding
auth attempts against an established room, each of which wakes the DO
and bills a request. The Worker may also run advisory per-IP and
per-room buckets ahead of the DO, with the per-isolate caveat below.

**Strict room-name validation ahead of the DO.** The Worker checks the
room header against `^[0-9a-f]{64}$` before addressing the DO, so a
malformed name never reaches DO storage, cardinality, or error paths.

**Expiry.** Pairing-mode state (challenges, tickets, registration
tokens) expires after 5 minutes, so a pairing that never completes
leaves nothing behind and the DO hibernates; there is no long-lived
pairing room. Established rooms carry the 30-day idle TTL described
earlier: kept alive by use, reaped only when unused, removed
immediately by an explicit delete-room at unpair.

## What Cloudflare can and cannot know

**Knows:** both devices' IPs while they are connected, the room
pseudonym, traffic volume and timing, the App Attest key ids (one per
pairing), and the public verifier `V` (which authorizes nothing). The
room pseudonym is stable for the life of the pairing, so over time the
operator can build a per-pairing history of IPs and activity. Rotating
the pseudonym on a schedule (epoch-based names) was considered but
deferred.

**Cannot know:** message plaintext, session images, either device's
static identity key, the raw `roomSecret`, or the `pid` behind the
pseudonym.

**Cannot do:** impersonate either device, splice in a third party (the
Noise handshake fails), originate traffic, or mint a join (it holds
only `V`, and the signed transcript also binds the room and origin).

**Can always do:** deny service, globally or for a specific room, and
observe each room's traffic metadata. That is inherent to any relay;
BYO relay is the remedy for anyone who will not accept it.

Separately, Apple sees pairing cadence: `generateKey` and `attest`
contact Apple from the device, so one key generation per pairing is
visible to Apple (device, app id, timing). That is the cost of the
per-pairing keys. The optional fraud-assessment receipts (Abuse layer
3) would send Apple more.

### Logging and retention commitments (hosted instance)

These describe what the operator controls. Cloudflare's edge keeps its
own connection metadata regardless, which no operator setting can
disable, so the claim is "we don't log," not "nothing is seen." BYO
relay is the remedy for anyone who needs more.

- No operator request logging: Workers logs, tail, and Logpush stay
  off, and the operator persists no IPs anywhere.
- The abuse counters (byte and frame quotas) are coarse, time-bucketed,
  auto-expiring, and keyed by room pseudonym, never by IP.
- An established room's record (its pseudonym, public verifier, and
  opaque attest key id) is deleted on unpair, and otherwise reaped by
  the 30-day idle TTL once the pairing goes unused, so an abandoned
  pairing's record does not persist indefinitely. No IP or content is
  ever part of it.
- Traffic timing and volume are inherent to relaying; no padding or
  cover traffic is added (any future ~100ms coalescing done for cost
  reasons would help here only incidentally).
- Both clients pin their HTTP User-Agent to a fixed string.
  URLSession's default User-Agent would otherwise leak the app version
  and OS build to the relay and Cloudflare's edge logs.
- This covers the Worker's own behavior only. Cloudflare operates the
  underlying platform (TLS termination, edge routing) and may log at
  those layers entirely outside any operator's control, a self-hoster's
  included; BYO relay changes who runs the Worker but still runs on
  Cloudflare, so it does not escape that.

## What each party stores

This consolidates what each party keeps at rest. The design above is
the source of truth; this is a quick reference.

- **Phone.** Keychain (this-device-only, non-synchronizable): the
  phone's Noise static private key, the per-pairing App Attest key (in
  the Secure Enclave), and `roomSecret`. UserDefaults (non-secret): the
  paired `pid`, the Mac's Noise static public key `rs` (from the QR),
  and the relay URL. The join signing keypair is derived from
  `roomSecret` on demand, not stored.
- **Mac.** Keychain: the Mac's Noise static private key and
  `roomSecret`. User defaults: the paired `pid`, the phone's Noise
  static public key (pinned at pairing), and the relay URL (an advanced
  setting). The existing chat database holds chats, messages, and icons.
  The join keypair is again derived from `roomSecret`.
- **Relay room DO.** The room name, the public verifier `V`, the attest
  key id, and coarse byte/frame counters keyed by room name. It never
  stores plaintext, session images, any static key, the raw
  `roomSecret`, or the `pid`.

The asymmetry to notice: the room relay stores only public or
non-authorizing values, so a full dump of it reveals pseudonyms, public
keys, key ids, and traffic counts, and authorizes nothing, then or
later.

### If a location is compromised

- **Relay (dump or full takeover):** pseudonyms, public verifiers, key
  ids, IPs, and traffic metadata. It cannot read messages, cannot mint
  a join (only `V` is stored), and cannot impersonate either device; it
  can deny service and observe metadata.
- **Phone Keychain:** the full pairing, the Noise static, `roomSecret`
  (hence the join key), and the attest key. This is the trusted device;
  this-device-only, non-synchronizable storage confines it to the
  physical phone (migration means re-pairing).
- **Mac:** `roomSecret`, the Mac static, and the chat history. It is the
  peer the phone talks to and is expected to be trusted.
- **Photographed QR (no device):** `rs`, `pid`, and the relay URL,
  which enable a remote pairing attempt, defeated by Mac-side SAS
  confirmation, the QR's short validity, and the per-room handshake cap.

## Abuse and cost control

The relay is a generic ciphertext pipe with an open-source protocol,
so it has to assume hostile clients. The defenses are layered. Layers 1
and 2, plus the admission hygiene above, apply in every configuration;
attestation (layer 3) hardens the hosted instance on top; and BYO relay
(layer 4) is the escape valve.

1. **Lean on the free tier.** Cloudflare's free plan has hard daily
   caps rather than overage billing, so the worst case under attack is
   "remote access unavailable until the caps reset," never a surprise
   bill. Moving to the paid plan is a deliberate operator decision
   later. The operator also enables Cloudflare's daily-cap alerts
   (which need no request logging), so a sustained exhaustion attack is
   distinguishable from "nobody is using remote access."
2. **DO-enforced quotas, sized so normal use never notices but
   tunneling is worthless.** Each room has a daily byte quota (512MB by
   default, tunable); exceeding it tears the room down for the rest of
   the 24-hour window. There are also frame caps, 500 frames per second
   and 256KB per frame, enforced before splicing: a flood of tiny
   frames is a CPU and billing attack that a byte quota alone misses,
   since many small messages can bill as one request-equivalent. The
   per-room counters double as the abuse signal.
3. **App Attest on the hosted instance** (`ATTEST_REQUIRED`): joining a
   pairing room and registering a verifier both require App Attest
   proof from a signed iTerm2 Buddy install. Several limits keep it
   from being trusted too far:
   - `ATTEST_REQUIRED` fails closed. Anything other than the exact
     string `false` means attestation is required, so one botched
     config edit cannot silently open the relay. Only an explicit
     `false` disables it (the BYO path).
   - The verifier checks the attestation's AAGUID, the field that
     identifies which App Attest environment produced it, and on the
     production instance rejects development-environment attestations
     (`appattestdevelop`), accepting only production (`appattest`).
     Skipping this would let any dev-signed build of the app pass during
     the window Apple allows development attestations, a classic App
     Attest mistake. Self-hosted instances configure which environments
     they accept.
   - Attestation proves the install is the signed iTerm2 Buddy app on a
     real Apple device, not that its operator is friendly, and an
     attest key id is not a stable device identity: `generateKey` can
     be called any number of times, so an attacker running a signed
     install can mint a fresh key id per request and walk through any
     key-id-keyed quota. The real backstop is the per-IP rate limit on
     the attestation endpoint (each new key costs an `/attest` call),
     with the WS upgrade limited per IP as well. Apple's
     attestation-receipt fraud assessment, which scores per-device
     key-generation count, could tighten this further but is not
     implemented.

   Per-IP limiting is coarse either way: it over-blocks many phones
   behind one carrier-grade NAT address and under-blocks one phone
   rotating addresses, so it is never trusted alone.
4. **Bring your own relay.** Anyone can `wrangler deploy` the same
   Worker to their own free account (hard-capped, $0) and point the
   Mac's relay setting at it; the QR's `relay=` carries it to the
   phone, so a self-hoster configures exactly one thing on one device.
   Forks sign with their own team and cannot attest against the
   official app id, so BYO relay with `ATTEST_REQUIRED=false` is the
   supported path for them, not just a capacity escape valve. Each
   pairing remembers which relay it lives on, so mixed setups stay
   coherent.

## Implementation notes

- The per-key-id assertion counter can race against itself when the
  phone reconnects rapidly: two assertions are in flight and the
  later-signed one is verified first. A counter rejection should be
  retried with a fresh assertion, not treated as an attack signal.
- App Attest keys cannot be deleted (Apple exposes no API for it), so
  per-pairing keys leave orphaned Secure Enclave material behind across
  re-pairs. This is harmless (each key is unusable once its Keychain
  key id is gone), but worth knowing so it is not mistaken for a leak.
