# iTerm2 Companion Relay: Data Flow and Storage

Companion document to `companion-relay-design.md`. That file is the
prose spec and the source of truth; this one is the visual map of
who-holds-what and what-crosses-where. Where they disagree, the
design doc wins.

Legend:

    -->    data in motion (arrow points downstream)
    [E]    travels inside the end-to-end Noise channel (relay sees ciphertext)
    [T]    travels over plain TLS to the relay (relay sees plaintext)
    [QR]   travels via the scanned QR code (camera only, never networked)
    (pub)  public value; exposure authorizes/reveals nothing sensitive
    SAS    Short Authentication String: a few digits (6) derived from the
           Noise handshake hash, shown on both screens; the user confirms
           they match to prove no one is interposed in the channel

---

## 1. The three locations and what each stores at rest

```
+---------------------------+   +---------------------------+   +---------------------------+
|        iPHONE             |   |   CLOUDFLARE (2 Workers)  |   |          MAC              |
|  (iTerm2 Buddy app)       |   |                           |   |   (iTerm2 app)            |
+---------------------------+   +---------------------------+   +---------------------------+
| Keychain, this-device-    |   | Room-relay Worker + DO    |   | Keychain:                 |
| only, non-syncable:       |   | per room:                 |   | - Mac Noise static priv   |
| - phone Noise static priv |   | - roomName (pseudonym)    |   | NoSync defaults:          |
| - per-pairing attest key  |   | - verifier V (pub)        |   | - paired pid              |
|   (Secure Enclave)        |   | - attest key id           |   | - phone Noise static pub  |
| - roomSecret              |   | - reclaim key id (TTL'd)  |   |   (pinned at pairing)     |
| UserDefaults:             |   | - coarse byte/frame       |   | - roomSecret + derived    |
| - paired pid              |   |   counters (by roomName)  |   |   Ed25519 join keypair    |
| - Mac Noise static pub    |   |                           |   | - APNs push state         |
|   (rs, from QR)           |   | NEVER stored: plaintext,  |   | - relay URL (advanced     |
| - relay URL               |   | session images, any       |   |   setting)                |
| - derived Ed25519 join    |   | static key, raw           |   |                           |
|   keypair                 |   | roomSecret, the pid       |   | Chat DB (existing):       |
| - APNs device token       |   |                           |   | - chats, messages, icons  |
|                           |   | Push-relay Worker (sep.   |   |                           |
|                           |   | deployment):              |   |                           |
|                           |   | - APNs token              |   |                           |
|                           |   | - push-secret hash        |   |                           |
|                           |   | - APNs signing key (.p8)  |   |                           |
+---------------------------+   +---------------------------+   +---------------------------+
```

Key asymmetry: the relay stores a PUBLIC verifier, never anything
that authorizes a join. A full storage dump of the relay reveals
pseudonyms, public keys, key ids, and traffic counts, and authorizes
nothing, then or later.

---

## 2. Pairing (first contact) -- what crosses, in order

The QR is the root of trust. Everything else is bootstrapped from it.

```
   MAC                          CLOUDFLARE                     PHONE
    |                                                            |
    |  park FIRST, before the QR is shown, so the room is        |
    |  guaranteed ready when the phone scans:                    |
    |  open WS, roomName [header]                                |
    |------------------------------------> validate header,      |
    |                                       idFromName (DO        |
    |                                       created, pairing mode)|
    |  join frame: {version, role=mac} --->                      |
    |                              (pre-auth Mac slot; the Mac    |
    |                               cannot attest, so no proof)   |
    |                                                            |
    |  THEN show QR on screen:                                   |
    |    rs (Mac static pub), pid, relay URL ........[QR]....... | scan (camera only)
    |  (the DO is name-addressed and persists, so even if the    |
    |   phone somehow arrives first it just waits for the Mac;   |
    |   park-first removes the window and the ambiguity)         |
    |                                                            |
    |                              <----[T] attest challenge req |
    |                              challenge ---[T]------------> |
    |                                                            | App Attest:
    |                                                            |  per-pairing key,
    |                                                            |  clientDataHash =
    |                                                            |  sha256(chal||origin)
    |                              <--[T] attestation (pub) ---- |
    |                              verify chain+appID+origin     |
    |                              ticket (1-use, TTL) --[T]---> |
    |                                                            |
    |                          PHONE races Bonjour vs relay-join |
    |                                                            |
    |                  open WS, roomName [header] <--------------|
    |                  join frame: {version, role=phone} <-------|
    |                  + pairing ticket; DO verifies ticket      |
    |                  then SPLICES the two sockets              |
    |                                                            |
    |<==================== Noise XK handshake ==================>|  (via whichever
    |   (relay splices ciphertext if remote; LAN if Bonjour won) |   transport won)
    |                                                            |
    |  derive SAS from handshake hash       derive same SAS      |
    |  input box (verifier only;            DISPLAY SAS code     |
    |   does NOT show its code)             (Cancel available)   |
    |  (Cancel available)                                        |
    |  *** user reads code off phone, types it into Mac;        |
    |      Mac compares to its own SAS ***                       |
    |                                                            |
    |==========[E] pairing ACCEPTED (or REJECTED) =============>|  phone stops
    |                                                            |  showing SAS,
    |                                                            |  shows chats
    |                                                            |
    |<=========[E] roomSecret (status) =========================|
    |==========[E] ack ========================================>|
    |  derive Ed25519 join keypair          derive same keypair |
    |                                                            |
    |                              <--[T] register verifier V    |
    |                              (assertion + counter; pin     |   (ONLY after ack:
    |                              registrant; room->established)|    establishing the
    |                                                            |    room before the Mac
    |                                                            |    holds roomSecret would
    |                                                            |    strand it)
    |                                                            |
    |<=========[E] chat list, push status, etc. ===============>|
```

