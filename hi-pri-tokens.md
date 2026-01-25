# High-Priority Token Categories - Functional Requirements

This document describes the functional requirements for "high-priority" token injection paths in iTerm2, independent of implementation details. These requirements should guide the design of any scheduling or fairness system.

---

## Category A: Synchronous Trigger Injection

**What:** When a trigger pattern matches terminal output, inject a response into the terminal stream.

**Example use case:** Auto-typing a password when a prompt appears.

**Functional requirements:**
- Injected data must execute **before the next token** from the same session processes
- Later triggers on the same line may depend on seeing the injected content
- Ordering is causally critical: Trigger B might match text that Trigger A injected

**State effects:** Session only (terminal buffer, cursor, modes)

**Key insight:** This is intra-session ordering, not inter-session competition. The injected data is part of processing *this session's* stream.

---

## Category B: API Injection

**What:** External programs inject data into terminal sessions via the iTerm2 API.

**Example use cases:**
- Remote automation scripts
- AI assistants sending commands
- Workflow orchestration tools

**Functional requirements:**
- **Injected data must execute as a contiguous, atomic block** - not interleaved with other data

**Why atomicity matters:**
1. **Parser integrity** - ANSI escape sequences (e.g., `\x1b[31m` for red) corrupt if split by interleaved PTY data
2. **Shell integration markers** - Prompt markers like `\x1b]133;...` lose semantic meaning if fragmented
3. **Stateful protocol** - VT100 parser is a state machine; partial sequences in wrong order cause cascading errors

**Caller expectation:** Fire-and-forget (no completion callback), but expects injected block to remain coherent.

**Scheduling implication:** Should be scheduled as a complete unit - "take a turn with this whole block" not "compete token-by-token."

---

## Category C: Session Startup Injection

**What:** Pre-populate a new session with initial content at creation time.

**Example use cases:**
- Python REPL welcome banners
- Initial shell commands
- Pre-filled content in viewer windows

**Functional requirements:**
- Must complete before normal PTY input begins
- One-time event at session creation
- Not recurring

**Scheduling implication:** N/A - happens before the session enters any scheduling system.

---

## Category D: Trigger Side Effects

These are non-token actions triggered by pattern matches. Each has distinct ordering requirements.

### D1. Variable Setting
- **Purpose:** Set session variables when patterns match
- **Downstream readers:** Other triggers (backreferences), shell integration (prompt context), API scripts
- **Ordering requirement:** Variable must be set BEFORE any downstream code reads it
- **Failure mode:** Downstream operations use stale values (e.g., wrong directory recorded with prompt)

### D2. Input Buffering
- **Purpose:** Start/stop buffering terminal input (e.g., during compilation)
- **Ordering requirement:** Start buffering BEFORE buffered input arrives; stop AFTER
- **Failure mode:** Input leaks through or buffering gets stuck on

### D3. Text Sending
- **Purpose:** Send text to PTY as if user typed it
- **Ordering requirement:** Commands must execute in sequence
- **Failure mode:** `cd /tmp` then `ls` reversed → lists wrong directory

### D4. Directory/Hostname Reporting
- **Purpose:** Track current working directory and host for shell integration
- **Ordering requirement:** Must be set BEFORE prompt detection and coprocess launch
- **Failure mode:** Directory breadcrumbs wrong; coprocesses operate in wrong path

### D5. Mark Creation
- **Purpose:** Create named positions in scrollback
- **Ordering requirement:** Mark must exist BEFORE fold/reference operations
- **Failure mode:** Fold fails with "named mark not found"

### D6. Fold Operation
- **Purpose:** Collapse regions between marks
- **Ordering requirement:** Referenced mark must already exist
- **Failure mode:** Silent failure if mark doesn't exist

### D7. Prompt Detection
- **Purpose:** Identify shell prompts for command history/navigation
- **Ordering requirement:** Must fire AFTER all content on that line is rendered
- **Failure mode:** Wrong content marked as prompt

### D8. Highlighting
- **Purpose:** Apply colors to matched text
- **Ordering requirement:** Must apply AFTER content is positioned
- **Failure mode:** Highlights wrong cells or stale content

### D9. Annotations/Hyperlinks
- **Purpose:** Attach metadata (links, notes) to screen cells
- **Ordering requirement:** Must attach AFTER content is positioned
- **Failure mode:** Annotations attach to wrong positions

### D10. Coprocess/Command Launch
- **Purpose:** Start external processes when patterns match
- **Ordering requirement:** Session state (directory, hostname, variables) must be set BEFORE launch
- **Failure mode:** Process operates with wrong state (wrong directory, missing variables)

### D11. Captured Output
- **Purpose:** Save matched output for later reference
- **Ordering requirement:** Capture AFTER content finishes rendering
- **Failure mode:** Captures incomplete output

### D12. Scroll Control
- **Purpose:** Freeze scroll position when pattern matches
- **Ordering requirement:** Must save AFTER triggering content is visible
- **Failure mode:** Scrolling continues past important content

