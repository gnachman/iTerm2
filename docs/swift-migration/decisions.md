# Decisions

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

The dated record of decisions made by the owner, with the reason for each.
[README.md §3](README.md) states the rules that follow from them; this file
says why. Add an entry whenever a rule in the process files changes, in the
same commit as the change.

## 2026-11-18: initial decisions

| Decision | Reason |
|---|---|
| AI-written documents are allowed in `docs/swift-migration/` only | The work is done by many agents with no shared memory, so the process and its records must live in the repository |
| `submodules/` is out of scope. `ThirdParty/` is out of scope except `ThirdParty/PSMTabBarControl` | PSMTabBarControl is now predominantly the owner's code |
| An out-of-bounds array access may crash in Swift | It is a bug that at least sometimes crashes in Objective-C already |
| Integer overflow is generally clamped, after checking for reliance on wrapping. Superseded the same day by the build-dependent policy below | Signed overflow is rarely better than a clamped value |
| Every overflow-capable arithmetic site is considered individually | Clamping can turn a loop that used to end into one that never does |
| Assertions are added liberally, through an `ITBetaAssert` equivalent | They validate assumptions without slowing release builds or adding crashes there |
| Nil that Objective-C handled by messaging nil is ported as such and not asserted on | Zero is very often the intended result |
| Hot paths are left until last | They need individual attention and must not block the bulk of the work |
| Tests run locally on every commit; fixing the Xcode CI job is optional | With this many tests, CI is not expected to save time |
| Hidden callers are hunted explicitly: selector strings, `NSStringFromSelector`, the runtime API, macros, and xib files | Any of them can call a method that no search of the source finds |
| More warnings are enabled, one file at a time | Warnings find dangerous patterns, and thousands at once are unmanageable |
| No hard limit on the size of a function in a port commit; over about 150 lines requires extra review | There are always extenuating circumstances |
| A temporary copy of a function may live in the test target only, with a distinctive marker | So that all of them can be found and proven gone at the end |
| Large files are ported a few methods at a time | Delete-and-replace in one commit does not work for files with hundreds of methods |
| The fast test tier runs without the address sanitizer | Speed; the full suite keeps it |
| No single test should take anywhere near 114 seconds; the slowest tests are fixed | About 20 minutes for a serial run is too long for this project |
| How Swift reaches each ivar is decided case by case | The cost of a property can be too high for some code |
| Raw ivar accessors are named `ivar_foo` for the ivar `_foo` | The natural name is often taken by an accessor that does something else, which is dangerously misleading |
| Every port asserts that a lock passed to `@synchronized` is not nil | A nil lock silently locks nothing |
| The thread sanitizer is used in tests but not when running the app | It falsely flags every Metal frame; almost no test touches Metal |

## 2026-11-18: unattended workflow

| Decision | Reason |
|---|---|
| The work runs mostly unattended | If every change waited for the owner's review, the migration would never finish |
| Each change is made by an Opus subagent and reviewed by another, iterating until the reviewer finds no meaningful issues; the author adds tests to validate findings | It replaces the owner's review of each change |
| A reviewer is never reused; every review is by a fresh subagent | A reviewer that has seen earlier rounds checks whether its findings were addressed, not whether the change is right |
| A unit stuck after too many rounds is set aside for the owner, and work continues elsewhere | The owner is happy to help but must not be on the critical path |
| The orchestrator does not need permission to move to the next class. The owner looks at rule changes, hot paths, and the move from one tier to the next. Giant classes need no checkpoints | Per-class approval would block the work. This removes the earlier checkpoint at the first extraction from each giant class and keeps the one at each tier |
| Items needing the owner go into `owner-queue.md`; the orchestrator parks and continues and never blocks on the owner | There is enough other work to keep the agents busy for a long time |
| Agents start at midnight and stop when weekly usage reaches the fraction of the week elapsed: 1/7 on the first night after the reset, 7/7 on the last | It spreads the weekly quota evenly and leaves the owner's daytime use intact |
| The run uses Opus throughout, and the budget is read from the "all models" line of `claude /usage` | Usage figures for other models are not relevant |
| Agents commit locally and never push; the owner reviews and pushes each morning | The owner sees everything before it leaves the machine |

## 2026-11-18: decisions from the review of the first draft

