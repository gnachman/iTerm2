# AI Chat: Cancellation, State, and Persistence Design Issues

This document captures the architectural issues in the AI chat stack that
have surfaced as a recent cluster of bugs around stop / queueing / tool
dispatch, and proposes a phased fix.

## The pattern

The bugs are all expressions of the same underlying issue. Catalog:

1. **Silent stop orphans the queue.** User sends A, A streams a reply,
   user presses Stop, user sends B. B never gets dispatched.
   - Root: `ChatAgent.stop()` called `conversation.stop()` →
     `controller.cancel()`, which set state to `.ground` *silently* and
     never fired the delegate callback. The completion chain from
     `AITermController` → `AIConversation.delegate` →
     `ChatAgent.fetchCompletion` → `ChatService.finishTurn` died at the
     first link. The queue head pointer (A) was never popped; the
     `enqueue(B)` saw `queue.count == 2` and skipped `startNextTurn`.
   - Patched in `ChatAgent.stop()` by routing through
     `conversation.cancelOutstandingOperation()` instead. Pinned by
     `test_chat_stopThenSend_secondMessageStillDispatches`.

2. **Stop during a parked tool dispatch is a no-op.** Same shape as (1),
   but the stop fires while the controller is waiting for the LLM
   framework's function-output. `parseStreamingResponse(final: true)`
   sets `state = .ground` after dispatching the function call, so
   `handle(.cancel)` and `handle(.error)` are *both* ignored by the
   state machine for the entire duration of the tool execution —
   typically seconds.
   - Patched in `AIConversation.cancelOutstandingOperation()` by
     falling back to directly firing
     `delegate.aitermControllerDidCancelOutstandingRequest(controller)`
     when `delegate.busy` is still true after the state machine call.
     Pinned by `test_chat_orphanToolResponseAfterStop_doesNotOrphanQueuedMessage`.

3. **Orphan tool response silently cancels the next queued turn.**
   After (1) and (2) are fixed, the in-flight `PTYSession` command
   eventually finishes and publishes a `.remoteCommandResponse`. The
   dispatcher that was supposed to consume it has been cancelled, so
   `handleRemoteCommandResponse` returns false. The code fell through
   to `fetchCompletionForRegularMessage`, which called
   `conversation.complete → prepare → cancel()` — the *silent* variant
   that sets `delegate.completion = noop`. The actively in-flight
   queued turn (B) had its completion silently overwritten and never
   fired `finishTurn`.
   - Patched in `ChatAgent.fetchCompletion` by dropping orphan
     `.remoteCommandResponse` messages with `completion(nil); return`
     instead of falling through. Pinned by the same test as (2).

4. **Auto-approved `tool_use` not persisted to chat DB.**
   `ChatClient.processRemoteCommandRequest` returns `nil` from the
   broker processor on the `.always` permission path.
   `ChatBroker.publish` interprets `nil` as a full squelch — skips both
   subscriber delivery *and* `listModel.append`. The `tool_use` record
   carrying the LLM's `function_call` (with its `toolu_…` id) never
   lands in the DB. For the current turn that's fine because
   `AIConversation.messages` is in-memory; but when the next turn
   dequeues from the queue, `ChatAgent.load(messages: history)`
   reconstructs from DB, sees an orphan `tool_result` with no
   preceding `tool_use`, and Anthropic 400s.
   - Patched in `ChatAgent.translate` by synthesizing the missing
     `tool_use` whenever a `tool_result` references a request id that
     wasn't persisted. Pinned by
     `test_chat_squelchedToolUseHistoryDoesNotBreakNextTurn`.

5. **`dropLast()` assumes the wrong invariant.**
   `ChatService.startNextTurn` builds B's history as
   `Array(self.messages(chatID:).dropLast())`, on the assumption that
   the last DB row is the in-flight user message. With B typed during
   A's tool round-trip, the DB ends up persistence-ordered as
   `[A, B, tool_use(if not squelched), tool_result, A_reply]`. The
   last row is `A_reply` — `dropLast` drops it. So B's history is
   missing A's full turn outcome (A_reply), and B itself is included
   in history (then re-added via `conversation.add(userAIMessage)`
   in `fetchCompletionForRegularMessage`, duplicating it on the wire).
   - **Not yet fixed.** The current `translate` + `enforceToolUseAdjacency`
     hacks paper over the worst symptoms but the structural assumption
     is wrong.