### D13-D17. UI Effects
- **Includes:** Alerts, notifications, bell, password manager, session title changes
- **Ordering:** Less critical but should reflect actual event timing

---

## Summary: Ordering Constraints

### Must be strictly ordered:

**State → Dependent Action:**
- Variable set → Code using variable
- Directory set → Coprocess launch / Prompt detection
- Hostname set → Shell integration
- Mark created → Fold operation
- Buffer start → Input arrives

**Content → Metadata:**
- Content rendered → Highlighting applied
- Content positioned → Annotations attached
- Prompt detected → Shell integration triggered

**Event → Effect:**
- Input buffering started → Input buffered
- Alarm trigger → Bell sounds
- Prompt detected → Marks/state updated

### Atomicity requirements:

- **API injection:** Entire injected block must be contiguous (not interleaved)
- **Trigger injection during evaluation:** Synchronous execution required
- **Startup injection:** Must complete before normal flow begins

---

## Design Implications for Fairness Scheduling

1. **Category A (trigger injection during eval):** Exempt from fairness - it's a subroutine of the current session's turn

2. **Category B (API injection):** Participates in fairness, but as atomic blocks, not individual tokens

3. **Category C (startup injection):** Exempt - happens before scheduling begins

4. **Category D (trigger side effects):** Must maintain ordering relative to token processing within the same session; some have cross-session implications (coprocess launch reads session state)

---