| Decision | Reason |
|---|---|
| A `switch` over an enum in Objective-C has no `default:`; `-Wswitch-default` is not used | Listing every case lets the compiler warn when a value is added |
| `CLAUDE.md` gets an exception for `docs/swift-migration/` and a pointer to the README | Otherwise an agent that reads `CLAUDE.md` first may refuse to commit these files. |
| Migration commits go directly onto master, with linear history, not through pull requests | Squashing a pull request would merge commits of different kinds, lose their trailers, and prevent reverting one alone |
| Unsafe pointers are used sparingly: for a measured performance need in a hot path, or temporarily | Otherwise a port keeps every out-of-bounds hazard of the C, against goal 1 |
| Arithmetic overflow crashes in Development, beta and nightly builds and clamps in release | So that it is found, without giving users crashes the Objective-C did not have |
| The app is built for Intel as well as Apple silicon | Several hazards differ between the two slices |
| One orchestrating agent assigns work to subagents and commits | Agents will not work on the migration independently |
| Soak is checked against crash reports, attributed by line. The wait for a soak was removed on 2026-11-19 (below) | Most crashes can be attributed by line number; reports need checking regularly |
| Rollbacks are handled case by case | They should be rare |
| The measurable goal is zero Objective-C | It gives a measure of progress, while accepting it is almost certainly not reachable |
| Nullability Step A applies to one header at a time, on demand | A sweep would churn hundreds of headers that feature work changes constantly |
| The process is split into topic files with a README that every agent reads | One file of over 3,000 lines uses too much of an agent's context and invites skimming |
| Every unit gets the full dossier, however small | A reduced dossier for simple units was proposed and rejected |
| Phase 0 is completed in full before the pilot | Building only what the pilot needs was proposed and rejected |
| Runtime behavior that tests cannot reach is verified by the lightest sufficient check, with VM QA for the most complex cases | Agents must not drive the owner's computer, and tests do not exercise the responder chain |
| Objective-C++ gets its own strategy: remove the C++ in Objective-C first, then port | It keeps translation and behavior change in separate commits |

## 2026-11-19: tools that analyze source use the compiler

| Decision | Reason |
|---|---|
| Tools that must understand Objective-C, C, C++ or Swift source start from the Clang AST and other compiler output, not from lexers and regular expressions written for the purpose | The text-based entry-point census and ivar table failed review round after round, each time on a different thing that only the compiler knows: sends hidden in macros, how an ivar is used, what Swift can import |
| The work is split in two phases: extraction writes facts from the AST into a database, and every tool is a query on that database | Queries can be run as often as needed without parsing again, and the database stays useful while code moves between files |
| Each translation unit in the database records a digest of its compile command and of every file it read; a query reports which of its rows come from units that are stale | Staleness is then reported by the tool and not left to an agent's judgment |
| Large data is streamed, only what is needed is kept, and it is stored compactly. Nothing large is loaded whole | Loading 160 MB AST dumps whole used over 20 GB per process and exhausted the machine's memory |
| Tools are written in whatever language suits the task. The earlier instruction to authors to use only the Python standard library is withdrawn | The natural extractor is a small compiled program on libclang |
| The tools do not depend on Xcode's own tooling: not its libclang, its index store, `-showBuildSettingsForIndex`, or any private file format. The extractor is built on upstream LLVM at a pinned version, and compile commands are captured from a real build with Clang's `-gen-cdb-fragment-path` or from the build log | Xcode changes constantly and is unreliable; Xcode 27 removed `-dry-run`. The macOS SDK headers are still needed to parse, and that is the one unavoidable use |
| Because upstream Clang is not the compiler that builds the app, the database is checked against the app's object files: the selectors each object file sends must be explained by the database, and the reverse | It shows that the two front ends agree on this code |
| Text and XML search remains for what the compiler does not see: xibs, storyboards, the sdef, plists, Core Data models, and names built at run time | The AST does not contain them |

What the spike of 2026-11-19 measured on this machine, which the design
rests on:

- Upstream Clang 22 from Homebrew parses `iTermPreferences.m` against the
  Apple SDK with the project's flags and no diagnostics, once flags it does
  not know are removed. It has the full C++ API, so the extractor can be a
  LibTooling tool. Xcode ships no Clang headers at all.
- A program on libclang parses `PTYSession.m` in 4 seconds at about 420 MB.
  The whole tree is estimated at 10 to 25 minutes, serially.
- `xcodebuild -dry-run` no longer exists, and an incremental build log has
  no compile commands, so capturing them takes one full build.
- The AST attributes a send made inside a macro to the place the macro is
  used, contains methods whose names are built by token pasting, and
  records macro definitions and expansions.
- The compile arguments Xcode uses include `-index-store-path`. A tool that
  runs them unchanged overwrites Xcode's own index, as the spike did once.
- Swift callers of Objective-C methods are not in a Clang AST. How to get
  them without Xcode's index store is not yet decided.
- Code in an inactive `#if` branch, the other architecture, and other build
  configurations are not in the AST. The extractor records skipped ranges so
  that a query can say so.

## 2026-11-19: what the pure-move checker means

| Decision | Reason |
|---|---|
| A pass from the pure-move checker means the change is probably a pure move. A failure means more analysis is needed, not that the change is wrong | A correct extraction that turns a local into a parameter or out-parameter rewrites every use of it, and no comparison of text can accept that. The earlier wording required extracted lines to be identical, which contradicted the rule that written locals become out-parameters |

