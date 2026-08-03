# AI Model Catalog

iTerm2's list of built-in AI models (context window, capabilities, the API/wire
protocol to use, and the recommended "latest" model per vendor) is data-driven.
Instead of hardcoded constants it is loaded from a JSON catalog that ships in the
app bundle and can be refreshed at runtime by downloading a newer, signed copy.
This lets new models reach users without an app update.

This document covers the moving parts, the runtime refresh + signing scheme, and
the process for publishing an update.

## Files and types

In this repo:

- `OtherResources/ai-models.json` - the bundled catalog (source of truth).
  Schema: a top-level `{ "version": Int, "models": [ ... ] }`. Each model entry
  is described in the header of `AIModelCatalog.swift` and the "ADDING A NEW
  MODEL" checklist in `AIMetadata.swift`.
- `sources/AITerm/AIModelCatalog.swift` - loads the catalog. A private `Codable`
  DTO decodes the JSON and maps it into the existing `AIMetadata.Model`. It
  loads both the bundled snapshot and any downloaded cache and uses whichever
  has the higher `version`. Entries whose `api`/`vendor` string the running app
  does not understand are skipped (fail-safe), not fatal.
- `sources/AITerm/AIModelCatalogUpdater.swift` - the runtime refresher (see
  below).
- `sources/AITerm/AIMetadata.swift` - unchanged public surface; its `models`
  array and `recommended<Vendor>Model` / `alternate<Vendor>Models` accessors now
  read from `AIModelCatalog`.
- `OtherResources/rsa_pub.pem` - the RSA public key used to verify downloaded
  catalogs. Same key pair as the Python runtime download.
- `tools/copy_models.sh` - the publish script (see "Publishing").

Served from the website (`iterm2.com/downloads/ai/`):

- `models.json` - the catalog payload. This is `ai-models.json` from this repo,
  copied verbatim. Stable URL.
- `manifest.json` - the signed manifest the app actually fetches. A JSON array
  of entries `{ version, url, signature, minimum_ai_version?, maximum_ai_version? }`.

The catalog payload and the manifest are two different files because they have
different shapes: the payload is an object (`{version, models}`), the manifest is
an array of download candidates. The app's `aiModelCatalogURL` advanced setting
points at `manifest.json`.

## Three independent version numbers

Do not conflate these:

- **Catalog `version`** (in `ai-models.json` / each manifest entry) - a
  monotonic data revision. The app installs a downloaded catalog only when its
  version is greater than the bundled/cached one, and the manifest entry's
  `version` must equal the version inside the payload it points at.
- **`AIModelCatalog.appCatalogCompatibilityVersion`** - a monotonic integer
  baked into the app describing what the app's AI code can represent. Bump it
  only for a change an older app could not consume gracefully (a new
  `iTermAIAPI` serializer, a new `Model.Feature`, or a new `VectorStoreConfig`
  value that alters how a model is represented or selected). A purely additive,
  optional field older apps ignore when decoding (like `economyModel`) does not
  warrant a bump - a server catalog using it should keep `minimum_ai_version`
  low so older apps still adopt it and just skip the optimization. The manifest
  gates each candidate on an integer `[minimum_ai_version, maximum_ai_version]`
  range against this value. Using an integer (rather than parsing the app's
  version string) is nightly/beta/adhoc-proof.
- **App version string** (`CFBundleShortVersionString`) - not used by the
  catalog machinery at all.

A new *model* on an already-supported serializer is a pure data update. A new
*wire protocol* still needs an app build; a catalog that references it sets
`minimum_ai_version` to the compatibility version where that serializer landed,
so older apps skip that entry and fall back to the highest one they can consume.

## Economy models

A model entry may carry an optional `economyModel` naming a cheaper same-vendor
model (e.g. `claude-opus-4-8` -> `claude-haiku-4-5`). It is for high-frequency,
low-stakes work where the primary model is overkill and too expensive to run
repeatedly - specifically the orchestration screen-watch poller
(`ScreenWatchPoller`), which asks a model every few seconds whether a session has
reached a described condition.

`AIMetadata.economyModel(for:)` resolves a model to its economy alternative
(returning nil when there is none). It works in both "use recommended" mode and
manual mode: if the passed model carries no pointer (settings-built models do
not), it falls back to the catalog entry of the same name.

Crucially, the resolved economy model **preserves the caller's transport** (its
`url` and `api`, hence which host the API key is sent to) and swaps only the
model identity and size limits. A manual-mode user may point a catalog-named
model at a custom base URL (corporate proxy / gateway); resolving to the economy
entry's own public endpoint would bypass that proxy and leak the API key to the
public vendor host. Same-vendor guarantees the economy model speaks the same
protocol, so forcing it onto the configured endpoint is safe.

Because of this, `ScreenWatchPoller` sets `AIConversation.modelOverride` (a full
model used verbatim), not `AIConversation.model` (a name that
`AIConversation.complete` re-resolves against the public catalog). An absent
economy model leaves the poller on the configured chat model.

## Runtime refresh

`AIModelCatalogUpdater` (a singleton, `@objc(iTermAIModelCatalogUpdater)`) runs
silently, with no UI beyond the one-time consent prompt:

1. Download the manifest from `aiModelCatalogURL`.
2. Filter entries to those whose `[minimum_ai_version, maximum_ai_version]` range
   admits this build and whose `version` is newer than what is already loaded,
   ordered highest-version-first.