## Current Implementation: Token Flow Diagrams

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           REGULAR TOKEN FLOW                                     │
│                                                                                  │
│  TaskNotifier Thread                                                             │
│  ┌─────────────────┐                                                             │
│  │ select() loop   │                                                             │
│  │ detects FD      │                                                             │
│  │ readable        │                                                             │
│  └────────┬────────┘                                                             │
│           │                                                                      │
│           ▼                                                                      │
│  ┌─────────────────┐                                                             │
│  │ PTYTask         │                                                             │
│  │ .processRead()  │                                                             │
│  │ reads bytes     │                                                             │
│  └────────┬────────┘                                                             │
│           │                                                                      │
│           ▼                                                                      │
│  ┌─────────────────┐                                                             │
│  │ VT100ScreenMutableState                                                       │
│  │ .threadedReadTask:length:                                                     │
│  │ parses → tokens │                                                             │
│  └────────┬────────┘                                                             │
│           │                                                                      │
│           ▼                                                                      │
│  ┌─────────────────┐                                                             │
│  │ addTokens:      │                                                             │
│  │ highPriority:NO │                                                             │
│  └────────┬────────┘                                                             │
│           │                                                                      │
│           ▼                                                                      │
│  ┌─────────────────────────────────────┐                                         │
│  │ TokenExecutor.addTokens()           │                                         │
│  │                                     │                                         │
│  │  semaphore.wait() ◄─── BLOCKS HERE  │                                         │
│  │  if queue full                      │                                         │
│  │                                     │                                         │
│  │  reallyAddTokens()                  │                                         │
│  │    → tokenQueue.queues[1].append()  │ ◄─── QUEUE 1 (normal priority)          │
│  │                                     │                                         │
│  │  queue.async { didAddTokens() }     │ ◄─── Schedules execution on             │
│  └─────────────────────────────────────┘      mutation queue                     │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────────┐
│                     HIGH-PRIORITY FLOW #1: External (API/Startup)                │
│                                                                                  │
│  Any Thread (Main, API socket, etc.)                                             │
│  ┌─────────────────┐                                                             │
│  │ iTermAPIHelper  │    OR    ┌─────────────────┐                                │
│  │ .inject:into:   │          │ iTermController │                                │
│  └────────┬────────┘          │ (startup)       │                                │
│           │                   └────────┬────────┘                                │
│           └───────────┬────────────────┘                                         │
│                       ▼                                                          │
│              ┌─────────────────┐                                                 │
│              │ PTYSession      │                                                 │
│              │ .injectData:    │                                                 │
│              └────────┬────────┘                                                 │
│                       ▼                                                          │
│              ┌─────────────────┐                                                 │
│              │ VT100Screen     │                                                 │
│              │ .injectData:    │                                                 │
│              └────────┬────────┘                                                 │
│                       │                                                          │
│                       ▼                                                          │
│  ┌─────────────────────────────────────────────────────────────┐                 │
│  │ mutateAsynchronously: { mutableState.injectData: }          │                 │
│  │                                                             │                 │
│  │ Dispatches block to MUTATION QUEUE                          │                 │
│  └─────────────────────────────────────────────────────────────┘                 │
│                       │                                                          │
│                       ▼                                                          │
│                                                                                  │
│  ════════════════ MUTATION QUEUE ════════════════════════════                    │
│                                                                                  │
│              ┌─────────────────┐                                                 │
│              │ VT100ScreenMutableState                                           │
│              │ .injectData:    │                                                 │
│              │ parses → tokens │                                                 │
│              └────────┬────────┘                                                 │
│                       ▼                                                          │
│              ┌─────────────────┐                                                 │
│              │ addTokens:      │                                                 │
│              │ highPriority:YES│                                                 │
│              └────────┬────────┘                                                 │
│                       ▼                                                          │
│  ┌─────────────────────────────────────┐                                         │
│  │ TokenExecutor.addTokens()           │                                         │
│  │                                     │                                         │
│  │  (NO semaphore wait)                │ ◄─── Does NOT block                     │
│  │                                     │                                         │
│  │  reallyAddTokens()                  │                                         │
│  │    → tokenQueue.queues[0].append()  │ ◄─── QUEUE 0 (high priority)            │
│  │                                     │                                         │
│  │  return (no queue.async!)           │ ◄─── Does NOT schedule execution        │
│  └─────────────────────────────────────┘                                         │
│                                                                                  │
│  Tokens sit in queue[0] until something else triggers execute()                  │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────────┐
│              HIGH-PRIORITY FLOW #2: Trigger (during token execution)             │
│                                                                                  │
│  ════════════════ ALREADY ON MUTATION QUEUE ═══════════════════                  │
│                                                                                  │
│  ┌─────────────────────────────────────────────────┐                             │
│  │ TokenExecutor.execute()                         │                             │
│  │   └─► executeTokenGroups()                      │                             │
│  │         └─► VT100Terminal.execute(token)        │                             │
│  │               └─► trigger fires                 │                             │
│  │                     └─► InjectTrigger           │                             │
│  └──────────────────────────┬──────────────────────┘                             │
│                             │                                                    │
│                             ▼                                                    │
│              ┌─────────────────────────────┐                                     │
│              │ triggerSession:injectData:  │                                     │
│              │ (VT100ScreenMutableState)   │                                     │
│              └──────────────┬──────────────┘                                     │
│                             │                                                    │
│                             ▼                                                    │
│              ┌─────────────────┐                                                 │
│              │ VT100ScreenMutableState                                           │
│              │ .injectData:    │  ◄─── Called DIRECTLY (no mutateAsynchronously) │
│              │ parses → tokens │                                                 │
│              └────────┬────────┘                                                 │
│                       ▼                                                          │
│              ┌─────────────────┐                                                 │
│              │ addTokens:      │                                                 │
│              │ highPriority:YES│                                                 │
│              └────────┬────────┘                                                 │
│                       ▼                                                          │
│  ┌─────────────────────────────────────┐                                         │
│  │ TokenExecutor.addTokens()           │                                         │
│  │                                     │                                         │
│  │  (NO semaphore wait)                │                                         │
│  │                                     │                                         │
│  │  reallyAddTokens()                  │                                         │
│  │    → tokenQueue.queues[0].append()  │ ◄─── QUEUE 0 (high priority)            │
│  │                                     │                                         │
│  │  return                             │                                         │
│  └─────────────────────────────────────┘                                         │
│                             │                                                    │
│                             │ Returns to...                                      │
│                             ▼                                                    │
│  ┌─────────────────────────────────────────────────┐                             │
│  │ ...executeTokenGroups() continues               │                             │
│  │                                                 │                             │
│  │ Next iteration of enumerateTokenArrayGroups     │                             │
│  │ will pull from queue[0] FIRST (high priority)   │                             │
│  │ before continuing with queue[1]                 │                             │
│  └─────────────────────────────────────────────────┘                             │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────────┐
│                              EXECUTION (Consumption)                             │
│                                                                                  │
│  ════════════════ MUTATION QUEUE ═══════════════════════════════                 │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐                 │
│  │ TokenExecutorImpl.execute()                                 │                 │
│  │                                                             │                 │
│  │   tokenQueue.enumerateTokenArrayGroups { group, priority    │                 │
│  │                                                             │                 │
│  │     nextQueueAndTokenArrayGroup:                            │                 │
│  │       for i in [0, 1]:           ◄─── Checks queue[0] FIRST │                 │
│  │         if queues[i].firstGroup:                            │                 │
│  │           return it                                         │                 │
│  │                                                             │                 │
│  │     executeTokenGroups(group, priority)                     │                 │
│  │       for each token:                                       │                 │
│  │         terminal.execute(token)                             │                 │
│  │         (triggers may fire here → re-entrant injection)     │                 │
│  │   }                                                         │                 │
│  └─────────────────────────────────────────────────────────────┘                 │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Key Observations

1. **Regular tokens (PTY):** Block on semaphore, go to queue[1], trigger async execution

2. **External high-priority (API/startup):** No semaphore, go to queue[0], but **don't trigger execution** - they wait for something else to call `execute()`

3. **Trigger high-priority:** No semaphore, go to queue[0], execution **continues immediately** in the same call stack (re-entrant)

4. **Consumption:** Always drains queue[0] completely before touching queue[1]