## 2026-11-19: review rounds and unlikely findings

| Decision | Reason |
|---|---|
| The orchestrator may run more than four review rounds while the reviews are converging and none of the latest findings is a wrong result on real code | The first Phase 0 tools reached a fourth review with only narrow findings left; parking them would have shelved work that was nearly done. The owner approved continuing |
| A finding that is unlikely to occur in practice is non-blocking and may be let slide | Fresh reviewers keep finding defects that only hostile or hand-made input can reach, and fixing each one keeps the loop running without making the migration safer |

## 2026-11-19: scope beyond `sources/`

| Decision | Reason |
|---|---|
| The owner's code that is compiled into the app from outside `sources/` is in scope: `SignedArchive/`, `pidinfo/`, `iTerm2SandboxedWorker/` | It is app code like any other. The code database found it when it recorded callers outside `sources/` |
| The code database records callers in every file in the repository, in or out of the migration's scope | A caller matters when a method is ported, wherever the caller lives |

## 2026-11-19: Swift facts from the Swift compiler's AST dump

The owner chose the Swift compiler's own AST dump as the source of Swift
callers (owner queue Q11). A spike on this machine found:

- The JSON form (`-dump-ast -dump-ast-format json`) gives, for every call,
  property reference, `#selector` and key path, the Clang USR of the
  Objective-C declaration it resolved to. That is the same string the code
  database stores for Objective-C sends, so the two sides join directly,
  including methods Swift imports under another name (`draw(_:)` is
  `drawRect:`, `throws` and `async` forms carry the full selector).
- One compiler process dumps the whole app module (961 files) in about 30
  seconds at 2.3 GB, with every file as a primary file. The output, about
  590 MB, is streamed and never stored. A reader on a streaming JSON parser
  used 3 MB.
- Swift has no way to record its own invocation, so the command comes from
  the build log's `SwiftDriver` line and the module's file list.
- A file's AST depends on its whole module, so the Swift side is cached per
  module, not per file.
- `swift-symbolgraph-extract` (the compiler under another name) on a module
  map that wraps the bridging header lists every Objective-C declaration
  Swift can import, by USR. A declaration that is absent cannot be seen
  from Swift.

Limits found, which the Swift tables must state:

- The compiler's help says the dump's format is not stable across versions.
  The reader is pinned to the compiler version and has fixture tests.
- This compiler has assertions on, and the JSON writer trips one on
  synthesized `Codable` code; `-Xllvm -assert-continue` gets past it. The
  count is recorded per module.
- A `#selector` naming a `private` `@objc` method does not show its
  selector (341 of 446 uses in the app). It is derived from the Swift name
  or read from the object file.
- Swift names a property, where the Objective-C side records the getter or
  setter that was sent, so the database needs a table of properties with
  their accessor selectors.
- Code in an inactive `#if` branch is absent, as on the Clang side.

## 2026-11-19: answers from the owner queue

| Decision | Reason |
|---|---|
| A port's dependents are ported without waiting for it to appear in nightly builds. Crash reports and beta assertion failures attributed to a port are still acted on when they arrive | Bug reports from nightly users are rare, so a soak tells little (owner queue Q3). Tests and review carry more of the weight |
| A flaky test is disabled, recorded in `bugs.md` with how it failed and when, and reported to the owner, who has another agent debug it. Flaky means it failed in a full run and passed alone on the same commit with no change to the code; a test that fails consistently is a failure, and a unit's targeted tests are not treated as flaky while its change is uncommitted. Deleting or weakening a test, or disabling one for any other reason, still needs the owner | The owner chose this over rerunning and logging each occurrence (owner queue Q9). The narrow definition keeps the rule from silencing a real failure |
| The ceiling for a single test in any tier is 10 seconds, above which the gate fails. The target for new tests and tests being fixed is under 1 second | Most tests should take under 1 second (owner queue Q1) |
| The fast tier's wall-clock budget, including the build, is its measured time plus a quarter, set once it has been measured | Proposed and accepted (owner queue Q2) |
| Warnings are treated as errors in every build configuration once the project-wide warning group is clean | Accepted as proposed (owner queue Q4) |
| An `assign` or `__unsafe_unretained` object reference is changed to `weak` in Objective-C, in its own `fix` commit with a lifetime test, before its class's state moves to Swift. `unowned` and `unowned(unsafe)` stay banned in migration Swift | Without this a class with such a reference has no allowed Swift form. The owner does not expect it to introduce bugs; the test covers the one known difference, a reference read while its target is being deallocated (owner queue R5) |
| For a class that changes language, the runtime snapshots must be identical in meaning, with the Swift compiler's systematic differences classified and listed for the reviewer. Incremental ports keep the rule that they are identical | The compiler orders property attributes differently, names backing ivars without the underscore, encodes some ivar types as unknown and adds `-init`, so an identical snapshot is impossible for a faithful whole-class port (owner queue R4) |
| vm1 is assigned to the migration and may be used for hands-on QA without asking. The orchestrator asks the owner to start it when VM work is ready | It is not left running (owner queue Q6) |
| Agents produce the stored-state corpus: the current version with `-suite` and AppleScript or the Python API, older releases on vm1 | `-suite` is a recent addition, so old releases cannot be isolated on the owner's Mac; downloading old release builds on the VM is fine (owner queue Q7) |
| The orchestrator may run `killall CoreDeviceService` when `xcodebuild` hangs waiting in CoreDevice | The system restarts the service on demand (owner queue Q10) |
| Factual errors and out-of-date descriptions in the process files may be corrected without asking the owner. A change to a rule still needs the owner and an entry here | The owner's standing answer to R1, R2 and R3 |

