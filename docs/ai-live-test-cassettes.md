# AI Live Test Cassettes: Record and Playback

The live AI harness (`tools/run_ai_live.sh`, driving `AILiveHarness` in the
ModernTests bundle) exercises end-to-end round-trips against real vendor
APIs. That costs real money on every run. The cassette layer lets those
same tests replay recorded responses instead of hitting the network.

It rests on one assumption: **a vendor returns the same answer for the same
input.** So we only need to spend money when our request would differ from
one we have already recorded. A request that canonicalizes to a known
cassette is served from disk; a request that differs is sent live (and
recorded for next time).

This is a record/replay (VCR/cassette) scheme, not a vendor-conformance
test. A replayed run validates *our* request builders and response parsers
against a frozen answer. It cannot catch vendor-side drift (a changed
response shape, a new rejection). The pure-live path remains the drift
detector; keep running it on a schedule or before a release. See the
caveats at the end.

## The four modes

The mode is set by `ITERM2_AI_LIVE_CASSETTE_MODE` before invoking
`tools/run_ai_live.sh`, which forwards it into the harness config as
`CASSETTE_MODE`. When unset, nothing changes: the harness behaves exactly
as it did before cassettes existed.

| Mode     | On a cassette hit       | On a cassette miss                        | Touches the network |
| -------- | ----------------------- | ----------------------------------------- | ------------------- |
| `off`    | (no interception)       | (no interception)                         | Always (pure live)  |
| `auto`   | Replay from disk        | Go live, then record the response         | Only on a miss      |
| `replay` | Replay from disk        | **Fail offline** with a `CASSETTE MISS`   | Never               |
| `record` | (ignored) Go live       | Go live                                   | Always; (over)writes every cassette |

- **`off`** (default when unset). No interceptor is installed. Pure live,
  the historical behavior. Use this to capture or refresh genuine vendor
  behavior, or when you specifically want to test against the real API.

- **`auto`**. The everyday cheap mode. The first time a given request is
  seen it goes live and the response is saved; every subsequent run with
  the same input replays for free. Existing cassettes are never
  overwritten in this mode, so a recorded response stays put until you
  delete it or refresh with `record`.

- **`replay`**. The strict, money-free mode for CI. A hit replays; a miss
  does **not** fall through to the network. Instead the call fails with an
  error whose reason begins `CASSETTE MISS`, which fails the test and
  prints the canonical request so you can see what changed. A miss here
  means one of two things: you legitimately changed the request builder
  (re-record), or a real regression. The mode refuses to paper over either
  by silently spending money.

- **`record`**. Deliberate refresh. Every request goes live and its
  cassette is overwritten, regardless of what was on disk. Use this after a
  request-builder change to regenerate the affected cassettes, then review
  the diff before committing.

### Why `replay` fails instead of falling back

A cassette miss is ambiguous. It can mean "the request builder changed and
this is expected" or "something is broken / the vendor drifted." The cache
cannot tell these apart. If a miss silently went live and recorded, a run
would go green by recording whatever the vendor now returns, laundering a
behavior change into a new fixture that nobody reviewed. `replay` mode
forbids that: misses are loud and offline. Refreshing a cassette is always
an explicit `auto`/`record` step a human reviews, mirroring how the
existing `SafetyRefusalFixtures` are opt-in (`REFRESH_REFUSAL_FIXTURES=1`).

## Telling cached from live in the logs

Every request prints one `[cassette]` line to the test output saying what
happened, so you never have to guess whether a value came from disk or the
wire:

```
[cassette] HIT    (replay) key=1931d8e1dfbd POST https://.../v1/chat
[cassette] MISS   (auto, going live) key=c80781daf161 POST https://.../v1/chat [stream]
[cassette] RECORD (auto) key=c80781daf161 (7 chunks)
[cassette] LIVE   (record) POST https://.../v1/chat
[cassette] MISS   (replay, FAILING) key=3f56...648c POST https://.../v1/chat
```

- **HIT** means the response was replayed from a cassette: no network, no
  money.
- **MISS (auto, going live)** then **RECORD** means the request was not
  cached, so it went live and was saved.
- **LIVE (record)** means `record` mode forced a live call to refresh.
- **MISS (replay, FAILING)** means strict mode refused to go live; the test
  fails and the full canonical request is printed beneath the line.
- **REWRITE** appears instead of RECORD when `record` overwrites an existing
  cassette.

The key shown is the cassette filename (truncated for hits/records, full on
a failing miss so you can find or diff `<key>.json`). URLs are scrubbed of
secrets. Replayed calls also produce no `AIChatWireLogger` entry and show
`elapsed` near zero in their capture JSON, but the `[cassette]` line is the
signal to read.

## How a request is matched

The cache key is **not** the raw request bytes. Requests carry per-run
noise that would otherwise miss on every run (and so never save anything).
The canonicalizer (`AICassetteCanonicalizer`) strips that noise before
hashing, so two runs that build the same logical request produce the same
key:

- **API keys.** We know the secret values from the harness config, so each
  is replaced with `<SECRET>` wherever it appears: the `Authorization` /
  `x-api-key` headers and Gemini's `?key=` URL parameter. Two developers
  with different keys hash identically.
- **UUIDs.** Every UUID is replaced with a positional placeholder
  (`<UUID-0>`, `<UUID-1>`, ...) numbered by first appearance. This collapses
  locally minted ids and the random multipart boundary, while keeping two
  genuinely distinct UUIDs distinct.
- **Multipart boundary.** A multipart upload's boundary is per-run random.
  It is echoed in the `Content-Type` header (`boundary=...`), so the
  canonicalizer reads that literal value and replaces it everywhere (header
  and body), independent of whether it is UUID-shaped. For a binary
  (`.bytes`) body the boundary bytes are replaced and the result is
  digested; the file payload itself is a deterministic fixture, so the
  digest is stable.
- **JSON key ordering.** Swift dictionary ordering is not stable across
  runs. String bodies that parse as JSON are re-serialized with sorted
  keys, and headers are sorted by name, before hashing.

The key is the SHA256 of the resulting canonical text. The cassette file is
named `<key>.json` and also stores the canonical request text, so a
`replay` miss is diffable against what you expected.

Recorded responses are scrubbed of secret values too (in case a vendor ever
echoes a key in an error message), which is why cassettes are safe to
commit.

## Where cassettes live

By default, `ModernTests/Resources/AICassettes/`. Override with
`ITERM2_AI_LIVE_CASSETTE_DIR` (forwarded as `CASSETTE_DIR`). Because they
are scrubbed, the intent is to commit them: once recorded, CI and local dev
replay them for free and only the live drift suite spends money.

Transient failures (HTTP 429, the 5xx capacity codes, `RESOURCE_EXHAUSTED`,
`UNAVAILABLE`, timeouts) are **not** recorded, so a capacity blip during a
recording run does not poison a cassette with a failure that would then
replay forever.

## Typical workflows

Populate cassettes once with real keys, then replay for free:

```sh
# Record everything the smoke suite touches.
ITERM2_AI_LIVE_CASSETTE_MODE=auto tools/run_ai_live.sh smoke
git add ModernTests/Resources/AICassettes
git commit -m "Record AI smoke cassettes"

# From now on, free and offline.
ITERM2_AI_LIVE_CASSETTE_MODE=replay tools/run_ai_live.sh smoke
```

Refresh after changing a request builder:

```sh
ITERM2_AI_LIVE_CASSETTE_MODE=record tools/run_ai_live.sh attachmentMatrix
git diff ModernTests/Resources/AICassettes   # review before committing
```

### Running `replay` in CI without real keys

The harness skips a vendor whose API key is absent, and the request builder
embeds the key into the request. So `replay` still needs *a* key per vendor
you want to exercise, but the value is irrelevant: any non-empty placeholder
works because canonicalization neutralizes whatever it is. Set dummy keys in
CI:

```sh
OPENAI_API_KEY=sk-test ANTHROPIC_API_KEY=sk-test \
GEMINI_API_KEY=test DEEPSEEK_API_KEY=sk-test \
ITERM2_AI_LIVE_CASSETTE_MODE=replay tools/run_ai_live.sh
```

## How it hooks in

The interceptor sits at the single network chokepoint,
`iTermAIClient.request(webRequest:stream:completion:)`. It mirrors the
existing `liveObserver`: a static hook (`requestInterceptor`) that is
always compiled in but only set by the test harness. When it returns a
delivery, `request()` replays the recorded stream chunks and final
response/error and fires the same observer and completion a live call
would, so downstream parsers and `AILiveDriver` see an identical sequence
of events. When it returns nil, the call proceeds live as normal. Nothing
in the shipping app sets the hook.

- Production seam: `sources/AITerm/AIPluginClient.swift`
  (`requestInterceptor`, `ReplayDelivery`, the short-circuit in `request`).
- Cassette logic: `AILiveHarness/AICassette.swift` (`AICassetteCanonicalizer`,
  `AICassetteStore`, `AICassetteSession`).
- Wiring: `AILiveHarness/AILiveDriver.swift` installs the interceptor next
  to `liveObserver` in `runOnce` and records from `consume`.
- Coverage: `ModernTests/AICassetteCanonicalizerTests.swift` (keying) and
  `ModernTests/AICassetteReplayTests.swift` (replay through the production
  seam). Both run offline and are not gated by the live config.

## Caveats

- Replay validates our code, not the vendor's. It cannot catch a changed
  response shape or a new rejection. Keep a real-network tier (`off`)
  running on a schedule or before releases to catch drift, especially the
  attachment matrix, whose whole purpose is to fail loudly when vendor
  accept/reject behavior changes.
- A cassette is only as current as its last recording. If a vendor changes
  behavior, replayed tests stay green until you re-record against the real
  API.
