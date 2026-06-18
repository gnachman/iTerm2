# iTerm2 Companion Push Relay

The push relay is a Cloudflare Worker, deployed separately from the
room relay, that lets a Mac send a push notification to its paired
phone when the phone is backgrounded or away. It is a separate
deployment with its own stored secret, so a compromise of one is not a
compromise of the other. See `companion-relay-design.md` for the room
relay it sits alongside.

## What it stores

- The phone's APNs device token.
- A hash of the push secret.
- The APNs signing key (the `.p8`).

## Credential pattern

The push secret follows the same pattern as the room relay's
`roomSecret`: the phone mints it, registers a derived value (its hash)
with the push relay over TLS, and couriers the secret itself to the Mac
inside the Noise channel. The relay only ever stores the hash, never
the secret.

## Sending a push

```
   MAC                     PUSH RELAY (Worker)            APPLE / PHONE
    |                                                          |
    |  (earlier) phone registered: APNs token, hash(secret)    |
    |  (earlier) phone couriered the push secret to the Mac     |
    |                                                          |
    |  POST { token, secret, title, body }  --[TLS]-->          |
    |                       verify hash(secret), rate-limit     |
    |                       sign APNs JWT (.p8), forward ---> APNs ---> phone
```

The Mac presents the push secret it was couriered; the relay checks it
against the stored hash, so the relay will only push to a phone on
behalf of its paired Mac.
