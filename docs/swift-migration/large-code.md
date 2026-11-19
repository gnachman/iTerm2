# Giant classes and oversized functions

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

## 1. Giant classes

`PTYSession.m` (28K lines), `PseudoTerminal.m` (18K), `PTYTab.m` (10K) and
`PTYTextView.m` (9K) are never ported as files. They are emptied.

- The obstacle is state. `PTYSession` has several hundred ivars, and Swift
  extensions cannot see Objective-C ivars. Behavior cannot move until its
  state moves.
- The method: identify a cohesive group of ivars and the methods that use only
  those ivars. Create a Swift class that owns that state (this is already the
  pattern in `PTYSessionSwiftState`, `PTYSessionHostState`,
  `PTYSessionZoomState`). The giant class holds one reference to it and
  forwards. Each extraction is a normal unit with a dossier, tests, and
  review.
- The ivar table ([objc-state.md](objc-state.md)) reports, per ivar, which
  methods touch it. It is being rebuilt as queries on the code database
  (owner queue P1) and does not exist yet. Groups with low coupling to the
  rest go first.
- Lifetimes need care: the extracted object must not hold the giant class
  strongly, and the giant class's `dealloc` order must still be respected.
- When the remaining Objective-C is a thin shell of forwarding methods, `init`,
  and `dealloc`, the shell is ported as an ordinary unit.
- These files are edited constantly for feature work. Extractions are small
  and merge quickly to keep conflicts low. New feature code goes into Swift
  collaborators, not into the Objective-C file.

## 2. Functions too large to test or port as they are

Some functions cannot be characterized or ported in their current shape.
`-[VT100Terminal reallyExecuteToken:]` is about 1,470 lines: a prologue of
guards with early returns, then a `switch` with about 260 cases that between
them call 124 different delegate methods. A rough count finds one function
over 1,000 lines, 9 over 500, 35 over 300, and about 280 over 100, in
`sources/` and `ThirdParty/PSMTabBarControl`.

This is the usual problem with legacy code: tests are needed before
refactoring, and refactoring is needed before tests can be written. The
process resolves it in a fixed order, and a function this size is never
translated in one commit.

**Size guideline.** There is no hard limit, because there are always
extenuating circumstances. A `port` commit that translates a function longer
than about 150 lines is very concerning: a reviewer cannot compare two
versions of anything that long side by side with confidence. The default is
to decompose it in Objective-C first. When that is not done, the commit
requires extra review:

- The commit message says why the function was not decomposed first.
- Two independent reviewers, each working alone, instead of one.
- The golden-master tests of section 2.1 cover the function, with the
  coverage report attached to the dossier.
- The commit carries the trailer `Oversize-Port: <function>, <lines>` so that
  every such commit can be listed for the owner.

### 2.1 First, test from outside without refactoring

A function that is too big to unit test is rarely impossible to test. Find the
nearest existing seam around it and write a golden-master test there: fixed
inputs in, a recorded transcript of everything observable out, compared with a
stored expected transcript.

For `reallyExecuteToken:` the seams already exist:

- Input: byte streams run through the real parser, which produces the tokens,
  with the terminal put into each relevant mode first.
- Output, option one: a recording delegate. A proxy object that conforms to
  `VT100TerminalDelegate` writes down every call it receives, with arguments,
  in order, and returns scripted values for the calls that return something.
  The transcript is the behavior.
- Output, option two: one layer further out. Feed bytes to a real
  `VT100Screen` and compare the resulting grid, cursor, and modes. This needs
  no mock and covers more code, at the cost of less precise failures.

Choose the outermost seam that is deterministic. The transcript format must be
stable and readable so that a diff points at the cause.

**Coverage decides when the net is good enough.** Run the golden-master tests
with code coverage and look at the function itself. Every case label and every
branch of the prologue must be executed, or be listed in the dossier with the
reason it cannot be (dead code, needs hardware, needs a private system
state). Coverage shows only that a line ran, not that its effect was checked,
so the reviewer also confirms that each case's observable effect appears in a
transcript. A Phase 0 tool prints uncovered lines for one named function.

Inputs for the corpus come from: the escape sequences each case handles,
existing tests (51 test files already touch `VT100Terminal`), recorded real
sessions, and boundary values for every numeric parameter.

### 2.2 When no outside seam exists