## 2026-11-20: answers from the owner queue

| Decision | Reason |
|---|---|
| The unattended nightly session runs in a separate clone whose remote cannot be written, not in the owner's working checkout, and as an ordinary Claude Code session inside tmux on a custom socket path, not headless. The owner takes the night's commits by fetching from the clone | A reviewer showed that the working checkout's local allow rules would let an unattended session push with no safety check. A clone that cannot push bounds the damage; tmux lets the owner attach, watch and intervene (owner queue Q19) |
| User-level hooks stay enabled in the nightly session. Network access is not restricted further. The schedule stands: start by 04:59, stop cleanly by 06:15, hard limit 07:00 or six hours | The owner wants status in iTerm2 and to answer prompts from his phone; he has had no problem with network access; the Mac never sleeps (owner queue Q19) |
| `.claude/agents/` is tracked in git, with the author and reviewer agent definitions there; the rest of `.claude/` stays ignored | It is the location Claude Code reads, so every session and every clone gets the same definitions (owner queue Q19) |
| The reading of a macro that hides a caller, a method definition or control flow lives in `macro-classification.tsv`, one row per macro, checked by `codedb.py macrolint`; the reflective-site registry points to it. In addition, anything about a macro that is unexpected or surprising and will be needed when porting is written as a comment in the code at the macro's definition | The lint already enforces the file and resets a row when the macro changes. The comment puts the surprise where the person porting will read it (owner queue Q21) |
| Agents that change code or run builds each work in their own clone, with its own build directory and code database, and up to three builds may run at once. One lane is kept for the full-suite run that decides whether a commit lands. The orchestrator takes each agent's change from its clone and commits it in the main checkout | One shared working tree and one `Build/` forced a single build lane, and units waited an hour or more for it. The machine has 16 cores and 64 GB; more than three concurrent builds would saturate it and make timing-sensitive tests fail (owner, 2026-11-20) |
| Dead code may be deleted. A method or function is deleted only when the entry-point census lists it under "no caller found" on a current database with every source consulted, in its own commit outside any port, with the full suite passing afterwards. Methods under any other census heading are not dead by this rule | The owner's standing permission ("feel free to delete dead code"). The conditions are the orchestrator's: the census listed reached methods as unreached in three successive reviews before its causes were fixed, and a deleted workaround is hard to notice |
| `XLog` is replaced by `RLog` everywhere, in Objective-C and in Swift, and `XLog` is removed | The Objective-C `XLog` always calls `NSLog` while the Swift `XLog` returns early when debug logging is off, so the two are not equivalent and a port would change behavior. The owner judges `RLog` strictly better (owner queue Q21) |
| Migration Swift may use an implicitly unwrapped type outside a property (a parameter, a result, a local, `init!`) when that is the best way to proceed, but not indefinitely: each such site carries a marker comment giving the reason, so the sites can be found, and is removed once it is no longer needed. The lint requires the marker and the inventory counts the sites | An unannotated Objective-C signature is imported with these types, and matching it is sometimes the right step in a port. The owner allows it as a temporary state that must be findable (owner queue Q20 item 1) |
| `assertionFailure` and `preconditionFailure` are banned in migration Swift, with `fatalError`, `assert` and `precondition`. Ports use `it_fatalError`, `it_assert` or the beta assertions | They have the same crash-log problem, and `assertionFailure` does nothing in release builds while the Objective-C `assert` it would replace stays enabled there (owner queue Q20 item 5) |
| The Beta and Nightly configurations compile Swift as a whole module, as Deployment does | File-by-file compilation cannot inline the arithmetic helpers across files, so ported hot code would run much slower in nightlies than in release and nightly timing would not predict release timing (owner queue Q17) |
| The checked-arithmetic helper calls (`it_add`, `it_subtract`, `it_multiply`, `it_negate`, `it_shiftLeft`, `it_narrow`, `it_floatToInteger`) are scaffolding for a faithful port, not the final form. Every one is removed eventually, in stage two, by replacing it with ordinary Swift once the overflow or conversion question at that site has been answered. The inventory counts the remaining calls | They make the code very hard to read (owner, 2026-11-20). They exist so that a port neither traps where C wrapped nor hides an overflow; once a site is understood, plain arithmetic or an explicit check says the same thing more clearly |
| Swift gets a `BETA` compilation condition in the Development, Beta and Nightly configurations, matching the C macro. `it_conservativeBetaAssert` compiles to nothing without it. A test asserts that the Swift condition and the C macro agree | Swift cannot see C macros, so the helpers read a run-time constant, and a conservative assertion still cost a load and a branch in release, where assertions.md asks for nothing. Same kind of mismatch as Swift's `DEBUG` (owner queue Q17) |
| In release builds every arithmetic and conversion helper does what the C it replaces does in practice: integer add, subtract, multiply and negate wrap; narrowing truncates; a left shift discards bits and a shift count is masked as the hardware masks it; a float converted to an integer gives what the processor gives (saturating with NaN as 0 on arm64, the minimum integer on x86_64). In Development, Beta and Nightly builds and in tests the same helpers assert aggressively on every such event. This replaces the earlier rule that overflow clamps in release, and removes the Clamp, Wrap or Stop choice per site | It minimizes the risk to release users: a port changes nothing for them, good or bad, while development builds and tests find the problems. Clamping was a behavior change in release, and could turn a loop that relied on wrapping into one that never ends (owner, 2026-11-20, owner queue Q17) |
| A migration Swift file is in stage two when no Objective-C refers to any type it defines, as the code database shows. The commit that starts stage two for a file adds the marker `// SWIFT-MIGRATION-STAGE: 2` at its top, and the gate checks the marker against the database and refuses one that is not true. The lints lift the stage-one ban on Swift concurrency only for files carrying a verified marker | The lints had no way to know a file had left stage one. The database answers the question the stage-two rule is defined by, and the marker makes the status visible in the file (owner queue Q17) |
| A new or changed `@synchronized` locks on `self`, a class object, or `ITNonnilLock(...)`, statics, globals, locals and parameters included, and `tools/check_nonnil_locks.py` enforces this from the pre-commit hook on added and changed lines, with a `// nonnil-lock-ok: <reason>` escape hatch | `@synchronized(nil)` silently locks nothing, and the macro was added only at the existing sites. In the owner's words: “The main risk is other agents not related to the re-factor adding one, so a rule like a lint that runs in a commit hook would be a good idea.” Wrapping is always harmless, so the rule needs no judgment about which locks can be nil |
| Migration Swift declares no file-scope `var`. A static or global variable from Objective-C becomes a static property of a type. The lint `file-scope-var` enforces it. A file-scope `let` constant is allowed (confirmed by the owner). The one Swift `XLog` call, which logs web page console output in the built-in browser, becomes `DLog`, not `RLog`, so page content is recorded only when debug logging is on | The owner, while reviewing the implicitly unwrapped lint: “I don't think global top-level variable should ever be used in Swift” |
| Dead code is never deleted when it could be overriding a public or private method of a superclass, or replacing one through a category. The census must check every candidate, whatever its name and whatever its superclass, against the list of methods the frameworks implement at run time; the shortcut that skipped the check for a class whose framework ancestor is NSObject and whose selector has no leading underscore is removed. The run-time list is specific to one macOS release, so the commit message states which releases were consulted | The owner, 2026-11-20: “Not all Apple private methods begin with an underscore. And I used underscores in the early days of the project for my private methods. You definitely shouldn't delete dead code that could be overriding a private or public method of a superclass.” A leading underscore says nothing in either direction |
| Word selection in regular expression mode extends over at most max(20, 2 x the screen height) lines of a soft-wrapped line; the `INT_MAX + width` overflow in the text extractor is fixed | The overflow made the "no limit" request mean "this row only", so a match that continued across a soft wrap was cut short. With the overflow fixed and no bound, a double-click on a very long wrapped line would do unbounded work on the main thread (owner, 2026-11-20) |
| The x86_64 results of the arithmetic and float helpers are derived from the instructions clang emits, not observed | macOS 27 does not support Rosetta, so no Intel code can be run on the owner's machine (owner, 2026-11-20) |
| Where what C does is not one fixed result, the helper clamps. `it_floatToInteger` saturates an out-of-range value to the target type's range and gives 0 for NaN, the same on both processors, and still asserts in Development, Beta, Nightly and tests. This amends the row above for float conversions only; integer wraparound, narrowing and shifts keep the C result, which was the same at every optimization level observed | The review of the helpers showed that an out-of-range float conversion in C gives different values depending on the optimization level and on whether the result is stored or kept in a register. The owner, 2026-11-20: “If ‘what C does’ is variable, then clamping is fine. My goal was to not break things that work by accident, but it sounds like they would only work accidentally on occasion anyway and clamping is more likely to accidentally work than anything else” |
| Float-to-integer conversions through the helper must not sit in a hot path. Where a hot path needs one, a cheaper and less safe form may be used, decided when that code is ported and with the owner's sign-off | The checked conversion costs many instructions where C has one. The owner, 2026-11-20: “Make sure the expensive float conversions are not in the hot path. We might need to be less safe in those cases” |
| The three hot-path nullability units (Metal, VT100Screen and LineBuffer, drawing) go ahead | The owner, 2026-11-20: “Hot path nullability annotation changes are fine. I presume you're changing them to be safer, which might incur more unwrapping, but that is a low cost and it's worth it for correctness” |
| “The nightly start mechanism and the usage check, proven over several nights” is no longer a Phase 0 item: Phase 0 needs it set up and dry-run; it is proven in use afterwards | It cannot be shown before the end of Phase 0 by its nature (owner, 2026-11-20) |
| The orchestrator runs as many agents at once as the work allows, each in its own lane, limited only by hard dependencies between units and by the machine's memory | The owner, 2026-11-20: “We shouldn't be lane-constrained unless there are hard dependencies” |
| The nightly clone follows the project's `origin/master` on GitHub. Every night the trusted start script fetches it and rebases the clone's own unpushed commits onto it; a rebase that conflicts skips the night and leaves the clone as it was. This replaces following the owner's local master through a mirror of his checkout | The owner, 2026-11-20: “there's no point porting stale code. It needs to fetch and rebase every time it runs. Usually I'll review its work and push during the day so there'll be nothing to rebase, but I'll miss days from time to time” |
| After new upstream code arrives, the orchestrator refreshes derived data before starting a unit: compile-command capture if stale, the code database, the macro lint and cross-check, the run-time method list if the OS changed, and a whole-suite baseline if the new commits touched code | The owner, 2026-11-20: “when the job starts at midnight it'll need to fetch and rebase, rebuild databases, tables, etc. for new code that gets pulled in” |
| An atomic Objective-C property is ported as a Swift property whose storage is a `MutableAtomicObject` (`sources/Infrastructure/Mutex.swift`), read and written through its `value`, so the accessors still take a lock. The runtime snapshot comparison lists atomic becoming nonatomic as an item to check against the source (the storage is a `MutableAtomicObject`) instead of failing | The owner, 2026-11-21: “an objective sea atomic property synthesizes getters and setters that wrap access in a lock. You can do the same thing using the type MutableAtomicObject.” |
| The pilot starts now. Phase 0 is no longer completed in full first: these items continue alongside the pilot and never ahead of it: extraction analysis, performance and memory baselines, the fast test tier's budget and the slow tests, the import table and the other Xcode projects in the code database, the whole-tree census sweep and macro readings, and the nightly job | The owner, 2026-11-21: “You are spending a lot of time fixing bugs and we still haven't begun the migration.” and “I approve of starting the pilot and your plan is good.” |
| Bugs found while building tools or porting are recorded in bugs.md and are not fixed unless one blocks a port | Same. Three rounds of terminal bug fixes on 2026-11-20 and 21 grew out of review findings and delayed the pilot |
| The first pilot unit is taken through its whole lifecycle, then the pilot stops for the owner's review: no second unit starts, in this session or in a nightly one, until he says so | The owner, 2026-11-21: “After the pilot completes I will want to review its work, so don't automatically start on the next step.” and “I want you to complete the pilot - dossier, annotation, port, tests, etc. That's what I will review” |
| The nightly session finishes the remaining Phase 0 items (extraction analysis, performance and memory baselines, the fast tier's budget and the slow tests, the import table and other projects, the census sweep and macro readings); it does not start a second pilot unit | The owner, 2026-11-21: “And I'm fine with wrapping up the remaining phase 0 work overnight” |
| Units take one of two paths: a light path for small leaf units (two commits, one review, a short generated dossier, the whole suite once per night) and the full path for the rest. The light path is written in lifecycle.md §3 as a proposal and is tried, timed, on the second pilot unit before any other unit uses it | The owner, 2026-11-21, on the first pilot unit: “Yeah, the two tier system makes sense”. That unit, 44 lines, took about 3.3 hours; `sources/` has 843 Objective-C files and about 426,000 lines, so the full path for every unit would not finish |
| The first pilot unit, `iTermCacheableImage`, is accepted and closed, and the second pilot unit may start, on the light path | The owner, 2026-11-21, after reading its five commits: “These look good”, then “Close it. ... You can start the second pilot afterwards” |
| A unit's dossier changes ride in the unit's own commits and are not folded into the commit that created it; the closing commit deletes the files | A dossier is updated as the unit proceeds (the port's evidence), so its creating commit would otherwise describe work not yet done. Proposed to the owner on 2026-11-21 and carried out when he said to close the unit |
| Changes under `docs/swift-migration/` and `tools/swift_migration/` go in one commit per session, amended while it is unpushed. They are no longer folded into the commits that created the files | The owner, 2026-11-21, after pushing the history: “Yeah one commit per session would be good”. Folding would rewrite pushed commits |
| A MANUAL qualifying condition of the light path (one `qualify_unit.py` cannot decide) is resolved by an agent's reading, recorded in the dossier and checked by the reviewer; a FAIL is never overridden | The owner, 2026-11-21: “Yeah, the agent can figure that out better than me usually.” 135 of 1,160 classes fail no condition; 42 have no MANUAL but the callers' thread |
| The false nonnull claim on `-[VT100ScreenDelegate screenRestoreState:]` is fixed by correcting the annotation, as an exception to “bugs are logged, not fixed” | The owner, 2026-11-21: “Fix the nullability annotation”. Every test that creates a `PTYSession` aborted under the nullability sanitizer there, which removed that gate step from most units |
| `TabLifetimeWitnessTests.testClosedTabIsFreedWithItsSession`, disabled as flaky after one failure in a full thread sanitizer run, is run by itself and re-enabled if it passes | The owner, 2026-11-21: “Run that test by itself. When you run the full suite sometimes all of memory gets used up and everything gets very slow” |
| Time and rate metrics (seconds, milliseconds per frame, iterations per second) are estimated by the best sample, the minimum when lower is better and the maximum when higher is better, and the performance comparison compares best against best. Only the statistic is decided. Proposed and not confirmed (owner queue Q23 item 3): the 5% threshold, that spread never makes a best-of row inconclusive, the five-sample floor, and keeping the median and its noise rule for memory and counts | The owner, 2026-11-22, on the baseline's unsteady app rates (`app.stress_normal_10tabs` gave 2056, 953, 2340, 959 and 953 iterations per second): “Given the variance you should take the fastest time, since that's our best estimate.” |
| A nil passed to an Apple parameter declared nonnull, where the call does nothing or gives a fixed result with nil today, is fixed in the Objective-C by a guard that keeps that behavior, not hidden by a sanitizer suppression. This covers the twelve guards of unit `session-nullability-guards` outside `iTermGenericEvaluator`, which the owner had not named when they were written | The owner, 2026-11-22, shown one of them (`if (registration && registration.weakSessions.count == 0)`) and the alternative of one suppression line per method: “I guess it's worth it to make conversion mechanical”. A guard is exact to the line and leaves the port a straight translation; a suppression matches a whole method, would hide a later violation there, and leaves the guard to be written at the port. A site in a hot path still waits for his word ([hot-paths.md](hot-paths.md)) |
| Guards of that kind may be added wherever the sanitizer finds one, a hot path included, provided the author and the reviewer are sure the guard changes no behavior; a site where that is not certain is reported, not guarded | The owner, 2026-11-22: “I'm fine with you adding guards as long as you're sure they have no behavior-changing effect” |
| Further units may start. The night that begins at midnight on 2026-11-23 does exactly one unit and is not held to the weekly usage ceiling; from the next night the ordinary rule of one seventh of the week per night applies. `nightly_start.sh` does this through `NIGHTLY_ONE_UNIT_DATE`, which has effect on the named date only; unknown usage still stops the night. Nothing was said about parallel lanes, so one unit at a time | The owner, 2026-11-22: “You can start it at midnight.” and “Have tonight's midnight run just do one unit. We can move to the regular 1/7 rule for the next night.” |
| The two edits under `ThirdParty/PSMTabBarControl` that the nullability sanitizer needs (a nil test before `-isEqualToString:` at two sites of `PSMTabBarControl.m`, and `nullable` on `-[PSMMinimalTabStyleDelegate minimalTabStyleBackgroundColor]`) are allowed. The directory otherwise stays untouched until he says it is safe | The owner, 2026-11-22, after reading the patch: “tmp/window-nullability-guards-thirdparty.patch looks fine.” |
| The performance baseline file is kept in `tools/swift_migration/perf_baselines/` and committed | The owner, 2026-11-22: “Put the baseline with other port-related files.” |
| Time spent in a test class's `+setUp` does not count toward the one-second rule for a test ([test-speed.md §3](test-speed.md)); the rule is about each test's own time | The owner, 2026-11-22: “I would not count +setUp time.” Asked because several layout test classes were made fast by reading a nib and its string tables once per class |
| The performance regression rule: the threshold of every compared metric is the larger of 5% and that scenario's own variation, and a metric over it in one comparison is only a suspected regression, which counts when runs of both versions made back to back on the same machine confirm it (`perf_compare.py --confirm`, [performance.md §3](performance.md)). This replaces the flat 5% that was proposed. How the variation is measured is our choice, not the owner's: in one comparison, for a best-of metric, how far the reference's worst sample but one lies from its best, and for memory and counts three times the larger robust relative spread, their earlier rule; in the confirmation, the spread between the base runs. Still proposals he has not confirmed: keeping the median for memory and counts with its 10% noise limit, the five-sample floor, and that spread never makes a best-of row inconclusive. What the measure costs is in owner-queue.md Q23 item 19 | The owner, 2026-11-22, asked whether to keep the flat 5% or to use 5% or the scenario's own run-to-run variation, whichever is larger, with a flagged regression counting only if it shows up again back to back: “per-scenario variation plus a back-to-back confirmation”. On time and rate metrics in result files of identical code, the flat 5% flagged 10 false regressions in three files and the chosen measure 5; resident-memory rows, judged by the unchanged median rule, read 4 false suspicions in one of them under both |
| The fast tier's 10 second ceiling is judged by a test's median, not by single runs | The owner, 2026-11-22: “Sure, median is fine”. 46 fast tests exceeded it in single runs on a loaded machine while their medians are under a second |
| The browser debug autofill menu item is left dormant; its JavaScript is not restored | The owner, 2026-11-22: “Leave it” |
| The fake screen delegate in `PerformanceTests` keeps its run-time protocol conformance; no app class is made public for it | The owner, 2026-11-22: “I don't care, you decide”. Decided by the orchestrator: making three internal Swift classes public for a test widens the app's surface for no gain |
| A port adds a thread assertion at the entry of every ported method whose thread is known, not only where the code depends on confinement today | The owner, 2026-11-22: “Add assertions generously because the code could change later.” |
| Bugs the owner authorized fixing on 2026-11-22: the DECRQCRA checksum (“Fix it”), the parked terminal fixes for inline image sizing and DECCRA's destination (“Fix”), the Kitty `t=f` denylist and its error replies (“Fix”; restricting `t=f` further was not decided), the seven category methods that collide with Apple's (“Colliding category methods: rename to it_”), and the twelve dormant Swift `#if DEBUG` blocks (“Delete them since they were never used”). The CHT cap with `tabsWrapAround` is not changed (“I don't believe it can stall for seconds”); the time is to be measured | The owner, 2026-11-22, answering owner-queue.md Q23 items 6 to 9 and items 7 and 8 of the list for the owner |
| No method is deleted as dead code on the census's word or on a sampled error rate. A method is deleted only when it has itself been shown to have no caller of any kind (hidden-callers.md), and the evidence is recorded with the deletion | The owner, 2026-11-22: “you can't delete anything until you're sure it's really dead code” |
| Before a method is deleted as dead: when in doubt it is kept; for a class with an AppKit or other framework ancestor the selector must be one the frameworks do not know about, since implementing a method can by itself change the framework's behavior; and the method's commit history is read to learn why it was added and how it was orphaned (hidden-callers.md §1) | The owner, 2026-11-22: “When in doubt, keep it in. If it's a selector AppKit knows about and the class is a subclass of NSView or other APpKit classes, sometimes implementing a method is all it takes to trigger different behavior. So you have to ensure the selector is not one AppKit knows about in addition to the other tests you already perform. Looking through commit history can sometimes be instructive to see why now-dead code was originally added and then later became orphaned.” He had looked at some of the 743 by hand and found them genuinely dead |
| Of the five milder category collisions, the three on `NSView` are renamed with the `it_` prefix (`+animateWithDuration:animations:completion:`, `-insertSubview:atIndex:`, `-snapshot`); the two on `NSObject` keep their names (`+object:isEqualToObject:`, `-performBlock:afterDelay:`) | The owner, 2026-11-22: “I don't want to rename those”, then “Actually, rename the NSView ones”. He had been told that the three also collide on `NSView` itself in frameworks the app does not load |
| At most one heavy job (a whole-suite run, a suite under a sanitizer, a full or `x86_64` build, a code database capture) runs at a time across the orchestrator and its agents, at low priority; sanitized suite runs wait while the owner is using the machine (orchestration.md §3) | The owner, 2026-11-23, after a resumed night session made the Mac unusable (load average over 400): “Finish your job but don't make my machine unusable” |
| `FramerFlowTwoHopSimulationTests` is skipped unless `ITERM2_FRAMER_SIMULATION_TESTS=1`, and runs its simulations one at a time when it does run. It is run by hand after changes to the framer's flow control | The owner, 2026-11-23: “Running unit tests should not use 1400% CPU. That test is much too heavyweight to be used regularly.” The class took about 370 s in a sanitized build; unit `slow-tests-over-5s` had made it fast by running the simulations on every core at once, which is undone |
