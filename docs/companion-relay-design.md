# iTerm2 Companion Relay: Design

Status: agreed design (revised after six security reviews), not yet
implemented.

NOTE (historical): the LAN / Bonjour (`_iterm2cmpn._tcp`) transport and
the connector/listener race described below were NOT shipped. The relay
is the only transport: it works on any network topology, and the extra
moving parts of a raced LAN path were not worth the latency saved. The
LAN/Bonjour discussion is retained here only as design rationale.
Scope: remote (off-LAN) communication between a paired Mac and
iPhone, including pairing on networks that forbid peer-to-peer
traffic.

## Goal

A paired phone and Mac should be able to communicate whenever both
have internet access. Same-LAN connectivity is an optimization, never
a precondition; in particular, pairing must work on client-isolated
networks (corporate WiFi, hotels) and across networks (phone on LTE,
Mac on ethernet). If a network blocks outbound HTTPS to the relay,
nothing network-bound can work and that is out of scope.

## Non-goals

- Peer-to-peer NAT traversal (ICE/STUN hole punching). VOIP-grade
  P2P exists to save bandwidth and latency that this app does not
  spend: traffic is chat frames and occasional ~100KB session tiles,
  and the primary remote scenario (phone on cellular) sits behind
  carrier-grade NAT where hole punching fails most often anyway. The
  relay's Durable Object would serve as the ICE signaling channel if
  P2P is ever wanted; nothing here forecloses it.
- Background connectivity on the phone. iOS kills our sockets in the
  background; push notifications cover that case.
- Trusting the relay. The relay is a blind splice and must remain
  one. Every protection below must hold even when the Worker runs
  fully open (ATTEST_REQUIRED=false, see Bring Your Own Relay), so
  the quota/admission machinery is a MUST-HAVE on par with
  attestation, not tuning.

## Background: what already exists

- Transport abstraction: `MessageTransport` (framed bytes),
  `TransportConnector` / `TransportListener` (rendezvous),
  `RaceTransportConnector` (phone races all connectors, first to
  connect wins), `CombinedTransportListener` (Mac accepts from
  several at once). Bonjour (`_iterm2cmpn._tcp`) is one conformance,
  and is retained: at-home traffic (the common case, and the heavy
  case for session tiles) stays on the LAN, off the relay, at zero
  cost and zero metadata, and survives relay/ISP outages.
- Security: Noise_XK_25519_ChaChaPoly_BLAKE2s on every connection,
  any transport. The QR pins the Mac's static key (`rs`); the
  handshake prologue binds the pairing id (`pid`). The phone's static
  key crosses only encrypted; the Mac's never crosses at all.
- The push relay: a Cloudflare Worker (Companion/PushRelay) that
  holds the APNs signing key. It established the credential pattern
  reused here: the phone mints a secret, registers a derived value
  with the Worker over HTTPS, and couriers the secret to the Mac
  over the Noise channel.

## Architecture

A room-relay Worker plus a Durable Object (DO) per room. The room
relay is a SEPARATE Worker deployment from PushRelay: the splice
path is the high-traffic, most-attackable surface and must not
share a deployment (or a compromise blast radius) with the APNs
signing key. (Separation splits the blast radius but not the
operator's ability to join the two datasets by IP and timing; see
the threat model.)

Both devices connect outbound via WebSocket (wss), so no inbound
firewall holes exist anywhere; the DO splices frames between the two
sockets and understands nothing it carries.

Rooms are named by an unguessable pseudonym, not the raw pid:

    roomName = sha256("iterm2-room" || rs || pid)

The domain-separation label keeps this hash distinct from any other
use of rs/pid. `rs` only ever travels inside the QR, so the room
name is unknowable to anyone who hasn't scanned it; `pid` is widened
to 16 hex chars (64 bits) since the entropy is nearly free in a QR
and rs is static across pairings, so a leaked QR otherwise leaves
pid as the only unknown in all future room names. This eliminates
room squatting and probing outright (rather than merely bounding
them) and replaces a long-lived linkable pid in Cloudflare's
metadata with an opaque pseudonym.

The room name is passed to the Worker in a request header (or WS
subprotocol field), NOT in the URL path: a path like /room/<name>
lands the stable pseudonym in Cloudflare's edge request logs, which
no operator setting removes. The Worker needs the name before
idFromName, so it cannot wait for the first WS message, but a header
keeps it out of URL-based logging.

The pseudonym is stable for the pairing's lifetime, which means the
relay operator can build a longitudinal IP-and-activity history per
pairing. Epoch-rotating names (roomName = HKDF(rs || pid, epochDay),
Mac parking in current + adjacent epochs to absorb clock skew) were
considered and consciously deferred: real complexity for a metadata
gain that BYO relay already provides to anyone who wants it. Listed
under Future work; the linkability is acknowledged in the threat
model below.

App-side, two new conformances:

- `RelayTransportConnector` (phone): dials the relay, authenticates,
  returns a `MessageTransport` once spliced. Registered alongside
  Bonjour in `RaceTransportConnector`, so LAN wins at home and the
  relay wins everywhere else, with no mode switch and no UI.
- `RelayTransportListener` (Mac): parks in the room while
  advertising (during pairing) and while away-listening (paired but
  disconnected), exactly parallel to the Bonjour listener. Both
  listeners run under the existing `CombinedTransportListener`.

The Noise handshake runs end-to-end through the splice on every
connection, so the relay carries only ciphertext (plus the plaintext
ephemeral public keys inherent to a Noise handshake, which are
useless to it).