## Why these are all the same bug

Four observations:

### (a) Four independent representations of "in flight"

| Layer | State for "a turn is running" |
|---|---|
| `AITermController` | `state: State` enum + `cancellation` token |
| `AIConversation` | `delegate.busy` boolean |
| `ChatAgent` | `pendingRemoteCommands: [UUID: PendingRemoteCommand]` + `conversation.busy` |
| `ChatService` | `pendingMessages: [String: [Message]]` |

These four states evolve independently. The bugs are all
"layer X thinks the turn is done, layer Y thinks it's still running" —
or the reverse.

### (b) Silent cancellation paths

`controller.cancel()` (AITerm.swift:205), `AIConversation.cancel()` in
`prepare` (AIConversation.swift:222), and the previous
`AIConversation.stop()` (line 306) all set state to clean and
overwrite `delegate.completion = noop`. They do not fire the delegate
callback. The outer completion chain dies silently.

The recently-fixed bugs are all silent-cancel paths leaking into
visible behavior. There may be more we haven't hit yet:

- `delegate.streaming = nil` in `cancel()` could orphan a partial
  streaming reply.
- `delegate.createVectorStoreCompletion = nil` etc. in `cancel()` could
  orphan a vector-store creation in flight.

### (c) State-machine dead zones

`.ground` ignores every event (AITerm.swift:227-229). But the
controller can sit in `.ground` for arbitrary wall-clock time while
the function-dispatch layer is waiting for a tool result. Cancellation,
errors, even unexpected web responses during that window all evaporate.

The state machine has no `.awaitingFunctionOutput` state. The handoff
from `parseStreamingResponse(final: true)` to `doFunctionCall`
implicitly uses `.ground` as that state, but `.ground`'s catch-all
ignore behavior is wrong for it.

### (d) Three things conflated into one stream

- **The LLM conversation** — strict ordering: alternating user/assistant
  with tool_use immediately followed by tool_result. Used to build the
  API request.
- **The chat history** — what the user sees in bubble UI, persisted to
  SQLite. Lossier and more permissive than the LLM conversation.
- **The dispatch queue** — pending user messages waiting their turn.

All three live in the same `ChatBroker` stream, in the same SQLite
table, with the same ordering. When B is typed during A's in-flight,
B is *immediately* persisted (broker.publish → listModel.append) and
added to ChatService's `pendingMessages` simultaneously. The DB ends
up persistence-ordered, which doesn't match LLM-required ordering
when turns interleave.

The LLM conversation is *reconstructed* from chat history at every
`fetchCompletion` call (`ChatAgent.load(messages: history)`). That
reconstruction has accumulated workarounds:

- `enforceToolUseAdjacency` in `AnthropicRequestBuilder` reorders
  tool_use/tool_result pairs.
