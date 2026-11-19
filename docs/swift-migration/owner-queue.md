# Owner queue

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

Items that need the owner's attention. The orchestrator adds an entry here
instead of waiting, then continues with other work
([workflow.md §3](workflow.md)). It reads this file at the start of each
night.

How to use it:

- **The owner** answers an item by writing under "Answer" and moving the item
  to "Answered", or by deleting it if no record is needed.
- **The orchestrator** acts on answered items, records any resulting rule in
  `decisions.md`, and then removes them from this file.
- Each item says what is needed, why, what is blocked until it is answered,
  and what the orchestrator is doing in the meantime.
- Newest items go at the top of each group.

## For the owner, when back at the computer

Things only the owner can do, noted on 2026-11-20 at his request.

1. **Enable the commit hooks in each checkout** (done by the owner in
   `~/git/iterm2-alt` on 2026-11-20, which covers its linked worktrees;
   `~/git/iterm2-alt11` and `~/git/iterm2` remain): run `make install-hooks`
   (it runs `git config core.hooksPath tools/git-hooks`). It is not
   enabled in `~/git/iterm2-alt`; check `~/git/iterm2-alt11` and the
   others. The nil-lock check in `tools/git-hooks/pre-commit` protects
   only checkouts where this has been run. Linked worktrees inherit it
   from their main checkout; fresh clones do not.
2. **The nil-lock line for `CLAUDE.md`**: added as written, with the
   owner's permission (2026-11-20).
3. **The stored-state corpus commit**: the owner looked and the files
   are fine (2026-11-20). Kept here for the record: look at the stored-state corpus commit (“Add a sanitized stored-state corpus and the tools that make and check it”) before
   pushing: it adds data.
4. **Set up the nightly clone** if the nightly start is to be used:
   `tools/swift_migration/nightly_clone.sh setup`, then accept Claude
   Code's workspace trust dialog in the clone once by hand. Nothing is
   installed until the launchd plist is installed by hand.
5. **`WebExtensionsFramework/.claude/settings.local.json`**: no longer
   tracked (the owner said it was committed by mistake, 2026-11-20). The
   file is still on disk and is still in the history.
6. **The website's dynamic profiles page**: corrected in
   `~/iterm2-website` (the current page and the 3.7 copy), with the
   owner's permission; not committed there. It now says errors appear in
   an alert and in the Script Console.
7. **Twelve Swift `#if DEBUG` blocks were left dormant** (commit
   "Change Swift #if DEBUG to #if ITERM_DEBUG where it is safe to
   enable"; Swift's `DEBUG` is set in no configuration, so these have
   never compiled). Each needs your decision:
   - the browser's debug autofill code no longer compiles
     (`iTermBrowserManager.swift:2062`,
     `iTermBrowserViewController.swift:1077`,
     `iTermBrowserToolbar.swift:49, 370, 470`):
     `safelyEvaluateJavaScript` changed signature;
   - `TokenExecutor.pause()` and `discardTokensFromPTY()` have queue
     assertions that fire in four tests and from app code on the main
     queue (`terminalSetColorTableEntryAtIndex` to
     `addUnmanagedPausedSideEffect` to `mutateColorMap` to
     `addPausedNoDelegateSideEffect` to `pause()`): a real threading
     violation, or a wrong assertion?
   - the `Unpauser` deinit assertion (`TokenExecutor.swift`, three linked
     sites) would turn the logged "Unpause in deinit!" into a crash;
   - `CompanionPairingController.swift:781` writes the pairing URL (the
     static key and pairing nonce) to a world-readable file in `/tmp`. If
     you want the automation hook, it should write mode 0600 to a
     per-user directory;
   - `iTermBrowserUserState.swift:59` sets the browser logger to debug,
     which sends page message bodies to the system log.
   Also `SearchEngine.swift:602` says `#if DEUG` (a typo; dead either
   way), and `ThirdParty/PSMTabBarControl/source/PSMTahoeTabStyle.swift:2331`
   has one `#if DEBUG` (a commented-out print) left alone because the
   tab bar is frozen.
8. **Seven category methods collide with Apple's own methods of the same
   name** (found 2026-11-20 by comparing the app's categories with the
   methods the frameworks implement at run time on macOS 27.0). A
   category method with the same selector replaces or is replaced by the
   other for every instance in the process; which one wins depends on
   load order. Rename each with an `it_` prefix?
   - `-[NSString lastComposedCharacter]` (`NSStringITerm.m:1900`) against
     a category in the private CoreHandwriting framework, which AVKit,
     Quartz and QuickLookUI load. The two DIFFER: for a half-width
     katakana with a voiced mark Apple's returns both characters and
     iTerm2's splits off the mark. The app never calls its own.
   - `-[NSString firstCharacter]` (`NSStringITerm.m:2005`) against
     libmecabra.
   - `-[NSString stringByTrimmingLeadingWhitespace]` (`:1019`) and
     `-stringByTrimmingTrailingWhitespace` (`:1049`) against AnnotationKit.
   - `-[NSArray objectPassingTest:]` (`NSArray+iTerm.m:145`) and
     `-[NSMutableArray removeObjectsPassingTest:]` (`:761`) against
     private CoreFoundation methods, on every release back to macOS 13.
   - `-[NSImage CGImage]` (`NSImage+iTerm.m:738`) against PencilKit.
   Milder, colliding only with private subclasses: `+[NSObject
   object:isEqualToObject:]`, `-[NSObject performBlock:afterDelay:]`,
   `+[NSView animateWithDuration:animations:completion:]`, `-[NSView
   insertSubview:atIndex:]`, `-[NSView snapshot]` (the last against
   `NSRemoteView`, `SCNView` and `SKView`). Swift `@objc` extensions on
   framework classes were not scanned yet.
9. **`TaskIOMonitorCharacterizationTests.testStress` failed once** in a
   parallel full-suite run at a load average over 100, and passed when
   its class was rerun alone. Not disabled yet; if it fails again it
   will be disabled and logged in bugs.md per your rule for flaky tests.
10. **Review and push.** `git log origin/master..master` lists what is
   local.

## Needs a decision

### Q23. Questions from the evening of 2026-11-20

Recommendations are first in each item. Work continues without the answers
except where an item says it waits.

1. **Atomic properties.** ANSWERED 2026-11-21: port an atomic property as a
   Swift property stored in a `MutableAtomicObject`, whose accessors take a
   lock as the synthesized Objective-C ones did (decisions.md). The
   comparison is to list atomic becoming nonatomic as a check item, not a
   failure. Still open: `+load`, `+initialize` and a `-dealloc` whose port
   has no `deinit` fail the comparison until a rule exists
   ([phase0.md §9](phase0.md)).
2. **The stress harness.** `tools/perf/run_stress_test.sh` cannot run beside
   another iTerm2 (it drives the app by name). Recommended: accept
   `ModernTests/StressStreamReplayTests.swift` in its place for the integer
   discovery run of [translation-rules.md §1](translation-rules.md). The
   replay does not reach PTY reading and task code, the text view, Metal or
   windowed paths. Otherwise run the harness by hand against a sanitized
   build with every other iTerm2 quit
   ([integer-findings.md](integer-findings.md), Limits).
