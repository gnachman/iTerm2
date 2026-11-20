# Nullability triage of the annotated headers

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

The first triage that [phase0.md §4](phase0.md) asks for: every nullability
claim in the existing code that the nullability sanitizer contradicted
during a whole-suite run, judged one by one, with a fix plan the orchestrator
can execute. The data is in
[nullability-triage.tsv](nullability-triage.tsv), one row per contradicted
claim; this file explains the columns, gives the counts, and sets out the
plan.

## 1. The run

| | |
|---|---|
| Date | 2026-11-20 |
| Command | `tools/swift_migration/sanitizer_tests.sh nullability --collect --parallel` (whole suite, no abort, no suppressions) |
| Run directory | `tmp/sanitizers/runs/nullability-20261120-013300` (not committed) |
| Tests | 12324 executed: 11637 passed, 3 failed (environment effects, see [thread-baseline.md](thread-baseline.md) section 1), 684 skipped |
| Reports | 1794 at 364 locations: 1785 at 356 locations in scope (1567 nil arguments, 207 nil returns, 11 nil bound to a `_Nonnull` local or ivar), 9 at 8 locations elsewhere |
| Grouped | 196 rows, one per group of reports the first pass made: usually one declaration and one position, but 13 rows group several parameters of one declaration (for example `iTermSessionTitleBuiltInFunction.h:24`, parameters 1 to 8). 176 rows are in the project's code, 20 in Apple's headers. Counts in this file, per verdict and per unit, are rows |
| Collection data | `tmp/sanitizer-collection/nullability/` (groups.json, classification.json with the first-pass classes) |

The 9 reports "elsewhere" are three tests passing nil on purpose and five app
locations the summarizer could not place because the report carried no file;
they belong to claims already in the table.

## 2. Columns

The file is tab-separated with a header row, sorted bytewise (`LC_ALL=C`) by `header`, then numerically by `line`.