Framing: over TCP, frames are 4-byte-length-prefixed; over the
relay, one WebSocket binary message = one frame (the WS layer
provides message boundaries). The >64KB chunking in NoiseChannel is
transport-agnostic and unchanged. The relay enforces its own frame
size cap (well below Cloudflare's 1 MiB WS message limit),
pre-splice.

## App Attest keys

The phone uses a DISTINCT App Attest key per pairing, not one key
across all pairings: a reused key id would let the relay link all of
one phone's rooms. Per-pairing keys cost one extra attestation each
and produce bounded, explainable key churn that composes with the
per-IP new-key caps in Abuse layer 3.

## Credentials and gatekeeping

Two distinct authorization moments.

### Pairing rooms (no shared credential exists yet)

The phone can authorize itself without the Mac: App Attest needs
nothing from the peer.

1. Phone scans the QR, then requests an attestation challenge from
   the relay. The phone refuses non-https relay URLs and refuses
   redirects, and canonicalizes relay= to scheme + host + port only
   at parse time, rejecting any userinfo, path, query, or fragment
   (the phone constructs endpoint paths against the origin itself, so
   embedded path/userinfo tricks have no legitimate use).
2. Phone generates a fresh per-pairing key and attests with
   clientDataHash = sha256(challenge || relayOrigin), where the
   challenge is a fixed, verified length (so concatenating it with
   the variable-length relayOrigin is unambiguous) and relayOrigin
   is the origin the phone believes it is talking to.
   The relay verifies the attestation chain to Apple's root, the app
   ID, AND that relayOrigin is its own. The origin binding closes a
   cross-relay forwarding attack: a hostile QR pointing at
   relay=evil.example could otherwise proxy a genuine challenge from
   the official relay through the phone and spend the official
   instance's resources under a victim device's attestation.
3. The relay issues a pairing-room ticket: single-use, short TTL
   (minutes), bound to the attest key id and the room name.
4. The Mac, which cannot attest (no App Attest off the Mac App
   Store), merely parks in the room it named; the DO activates
   splicing only when a ticketed phone arrives.

Tickets, challenges, and their single-use/TTL state live in the room
DO (which is already addressed by room name), NOT in Workers KV: KV
is eventually consistent and cannot enforce single-use. Outstanding
challenges are capped in count and TTL'd so challenge issuance is
not a storage-fill vector.

### Pairing confirmation (the anti-hijack step)

The relay removes the proximity requirement that made QR leakage
tolerable on LAN: with the relay, a photograph of the QR is
sufficient to pair from anywhere, using a genuine phone and a
legitimate attestation, by racing the real phone into the handshake.
Three mitigations, all required:

- Short pairing validity: the QR/pid expires after a couple of
  minutes; the pairing window regenerates it on expiry.
- Explicit Mac-side verification: pairing is not finalized when the
  Noise handshake completes. Both ends derive the same short
  authentication string (SAS) from the Noise handshake hash (which
  commits to both static keys); the derivation uses a fixed label and
  a specified length (e.g. 6 decimal digits). The UI is asymmetric:
  the PHONE displays the SAS, and the MAC is an input-only verifier,
  the user reads the code off the phone and types it into the Mac,
  which compares it against its own derived SAS. The Mac must NOT
  also display the code: if it did, the user could read the Mac's
  own number and type it back, which always matches and bypasses the
  check. Typed entry (rather than a bare Accept, or a
  select-from-candidates picker) resists blind clicking, the user
  cannot approve without engaging the actual digits. (A picker was
  considered and dropped: its only output is a weaker variant with a
  1/N blind-click
  floor that someone might ship by accident.)
- The SAS commits to ONE handshake. Because slots are newest-wins, a
  displacement can occur while the confirm UI is up (attacker
  connects, victim phone displaces, or vice versa). The Mac's
  pending confirmation is bound to a specific handshake hash and is
  VOIDED, never carried over, the instant a new handshake occupies
  the slot; the SAS is re-derived for the new connection. The phone
  that loses the race does not spin silently: it displays its own
  SAS with "your Mac is showing a code; if it does not match this,
  reject", so a hijacker's SAS on the Mac is visibly wrong to the
  user holding the real phone.
- The phone BLANKS its SAS the instant its connection dies. A 6-digit
  SAS is only ~20 bits; the relay path otherwise lets a photographed-
  QR attacker reconnect repeatedly during the pairing window,
  re-rolling their handshake hash each time, and grind toward a value
  matching the victim phone's still-displayed (now stale) SAS, which
  the user would then type into the Mac. Clearing the phone's SAS on
  disconnect removes the target.
- The DO caps handshake/displacement cycles per pairing room (on the
  order of 5-10): exceeding it kills the room and forces QR
  regeneration. The cap is anchored per park instance, not per QR,
  because a confirmed-but-not-yet-established Mac re-parks in pairing
  mode with no QR (see the lifecycle section); each fresh park gets
  its own budget. With both the attempt cap and the blank-on-
  disconnect rule, grinding 2^20 SAS candidates is dead even in open
  mode.
- Wrong-SAS confirmations count toward the kill cap too. A code typed
  wrong on the Mac is the other observable signature of an active
  hijack (or a typo); two or three failures void the pairing and
  regenerate the QR.
- Explicit accept/reject from the Mac. The SAS is verified only on the
  Mac, so the phone cannot know the outcome on its own; it would
  otherwise sit on the pairing screen forever even on success. After
  the typed code matches, the Mac sends an explicit "pairing accepted"
  control message to the phone over the now-active Noise channel; this
  is the FIRST application message, and it is the phone's signal to
  stop displaying the SAS, transition into the chat list, and only
  then begin the post-confirmation cascade (pushStatus, roomSecret
  courier + ack, verifier registration). The phone sends none of that
  before it arrives. On a wrong code, abort, or timeout, the Mac sends
  an explicit "pairing rejected" message so the phone fails fast
  rather than waiting out its own timeout. The phone also keeps an
  independent pairing-window timeout (absence of accept = failure) and
  blanks its SAS on disconnect/timeout regardless. The phone trusts
  the accept because the channel is end-to-end authenticated by the
  completed handshake (it provably came from the entity the phone
  handshook with) and only the phone that both completed the handshake
  AND whose code the user typed correctly is the one that receives an
  accept; the human's trust decision happened on the Mac.
- Abort at any time, on either end. Both the Mac's confirmation screen
  and the phone's SAS screen carry a visible Cancel/Abort affordance
  throughout the pairing window. Aborting on the Mac sends "pairing
  rejected" to the phone and tears down; aborting on the phone closes
  its connection (which the Mac observes as the slot dying, voiding any
  pending confirmation). Either way no key is pinned, no roomSecret is
  couriered, no verifier is registered, and the room/QR is regenerated
  for a fresh attempt. Abort leaves no half-paired state on either
  side.

The SAS step applies to pairing regardless of transport (it costs
one glance on LAN and closes the photographed-QR hole there too). The
phone's confirmation screen also shows the relay HOST whenever
`relay=` differs from the official default, so a camera-scanned
hostile QR pointing at an attacker relay gets the same disclosure the
(rejected) URL-handler path would have required. The host is rendered
as ASCII/punycode, never the Unicode form, so a confusable lookalike
of the official hostname cannot read as legitimate.

### Established rooms

During the first confirmed session (after Mac-side verification):

The join credential is ASYMMETRIC: the relay stores only a public
verifier, never anything that authorizes a join. Both devices derive
the same Ed25519 signing key from the couriered secret
(`seed = HKDF(roomSecret, "relay-auth-ed25519")`, the public key is
the verifier V); joins are signatures, not HMACs. This means a
one-time Worker compromise or storage dump exfiltrates only public
keys and authorizes nothing, then or later. A symmetric K stored at
the relay would, by contrast, let a single dump persistently occupy
and displace devices in every room until rotation, which in practice
never happens (only on unpair). It also moots a residual TLS-MITM
concern (an enterprise root capturing a symmetric key at
registration), since only V ever crosses TLS. CryptoKit and Workers
WebCrypto both implement Ed25519.

1. The phone mints a 32-byte `roomSecret` (Keychain, rotated on
   unpair, same lifecycle as the push-relay secret) and derives the
   join signing keypair (private signing key + public verifier V).
2. The phone sends `roomSecret` to the Mac inside the Noise channel
   (a field of connection-time status, like `pushStatus`; re-sent
   every connect, self-healing, automatic re-key) and WAITS for the
   Mac's in-channel ack. The Mac derives the same keypair.
3. ONLY THEN does the phone register V with the relay, which
   transitions the room to established. This ordering is critical:
   establishing the room permanently closes pairing-mode admission,
   but the Mac can only join an established room once it holds
   roomSecret. If registration happened first and the session then
   died before the courier arrived, the room would be established,
   the Mac would hold no signing key and could not park, and a
   remote phone would find an empty room recoverable only over LAN,
   defeating the no-P2P guarantee. The reverse failure (Mac acked,
   registration fails) is harmless: the room stays in pairing mode
   and the phone retries on next connect. So ack-before-register is
   strictly safer. The first registration is bound to the pairing
   session mechanically: at phone admission the DO mints a one-time
   registration token; the phone presents it (over HTTPS, a
   different connection than the splice) alongside V, and the DO
   accepts the first V for the room only with a valid, unused token.
   This bounds the open-mode "who registers V" race to the
   pairing-room TTL even though registration does not ride the
   spliced connection. Under ATTEST_REQUIRED it is ALSO authenticated
   by an App Attest ASSERTION over a fresh server-issued challenge
   (clientDataHash = sha256(challenge || origin), the challenge a
   fixed, verified length so the concatenation is unambiguous) AND a
   strictly-increasing counter enforced atomically per key id.
4. The relay pins the registrant at first registration: the attest
   key id under ATTEST_REQUIRED, or the first registrant's V
   otherwise. The DESIGN is that any later re-registration or rotation
   of V must prove possession of the CURRENT signing key (a signature
   over a fresh challenge) before the new V is accepted, so that
   "registration runs on every connect" does not double as an overwrite
   channel for anyone who learns the room name (the only gate left
   in open mode), and so rotation on unpair works because the rotating
   party still holds the current signing key. As implemented today the
   relay enforces this conservatively by refusing ALL re-registration
   (a second registration returns "already registered"); the
   prove-current-key overwrite slice is Future Work (see "Future work"),
   which is why the pinned `registrantKeyId` is stored but not yet read.

Once V is registered, the DO switches admission mode in place and
pairing-mode admission is PERMANENTLY closed for that room: no
second ticketed phone can ever join an established room. The
transition is atomic within the DO.

Join authorization is signature challenge-response: the DO sends a
nonce; the client returns a signature over a fixed-length transcript
of (protocol version byte, role byte, fixed-length nonce, room name,
relay origin), verified against the stored V. Binding the room name
and origin into the transcript makes the signing key structurally
useless outside this room and relay even if a future change reuses
it. The relay never holds anything that authorizes a join, so even a
fully compromised or dumped relay cannot mint one; `roomSecret`
itself never goes anywhere except through the Noise channel to the
Mac.

Signature verification and ticket comparisons are constant-time.

The Mac's legitimacy derives from holding a secret only an attested
phone could have minted and only the paired Mac could have received.

### LAN-paired-then-remote lifecycle

If Bonjour wins the pairing race, the phone never attested, the
relay has never seen a key, and no room exists. To make remote
access "just work" later without a second pairing:

- Verifier registration over HTTPS happens EAGERLY during the first
  confirmed session, regardless of which transport carried it. First
  relay contact in this path performs a full attestation (generate
  per-pairing key + attest), not merely an assertion, since no key
  is registered yet.
- A Mac that is paired-but-disconnected and has never seen the room
  established parks in pairing mode. Pairing-mode rooms expire in
  minutes, so the Mac does not hold such a room open indefinitely;
  it re-parks opportunistically (on the same schedule as Bonjour
  re-advertising) rather than maintaining a permanent pairing-mode
  presence. Once the phone has registered its verifier (which happens
  on its next connect by any transport), the room is established and
  the
  Mac parks persistently as normal.
- CRITICAL: a Mac in this confirmed-but-not-yet-established state is
  the one place a PAIRED Mac sits in a room whose admission policy
  still says "new pairings welcome", so anyone admitted by the DO
  (any ticketed phone under attestation, any peer in open mode) can
  be spliced to it. This listener therefore pins the phone static
  recorded at pairing confirmation and REJECTS any Noise initiator
  presenting a different static, and it never re-enters the
  pairing/SAS confirmation UI; it only completes the handshake with
  the already-confirmed phone. (Noise XK provides this rejection;
  the requirement is that this listener not treat a fresh static as a
  new pairing.) Covered by a test.

In practice the phone registers V within the first confirmed
session, so the never-established window is short; the rule above
just defines behavior if the phone is slow to come back.

### Deletion, revocation, and expiry

Unpair (either side) sends an explicit, AUTHENTICATED delete-room
call in addition to rotating the secret. Both sides authenticate by
signing the delete over a FRESH DO-issued nonce challenge with the
current join key (the same challenge-response as a join, so a
captured delete signature is never replayable; the phone could use an
assertion under ATTEST_REQUIRED, but signature-proof is used
uniformly so delete works in open mode too). An unauthenticated
delete would let anyone holding a room name destroy rooms.

A successful pairing's room is reusable for as long as it is USED:
delete-room is best-effort (relay unreachable at unpair, device
wiped, app deleted), so established rooms ALSO carry an idle TTL of 30
days. Every authenticated contact (a re-park or re-registration)
bumps the room's last-activity stamp, so the TTL never reaps a
pairing in active use; only a room left untouched for 30 days is
deleted, bounding how long an abandoned pairing's pseudonym,
verifier, and attest key id persist in the operator's storage. The
retained data is pseudonymous and authorizes nothing (V is a public
verifier; the room name is a derived hash; the key id is opaque).

A device that returns AFTER its room was reaped re-pairs: its
reconnect finds no verifier (under ATTEST_REQUIRED its signed join is
refused; in open mode the room is simply empty), which surfaces a
"remote access needs re-pairing" affordance rather than failing
silently. Re-pairing mints a fresh pid/room, so even if a leaked-QR
holder squats the reaped room in the meantime it gains nothing: the
real devices never join it (their join key does not match a
squatter's verifier), and they move to a new room on re-pair. This is
why the post-reap "reclaim" path (the original key id reclaiming its
room) is unnecessary here and is not implemented; re-pairing is the
recovery. Verifier ROTATION (overwriting V in place by proving the
current key) likewise remains Future Work; today a re-pair is the
clean path when the same room cannot be reused.

## Pairing flow (the no-P2P guarantee)

1. Mac: generates/loads static keypair, mints pid (16 hex chars),
   starts the Bonjour listener AND parks in relay room
   sha256("iterm2-room" || rs || pid). QR content:

   iterm2://pair?v=1&proto=Noise_XK_25519_ChaChaPoly_BLAKE2s
       &rs=<base64url 32-byte Mac static public key>
       &pid=<16 hex chars>
       &relay=<relay base URL>          (new)

   The QR expires after a couple of minutes and the window
   regenerates it.
2. Phone ingests the QR ONLY through the in-app camera scanner.
   Pairing parameters are not accepted via the system URL handler:
   otherwise a malicious webpage could push a pairing flow with an
   attacker-controlled relay= without any QR. (If a URL-handler path
   is ever wanted, it must show the relay host and require explicit
   confirmation.) The phone stores rs, pid, relay URL with the
   pairing.
3. Phone races connectors: Bonjour discovery vs. attest-and-join on
   the relay. First transport to produce a connection wins; the
   other attempt is abandoned.
4. Noise XK handshake over whichever transport won. Security is
   identical on both: the phone only completes against the scanned
   key; the prologue binds pid.
5. Both screens show the SAS; the user verifies on the Mac (the
   confirmation section). Only then does the bridge go live.
6. Inside the channel: chat list bootstrap, pushStatus, eager
   room-secret mint / courier+ack / verifier registration.

The previous design's hidden assumption, "proximity implies LAN", is
gone. Proximity only ever mattered for delivering the QR, plus one
glance at the SAS.

## Reconnection

The Mac parks in its (established) room whenever
paired-but-disconnected (relay analog of resume-paired-listening,
with the same self-healing retry on listener death). The phone, on
app open or connection loss, races Bonjour vs. relay with the stored
credentials. Either side's reconnect is a fresh Noise handshake (no
SAS after the first confirmation: both statics are pinned from
pairing); the stale-bridge replacement logic on the Mac applies
unchanged.

DO hibernation makes a parked Mac connection effectively free: the
object is evicted from memory while the socket stays open, and
billing accrues only while frames flow. Keepalive pings (needed so
parked connections survive NATs) are answered with the hibernation
API's setWebSocketAutoResponse so they never wake the DO or bill
duration; this protects the cost model's core assumption.

AEAD failure policy: the relay can drop, reorder, or replay frames,
and with Noise's counter nonces any of those surfaces as a
post-handshake AEAD decrypt failure. A single such failure FATALLY
tears down the transport (forcing a fresh handshake), rather than
skipping the offending frame. This turns relay frame games into a
clean reconnect instead of undefined behavior, and the rule is
stated because it gets implemented leniently by default.

## DO admission and connection hygiene

Required in ALL configurations: the open-source Worker must be safe
to run fully open (attestation off), so these are load-bearing, not
tuning.

- The auth exchange must be the first WS traffic: small size cap,
  short deadline, close silently on violation. Pre-auth bytes are
  never buffered or spliced. The join message carries a protocol
  version byte so future admission changes cannot be confused with
  v1. No more than a few (2-4) simultaneous pre-auth sockets per
  room; oldest dropped, bounding per-room memory and wake cost
  during the deadline window.
- Uniform first response to remove an admission-mode oracle. A naive
  DO would reply differently depending on whether the room is
  pairing-mode, established, or absent (different challenge types),
  letting a connector that knows a room name probe its state. The DO
  instead always opens with a generic nonce and branches on what the
  client then presents (ticket vs. signature). Minor (only reachable
  by someone who already holds the unguessable name) but nearly free
  to close.
- Reject any WS upgrade carrying an Origin header. Browsers attach
  Origin to WebSocket upgrades and there is no CORS gate on WS, so
  any webpage could otherwise conscript visitors' browsers into
  burning the daily request cap against invented room names from
  residential IPs that per-IP rules never catch. The native clients
  (URLSession, NWConnection) send no Origin, so one header check
  removes the entire in-browser botnet surface at zero cost. (This
  intentionally conflicts with the "possible web client" future-work
  item; it is the right trade today and trivially reversible.)
- Exactly two slots per room, one per role. Duplicate joins:
  newest wins, but displacement is AUTH-GATED by whatever the DO can
  verify ITSELF (it is blind to the end-to-end Noise handshake, so
  "displace after the handshake" would deadlock: a challenger cannot
  handshake until spliced and cannot splice until it displaces).
  Concretely:
  - Established room (phone slot): the signature proof is DO-side and
    happens BEFORE splicing, so displacement gates on it directly. A
    new connection takes the slot only after verifying against V.
  - Pairing room (phone slot): the DO gates displacement on the
    pairing TICKET (DO-verifiable, checked before splice). Under
    ATTEST_REQUIRED this preserves the intent (only another attested,
    ticketed phone can perturb a mid-pairing victim, never a garbage
    pre-auth socket). In open mode there is no ticket, so it degrades
    to displace-on-connect, which the per-park cycle kill cap and SAS
    voiding already bound.
  - Mac slot (always pre-auth: the Mac cannot attest): newest pre-auth
    Mac-role parker wins. First-wins would let the real Mac's
    silently-dead socket (NAT timeouts lag WS close detection by
    minutes) block reclaim for the rest of the window, breaking the
    legitimate user; newest-wins is self-healing (the real Mac
    re-parks). A QR-photo squatter flapping the Mac slot is harmless
    beyond DoS, since it lacks the Mac static private key so the
    phone's XK handshake fails and the attempt burns the cycle cap.
  The dangerous lenient implementation is "replace slot on connect"
  unconditionally; the phone-slot rules above must gate it. A
  displaced legitimate device simply reconnects. Covered by a test.
- Per-room token bucket on FAILED auth attempts, enforced in the DO
  (cheap; the DO is awake handling the attempt anyway): bounds
  someone who knows the pseudonym from grinding auth attempts
  against an established room, each of which wakes the DO and bills a
  request. The Worker may also run an advisory per-room-name bucket
  pre-DO (it reads the room header before idFromName), with the same
  per-isolate caveat as the per-IP buckets.
- Frames-per-second cap in addition to bytes-per-minute: a flood of
  tiny frames is a CPU/billing attack (20 messages bill as one
  request-equivalent) that byte quotas do not catch. Frame size cap
  enforced pre-splice.
- Bound splice buffering against a slow reader. If one peer reads
  slowly while the other sends tiles, the DO buffers the difference;
  the byte-per-minute quota does not cap instantaneous buffering.
  Apply the byte quota on the SENDING side of the splice and cap
  in-flight buffered bytes per socket, killing the connection on
  overflow.
- Validate the room-name header strictly before idFromName: exact
  length, exact alphabet (the hash's hex), reject otherwise pre-DO.
  Keeps garbage out of DO-name cardinality, storage, and error
  paths.
- Pairing rooms expire after a few minutes; every WS connection has
  a generous (hours) max lifetime so a client bug cannot park
  forever. Established rooms carry a 30-day idle TTL (above): kept
  alive by use, reaped only when unused, removed immediately by an
  explicit delete-room at unpair.

### Gating ahead of the DO (the unattested surface)

Unauthenticated Mac parking is the largest open surface: any wss
upgrade to an invented room name would instantiate a DO and burn a
request against the free tier's hard daily caps. The defenses, with
honest descriptions of what each can actually enforce:

- Cloudflare rate-limiting rules in front of the Worker are the
  PRIMARY pre-DO gate; they are the only layer that coordinates
  across the edge. (Verify before shipping, same standing as the
  hibernation-pricing check: the free plan's rate-limiting budget is
  historically small, roughly one rule with constrained windows and
  IP-only keys. TWO surfaces need real per-IP enforcement, the WS
  upgrades AND the attestation endpoints, the latter guarding the
  Worker's most CPU-expensive code; in-Worker per-IP caps are only
  advisory, so confirm the rule budget covers both or decide
  explicitly which surface gets the scarce rule and what carries the
  other. It carries the whole pre-DO layer.)
  Rate-limiting and WAF rules key on IP and PATH only, NEVER on the
  room-name header: triggered edge events can log the fields a rule
  references, and the header was placed off the URL precisely to keep
  the pseudonym out of edge logs.
- In-Worker per-IP token buckets are ADVISORY only: Worker memory is
  per-isolate, per-PoP, so a distributed attacker never shares an
  isolate and these never form a global limit. Useful against crude
  single-source loops, not against botnets.
- A global cap on concurrent pairing-mode rooms is APPROXIMATE: a
  true cap needs a coordination point (a singleton DO), which is
  itself a hot unauthenticated-reachable object that bills a request
  per garbage upgrade. Implement as sharded counters or a
  periodically-refreshed cached count, not an exact gate.

ATTEST_REQUIRED fails CLOSED: an unset, empty, or unrecognized value
means required, not open. One botched wrangler.toml edit must not
silently turn the hosted instance into an open relay. Only an
explicit, recognized "false" disables attestation (the BYO path).

A distributed attacker can still exhaust the daily cap; the honest
framing stands (worst case is "remote access down until midnight
UTC", never a bill, and LAN is unaffected), and these raise the cost
from one curl loop to a botnet without promising enforcement Workers
cannot deliver.

### Protecting the attestation verifier

Attestation verification (CBOR parse + cert chain to Apple's root)
is the most CPU-expensive code in the Worker and can be fed garbage
by attackers with no device at all. Challenge issuance is capped per
IP, each challenge permits exactly one verification attempt, and
malformed CBOR fails fast before any chain work.

Environment check: the verifier inspects the authData AAGUID and, on
the hosted (production) instance, REJECTS development-environment
attestations (`appattestdevelop`) and accepts only production
(`appattest`). Skipping this accepts any dev-signed build of the app
during the window Apple permits development attestations, a classic
App Attest gotcha. Self-hosted/dev instances configure which
environment(s) they accept.

## What Cloudflare can and cannot know

Knows: both devices' IPs while connected, the room pseudonym (a
stable, linkable per-pairing identifier; see the epoch-rotation
deferral), traffic volumes and timing, App Attest key ids (distinct
per pairing), the public join verifier V (which authorizes nothing).
The push relay, a separate deployment, knows APNs tokens and
push-secret hashes; separating the deployments splits the compromise
blast radius but NOT the operator's ability to correlate the two
datasets by shared IP and
timing. Treat the operator as able to join them.
Separately, Apple sees pairing cadence: generateKey/attest contact
Apple from the device, so the per-pairing-key choice means Apple
observes one key generation per pairing (device, app id, timing).
That is the cost of the otherwise-correct per-pairing keys, and the
optional fraud-assessment receipts (Abuse layer 3) would send Apple
more.
Cannot know (by the relay operator): message plaintext, session
images, either static identity key, the raw roomSecret, the pid
behind the pseudonym.
Cannot do: impersonate either device, splice in a third party (the
Noise handshake fails), originate traffic, or mint a join at all (it
holds only the public verifier; the signed transcript also binds
room and origin).
Can always do, stated plainly: deny service, globally or per-room
selectively, and observe per-room traffic metadata. That is inherent
to any relay; BYO relay is the remedy for users who do not accept
it.

### Logging and retention commitments (hosted instance)

These cover what the operator controls; Cloudflare's edge retains
its own connection metadata regardless, which no operator setting
removes. The honest claim is "we don't log", not "nothing is seen";
BYO relay is the remedy for those who need stronger.

- No operator request logging: Workers logs/tail/Logpush stay off.
  The operator persists no IPs anywhere.
- Abuse counters (the byte/frame quotas) are coarse, time-bucketed,
  auto-expiring, and keyed by room pseudonym, never by IP.
- An established room's record (its pseudonym, public verifier, and
  opaque attest key id) is deleted on unpair, and otherwise reaped by
  the 30-day idle TTL once the pairing stops being used, so an
  abandoned pairing's pseudonymous, non-authorizing record does not
  persist indefinitely. No IP or content is ever part of this record.
- Traffic timing/volume metadata is inherent to relaying; no padding
  or cover traffic is attempted (the ~100ms delta coalescing planned
  for cost reasons helps incidentally).
- Both clients normalize their HTTP User-Agent to a fixed string.
  URLSession's default UA leaks app version and OS build to the relay
  and Cloudflare's edge logs; pinning it to a constant keeps that out,
  consistent with the metadata-minimization posture.

## Abuse and cost control

The relay is a generic ciphertext pipe and the protocol is open
source. Layered defenses; layers 1 and 2 plus the admission hygiene
above are must-haves in every configuration, and attestation hardens
the hosted instance on top:

1. Free plan first. Cloudflare's free tier has hard daily caps, not
   overage billing; the worst case is "remote access unavailable
   until midnight UTC", never a bill. LAN service is unaffected.
   Upgrading to the $5 paid plan is a deliberate operator decision
   later. (Verify before shipping, alongside the rate-limiting check
   above: that SQLite-backed DOs with WebSocket hibernation are
   included on the current free plan; this claim carries the whole
   layer. Believed true as of this writing.) Operationally, commit to
   a Cloudflare notification on daily-cap approach/exhaustion (these
   alerts need no request logging), so a sustained quota-exhaustion
   attack is distinguishable from "nobody is using remote access" and
   the operator can react (raise limits, deploy paid, investigate).
2. DO-enforced quotas sized so chat + session viewing never notice
   but tunneling is worthless. Initial values, tunable in
   wrangler.toml: 5MB/min burst per room (session tiles are bursty),
   ~100MB/day per room, frame size cap, frames/sec cap. Per-room
   counters double as the abuse dashboard.
3. App Attest on the hosted instance (ATTEST_REQUIRED): pairing
   rooms and verifier registration require a genuine signed iTerm2 Buddy
   install. Two caveats keep this from being trusted naively:
   - An attest key id is NOT a stable per-device identity.
     generateKey can be called repeatedly, so a malicious genuine
     device can mint a fresh key id per request and walk through
     key-id-keyed quotas. Key-id quotas are therefore SOFT. Hard
     backstops: per-IP caps on NEW key registrations (key churn is
     the tell, and note our own per-pairing keys produce only
     bounded churn), and optionally Apple's server-to-server
     attestation-receipt fraud assessment, whose risk metric
     includes the per-device key-generation count.
   - Even without churn, one genuine key id can mint many rooms
     (100MB/day each) for generic relaying with a scripted peer. So
     also cap concurrent rooms per attest key id to a small number.
   Per-IP limits otherwise remain the coarse backstop for the
   unattested surface; on their own they both over-block (many
   phones behind one CGNAT address) and under-block (one phone
   rotating addresses), which is why neither axis is trusted alone.
4. Bring your own relay. Anyone can `wrangler deploy` the same
   Worker to their own free account (hard-capped, $0) and point the
   Mac's advanced setting at it; the QR's `relay=` parameter
   propagates it to the phone, so self-hosters configure exactly one
   thing on one device. Self-builders sign with their own team and
   cannot attest against the official app ID, so BYO relay (with
   ATTEST_REQUIRED=false) is the supported path for forks, not just
   a capacity escape valve. Each pairing remembers which relay it
   lives on, so mixed setups stay coherent.

## Cost model (estimate-grade, published pricing)

No egress charges on Workers/DO WebSocket traffic, which is what
makes PNG tiles affordable. With hibernation, message deliveries
bill at 20 messages per request-equivalent and duration only while
awake (keepalives excluded via auto-response, above). A daily-active
remote user doing ~5 min of actual frame flow costs ~1,100
GB-s/month of DO duration; the paid plan's included 400k GB-s covers
roughly 300-400 such users, after which costs run about 1-2 cents
per daily-active user per month (10k DAU is on the order of
$150/month). Duration is the binding meter; message counts and
storage are noise. Bonjour keeps at-home usage (the bulk, and the
heavy tile traffic) off the relay entirely. If streaming deltas ever
dominate, the Mac can coalesce appends over ~100ms windows on the
relay transport only (~10x frame reduction, imperceptible latency).
If tile bytes ever dominate, switch the session renderer to
HEIC/JPEG.

## Future work

- P2P upgrade: the room DO is the ICE signaling channel if direct
  paths ever matter; STUN via public servers; relay remains the
  fallback. Only worth it if relay latency annoys in practice.
- Epoch-rotating room pseudonyms (consciously deferred; see
  Architecture).
- Apple attestation-receipt fraud assessment if key churn shows up
  in practice (see Abuse layer 3).
- Replacing flaky mDNS discovery (not the LAN path itself) with the
  Mac registering its current LAN address in the room DO, so the
  phone can attempt a direct LAN TCP connect without Bonjour. Only
  if the mDNS bug tax stays high after the relay ships.
- Session-list change pushes and other protocol growth ride the same
  channel and need nothing from the relay.
- Possible web client: anything that can attest-or-hold-a-secret and
  speak Noise can join a room; the relay does not care.
- Verifier rotation is NOT implemented today. The relay pins the
  first verifier and refuses any second registration outright
  ("already registered"); there is no prove-current-key-to-overwrite
  slice. The `registrantKeyId` the DO records at first registration is
  therefore dormant storage, written but never read as a live control;
  it exists only so a future rotation feature has the pin it needs.
  The one consequence is that unpair-and-re-pair cannot reuse the same
  room while the old established room still exists (the new verifier is
  refused). The working path is the authenticated delete-room at
  unpair, which the relay DOES implement and the clients DO call, so a
  re-pair is clean; if that delete never reached the relay (offline
  unpair, wiped device, deleted app) the orphan room is instead reaped
  by the 30-day idle TTL, after which the same pid pairs cleanly again.
  A post-reap "reclaim" (the original key id re-taking its room without
  re-pairing) is deliberately NOT implemented: a reaped room means the
  user re-pairs anyway, and re-pairing mints a fresh room, so a leaked-
  QR squatter of the reaped room gains nothing.

## Implementation sketch

- Room-relay Worker (separate deployment from PushRelay): room DO
  (challenge-response admission with versioned fixed-length join
  transcript binding room name + origin, splice, quotas,
  newest-wins slots with SAS-voiding semantics during pairing,
  per-park handshake/displacement attempt cap, pre-auth socket cap,
  newest-wins among pre-auth Mac parkers, short pairing-room lifetimes
  + 30-day established-room idle TTL (kept alive by use), hibernation with setWebSocketAutoResponse
  for keepalives, atomic ticket/challenge/counter state, one-time
  registration-token mint at phone admission, stores only the public
  verifier V (never a join-authorizing secret), registrant-pinning
  (prove-current-signing-key-to-rotate is Future Work; today a second
  registration is simply refused), ticket-gated pairing-room
  displacement (signature-gated in established rooms), in-place
  pairing->established transition (only AFTER the phone confirms the
  Mac acked roomSecret), per-room
  failed-auth token bucket, slow-reader
  buffer cap (kill on overflow), signature-authenticated delete-room),
  strict room-name
  header validation and Origin-header rejection pre-DO, room name via
  request header (not URL path), /attest challenge + verification
  with origin binding and fail-fast CBOR validation, assertion
  verification (fresh challenge + atomic counter, counter rejection
  treated as RETRYABLE not hostile, see note), single-use
  key-id-bound pairing tickets bound to first V registration, pre-DO
  gating (Cloudflare rate-limiting rules primary; advisory per-IP and
  per-room buckets; approximate pairing-room global cap), per-key-id
  room cap, constant-time comparisons, ATTEST_REQUIRED fails closed,
  wrangler.toml knobs (ATTEST_REQUIRED, quota values).
- Shared: PairingCode gains relay URL parsing/encoding (https-only),
  pid widened to 16 hex; room-name derivation
  sha256("iterm2-room" || rs || pid); join signing keypair from
  HKDF(roomSecret, "relay-auth-ed25519") (Ed25519, both devices);
  wire status message gains roomSecret field; SAS derivation from the
  Noise handshake hash (fixed label, specified digit length);
  Mac->phone pairing accept/reject control message (first post-SAS
  application message).
- CompanionTransport: RelayTransportConnector / -Listener
  (URLSessionWebSocketTask on the phone, NWConnection or
  URLSessionWebSocketTask on the Mac; room name in a header; fixed
  normalized User-Agent on all relay HTTP/WS requests both ends),
  translated into the existing TransportError taxonomy.
- Phone: App Attest helper (DCAppAttestService: per-pairing
  generateKey/attest at pairing, generateAssertion with server
  challenges thereafter, counter-rejection retry), Ed25519 join
  keypair from roomSecret, eager verifier registration in
  connect-time status flow ONLY after the Mac acks roomSecret over
  the Noise channel, roomSecret + per-pairing attest key id in
  Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
  non-synchronizable, beside the push secret; migration = re-pair,
  consistent with the Secure-Enclave-bound attest key not migrating;
  unpair removes the key id from Keychain and orphans the SE key,
  which has no delete API), one-time registration-token presentation
  with V, relay-URL canonicalization (scheme+host+port), camera-only
  pairing ingestion, punycode relay-host disclosure on the
  confirmation screen when relay != default, typed-SAS display that
  blanks on disconnect with match-or-reject guidance when it loses
  the race, waits for the Mac's pairing-accept message before leaving
  the pairing screen (independent window timeout = failure; explicit
  reject fails fast), Cancel affordance on the SAS screen throughout
  the window, fatal teardown on AEAD failure, "remote access needs
  re-pairing" affordance on join/registration rejection.
- Mac: park-in-room listener under CombinedTransportListener
  (pairing-mode re-park enforcing the pinned phone static and never
  re-entering pairing UI, newest-wins among pre-auth Mac parkers,
  per-park cycle-cap anchor, vs. established persistent park),
  typed-SAS verifier (input only, never displays its own code),
  sends pairing accept on match / reject on wrong-code-or-abort,
  Cancel affordance on the confirmation screen throughout the window,
  in-channel ack of roomSecret receipt, roomSecret + derived join
  keypair in Keychain (this-device-only, non-synchronizable, beside
  the push registry), advanced setting for the relay URL, QR
  expiry/regeneration in the pairing window, typed-SAS verification
  bound to one handshake hash and voided on displacement, fatal
  teardown on AEAD failure, signature-authenticated delete-room on
  unpair, "remote access needs re-pairing" affordance on rejection.

## Implementation notes (not design changes)

- The per-key-id assertion counter can race against itself when a
  phone reconnects rapidly: two assertions in flight, the
  later-signed one verified first. Treat counter rejection as
  retryable with a fresh assertion, NOT as an attack signal.
- App Attest keys cannot be deleted (no API). Per-pairing keys
  therefore accumulate orphaned Secure Enclave key material across
  re-pairs. Harmless (each is unusable once its Keychain key id is
  gone), worth knowing so it is not mistaken for a leak.