3. **The performance regression rule.** [performance.md §1](performance.md)
   says "beyond noise" without defining it. Proposed in
   `perf_compare.py`: a median worse by more than the larger of 5% and three
   times the measured spread; fewer than five samples or spread over 10% is
   inconclusive. And where the baseline file lives, if it is committed.
4. **The fast test tier** ([test-tiers.md](test-tiers.md)). The 10 second
   ceiling is reported, not enforced, because 46 fast tests exceeded it in
   single runs on a loaded machine while their medians are under a second:
   judge by median, or fix those tests first? Should the fast tier also drop
   `MallocScribble`, `MallocGuardEdges` and `NSZombieEnabled`? The slow tier
   is derived from address sanitizer medians and is larger than needed;
   `TokenExecutorPermitTests` loses 20 of its 23 tests to it.
5. **The browser debug autofill tool.** Its JavaScript function
   `window.debugAutofillFields` was deleted when `autofill-detector.js` was
   split, so the menu item would do nothing. Recommended: leave it dormant.
   Restoring it means bringing back about 100 lines of JavaScript and can
   only be checked by hand.
6. **DECRQCRA checksums.** The test for iTerm2's private codes in the
   checksum could never be true, so the right half of a wide character and
   tab fillers were summed. A fix that skips them changes the checksums of
   screens with wide characters or tabs (DECRQCRA is off by default). It is
   in review with the other terminal fixes; say if checksums must not change.
7. **Tab forward with `tabsWrapAround` on** is capped at 65535 like REP, which
   is still a stall of several seconds. Proposed: a lower cap in that mode,
   such as the screen's cell count.
8. **Terminal fixes that change what users see**, written and parked
   (`tmp/parked/integer-findings-fixes-4b.patch`, bugs.md): inline images
   too tall or too wide are shrunk in proportion instead of widened or
   clipped; DECCRA's destination honors origin mode. Approve, and the patch
   is repaired (its CHT change has a loop on double-width lines) and landed.
   Already landed, for your information: kitty `d=q` deletes take 1-based
   coordinates, as the protocol says.
9. **Kitty `t=f`** lets program output, including from a remote host, make
   iTerm2 read any regular file you can read into an image decoder, by the
   protocol's design; three of its denylist entries never match and its
   error replies reveal which paths exist (bugs.md). Recommended: fix the
   denylist. Restricting it further is your decision.
10. **The fake screen delegate in `PerformanceTests`** gets its protocol
   conformance at run time, because a release build has no testability and
   three delegate methods take internal Swift classes. The alternative is to
   make those three classes public.
11. **A flaky test is disabled:**
    `AsyncFilterDeliveryQueueTests.testDeliveriesQueuedDuringCatchUp` failed
    once in a full parallel run and passed alone on the same tree. It is
    skipped by the flaky test rule and recorded in bugs.md; someone should
    debug whether the test or `AsyncFilter` is at fault.
12. **Any test that creates a `PTYSession` aborts under the nullability
    sanitizer:** `-screenRestoreState:` receives nil during
    `-[PTYSession initSynthetic:]` (bugs.md). Gate step 4 cannot pass for
    such tests until this is triaged as a wrong annotation or a bug. May
    it be fixed as an exception to "log, do not fix", since it blocks
    ports?

### Q22. Questions raised on 2026-11-20 and answered the same day

- **Swift `#if DEBUG` is never active.** The Development build defines
  `DEBUG=1` for C and Objective-C and `ITERM_DEBUG` for Swift, but not
  Swift's own `DEBUG` condition, so the 42 `#if DEBUG` blocks in Swift
  under `sources/` are compiled in no configuration. Owner: change those
  blocks to `#if ITERM_DEBUG`, site by site.
- **Build lanes.** Owner: yes to a clone per code-changing agent and up to
  three builds at once (decisions.md).