Sometimes the function reaches for singletons, the clock, the file system,
user defaults, or live UI, and nothing deterministic can be observed from
outside. Then, and only then, a small set of mechanical refactorings may be
done before tests exist. They are allowed because each can be verified by
inspection of the diff alone:

- **Extract a contiguous block** into a new method or function, changing
  only what the extraction forces: a local that the block uses becomes a
  parameter, and a local that the block writes and the caller reads
  afterwards becomes a return value or an out-parameter, so its uses inside
  the block are rewritten (`z` becomes `*z`, `&z` becomes `z`).
- **Introduce a seam for one dependency:** a parameter or property whose
  default is exactly the old expression (the same singleton, the same clock),
  so tests can substitute it.

Nothing else. No reordering, no renaming of anything other than the new
method, no simplifying, no merging of duplicate code, no changing a condition
to an equivalent one.

Each is an `extract` commit containing one extraction or a few closely related
ones. The checks:

- **The pure-move checker is the first check, not the definition.**
  `tools/swift_migration/pure_move.py --extract` compares the extracted
  lines with the removed lines, ignoring indentation, and requires the rest
  of the file to be unchanged apart from the lines declared as new (the
  signature, the braces, the call).
  - If it passes, the change is probably a pure extraction. The reviewer
    still reads the declared lines, which the tool prints and does not
    check.
  - If it fails, the change is not thereby wrong. It means the tool cannot
    confirm it and more analysis is needed. An extraction that turns a
    local into a parameter or an out-parameter rewrites every use of it and
    always fails this check. The further analysis is one of: the reviewer
    confirms by reading that every difference the tool lists is such a
    rewrite and nothing else; or the comparison of compiled code described
    at the end of this section.
- **Control flow that leaves the block** is the main hazard. A `return` in the
  original leaves the whole function; after extraction it leaves only the new
  method, and the caller carries on. The same goes for `break` and `continue`
  that target an enclosing loop or `switch`, and for `goto`. Every one in
  the extracted block is listed in the dossier. The list comes from
  `tools/swift_migration/extraction/extract_check.py range`, which reads
  Clang's AST ([phase0.md §11](phase0.md)), including exits hidden in
  macros, and the reviewer checks it. Either there are none, or each is handled
  by a stated convention (the new method returns a flag and the call site
  acts on it) and the reviewer checks each one. The prologue of
  `reallyExecuteToken:` is full of early returns and is exactly this case.
- **Variables.** Locals read in the block become parameters. Locals written
  in the block and read afterwards become return values or out-parameters,
  and the dossier lists them; the same tool lists both, with captures,
  addresses taken, ownership qualifiers, `self` and ivars. A local declared
  before the block and captured by a block literal inside it needs
  individual attention.
- **After the extraction**, `extract_check.py after` is available: given
  the commit and the same declaration as `pure_move.py --extract`, it runs
  pure_move's check, checks that the new function's parameters and the
  call cover those variables (including `self` assigned in the block),
  flags an out-parameter whose ownership differs from the variable it
  replaces (the implicit `__autoreleasing` of a pointer to an object
  pointer), and pairs each exit of the block with what the call site does.
  It also checks that the call sits where the block was, and accepts a
  variable coming back as the helper's return value only when the block
  assigns it on every path first. A pairing marked "matches a known safe
  pattern" is not a proof; one marked "needs review" is checked by the
  reviewer. Its result is clean
  only when pure_move also confirms the moved lines, so an extraction that
  rewrites uses of a variable always needs review, and so does any
  statement the helper or the caller gains that no pattern accounts for.
  It checks one compile
  configuration, and does not check the order or number of argument
  evaluations below. Its liveness is lexical: it can list a variable that
  need not come back, and can miss one read later only through a pointer
  stored inside the block or a reference held elsewhere
  ([phase0.md §11](phase0.md)).
- **Evaluation count and order.** An expression passed as an argument is now
  evaluated once, at the call. If the original evaluated it at a different
  point, or more than once, or after a side effect, extraction changed
  behavior.
- **Manual reference counting.** In a file not yet under ARC, an extracted
  method that returns an object must follow the same ownership as the
  original expression.
- **An independent review** of the diff, with the checker's report and
  these lists.