What each party learns from pairing:

- Phone: rs, pid, relay URL (from QR); roomSecret (it minted);
  Mac is authentic (Noise XK against the pinned rs); SAS confirmed.
- Mac: phone's static key (encrypted in handshake); roomSecret
  (couriered [E]); SAS confirmed by the user.
- Relay: roomName, attestation (pub), key id, verifier V (pub),
  both IPs, timing. Nothing that reads or joins later.

---

## 3. Remote reconnect (phone on LTE, Mac behind firewall)

No QR, no attestation, no SAS. Both sides already hold the derived
join keypair; they prove possession by signature.

```
   MAC                          CLOUDFLARE (room DO)            PHONE
    |                                                            |
    |  park: open WS, roomName [header]                          |
    |-----------------------------> validate header, idFromName  |
    |  join frame: {version, role=mac} --->                      |
    |                          <---- nonce                       |
    |  sign(transcript: ver||role||nonce||roomName||origin)      |
    |-----------------------------> verify sig vs stored V       |
    |                               (auth-gated slot: mac)       |
    |       ... parked, hibernated, $0 until frames flow ...     |
    |                                                            |
    |                  open WS, roomName [header] <--------------|
    |                  join frame: {version, role=phone} <------ |
    |                  nonce ---------------------------------->  |
    |                  <--- sign(transcript, phone)             |
    |                  verify vs V; slot: phone                 |
    |                                                            |
    |<===== both present: DO splices the two sockets ==========>|
    |<================= Noise XK handshake ====================>|  (fresh keys;
    |                                                            |   no SAS, statics
    |<=========[E] chat frames, session-view PNGs =============>|   pinned at pairing)
```

The relay moves opaque [E] blobs of visible size and timing. One
AEAD failure (relay dropped/reordered/replayed a frame) fatally
tears the transport down -> clean reconnect.

---

## 4. At-home connection (same LAN)

```
   MAC <======== Bonjour discovery + TCP + Noise XK ========> PHONE
                 (RaceTransportConnector: Bonjour wins)
                 zero relay traffic, zero relay metadata,
                 survives relay/ISP outage, ~1-5ms
```

The relay path is attempted in parallel and abandoned when Bonjour
wins. Heavy session-tile (PNG) browsing at home never touches
Cloudflare.

---

## 5. Push notification (phone backgrounded / away)

Separate Worker, separate stored secret, separate deployment so a
compromise of one is not the other.

```
   MAC                       CLOUDFLARE (push-relay Worker)     PHONE / APPLE
    |                                                            |
    |  (phone earlier, [T]) register: APNs token, hash(secret)  |
    |  (phone earlier, [E]) couriered the push secret to Mac    |
    |                                                            |
    |  POST {token, secret, title, body} --[T]-->               |
    |                          verify hash, rate-limit          |
    |                          sign APNs JWT (.p8), forward ---> APNs --> phone
```

The Mac presents the push secret (couriered to it over Noise); the
relay checks it against the stored hash, so the relay can only push
to a phone on behalf of its paired Mac.

---

## 6. What a compromise of each location yields

```
+------------------+--------------------------------------------------+
| Compromised      | Attacker gains                                   |
+------------------+--------------------------------------------------+
| Relay (dump or   | Pseudonyms, public verifiers, key ids, IPs,      |
| full takeover)   | traffic metadata. CANNOT read messages, CANNOT   |
|                  | mint a join (only public V stored), CANNOT       |
|                  | impersonate either device. CAN deny service and  |
|                  | observe metadata. Push-relay (separate) holds    |
|                  | the APNs key; not reachable from this compromise.|
+------------------+--------------------------------------------------+
| Phone Keychain   | Full pairing: Noise static, roomSecret (=> join  |
|                  | key), attest key. This IS the trusted device;    |
|                  | this-device-only + non-syncable confines it to   |
|                  | the physical phone (migration => re-pair).        |
+------------------+--------------------------------------------------+
| Mac              | roomSecret + join keypair + Mac static + chats.  |
|                  | The peer it talks to; expected to be trusted.    |
+------------------+--------------------------------------------------+
| Photographed QR  | rs + pid + relay URL. Enables a remote pairing    |
| (no device)      | ATTEMPT, defeated by Mac-side SAS confirmation,   |
|                  | QR TTL, and per-room handshake/confirm caps.      |
+------------------+--------------------------------------------------+
```

---

## 7. One-line summary per data item

```
rs (Mac static pub)   QR -> phone; pins Mac identity; never secret
pid                   QR -> phone; room-name input; never to relay raw
relay URL             QR -> phone; which relay this pairing uses
Mac static priv       Mac Keychain only; never leaves
phone static priv     phone Keychain only; never leaves
phone static pub      encrypted in handshake -> Mac (pinned)
roomSecret            phone-minted; [E] -> Mac only; never to relay
join keypair          derived from roomSecret on BOTH ends; priv never sent
verifier V (pub)      [T] -> relay; authorizes nothing
attest key id         [T] -> relay; per-pairing; relay-linkable, TTL'd
roomName pseudonym    sha256(label||rs||pid); [header] -> relay
SAS                   derived from handshake hash; shown on both screens
APNs token            [T] -> push-relay; [E]-coupled push secret to Mac
chat data / PNGs      [E] only; relay sees ciphertext blobs
```