| Column | Meaning |
|---|---|
| `header` | Where the claim is written, repository-relative. For a method declared in a header, the header (for a protocol method, the protocol's header). For a method or C function declared only in an implementation file, that file. For a Swift `@objc` declaration, the Swift file. For an Apple declaration, `SDK` and the SDK header's name |
| `line` | The line of that declaration in the current tree |
| `declaration` | The method (`-[Class selector]`, `+[...]`), C function, or Swift declaration (`Class.name (@objc selector)`). `(claim in X)` names the protocol or class whose header holds the claim when it differs from the implementing class. For a local or ivar, the method containing it |
| `position` | The parameter (name and 1-based index), `return`, or `local NAME` / `ivar NAME` |
| `annotation` | The current claim: `nonnull (NS_ASSUME_NONNULL)` (implicit), `nonnull (explicit)`, `_Nonnull (explicit)`, `non-optional Swift parameter`, `nonnull (SDK)` |
| `observed` | `nil passed`, `nil returned` or `nil assigned` |
| `count` | Reports, summed over the claim's locations; a location counts once per test host process (ten in the run) |
| `sites` | Up to three of the reported locations (`file:line`), with how many more |
| `tests` | Up to three tests that produced it; `(fixture code)` marks a fixture method rather than a test |
| `verdict` | One of the five below |
| `reason` | One line a reviewer can check: what the implementation does with nil (with file and line), where the nil comes from, and, where the first pass differed, `First pass: ...` and what settled it |
| `first_pass` | The collection night's class: `wrong-annotation`, `unclear`, `test-only`, `sdk-claim`, `swift-non-optional-parameter` |
| `swift_fallout` | For `annotation-wrong-make-nullable` only: what making the position nullable breaks in Swift (section 6) |
| `objc_callers` | For `annotation-wrong-make-nullable` only: Objective-C sends of the selector whose receiver is the class, its protocol or `id` |

## 3. Verdicts

| Verdict | When |
|---|---|
| `annotation-wrong-make-nullable` | The implementation handles nil or produces nil by design: it tests for nil, only messages the value, stores it where nil is allowed, passes it to positions that accept nil, or returns a lookup, a search, a weak reference, a delegate's answer or a failable parse (always nullable by [nullability.md §5](nullability.md)). For a Swift `@objc` declaration, the Swift parameter should be optional |
| `caller-bug-keep-nonnull` | The callee cannot use nil, and nil arrives only from a path that is itself a mistake. The caller is fixed; the claim stays |
| `test-only` | Only a test or fixture supplies the nil; no app path was found. The claim stays; a port keeps the precondition |
| `sdk-claim` | nil passed to an Apple declaration. Outside this item; a port must handle the optional before the call |
| `unclear` | Not decided; the reason says what would settle it |

Every row was decided by reading the declaration, the implementation and at
least one producing call site in the current tree, not by accepting the
first pass.

## 4. Counts

| Verdict | Rows | First pass, for comparison |
|---|---|---|
| `annotation-wrong-make-nullable` | 160 | 126 wrong annotation |
| `caller-bug-keep-nonnull` | 1 | (no such class) |
| `test-only` | 12 | 10 |
| `sdk-claim` | 20 | 20 |
| `unclear` | 3 | 27 |
| first pass "Swift non-optional parameter" | (spread over the above) | 13 |
| total | 196 | 196 |

How the first pass's classes moved:

| First pass | Now | Rows |
|---|---|---|
| wrong annotation | `annotation-wrong-make-nullable` | 126 |
| unclear | `annotation-wrong-make-nullable` | 24 |
| unclear | `test-only` | 1 |
| unclear | `unclear` | 2 |
| Swift non-optional parameter | `annotation-wrong-make-nullable` | 10 |
| Swift non-optional parameter | `caller-bug-keep-nonnull` | 1 |
| Swift non-optional parameter | `test-only` | 1 |
| Swift non-optional parameter | `unclear` | 1 |
| test-only | `test-only` | 10 |
| SDK claim | `sdk-claim` | 20 |

No first-pass "wrong annotation" was overturned: each of the 126 was read
again and the implementation does tolerate or produce nil. The 27
disagreements, each marked `First pass:` in its reason, are mostly unclear
rows settled by reading further. Examples:

- `-[iTermVariablesIndex setVariables:forKey:]` (`iTermVariablesIndex.h:19`):
  the first pass feared that a nil key collided under NULL in the
  `NSMapTable`. A scratch program shows `-setObject:forKey:nil` is a no-op
  for that table's options, so nil is harmless: wrong annotation.
- `-[PreferencePanel allSettings]` (`PreferencePanel.h:127`): the first pass
  asked whether the app can call it before the settings window loads. It
  does: `SettingPopupView.swift:13` calls it without loading the window,
  and `ProfileBoolSettingCatalog.swift:34-40` documents that the nib is not
  loaded by `+sharedInstance`. Wrong outward claim read by Swift.
- The seven `PTYTextView` and `PTYMouseHandler` event methods (`PTYTextView+ARC.h:39`
  to `:89`, `PTYMouseHandler.h:152`, `:218`): the app passes a nil event on
  purpose (`[_textview updateCursor:nil]`, `PTYSession.m:17950`, and
  `[NSApp currentEvent]`), and every body tolerates it. Wrong annotations.
- `VT100ConductorParser.init(uniqueID:)` (`VT100ConductorParser.swift:49`):
  the first pass wanted the Swift parameter optional. The nil comes only
  from `-[VT100DCSParser startConductorRecoveryModeWithID:clientUniqueID:]`
  building a throwaway parser that is replaced two lines later, and the
  Swift class stores the ID in a non-optional constant: caller bug.
- `iTermSessionDirectoryTracker.switchToTmuxPoller(tmuxController:)`
  (`iTermSessionDirectoryTracker.swift:526`): settled as test-only; the
  tests make a session a tmux client before it has a controller on purpose,
  while the app assigns the controller before the asynchronous mode change
  runs (`PTYTab.m:6863`, `:7262`, `PTYSession.m:10705`).

### Findings that cut across rows

- **One cause behind most argument reports.** A `PTYSession` evaluates
  profile-dependent configuration, its title and automatic profile
  switching before `setProfile:` has run (`-[PTYSession initSynthetic:]`,
  which `iTermSessionFactory` also uses), so nil profiles, nil session
  variables and nil profile-switching fields reach many parameters. Every
  callee involved tolerates nil, so the verdicts are wrong annotations, but
  whether that ordering is intended is an owner question (section 8).
- **The model case is smaller in Swift than expected.**
  `+[iTermProfilePreferences objectForKey:inProfile:]` does return nil
  (`iTermProfilePreferences.m:1429-1435`: neither a computed value, the
  profile nor the defaults has the key) under a nonnull claim, the dangerous
  direction. But the code database and a text search agree that Swift
  reads it at 7 places in 5 files, not dozens: `iTermBellSound.swift:73`,
  `GetProfilePropertyBuiltInFunction.swift:35`, `PTYSession+Browser.swift:180`,
  `PTYSession.swift:3196`, `iTermProfilePreferenceObserver.swift:107`, `:110`,
  `:125`. Five of them cast with `as?` or pass the value to an optional
  parameter and keep compiling; `PTYSession.swift:3196` passes it to
  `+[iTermTuple fromPlistValue:]`, whose own claim is wrong too
  (`iTermTuple.h:19`), so fixing both in one commit leaves no Swift site to
  change. The first pass's "dozens of files" came from a text heuristic that
  matched other methods' names.
- **Outward claims found beside inward rows.** Reading the bodies turned up
  positions the sanitizer did not report but which are wrong for the same
  reason, and which belong in the same commits: the `instancetype` returns
  of `+[iTermUniformExternalAttributes withAttribute:]` and
  `+[iTermCPUUtilization instanceForSessionID:]` (both return nil for nil
  input), the `image` property of `iTermImageWrapper`
  (`iTermSharedImageStore.h:17`), the `contentRegex` property of `Trigger`,
  the `profile` parameter of the block type
  `iTermRightGutterPanelWidthProvider` (`iTermRightGutterPanelRegistry.h:26`).
  Each unit's author checks these with the rows.
- **Bridged Swift parameters hide a behavior.** Where nil reaches a
  non-optional Swift `String`, `Array`, `Dictionary` or `Data` parameter, the
  bridge substitutes an empty value. Making the parameter optional is then a
  behavior change in two rows, where the code meant nil and got an empty
  value: `PathSniffer` (`pwd`) and `ImageRegistry` (`data`). Those are `fix`
  commits with tests. In the other bridged rows the empty value is what the
  code would do with nil anyway.
- **Two wrong results from bridged nil.** No row shows a callee that
  crashes on a nil the app can deliver, and the one caller bug is harmless
  today. But the two bridged rows above give wrong results, and are logged in
  `bugs.md`: in `PathSniffer`, a `pwd` of nil was meant to skip relative
  candidates, but the bridged `""` turns a relative candidate into
  `"/" + candidate` (`PathSniffer.swift:132-133`), which is then stat'd at the
  root of the file system; in `ImageRegistry`, a native image's nil data
  becomes an empty `Data` in the image info, so consumers that test its data
  see empty data instead of none (the archive is unchanged, since
  `iTermImageInfo.m:236` already writes `_data ?: [NSData data]`). The
  umbrella entry "nil reaches non-optional Swift parameters from Objective-C
  (pending per site)" can then cite this table for the other Swift rows.

## 5. Unclear, test-only and caller-bug rows

The three `unclear` rows and what settles each:

- `-[VT100ScreenDelegate screenRestoreState:]` (`VT100ScreenDelegate.h:524`):
  whether the joined block's delegate is nil during session setup, which
  would mean the callee never ran. A DLog or breakpoint at
  `VT100ScreenMutableState.m:7176` under the fixture settles it.
- `VT100SavedColorsSlot.init(text:background:selectionText:selectionBackground:...)`
  (`VT100SavedColors.swift:122`): whether every app screen's color map has
  its four keys before the terminal parses anything; if so, test-only. A
  port makes the parameters optional regardless, because a nil class
  reference in a non-optional parameter is undefined behavior.
- `-[iTermInitialDirectory tmuxSplitWindowCommand:...scope:...]`
  (`iTermInitialDirectory+Tmux.h:25`): whether the evaluator chain tolerates
  a nil scope in Custom mode.

The 12 `test-only` rows and the one `caller-bug-keep-nonnull` row keep their
claims. Each `test-only` reason names the precondition a port must keep;
where the callee would crash on nil (`-[SessionView takeStatusBarViewFrom:]`,
`-takeFindDriverFrom:delegate:`), the port asserts it. The caller bug
(`VT100DCSParser.m:535`) is fixed in a `fix` commit that gives the throwaway
parser an ID or stops building it.

The 20 `sdk-claim` rows need no change now. A port of each listed call site
must test the optional before calling the Apple method, reproducing what
messaging nil did ([translation-rules.md §2](translation-rules.md)).

## 6. Swift fallout and Objective-C callers

The fallout of making a position nullable depends on its direction
([nullability.md §2](nullability.md)):

- **An outward position** (a return, a property) becomes `T?` in Swift, and
  every Swift reference that uses it as non-optional stops compiling. The
  column gives the number of Swift references to the declaration found by
  `codedb.py swiftrefs`, with how many are in ModernTests. A reference that
  casts with `as?`, passes the value to an optional parameter or
  interpolates it keeps compiling, so the real count can be lower.
- **An inward position** (a parameter) becoming nullable breaks no call
  site: a caller passing a value still compiles. Only Swift subclasses that
  override the method and Swift classes that conform to the protocol must
  change their signatures; the column gives the number of Swift
  declarations with the selector, some of which belong to unrelated classes.
- **A Swift `@objc` declaration** changes its own signature and unwraps in
  its body; Swift callers keep compiling.
- **A file-local declaration, local or ivar** is invisible to Swift: 0.

Every query answered with exit status 3: the scratch copy of the code
database had units and Swift modules that were not current (6 of 11 Swift
modules at the start; files other agents edited during the queries made
more units stale). By the rule for this table such a count is recorded as
`unknown (N ... in an incomplete database)`: N is what the database holds,
a guide and not a proof. The compiler gives the exact list when the
annotation changes, which is how an `annotate` commit finds its Swift sites
anyway ([nullability.md §6](nullability.md)).

## 7. Fix plan

160 rows, grouped into 16 units of work an author can do in one sitting,
by header or subsystem. The order puts the claims Swift reads first. Units
N1 to N13 are `annotate` commits (N6, and N3 if its alternative is taken,
are `fix` commits, as marked), each following [nullability.md](nullability.md) sections 4 to 6:
the claim list in the commit message, the interface snapshot diff matching
it exactly, the Swift sites the compiler lists fixed in the same commit,
and the sanitizer configuration's targeted tests passing
([README.md §5](README.md), gate step 4). Units H1 to H3 touch hot paths
([performance.md §2](performance.md)) and need the owner before they start
([workflow.md §3](workflow.md)); they are queued, not executed.

Expected fallout is from the column above and from reading the Swift sites
named; "0" means no Swift call site has to change.

| Unit | Files | Rows | Expected Swift fallout | Kind |
|---|---|---|---|---|
| N1 profile preferences | `sources/Settings/iTermProfilePreferences.h`, `sources/DataStructuresAlgorithms/iTermTuple.h` | 13 | 0 if both headers change together (7 references, all compatible except `PTYSession.swift:3196`, which `iTermTuple.h:19` fixes); 1 otherwise | annotate. **Done** (unit `nullability-n1-profile-preferences`): all 13 claims made nullable. No line failed to compile, but two Swift sites changed meaning silently and were preserved by hand: `GetProfilePropertyBuiltInFunction.swift` (a missing key reached the completion as `NSNull`, now `value ?? NSNull()`) and the five `iTermProfilePreferenceObserver.value(_:)` accessors (an implicitly unwrapped `bookmark(withGuid:)` passed to the formerly nonnull `profile` trapped when the profile was missing; the trap is now explicit, see `bugs.md`) |
| N2 settings panel | `sources/Settings/PreferencePanel.h`, `sources/Settings/iTermPreferencesBaseViewController.h` | 3 | 3 if `allSettings` becomes nullable: `SettingPopupView.swift:13`, `ProfileBoolSettingCatalog.swift:43`, `ModernTests/ProfileBoolSettingCatalogTests.swift:32` iterate `allSettings()`; 0 with the alternative below | annotate, or the alternative below for `allSettings`. **Done** (unit `nullability-n2-settings-panel`, two commits): a `fix` commit takes the alternative, so `allSettings` keeps its nonnull claim and returns `@[]` before the nib loads (Objective-C no longer sees nil; Swift sees the `[]` it already got); an `annotate` commit makes the other two claims nullable, with no Swift site for either |
| N3 function call suggester | `sources/Language/iTermFunctionCallSuggester.h` | 1 | up to 89 references, all tests: 88 in `ModernTests/iTermFunctionCallSuggesterTests.swift` and 1 at `ModernTests/FunctionCallSuggesterLegacyCasesTests.swift:88`. Many only assign or compare the result, so fewer lines would change (a reviewer estimated about 20; not counted line by line) | annotate, or the alternative below |
| N4 scripts | `sources/API/iTermScriptsMenuController.h`, `.m`, `sources/API/iTermScriptHistory.h` | 4 | 1 (`ModernTests/iTermScriptHistoryTests.swift:368` reads `entryWithIdentifier:`) | annotate; then remove the two `iTermScriptsMenuController` suppressions. **Done** (unit `nullability-n4-scripts`): all 4 claims made nullable and both suppressions removed. The implementations in `iTermScriptHistory.m` and `iTermScriptsMenuController.m` also changed, because an implementation under `NS_ASSUME_NONNULL` that conflicts with a nullable declaration is a compile error. The one Swift reader compiles unchanged and behaves the same when an entry exists; for a missing entry it now gets a real nil, where before `XCTUnwrap` let the hidden nil through. `iTermScriptsMenuController.h` is not visible to Swift; both Objective-C callers of `scriptItems`, `-addMenuItemsTo:` and `iTermDependencyEditorWindowController.m:264`, tolerate nil |
| N5 Swift `@objc` parameters | `iTermEventTriggerEvaluator.swift`, `iTermTitlebarAccessoryNanny.swift`, `ToolNamedMarks.swift`, `AppSwitchingPreventionDetector.swift`, `WindowInitialPositioner.swift`, `iTermTmuxTabGroups.swift` | 6 | 0 call sites; each body adds `?? []`, `?? ""` or a nil guard that reproduces today's bridged value | annotate (Swift side). **Done** (unit `nullability-n5-swift-objc-parameters`): the six parameters are optional and each body substitutes what the bridge gave (`?? []`, `?? ""`, `?? [:]`, or `false` from `has:`); the generated header changes exactly these six parameters to `_Nullable` (four parameter names in it change too, with the selectors unchanged), and no Objective-C caller needed a change |
| N6 Swift parameters that change behavior | `sources/ContentAnalysis/PathSniffer.swift`, `sources/InlineImages/ImageRegistry.swift` | 2 | 0 call sites | fix, test first (nil instead of "" and of empty `Data`). **Done** (unit `nullability-n6-swift-parameters`): both parameters are optional and nil reaches the bodies. `PathSniffer` keeps a nil `pwd`, so its existing branch skips relative candidates; that branch is unreachable today, because `PathExtractor` only yields candidates that begin with `/` or `~`, so section 4's root-of-the-file-system result cannot happen and nothing a user sees changes. `ImageRegistry` stores nil data for a native image and for an inline image whose base64 payload decodes to no bytes: saving a native image under a `.tiff` name now renders the image instead of writing an empty file, and such a broken inline image now saves as the broken-image picture in every format instead of an empty file; copying it offers no `public.image` data instead of zero bytes, with a guard in `-[iTermImageInfo pasteboard:item:provideDataForType:]` because `-setData:forType:` raises on nil; and Cmd-dragging it no longer starts a drag (`-[PTYTextView _dragImage:forEvent:]` returns at its existing nil-data test; before, the drop gave a zero-byte file). The temporary file behind the file URL and the Open action is zero bytes as before. Both `bugs.md` entries were removed and one was added for what copying, dragging and opening still cannot offer |
| N7 expression language and variables | `sources/Language/iTermVariables.m`, `iTermVariableScope.h`, `iTermVariablesIndex.h`, `iTermBuiltInFunctions.h`, `iTermExpressionEvaluator.h`, `iTermParsedExpression.h`, `BuiltInFunctions/iTermSessionTitleBuiltInFunction.h` | 15 | 0 (one return, `recordedReferences`, has no Swift reader in the database) | annotate; then remove the three `iTermVariables` suppressions. **Done** (unit `nullability-n7-expression-language`): all 15 rows (22 positions, since one row groups eight parameters) made nullable, and the three suppressions removed, which leaves the file with none. `iTermVariables.m` and `iTermVariableScope.m` are under `NS_ASSUME_NONNULL`, so their implementations are annotated too. No Swift line failed to compile and none changed meaning: `recordedReferences` has no Swift reader outside the new test, `iTermVariablesIndex.h` is not visible to Swift, the three methods of `iTermVariables.m` are file-local, and every Swift caller of the changed parameters passes a non-optional value. Two reasons above were incomplete. `invocation` also goes to `-[iTermScriptFunctionCall performFunctionCallFromInvocation:...]`, claimed nonnull in `iTermScriptFunctionCall+Private.h` (it only formats and forwards it), and to the non-optional Swift `evaluate(invocation:)` of `Subexpression` and `IndirectValue`, where nil arrives as `""`; the private header was left, since it is visible to Swift through the bridging header. `-initWithString:` stores nil in `_object`, behind getters claimed nonnull: `-string` asserts and so aborts, as does `-description`, which is logged in `bugs.md`; the parameter is nullable because the app does pass nil |
| N8 status bar and composer | `sources/StatusBar/...` (13 files), `sources/Composer/iTermMinimalComposerViewController.h`, `sources/Categories/NSImageView+iTerm.h` | 17 | 0 in the database (nine returns, none with a Swift reader found); three protocols change (the two composer delegates and the status bar component delegate), so check Swift conformers | annotate. **Done** (unit `nullability-n8-status-bar-composer`): all 17 claims made nullable, plus the `instancetype` return of `+[iTermCPUUtilization instanceForSessionID:]` and the `scope` parameter of the `iTermStatusBarComponent` protocol's `-initWithConfiguration:scope:`, which every implementation already declares nullable and which the file-local `componentsArrayFromDictionary:scope:` passes its nil scope to. The `-[PTYSession statusBarBackgroundColor]` claim is in `iTermStatusBarViewControllerDelegate` (`iTermStatusBarViewController.h:31`), not in `iTermStatusBarComponent.h:159`, which was already nullable. Four `-statusBarBackgroundColor` overrides in implementation files under `NS_ASSUME_NONNULL` (text, attributed text, fixed spacer and function call components) are annotated too, since an implicit nonnull there conflicts with the nullable property and does not compile. Swift sites: the two Swift conformers of the minimal composer delegate (`CockpitWindowController.swift`, `ModernTests/CockpitComposerSendEachTests.swift`) take optional parameters; both ignore them and return `false`, as before when Objective-C passed nil. `Conductor.swift` sets the publisher through optional chaining; its session ID is non-nil, so the instance is too |
| N9 session, profile switching, triggers | `sources/PTYSession/PTYSession.h`, `iTermNaggingController.h`, `sources/AutomaticProfileSwitching/iTermAutomaticProfileSwitcher.h`, `.m`, `sources/TerminalView/iTermRightGutterPanelRegistry.h` (and its block type), `sources/TryingTooHard/iTermPrintGuard.h`, `sources/Triggers/PTYTriggerEvaluator.h`, `Trigger.m` (and `Trigger.h`'s `contentRegex`) | 16 | 0 for the rows; the gutter block type change reaches the two Swift providers (`ClippingsGutterPanel.swift:148`, `ChatViewController.swift:4070`), which ignore the argument and keep compiling | annotate. **Done** (unit `nullability-n9-session-triggers`): 15 of the 16 claims made nullable, plus the two outward claims found beside them (the gutter block type's `profile` and `Trigger.contentRegex`). Not made: `-[iTermNaggingController offerToFixSessionWithBrokenArrangementProfileIn:guid:]` (`iTermNaggingController.h:120`), because its reason is wrong for `arrangementName`: `+[WindowArrangements arrangementWithName:nil]` returns the default arrangement, and accepting the offer then reaches `+[WindowArrangements setArrangement:withName:nil]`, which raises (`bugs.md`); the claim stays until that is fixed. Swift sites: the two gutter width providers ignore the profile and compile unchanged; `ModernTests/AutomaticProfileSwitcherTests.swift`'s fake delegate now returns an optional, since a non-optional result was a nearly-matches warning; `Trigger.contentRegex` has no Swift reader in the app, and a test reading it would have seen `""` for a trigger saved without one |
| N10 text view events and views | `sources/TerminalView/PTYTextView+ARC.h`, `PTYMouseHandler.h`, `SessionView.h`, `iTermFakeWindowTitleLabel.h`, `iTermImageView.h`, `sources/ContextMenu/iTermTextViewContextMenuHelper.h` | 11 | 0 in the database (two returns) | annotate. **Done** (unit `nullability-n10-text-view-events`): all 11 claims made nullable. The only one Swift uses is `addSubviewBelowFindView:` (the right gutter controller, the chat mention picker, two workgroup overlays and two tests), always with a non-optional view, so every call compiles unchanged; the two protocols have one Objective-C conformer each (`PTYTextView`), in files outside `NS_ASSUME_NONNULL`. `-addSubviewBelowFindView:` tolerates nil only because AppKit's `-addSubview:` (declared nonnull) happens to ignore it; `iTermFakeWindowTitleLabel.windowIcon` is a further false outward claim, not visible to Swift, left for a later unit |
| N11 categories and data structures | `sources/Categories/NSColor+iTerm.h`, `NSStringITerm.h`, `NSTableView+iTerm.h`, `NSURL+iTerm.m`, `sources/DataStructuresAlgorithms/IntervalTree.h`, `iTermOrderedDictionary.h`, `sources/Keyboard/iTermKeyMappings.h`, `iTermKeystroke.h` | 14 | 0 in the database (two returns: `firstComposedCharacter:`, `keyMappingsForProfile:`) | annotate. **Done** (unit `nullability-n11-categories-data-structures`): all 14 claims made nullable. No Swift line failed to compile: every changed parameter is inward, and no Swift code reads `firstComposedCharacter:` or `keyMappingsForProfile:`; `NSURL+iTerm.m`'s `URLWithUserSuppliedStringImpl:` is file-local and its public caller was already nullable |
| N12 infrastructure, external attributes | `sources/ExternalSessionState/iTermExternalAttributeIndex.h`, `.m`, `sources/FileTransfer/TransferrableFile.h`, `sources/Infrastructure/iTermWarning.h`, `sources/InputBroadcasting/iTermBroadcastInputHelper.h`, `sources/ScreenChar/ScreenCharArray.h` | 8 | 0 in the database (two returns: `warningHandler`, `domainContainingSession:`) | annotate. **Done** (unit `nullability-n12-infrastructure`): all 8 claims made nullable, plus the `instancetype` return of `+[iTermUniformExternalAttributes withAttribute:]`. That return is the only Swift fallout: `ModernTests/LineBlockTests.swift` maps with `flatMap` instead of `map`, and four tests in `ModernTests/iTermExternalAttributeIndexEqualityTests.swift` unwrap it with `XCTUnwrap`; none of them passes nil, so they test the same thing. The changes are to declarations only; no code read per cell by the renderer changed (whether this unit counts as part of H1 was not confirmed with the orchestrator) |
| N13 tab bar and pidinfo | `ThirdParty/PSMTabBarControl/source/PSMMinimalTabStyle.h`, `PSMTabStyle.h`, `PSMYosemiteTabStyle.h`, `pidinfo/iTermGitClient.m` | 4 | 0 (one Swift declaration shares `closeButtonRectForTabCell:`; check it is not a `PSMTabStyle` conformer) | annotate. **Partly done** (unit `nullability-n13-pidinfo`): the `pidinfo/iTermGitClient.m` row is made by declaring `-[iTermGitClient repo]` nullable in `pidinfo/iTermGitClient.h`, which removes the `_Nonnull` from its synthesized ivar; its readers already test it. The three `ThirdParty/PSMTabBarControl` rows wait for the owner: the tab bar is frozen while a large change to it is in progress elsewhere (owner queue Q12) |
| H1 Metal renderer (owner first) | `sources/MetalRenderer/...` (9 files) | 28 | 0 in the database; the `iTermMetalViewDelegate` Swift protocol parameter becomes optional, and its Objective-C conformer `-[iTermMetalDriver metalView:drawableSizeWillChange:]` (`iTermMetalDriver.m:410`, explicit `nonnull`) must change in the same commit or the compiler warns of a nullability mismatch | annotate, hot path. **Done** (unit `nullability-h1-metal`, owner approval of 2026-11-20 for hot-path files): all 28 claims made nullable, with the implementations under `NS_ASSUME_NONNULL` annotated to match and the conformer changed. The renderer, glue and per-frame state headers are not visible to Swift; the one Swift change is the protocol parameter, whose two Swift callers pass `self`. No Swift hot-path site gained an unwrap, and the generated Objective-C code is identical |
| H2 screen, line buffer, metadata (owner first) | `sources/VT100Screen/...`, `sources/LineBuffer/...`, `sources/VT100/iTermMetadata.h` (9 files) | 14 | 0 in the database (five returns: `-[VT100Screen namedMarks]`, `screenSSHLocation`, `bidiInfoForLine:`, `lastBlock`, `firstBlock`) | annotate, hot path. **Done** (unit `nullability-h2-screen-linebuffer`, owner approval of 2026-11-20 for hot-path files): all 14 claims made nullable. No app Swift code reads the five returns or passes an implicitly unwrapped value to the ten parameters; the two Swift test conformers of `VT100ScreenDelegate` (`VT100ScreenTests.swift`, `PerformanceTests.swift`) now return `String?`. No Swift hot-path site gained an unwrap, and the generated Objective-C code is identical |
| H3 drawing (owner first) | `sources/Drawing/iTermSharedImageStore.h`, `iTermTextDrawingHelperDelegate.h`, `BidiDisplayInfo.swift` | 4 | 0 in the database | annotate, hot path. **Done** (unit `nullability-h3-drawing`, owner approval of 2026-11-20 for hot-path files): the 4 claims and the `image` property found beside them made nullable. No Swift line failed to compile and no Swift code reads the changed outward positions; the Swift conformer `TextClipDrawing` now declares an optional return (it still always returns a color), and `iTermBidiDisplayInfo.init(_:)` returns nil for a nil dictionary at a guard, which is what the hidden nil gave before. No Swift hot-path site gained an unwrap |

N11 and N12 together are the split of what would otherwise be a 22-claim
miscellany; N12 is listed separately because `iTermExternalAttributeIndex` is
read per cell by the renderer, and its author should confirm with the
orchestrator that it is not treated as part of H1.

The claims in each unit are the TSV rows whose `header` is in the unit's
files and whose verdict is `annotation-wrong-make-nullable`; the
"outward claims found beside inward rows" of section 4 are added to the unit
that holds their header.

**N2 alternative.** `-[PreferencePanel allSettings]` returns nil only by
messaging a nil `_tabView` before the window's nib loads
(`PreferencePanel.m:877`); with the nib loaded, `flatMapWithBlock:` returns
an array. The Swift readers already expect an empty array in that case
(`ProfileBoolSettingCatalog.swift:34-36`: "allSettings() would be empty").
So the method can keep its nonnull claim and return
`[_tabView.tabViewItems flatMapWithBlock:...] ?: @[]`, a `fix` commit with a
test, with zero Swift fallout and the same behavior for every Swift reader
(the bridge already gives them `[]`). Recommended: the alternative, because
the claim then states what callers already rely on.

**N3 alternative.** `suggestionsForString:` is a protocol method with two
implementations; it returns nil when the parser yields nothing, which by
[nullability.md §5](nullability.md) makes the nullable claim correct. But its
only Swift readers are 89 test lines. The cheaper route is a `fix` commit
that returns `@[]` instead of nil in both implementations, with a test, and
keeps the claim nonnull, provided the Objective-C callers
(`iTermFunctionCallSuggester.m:716` and `:838`,
`iTermFunctionCallTextFieldDelegate.m:141`) treat nil and an empty array
alike, which the author must confirm first. The
orchestrator chooses; the default is the alternative, because it changes no
test.

**Order and dependencies.** N1 first: it is the model case, it holds the
most-used claims, and it fixes the dangerous outward claim Swift reads.
N9 depends on nothing but shares `PTYSession.h` with feature work, so it
should not sit in review long. N7 and N4 remove all five entries of
`tools/swift_migration/sanitizer_nullability_suppressions.txt` (three
`iTermVariables`, two `iTermScriptsMenuController`), each in the same
commit as the claims that make its entry unnecessary, so the nullability
gate starts enforcing them. The rest can run in any order.

**Size.** The largest non-hot unit has 17 claims in 15 small files (N8);
every inward claim is a one-word change with no call-site fallout, so each
unit is one sitting even at that size. If a reviewer finds a unit too
broad, split it by header.

## 8. Questions for the owner

- Whether a `PTYSession` may evaluate profile-dependent configuration, its
  title and automatic profile switching before `setProfile:` has run (the
  source of most argument reports, section 4), or whether that ordering is
  itself the bug. The verdicts do not depend on the answer: every callee
  tolerates nil today.
- Approval to start H1 to H3, which touch hot-path headers. They change no
  Objective-C behavior, only claims and the Swift that reads them.

## 9. Regenerating

The verdict and reason columns are judgments and are kept by hand: a
regeneration must carry them over by `header`, `line` and `position` and
re-read any row whose declaration changed. The mechanical columns come from:

1. `tools/swift_migration/sanitizer_tests.sh nullability --collect --parallel`
   (a build-lane job), then `tools/swift_migration/sanitizer_summary.py`
   with `--json` over the run's reports, which gives each location with its
   kind, count, callers, tests and the declaration the runtime names.
2. Grouping locations by the declaration and position the runtime names,
   with the declaration looked up in the code database's `objc_method` and
   `swift_objc_decl` tables (header declaration by the method's USR, Swift
   declaration by selector).
3. For each `annotation-wrong-make-nullable` row, `codedb.py swiftrefs
   SELECTOR` and `codedb.py sends SELECTOR` on a copy of
   `tmp/codedb/codedb.sqlite` (never `codedb.py update` on the shared file),
   counting the references whose referenced class or receiver is the
   declaring class, its protocol or `id`, and recording "unknown" when the
   query exits 3.

The scripts that did steps 2 and 3 for this file were scratch work in
`tmp/phase0-sanitizer-ledgers/scripts/` and are not committed; making them a
tool is a separate `tool` unit if regeneration becomes routine.

## 10. Limits

- The sanitizer sees only code the tests run, and the 684 skipped tests
  (on-screen, live harnesses) are a real gap; a claim not in the table is not
  thereby proven.
- An argument report fires at the call site even when the receiver is nil
  and the callee never runs; the reasons say where that applies
  (`SessionView` rows, `screenRestoreState:`).
- A `nonnull` method called on a nil receiver yields nil without a report
  ([nullability.md §7](nullability.md)), so outward claims can be wrong in
  ways this run could not see.
- Swift fallout counts come from an incomplete database (section 6).