- `translate` in `ChatAgent` synthesizes orphan `function_output`
  fillers (line 340-356, for tool_use without tool_result, "iTerm2
  quit mid-tool-call").
- `translate` now also synthesizes orphan `function_call` fillers
  (the recent patch for bug 4).

Each of these is a partial fix for "DB persistence order is not LLM
conversation order."

## Proposed fix

Four pieces, in roughly increasing risk:

### Phase 1 — Eliminate silent cancellation

Make every cancellation that goes through the controller / conversation
fire the delegate callback. Specifically:

- In `AITermController.handle(event:)` for `.ground` state: if
  `delegate.busy` (or `cancellation != nil`), `.cancel` fires
  `aitermControllerDidCancelOutstandingRequest` and `.error` fires
  `didFailWithError`. `.ground` stops being a black hole.

- `AITermController.cancel()` (the silent one used by
  `AIConversation.cancel()`) gets renamed to `tearDown()` and its
  contract documented as "no callbacks; only for teardown after the
  outer caller has already collected what it needs." All current
  callers audited: the `prepare()` site is the suspect one — it's
  used to clean up before starting a fresh `conversation.complete`,
  but the silent overwrite of `delegate.completion = noop` orphans
  any genuinely-in-flight prior call. Replace with
  `cancelOutstandingOperation()` so the prior call's completion fires
  with `.failure(PendingCommandCanceled)` and ChatAgent's existing
  handler does the right thing.

- `AIConversation.stop()` was already changed to use
  `cancelOutstandingOperation()`. Remove the now-unused silent
  variant.

This is a tactical change, contained to two files
(`AITerm.swift` + `AIConversation.swift`). Low risk. Directly
eliminates the bug class described in (b).

### Phase 2 — Real state for function dispatch

Add `.awaitingFunctionOutput` to `AITermController.State`. The
transition from `parseStreamingResponse(final: true)` after a
`function_call` goes to that state instead of `.ground`. The
transition out happens when `doFunctionCall`'s impl.invoke
completion fires (either `.success(output)` → `.querySent` via a new
HTTP request, or `.failure(error)` → state machine processes the
error).

In `.awaitingFunctionOutput`, `.cancel` and `.error` both fire the
delegate. `.word` and `.webResponse` from the original HTTP request
are ignored (the request is done).

Eliminates bug class (c). Localized to `AITermController`. Combined
with Phase 1, makes the existing state of the code self-consistent.

### Phase 3 — Separate dispatch queue from chat persistence

User typing lands in `ChatService.pendingMessages` *only*. Persistence
to the DB and broker delivery happen at *dispatch time*, in the order
the LLM will see them.

Concretely:

- New API: `ChatService.acceptUserMessage(message)` adds to
  pendingMessages without broker.publish.
- UI (ChatViewController) calls this instead of `broker.publish` for
  user-typed messages.
- `startNextTurn` calls `broker.publish` on the dequeued message
  *first* (which persists + delivers to UI subscribers), then
  dispatches.

Consequences:

- `dropLast()` becomes well-defined ("the last DB row IS the in-flight
  user message," by construction).
- `translate` doesn't need orphan-synthesis hacks; the chat history
  matches LLM-required ordering by construction.
- `enforceToolUseAdjacency` becomes unnecessary.
- The `ChatClient.processRemoteCommandRequest` squelch-vs-persist
  conflict goes away: `ChatAgent` itself creates and persists the
  `.remoteCommandRequest` at the right moment in the LLM-history
  order, so there's no need for a separate "show it in UI" path that
  the broker processor was conflating with persistence.

Bigger change. Estimated week of work. Eliminates bug class (d).

### Phase 4 — Structured concurrency for turns

Each turn becomes a `Task`. `ChatAgent.fetchCompletion` becomes an
`async` function. Cancellation propagates through the task hierarchy.
The four-layer callback chain collapses into one async function
where each `await` is a natural cancellation point.

Eliminates bug class (a). Biggest change. Probably 2-3 weeks of
careful refactoring with the live harness tests as the safety net.
Would also unlock substantial readability improvements: the current
ChatAgent has 1000+ lines partly because of the manual completion
plumbing.

## Recommended sequencing

**Phase 1 + Phase 2 together.** They're contained to two files, they
eliminate the entire silent-cancel/dead-zone bug class, and they make
the rest of the code base self-consistent. Ship the live tests we
already have as the regression suite.

**Then Phase 3** if the data-model conflation continues to produce
bugs (it will).

**Phase 4** is the long-term cleanup. Don't block on it.

## What this document is for

These bugs are converging on the same root cause faster than we can
patch the symptoms. This document is the place where the next person
(or the same person on a different day) can read the *shape* of the
problem instead of just the catalog of individual patches.

If you find a fifth bug that looks like one of the patterns above
(silent cancel, state-machine dead zone, persistence-vs-LLM-order,
four-state-machines-out-of-sync), update this doc with the example
and resist the urge to ship another targeted patch.