3. Download the top candidate's payload.
4. Verify the payload's RSA signature (`iTermSignatureVerifier`,
   RSA-PKCS#1-v1.5 over SHA-256) against the bundled `rsa_pub.pem`.
5. Validate that it decodes to at least one usable model, satisfies the catalog
   invariants (see `AIModelCatalog.validate`: every `economyModel` resolves to a
   same-vendor non-self entry; at most one recommended per vendor), and that its
   version matches the manifest entry, then atomically replace the cached
   catalog.

If a candidate fails at any of steps 3-5, the updater falls through to the next
candidate, so one broken top entry (dead URL, botched signing) doesn't stall
updates when an older-but-still-newer good entry exists in the same manifest. The
refreshed catalog takes effect on the next launch. On any failure the previous
cached/bundled catalog is left untouched.

### When it runs

`performPeriodicCheck()` is invoked at app launch (`applicationDidFinishLaunching`)
and again the moment AI is turned on (via the `iTermSecureUserDefaults.didChange`
notification for the `enableAI` key), so a freshly-enabled user does not wait for
a relaunch. It is rate-limited to once per day
(`iTermPersistentRateLimitedUpdate`), and self-gating, so calling it from both
places is idempotent.

### Gating and consent

Downloading contacts the network, which changes the privacy model, so
`performPeriodicCheck` applies three gates in order:

1. **AI must be fully enabled**: allowed in advanced settings and in the secure
   setting (both covered by `iTermAITermGatekeeper.allowed`) and the plugin
   installed (`iTermAITermGatekeeper.pluginInstalled()`). If AI is not set up we
   never download and never even ask.
2. **A non-empty, valid `aiModelCatalogURL`**: clearing it disables checking
   entirely, as the advanced-setting help promises. This is checked BEFORE
   consent so a cleared URL also suppresses the consent prompt (rather than
   asking permission for a download that can never happen). A non-empty URL does
   not by itself enable anything; the other gates still apply.
3. **One-time consent**: a tri-state
   `iTermUserDefaults.aiModelCatalogUpdateConsent` (`.unknown` / `.granted` /
   `.denied`, stored under a `NoSync` key). On first eligible check we present a
   modal; the answer is remembered so we never ask again. A dismissal leaves it
   `.unknown` so we ask again rather than silently disabling updates. An
   in-flight guard prevents stacking a second modal if a queued check re-enters
   while the prompt is open.

## Signing

The signature is a detached RSA signature over the raw bytes of the payload,
base64-encoded:

```
openssl dgst -sha256 -sign "$RSA_PRIV" -out models.sig models.json
openssl base64 -A -in models.sig            # the signature string

# self-check against the shipped public key:
openssl dgst -sha256 -verify OtherResources/rsa_pub.pem -signature models.sig models.json
# -> "Verified OK"
```

`$RSA_PRIV` is the private key matching `OtherResources/rsa_pub.pem` (the Python
runtime signing key; not in the repo). The signature goes in the manifest entry's
`signature` field, not in the payload. The bundled `ai-models.json` is not
signature-checked - its integrity comes from the app's own code signature; only
downloaded payloads are verified.

Gotchas:

- Sign the exact bytes you serve. Any reformatting after signing breaks the
  digest. Sign last.
- The manifest entry's `version` must equal the top-level `version` inside the
  payload, or the app rejects the download.
- The manifest itself is unsigned; that is fine, because nothing it points at can
  be installed without a valid payload signature, and it is fetched over HTTPS.

## Publishing

`tools/copy_models.sh` bridges this repo (source of truth) and the website repo
(`~/iterm2-website`, which serves iterm2.com). It copies the payload, signs it,
updates the manifest, and pushes both live via `scp` to the `bryan` host (the
same mechanism as `update-patrons.sh`).

Full release process (the script automates steps 4-5):

1. Edit `OtherResources/ai-models.json`. Capture any new refusal fixtures the
   tests require (see the "ADDING A NEW MODEL" checklist in `AIMetadata.swift`).
2. Bump the top-level `version`. Mandatory: the app only installs a higher
   version, and it must match the manifest entry.
3. Build and ship the app so the bundled snapshot matches (an app upgrade always
   wins over a stale cache of the same-or-lower version).
4. Run the publish script:
   ```
   RSA_PRIV=/path/to/rsa_priv.pem tools/copy_models.sh
   ```
   It writes `~/iterm2-website/downloads/ai/models.json` and merges an entry into
   `manifest.json` (replacing this version's entry, keeping others), self-verifies
   the signature against `rsa_pub.pem`, `scp`s both files to
   `bryan:iterm2.com/downloads/ai/`, and opens the Cloudflare cache page so you
   can purge the two URLs. Set `AI_MIN_VERSION=<int>` to raise the entry's
   `minimum_ai_version` when the catalog needs a newer app.
5. Commit the website repo (`models.json` + `manifest.json`) so the deploy is
   reproducible.

Because both files sit at stable URLs, a CDN can serve stale copies; purge the
Cloudflare cache for `models.json` and `manifest.json` after pushing. If a stale
payload is briefly served against a newer manifest, the version-mismatch check
rejects it safely (no update until the cache clears) rather than installing
anything wrong.