A stronger check may be available and should be tried in the pilot: extract
into a `static` function marked always-inline, build optimized, and compare
the code of the outer function before and after. `extract_check.py
compiled` does the comparison without changing the code under test: it
compiles both versions at `-O2` with the file's compile command and compares
the outer function's normalized LLVM IR. If the compiler inlines the
extraction back and the code is identical, that is strong evidence that the
refactoring changed nothing in that configuration. If the code differs, that
is not proof of a bug. If the new function is not inlined (an Objective-C
method never is, being called by message send), the tool says the versions
are not comparable. "identical" holds for the one configuration
compiled and up to the normalization the tool states
([phase0.md §11](phase0.md)). On real code it has so far given only
"different" or "not comparable"; on small fixtures it separates correct
extractions from broken ones. The function is turned into a method afterwards. This may prove too fragile to rely on;
it is listed in [plan.md §2](plan.md).

Once the extraction gives a testable piece, the unit goes back to section 2.1 and
tests are written before anything further is done.

### 2.3 Decompose under the net

With the golden-master tests passing:

1. Extract the function into a dispatcher plus handlers, in Objective-C, one
   `extract` commit at a time under the rules above. For a `switch`, each case
   body becomes a method and the `switch` becomes a list of calls. The
   golden-master tests run on every commit.
2. Give each handler its own direct tests. They are now small enough.
3. Port handlers to Swift one at a time or in small related groups. The
   Objective-C dispatcher calls the Swift handlers. Handlers need the state
   they touch, so the state moves first, as in section 1 (this function uses
   about 16 ivars).
4. Port the dispatcher last, when it is a short function that only dispatches.

**A frozen reference for differential testing.** For the duration of a large
decomposition, a copy of the original function may be kept in the test target
only, never in the app, and the tests run the same inputs through the frozen
original and the live version and compare transcripts. Random and generated
inputs then become useful, because no expected output has to be written by
hand. The copy is deleted in the unit's closing commit. It does not violate
the rule against two implementations, because the app only ever contains one,
but it goes stale as soon as the live function gains a feature, so the
decomposition should be finished quickly and feature work on that function
coordinated with the owner while it is in progress.

Every frozen copy is marked, on the line above it, with this exact comment:

```
// SWIFT-MIGRATION-FROZEN-REFERENCE: <unit> <original file>:<function>
```

The marker string is used for nothing else. Three checks follow from it:

- The inventory script lists every marker, with its age from `git blame`.
  Today `inventory.py summary` only counts them; the list with ages is not
  built.
- A lint fails the gate if a file containing the marker is a member of any
  target other than a test target.
- The migration is not finished until a search for the marker in the whole
  repository returns nothing. That search is part of the final checklist,
  together with the same search for `SWIFT-MIGRATION-SHIM` ([objc-state.md §1](objc-state.md)).

### 2.4 Kinds of large function

Not all of them are alike, and the right approach differs:

| Kind | Examples | Approach |
|---|---|---|
| Dispatcher: a long `switch` or chain of `if` | `reallyExecuteToken:`, `reallyPerformKeyBindingAction:`, `SetCSITypeAndDefaultParameters` | Golden master at the outer seam, then one handler per case |
| Table written as code | `strongLTRCodePoints` (812 lines), `iTermTerminfo stringForKey:` (794), `iTermCharacterSetsInit` (713), box drawing shapes (659) | Test by enumerating the whole input domain (every key, every code point) and comparing old and new output. For a finite domain that is a proof. Where the file is generated from a template in `tools/`, change the generator instead of porting the output |
| Setup sequence: many independent stanzas | `GeneralPreferencesViewController awakeFromNib` (695), `loadRulesAndTransforms` (501) | Snapshot the resulting state (control values, bindings, registered rules) as the golden master. Stanzas extract cleanly because they share little |
| Decoder of stored state | `sessionFromArrangement:` (637) | The stored-state corpus from [stored-state.md](stored-state.md) is the golden master |
| Algorithm with interleaved state | `calculateDragAnimationForTabBar:` (708), `menuAtCoord:` (453), `performTransfer:` (430) | Hardest. Deterministic tests that drive the function directly with constructed inputs, as already done for tab dragging. Decompose along the phases of the algorithm, and expect to introduce a small state struct to carry what the phases share |

### 2.5 Hot paths

`reallyExecuteToken:` is also a hot path, so under [performance.md §2](performance.md) it waits until
the end regardless. When its turn comes, decomposition has a cost that the
other cases do not: every extracted handler is a message send or call where
there was inline code, on a path that runs for every token. Extractions there
are measured with the perf harness as they are made, and the plan for that
function is approved by the owner before work starts.