- **The two slowest tests** (`FramerFlowTwoHopSimulationTests`, up to 213
  and 94 seconds, 91 percent of it inside the app's `FramerFlowController`):
  owner: put them in the slow tier; they may not be needed again.
  `FramerFlowController` is not changed.

Work queued from these answers, not yet started when this was written:
replace `XLog` with `RLog` (Q21); change Swift `#if DEBUG` to
`#if ITERM_DEBUG`; delete the seven unused reflective helpers (Q21 item 5);
a pool of lane clones built on `nightly_clone.sh`; type-aware lints on the
Swift AST (Q20 item 2); the ten restorable-state databases committed
gzipped (Q18 item 2); secure decoding of the status bar setup element's
`componentFactory` (follow-up to the class-check fix); `run_tests.expect`
failing on a run that executes no tests (Q18 item 4); the wrong-lock fix in
`iTermSlowOperationGateway` and `NS_UNAVAILABLE` on
`-[iTermHTTPConnection init]` (Q18 item 6); whole-module compilation for
the Beta and Nightly configurations (Q17); the inventory counting the
remaining arithmetic-helper calls (Q17); a Swift `BETA` compilation
condition and the helpers using it (Q17); the helpers changed to do what C
does in release, with README.md and translation-rules.md section 1
rewritten to match, and beta assertions made to fail tests (Q17); the
stage-two marker, its check against the code database, and the lints
honoring it (Q17).

### Q21. Questions from the reflective registry, the macro lint and the cross-check

Owner, 2026-11-20, while reviewing the implicitly-unwrapped lint: "I don't
think global top-level variable should ever be used in Swift". Recorded as
a rule to add to decisions.md and translation-rules.md with the lint that
enforces it: migration Swift declares no file-scope `var`. A static or
global variable from Objective-C becomes a static property of a type. The
orchestrator read this as covering mutable variables, and the owner
confirmed on 2026-11-20 that a file-scope `let` constant is fine. Queued: the lint, the two
document edits, and the decisions.md row.

Owner's answers so far (2026-11-20):

- **Item 1: `macro-classification.tsv` is the home of macro readings**,
  and anything unexpected or surprising about a macro that porting will
  need is also written as a comment in the code at its definition.
  Whether unread rows fail the gate was not answered separately; the
  orchestrator's reading is that they do once the reading pass is done.
- **Item 2: nothing to do.** The two old class names are not looked up
  by anything today; the item was background, not a decision.
- **Item 3: fix both class lookups with a type check** (the status bar
  component archive and the interval-tree class name): the class must
  conform to the protocol its objects implement. No allowlist. Ordinary
  `fix` commits with a test each, before either class is ported. The four
  key-binding selector sites are left as they are.
- **Item 4: leave the four module-qualified Swift class names as they
  are.** The binding tests pin them. Pinning them with `@objc(Name)` and
  a compatibility read of the old names is a prerequisite for any change
  to the module's name or to which module those classes are in.
- **Item 5: dead code may be deleted** ("feel free to delete dead code"),
  under the conditions recorded in decisions.md for 2026-11-20.
- **The `XLog` mismatch** (found by the macro reading pass; the
  Objective-C macro always logs, the Swift function does not): replace
  `XLog` with `RLog` everywhere and remove `XLog`.
  A straight swap: the call sites are not classified for private data
  and `RLogRedact` is not added (owner, 2026-11-20). Note for whoever
  does it: `RLog` prints to stderr only in `ITERM_DEBUG` builds and never
  calls `NSLog`, so these messages leave the system log in release builds.
- **Item 7: answered.** The project-file rewrites were Xcode (see Q19).

Asked 2026-11-20. None blocks other work.

1. **Where macro readings live.** [hidden-callers.md](hidden-callers.md)
   section 2 says macros that hide callers are entered in the
   reflective-site registry. The macro lint (`codedb.py macrolint`) checks
   a separate file, `macro-classification.tsv`: 69 rows, all UNREVIEWED.
   Keep the readings there, or in the registry? And should UNREVIEWED rows
   fail the gate (the lint's default) once the reading pass is done?
2. **Old stored class names that no longer load.** `InteractiveScriptTrigger`
   was renamed to `CoprocessTrigger` and `iTermURLMark` was deleted, with
   no compatibility class, so triggers and marks saved under those names by
   old versions are dropped. Add compatibility, or accept?
3. **Six reflective sites take a name from outside the app with no
   allowlist** ([reflective-sites.md](reflective-sites.md), security
   section): status bar drag data unarchived without secure coding;
   interval-tree class names from saved data checked only for
   `initWithDictionary:`; four key-binding selector sites. Fix any?
4. **Four Swift classes are stored under module-qualified names**
   (`iTerm2SharedARC.PortholeMark` and three browser triggers) because
   they lack `@objc(Name)`. The binding tests now pin those names. Renaming
   the module or moving the classes would break old saved data. Pin them
   with `@objc` names plus a compatibility read of the old names, or leave?
5. **Seven generic reflective helpers have no callers** (two swizzling
   helpers among them; listed in the registry). Delete in separate
   commits?
6. **The census treats every method whose selector the SDK declares as
   possibly system-called**, never as "no caller found". That over-flags
   private methods that share a name with an SDK method. Acceptable?
7. **`project.pbxproj` was rewritten once during the night** by an agent
   running `tools/add_file_to_xcodeproj.rb` on a synchronized-folder file;
   the rewrite dropped settings and a test run hung. Restored. The agent
   definitions now forbid it for `ModernTests`, but the script itself
   should refuse or be fixed (see also Q18 item 5).

### Q20. Rule questions found while correcting the documents

Owner's answers so far (2026-11-20):

- **Item 2: both.** The token lints stay as the fast check on a staged
  change. Type-aware lints are added on the Swift AST dump the code
  database already reads, for the rules that need types, run at the close
  of a unit.
- **Item 1: implicitly unwrapped types outside properties are allowed
  with a marker comment and a reason**, to be removed once no longer
  needed. The lint requires the marker; unmarked ones are reported.
- **Item 5: `assertionFailure` and `preconditionFailure` are banned in
  migration Swift**, like `fatalError`, `assert` and `precondition`.
- **Item 6: the unsafe marker on `&x` passed as a pointer is enforced by
  the type-aware lints** (the AST knows whether `&x` becomes a pointer or
  an `inout`). Until that lint exists it is a review item.
- **Item 3: the commit-history rule for which files are migration Swift
  stays provisional** until the pilot; the document keeps "to be decided
  in the pilot" and describes what the tool does today.
- **Item 4:** settled by the work: the interface snapshot is built on the
  compiler's own emitters (`swift_interface.py`), not on
  `swift-synthesize-interface`.

Asked 2026-11-20. The documents were corrected where they were factually
wrong (commit "Correct the Swift migration documents to match the tools as
they are"). These seven would change a rule, so they were left alone.

1. **Implicitly unwrapped types outside properties.** The lint allows `T!`
   in parameter and return types, locals and `init!`; only properties and
   outlets are covered by a written rule. Report them, or allow them?
2. **The Swift lints are a hand-written token lexer**, while the decision
   of 2026-11-19 says tools that must understand source start from
   compiler output. What the lints cannot check (integer initializers,
   arithmetic, use of implicitly unwrapped values, bridging casts, optional
   lock arguments) is exactly the part that needs types. Record an
   exception for token-level lints, or queue rebuilding the type-dependent
   lints on the Swift AST dump the code database already reads?
3. **How migration files are identified.** phase0.md section 6 still says
   "to be decided in the pilot"; the lint uses the trailer history. Confirm
   that as the rule, or leave it for the pilot?
4. **The interface snapshot** (phase0.md section 5) names
   `swift-synthesize-interface`, which the no-Xcode-tooling decision rules
   out. The snapshot is being built on the compiler's own emitters
   instead. Confirm.
5. **`assertionFailure` and `preconditionFailure` pass the lint**, because
   the documents name only `fatalError`, `assert` and `precondition`. Ban
   them too?
6. **A call that passes `&x` to a pointer parameter must carry an unsafe
   marker** (translation-rules.md section 8), but no token-level tool can
   tell it from `inout`. Make it a review item, or drop it for calls that
   name no unsafe API?
7. **New Objective-C `@synchronized` on an ivar or call result:** should
   `ITNonnilLock` be required there, with a lint?

### Q19. The nightly start: approve, change or replace before installing

Owner, 2026-11-20, after the second review of the clone scripts: "you could
spend eternity trying to lock this down. Don't be too paranoid about the
agent trying to escape." The guards are against accidents. Routes that need
a session acting against its instructions are listed in the script
headers, are non-blocking in review, and get no further hardening rounds.

Asked 2026-11-20. Nothing is installed. `tools/swift_migration/nightly_start.sh`
and the launchd plist template are committed; the checklist item stays open.

What the unattended session gets: Opus, auto permission mode with prompts
denied, user settings only (this checkout's `.claude/settings.local.json`
allow rules such as `Bash(git *)` would otherwise let it push with no
classifier call: a reviewer demonstrated that against a throwaway
repository), every shell command sent to the classifier, deny rules for
push, `gh`, `osascript`, `launchctl`, `sudo`, `open`, `ssh`, `it2`, no MCP
servers or claude.ai connectors (Gmail was loaded before), and an
environment in which every push fails in git itself. A hard time limit
kills everything the run started.

What a misbehaving session could still do, stated plainly:

- Undo the environment guards (`unset`, `GIT_CONFIG_COUNT=0`). They stop
  accidents, not intent. Only the classifier and the deny rules remain.
- Send data out with `curl` or Python; only the classifier stops that.
- Act as you in your GUI session: call `osascript` or `it2` through an
  interpreter, or start processes through launchd or XPC that the final
  sweep cannot find.
- Damage local state: rewrite or reset local history, delete untracked
  files, switch branches, edit `CLAUDE.md`. The before and after log only
  makes it visible.
- Have a request approved by your user-level `PermissionRequest` hooks if
  they relay prompts to iTerm2 Buddy.

Owner's answers so far (2026-11-20):

- **Item 1: a separate clone.** The nightly session runs in its own clone
  whose remote cannot be written, not in the owner's working checkout.
- **Not headless.** The session runs as an ordinary Claude Code session
  inside tmux, on a custom socket path, so the owner can attach and watch.

- **Item 2: hooks stay enabled** in the nightly session.
- **The project file rewrites** (Q18 item 5, Q21 item 7) were Xcode itself,
  left open on this project, not an agent's script. Xcode was quit on
  2026-11-20 with the owner's permission; it need not be running.
- **Item 4: network access stays as it is** (no extra deny rules for
  `curl`, `wget` or web search).
- **Item 5: the times stand** (latest start 04:59, clean stop 06:15, hard
  limit 07:00 or six hours). The Mac never sleeps, so no wake schedule.
- **Separate macOS user: no.** After a review showed that a session
  under the owner's account can still reach his checkout by other routes,
  the orchestrator raised a separate user account again. The owner
  declined: multiple user accounts on macOS do not work well in his
  experience. The session stays in a clone under his account, with the
  guards and the tamper detection the review led to.
- **Item 6: track `.claude/agents/`.** The ignore rule becomes
  `.claude/*` with an exception for `.claude/agents/`, and the two agent
  definitions move there.

Decisions needed:

1. (Answered above.) Is this acceptable, or do you want a hard guarantee? The two that do
   not depend on the model: run the nightly session as a separate macOS
   user with no push credentials and no GUI session, or in a separate
   clone whose remote cannot be written.
2. May your user-level hooks run in the nightly session? If not, the
   session settings can disable all hooks.
3. Restricting the session to user settings also stops the project's
   `CLAUDE.md` loading automatically. The prompt and the agent
   definitions tell every agent to read it first. Enough, or should its
   text be appended to the system prompt?
4. Deny `curl`, `wget` and web search at night?
5. Numbers: start no later than 05:00, stop cleanly by 06:15, hard limit
   07:00 or six hours. And should the Mac be scheduled to wake at
   midnight (`pmset`, needs sudo)?
6. `.gitignore` ignores `.claude/`, so the agent definitions live in
   `.claude/agents/` and are passed on the command line.
   Track `.claude/agents/` instead, so interactive sessions get them?
7. The fixes made after the review were not reviewed again. Say if you
   want another review round before you read it yourself.
8. The same local allow rules apply to interactive orchestrator sessions
   such as the one that ran tonight. No agent pushed (every brief forbids
   it and the orchestrator commits by hand), but that protection was
   instructions, not mechanism. `git log origin/master..master` shows what
   is local.

### Q18. Questions from the stored-state corpus and the sanitizer runs

Owner's answers so far (2026-11-20):

- **Item 1: the corpus stays at `tests/stored-state-corpus/`.**
- **Item 2: commit all ten restorable-state databases, gzipped.** Tests
  decompress to a temporary directory.
- **Item 4: make `tools/run_tests.expect` fail when a run executes no
  tests** (a skipped test counts as executed).
- **Item 6:** fix the wrong-lock race in `iTermSlowOperationGateway`
  (with a test); mark `-[iTermHTTPConnection init]` unavailable; leave the
  two `pidinfo` lock sites without an assertion.
- **Item 5:** the project-file rewrites were Xcode, not the script (Q19).

Asked 2026-11-20. None of these blocks other work.

1. **Where the corpus lives.** [stored-state.md](stored-state.md) says
   `ModernTests/Resources`; it was committed at `tests/stored-state-corpus/`
   (4.7 MB, 81 files). Move it, or correct the document?
2. **How much restorable state to commit.** Four of the ten
   restorable-state databases are committed (3.4.0, 3.4.0 after a restore,
   3.7.8, and 3.4.0 upgraded to 3.7.8). The others are sanitized and proven
   but left out for size; some exceed 1 MB. Commit all ten gzipped (about
   1.4 MB in total)? The round-trip tests for session and arrangement
   restoration will want the 3.7.8 complex layout most.
3. **Please look at the corpus before pushing.** It is the only commit that
   adds data. A fresh reviewer extracted and read every string at every
   level and found only placeholders and made-up content, but a leak in a
   public repository cannot be undone.
4. **`tools/run_tests.expect` passes on a test name that does not exist**
   (it runs 0 tests and reports success). The sanitizer scripts now fail in
   that case. Should the normal runner fail too? Not changed.
5. **`tools/add_file_to_xcodeproj.rb` rewrites the project file** (about
   160 lines added and 270 removed, all reordering) when given a file in a
   synchronized folder, after printing that no change is needed. Authors
   revert it each time. Not changed.
6. **Three small items from the nil-lock audit:** assert at the two
   `pidinfo` ivar sites (that target has no beta assertion); mark
   `-[iTermHTTPConnection init]` unavailable; fix the wrong-lock race in
   `iTermSlowOperationGateway` (logged in [bugs.md](bugs.md)).

### Q17. Questions from the helper library and the Swift lints

Owner's answers so far (2026-11-20):

- **Whole-module compilation for Beta and Nightly: yes.**
- **The helper calls must be removed eventually**: they make the code
  hard to read. Recorded as a rule in decisions.md: scaffolding, removed
  in stage two, counted by the inventory.
- **Build type in Swift: add a `BETA` compilation condition** to the
  Development, Beta and Nightly configurations, with a test that it agrees
  with the C macro.
- **What the helpers do at the edges, and in general:** in release, what
  C does in practice (wrap, truncate, hardware shift masking, the
  processor's float conversion per architecture); in Development, Beta,
  Nightly and tests, assert aggressively. This replaces "clamps in
  release" for all helpers.
- **Stage two:** decided by the code database (no Objective-C refers to
  any type the file defines), recorded by a marker
  `// SWIFT-MIGRATION-STAGE: 2` that the gate verifies.
- The last item (ported code is held to a stricter standard than existing
  Swift) was information, not a question.
- **Added:** 2026-11-19.
- **Beta and Nightly builds compile Swift file by file.** Only the
  Deployment configuration sets whole-module compilation. In Beta and
  Nightly a helper defined in one file cannot be inlined into another, so
  `it_add` on `Int` becomes a call to an unspecialized generic function
  through witness tables, where Deployment gets one add and a branch. It is
  not a correctness problem, but ported hot code would run much slower in
  nightly builds than in release, and nightly timing would not predict
  release timing. Switch Beta and Nightly to whole-module compilation, or
  accept it?
- **How Swift learns the build type.** Swift cannot see the `BETA` macro.
  The helper library reads a constant, `iTermBetaAssertionsCrash`, defined
  in `DebugLogging.m` under `#if BETA`. The alternative is a Swift
  compilation condition in the Development, Beta and Nightly
  configurations, which would let `it_conservativeBetaAssert` compile to
  nothing in release, as [assertions.md](assertions.md) asks; today it is a
  load and a branch. Keep the constant, or add the build setting?
- **`it_shiftLeft`.** It reports a shift that loses set bits for unsigned
  types too, where C defines the result (code that relies on that uses
  `&<<`), and a negative count is reported and then shifts right, where C
  leaves it undefined. Confirm both, or say what they should do.
- **Float to integer.** Out-of-range values clamp, NaN gives 0, rounding
  is toward zero, and each is a beta assertion. The documents said only
  "defined result". Confirm.
- **Stage two and Swift concurrency.** The lints ban `async`, `await`,
  `Task` and `@MainActor` in migration Swift, as stage one requires.
  Nothing tells the lints that a file has reached stage two, where those
  become legitimate. How should a file be marked as stage two: a marker
  comment, a commit kind, or a list?
- **Ported code is held to a stricter standard than existing Swift.** A
  survey of the 981 Swift files in scope found 920 force unwraps, 158
  `as!`, 67 `try!`, 79 `fatalError` or `assert`, 384 unsafe pointer uses
  without a marker and 2,691 uses of Swift concurrency. This is as
  designed; it is recorded here so the gap is known.
- **Meanwhile:** the constant is used, the helpers behave as described, and
  every migration file is treated as stage one.
- **Answer:**

### Q16. Side effects on vm1 from collecting the stored-state corpus
- **Added:** 2026-11-19.
- **What happened:** an agent ran iTerm2 3.4.0, 3.5.0, 3.6.0 and 3.7.8 on
  vm1 to collect stored state. Old releases have no `-suite`, so they used
  the VM's real iTerm2 preferences. The agent moved the VM's existing
  iTerm2 state aside and restored it afterwards, removed everything it
  downloaded, and left vm1 running. Four things could not be fully undone:
  - `~/.zsh_history` on vm1: the agent's shells appended to it before it
    was backed up. zsh's 1,000-line limit dropped some of the oldest
    entries, and a few fake commands remain at the end.
  - `~/.config/iterm2` on vm1: a glob error deleted it before it was moved
    aside. The agent recreated its contents (three symlinks and an empty
    sockets directory) with new timestamps.
  - macOS asked repeatedly whether iTerm may control the Mac, and the agent
    pressed Deny. If macOS records that per bundle identifier, it applies
    to your own iTerm builds on vm1. Worth a look in System Settings.
  - The VM's clipboard held text that was not the agent's. It was replaced
    and then cleared.
- **Needed:** nothing, unless any of these matters to you. Say so if vm1
  should be restored from a snapshot.
- **The corpus** is at `tmp/stored-state-corpus/` (about 40 MB, not
  committed), with a README and a manifest per set. It contains the VM's
  account name, home path and host name, and nothing else real. Before any
  of it is committed it must be sanitized, and
  `tools/sanitize_iterm2_plist.py` does not yet cover the SQLite stores,
  the paste history archive, snippets, profile JSON or the export archive,
  and it fails on plists containing a control character (the hot key's
  character). Extending it is a later item.
- **For next time:** `tools/vm/qa.sh` and `docs/vm-qa.md` assume builds
  launched with `-suite qa`. They have no way to launch a release build,
  no general cleanup, and no way to copy files back, and `launch` turns
  window restoration off. If you want, the migration can extend them
  through the usual loop.
- **Answer:** (2026-11-20) "you can do whatever you want with the virtual
  machine. I don't care." Nothing to restore. The VM tooling
  (`tools/vm/qa.sh`, `docs/vm-qa.md`) may be extended to launch release
  builds, clean up and copy files back; queued with the next corpus
  collection run.

### Q15. Small questions from widening the inventory's scope
- **Added:** 2026-11-19, from the review of the inventory's scope change.
- **Stale files, delete?**
  - `SignedArchive/SignedArchive/resign/main.c` is compiled by no target of
    any project; `resign/main.m` replaced it.
  - The top-level `SearchableComboListView/SearchableComboListView.h` and
    six top-level `.swift` files there duplicate the copies in
    `SearchableComboListView/SearchableComboView/` and are in no project.
- **Files that only other targets compile.** The leaf ordering defers every
  file that a target other than the app's two main static targets compiles
  (frameworks, libraries, helper programs), so none of the 52 newly
  in-scope implementation files is offered. For the 16 `SIG*.m` files the
  other target is a static library that only the standalone sign, verify,
  extract and resign tools link. Should such a target defer a file at all,
  and is there a rule for porting code that lives in a framework or a
  helper (`ColorPicker`, `pidinfo`, the sandboxed worker)?
- **The Companion app.** `Companion/CompanionCore/Sources/CNoise/shim/cnoise_stubs.c`
  and `Companion/PushService/PushService-Bridging-Header.h` are the owner's
  C, compiled into the iOS Companion app. README section 2 says "the app or
  its helper programs", which the tools read as the Mac app. Is the
  Companion's small amount of C in scope?
- **Meanwhile:** the stale files are counted and deferred, never offered;
  the new directories' files stay deferred; the Companion's C is outside
  the scope.
- **Answer:** (2026-11-20)
  - Stale files: delete them.
  - Code in frameworks and helper programs: decide per target when the
    migration gets there. They stay deferred until then.
  - The Companion app's C: out of scope.

### Q12. Moving PSMTabBarControl under `sources/`: waiting for the owner
- **Added:** 2026-11-19.
- **Decided:** the owner agreed that `ThirdParty/PSMTabBarControl` may move
  to `sources/PSMTabBarControl`, since it is no longer third-party code in
  practice. That would reduce the scope rule to "everything under
  `sources/`, nothing under `ThirdParty/`".
- **Blocked:** a very large change to the tab bar is in progress in another
  checkout, and a directory move would conflict with it. Do not move it
  until the owner says it is safe.
- **When it is safe:** move it in a commit of its own, keeping the LICENSE
  file with the code; build and run the full suite; then, in a second
  commit, simplify the scope rule in `inventory.py`, `entry_points.py`,
  `codedb.py`, their tests and the process files, with a `decisions.md`
  entry; then recapture the compile commands and extract again.
- **Meanwhile:** the tools keep the exception for
  `ThirdParty/PSMTabBarControl`. Units in PSMTabBarControl are not started
  until the other change has landed, since ports there would conflict too.
- **Answer (2026-11-20):** not done yet. The work is in the checkout
  `~/git/iterm2-alt11` (on that date: `master`, one commit ahead of
  `origin/master`, "Add rich tab content", with 37 uncommitted changes).
  The signal that it is safe is that checkout pushing: its commits appear
  on `origin/master` and it has nothing left ahead or uncommitted in
  `ThirdParty/PSMTabBarControl`. The orchestrator checks by reading that
  checkout's state (never writing to it) and asks the owner to confirm
  before moving anything.

## Parked units

Units set aside after four review rounds without converging, or waiting on
something above. Each entry names the unit, the step it reached, the
outstanding findings with the author's position on each, and where the saved
patch is.

## Rule changes proposed

A rule in the process files that an agent believes is wrong or missing, with
the evidence. Nothing changes until the owner agrees.

## Hot paths

Requests to start work on a deferred hot path, each with its plan and
benchmarks ([performance.md §2](performance.md)).

None.

## Tier transitions

A request to begin the next tier ([plan.md §1](plan.md)), with what was done
in the current one and what crash reports have been attributed to its
ports.

None.

## Answered

### Q14. vm1 does not accept this Mac's ssh key
- **Added:** 2026-11-19.
- **What:** `tools/vm/qa.sh --host vm1 sh true` fails with
  `gnachman@192.168.64.3: Permission denied (publickey,password,keyboard-interactive)`.
  The VM answers and its host key matches `known_hosts`, but it rejects
  `~/.ssh/id_rsa` for the user `gnachman`, and the ssh agent holds no
  identities. In `~/.ssh/config`, `Host vm1` has no `User` line; `Host vm4`
  has the same address with `User qa` and `ProxyJump vmhost`. The agent did
  not try another user, alias or password.
- **Needed:** either add this Mac's public key to the account on vm1 that
  `qa.sh` should use, or correct the `vm1` entry in `~/.ssh/config`, so that
  `tools/vm/qa.sh --host vm1 sh true` works.
- **Blocks:** the stored-state corpus from older releases, and any hands-on
  QA on vm1.
- **Also found, for when it works:** `docs/vm-qa.md` and `tools/vm/qa.sh`
  assume a build made by `qa.sh build` and launched with `-suite qa`. For
  old release builds they have no way to launch a downloaded app, their
  process lookup and `clean` only know the `qa` suites, `launch` turns
  window restoration off, and there is no general way to copy files back.
  The corpus work needs a small extension of that tooling.
- **Answer:** 2026-11-19: the ssh configuration was wrong and is fixed.
  `tools/vm/qa.sh --host vm1 sh` works (macOS 27.0.1, arm64).

### R1. Additions to `phase0.md` section 9 and `lifecycle.md` section 2
- **Added:** 2026-11-18, from the runtime snapshot's author and its first
  reviewer.
- **Proposed:**
  - Say that a property can legitimately appear more than once in a class's
    property list (the `NSObject` protocol's properties repeat once per
    category that adopts a protocol derived from it), so repeated properties
    are duplicates only when their attributes differ. Method duplicates
    always are.
  - Say that direct members never appear in a snapshot.
  - Say that the before and after snapshots must come from the same
    architecture and build configuration.
  - Add ivars (name and type encoding) to what the snapshot records, because
    key-value coding and xib outlets can reach ivars that have no property.
    The tool is being extended to do this.
  - In `lifecycle.md` section 2, name a second source of duplicate
    selectors: a property declared in the class interface whose accessor is
    written only in a category, which makes the compiler synthesize a second
    one. `PTYTask` has this today (see Q8).
  - Describe what the snapshot now records beyond the original list: the
    language each class is defined in, the image of the class and of any
    method implemented elsewhere (including methods a system framework adds
    at run time), a header with architecture, build configuration and
    sanitizer variant, and property ownership labels that say `unrecorded`
    when the property's own attributes do not state it. Also the exception
    for `+load` in duplicate detection. Ivar ownership is not recorded yet;
    it was split into its own Phase 0 item.
  - Say that the snapshot lists ivars sorted by name, so a change in
    declaration order is not reported, although that order decides teardown
    order under ARC ([arc.md](arc.md)). The dealloc audit has to cover it.
  - Say that a snapshot records the process as it is when taken, including
    methods and classes that system frameworks add at run time, which is why
    the script runs it as the only test; and document the comparison's
    report format and exit codes (0 match, 1 difference or no verdict,
    2 error).
- **Meanwhile:** the tool does these things or is being changed to, except
  ivar ownership as noted; only the documents lag.
- **Answer:** 2026-11-19: yes. Errors in the documents can always be fixed
  without asking.

### R2. Corrections to `baseline.md`
- **Added:** 2026-11-18, from the inventory script's author. Not yet
  confirmed by review.
- **Proposed:** three figures were measured in ways that undercount or
  overcount, and the file should say how each is measured:
  - Retain and release sites in `PTYSession.m`: 489, not about 303. The
    earlier search missed nested sends such as
    `[[[Foo alloc] init] autorelease]`.
  - Files in the non-ARC target: 180 in scope, not 210. The 210 was every
    `.m` in the target, including other third-party and generated files.
  - Headers with two or fewer importers: 424 counting the bridging header as
    an importer, 455 not counting it. The earlier 448 did not count it.
- **Meanwhile:** agents use the script's figures, not the file's.
- **Answer:** 2026-11-19: yes. Errors in the documents can always be fixed
  without asking.

### R3. Corrections to `objcxx.md`
- **Added:** 2026-11-18, from the inventory script's author. Not yet
  confirmed by review.
- **Proposed:** the table says `iTermBackgroundColorRenderer.mm` uses no
  C++. It uses `iTerm2::PIUArray` and `static_cast`. Correct the row, and
  drop it as the example of a file that can simply be renamed to `.m`.
- **Meanwhile:** the inventory script classifies each `.mm` file itself and
  does not rely on the table.
- **Answer:** 2026-11-19: yes. Errors in the documents can always be fixed
  without asking.

### Q10. xcodebuild hangs on this machine (blocks everything that builds)
- **Added:** 2026-11-19, about 02:30.
- **What:** every `xcodebuild` command, even `xcodebuild -list`, hangs
  before printing anything. A sample shows it waiting in
  `DVTCoreDeviceLocator.startLocating()` on the CoreDevice service.
  `CoreDeviceService` (pid 5708 when checked, running for 35 days) appears
  to be stuck. It began mid-run: a full parallel suite passed 3,450 tests,
  then all ten test hosts went silent at once.
- **Likely remedy:** `killall CoreDeviceService` (launchd restarts it on
  demand), or a reboot. The orchestrator did not do this itself, because it
  is a service outside the repository that other sessions and a connected
  device may be using.
- **Blocks:** builds, the Xcode test suite, and the runtime snapshot tool,
  in every checkout on this machine. Python-only work is unaffected.
- **Resolved without an answer:** the machine rebooted on 2026-11-19 and
  `xcodebuild` has worked since. The question that remains is whether the
  orchestrator may run `killall CoreDeviceService` itself if this recurs.
- **Answer:** 2026-11-19: yes, the orchestrator may run
  `killall CoreDeviceService` if the hang recurs.

### Q4. Warnings as errors in every configuration
- **Added:** 2026-11-18
- **Needed:** treating warnings as errors is a build setting in only some
  configurations today. Decide whether to turn it on everywhere once the
  project-wide warning group is clean ([warnings.md](warnings.md)).
- **Blocks:** nothing yet. The gate treats warnings as errors regardless.
- **Answer:** 2026-11-19: yes, in every configuration, once the warning group is
  clean.

### Q9. Two existing tests failed once under the parallel suite
- **Added:** 2026-11-18, seen by the runtime snapshot's author.
- **What:** in one `tools/run_tests.expect -parallel` run,
  `AsyncFilterTemporaryLineTests.testOnCompleteCallback` and
  `PTYSessionEndedMessageTests.testShortOutputMovesToTheBottomOfTheScreen`
  failed. Both passed when run alone, and a second full parallel run
  passed. Neither is related to the migration work. That they are flaky
  under load is a guess; nobody has found the cause.
- **Needed:** whether you want these investigated now. The process forbids
  retrying a test until it passes and forbids disabling one.
- **Blocks:** nothing, but a gate run that hits one of them will fail and
  have to be looked at each time.
- **Meanwhile:** when a gate run fails only on one of these two, the
  orchestrator reruns that test alone, records the occurrence here, and
  does not treat a pass on the rerun as proof for anything else.
- **Occurrences:** 3 on 2026-11-18. In a second full run,
  `PTYSessionEndedMessageTests.testShortOutputMovesToTheBottomOfTheScreen`
  failed again together with
  `AsyncFilterStateMachineTests.testStateTransitionsWithPendingDeliveries`;
  all passed alone. In a third, with the machine heavily loaded by other
  builds, the stall detector killed the run inside
  `StatusPriorityPopoverLayoutTests`, which passed alone in 192 seconds.
- **Answer:** 2026-11-19: disable flaky tests and tell the owner, who will
  have another agent debug each flake. This replaces the rule that no test
  is disabled without the owner. To do: disable the three tests that have
  failed, list every disabled test in `bugs.md` with how it failed, and
  update [test-speed.md §3](test-speed.md) and
  [orchestration.md §10](orchestration.md).

### Q2. Time budget for the fast test tier
- **Added:** 2026-11-18
- **Needed:** the wall-clock limit for the tests the gate runs on every
  commit, including the build ([test-speed.md §3](test-speed.md)).
- **Blocks:** nothing until the fast tier exists.
- **Proposed:** set it after the Phase 0 measurement, at about the measured
  time plus a quarter.
- **Answer:** 2026-11-19: fine as proposed.

### Q1. Ceiling for a single test
- **Added:** 2026-11-18
- **Needed:** confirm or change the proposed limit of 10 seconds for any one
  test in any tier, above which the gate fails
  ([test-speed.md §2](test-speed.md)).
- **Blocks:** nothing. The slowest tests are being fixed regardless.
- **Answer:** 2026-11-19: 10 seconds is fine as the ceiling. Most tests
  should take under 1 second; treat that as the target for new tests and
  for the ones being fixed.

### Q3. How long a port soaks, and how often crash reports are checked
- **Added:** 2026-11-18
- **Needed:** the number of nightly builds a port must be in before its
  dependents are ported, per tier, and how often the orchestrator checks
  crash reports and beta assertion failures
  ([lifecycle.md §1](lifecycle.md), step 7).
- **Blocks:** porting anything that depends on a recent port.
- **Meanwhile:** units with no recently ported dependencies.
- **Proposed:** one nightly for the leaf tier; check reports at the start of
  every night.
- **Answer:** 2026-11-19: do not wait for nightly builds. Bug reports from
  nightly users are rare, so a soak tells little. Dependents may be ported
  without waiting. To do: remove the wait from
  [lifecycle.md §1](lifecycle.md) step 7 and [workflow.md §5](workflow.md),
  keeping the check of crash reports as something done when reports arrive.

### Q6. A VM for unattended QA
- **Added:** 2026-11-18
- **Needed:** `CLAUDE.md` says to ask which VM to use for hands-on QA. Name
  a VM that may be used without asking each time, or say that VM QA always
  waits for the morning.
- **Blocks:** closing any unit whose runtime check is VM QA (units with
  First Responder actions or many xib connections).
- **Meanwhile:** such units are taken up to that step and parked.
- **Answer:** 2026-11-19: vm1 is permanently assigned to the migration.
  Agents may use it without asking. It is not running; the owner starts it
  when asked, so ask when work that needs it is ready.

### Q7. Stored state from old releases
- **Added:** 2026-11-18
- **Needed:** real arrangements, restorable window state, keyed archives,
  profile JSON, and user defaults from several released versions, to build
  the persistence corpus ([stored-state.md](stored-state.md)). Agents cannot
  source these.
- **Blocks:** the end of Phase 0, and any unit that encodes or decodes
  stored state.
- **Meanwhile:** the rest of Phase 0.
- **Answer:** 2026-11-19: agents can produce the corpus themselves.
  - For the current version: run the app with `-suite` and drive it with
    AppleScript or the Python API to generate the data. On the owner's Mac
    do not use accessibility APIs (`CLAUDE.md`).
  - For older versions: `-suite` is a recent addition, so old releases
    cannot be isolated that way. Use the VMs and the QA process in
    `docs/vm-qa.md`. Downloading old release builds on the VMs is fine.

### R4. "Identical snapshots" cannot hold when a class changes language
- **Added:** 2026-11-18, from the second review of the runtime snapshot.
- **The problem:** [phase0.md §9](phase0.md) and
  [hidden-callers.md §1](hidden-callers.md) require the runtime snapshot to
  be identical before and after a port, apart from a short fixed list. That
  works while a class stays in Objective-C. When a whole class moves to
  Swift it cannot: the compiler orders property attributes differently,
  names backing ivars without the underscore, encodes some ivar types as
  unknown, and adds `-init`. A reviewer's test showed 13 differences for a
  semantically identical four-property class.
- **Proposed:** for a class that changes language, the rule becomes
  "identical in meaning": methods, type encodings, protocols, superclass and
  decoded property attributes must match exactly, and the systematic
  differences are classified by the tool and listed for the reviewer instead
  of failing. Anything the runtime cannot verify (weak versus unowned) is
  listed as needing a check against the source.
- **Meanwhile:** the tool refuses to give a verdict for a class that changed
  language. A new Phase 0 item builds the classified comparison. Incremental
  ports, where the class stays in Objective-C, are unaffected.
- **Also to state in the documents:** the tool can only snapshot the build
  configuration that the test scheme builds, so code that exists only in
  beta or release builds is not seen.
- **Answer:** 2026-11-19: agreed as proposed.

### R5. `unsafe_unretained` and `assign` object references have no allowed Swift form
- **Added:** 2026-11-18, from the second review of the runtime snapshot.
- **The gap:** [lifetimes.md](lifetimes.md) says an `assign` or
  `__unsafe_unretained` back-pointer becomes `weak` only as a deliberate,
  separate change. The lints ban `unowned` and `unowned(unsafe)`. So when a
  class with such a reference moves to Swift, the only faithful translation
  (`unowned(unsafe)`) is banned and the only allowed one (`weak`) changes
  behavior. There are about 35 `assign` object properties and 18
  `__unsafe_unretained` uses.
- **Proposed:** require the reference to be changed to `weak` in Objective-C,
  in its own `fix` commit with a lifetime test, before the class's state
  moves to Swift. `unowned` stays banned.
- **Related:** the runtime cannot tell Swift `weak` from `unowned` or
  `unowned(unsafe)`; all three look the same. The snapshot will say so
  instead of printing "weak", and the ban on `unowned` in migration files is
  what actually prevents the mistake.
- **Blocks:** nothing until a class with such a reference reaches its flip.
- **Answer:** 2026-11-19: agreed. Change each such reference to `weak` in
  Objective-C first, in its own commit with a test. The owner does not
  expect this to introduce bugs; the test is there for the one known
  difference, a reference read while its target is being deallocated.

### P1. `phase0-inventory-state` (the ivar and static table), parked at the cap
- **Added:** 2026-11-19.
- **Step reached:** fourth review, with blocking findings. Rounds one to
  three found 4, 6 and 4 blocking findings; each was fixed with a failing
  test first. The fourth found the four below. All are wrong answers on real
  classes, so the proposed rule in R6 also says to park.
- **Saved patch:** `tmp/parked/phase0-inventory-state-round4.patch`. It
  applies to the tree at the inventory core commit with
  `git apply --index`. It includes a small fix to the committed
  `inventory.py` (declaration lines in `parse_ivar_block` were off by one
  after `@public` and similar, for 182 ivars). `tmp/` is not committed, so
  the patch exists only on this machine.
- **Also set aside:** `phase0-inventory-verify`, which imports this module
  and has not been reviewed, at
  `tmp/parked/phase0-inventory-verify-unreviewed.patch`.
- **Outstanding findings.** No author has responded to them:
  1. A C array ivar passed by bare name is classified `read` although the
     callee writes through it. `iTermColorMap.m:372` and `:558` (`memmove`),
     `iTermMetalDriver.m:309` and `:353`. At least 4 ivars are reported
     read-only that are written. Proposed fix: a bare array name outside
     `sizeof` counts as `addr`.
  2. A protocol-qualified class type, `X<P> *`, is treated as a generic and
     the protocol's visibility is not checked. 3 rows, including
     `PTYTab._variablesScope`, are "degraded" where
     [objc-state.md §1](objc-state.md) says not imported.
  3. Block and function-pointer types are always "importable"; parameter
     and return types are not classified. 5 rows, for example
     `iTermURLActionFactory._completion`.
  4. The group explanation prints "(the cap was reached first)" when it was
     not. 9 files. The cause is one condition near line 1852.
- **What every review found sound:** the ivar list. It matched the built
  binary exactly across 947 classes, and declaration lines are right for
  7,592 of 7,594 rows.
- **The pattern:** each round fixed what was found, and the next reviewer
  found a different class of text-analysis gap in the use kinds, the
  importability verdict or the accessor verdict. The ivar list, statics and
  ARC-based ownership have not produced a finding since round one.
- **Options:**
  1. One more fix round and review. The four findings are small.
  2. Split: commit the ivar list, declaration sites, statics and ownership
     as one piece, and treat use kinds, importability and accessor verdicts
     as separate pieces, each reviewed alone.
  3. Take importability, inherited accessors and ownership from the runtime
     and the compiler in the verify step, and keep the text tool to what
     text can establish.
- **Meanwhile:** the orchestrator moved to Phase 0 items that do not need
  this table.
- **Answer:** 2026-11-19: discard the text version and rebuild the table as
  queries on the code database, with types and importability from the
  compiler.

### Q8. An existing duplicate selector in `PTYTask`
- **Added:** 2026-11-18, found by the runtime snapshot tool and confirmed by
  its reviewer.
- **What:** `PTYTask` has two `-processInfoPID` methods. `PTYTask.h` declares
  the property in the class interface, the getter is written only in the
  category in `sources/Tasks/PTYTask+ProcessInfo.m`, and the compiler also
  synthesizes a getter and an ivar in the main implementation. Which one
  runs is not defined. It is the only duplicate among the roughly 2,000 app
  classes.
- **Needed:** agreement to fix it in a `fix` commit (most likely by moving
  the property declaration into the category, or marking it `@dynamic`),
  after checking which implementation runs today.
- **Blocks:** any snapshot comparison involving `PTYTask`, which fails by
  design while a duplicate exists.
- **Meanwhile:** nothing depends on `PTYTask` yet.
- **Answer:** 2026-11-19: fine to fix, provided nothing breaks. Fixed the same day
  with `@dynamic` in `PTYTask.m`; the category's getter was the one running
  before, so callers see no change.

### Q13. Which other directories are in scope
- **Added:** 2026-11-19.
- **Decided:** the owner's code in `SignedArchive/` (39 Objective-C and C
  files and headers), `pidinfo/` (13) and `iTerm2SandboxedWorker/` (9) is
  to be migrated.
- **Assumed from the same rule, to confirm:** `ColorPicker/` (57 files),
  `SearchableComboListView/` (4), `BetterFontPicker/` (3) and
  `ShellLauncher/` (1). [README.md §2](README.md) lists them as in scope.
  Say if any of them should stay as they are.
- **Not included:** `Companion/` (3 vendored C files in an iOS app that is
  otherwise Swift), `tests/`, `Applescript Tests/`, `PerformanceTests/`.
- **Follow-up work:** `inventory.py` still defines scope as `sources/` and
  `ThirdParty/PSMTabBarControl`. Its scope list, counts and leaf ordering
  need a `tool` commit; see the checklist.
- **Answer:** 2026-11-19: yes, all four are in scope.

### R6. The four-round cap, and a deviation from it
- **Added:** 2026-11-19.
- **What happened:** the runtime snapshot tool (after ivar ownership was
  split out) had blocking findings in its fourth review. They were one
  one-line parser bug, the wording of the pass caveat, and two missing
  tests. [workflow.md §2](workflow.md) says to split or park at that point.
  No further split made sense, and parking would have stopped all of
  Phase 0, because every other item depends on this tool or the inventory.
  The orchestrator ran a fifth round instead. This is a deviation from the
  rule as written, recorded here so it is not silent.
- **Second occurrence, same night:** the inventory core (after its split)
  also had blocking findings in its fourth review. All three came from two
  recently added features, the transitive stored-state wrapper discovery
  and the Swift selector-site scan; the review confirmed everything else by
  its own scripts. The orchestrator asked a fresh author to replace the
  discovery with a simpler rule whose reasons can be checked, and will run a
  fifth review.
- **Proposed rule:** the cap stays at four, but the orchestrator may run
  further rounds while findings are converging, meaning each review has
  fewer or narrower blocking findings than the last and none of them is a
  wrong result on the real tree. Each extra round is recorded in the night's
  report. A review whose blocking findings are as broad as the previous
  one's still means split or park.
- **Also proposed, from the same experience:**
  - Authors run out of context after two or three rounds on a large item.
    Say in workflow.md that a fresh author taking over from a handback note
    is normal, and that an author who is near its limit stops and writes
    that note instead of starting a round.
  - Give reviewers the labeling guidance that worked: blocking means a wrong
    result or false statement on real code, a file or verdict that would
    mislead an agent, or a rule that matters with no test; leniency that
    only hand-edited input or a contrived class can reach is non-blocking.
  - Size Phase 0 items so that one author can finish in one context. The two
    tools started as single items and had to be split into six.
- **Answer:** 2026-11-19: continuing past four rounds was fine, and
  findings that are unlikely to occur in practice can be let slide. The
  rule is now in [workflow.md](workflow.md) sections 1 and 2. The other
  proposals in this entry (fresh authors from handback notes, labeling
  guidance for reviewers, sizing Phase 0 items) are followed in practice
  and are not yet written into the process files.

### Q11. Where Swift callers of Objective-C methods come from
- **Added:** 2026-11-19.
- **What:** the code database is built from the Clang AST, which does not
  contain Swift. To know which Swift code calls an Objective-C method, or
  names it with `#selector`, and what Swift can import from a bridged
  header, a second source is needed. The one that was measured to work is
  Xcode's index store, with `swift-synthesize-interface` for importability,
  and both are ruled out by the decision not to depend on Xcode's tooling.
- **Options:**
  1. `swiftc -dump-ast` or `-emit-symbol-graph` on the Swift sources, with
     the compile commands captured from the build. The compiler is still
     the one Xcode ships, but the interface is the compiler's own.
  2. An open-source Swift toolchain from swift.org at a pinned version,
     with SourceKit or `swift-syntax`. No Xcode at all, but a second
     toolchain to install, and it must be able to build against this SDK.
  3. `swift-syntax` alone, which parses without types. It finds calls by
     name but cannot say which declaration a call resolves to.
  4. Text search over Swift for selector base names, as the parked census
     does, kept as the stated limit.
- **Meanwhile:** the Objective-C side is being built first. Nothing is
  ported that has Swift callers until this is answered, or the dossier
  lists the Swift callers by reading.
- **Answer:** 2026-11-19: use the Swift compiler's own AST dump
  (option 1). The owner expects it to be the most complete. A spike
  confirms what it contains before the item is built.

Items the owner has answered and the orchestrator has not yet acted on.

None.
