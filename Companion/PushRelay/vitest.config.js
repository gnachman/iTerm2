import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

// Runs the push relay inside workerd (real KV, real WebCrypto for the APNs JWT),
// with Apple's push endpoint stubbed via the Miniflare fetchMock (see helpers.js).
// Bindings are declared inline rather than read from wrangler.toml so the test
// env stays independent of the production config (and does not need the Rate
// Limiting binding, which the worker treats as optional and which Miniflare does
// not exercise locally; the IP rate limit is only live on a deployed worker).
//
// APNS_P8 is a throwaway P-256 key generated for tests: it lets the JWT signer
// (crypto.subtle.importKey/sign) succeed. The signature is never verified here
// because Apple is stubbed, so this is not a secret.
const TEST_APNS_P8 = [
  "-----BEGIN PRIVATE KEY-----",
  "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgnjiLVvDqoxAEr50F",
  "Q5IEcY5FGUqvykFYDLxOr7Nn6FehRANCAARj1irFFlMCoD4iS9pNeD6XE/wY6KFh",
  "aA2rAzxkzFeNVZYnNUbNFLRc2G2cWhGGA/MbPTktoQhgwpYnRnoxrtJx",
  "-----END PRIVATE KEY-----",
].join("\n");

export default defineWorkersConfig({
  test: {
    name: "push-relay",
    poolOptions: {
      workers: {
        main: "./src/worker.js",
        miniflare: {
          // The installed workerd caps here; the deployed worker runs the
          // wrangler.toml date. Pinned to the supported date to keep test output
          // clean (the worker uses only stable APIs, so the date is immaterial).
          compatibilityDate: "2025-09-06",
          kvNamespaces: ["PUSH_KV"],
          bindings: {
            APNS_TOPIC: "com.googlecode.iterm2.companion",
            APNS_TEAM_ID: "TEAMID1234",
            APNS_KEY_ID: "KEYID56789",
            APNS_P8: TEST_APNS_P8,
            // Short, explicit TTL so the registration test can assert the
            // self-expiry window precisely instead of probing a 90-day default.
            REGISTRATION_TTL_SECONDS: "3600",
          },
        },
      },
    },
  },
});
