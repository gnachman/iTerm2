# Reflective-site registry

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) and [hidden-callers.md](hidden-callers.md) first.

## 1. What this is and how to use it

A reflective site is a place that reaches a method, class or key by a name
that the compiler does not check: `NSSelectorFromString`, the
`performSelector:` family, `respondsToSelector:`, `NSClassFromString`,
key-value coding and observing with a string, `NSInvocation`, the runtime
functions, and target-action with a selector held in a variable. When the
name is computed at run time (argument kind `dynamic` in the code database),
no query can say which methods the site reaches. This registry is the answer
for those sites, written by reading the code: for each one, the set of names
that can reach it at run time.

**How a porting agent uses it.** Before porting a method, property or class,
search this file for its selector or class name, and for any prefix pattern
in "Names that must be preserved" that matches it. If a registered site can
reach it by name:

- keep the runtime name exactly what it is today. For a method, that means
  `@objc(selector)` with the Objective-C selector. For a class, the invariant
  is that its runtime name (what `NSStringFromClass` returns, and what an
  archive records) does not change: for an Objective-C class being ported,
  that means `@objc(ClassName)` on the Swift class, so that its runtime name
  is not module-qualified; for a class that is already Swift, it means
  leaving its declaration's naming alone. A Swift class without
  `@objc(Name)` already has a module-qualified runtime name (for example
  `iTerm2SharedARC.PortholeMark`); that is the name stored in saved data,
  and adding `@objc(Name)` would change it and stop old data from loading.
  The "Runtime name" column of the names table gives the name to keep for
  every class, and section 6 lists the Swift classes. A class compiled into
  more than one target (the XPC classes of section 6) must have the same
  runtime name in each;
- keep what the site depends on beyond the name: the type encoding where the
  site reads it (`iTermReflection`), the `@dynamic` attribute where the site
  enumerates properties (`VT100MutableScreenConfiguration`), key-value
  observability where the site observes the key;
- put a comment at the method or class naming the site that reaches it
  ([hidden-callers.md section 5](hidden-callers.md)), for example
  `// Reached by name: TmuxGateway.m in -[TmuxGateway currentCommandSelector] (reflective-sites.md).`, so that the
  next reader sees why the name is fixed;
- add a test that pins the name, for example by sending it with
  `NSSelectorFromString` or looking the class up with `NSClassFromString` and
  asserting the result, so that a later rename fails a test instead of
  silently changing behavior;
- for an OPEN-EXTERNAL site, also keep accepting names that older versions
  wrote, even after the class is renamed in Swift.

A method that no registered site can reach can still be reached by the
mechanisms this registry does not cover; see section 9 and the entry-point
census ([phase0.md section 2](phase0.md)).

Macros are not registered here. A macro that sends a message, defines a
method or class, or builds a name by pasting or stringifying is read in
`docs/swift-migration/macro-classification.tsv`, one row per macro with
what it expands to and reaches, checked by `codedb.py macrolint`; what is
surprising about a macro and will matter when porting is also commented at
its definition ([decisions.md](decisions.md), 2026-11-20). A name that a
macro builds and that a site in this registry looks up (the
`iTermAdvancedSettingsModel` prefixes, for example) is still listed here.

**How it was built.** The list of sites is the `reflective_call` table of
the code database (`tools/swift_migration/codedb/`), rows with
`argument_kind = 'dynamic'` whose file is in the migration's scope
(`in_migration_scope = 1`: `sources/`, `ThirdParty/PSMTabBarControl/`,
`SignedArchive/`, `pidinfo/`, `iTerm2SandboxedWorker/`, `ShellLauncher/`,
`ColorPicker/`, `SearchableComboListView/`, `BetterFontPicker/`). Each row
was then read in the current source, and each computed value was followed
back through its callers. A site whose argument is a parameter of a helper
was resolved from every caller of the helper; callers that pass a computed
selector are entries of their own (section 4). Objective-C callers come from
the database's `send` rows for the helper's selector (with the `selector_ref`
rows on the same lines for `@selector` arguments), not from reading, and C
functions from `git grep`.

**How Swift callers were found.** Swift imports an Objective-C method under a
different name, so a search for the Objective-C spelling misses Swift
callers. They were found with the database's Swift tables: `swift_ref` rows
of kind `call` or `init` whose `selector` is the helper's Objective-C
selector, with the `selector-expr` rows on the same lines giving the
`#selector` argument; each hit was read in the current source. Where the
helper is Swift, its Swift base name was also searched with `git grep`.

**Names persisted or sent between processes by the frameworks** (section 6:
window restoration, XPC, keyed archives) were found by `git grep` for the
APIs named at the start of each part of that section, Objective-C and Swift,
every hit read.

**Selector and class names used as strings** (section 5) were found by
`git grep` for `NSStringFromSelector`, `sel_getName`, `NSStringFromClass`,
`class_getName` and `object_getClassName` in the scope directories, every hit
read. Classes that exist only to be found by name were searched for as empty
`@interface`/`@implementation` pairs, `@compatibility_alias`,
`setClass:forClassName:` and `setClassName:forClass:`; the only compatibility
class is `GrowlTrigger` (the Trigger.m in +[Trigger triggerFromUntrustedDict:] entry; the other 28 empty pairs are
xib custom classes, Core Data classes, Metal transient states, or classes used
by symbol, such as `iTermModifyOtherKeysMapper2`), and the only class
substitution is `PreferencePanel.m` in -[PreferencePanel bigSurSearchFieldToolbarItem] (section 5).

**What it reflects.** Written on 2026-11-20 against the commit “Add a sanitized stored-state corpus and the tools that make and check it”; the
caller lists, Swift callers and section 5 were rechecked against commit
the commit “Add the sanitizer test and app build modes for the Swift migration”. The
database rows come from the capture of 2026-11-19 (the database was stale
for unrelated reasons, 519 of 1079 units not current; the dynamic rows were
checked one by one against the current source). Line numbers are current at
the commit “Add a sanitized stored-state corpus and the tools that make and check it”; where they differ from the database row the entry says so (two
rows in `iTermUserDefaultsObserver.m` moved by one line). Every row was
found in the current source; none is missing.

**How to regenerate the list of sites.** Either
`python3 tools/swift_migration/codedb/codedb.py reflective` (dynamic rows
only, the default), or, on the database file:

```sql
SELECT DISTINCT file, line, col, function_or_selector, argument_text, enclosing_name
FROM reflective_call
WHERE argument_kind = 'dynamic' AND in_migration_scope = 1
ORDER BY file, line;
```

A row that is not in this file is a new site and must be read and added. A
row is identified here by file, enclosing function or method, call and
argument; lines drift.

**Classifications.**

- **CLOSED**: the set of names is finite and known; the entry lists them and
  where they come from.
- **OPEN-INTERNAL**: the names come from data the app itself builds, not
  enumerable by reading this site; the entry says what would enumerate them.
- **OPEN-EXTERNAL**: the names come from outside the app (saved state,
  preferences, scripts, pasteboard, key bindings); the entry names the input
  and the check between input and call.
- **GENERIC**: a forwarding or utility helper; the real sites are its
  callers, listed in the entry. Static callers need nothing more; a caller
  that passes a computed name is an entry in section 4.
- **NOT-REFLECTIVE**: an extractor false positive: a setter named
  `setAction:` or `setSelector:` on a property that is not a selector (an
  enum, a block, an object). Recorded so that it is known someone looked.
- **UNRESOLVED**: not resolved by reading. There are none.

## 2. Summary

### Database rows by mechanism and classification

| Mechanism | CLOSED | GENERIC | OPEN-INTERNAL | OPEN-EXTERNAL | NOT-REFLECTIVE | UNRESOLVED | Total |
|---|---|---|---|---|---|---|---|
| Selector from a string | 11 | 0 | 0 | 0 | 0 | 0 | 11 |
| Calling by selector | 12 | 13 | 1 | 2 | 0 | 0 | 28 |
| Responds-to checks and forwarding | 10 | 14 | 0 | 5 | 0 | 0 | 29 |
| Target-action (menu items and controls) | 10 | 16 | 0 | 0 | 13 | 0 | 39 |
| Class from a string or made at run time | 5 | 0 | 0 | 6 | 0 | 0 | 11 |
| Key-value coding, observing, bindings and sort keys | 9 | 0 | 0 | 5 | 0 | 0 | 14 |
| Runtime method and property functions | 23 | 8 | 0 | 0 | 0 | 0 | 31 |
| **Total** | **80** | **51** | **1** | **18** | **13** | **0** | **163** |

Callers of generic helpers (section 4, not database rows): 12 sites; CLOSED 12, GENERIC 0.

Selector and class names used as data (section 5, not database rows): 22 entries; CLOSED 18, GENERIC 1, OPEN-EXTERNAL 2, NOT-REFLECTIVE 1.

### Names that must be preserved

The rule: this table is the union of the `Names:` lines of every entry in sections 3, 4, 5 and 6 and of the Swift sites in section 9, and `tools/swift_migration/reflective_registry.py check` checks that it is exactly that union (it also checks that every dynamic reflective call of the database has a bullet in section 3 and no bullet is stale, the bullet lines, and the summary table; it does not check the functions the prose cites, that each name resolves in the database, or the backticked-selector rule below, which the uncommitted verifier of 2026-11-20 checked). An entry's `Names:` line lists every name the entry can reach: every selector, class, key-value coding key or method-name pattern, including names written as `@selector` literals in tables and arrays, names of SDK and AppKit-private classes and methods (marked in the Note column; a port does not rename them, but a port of the site must keep reaching them), class names that are written to stored state (marked "persisted by name"; including names that AppKit persists, such as window restoration classes, and classes allowed when reading archives), and class names and selectors that cross a process boundary (XPC and pasteboard archives, marked). Three groups are deliberately not listed by name, because a binding test or the census owns them, and the entries that reach them say so: the main-menu action selectors (reached by the menu-dispatch entries), the `window` keys of `iTerm2.sdef` (reached through `iTermScriptingWindow`), and user-defaults keys (not methods). Names that only tests pass are named in the entry text, not here. The rule also requires every backticked selector in an entry's text to be either one of its names or explicitly marked as mentioned but not reached (the helper's own selector, a caller's method).

A selector is written as the runtime spells it; `Class.key` is a key-value coding key of that class (its getter, and setter when settable); `Class +prefix*` is every class method of that class whose selector starts with the prefix; `prefix*` alone is every selector with that prefix, on any class. Sites are given as the file and function of the entry's first database row or site. Outside the bullets, the registry cites a place by its file and function (or macro, class or declaration), not by line, because line numbers in prose go stale with every edit above them and no tool regenerates them. The bullets keep `FILE:LINE`: those of section 3 are kept current by `reflective_registry.py update`; those of sections 4 to 9 are read by `entry_points.py` in that form, were brought to the tree of 2026-11-21, and are not regenerated (most of them also name their function). "Resolves" says how the name was found in the database copy. "Runtime name" is filled for every class: the name `NSStringFromClass` returns today and the one stored or looked up; it differs from the name only for Swift classes without `@objc(Name)` (section 6 says how it was determined), and those rows say not to add or change `@objc(Name)`. Where a selector name is generic (`paste:`, `setDelegate:`, `insertNewline:`, `moveDown:`, `deleteBackward:`), the Note says which classes' implementations the entry reaches.

| Name | Resolves | Runtime name | Note | Sites |
|---|---|---|---|---|
| `_crashOnException:` | not in database: SDK or AppKit-private name |  | SDK or AppKit-private | AppKit/iTermApplication.m in iTermInstallCrashOnExceptionHook |
| `_moveToDisplay:` | not in database: SDK or AppKit-private name |  | SDK or AppKit-private | Settings/MenuItemPopupView.swift in NSMenuItem.isWindowMenuItem(parent:) |
| `_NSKeyboardFocusClipView` | not in database: SDK or AppKit-private name | `_NSKeyboardFocusClipView` | SDK or AppKit-private | AppKit/iTermApplication.m in -[iTermApplication it_windowDidOrderOnScreen:] |
| `_NSThemeZoomWidgetCell` | not in database: SDK or AppKit-private name | `_NSThemeZoomWidgetCell` | SDK or AppKit-private | Categories/NSObject+iTerm.m in +[NSObject(iTerm) load] |
| `_toggleIPad:` | not in database: SDK or AppKit-private name |  | SDK or AppKit-private | Settings/MenuItemPopupView.swift in NSMenuItem.isWindowMenuItem(parent:) |
| `_updateDividerLayerForController:animated:` | selector |  | SDK or AppKit-private | Infrastructure/iTermSelectorSwizzler.m in +[iTermSelectorSwizzler permanentlySwizzleSelector:fromClass:withBlock:] |
| `_windowResizeNorthEastSouthWestCursor` | not in database: SDK or AppKit-private name |  | SDK or AppKit-private; Swift site (section 9) | FloatingPanes/iTermFloatingPaneView.swift in iTermFloatingPaneView.cursor(for:) |
| `_windowResizeNorthWestSouthEastCursor` | not in database: SDK or AppKit-private name |  | SDK or AppKit-private; Swift site (section 9) | FloatingPanes/iTermFloatingPaneView.swift in iTermFloatingPaneView.cursor(for:) |
| `actionsDidChange:` | selector |  |  | Notifications/iTermNotificationCenter.m in +[iTermBaseNotification subscribe:selector:] |
| `add:` | selector |  |  | Toolbelt/iTermToolActions.m in iTermToolActionsNewButton, Toolbelt/iTermToolSnippets.m in iTermToolSnippetsNewButton |
| `addAndCommit:` | selector |  |  | StatusBar/Components/iTermStatusBarGitComponent.m in -[iTermStatusBarGitComponent openMenuWithView:] |
| `addAnnotationWithCompletion:startX:startY:endX:endY:text:` | selector |  |  | Language/iTermBuiltInFunctions.m in -[iTermBuiltInMethod callWithArguments:connectionKey:cancellation:completion:], Language/iTermReflection.m in -[iTermReflection reflectedArguments] |
| `addDeleteClicked:` | selector |  |  | Settings/GeneralPreferencesViewController.m in -[iTermManualAIModelsPanelController makeSegmentedControlWithSegments:action:] |
| `addNote:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `addTrigger:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `adjustBottom:` | selector |  |  | Settings/iTermBadgeConfigurationWindowController.m in -[iTermBadgeConfigurationBadgeView mouseDragged:] |
| `adjustLeft:` | selector |  |  | Settings/iTermBadgeConfigurationWindowController.m in -[iTermBadgeConfigurationBadgeView mouseDragged:] |
| `adjustRight:` | selector |  |  | Settings/iTermBadgeConfigurationWindowController.m in -[iTermBadgeConfigurationBadgeView mouseDragged:] |
| `adjustTop:` | selector |  |  | Settings/iTermBadgeConfigurationWindowController.m in -[iTermBadgeConfigurationBadgeView mouseDragged:] |
| `AlertTrigger` | class | `AlertTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `AnnotateTrigger` | class | `AnnotateTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `apiAddTabToGroupWithCompletion:tab_id:group_id:` | selector |  |  | Language/iTermBuiltInFunctions.m in -[iTermBuiltInMethod callWithArguments:connectionKey:cancellation:completion:], Language/iTermReflection.m in -[iTermReflection reflectedArguments] |
| `apiCreateTabGroupWithCompletion:tab_ids:name:color:parent_group_id:` | selector |  |  | Language/iTermBuiltInFunctions.m in -[iTermBuiltInMethod callWithArguments:connectionKey:cancellation:completion:], Language/iTermReflection.m in -[iTermReflection reflectedArguments] |
| `apiMenuItem:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in +[iTermTextViewContextMenuHelper menuItemsForAPIRegistrationRequests:scope:target:action:] |
| `apiRemoveTabFromGroupWithCompletion:tab_id:` | selector |  |  | Language/iTermBuiltInFunctions.m in -[iTermBuiltInMethod callWithArguments:connectionKey:cancellation:completion:], Language/iTermReflection.m in -[iTermReflection reflectedArguments] |
| `appendRequestsForNode:toArray:` | selector |  |  | tmux/TmuxLayoutParser.m in -[TmuxLayoutParser depthFirstSearchParseTree:callingSelector:onTarget:withObject:] |
| `apply:` | selector |  |  | Toolbelt/iTermToolActions.m in iTermToolActionsNewButton, Toolbelt/iTermToolSnippets.m in iTermToolSnippetsNewButton |
| `BellTrigger` | class | `BellTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `bogusSelector` | selector |  |  | StatusBar/Components/iTermStatusBarGitComponent.m in -[iTermStatusBarGitComponent openMenuWithView:] |
| `BounceTrigger` | class | `BounceTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `bringFloatingPaneToFrontFromContextMenu:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `browse:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `browserEvalJSWithCompletion:js:connectionKey:cancellation:` | selector |  |  | Language/iTermBuiltInFunctions.m in -[iTermBuiltInMethod callWithArguments:connectionKey:cancellation:completion:], Language/iTermReflection.m in -[iTermReflection reflectedArguments] |
| `browserSetToolbarHiddenWithCompletion:hidden:` | selector |  |  | Language/iTermBuiltInFunctions.m in -[iTermBuiltInMethod callWithArguments:connectionKey:cancellation:completion:], Language/iTermReflection.m in -[iTermReflection reflectedArguments] |
| `buriedPanesDidOpen:` | selector |  |  | tmux/TmuxWindowOpener.m in -[TmuxWindowOpener finishErroneously], tmux/TmuxWindowOpener.m in -[TmuxWindowOpener requestDidComplete], tmux/TmuxWindowOpener.m in -[TmuxWindowOpener requestDidComplete] |
| `bury:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `buttonPressed:` | selector |  |  | TIps/iTermTipCardActionButton.m in -[iTermTipCardActionButton accessibilityPerformPress], TIps/iTermTipCardActionButton.m in -[iTermTipCardActionButton mouseUp:] |
| `cancelFindExistingFileRequest:reply:` | selector |  | XPC wire format (selector sent by name) | SlowOperationXPC/iTermSlowOperationGateway.m in -[iTermSlowOperationGateway connect] |
| `cancelNewAccount:` | selector |  |  | PasswordManager/iTermPasswordManagerWindowController.m in iTermPWMakePushButton |
| `CaptureTrigger` | class | `CaptureTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `carbonHotkeyPressed:siblings:` | selector |  |  | Hotkey/iTermCarbonHotKeyController.m in -[iTermCarbonHotKeyController handleEvent:] |
| `checkForUTF8Response:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `checkIfDirectoryExists:withReply:` | selector |  | XPC wire format (selector sent by name) | SlowOperationXPC/iTermSlowOperationGateway.m in -[iTermSlowOperationGateway connect] |
| `checkIfExecutableRegularFile:searchPaths:withReply:` | selector |  | XPC wire format (selector sent by name) | SlowOperationXPC/iTermSlowOperationGateway.m in -[iTermSlowOperationGateway connect] |
| `checkout:` | selector |  |  | StatusBar/Components/iTermStatusBarGitComponent.m in -[iTermStatusBarGitComponent openMenuWithView:] |
| `clearTextViewBuffer:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `closeCurrentSession:` | selector |  |  | Companion/CompanionWizardWindowController.swift in CompanionWizardWindowController.validateMenuItem(_:) |
| `closeTabGroup:` | selector |  |  | TerminalView/PseudoTerminal.m in -[PseudoTerminal reconcileTabGroupDefinitionForTab:] |
| `closeTabsOutsideGroup:` | selector |  |  | TerminalView/PseudoTerminal.m in -[PseudoTerminal reconcileTabGroupDefinitionForTab:] |
| `closeTabsRightOfGroup:` | selector |  |  | TerminalView/PseudoTerminal.m in -[PseudoTerminal reconcileTabGroupDefinitionForTab:] |
| `closeTextViewSession:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `collapseTabGroupFromMenu:` | selector |  |  | TerminalView/PseudoTerminal.m in -[PseudoTerminal reconcileTabGroupDefinitionForTab:] |
| `commit:` | selector |  |  | StatusBar/Components/iTermStatusBarGitComponent.m in -[iTermStatusBarGitComponent openMenuWithView:] |
| `configureComponent:` | selector |  |  | StatusBar/Setup/iTermStatusBarSetupDestinationCollectionViewController.m in -[iTermStatusBarSetupDestinationCollectionViewController configureStatusBarComponentWithIdentifier:] |
| `contextMenuAction*` | 8 selectors with prefix |  | selector prefix pattern (PTYTextView.m in -[PTYTextView validateMenuItem:]) | TerminalView/PTYTextView.m in -[PTYTextView validateMenuItem:] |
| `contextMenuActionCopy:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper validateMenuItem:], ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper smartSelectionActionSelectorDictionary], ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper selectorForSmartSelectionAction:], SemanticHistory/iTermURLActionFactory.m in -[iTermURLActionFactory computeURLActionForSmartSelection:], SemanticHistory/iTermURLActionHelper.m in -[iTermURLActionHelper finishOpeningTargetWithEvent:coord:inBackground:style:action:generation:smartSelectionActionsOnly:], TerminalView/PTYTextView.m in -[PTYTextView validateMenuItem:] |
| `contextMenuActionOpenFile:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper validateMenuItem:], ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper smartSelectionActionSelectorDictionary], ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper selectorForSmartSelectionAction:], SemanticHistory/iTermURLActionFactory.m in -[iTermURLActionFactory computeURLActionForSmartSelection:], SemanticHistory/iTermURLActionHelper.m in -[iTermURLActionHelper finishOpeningTargetWithEvent:coord:inBackground:style:action:generation:smartSelectionActionsOnly:], TerminalView/PTYTextView.m in -[PTYTextView validateMenuItem:] |
| `contextMenuActionOpenURL:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper validateMenuItem:], ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper smartSelectionActionSelectorDictionary], ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper selectorForSmartSelectionAction:], SemanticHistory/iTermURLActionFactory.m in -[iTermURLActionFactory computeURLActionForSmartSelection:], SemanticHistory/iTermURLActionHelper.m in -[iTermURLActionHelper finishOpeningTargetWithEvent:coord:inBackground:style:action:generation:smartSelectionActionsOnly:], TerminalView/PTYTextView.m in -[PTYTextView validateMenuItem:] |
| `contextMenuActionRunCommand:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper validateMenuItem:], ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper smartSelectionActionSelectorDictionary], ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper selectorForSmartSelectionAction:], SemanticHistory/iTermURLActionFactory.m in -[iTermURLActionFactory computeURLActionForSmartSelection:], SemanticHistory/iTermURLActionHelper.m in -[iTermURLActionHelper finishOpeningTargetWithEvent:coord:inBackground:style:action:generation:smartSelectionActionsOnly:], TerminalView/PTYTextView.m in -[PTYTextView validateMenuItem:] |
| `contextMenuActionRunCommandInWindow:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper validateMenuItem:], ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper smartSelectionActionSelectorDictionary], ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper selectorForSmartSelectionAction:], SemanticHistory/iTermURLActionFactory.m in -[iTermURLActionFactory computeURLActionForSmartSelection:], SemanticHistory/iTermURLActionHelper.m in -[iTermURLActionHelper finishOpeningTargetWithEvent:coord:inBackground:style:action:generation:smartSelectionActionsOnly:], TerminalView/PTYTextView.m in -[PTYTextView validateMenuItem:] |
| `contextMenuActionRunCoprocess:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper validateMenuItem:], ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper smartSelectionActionSelectorDictionary], ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper selectorForSmartSelectionAction:], SemanticHistory/iTermURLActionFactory.m in -[iTermURLActionFactory computeURLActionForSmartSelection:], SemanticHistory/iTermURLActionHelper.m in -[iTermURLActionHelper finishOpeningTargetWithEvent:coord:inBackground:style:action:generation:smartSelectionActionsOnly:], TerminalView/PTYTextView.m in -[PTYTextView validateMenuItem:] |
| `contextMenuActionSendText:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper validateMenuItem:], ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper smartSelectionActionSelectorDictionary], ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper selectorForSmartSelectionAction:], SemanticHistory/iTermURLActionFactory.m in -[iTermURLActionFactory computeURLActionForSmartSelection:], SemanticHistory/iTermURLActionHelper.m in -[iTermURLActionHelper finishOpeningTargetWithEvent:coord:inBackground:style:action:generation:smartSelectionActionsOnly:], TerminalView/PTYTextView.m in -[PTYTextView validateMenuItem:] |
| `CoprocessTrigger` | class | `CoprocessTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `copy:` | selector |  | SDK or AppKit-private | PTYSession/PTYSession.m in -[PTYSession composerManagerHandleKeyDown:] |
| `copyData:` | selector |  |  | ContextMenu/iTermContextMenuUtilities.m in +[iTermContextMenuUtilities addMenuItemForBase64Encoded:menu:index:selector:target:] |
| `copyImage:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:], ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper smartSelectionActionSelectorDictionary] |
| `copySelection:` | selector |  |  | Toolbelt/ToolPasteHistory.m in -[ToolPasteHistory validateMenuItem:] |
| `copyString:` | selector |  |  | ContextMenu/iTermContextMenuUtilities.m in +[iTermContextMenuUtilities addMenuItemForBase64Encoded:menu:index:selector:target:] |
| `copyWithControlSequences:` | selector |  |  | PTYSession/PTYSession.m in -[PTYSession composerManagerHandleKeyDown:] |
| `copyWithStyles:` | selector |  |  | PTYSession/PTYSession.m in -[PTYSession composerManagerHandleKeyDown:] |
| `debug` | selector |  |  | StatusBar/Components/iTermStatusBarGitComponent.m in -[iTermStatusBarGitComponent openMenuWithView:] |
| `decodeImageFromData:withReply:` | selector |  | XPC wire format (selector sent by name) | XPC/iTermSandboxedWorkerClient.m in +[iTermSandboxedWorkerClient connection] |
| `decodeImageFromSixelData:withReply:` | selector |  | XPC wire format (selector sent by name) | XPC/iTermSandboxedWorkerClient.m in +[iTermSandboxedWorkerClient connection] |
| `decorateWindowPane:` | selector |  |  | tmux/TmuxLayoutParser.m in -[TmuxLayoutParser depthFirstSearchParseTree:callingSelector:onTarget:withObject:] |
| `deleteBackward:` | selector |  | SDK or AppKit-private; defined on: `iTermStatusBarSetupDestinationCollectionViewController`, the collection view's delegate | StatusBar/Setup/iTermStatusBarSetupDestinationCollectionViewController.m in -[iTermStatusBarSetupDestinationCollectionView doCommandBySelector:] |
| `deleteColorPreset:` | selector |  |  | Settings/ProfilesColorsPreferencesViewController.m in -[ProfilesColorsPreferencesViewController addPresetItemWithTitle:action:] |
| `didChangeWhetherPaneFloats:request:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `didFetch:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `didFetchDefaultTerminal:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `didFetchNow:completion:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `didFetchTmuxPid:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `didGetCurrentWindow:beforeSelecting:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `didListClients:completion:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `didListPanes:forBuriedPanes:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `didListWindows:forSession:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxController.m in -[TmuxController didListWindows:userData:] |
| `didListWindows:userData:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `didListWindowsSubsequentToSettingLayout:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `didLoadServerIdentity:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `didLoadTmuxClientName:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `didMakeFloatingPane:completion:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `didPause:panes:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `didSelectWindow:selection:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `didSetLayout:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `didSetLayoutWithMovedDivider:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `didSplit:state:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `didSubscribe:handleID:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `didSwapWindows:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `dismissByKeyboard:` | selector |  |  | Hotkey/iTermCarbonHotKeyController.m in -[iTermCarbonHotKeyController handleEvent:] |
| `dockFloatingPaneFromContextMenu:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `downloadWithSCP:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `dumpHistoryResponse:paneAndAlternate:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `dumpStateResponse:pane:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `duplicateTabGroup:` | selector |  |  | TerminalView/PseudoTerminal.m in -[PseudoTerminal reconcileTabGroupDefinitionForTab:] |
| `edit:` | selector |  |  | Toolbelt/iTermToolActions.m in iTermToolActionsNewButton, Toolbelt/iTermToolSnippets.m in iTermToolSnippetsNewButton |
| `editControlClicked:` | selector |  |  | Settings/GeneralPreferencesViewController.m in -[iTermManualAIModelsPanelController makeSegmentedControlWithSegments:action:] |
| `editTextViewSession:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `effectiveAppearance` | not in database: SDK or AppKit-private name |  | SDK or AppKit-private | Language/iTermGlobalScopeController.m in -[iTermGlobalScopeControllerModernImpl init] |
| `executeShellCommand:args:dir:env:reply:` | selector |  | XPC wire format (selector sent by name) | SlowOperationXPC/iTermSlowOperationGateway.m in -[iTermSlowOperationGateway connect] |
| `expandTabGroupFromMenu:` | selector |  |  | TerminalView/PseudoTerminal.m in -[PseudoTerminal reconcileTabGroupDefinitionForTab:] |
| `exportColorPreset:` | selector |  |  | Settings/ProfilesColorsPreferencesViewController.m in -[ProfilesColorsPreferencesViewController addPresetItemWithTitle:action:] |
| `fetchDirectoryListingOfPath:completion:` | selector |  | XPC wire format (selector sent by name) | SlowOperationXPC/iTermSlowOperationGateway.m in -[iTermSlowOperationGateway connect] |
| `fetchRecentBranchesAt:count:completion:` | selector |  | XPC wire format (selector sent by name) | SlowOperationXPC/iTermSlowOperationGateway.m in -[iTermSlowOperationGateway connect] |
| `fetchTimeOffsetWithCompletion:` | selector |  |  | Language/iTermBuiltInFunctions.m in -[iTermBuiltInMethod callWithArguments:connectionKey:cancellation:completion:], Language/iTermReflection.m in -[iTermReflection reflectedArguments] |
| `fetchUserShellWithReply:` | selector |  | XPC wire format (selector sent by name) | SlowOperationXPC/iTermSlowOperationGateway.m in -[iTermSlowOperationGateway connect] |
| `findCompletionsWithPrefix:inDirectories:pwd:maxCount:executable:withReply:` | selector |  | XPC wire format (selector sent by name) | SlowOperationXPC/iTermSlowOperationGateway.m in -[iTermSlowOperationGateway connect] |
| `findExistingFileWithPrefix:suffix:workingDirectory:trimWhitespace:pathsToIgnore:allowNetworkMounts:reqid:reply:` | selector |  | XPC wire format (selector sent by name) | SlowOperationXPC/iTermSlowOperationGateway.m in -[iTermSlowOperationGateway connect] |
| `getAffinitiesResponse:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `getBuriedIndexesResponse:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `getCoprocessWithCompletion:` | selector |  |  | Language/iTermBuiltInFunctions.m in -[iTermBuiltInMethod callWithArguments:connectionKey:cancellation:completion:], Language/iTermReflection.m in -[iTermReflection reflectedArguments] |
| `getHiddenWindowsResponse:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `getHotkeysResponse:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `getOriginsResponse:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `getPaneIDsResponseAndSetHotkeys:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `getPaneIDsResponseAndSetTabColors:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `getPendingOutputResponse:pane:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `getPerTabSettingsResponse:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `getPerWindowSettingsResponse:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `getProcessInfoForProcessID:flavor:arg:size:reqid:withReply:` | selector |  | XPC wire format (selector sent by name) | SlowOperationXPC/iTermSlowOperationGateway.m in -[iTermSlowOperationGateway connect] |
| `getSessionGuidResponse:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `getTabColorsResponse:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `getTabGroupParentsResponse:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `getTabGroupsResponse:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `getUserVarsResponse:pane:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `GrowlTrigger` | class (empty @interface and @implementation, iTermUserNotificationTrigger.m in the GrowlTrigger class; no method rows) | `GrowlTrigger` | persisted by name | Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `guessVersion18Response:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `guessVersion21Response:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `guessVersion22Response:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `guessVersion23Response:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `handle:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `handleDisplayMessageVersion:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `handleListKeys:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `handlePingResponse:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `handleResizeWindowResponse:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `handleShowBuffer:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `handleShowSetTitles:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `handleShowSize:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `handleStatusIntervalResponse:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `handleStatusResponse:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `handshakeWithReply:` | selector |  | XPC wire format (selector sent by name) | SlowOperationXPC/iTermSlowOperationGateway.m in -[iTermSlowOperationGateway connect] |
| `HighlightBrowserTrigger` | class | `iTerm2SharedARC.HighlightBrowserTrigger` | persisted by name; do not add or change `@objc(Name)`: the stored name is the current runtime name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `HighlightTrigger` | class | `HighlightTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `hotKeyPressed:siblings:` | selector |  |  | Hotkey/iTermCarbonHotKeyController.m in -[iTermCarbonHotKeyController handleEvent:] |
| `hotkeyPressed:siblings:` | selector |  |  | Hotkey/iTermCarbonHotKeyController.m in -[iTermCarbonHotKeyController handleEvent:] |
| `HyperlinkBrowserTrigger` | class | `iTerm2SharedARC.HyperlinkBrowserTrigger` | persisted by name; do not add or change `@objc(Name)`: the stored name is the current runtime name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `imageRectForBounds:` | not in database: SDK or AppKit-private name |  | SDK or AppKit-private | Categories/NSTableView+iTerm.m in -[iTermToolbeltOutlineView makeViewWithIdentifier:owner:] |
| `importColorPreset:` | selector |  |  | Settings/ProfilesColorsPreferencesViewController.m in -[ProfilesColorsPreferencesViewController addPresetItemWithTitle:action:] |
| `initialListWindowsResponse:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `initWithConfiguration:scope:` | selector |  |  | StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:] |
| `initWithDictionary:` | selector |  |  | DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromDictionary:], Marks/iTermMark.m in +[iTermMark intervalTreeObjectWithDictionaryWithTypeInformation:] |
| `InjectJavascriptContentTrigger` | class | `InjectJavascriptContentTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `InjectJavascriptURLTrigger` | class | `InjectJavascriptURLTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `insertNewline:` | selector |  | SDK or AppKit-private; defined on: `iTermStatusBarKnobNumericViewController` and `iTermStatusBarKnobTextViewController` | StatusBar/Setup/Knobs/iTermStatusBarKnobNumericViewController.m in -[iTermStatusBarKnobNumericViewController control:textView:doCommandBySelector:], StatusBar/Setup/Knobs/iTermStatusBarKnobTextViewController.m in -[iTermStatusBarKnobTextViewController control:textView:doCommandBySelector:] |
| `inspectImage:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:], ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper smartSelectionActionSelectorDictionary] |
| `installShellIntegration:` | selector |  |  | ShellIntegration/iTermShellHistoryController.m in +[iTermShellHistoryController showInformationalMessageInWindow:] |
| `it_intlistValue` | selector |  |  | tmux/TmuxStateParser.m in +[TmuxStateParser dictionaryForState:workAroundTabBug:] |
| `it_numberValue` | selector |  |  | tmux/TmuxStateParser.m in +[TmuxStateParser dictionaryForState:workAroundTabBug:] |
| `it_paneIdNumberValue` | selector |  |  | tmux/TmuxStateParser.m in +[TmuxStateParser dictionaryForState:workAroundTabBug:] |
| `it_redrawPeriodically:` | selector |  |  | Categories/NSTimer+iTerm.m in -[iTermTimerProxy timerDidFire:] |
| `iterm_undoSafety_viewWillMoveToWindow:` | selector |  |  | Categories/NSTextView+iTermUndoSafety.m in +[NSTextView(iTermUndoSafety) load] |
| `iTermAdvancedSettingsModel +advancedSettingsModelDictionary_*` | 515 class methods with prefix |  |  | Settings/iTermAdvancedSettingsModel.m in +[iTermAdvancedSettingsModel enumerateMethods:], Settings/iTermAdvancedSettingsModel.m in +[iTermAdvancedSettingsModel enumerateDictionaries:] |
| `iTermAdvancedSettingsModel +deprecated_*` | 1 class methods with prefix |  |  | Settings/iTermAdvancedSettingsModel.m in +[iTermAdvancedSettingsModel settingIsDeprecated:] |
| `iTermAdvancedSettingsModel +load_*` | 516 class methods with prefix |  |  | Settings/iTermAdvancedSettingsModel.m in +[iTermAdvancedSettingsModel enumerateMethods:], Settings/iTermAdvancedSettingsModel.m in +[iTermAdvancedSettingsModel enumerateDictionaries:] |
| `iTermBadgeConfigurationWindowController` | class | `iTermBadgeConfigurationWindowController` | nib name derived from class name | Composer/iTermMinimalComposerViewController.m in -[iTermMinimalComposerViewController init] (also iTermHotkeyPreferencesWindowController.m in -[iTermHotkeyPreferencesWindowController init] |
| `iTermBlockMark` | class | `iTermBlockMark` | persisted by name | DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree dictionaryValueWithOffset:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromGraphRecord:offset:largeContentProvider:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromDictionary:], Marks/iTermMark.m in +[iTermMark intervalTreeObjectWithDictionaryWithTypeInformation:] |
| `iTermBufferInputTrigger` | class | `iTermBufferInputTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `iTermButtonMark` | class | `iTermButtonMark` | persisted by name | DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree dictionaryValueWithOffset:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromGraphRecord:offset:largeContentProvider:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromDictionary:], Marks/iTermMark.m in +[iTermMark intervalTreeObjectWithDictionaryWithTypeInformation:] |
| `iTermCapturedOutputMark` | class (empty @implementation, iTermCapturedOutputMark.m; no method rows) | `iTermCapturedOutputMark` | persisted by name | DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree dictionaryValueWithOffset:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromGraphRecord:offset:largeContentProvider:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromDictionary:], Marks/iTermMark.m in +[iTermMark intervalTreeObjectWithDictionaryWithTypeInformation:] |
| `iTermDirectoryEntry` | class | `iTermDirectoryEntry` | crosses a process boundary by name (XPC); compiled into two targets | SlowOperationXPC/iTermSlowOperationGateway.m in -[iTermSlowOperationGateway connect] |
| `iTermEditSnippetWindowController` | class | `iTermEditSnippetWindowController` | nib name derived from class name | Composer/iTermMinimalComposerViewController.m in -[iTermMinimalComposerViewController init] (also iTermHotkeyPreferencesWindowController.m in -[iTermHotkeyPreferencesWindowController init] |
| `iTermEnterWorkgroupBrowserTrigger` | class | `iTermEnterWorkgroupBrowserTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `iTermEnterWorkgroupTrigger` | class | `iTermEnterWorkgroupTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `iTermExitWorkgroupBrowserTrigger` | class | `iTermExitWorkgroupBrowserTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `iTermExitWorkgroupTrigger` | class | `iTermExitWorkgroupTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `iTermFoldMark` | class | `iTermFoldMark` | persisted by name | DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree dictionaryValueWithOffset:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromGraphRecord:offset:largeContentProvider:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromDictionary:], Marks/iTermMark.m in +[iTermMark intervalTreeObjectWithDictionaryWithTypeInformation:] |
| `iTermFoldTrigger` | class | `iTermFoldTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `iTermGitFileStatus` | class | `iTermGitFileStatus` | crosses a process boundary by name (XPC); compiled into two targets | SlowOperationXPC/iTermSlowOperationGateway.m in -[iTermSlowOperationGateway connect] |
| `iTermGitState` | class | `iTermGitState` | crosses a process boundary by name (XPC); compiled into two targets | SlowOperationXPC/iTermSlowOperationGateway.m in -[iTermSlowOperationGateway connect] |
| `iTermHighlightLineTrigger` | class | `iTermHighlightLineTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `iTermHotkeyPreferencesWindowController` | class | `iTermHotkeyPreferencesWindowController` | nib name derived from class name | Composer/iTermMinimalComposerViewController.m in -[iTermMinimalComposerViewController init] (also iTermHotkeyPreferencesWindowController.m in -[iTermHotkeyPreferencesWindowController init] |
| `iTermHyperlinkTrigger` | class | `iTermHyperlinkTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `iTermImage` | class | `iTermImage` | crosses a process boundary by name (XPC); compiled into two targets | XPC/iTermSandboxedWorkerClient.m in +[iTermSandboxedWorkerClient connection] |
| `iTermImageMark` | class | `iTermImageMark` | persisted by name | DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree dictionaryValueWithOffset:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromGraphRecord:offset:largeContentProvider:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromDictionary:], Marks/iTermMark.m in +[iTermMark intervalTreeObjectWithDictionaryWithTypeInformation:] |
| `iTermInjectTrigger` | class | `iTermInjectTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `iTermMark` | class | `iTermMark` | persisted by name | DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree dictionaryValueWithOffset:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromGraphRecord:offset:largeContentProvider:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromDictionary:], Marks/iTermMark.m in +[iTermMark intervalTreeObjectWithDictionaryWithTypeInformation:] |
| `iTermMinimalComposerViewController` | class | `iTermMinimalComposerViewController` | nib name derived from class name | Composer/iTermMinimalComposerViewController.m in -[iTermMinimalComposerViewController init] (also iTermHotkeyPreferencesWindowController.m in -[iTermHotkeyPreferencesWindowController init] |
| `iTermPathMark` | class | `iTermPathMark` | persisted by name | DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree dictionaryValueWithOffset:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromGraphRecord:offset:largeContentProvider:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromDictionary:], Marks/iTermMark.m in +[iTermMark intervalTreeObjectWithDictionaryWithTypeInformation:] |
| `iTermProfilesWindowRestorer` | class | `iTermProfilesWindowRestorer` | persisted by name by AppKit (saved application state) | Settings/Profiles/iTermProfilesWindowController.m in -[iTermProfilesWindowController initWithWindowNibName:] |
| `iTermRPCTrigger` | class | `iTermRPCTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `iTermScriptCallCancellation` | class | `iTermScriptCallCancellation` | class name read from a type encoding | Language/iTermBuiltInFunctions.m in +[iTermBuiltInMethod argumentDictionaryFromArray:] |
| `iTermSetNamedMarkTrigger` | class | `iTermSetNamedMarkTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `iTermSetProfileBooleanTrigger` | class | `iTermSetProfileBooleanTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `iTermSetTabStatusTrigger` | class | `iTermSetTabStatusTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `iTermSetTitleTrigger` | class | `iTermSetTitleTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `iTermSetUserVariableTrigger` | class | `iTermSetUserVariableTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `iTermSGRTrigger` | class | `iTermSGRTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `iTermShellPromptTrigger` | class | `iTermShellPromptTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `iTermStatusBarActionComponent` | class | `iTermStatusBarActionComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarActionMenuComponent` | class | `iTermStatusBarActionMenuComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarAttributedTextComponent` | class | `iTermStatusBarAttributedTextComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarBatteryComponent` | class | `iTermStatusBarBatteryComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarBuiltInComponentFactory` | class | `iTermStatusBarBuiltInComponentFactory` | crosses a process boundary by name (pasteboard archive) | Categories/NSData+iTerm.m in +[NSData(iTerm) it_dataWithArchivedObject:] |
| `iTermStatusBarClockComponent` | class | `iTermStatusBarClockComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarComposerComponent` | class | `iTermStatusBarComposerComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarCPUUtilizationComponent` | class | `iTermStatusBarCPUUtilizationComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarFilterComponent` | class | `iTermStatusBarFilterComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarFixedSpacerComponent` | class | `iTermStatusBarFixedSpacerComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarFunctionCallComponent` | class | `iTermStatusBarFunctionCallComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarGitComponent` | class | `iTermStatusBarGitComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarHostnameComponent` | class | `iTermStatusBarHostnameComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarJobComponent` | class | `iTermStatusBarJobComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarMemoryUtilizationComponent` | class | `iTermStatusBarMemoryUtilizationComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarNetworkUtilizationComponent` | class | `iTermStatusBarNetworkUtilizationComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarPlaceholderComponent` | class | `iTermStatusBarPlaceholderComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarProgressComponent` | class | `iTermStatusBarProgressComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarRPCComponentFactory` | class | `iTermStatusBarRPCComponentFactory` | crosses a process boundary by name (pasteboard archive) | Categories/NSData+iTerm.m in +[NSData(iTerm) it_dataWithArchivedObject:] |
| `iTermStatusBarRPCProvidedAttributedTextComponent` | class | `iTermStatusBarRPCProvidedAttributedTextComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarRPCProvidedTextComponent` | class | `iTermStatusBarRPCProvidedTextComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarSearchFieldComponent` | class | `iTermStatusBarSearchFieldComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarSetupElement` | class | `iTermStatusBarSetupElement` | crosses a process boundary by name (pasteboard archive) | Categories/NSData+iTerm.m in +[NSData(iTerm) it_dataWithArchivedObject:] |
| `iTermStatusBarSnippetMenuComponent` | class | `iTermStatusBarSnippetMenuComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarSparklinesComponent` | class | `iTermStatusBarSparklinesComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarSpringComponent` | class | `iTermStatusBarSpringComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarSwiftyStringComponent` | class | `iTermStatusBarSwiftyStringComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarTextComponent` | class | `iTermStatusBarTextComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarTmuxLeftComponent` | class | `iTermStatusBarTmuxLeftComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarTmuxRightComponent` | class | `iTermStatusBarTmuxRightComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarTriggersComponent` | class | `iTermStatusBarTriggersComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarUsernameComponent` | class | `iTermStatusBarUsernameComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarVariableBaseComponent` | class | `iTermStatusBarVariableBaseComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermStatusBarWorkingDirectoryComponent` | class | `iTermStatusBarWorkingDirectoryComponent` | persisted by name | StatusBar/Components/iTermStatusBarBaseComponent.m in +[iTermStatusBarBaseComponent statusBarComponentIdentifier], StatusBar/Components/iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], StatusBar/Core/iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], StatusBar/Core/iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (also iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]) |
| `iTermTuple` | class | `iTermTuple` | persisted by name (allowed when reading state-restoration archives) | Categories/NSData+iTerm.m in -[NSData(iTerm) it_unarchivedObjectOfBasicClassesWithError:] |
| `iTermUserNotificationTrigger` | class | `iTermUserNotificationTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `listedWindowsToOpenOne:forWindowIdAndAffinities:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `listSessionsResponse:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `listWindowsResponse:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `loadURLWithCompletion:url:connectionKey:cancellation:` | selector |  |  | Language/iTermBuiltInFunctions.m in -[iTermBuiltInMethod callWithArguments:connectionKey:cancellation:completion:], Language/iTermReflection.m in -[iTermReflection reflectedArguments] |
| `log:` | selector |  |  | StatusBar/Components/iTermStatusBarGitComponent.m in -[iTermStatusBarGitComponent openMenuWithView:] |
| `mail:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `MarkTrigger` | class | `MarkTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `maybePollForWorkingDirectory` | selector |  |  | Infrastructure/iTermRateLimitedUpdate.m in -[iTermRateLimitedUpdate performRateLimitedSelector:onTarget:withObject:] |
| `moveDown:` | selector |  | SDK or AppKit-private; defined on: `iTermFindDriver` (iTermFindDriver.m in -[iTermFindDriver moveDown:]) | SearchingFiltering/iTermFindDriver.m in -[iTermFindDriver doCommandBySelector:] |
| `movePane:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `moveSessionToFloatingPaneFromContextMenu:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `moveTabGroupToNewWindow:` | selector |  |  | TerminalView/PseudoTerminal.m in -[PseudoTerminal reconcileTabGroupDefinitionForTab:] |
| `MuteCoprocessTrigger` | class | `MuteCoprocessTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `newSessionInTabAtIndex:` | selector |  |  | Settings/Profiles/iTermProfilesMenuController.m in +[iTermProfilesMenuController addOpenAllToMenu:params:identifier:], iTermController/iTermController.m in -[iTermController addBookmarksToMenu:supermenu:withSelector:openAllSelector:startingAt:] |
| `newSessionInWindowAtIndex:` | selector |  |  | Settings/Profiles/iTermProfilesMenuController.m in +[iTermProfilesMenuController addOpenAllToMenu:params:identifier:], iTermController/iTermController.m in -[iTermController addBookmarksToMenu:supermenu:withSelector:openAllSelector:startingAt:] |
| `newSessionsInNewWindow:` | selector |  |  | Settings/Profiles/iTermProfilesMenuController.m in +[iTermProfilesMenuController addOpenAllToMenu:params:identifier:], iTermController/iTermController.m in -[iTermController addBookmarksToMenu:supermenu:withSelector:openAllSelector:startingAt:] |
| `newSessionsInWindow:` | selector |  |  | Settings/Profiles/iTermProfilesMenuController.m in +[iTermProfilesMenuController addOpenAllToMenu:params:identifier:], iTermController/iTermController.m in -[iTermController addBookmarksToMenu:supermenu:withSelector:openAllSelector:startingAt:] |
| `newTabInGroup:` | selector |  |  | TerminalView/PseudoTerminal.m in -[PseudoTerminal reconcileTabGroupDefinitionForTab:] |
| `newWindowWithAffinityCreated:affinityWindowAndCompletion:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `noop:` | selector |  | compared by name at iTermFocusReportingTextField.m in -[iTermFocusReportingSearchField doCommandBySelector:] (Cocoa text system command); also an action of ours | Infrastructure/Views/iTermFocusReportingTextField.m in -[iTermFocusReportingSearchField doCommandBySelector:], StatusBar/Setup/iTermStatusBarSetupViewController.m in -[iTermStatusBarSetupViewController initializeColorWell:withAction:color:alphaAllowed:] |
| `NSArray` | class | `NSArray` | SDK or AppKit-private | Language/iTermBuiltInFunctions.m in +[iTermBuiltInMethod argumentDictionaryFromArray:] |
| `NSNumber` | class | `NSNumber` | SDK or AppKit-private | Language/iTermBuiltInFunctions.m in +[iTermBuiltInMethod argumentDictionaryFromArray:] |
| `NSOutlineButtonCell_iTermCustomImageRect` | class made at run time by objc_allocateClassPair (NSTableView+iTerm.m in -[iTermToolbeltOutlineView makeViewWithIdentifier:owner:]) | `NSOutlineButtonCell_iTermCustomImageRect` | created at run time | Categories/NSTableView+iTerm.m in -[iTermToolbeltOutlineView makeViewWithIdentifier:owner:] |
| `NSPanel.ViewBridge.rendezvous` | not in database: SDK or AppKit-private name | `NSPanel.ViewBridge.rendezvous` | SDK or AppKit-private | AppKit/iTermApplication.m in -[iTermApplication it_windowDidOrderOnScreen:] |
| `NSPanelViewBridge` | not in database: SDK or AppKit-private name | `NSPanelViewBridge` | SDK or AppKit-private | AppKit/iTermApplication.m in -[iTermApplication it_windowDidOrderOnScreen:] |
| `NSSearchFieldCell` | not in database: SDK or AppKit-private name | `NSSearchFieldCell` | SDK or AppKit-private | Settings/PreferencePanel.m in -[PreferencePanel bigSurSearchFieldToolbarItem] |
| `NSString` | class | `NSString` | SDK or AppKit-private | Language/iTermBuiltInFunctions.m in +[iTermBuiltInMethod argumentDictionaryFromArray:] |
| `NSTitlebarContainerView` | not in database: SDK or AppKit-private name | `NSTitlebarContainerView` | SDK or AppKit-private | Infrastructure/iTermSelectorSwizzler.m in +[iTermSelectorSwizzler permanentlySwizzleSelector:fromClass:withBlock:] |
| `NSToolbarFullScreenWindow` | not in database: SDK or AppKit-private name | `NSToolbarFullScreenWindow` | SDK or AppKit-private | AppKit/iTermApplication.m in -[iTermApplication it_windowDidOrderOnScreen:] |
| `NSToolTipPanel` | not in database: SDK or AppKit-private name | `NSToolTipPanel` | SDK or AppKit-private | AppKit/iTermApplication.m in -[iTermApplication it_windowDidOrderOnScreen:] |
| `object_browserBundleID` | selector |  |  | Settings/iTermAdvancedSettingsViewController.m in -[iTermAdvancedSettingsViewController toggleOnOff:] |
| `object_enableSecureKeyboardEntryAutomatically` | selector |  |  | Settings/iTermAdvancedSettingsViewController.m in -[iTermAdvancedSettingsViewController toggleOnOff:] |
| `openImage:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:], ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper smartSelectionActionSelectorDictionary] |
| `openInAdvancedPaste:` | selector |  |  | Toolbelt/ToolPasteHistory.m in -[ToolPasteHistory validateMenuItem:], Toolbelt/iTermToolSnippets.m in iTermToolSnippetsNewButton |
| `openURLInFloatingPane:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `openURLInHorizontalSplitPane:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `openURLInVerticalSplitPane:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `original_imageRectForBounds:` | selector |  |  | Categories/NSTableView+iTerm.m in -[iTermToolbeltOutlineView makeViewWithIdentifier:owner:] |
| `panesDidUnpause:` | selector |  |  | tmux/TmuxWindowOpener.m in -[TmuxWindowOpener finishErroneously], tmux/TmuxWindowOpener.m in -[TmuxWindowOpener requestDidComplete], tmux/TmuxWindowOpener.m in -[TmuxWindowOpener requestDidComplete] |
| `parseListWindowsResponseAndUpdateLayouts:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `PasswordTrigger` | class | `PasswordTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `paste:` | selector |  | SDK or AppKit-private; defined on: any responder (the first responder of the front terminal window, PasteboardHistory.m in -[PasteboardHistoryWindowController rowSelected:], if it responds) | Categories/NSObject+iTerm.m in -[NSObject(iTerm) it_performNonObjectReturningSelector:withObject:] |
| `pasteNextChunkAndScheduleTimer` | selector |  |  | Pasting/iTermPasteHelper.m in -[iTermPasteHelper scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:] |
| `performBlockIfNeeded:` | selector |  |  | Categories/NSTimer+iTerm.m in -[iTermTimerProxy timerDidFire:], Infrastructure/iTermGCDTimer.m in -[iTermGCDTimer didFire] |
| `performFindPanelAction:` | selector |  | SDK or AppKit-private | Infrastructure/Views/iTermFocusReportingTextField.m in -[iTermTextView validateMenuItem:] |
| `phonyCommandDidComplete:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `poll` | selector |  |  | Categories/NSTimer+iTerm.m in -[iTermTimerProxy timerDidFire:] |
| `PortholeMark` | class | `iTerm2SharedARC.PortholeMark` | persisted by name; do not add or change `@objc(Name)`: the stored name is the current runtime name | DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree dictionaryValueWithOffset:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromGraphRecord:offset:largeContentProvider:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromDictionary:], Marks/iTermMark.m in +[iTermMark intervalTreeObjectWithDictionaryWithTypeInformation:] |
| `postInvalidateNotification` | selector |  |  | Infrastructure/iTermRateLimitedUpdate.m in -[iTermRateLimitedUpdate performRateLimitedSelector:onTarget:withObject:] |
| `postUpdateSessionNameNotification` | selector |  |  | Infrastructure/iTermRateLimitedUpdate.m in -[iTermRateLimitedUpdate performRateLimitedSelector:onTarget:withObject:] |
| `preferenceDidChange:` | selector |  |  | Notifications/iTermNotificationCenter.m in +[iTermBaseNotification subscribe:selector:] |
| `pressDownloadsMenu` | selector |  |  | FileTransfer/FileTransferManager.m in -[FileTransferManager performMenuActionOnRunLoop:inModes:] |
| `pressUploadsMenu` | selector |  |  | FileTransfer/FileTransferManager.m in -[FileTransferManager performMenuActionOnRunLoop:inModes:] |
| `printTmuxCommandOutputToScreen:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `ProfileTableRow.command` | property |  |  | Settings/Profiles/ProfileListView.m in -[ProfileListView tableView:didClickTableColumn:] |
| `ProfileTableRow.name` | property |  |  | Settings/Profiles/ProfileListView.m in -[ProfileListView tableView:didClickTableColumn:] |
| `ProfileTableRow.shortcut` | property |  |  | Settings/Profiles/ProfileListView.m in -[ProfileListView tableView:didClickTableColumn:] |
| `PseudoTerminalRestorer` | class | `PseudoTerminalRestorer` | persisted by name by AppKit (saved application state) | TerminalView/PseudoTerminal.m in -[PseudoTerminal finishInitializationWithSmartLayout:windowType:savedWindowType:percentage:screen:hotkeyWindowType:profile:] |
| `PTYAnnotation` | class | `PTYAnnotation` | persisted by name | DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree dictionaryValueWithOffset:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromGraphRecord:offset:largeContentProvider:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromDictionary:], Marks/iTermMark.m in +[iTermMark intervalTreeObjectWithDictionaryWithTypeInformation:] |
| `pull:` | selector |  |  | StatusBar/Components/iTermStatusBarGitComponent.m in -[iTermStatusBarGitComponent openMenuWithView:] |
| `push:` | selector |  |  | StatusBar/Components/iTermStatusBarGitComponent.m in -[iTermStatusBarGitComponent openMenuWithView:] |
| `quickLook:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `ReaderModeBrowserTrigger` | class | `iTerm2SharedARC.ReaderModeBrowserTrigger` | persisted by name; do not add or change `@objc(Name)`: the stored name is the current runtime name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `reallyAdd:` | selector |  |  | PasswordManager/iTermPasswordManagerWindowController.m in iTermPWMakePushButton |
| `recordPanes:state:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `redo:` | selector |  | SDK or AppKit-private | AppKit/iTermApplicationDelegate.m in -[iTermApplicationDelegate performUndoRedoSelector:sender:] |
| `reevaluateTimer:` | selector |  |  | Categories/NSTimer+iTerm.m in -[iTermTimerProxy timerDidFire:] |
| `refreshMenuBarNow` | selector |  |  | FileTransfer/FileTransferManager.m in -[FileTransferManager performMenuActionOnRunLoop:inModes:] |
| `ReloadBrowserTrigger` | class | `ReloadBrowserTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `remove:` | selector |  |  | Toolbelt/iTermToolActions.m in iTermToolActionsNewButton, Toolbelt/iTermToolSnippets.m in iTermToolSnippetsNewButton |
| `renameTabGroupFromMenu:` | selector |  |  | TerminalView/PseudoTerminal.m in -[PseudoTerminal reconcileTabGroupDefinitionForTab:] |
| `requestDidComplete` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `requestGitStateForPath:gitBase:timeout:includeDiffStats:completion:` | selector |  | XPC wire format (selector sent by name) | SlowOperationXPC/iTermSlowOperationGateway.m in -[iTermSlowOperationGateway connect] |
| `resolvePathOfDirectory:withReply:` | selector |  | XPC wire format (selector sent by name) | SlowOperationXPC/iTermSlowOperationGateway.m in -[iTermSlowOperationGateway connect] |
| `responseForListWindows:toSetPartialOrder:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `restartSession:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `restoreWindowArrangement:` | selector |  |  | Settings/WindowArrangements.m in +[WindowArrangements refreshRestoreArrangementsMenu:withSelector:defaultShortcut:identifier:] |
| `restoreWindowArrangementAfterDelay:` | selector |  |  | Settings/WindowArrangements.m in +[WindowArrangements refreshRestoreArrangementsMenu:withSelector:defaultShortcut:identifier:] |
| `restoreWindowArrangementAfterDelayAsTabs:` | selector |  |  | Settings/WindowArrangements.m in +[WindowArrangements refreshRestoreArrangementsMenu:withSelector:defaultShortcut:identifier:] |
| `restoreWindowArrangementAsTabs:` | selector |  |  | Settings/WindowArrangements.m in +[WindowArrangements refreshRestoreArrangementsMenu:withSelector:defaultShortcut:identifier:] |
| `restoreWindowWithIdentifier:state:completionHandler:` | selector |  | sent by AppKit to the restoration class found by name | Settings/Profiles/iTermProfilesWindowController.m in -[iTermProfilesWindowController initWithWindowNibName:], TerminalView/PseudoTerminal.m in -[PseudoTerminal finishInitializationWithSmartLayout:windowType:savedWindowType:percentage:screen:hotkeyWindowType:profile:] |
| `runCoprocessWithCompletion:commandLine:mute:` | selector |  |  | Language/iTermBuiltInFunctions.m in -[iTermBuiltInMethod callWithArguments:connectionKey:cancellation:completion:], Language/iTermReflection.m in -[iTermReflection reflectedArguments] |
| `runModal` | selector |  | SDK or AppKit-private | AppKit/iTermApplicationDelegate.m in -[iTermApplicationDelegate init] |
| `runShellScript:shell:mode:withReply:` | selector |  | XPC wire format (selector sent by name) | SlowOperationXPC/iTermSlowOperationGateway.m in -[iTermSlowOperationGateway connect] |
| `saveColorPreset:` | selector |  |  | Settings/ProfilesColorsPreferencesViewController.m in -[ProfilesColorsPreferencesViewController addPresetItemWithTitle:action:] |
| `savedGridExpirationTimer:` | selector |  |  | Infrastructure/iTermGCDTimer.m in -[iTermGCDTimer didFire] |
| `saveImageAs:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:], ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper smartSelectionActionSelectorDictionary] |
| `saveSelectionAsSnippet:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `saveTabGroupAsWindowArrangement:` | selector |  |  | TerminalView/PseudoTerminal.m in -[PseudoTerminal reconcileTabGroupDefinitionForTab:] |
| `saveWindowOriginsResponse:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `ScriptTrigger` | class | `ScriptTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `searchInBrowser:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `searchMore:` | selector |  |  | Categories/NSTimer+iTerm.m in -[iTermTimerProxy timerDidFire:] |
| `searchParseTree:forWindowPane:` | selector |  |  | tmux/TmuxLayoutParser.m in -[TmuxLayoutParser depthFirstSearchParseTree:callingSelector:onTarget:withObject:] |
| `selectAll:` | selector |  | SDK or AppKit-private | Infrastructure/Views/iTermKeyboardNavigatableTableView.m in -[iTermKeyboardNavigatableTableView respondsToSelector:] |
| `selector:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `selectPaneInDirectionWithCompletion:direction:` | selector |  |  | Language/iTermBuiltInFunctions.m in -[iTermBuiltInMethod callWithArguments:connectionKey:cancellation:completion:], Language/iTermReflection.m in -[iTermReflection reflectedArguments] |
| `sendFloatingPaneToBackFromContextMenu:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `sendSelection:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `SendTextTrigger` | class | `SendTextTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `sendTmuxCommandMethodDidComplete:completion:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `sendTmuxCommandWithCompletion:command:` | selector |  |  | Language/iTermBuiltInFunctions.m in -[iTermBuiltInMethod callWithArguments:connectionKey:cancellation:completion:], Language/iTermReflection.m in -[iTermReflection reflectedArguments] |
| `setDelegate:` | selector |  | SDK or AppKit-private; defined on: the key mapper chosen at PTYSession.m in -[PTYSession updateKeyMapper], if it responds: `iTermStandardKeyMapper`, `iTermModernKeyMapper`, `iTermTermkeyKeyMapper`, `iTermModifyOtherKeysMapper1`, `iTermModifyOtherKeysMapper2` (property inherited from `iTermModifyOtherKeysMapper`); `iTermRawKeyMapper` has none | Categories/NSObject+iTerm.m in -[NSObject(iTerm) it_performNonObjectReturningSelector:withObject:] |
| `SetDirectoryTrigger` | class | `SetDirectoryTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `setFromObject_BrowserBundleID:` | selector |  |  | Settings/iTermAdvancedSettingsViewController.m in -[iTermAdvancedSettingsViewController toggleOnOff:] |
| `setFromObject_EnableSecureKeyboardEntryAutomatically:` | selector |  |  | Settings/iTermAdvancedSettingsViewController.m in -[iTermAdvancedSettingsViewController toggleOnOff:] |
| `SetHostnameTrigger` | class | `SetHostnameTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `setNameWithCompletion:name:` | selector |  |  | Language/iTermBuiltInFunctions.m in -[iTermBuiltInMethod callWithArguments:connectionKey:cancellation:completion:], Language/iTermReflection.m in -[iTermReflection reflectedArguments] |
| `setStatusBarComponentUnreadCountWithCompletion:identifier:count:` | selector |  |  | Language/iTermBuiltInFunctions.m in -[iTermBuiltInMethod callWithArguments:connectionKey:cancellation:completion:], Language/iTermReflection.m in -[iTermReflection reflectedArguments] |
| `settingChanged:` | selector |  |  | Settings/iTermSlider.m in -[iTermSlider performAction] |
| `setTitleWithCompletion:title:` | selector |  |  | Language/iTermBuiltInFunctions.m in -[iTermBuiltInMethod callWithArguments:connectionKey:cancellation:completion:], Language/iTermReflection.m in -[iTermReflection reflectedArguments] |
| `setWindows:forSession:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxController.m in -[TmuxController didListWindows:userData:] |
| `showMenu:` | selector |  | SDK or AppKit-private | Categories/NSObject+iTerm.m in +[NSObject(iTerm) load] |
| `showNotes:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `showWindowOptionsResponse:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |
| `snippetsDidChange:` | selector |  |  | Notifications/iTermNotificationCenter.m in +[iTermBaseNotification subscribe:selector:] |
| `splitTextViewHorizontally:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `splitTextViewVertically:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `stash:` | selector |  |  | StatusBar/Components/iTermStatusBarGitComponent.m in -[iTermStatusBarGitComponent openMenuWithView:] |
| `statFile:withReply:` | selector |  | XPC wire format (selector sent by name) | SlowOperationXPC/iTermSlowOperationGateway.m in -[iTermSlowOperationGateway connect] |
| `stopCoprocess:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `stopCoprocessWithCompletion:` | selector |  |  | Language/iTermBuiltInFunctions.m in -[iTermBuiltInMethod callWithArguments:connectionKey:cancellation:completion:], Language/iTermReflection.m in -[iTermReflection reflectedArguments] |
| `StopTrigger` | class | `StopTrigger` | persisted by name | Settings/TriggerController.m in -[TriggerController indexOfAction:], Triggers/Trigger.m in -[Trigger dictionaryValue], Triggers/Trigger.m in +[Trigger triggerFromUntrustedDict:] |
| `swapSessions:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `swizzled__NSThemeZoomWidgetCell_showMenu:` | selector |  |  | Categories/NSObject+iTerm.m in +[NSObject(iTerm) load] |
| `terminalStateSetEmulationLevel:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `terminalStateToggleAlternateScreen:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `terminalStateToggleApplicationCursor:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `terminalStateToggleApplicationKeypad:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `terminalStateToggleFocusReporting:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `terminalStateToggleLiteralMode:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `terminalStateToggleMouseReporting:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `terminalStateTogglePasteBracketing:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `terminalToggleKeyboardMode:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `textFieldSubmitted` | selector |  | Swift site (section 9) | Browser/UI/iTermURLTextField.swift in iTermURLTextField.textView(_:doCommandBy:) |
| `threeFingerTap:` | selector |  |  | MousePointer/ThreeFingerTapGestureRecognizer.m in -[ThreeFingerTapGestureRecognizer touchesEndedWithEvent:] |
| `timeout` | selector |  |  | Infrastructure/iTermGCDTimer.m in -[iTermGCDTimer didFire] |
| `toggleBroadcastingInput:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] |
| `toggleCheckmark:` | selector |  |  | Toolbelt/CapturedOutput/ToolCapturedOutputView.m in -[ToolCapturedOutputView validateMenuItem:] |
| `togglePauseAnimatingImage:` | selector |  |  | ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:], ContextMenu/iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper smartSelectionActionSelectorDictionary] |
| `toggleStar:` | selector |  |  | Toolbelt/ToolDirectoriesView.m in -[ToolDirectoriesView validateMenuItem:] |
| `toggleTriggerEnabled:` | selector |  |  | AppKit/iTermApplicationDelegate.m in -[iTermApplicationDelegate firstResponderForMenuItem:], Categories/NSObject+iTerm.m in -[NSObject(iTerm) it_performNonObjectReturningSelector:withObject:] |
| `toolProfilesNewFloatingPane:` | selector |  |  | Toolbelt/ToolProfiles.m in -[ToolProfiles open:] |
| `toolProfilesNewHorizontalSplit:` | selector |  |  | Toolbelt/ToolProfiles.m in -[ToolProfiles open:] |
| `toolProfilesNewTab:` | selector |  |  | Toolbelt/ToolProfiles.m in -[ToolProfiles open:] |
| `toolProfilesNewVerticalSplit:` | selector |  |  | Toolbelt/ToolProfiles.m in -[ToolProfiles open:] |
| `toolProfilesNewWindow:` | selector |  |  | Toolbelt/ToolProfiles.m in -[ToolProfiles open:] |
| `undo:` | selector |  | SDK or AppKit-private | AppKit/iTermApplicationDelegate.m in -[iTermApplicationDelegate performUndoRedoSelector:sender:], PTYSession/PTYSession.m in +[PTYSession _recursiveSelectMenuWithSelector:inMenu:] |
| `ungroupTabGroup:` | selector |  |  | TerminalView/PseudoTerminal.m in -[PseudoTerminal reconcileTabGroupDefinitionForTab:] |
| `update:` | selector |  |  | Categories/NSTimer+iTerm.m in -[iTermTimerProxy timerDidFire:], Infrastructure/iTermGCDTimer.m in -[iTermGCDTimer didFire] |
| `updateDisplay` | selector |  |  | Categories/NSTimer+iTerm.m in -[iTermTimerProxy timerDidFire:] |
| `updateDownloadBrowserPluginButtonHidden` | selector |  |  | Categories/NSTimer+iTerm.m in -[iTermTimerProxy timerDidFire:] |
| `updateIfNeeded` | selector |  |  | Infrastructure/iTermRateLimitedUpdate.m in -[iTermRateLimitedUpdate performRateLimitedSelector:onTarget:withObject:] |
| `updateStringValue:` | selector |  |  | ThirdParty/PSMTabBarControl/source/PSMTabBarCell.m in -[PSMWeakTimer timerDidFire:] |
| `validateMenuItem:` | selector |  | SDK or AppKit-private | Infrastructure/Views/iTermFocusReportingTextField.m in -[iTermTextView validateMenuItem:] |
| `viewWillMoveToWindow:` | selector |  | SDK or AppKit-private | Categories/NSTextView+iTermUndoSafety.m in +[NSTextView(iTermUndoSafety) load] |
| `visitGallery:` | selector |  |  | Settings/ProfilesColorsPreferencesViewController.m in -[ProfilesColorsPreferencesViewController addPresetItemWithTitle:action:] |
| `VT100MutableScreenConfiguration.alertOnNextMark` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.allowAlternateMouseScroll` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.allowTitleReporting` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.allowTitleSetting` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.appendToScrollbackWithStatusBar` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.audibleBell` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.autoComposerEnabled` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.backingScaleFactor` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.cellSize` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.clearScrollbackAllowed` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.clipboardAccessAllowed` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.cursorBlinks` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.darkMode` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.desiredComposerRows` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.dimmingAmount` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.dimOnlyText` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.enableTriggersInInteractiveApps` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.faintTextAlpha` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.flashBell` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.globalWindowFrame` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.iconTitle` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.isDirty` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.isTmuxClient` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.loggingEnabled` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.maximumTheoreticalImageDimension` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.maxScrollbackLines` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.miniaturized` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.minimumContrast` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.mutingAmount` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.normalization` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.optionIsMetaForSpecialChars` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.osc52` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.postUserNotifications` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.printingAllowed` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.profileName` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.publishing` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.reduceFlicker` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.saveToScrollbackInAlternateScreen` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.screenFrames` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.sessionGuid` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.sessionIsVisible` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.shouldPlacePromptAtFirstColumn` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.showBellIndicator` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.stableID` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.terminalCanChangeBlink` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.terminfoValues` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.theoreticalGridSize` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.treatAmbiguousCharsAsDoubleWidth` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.triggerParametersUseInterpolatedStrings` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.triggerProfileDicts` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.unicodeVersion` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.unlimitedScrollback` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.useLineStyleMarks` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.useSeparateColorsForLightAndDarkMode` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.wantsCommandChangeNotifications` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.windowFrame` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100MutableScreenConfiguration.windowTitle` | property |  |  | VT100Screen/VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] |
| `VT100RemoteHost` | class | `VT100RemoteHost` | persisted by name | DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree dictionaryValueWithOffset:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromGraphRecord:offset:largeContentProvider:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromDictionary:], Marks/iTermMark.m in +[iTermMark intervalTreeObjectWithDictionaryWithTypeInformation:] |
| `VT100ScreenMark` | class | `VT100ScreenMark` | persisted by name | DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree dictionaryValueWithOffset:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromGraphRecord:offset:largeContentProvider:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromDictionary:], Marks/iTermMark.m in +[iTermMark intervalTreeObjectWithDictionaryWithTypeInformation:] |
| `VT100WorkingDirectory` | class | `VT100WorkingDirectory` | persisted by name | DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree dictionaryValueWithOffset:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromGraphRecord:offset:largeContentProvider:], DataStructuresAlgorithms/IntervalTree.m in -[IntervalTree restoreFromDictionary:], Marks/iTermMark.m in +[iTermMark intervalTreeObjectWithDictionaryWithTypeInformation:] |
| `weaklyReferencedObject` | selector |  |  | Infrastructure/iTermWeakReference.m in -[iTermWeakReference respondsToSelector:], Infrastructure/iTermWeakReference.m in -[iTermWeakReference respondsToSelector:] |
| `windowDidOpen:` | selector |  |  | tmux/TmuxWindowOpener.m in -[TmuxWindowOpener finishErroneously], tmux/TmuxWindowOpener.m in -[TmuxWindowOpener requestDidComplete], tmux/TmuxWindowOpener.m in -[TmuxWindowOpener requestDidComplete] |
| `windowPaneBrokeOutWithWindowId:setAffinityTo:` | selector |  |  | tmux/TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:] (also TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:]), tmux/TmuxGateway.m in -[TmuxGateway currentCommandSelector] |

Not listed by name, because a binding test or the census owns the list: every main-menu action selector (reached by the menu-dispatch sites, see `NSMenu+iTerm.m`, `iTermAPIHelper.m`, `iTermOpenQuicklyWindowController.m`) and the `window` keys of `iTerm2.sdef` (reached through `iTermScriptingWindow`).

## 3. Dynamic sites

Grouped by mechanism, then by file. Each bullet is one database row (file and current line, enclosing function, call, argument as written); the paragraph after the bullets classifies all of them.

### Selector from a string

#### `sources/ContextMenu/iTermTextViewContextMenuHelper.m`

- `sources/ContextMenu/iTermTextViewContextMenuHelper.m:877` in `-[iTermTextViewContextMenuHelper selectorForSmartSelectionAction:]`: `NSSelectorFromString` on `dictionary[@(contextMenuAction)]`
- `sources/ContextMenu/iTermTextViewContextMenuHelper.m:920` in `-[iTermTextViewContextMenuHelper addCustomActionsToMenu:matchingText:line:]`: `initWithTitle:action:keyEquivalent:` on `mySelector`

  **CLOSED.** `smartSelectionActionSelectorDictionary` (iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper smartSelectionActionSelectorDictionary]) maps each `ContextMenuActions` value to `NSStringFromSelector(@selector(...))`; an action dict whose kind is not in the table gives nil (no action). Reach: `contextMenuActionOpenFile:`, `contextMenuActionOpenURL:`, `contextMenuActionRunCommand:`, `contextMenuActionRunCoprocess:`, `contextMenuActionSendText:`, `contextMenuActionRunCommandInWindow:`, `contextMenuActionCopy:`. `validateMenuItem:` compares `NSStringFromSelector(item.action)` against the same table, so these names must also stay in that table.

  Names: `contextMenuActionOpenFile:`, `contextMenuActionOpenURL:`, `contextMenuActionRunCommand:`, `contextMenuActionRunCoprocess:`, `contextMenuActionSendText:`, `contextMenuActionRunCommandInWindow:`, `contextMenuActionCopy:`.

#### `sources/SemanticHistory/iTermURLActionFactory.m`

- `sources/SemanticHistory/iTermURLActionFactory.m:584` in `-[iTermURLActionFactory computeURLActionForSmartSelection:]`: `NSSelectorFromString` on `self.selectors[@(value)]`
- `sources/SemanticHistory/iTermURLActionFactory.m:584` in `-[iTermURLActionFactory computeURLActionForSmartSelection:]`: `setSelector:` on `NSSelectorFromString(self.selectors[@(value)])`

  **CLOSED.** `self.selectors` is passed in at iTermURLActionHelper.m in -[iTermURLActionHelper urlActionForClickAtCoord:respectingHardNewlines:alternate:completion:], which asks the helper's delegate; the only implementation (PTYTextView+ARC.m in -[PTYTextView(ARC) urlActionHelperSmartSelectionRules:]) returns `-[iTermTextViewContextMenuHelper smartSelectionActionSelectorDictionary]`, the table at iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper smartSelectionActionSelectorDictionary]. The selector is performed later at iTermURLActionHelper.m in -[iTermURLActionHelper finishOpeningTargetWithEvent:coord:inBackground:style:action:generation:smartSelectionActionsOnly:] on `smartSelectionActionTarget`, which is the context menu helper (PTYTextView.m in -[PTYTextView initWithFrame:]). Reach: the seven `contextMenuAction...:` selectors of that table.

  Names: `contextMenuActionOpenFile:`, `contextMenuActionOpenURL:`, `contextMenuActionRunCommand:`, `contextMenuActionRunCoprocess:`, `contextMenuActionSendText:`, `contextMenuActionRunCommandInWindow:`, `contextMenuActionCopy:`.

#### `sources/Settings/iTermAdvancedSettingsModel.m`

- `sources/Settings/iTermAdvancedSettingsModel.m:375` in `+[iTermAdvancedSettingsModel settingIsDeprecated:]`: `NSSelectorFromString` on `string`
- `sources/Settings/iTermAdvancedSettingsModel.m:376` in `+[iTermAdvancedSettingsModel settingIsDeprecated:]`: `respondsToSelector:` on `selector`

  **CLOSED.** Builds `@"deprecated_" + name` for each setting name found by `enumerateDictionaries:` (iTermAdvancedSettingsModel.m in +[iTermAdvancedSettingsModel enumerateDictionaries:]) and tests it with `respondsToSelector:`. Only `DEFINE_DEPRECATED_STRING` (iTermAdvancedSettingsModel.m in the DEFINE_DEPRECATED_STRING macro) defines `deprecated_<name>`; it is used once, for `autoLogFormat`. Reach: `+deprecated_autoLogFormat`; for every other setting the answer must stay NO.

  Names: `iTermAdvancedSettingsModel +deprecated_*`.

#### `sources/Settings/iTermAdvancedSettingsViewController.m`

- `sources/Settings/iTermAdvancedSettingsViewController.m:354` in `-[iTermAdvancedSettingsViewController toggleOnOff:]`: `NSSelectorFromString` on `selectorName`
- `sources/Settings/iTermAdvancedSettingsViewController.m:355` in `-[iTermAdvancedSettingsViewController toggleOnOff:]`: `performSelector:withObject:` on `selector`
- `sources/Settings/iTermAdvancedSettingsViewController.m:593` in `-[iTermAdvancedSettingsViewController valueInDictionary:]`: `NSSelectorFromString` on `getter`
- `sources/Settings/iTermAdvancedSettingsViewController.m:594` in `-[iTermAdvancedSettingsViewController valueInDictionary:]`: `performSelector:` on `selector`
- `sources/Settings/iTermAdvancedSettingsViewController.m:603` in `iTermAdvancedSettingsSaveSecureString`: `NSSelectorFromString` on `selectorName`
- `sources/Settings/iTermAdvancedSettingsViewController.m:604` in `iTermAdvancedSettingsSaveSecureString`: `performSelector:withObject:` on `selector`

  **CLOSED.** Getter and setter names come from the setting dictionary keys `kAdvancedSettingGetter` and `kAdvancedSettingSetter`, which only `DEFINE_SECURE_BOILERPLATE` sets (iTermAdvancedSettingsModel.m in the DEFINE_SECURE_BOILERPLATE macro: `object_<name>` and `setFromObject_<CapitalizedName>:`). It is used twice: `DEFINE_SECURE_BOOL(enableSecureKeyboardEntryAutomatically, ...)` and `DEFINE_SECURE_STRING(browserBundleID, ...)`. Reach: `+object_enableSecureKeyboardEntryAutomatically`, `+setFromObject_EnableSecureKeyboardEntryAutomatically:`, `+object_browserBundleID`, `+setFromObject_BrowserBundleID:`.

  Names: `object_enableSecureKeyboardEntryAutomatically`, `setFromObject_EnableSecureKeyboardEntryAutomatically:`, `object_browserBundleID`, `setFromObject_BrowserBundleID:`.

#### `sources/tmux/TmuxController.m`

- `sources/tmux/TmuxController.m:4660` in `-[TmuxController didListWindows:userData:]`: `NSSelectorFromString` on `userData[1]`

  **CLOSED.** `userData[1]` is `NSStringFromSelector(selector)` stored by `-listWindowsInSessionNumber:target:selector:object:` (TmuxController.m in -[TmuxController listWindowsInSessionNumber:target:selector:object:]) and carried through `listWindowsTimerFired:` (internal string round trip). Callers pass `@selector(setWindows:forSession:)` (TmuxDashboardController.m in -[TmuxDashboardController reloadWindows], iTermTmuxWindowCache.m in -[iTermTmuxWindowCache tmuxControllerSessionsDidChange:] and -[iTermTmuxWindowCache tmuxControllerWindowsDidChange:]) and `@selector(didListWindows:forSession:)` (iTermTmuxWindowCache.m in -[iTermTmuxWindowCache tmuxControllerRegistryDidChange:]). No Swift callers (database Swift rows). Reach: `-[TmuxDashboardController setWindows:forSession:]`, `-[iTermTmuxWindowCache setWindows:forSession:]`, `-[iTermTmuxWindowCache didListWindows:forSession:]`.

  Names: `setWindows:forSession:`, `didListWindows:forSession:`.

#### `sources/tmux/TmuxGateway.m`

- `sources/tmux/TmuxGateway.m:581` in `-[TmuxGateway currentCommandSelector]`: `NSSelectorFromString` on `theString`

  **CLOSED.** `currentCommandSelector` converts back the string stored by `-dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:` (TmuxGateway.m in -[TmuxGateway dictionaryForCommand:responseTarget:responseSelector:responseObject:flags:], `NSStringFromSelector`), then `invokeCurrentCallbackWithError:` (TmuxGateway.m in -[TmuxGateway invokeCurrentCallbackWithError:]) calls it with `it_performNonObjectReturningSelector:withObject:withObject:`. The selectors are the `responseSelector:` arguments of `sendCommand:...`, `sendGuardedCommand:...` and `dictionaryForCommand:...`. A `git grep` of every `responseSelector:` argument finds only `@selector`/`#selector` literals, `nil`/`NULL`, and TmuxGateway.m in -[TmuxGateway sendCommand:responseTarget:responseSelector:], -[TmuxGateway sendCommand:responseTarget:responseSelector:responseObject:flags:] and -[TmuxGateway sendGuardedCommand:responseTarget:responseSelector:responseObject:flags:], which forward the parameter. Reach (by that scheme, 68 names): `checkForUTF8Response:`, `didChangeWhetherPaneFloats:request:`, `didFetch:`, `didFetchDefaultTerminal:`, `didFetchNow:completion:`, `didFetchTmuxPid:`, `didGetCurrentWindow:beforeSelecting:`, `didListPanes:forBuriedPanes:`, `didListWindows:userData:`, `didListWindowsSubsequentToSettingLayout:`, `didLoadServerIdentity:`, `didLoadTmuxClientName:`, `didMakeFloatingPane:completion:`, `didPause:panes:`, `didSelectWindow:selection:`, `didSetLayout:`, `didSetLayoutWithMovedDivider:`, `didSplit:state:`, `didSubscribe:handleID:`, `didSwapWindows:`, `dumpHistoryResponse:paneAndAlternate:`, `dumpStateResponse:pane:`, `getAffinitiesResponse:`, `getBuriedIndexesResponse:`, `getHiddenWindowsResponse:`, `getHotkeysResponse:`, `getOriginsResponse:`, `getPaneIDsResponseAndSetHotkeys:`, `getPaneIDsResponseAndSetTabColors:`, `getPendingOutputResponse:pane:`, `getPerTabSettingsResponse:`, `getPerWindowSettingsResponse:`, `getSessionGuidResponse:`, `getTabColorsResponse:`, `getTabGroupParentsResponse:`, `getTabGroupsResponse:`, `getUserVarsResponse:pane:`, `guessVersion18Response:`, `guessVersion21Response:`, `guessVersion22Response:`, `guessVersion23Response:`, `handleDisplayMessageVersion:`, `handleListKeys:`, `handlePingResponse:`, `handleResizeWindowResponse:`, `handleShowBuffer:`, `handleShowSetTitles:`, `handleShowSize:`, `handleStatusIntervalResponse:`, `handleStatusResponse:`, `initialListWindowsResponse:`, `listedWindowsToOpenOne:forWindowIdAndAffinities:`, `listSessionsResponse:`, `listWindowsResponse:`, `newWindowWithAffinityCreated:affinityWindowAndCompletion:`, `parseListWindowsResponseAndUpdateLayouts:`, `phonyCommandDidComplete:`, `printTmuxCommandOutputToScreen:`, `recordPanes:state:`, `requestDidComplete`, `responseForListWindows:toSetPartialOrder:`, `saveWindowOriginsResponse:`, `selector:`, `sendTmuxCommandMethodDidComplete:completion:`, `showWindowOptionsResponse:`, `windowPaneBrokeOutWithWindowId:setAffinityTo:`, `handle:`, `didListClients:completion:`. Swift: `#selector(TmuxGatewayReply.handle(_:))` (TmuxGateway+Replies.swift) and `#selector(didListClients(_:completion:))` (iTermTmuxClientTracker.swift in TmuxClientTracker.updateClients(completion:)). Tests also pass `TmuxTestReply.handle(_:)` and, in Objective-C tests, `recordReply:`, `handleResponse:`, `handleOtherReply:` and `handleGuardReply:` (ModernTests only, not listed as names). Rechecked against the database: the `@selector` arguments of all 145 sends of the four selectors and the Swift calls (TmuxGateway+Replies.swift in TmuxGateway.send(_:reply:), TmuxGateway.sendList(_:replies:) and TmuxGateway.sendGuardedForBranchReply(_:reply:), iTermTmuxClientTracker.swift in TmuxClientTracker.updateClients(completion:)) give exactly this set plus the test names. Regenerate with `git grep -h -o 'responseSelector: *@selector([^)]*)' -- sources` plus the Swift `#selector` form.

  Names: `checkForUTF8Response:`, `didChangeWhetherPaneFloats:request:`, `didFetch:`, `didFetchDefaultTerminal:`, `didFetchNow:completion:`, `didFetchTmuxPid:`, `didGetCurrentWindow:beforeSelecting:`, `didListPanes:forBuriedPanes:`, `didListWindows:userData:`, `didListWindowsSubsequentToSettingLayout:`, `didLoadServerIdentity:`, `didLoadTmuxClientName:`, `didMakeFloatingPane:completion:`, `didPause:panes:`, `didSelectWindow:selection:`, `didSetLayout:`, `didSetLayoutWithMovedDivider:`, `didSplit:state:`, `didSubscribe:handleID:`, `didSwapWindows:`, `dumpHistoryResponse:paneAndAlternate:`, `dumpStateResponse:pane:`, `getAffinitiesResponse:`, `getBuriedIndexesResponse:`, `getHiddenWindowsResponse:`, `getHotkeysResponse:`, `getOriginsResponse:`, `getPaneIDsResponseAndSetHotkeys:`, `getPaneIDsResponseAndSetTabColors:`, `getPendingOutputResponse:pane:`, `getPerTabSettingsResponse:`, `getPerWindowSettingsResponse:`, `getSessionGuidResponse:`, `getTabColorsResponse:`, `getTabGroupParentsResponse:`, `getTabGroupsResponse:`, `getUserVarsResponse:pane:`, `guessVersion18Response:`, `guessVersion21Response:`, `guessVersion22Response:`, `guessVersion23Response:`, `handleDisplayMessageVersion:`, `handleListKeys:`, `handlePingResponse:`, `handleResizeWindowResponse:`, `handleShowBuffer:`, `handleShowSetTitles:`, `handleShowSize:`, `handleStatusIntervalResponse:`, `handleStatusResponse:`, `initialListWindowsResponse:`, `listedWindowsToOpenOne:forWindowIdAndAffinities:`, `listSessionsResponse:`, `listWindowsResponse:`, `newWindowWithAffinityCreated:affinityWindowAndCompletion:`, `parseListWindowsResponseAndUpdateLayouts:`, `phonyCommandDidComplete:`, `printTmuxCommandOutputToScreen:`, `recordPanes:state:`, `requestDidComplete`, `responseForListWindows:toSetPartialOrder:`, `saveWindowOriginsResponse:`, `selector:`, `sendTmuxCommandMethodDidComplete:completion:`, `showWindowOptionsResponse:`, `windowPaneBrokeOutWithWindowId:setAffinityTo:`, `handle:`, `didListClients:completion:`.

#### `sources/tmux/TmuxStateParser.m`

- `sources/tmux/TmuxStateParser.m:167` in `+[TmuxStateParser dictionaryForState:workAroundTabBug:]`: `NSSelectorFromString` on `converter`
- `sources/tmux/TmuxStateParser.m:168` in `+[TmuxStateParser dictionaryForState:workAroundTabBug:]`: `performSelector:` on `sel`

  **CLOSED.** `converter` is looked up in the `fieldTypes` dictionary literal in the same method; keys come from tmux output (external), but only keys in the table produce a selector. Reach: `it_numberValue`, `it_intlistValue`, `it_paneIdNumberValue` (NSString category in TmuxStateParser.m).

  Names: `it_numberValue`, `it_intlistValue`, `it_paneIdNumberValue`.

### Calling by selector

#### `ThirdParty/PSMTabBarControl/source/PSMTabBarCell.m`

- `ThirdParty/PSMTabBarControl/source/PSMTabBarCell.m:166` in `-[PSMWeakTimer timerDidFire:]`: `methodForSelector:` on `_selector`

  **GENERIC.** Private weak timer in PSMTabBarCell.m. One caller: `-[PSMTabBarCell reallySetStringValue:]` (PSMTabBarCell.m in -[PSMTabBarCell reallySetStringValue:]) passes `@selector(updateStringValue:)`, static. Reach: `-[PSMTabBarCell updateStringValue:]`.

  Names: `updateStringValue:`.

#### `sources/API/iTermAPIHelper.m`

- `sources/API/iTermAPIHelper.m:3698` in `-[iTermAPIHelper apiServerMenuItem:handler:]`: `sendAction:to:from:` on `menuItem.action`

  **OPEN-EXTERNAL.** Python API `MenuItemRequest`: the client names a main-menu item by identifier; the action of that live `NSMenuItem` is sent. Allowlist: only items found in `[NSApp mainMenu]` by `menuItemWithIdentifier:inMenu:` and enabled after `[menu update]`. Reach: every action selector of a main-menu item (MainMenu.xib plus menu items built in code); enumerated by the entry-point census and xib binding tests, not here.

  Names: none.

#### `sources/AppKit/iTermApplicationDelegate.m`

- `sources/AppKit/iTermApplicationDelegate.m:3428` in `-[iTermApplicationDelegate performUndoRedoSelector:sender:]`: `performSelector:withObject:` on `selector`
- `sources/AppKit/iTermApplicationDelegate.m:3449` in `-[iTermApplicationDelegate responderForUndoRedoSelector:menuItem:]`: `respondsToSelector:` on `selector`

  **CLOSED.** `performUndoRedoSelector:sender:` is called only with `@selector(undo:)` and `@selector(redo:)` (iTermApplicationDelegate.m in -[iTermApplicationDelegate performUndo:] and -[iTermApplicationDelegate performRedo:]); `responderForUndoRedoSelector:menuItem:` also from `validateUndoRedoMenuItem:selector:allowMigration:` with the same two selectors. Reach: `undo:` and `redo:` on any responder in the key window chain that also conforms to NSMenuItemValidation (for example settings window controllers with private undo managers).

  Names: `undo:`, `redo:`.

#### `sources/Categories/NSMenu+iTerm.m`

- `sources/Categories/NSMenu+iTerm.m:64` in `-[NSMenu(iTermAdditions) it_selectMenuItemWithTitle:identifier:]`: `sendAction:to:from:` on `[target action]`

  **OPEN-EXTERNAL.** Fires a main-menu item chosen by title and identifier. Callers: `+[PTYSession selectMenuItem:]` (PTYSession.m in +[PTYSession selectMenuItem:]), reached from key binding actions of type Select Menu Item (PTYSession.m in +[PTYSession performKeyBindingAction:event:] and -[PTYSession reallyPerformKeyBindingAction:event:]; the parameter comes from the user's key mappings in preferences), `-[PTYSession textViewSelectMenuItemWithIdentifier:title:]` (PTYSession.m in -[PTYSession textViewSelectMenuItemWithIdentifier:title:], called from `-[PTYTextView(PointerDelegate) selectMenuItemWithIdentifier:title:event:]`, PTYTextView.m in -[PTYTextView(PointerDelegate) selectMenuItemWithIdentifier:title:event:], a pointer action from the user's pointer bindings), and in Swift `iTermBrowserPointerActionPerformer.selectMenuItem(withIdentifier:title:event:)` (iTermBrowserPointerActionPerformer.swift in iTermBrowserPointerActionPerformer.selectMenuItem(withIdentifier:title:event:), `NSApp.mainMenu?.it_selectItem(withTitle:identifier:)`, the Swift name of the same method; the browser's pointer actions). Allowlist: only items that exist in `NSApp.mainMenu`, with a recursion guard. Reach: every main-menu action selector (MainMenu.xib plus code-built items); see the entry-point census.

  Names: none.

#### `sources/Categories/NSObject+iTerm.m`

- `sources/Categories/NSObject+iTerm.m:268` in `-[NSObject(iTerm) it_performNonObjectReturningSelector:withObject:]`: `methodForSelector:` on `selector`
- `sources/Categories/NSObject+iTerm.m:274` in `-[NSObject(iTerm) it_performNonObjectReturningSelector:withObject:withObject:]`: `methodForSelector:` on `selector`
- `sources/Categories/NSObject+iTerm.m:280` in `-[NSObject(iTerm) it_performAutoreleasedObjectReturningSelector:withObject:]`: `methodForSelector:` on `selector`

  **GENERIC.** Category helpers that call `methodForSelector:` on a selector argument. Callers are listed below as separate entries under "Callers of generic helpers"; static callers: PTYSession.m in -[PTYSession updateKeyMapper] (`setDelegate:`), PasteboardHistory.m in -[PasteboardHistoryWindowController rowSelected:] (`paste:`), iTermApplicationDelegate.m in -[iTermApplicationDelegate toggleTriggerEnabled:] (`_cmd`, `toggleTriggerEnabled:`). `it_performAutoreleasedObjectReturningSelector:withObject:` has no callers. A three-object variant, `it_performNonObjectReturningSelector:withObject:object:object:`, lost its only caller, `-[iTermThread newCallbackWithWeakTarget:selector:userInfo:]`, when that was deleted as dead code on 2026-11-20, and was itself deleted the same day (unit `dead-code-followup`). Rechecked with the database's send rows (every send of these selectors) and its Swift rows (no Swift call of any of them).

  Names: `setDelegate:`, `paste:`, `toggleTriggerEnabled:`.

#### `sources/Categories/NSTimer+iTerm.m`

- `sources/Categories/NSTimer+iTerm.m:54` in `-[iTermTimerProxy timerDidFire:]`: `methodForSelector:` on `self.selector`
- `sources/Categories/NSTimer+iTerm.m:75` in `+[NSTimer(iTerm) it_weakTimerWithTimeInterval:target:selector:userInfo:repeats:]`: `setSelector:` on `selector`
- `sources/Categories/NSTimer+iTerm.m:88` in `+[NSTimer(iTerm) it_scheduledWeakTimerWithTimeInterval:target:selector:userInfo:repeats:]`: `setSelector:` on `aSelector`

  **GENERIC.** `iTermTimerProxy` calls the selector given to `+[NSTimer it_weakTimerWithTimeInterval:...]` or `+[NSTimer it_scheduledWeakTimerWithTimeInterval:...]`. Every caller passes `@selector`: iTermGlobalSearchEngine.m in -[iTermGlobalSearchEngine initWithQuery:sessions:mode:handler:] `searchMore:`, iTermRateLimitedUpdate.m in -[iTermRateLimitedUpdate scheduleTimerAfterDelay:] `performBlockIfNeeded:`, iTermUpdateCadenceController.m in -[iTermUpdateCadenceController setTimerUpdateCadence:liveResizing:force:] `updateDisplay`, ProfilesGeneralPreferencesViewController.m in -[ProfilesGeneralPreferencesViewController downloadBrowserPlugin:] `updateDownloadBrowserPluginButtonHidden`, iTermStatusBarContainerView.m in -[iTermStatusBarContainerView initWithComponent:] `reevaluateTimer:`, iTermGitPoller.m in -[iTermGitPoller startTimer] `poll`, iTermTmuxBufferSizeMonitor.m in -[iTermTmuxBufferSizeMonitor initWithController:pauseAge:] and iTermTmuxOptionMonitor.m in -[iTermTmuxOptionMonitor startTimer] `update:`, iTermMTKView.swift in iTermMTKView.it_schedule() `#selector(it_redrawPeriodically(_:))` (Swift name `Timer.it_scheduledWeakTimer(withTimeInterval:target:selector:userInfo:repeats:)`). No dynamic callers.

  Names: `searchMore:`, `performBlockIfNeeded:`, `updateDisplay`, `updateDownloadBrowserPluginButtonHidden`, `reevaluateTimer:`, `poll`, `update:`, `it_redrawPeriodically:`.

#### `sources/FileTransfer/FileTransferManager.m`

- `sources/FileTransfer/FileTransferManager.m:254` in `-[FileTransferManager performMenuActionOnRunLoop:inModes:]`: `performSelector:withObject:afterDelay:inModes:` on `selector`

  **GENERIC.** `performMenuActionOnRunLoop:inModes:` callers (database send rows) pass `@selector(pressDownloadsMenu)` (FileTransferManager.m in -[FileTransferManager openDownloadsMenu]), `@selector(pressUploadsMenu)` (-[FileTransferManager openUploadsMenu]) and `@selector(refreshMenuBarNow)` (-[FileTransferManager refreshMenuBarIfNeeded]). No Swift callers.

  Names: `pressDownloadsMenu`, `pressUploadsMenu`, `refreshMenuBarNow`.

#### `sources/Hotkey/iTermCarbonHotKeyController.m`

- `sources/Hotkey/iTermCarbonHotKeyController.m:371` in `-[iTermCarbonHotKeyController handleEvent:]`: `performSelector:withObject:withObject:` on `hotkey.selector`

  **CLOSED.** `hotkey.selector` is the selector given to `-[iTermCarbonHotKeyController registerShortcut:...selector:...]`. Callers pass `@selector(carbonHotkeyPressed:siblings:)` (iTermBaseHotKey.m in -[iTermBaseHotKey registerShortcut:]), `@selector(hotkeyPressed:siblings:)` (iTermSessionHotkeyController.m in -[iTermSessionHotkeyRegistration initWithShortcut:]), `@selector(dismissByKeyboard:)` (iTermTipWindowController.m in -[iTermTipWindowController showTipWindow]), and from Swift, where the method is imported as `register(_:target:selector:userData:)`, `#selector(hotKeyPressed(_:siblings:))` (iTermOpenQuicklyHotKeyProvider.swift in OpenQuicklyHotKeyProvider.invalidate(); the method is `@objc(hotKeyPressed:siblings:)`, capital K, a different selector from `hotkeyPressed:siblings:`). Reach: those four selectors.

  Names: `carbonHotkeyPressed:siblings:`, `hotkeyPressed:siblings:`, `dismissByKeyboard:`, `hotKeyPressed:siblings:`.

#### `sources/Infrastructure/iTermRateLimitedUpdate.m`

- `sources/Infrastructure/iTermRateLimitedUpdate.m:140` in `-[iTermRateLimitedUpdate performRateLimitedSelector:onTarget:withObject:]`: `methodForSelector:` on `selector`

  **GENERIC.** `-[iTermRateLimitedUpdate performRateLimitedSelector:onTarget:withObject:]`. Callers all pass `@selector`: iTermProcessCache.m in -[iTermProcessCache setNeedsUpdate:] and -[iTermProcessCache processMonitor:didChangeFlags:] `updateIfNeeded`, iTermWorkingDirectoryPoller.m in -[iTermWorkingDirectoryPoller didReceiveLineFeed] `maybePollForWorkingDirectory`, ProfilesGeneralPreferencesViewController.m in -[ProfilesGeneralPreferencesViewController sessionNameDidChange] `postUpdateSessionNameNotification`, iTermSearchResultsMinimapView.m in -[iTermBaseMinimapView invalidate] `postInvalidateNotification`. No Swift callers (database Swift rows).

  Names: `updateIfNeeded`, `maybePollForWorkingDirectory`, `postUpdateSessionNameNotification`, `postInvalidateNotification`.

#### `sources/MousePointer/ThreeFingerTapGestureRecognizer.m`

- `sources/MousePointer/ThreeFingerTapGestureRecognizer.m:78` in `-[ThreeFingerTapGestureRecognizer touchesEndedWithEvent:]`: `performSelector:withObject:` on `selector_`

  **CLOSED.** `selector_` from `initWithTarget:selector:`; callers pass `@selector(threeFingerTap:)` (EventMonitorView.m in -[EventMonitorView awakeFromNib], PTYTextView.m in -[PTYTextView initWithFrame:]) and, from Swift, `#selector(threeFingerTap(_:))` (iTermBrowserWebView.swift in iTermBrowserWebView.init(frame:configuration:pointerController:), `ThreeFingerTapGestureRecognizer(target:selector:)`).

  Names: `threeFingerTap:`.

#### `sources/OpenQuickly/iTermOpenQuicklyWindowController.m`

- `sources/OpenQuickly/iTermOpenQuicklyWindowController.m:538` in `-[iTermOpenQuicklyWindowController openSelectedRow]`: `sendAction:to:from:` on `item.menuItem.action`

  **OPEN-INTERNAL.** Open Quickly lists the items of `[NSApp mainMenu]` (iTermOpenQuicklyModel.m in -[iTermOpenQuicklyModel addMenuItemsToItems:withMatcher:]) and sends the chosen item's action. The user chooses among live menu items; no name comes from outside. Reach: every main-menu action selector (MainMenu.xib plus code-built items), enumerated by the entry-point census and xib binding tests rather than here; a runtime walk of the main menu would enumerate it.

  Names: none.

#### `sources/PTYSession/PTYSession.m`

- `sources/PTYSession/PTYSession.m:5545` in `+[PTYSession _recursiveSelectMenuWithSelector:inMenu:]`: `sendAction:to:from:` on `[item action]`

  **CLOSED.** `+_recursiveSelectMenuWithSelector:inMenu:` is called only from `+selectMenuItemWithSelector:` (PTYSession.m in +[PTYSession selectMenuItemWithSelector:]), whose callers pass `@selector(undo:)` (PTYSession.m in +[PTYSession performKeyBindingAction:event:] and -[PTYSession reallyPerformKeyBindingAction:event:]). Reach: the main-menu item whose action is `undo:`.

  Names: `undo:`.

- `sources/PTYSession/PTYSession.m:26735` in `-[PTYSession composerManager:forwardMenuItem:]`: `performSelector:withObject:` on `menuItem.action`

  **CLOSED.** The menu item is the sender of `copy:`, `copyWithStyles:` or `copyWithControlSequences:` on `ComposerTextView` (ComposerTextView.swift in ComposerTextView.copy(_:), ComposerTextView.copyWithStyles(_:) and ComposerTextView.copyWithControlSequences(_:)), forwarded through `iTermMinimalComposerViewController` and `iTermComposerManager`. Its action is the method that received it. Reach on `PTYTextView`: `copy:`, `copyWithStyles:`, `copyWithControlSequences:`.

  Names: `copy:`, `copyWithStyles:`, `copyWithControlSequences:`.

#### `sources/Pasting/iTermPasteHelper.m`

- `sources/Pasting/iTermPasteHelper.m:1117` in `-[iTermPasteHelper scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:]`: `scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:` on `aSelector`

  **GENERIC.** Test seam wrapping `+[NSTimer scheduledTimerWithTimeInterval:...]`. Callers iTermPasteHelper.m in -[iTermPasteHelper scheduleNextPasteForCurrentPasteContext] and -[iTermPasteHelper pasteLiteralEventUnconditionallyImmediately:] pass `@selector(pasteNextChunkAndScheduleTimer)`.

  Names: `pasteNextChunkAndScheduleTimer`.

#### `sources/iTermController/iTermController.m`

- `sources/iTermController/iTermController.m:918` in `-[iTermController addBookmarksToMenu:supermenu:withSelector:openAllSelector:startingAt:]`: `setSelector:` on `selector`

  **GENERIC.** `addBookmarksToMenu:supermenu:withSelector:openAllSelector:startingAt:` callers: iTermApplicationDelegate.m in -[iTermApplicationDelegate newSessionMenu:title:selector:openAllSelector:] (from `newSessionMenu:...`, whose callers in -[iTermApplicationDelegate applicationDockMenu:] pass `newSessionInWindowAtIndex:`/`newSessionsInNewWindow:` and `newSessionInTabAtIndex:`/`newSessionsInWindow:`), PseudoTerminal.m in -[PseudoTerminal menuForEvent:menu:] (same selectors). Reach: those four.

  Names: `newSessionInWindowAtIndex:`, `newSessionInTabAtIndex:`, `newSessionsInWindow:`, `newSessionsInNewWindow:`.

#### `sources/tmux/TmuxLayoutParser.m`

- `sources/tmux/TmuxLayoutParser.m:292` in `-[TmuxLayoutParser depthFirstSearchParseTree:callingSelector:onTarget:withObject:]`: `performSelector:withObject:withObject:` on `selector`
- `sources/tmux/TmuxLayoutParser.m:305` in `-[TmuxLayoutParser depthFirstSearchParseTree:callingSelector:onTarget:withObject:]`: `performSelector:withObject:withObject:` on `selector`

  **GENERIC.** `depthFirstSearchParseTree:callingSelector:onTarget:withObject:`. Callers pass `@selector`: TmuxLayoutParser.m in -[TmuxLayoutParser windowPane:inParseTree:] `searchParseTree:forWindowPane:`, TmuxWindowOpener.m in -[TmuxWindowOpener openWindows:] `appendRequestsForNode:toArray:`, TmuxWindowOpener.m in -[TmuxWindowOpener decorateParseTree:] `decorateWindowPane:`.

  Names: `searchParseTree:forWindowPane:`, `appendRequestsForNode:toArray:`, `decorateWindowPane:`.

### Responds-to checks and forwarding

#### `sources/AppKit/iTermApplicationDelegate.m`

- `sources/AppKit/iTermApplicationDelegate.m:647` in `-[iTermApplicationDelegate firstResponderForMenuItem:]`: `respondsToSelector:` on `menuItem.action`

  **CLOSED.** Only caller is `-[iTermApplicationDelegate toggleTriggerEnabled:]` (iTermApplicationDelegate.m in -[iTermApplicationDelegate toggleTriggerEnabled:]), whose sender is the menu item built at iTermApplicationDelegate.m in -[iTermApplicationDelegate menuNeedsUpdate:] with `@selector(toggleTriggerEnabled:)`. Reach: `toggleTriggerEnabled:` on the first responder chain (implemented by `PseudoTerminal`, declared in NSResponder+iTerm.h).

  Names: `toggleTriggerEnabled:`.

#### `sources/ExternalSessionState/iTermColorMap.m`

- `sources/ExternalSessionState/iTermColorMap.m:863` in `-[iTermColorMapSanitizingAdapter forwardingTargetForSelector:]`: `respondsToSelector:` on `aSelector`
- `sources/ExternalSessionState/iTermColorMap.m:870` in `-[iTermColorMapSanitizingAdapter respondsToSelector:]`: `respondsToSelector:` on `aSelector`
- `sources/ExternalSessionState/iTermColorMap.m:870` in `-[iTermColorMapSanitizingAdapter respondsToSelector:]`: `respondsToSelector:` on `aSelector`
- `sources/ExternalSessionState/iTermColorMap.m:874` in `-[iTermColorMapSanitizingAdapter methodSignatureForSelector:]`: `methodSignatureForSelector:` on `aSelector`
- `sources/ExternalSessionState/iTermColorMap.m:878` in `-[iTermColorMapSanitizingAdapter forwardInvocation:]`: `respondsToSelector:` on `anInvocation.selector`

  **GENERIC.** `iTermColorMapSanitizingAdapter` is an NSProxy (declared `NSProxy<iTermColorMapReading>`) that forwards to `_impl` or `_source`. The selector is whatever is sent to the proxy; senders are compiler-visible sends on `id<iTermColorMapReading>`. Reach: methods of `iTermColorMapReading` on `iTermColorMapSanitizingAdapterImpl` and `iTermColorMap`. The proxy must stay Objective-C ([hidden-callers.md section 5](hidden-callers.md)); its targets keep their selectors and type encodings.

  Names: none.

#### `sources/Infrastructure/Views/iTermFocusReportingTextField.m`

- `sources/Infrastructure/Views/iTermFocusReportingTextField.m:40` in `-[iTermTextView validateMenuItem:]`: `respondsToSelector:` on `menuItem.action`

  **CLOSED.** Guarded by `menuItem.action == @selector(performFindPanelAction:)`. Reach: `performFindPanelAction:` and `validateMenuItem:` on responders after the text view.

  Names: `performFindPanelAction:`, `validateMenuItem:`.

#### `sources/Infrastructure/Views/iTermKeyboardNavigatableTableView.m`

- `sources/Infrastructure/Views/iTermKeyboardNavigatableTableView.m:25` in `-[iTermKeyboardNavigatableTableView respondsToSelector:]`: `respondsToSelector:` on `aSelector`

  **CLOSED.** Override of `respondsToSelector:` that answers NO for `@selector(selectAll:)` and defers to super otherwise. Reaches nothing by name; renaming `selectAll:` handling in a port must keep the override.

  Names: `selectAll:`.

#### `sources/Infrastructure/iTermWeakProxy.m`

- `sources/Infrastructure/iTermWeakProxy.m:27` in `-[iTermWeakProxy methodSignatureForSelector:]`: `methodSignatureForSelector:` on `sel`

  **GENERIC.** `iTermWeakProxy` NSProxy: forwards every message to the weakly held object. Senders are compiler-visible sends on the proxy's generic `ObjectType`.

  Names: none.

#### `sources/Infrastructure/iTermWeakReference.m`

- `sources/Infrastructure/iTermWeakReference.m:45` in `-[iTermWeakReference respondsToSelector:]`: `respondsToSelector:` on `aSelector`
- `sources/Infrastructure/iTermWeakReference.m:59` in `-[iTermWeakReference methodSignatureForSelector:]`: `methodSignatureForSelector:` on `selector`
- `sources/Infrastructure/iTermWeakReference.m:61` in `-[iTermWeakReference methodSignatureForSelector:]`: `instanceMethodSignatureForSelector:` on `selector`

  **GENERIC.** `iTermWeakReference` NSProxy: forwards to the weakly held object; `respondsToSelector:` special-cases `weaklyReferencedObject` by name (`NSStringFromSelector` comparison). Senders are compiler-visible sends on the generic `ObjectType`.

  Names: `weaklyReferencedObject`.

#### `sources/SearchingFiltering/iTermFindDriver.m`

- `sources/SearchingFiltering/iTermFindDriver.m:761` in `-[iTermFindDriver doCommandBySelector:]`: `respondsToSelector:` on `selector`

  **OPEN-EXTERNAL.** `-[iTermFindDriver doCommandBySelector:]` is called from `-[iTermDropDownFindViewController control:textView:doCommandBySelector:]` (iTermDropDownFindViewController.m in -[iTermDropDownFindViewController control:textView:doCommandBySelector:]) and `-[iTermMiniSearchFieldViewController control:textView:doCommandBySelector:]` (iTermMiniSearchFieldViewController.m in -[iTermMiniSearchFieldViewController control:textView:doCommandBySelector:], the status bar search field) with the command selector of the Cocoa text system, then performs it on self if `respondsToSelector:` (`it_performNonObjectReturningSelector:withObject:`). Input: the key binding dictionaries of the Cocoa text system (system `StandardKeyBinding.dict` and the user's `~/Library/KeyBindings/DefaultKeyBinding.dict`). Check: `respondsToSelector:` only. Intended reach: `moveDown:` (iTermFindDriver.m in -[iTermFindDriver moveDown:]); any other one-argument method of `iTermFindDriver` whose name a key binding names is also reached.

  Names: `moveDown:`.

#### `sources/ShellIntegration/iTermShellHistoryController.m`

- `sources/ShellIntegration/iTermShellHistoryController.m:365` in `+[iTermShellHistoryController showInformationalMessageInWindow:]`: `respondsToSelector:` on `selector`
- `sources/ShellIntegration/iTermShellHistoryController.m:402` in `+[iTermShellHistoryController showInformationalMessageInWindow:]`: `performSelector:withObject:` on `selector`

  **CLOSED.** `selector` is the local `@selector(installShellIntegration:)` (iTermShellHistoryController.m in +[iTermShellHistoryController showInformationalMessageInWindow:]).

  Names: `installShellIntegration:`.

#### `sources/StatusBar/Setup/Knobs/iTermStatusBarKnobNumericViewController.m`

- `sources/StatusBar/Setup/Knobs/iTermStatusBarKnobNumericViewController.m:88` in `-[iTermStatusBarKnobNumericViewController control:textView:doCommandBySelector:]`: `respondsToSelector:` on `commandSelector`

  **OPEN-EXTERNAL.** NSControl delegate `control:textView:doCommandBySelector:`; performs the command selector on self if `respondsToSelector:`. Input: Cocoa text system key bindings (system and user `DefaultKeyBinding.dict`). Check: `respondsToSelector:` only. Intended reach: `insertNewline:`.

  Names: `insertNewline:`.

#### `sources/StatusBar/Setup/Knobs/iTermStatusBarKnobTextViewController.m`

- `sources/StatusBar/Setup/Knobs/iTermStatusBarKnobTextViewController.m:124` in `-[iTermStatusBarKnobTextViewController control:textView:doCommandBySelector:]`: `respondsToSelector:` on `commandSelector`

  **OPEN-EXTERNAL.** Same as the numeric knob. Intended reach: `insertNewline:`.

  Names: `insertNewline:`.

#### `sources/StatusBar/Setup/iTermStatusBarSetupDestinationCollectionViewController.m`

- `sources/StatusBar/Setup/iTermStatusBarSetupDestinationCollectionViewController.m:53` in `-[iTermStatusBarSetupDestinationCollectionView doCommandBySelector:]`: `respondsToSelector:` on `selector`

  **OPEN-EXTERNAL.** Override of `-[NSResponder doCommandBySelector:]` on the collection view; forwards the key-binding command selector to its delegate if the delegate `respondsToSelector:`. Input: Cocoa text system key bindings. Check: `respondsToSelector:` only. Intended reach: `deleteBackward:` on the delegate (`iTermStatusBarSetupDestinationCollectionViewController`).

  Names: `deleteBackward:`.

#### `sources/Toolbelt/CapturedOutput/ToolCapturedOutputView.m`

- `sources/Toolbelt/CapturedOutput/ToolCapturedOutputView.m:396` in `-[ToolCapturedOutputView validateMenuItem:]`: `respondsToSelector:` on `[item action]`

  **CLOSED.** `validateMenuItem:` answers whether self implements the item's action. Its context menu (ToolCapturedOutputView.m in -[ToolCapturedOutputView initWithFrame:]) has `toggleCheckmark:`. Any other menu item validated against this view is enabled only if the class implements its action, so adding or removing a method with a menu action's name changes enablement.

  Names: `toggleCheckmark:`.

#### `sources/Toolbelt/ToolDirectoriesView.m`

- `sources/Toolbelt/ToolDirectoriesView.m:333` in `-[ToolDirectoriesView validateMenuItem:]`: `respondsToSelector:` on `[item action]`

  **CLOSED.** Same pattern; context menu (ToolDirectoriesView.m in -[ToolDirectoriesView initWithFrame:]) has `toggleStar:`.

  Names: `toggleStar:`.

#### `sources/Toolbelt/ToolPasteHistory.m`

- `sources/Toolbelt/ToolPasteHistory.m:125` in `-[ToolPasteHistory validateMenuItem:]`: `respondsToSelector:` on `[item action]`

  **CLOSED.** Same pattern; context menu (ToolPasteHistory.m in -[ToolPasteHistory initWithFrame:]) has `copySelection:` and `openInAdvancedPaste:`.

  Names: `copySelection:`, `openInAdvancedPaste:`.

#### `sources/VT100Screen/VT100ScreenStateSanitizingAdapter.m`

- `sources/VT100Screen/VT100ScreenStateSanitizingAdapter.m:108` in `-[VT100ScreenStateSanitizingAdapter forwardingTargetForSelector:]`: `respondsToSelector:` on `aSelector`
- `sources/VT100Screen/VT100ScreenStateSanitizingAdapter.m:115` in `-[VT100ScreenStateSanitizingAdapter respondsToSelector:]`: `respondsToSelector:` on `aSelector`
- `sources/VT100Screen/VT100ScreenStateSanitizingAdapter.m:115` in `-[VT100ScreenStateSanitizingAdapter respondsToSelector:]`: `respondsToSelector:` on `aSelector`
- `sources/VT100Screen/VT100ScreenStateSanitizingAdapter.m:119` in `-[VT100ScreenStateSanitizingAdapter methodSignatureForSelector:]`: `methodSignatureForSelector:` on `aSelector`
- `sources/VT100Screen/VT100ScreenStateSanitizingAdapter.m:123` in `-[VT100ScreenStateSanitizingAdapter forwardInvocation:]`: `respondsToSelector:` on `anInvocation.selector`

  **GENERIC.** `VT100ScreenStateSanitizingAdapter` is an NSProxy, cast to `VT100ScreenState *` at VT100ScreenMutableState.m in -[VT100ScreenMutableState initWithSideEffectPerformer:queue:ownsQueue:], forwarding to `_impl` or `_impl.source`. Senders are compiler-visible sends on `VT100ScreenState`. Reach: methods of `VT100ScreenState` and `VT100ScreenStateSanitizingAdapterImpl`. Same rule as the color map adapter.

  Names: none.

### Target-action (menu items and controls)

#### `sources/ContextMenu/iTermContextMenuUtilities.m`

- `sources/ContextMenu/iTermContextMenuUtilities.m:360` in `+[iTermContextMenuUtilities addMenuItemForBase64Encoded:menu:index:selector:target:]`: `setAction:` on `selector`
- `sources/ContextMenu/iTermContextMenuUtilities.m:421` in `+[iTermContextMenuUtilities addMenuItemsForNumericConversions:menu:index:selector:target:]`: `setAction:` on `selector`
- `sources/ContextMenu/iTermContextMenuUtilities.m:430` in `+[iTermContextMenuUtilities addMenuItemsForNumericConversions:menu:index:selector:target:]`: `setAction:` on `selector`
- `sources/ContextMenu/iTermContextMenuUtilities.m:439` in `+[iTermContextMenuUtilities addMenuItemsForNumericConversions:menu:index:selector:target:]`: `setAction:` on `selector`
- `sources/ContextMenu/iTermContextMenuUtilities.m:448` in `+[iTermContextMenuUtilities addMenuItemsForNumericConversions:menu:index:selector:target:]`: `setAction:` on `selector`
- `sources/ContextMenu/iTermContextMenuUtilities.m:458` in `+[iTermContextMenuUtilities addMenuItemsForNumericConversions:menu:index:selector:target:]`: `setAction:` on `selector`
- `sources/ContextMenu/iTermContextMenuUtilities.m:490` in `+[iTermContextMenuUtilities addMenuItemsToCopyBase64:menu:index:selectorForString:selectorForData:target:]`: `setAction:` on `selectorForData`
- `sources/ContextMenu/iTermContextMenuUtilities.m:500` in `+[iTermContextMenuUtilities addMenuItemsToCopyBase64:menu:index:selectorForString:selectorForData:target:]`: `setAction:` on `selectorForString`

  **GENERIC.** Menu builders taking the action as a parameter. Callers pass static selectors: iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] (`copyData:`, `copyString:`) and iTermBrowserContextMenuHelper.swift in iTermBrowserContextMenuHelper.decorate(menu:event:) (`#selector(copyData(_:))`, `#selector(copyString(_:))`; Swift names `addMenuItem(forBase64Encoded:...)`, `addMenuItems(forNumericConversions:...)`, `addMenuItems(toCopyBase64:...)`).

  Names: `copyData:`, `copyString:`.

#### `sources/ContextMenu/iTermTextViewContextMenuHelper.m`

- `sources/ContextMenu/iTermTextViewContextMenuHelper.m:444` in `-[iTermTextViewContextMenuHelper menuAtCoord:]`: `initWithTitle:action:keyEquivalent:` on `NSSelectorFromString(entryDict[@"selector"])`
- `sources/ContextMenu/iTermTextViewContextMenuHelper.m:445` in `-[iTermTextViewContextMenuHelper menuAtCoord:]`: `NSSelectorFromString` on `entryDict[@"selector"]`

  **CLOSED.** `entryDict[@"selector"]` comes from dictionary literals a few lines above in the same method, each built with `NSStringFromSelector(@selector(...))`. Reach: `saveImageAs:`, `copyImage:`, `openImage:`, `inspectImage:`, `togglePauseAnimatingImage:` on `iTermTextViewContextMenuHelper` (target is `self`).

  Names: `saveImageAs:`, `copyImage:`, `openImage:`, `inspectImage:`, `togglePauseAnimatingImage:`.

- `sources/ContextMenu/iTermTextViewContextMenuHelper.m:563` in `-[iTermTextViewContextMenuHelper menuAtCoord:]`: `addItemWithTitle:action:keyEquivalent:` on `selector`

  **CLOSED.** Local block `add(title, selector)`; every call passes `@selector(...)` (iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper menuAtCoord:] and the file's imports calls). No string-built selectors. Reach: `addNote:`, `addTrigger:`, `bringFloatingPaneToFrontFromContextMenu:`, `browse:`, `bury:`, `clearTextViewBuffer:`, `closeTextViewSession:`, `dockFloatingPaneFromContextMenu:`, `downloadWithSCP:`, `editTextViewSession:`, `mail:`, `movePane:`, `moveSessionToFloatingPaneFromContextMenu:`, `openURLInFloatingPane:`, `openURLInHorizontalSplitPane:`, `openURLInVerticalSplitPane:`, `quickLook:`, `restartSession:`, `saveSelectionAsSnippet:`, `searchInBrowser:`, `sendFloatingPaneToBackFromContextMenu:`, `sendSelection:`, `showNotes:`, `splitTextViewHorizontally:`, `splitTextViewVertically:`, `stopCoprocess:`, `swapSessions:`, `toggleBroadcastingInput:`.

  Names: `addNote:`, `addTrigger:`, `bringFloatingPaneToFrontFromContextMenu:`, `browse:`, `bury:`, `clearTextViewBuffer:`, `closeTextViewSession:`, `dockFloatingPaneFromContextMenu:`, `downloadWithSCP:`, `editTextViewSession:`, `mail:`, `movePane:`, `moveSessionToFloatingPaneFromContextMenu:`, `openURLInFloatingPane:`, `openURLInHorizontalSplitPane:`, `openURLInVerticalSplitPane:`, `quickLook:`, `restartSession:`, `saveSelectionAsSnippet:`, `searchInBrowser:`, `sendFloatingPaneToBackFromContextMenu:`, `sendSelection:`, `showNotes:`, `splitTextViewHorizontally:`, `splitTextViewVertically:`, `stopCoprocess:`, `swapSessions:`, `toggleBroadcastingInput:`.

- `sources/ContextMenu/iTermTextViewContextMenuHelper.m:811` in `-[iTermTextViewContextMenuHelper menuAtCoord:]`: `addItemWithTitle:action:keyEquivalent:` on `terminalStateDecls[i].action`
- `sources/ContextMenu/iTermTextViewContextMenuHelper.m:839` in `-[iTermTextViewContextMenuHelper menuAtCoord:]`: `addItemWithTitle:action:keyEquivalent:` on `emulationLevelDecls[i].action`

  **CLOSED.** C arrays `terminalStateDecls` and `emulationLevelDecls` in the same method, written with `@selector(...)`. No strings. Reach: `terminalStateDecls` has `terminalStateToggleAlternateScreen:`, `terminalStateToggleApplicationCursor:`, `terminalStateToggleApplicationKeypad:`, `terminalStateToggleFocusReporting:`, `terminalStateToggleLiteralMode:`, `terminalStateToggleMouseReporting:`, `terminalStateTogglePasteBracketing:`, `terminalToggleKeyboardMode:`; every entry of `emulationLevelDecls` is `terminalStateSetEmulationLevel:`.

  Names: `terminalStateToggleAlternateScreen:`, `terminalStateToggleApplicationCursor:`, `terminalStateToggleApplicationKeypad:`, `terminalStateToggleFocusReporting:`, `terminalStateToggleLiteralMode:`, `terminalStateToggleMouseReporting:`, `terminalStateTogglePasteBracketing:`, `terminalToggleKeyboardMode:`, `terminalStateSetEmulationLevel:`.

- `sources/ContextMenu/iTermTextViewContextMenuHelper.m:969` in `+[iTermTextViewContextMenuHelper menuItemsForAPIRegistrationRequests:scope:target:action:]`: `initWithTitle:action:keyEquivalent:` on `action`

  **GENERIC.** `+menuItemsForAPIRegistrationRequests:scope:target:action:` has one caller, iTermTextViewContextMenuHelper.m in -[iTermTextViewContextMenuHelper addAPIProvidedMenuItems:], passing `@selector(apiMenuItem:)`.

  Names: `apiMenuItem:`.

#### `sources/OpenQuickly/iTermOpenQuicklyModel.m`

- `sources/OpenQuickly/iTermOpenQuicklyModel.m:685` in `-[iTermOpenQuicklyModel actionItemForAction:matcher:]`: `setAction:` on `action`

  **NOT-REFLECTIVE.** `actionItem.action` is an `iTermAction *` property of `iTermOpenQuicklyActionItem`, not a selector. Extractor false positive (`setAction:` on a non-selector property).

  Names: none.

#### `sources/PTYSession/PTYSession.m`

- `sources/PTYSession/PTYSession.m:12783` in `-[PTYSession sendKeystrokeNotificationForEvent:advanced:]`: `setAction:` on `ITMKeystrokeNotification_Action_KeyDown`
- `sources/PTYSession/PTYSession.m:12786` in `-[PTYSession sendKeystrokeNotificationForEvent:advanced:]`: `setAction:` on `ITMKeystrokeNotification_Action_KeyUp`
- `sources/PTYSession/PTYSession.m:12789` in `-[PTYSession sendKeystrokeNotificationForEvent:advanced:]`: `setAction:` on `ITMKeystrokeNotification_Action_FlagsChanged`

  **NOT-REFLECTIVE.** `keystrokeNotification.action` is a protobuf enum field (`ITMKeystrokeNotification_Action_*`). Extractor false positive.

  Names: none.

#### `sources/PasswordManager/iTermPasswordManagerWindowController.m`

- `sources/PasswordManager/iTermPasswordManagerWindowController.m:92` in `iTermPWMakePushButton`: `setAction:` on `action`

  **GENERIC.** `iTermPWMakePushButton` callers pass `@selector(reallyAdd:)` and `@selector(cancelNewAccount:)` (iTermPasswordManagerWindowController.m in -[iTermPasswordManagerWindowController ensureNewAccountPanel]).

  Names: `reallyAdd:`, `cancelNewAccount:`.

#### `sources/Settings/GeneralPreferencesViewController.m`

- `sources/Settings/GeneralPreferencesViewController.m:577` in `-[iTermManualAIModelsPanelController makeSegmentedControlWithSegments:action:]`: `setAction:` on `action`

  **GENERIC.** `makeSegmentedControlWithSegments:action:` callers pass `@selector(addDeleteClicked:)` and `@selector(editControlClicked:)` (GeneralPreferencesViewController.m in -[iTermManualAIModelsPanelController buildWindow]).

  Names: `addDeleteClicked:`, `editControlClicked:`.

#### `sources/Settings/Profiles/iTermProfileModelJournal.m`

- `sources/Settings/Profiles/iTermProfileModelJournal.m:43` in `+[BookmarkJournalEntry journalWithAction:bookmark:model:index:identifier:]`: `setAction:` on `action`

  **NOT-REFLECTIVE.** `entry.action` is a `JournalAction` enum on `BookmarkJournalEntry`. Extractor false positive.

  Names: none.

#### `sources/Settings/Profiles/iTermProfilesMenuController.m`

- `sources/Settings/Profiles/iTermProfilesMenuController.m:99` in `+[iTermProfilesMenuController addOpenAllToMenu:params:identifier:]`: `addItemWithTitle:action:keyEquivalent:` on `params.openAllSelector`
- `sources/Settings/Profiles/iTermProfilesMenuController.m:114` in `+[iTermProfilesMenuController addOpenAllToMenu:params:identifier:]`: `initWithTitle:action:keyEquivalent:` on `params.alternateOpenAllSelector`
- `sources/Settings/Profiles/iTermProfilesMenuController.m:200` in `-[iTermProfilesMenuController addBookmark:toMenu:atPosition:withParams:isAlternate:withTag:identifier:]`: `initWithTitle:action:keyEquivalent:` on `isAlternate ? params.alternateSelector : params.selector`

  **CLOSED.** Selectors from `iTermProfileModelJournalParams`, assigned only with `@selector`: iTermApplicationDelegate.m in -[iTermApplicationDelegate updateAddressBookMenu:] and iTermController.m in -[iTermController addBookmarksToMenu:supermenu:withSelector:openAllSelector:startingAt:] (whose own parameters come from `addBookmarksToMenu:...` callers, see iTermController.m in -[iTermController addBookmarksToMenu:supermenu:withSelector:openAllSelector:startingAt:]). Reach: `newSessionInWindowAtIndex:`, `newSessionInTabAtIndex:`, `newSessionsInWindow:`, `newSessionsInNewWindow:`.

  Names: `newSessionInWindowAtIndex:`, `newSessionInTabAtIndex:`, `newSessionsInWindow:`, `newSessionsInNewWindow:`.

#### `sources/Settings/ProfilesColorsPreferencesViewController.m`

- `sources/Settings/ProfilesColorsPreferencesViewController.m:620` in `-[ProfilesColorsPreferencesViewController addPresetItemWithTitle:action:]`: `addItemWithTitle:action:keyEquivalent:` on `action`

  **GENERIC.** `addPresetItemWithTitle:action:` callers pass `@selector`: `importColorPreset:`, `exportColorPreset:`, `saveColorPreset:`, `deleteColorPreset:`, `visitGallery:` (ProfilesColorsPreferencesViewController.m in -[ProfilesColorsPreferencesViewController rebuildColorPresetsMenu]).

  Names: `importColorPreset:`, `exportColorPreset:`, `saveColorPreset:`, `deleteColorPreset:`, `visitGallery:`.

#### `sources/Settings/WindowArrangements.m`

- `sources/Settings/WindowArrangements.m:195` in `+[WindowArrangements refreshRestoreArrangementsMenu:withSelector:defaultShortcut:identifier:]`: `addItemWithTitle:action:keyEquivalent:` on `selector`

  **GENERIC.** `refreshRestoreArrangementsMenu:withSelector:...` has one caller, iTermApplicationDelegate.m in -[iTermApplicationDelegate updateRestoreWindowArrangementsMenu:asTabs:fromDock:], whose selector comes from `restoreWindowArrangementSelectorAsTabs:fromDock:`, which returns one of `@selector(restoreWindowArrangementAfterDelayAsTabs:)`, `restoreWindowArrangementAfterDelay:`, `restoreWindowArrangementAsTabs:`, `restoreWindowArrangement:`.

  Names: `restoreWindowArrangementAfterDelayAsTabs:`, `restoreWindowArrangementAfterDelay:`, `restoreWindowArrangementAsTabs:`, `restoreWindowArrangement:`.

#### `sources/Settings/iTermEditKeyActionWindowController.m`

- `sources/Settings/iTermEditKeyActionWindowController.m:703` in `-[iTermEditKeyActionWindowController setAction:parameter:applyMode:]`: `setAction:` on `keyAction`

  **NOT-REFLECTIVE.** `[self setAction:keyAction]` sets a `KEY_ACTION` enum property of the window controller. Extractor false positive.

  Names: none.

#### `sources/StatusBar/Components/iTermStatusBarGitComponent.m`

- `sources/StatusBar/Components/iTermStatusBarGitComponent.m:365` in `-[iTermStatusBarGitComponent openMenuWithView:]`: `initWithTitle:action:keyEquivalent:` on `enabled ? selector : @selector(bogusSelector)`

  **CLOSED.** Local block `addItem`; every call passes `@selector`: `commit:`, `addAndCommit:`, `stash:`, `log:`, `push:`, `pull:`, `checkout:`, `debug`; disabled items get `bogusSelector`.

  Names: `commit:`, `addAndCommit:`, `stash:`, `log:`, `push:`, `pull:`, `checkout:`, `debug`, `bogusSelector`.

#### `sources/StatusBar/Setup/iTermStatusBarSetupViewController.m`

- `sources/StatusBar/Setup/iTermStatusBarSetupViewController.m:216` in `-[iTermStatusBarSetupViewController initializeColorWell:withAction:color:alphaAllowed:]`: `setAction:` on `selector`

  **GENERIC.** `initializeColorWell:withAction:...` callers pass `@selector(noop:)` (iTermStatusBarSetupViewController.m in -[iTermStatusBarSetupViewController awakeFromNib]).

  Names: `noop:`.

#### `sources/TerminalView/PTYTextView.m`

- `sources/TerminalView/PTYTextView.m:3639` in `-[PTYTextView makeBlockCopyButtonForLine:block:]`: `setAction:` on `^(NSPoint locationInWindow) { [weakSelf copyBlock:block absLine:line+offset screenCoord...`
- `sources/TerminalView/PTYTextView.m:3681` in `-[PTYTextView makeOrUpdateBlockFoldButtonForLine:block:absLineRange:changed:]`: `setAction:` on `^(NSPoint locationInWindow) { if (wasFolded) { [weakSelf unfoldBlock:block]; } else { [...`
- `sources/TerminalView/PTYTextView.m:6893` in `-[PTYTextView terminalButtons]`: `setAction:` on `^(NSPoint locationInWindow) { [weakSelf copyBlock:blockID absLine:-1 screenCoordinate:[...`
- `sources/TerminalView/PTYTextView.m:6908` in `-[PTYTextView terminalButtons]`: `setAction:` on `^(NSPoint locationInWindow) { [weakSelf.delegate textViewSendCustomButtonCode:code]; }`
- `sources/TerminalView/PTYTextView.m:6915` in `-[PTYTextView terminalButtons]`: `setAction:` on `^(NSPoint locationInWindow) { [weakSelf revealChannelWithUID:uid]; }`
- `sources/TerminalView/PTYTextView.m:6970` in `-[PTYTextView commandButtonsForMark:line:shouldFloat:offByOne:]`: `setAction:` on `^(NSPoint locationInWindow) { actionBlock(locationInWindow, weakMark); }`

  **NOT-REFLECTIVE.** `button.action` is a block property of the terminal button class (`^(NSPoint locationInWindow) {...}`), not a selector. Extractor false positive.

  Names: none.

#### `sources/TerminalView/PseudoTerminal.m`

- `sources/TerminalView/PseudoTerminal.m:10477` in `-[PseudoTerminal tabView:menuForTabGroup:]`: `initWithTitle:action:keyEquivalent:` on `NSSelectorFromString(spec[1])`
- `sources/TerminalView/PseudoTerminal.m:10478` in `-[PseudoTerminal tabView:menuForTabGroup:]`: `NSSelectorFromString` on `spec[1]`

  **CLOSED.** `spec[1]` comes from the `specs` array literal in the same method (string literals). Target is `self` (PseudoTerminal). Reach: `newTabInGroup:`, `expandTabGroupFromMenu:`, `collapseTabGroupFromMenu:`, `renameTabGroupFromMenu:`, `duplicateTabGroup:`, `moveTabGroupToNewWindow:`, `saveTabGroupAsWindowArrangement:`, `ungroupTabGroup:`, `closeTabGroup:`, `closeTabsOutsideGroup:`, `closeTabsRightOfGroup:`. Line 10416 also compares `spec[1]` with `@"collapseTabGroupFromMenu:"`.

  Names: `newTabInGroup:`, `expandTabGroupFromMenu:`, `collapseTabGroupFromMenu:`, `renameTabGroupFromMenu:`, `duplicateTabGroup:`, `moveTabGroupToNewWindow:`, `saveTabGroupAsWindowArrangement:`, `ungroupTabGroup:`, `closeTabGroup:`, `closeTabsOutsideGroup:`, `closeTabsRightOfGroup:`.

#### `sources/Toolbelt/iTermToolActions.m`

- `sources/Toolbelt/iTermToolActions.m:53` in `iTermToolActionsNewButton`: `setAction:` on `selector`

  **GENERIC.** `iTermToolActionsNewButton` callers pass `@selector`: `apply:`, `add:`, `remove:`, `edit:` (iTermToolActions.m in -[iTermToolActions initWithFrame:]; C function, found with `git grep`).

  Names: `apply:`, `add:`, `remove:`, `edit:`.

#### `sources/Toolbelt/iTermToolSnippets.m`

- `sources/Toolbelt/iTermToolSnippets.m:110` in `iTermToolSnippetsNewButton`: `setAction:` on `selector`

  **GENERIC.** `iTermToolSnippetsNewButton` callers pass `@selector`: `apply:`, `add:`, `remove:`, `edit:`, `openInAdvancedPaste:` (iTermToolSnippets.m in -[iTermToolSnippets initWithFrame:]; C function, found with `git grep`).

  Names: `apply:`, `add:`, `remove:`, `edit:`, `openInAdvancedPaste:`.

#### `sources/VT100/VT100StateTransition.m`

- `sources/VT100/VT100StateTransition.m:8` in `+[VT100StateTransition transitionToState:withAction:]`: `setAction:` on `action`

  **NOT-REFLECTIVE.** `transition.action` is a `VT100StateAction` block property. Extractor false positive.

  Names: none.

### Class from a string or made at run time

#### `sources/Categories/NSTableView+iTerm.m`

- `sources/Categories/NSTableView+iTerm.m:196` in `-[iTermToolbeltOutlineView makeViewWithIdentifier:owner:]`: `NSClassFromString` on `subclassName`
- `sources/Categories/NSTableView+iTerm.m:198` in `-[iTermToolbeltOutlineView makeViewWithIdentifier:owner:]`: `objc_allocateClassPair` on `[subclassName UTF8String]`
- `sources/Categories/NSTableView+iTerm.m:200` in `-[iTermToolbeltOutlineView makeViewWithIdentifier:owner:]`: `class_getInstanceMethod` on `sel`
- `sources/Categories/NSTableView+iTerm.m:202` in `-[iTermToolbeltOutlineView makeViewWithIdentifier:owner:]`: `method_getImplementation` on `method`
- `sources/Categories/NSTableView+iTerm.m:207` in `-[iTermToolbeltOutlineView makeViewWithIdentifier:owner:]`: `class_addMethod` on `sel`
- `sources/Categories/NSTableView+iTerm.m:211` in `-[iTermToolbeltOutlineView makeViewWithIdentifier:owner:]`: `object_setClass` on `subclass`

  **CLOSED.** Creates subclass `NSOutlineButtonCell_iTermCustomImageRect` (string literal) of the disclosure button cell's class and adds `imageRectForBounds:` and `original_imageRectForBounds:` (both `@selector`). Reach: those names on AppKit's private `NSOutlineButtonCell`; the class name is created here, not looked up from data.

  Names: `imageRectForBounds:`, `original_imageRectForBounds:`, `NSOutlineButtonCell_iTermCustomImageRect`.

#### `sources/DataStructuresAlgorithms/IntervalTree.m`

- `sources/DataStructuresAlgorithms/IntervalTree.m:517` in `-[IntervalTree restoreFromDictionary:]`: `NSClassFromString` on `className`

  **OPEN-EXTERNAL.** Class name from a saved interval-tree dictionary (window arrangements and session restoration written by this or another version; `restoreFromDictionary:` via `initWithDictionary:`, reached from `-[PTYSession ...]` restore through VT100Screen). Writers store `NSStringFromClass(object.class)` (IntervalTree.m in -[IntervalTree encodeWithEncoder:offset:]). Check: `conformsToProtocol:@protocol(IntervalTreeObject)` (a class that does not conform is skipped), then `instancesRespondToSelector:@selector(initWithDictionary:)`, as the graph-record path does (added 2026-11-21, owner queue Q21 item 3; before, only the responds-to check). Names the app writes: interval-tree object classes `iTermMark`, `VT100ScreenMark`, `iTermCapturedOutputMark`, `iTermImageMark`, `iTermBlockMark`, `iTermButtonMark`, `iTermFoldMark`, `iTermPathMark`, the Swift `PortholeMark` (module-qualified runtime name, no `@objc(Name)`), `PTYAnnotation`, `VT100RemoteHost`, `VT100WorkingDirectory` (writers: IntervalTree.m in -[IntervalTree encodeWithEncoder:offset:] and the `dictionaryValueWithTypeInformation` methods, section 5). Names written by older versions: `iTermURLMark` was an interval-tree object until it was deleted (commit c4b3c4830, issue 11697); saved state that still contains it is skipped here because the class no longer exists. No rename table exists; no other class of this list was renamed (git history of the class files shows only moves).

  Names: `initWithDictionary:`, `iTermMark`, `VT100ScreenMark`, `iTermCapturedOutputMark`, `iTermImageMark`, `iTermBlockMark`, `iTermButtonMark`, `iTermFoldMark`, `iTermPathMark`, `PortholeMark`, `PTYAnnotation`, `VT100RemoteHost`, `VT100WorkingDirectory`.

- `sources/DataStructuresAlgorithms/IntervalTree.m:1440` in `-[IntervalTree restoreFromGraphRecord:offset:largeContentProvider:]`: `NSClassFromString` on `className`

  **OPEN-EXTERNAL.** Class name from a graph record of saved state (same writers as the entry of -[IntervalTree restoreFromDictionary:]). Check: `conformsToProtocol:@protocol(IntervalTreeObject)`. Names: the same interval-tree object classes as IntervalTree.m in -[IntervalTree restoreFromDictionary:], and the same history (`iTermURLMark` is skipped).

  Names: `iTermMark`, `VT100ScreenMark`, `iTermCapturedOutputMark`, `iTermImageMark`, `iTermBlockMark`, `iTermButtonMark`, `iTermFoldMark`, `iTermPathMark`, `PortholeMark`, `PTYAnnotation`, `VT100RemoteHost`, `VT100WorkingDirectory`.

#### `sources/Language/iTermBuiltInFunctions.m`

- `sources/Language/iTermBuiltInFunctions.m:464` in `+[iTermBuiltInMethod argumentDictionaryFromArray:]`: `NSClassFromString` on `obj.className`

  **CLOSED.** `obj.className` is parsed by `iTermReflection` from the type encoding of an argument of a registered built-in method (see iTermBuiltInFunctions.m in -[iTermBuiltInMethod callWithArguments:connectionKey:cancellation:completion:]). Reach: the classes of the object arguments of the 16 registered methods listed there, read from their declarations: `NSString`, `NSNumber`, `NSArray` and our own `iTermScriptCallCancellation` (the `cancellation:` argument of `loadURLWithCompletion:url:connectionKey:cancellation:` and `browserEvalJSWithCompletion:js:connectionKey:cancellation:`). If a method moves to Swift its type encoding loses the class name, and a Swift `iTermScriptCallCancellation` without `@objc(iTermScriptCallCancellation)` has a module-qualified name, so this lookup changes behavior.

  Names: `NSString`, `NSNumber`, `NSArray`, `iTermScriptCallCancellation`.

#### `sources/Marks/iTermMark.m`

- `sources/Marks/iTermMark.m:77` in `+[iTermMark intervalTreeObjectWithDictionaryWithTypeInformation:]`: `NSClassFromString` on `className`

  **OPEN-EXTERNAL.** Class name from `dict[@"class"]` of saved state, written by `-dictionaryValueWithTypeInformation` (iTermMark.m in -[iTermMark dictionaryValueWithTypeInformation], `NSStringFromClass(self.class)`). Check: `conformsToProtocol:@protocol(IntervalTreeObject)` and `instancesRespondToSelector:@selector(initWithDictionary:)`. The same dictionary form is written by `PTYAnnotation`, `VT100RemoteHost` and `VT100WorkingDirectory` (`dictionaryValueWithTypeInformation`, section 5), which also conform. Names: the interval-tree object classes of IntervalTree.m in -[IntervalTree restoreFromDictionary:], with the same history (`iTermURLMark` is no longer loadable).

  Names: `initWithDictionary:`, `iTermMark`, `VT100ScreenMark`, `iTermCapturedOutputMark`, `iTermImageMark`, `iTermBlockMark`, `iTermButtonMark`, `iTermFoldMark`, `iTermPathMark`, `PortholeMark`, `PTYAnnotation`, `VT100RemoteHost`, `VT100WorkingDirectory`.

#### `sources/Settings/TriggerController.m`

- `sources/Settings/TriggerController.m:385` in `-[TriggerController indexOfAction:]`: `NSClassFromString` on `className`

  **CLOSED.** `className` is `NSStringFromClass(classes[i])` over `+triggerClassesForTerminal:` (TriggerController.m in +[TriggerController triggerClassesForTerminal:]), a round trip of known classes, used to call `+synonyms`. Reach: the trigger classes in that list (see Trigger.m in +[Trigger triggerFromUntrustedDict:]). The same name is also compared with `action`, which `-triggerWithAction:` passes from a stored trigger dictionary's `kTriggerActionKey` (in -[TriggerController actionDidChange:], -[TriggerController parameterPopUpButtonDidChange:] and -[TriggerController comboBoxSelectionDidChange:]): the class name that `-[Trigger dictionaryValue]` wrote (section 5, Trigger.m in -[Trigger dictionaryValue]). A stored name therefore matches only a class whose runtime name is still exactly that string (or one of its `+synonyms`); this is the section 5 use of `NSStringFromClass(classes[i])`, covered here.

  Names: `AlertTrigger`, `AnnotateTrigger`, `BellTrigger`, `BounceTrigger`, `iTermRPCTrigger`, `CaptureTrigger`, `iTermBufferInputTrigger`, `iTermFoldTrigger`, `iTermInjectTrigger`, `iTermEnterWorkgroupTrigger`, `iTermExitWorkgroupTrigger`, `iTermHighlightLineTrigger`, `iTermUserNotificationTrigger`, `iTermSetUserVariableTrigger`, `iTermSetProfileBooleanTrigger`, `iTermShellPromptTrigger`, `iTermSetTitleTrigger`, `iTermSetNamedMarkTrigger`, `iTermSGRTrigger`, `SendTextTrigger`, `ScriptTrigger`, `CoprocessTrigger`, `MuteCoprocessTrigger`, `HighlightTrigger`, `MarkTrigger`, `PasswordTrigger`, `iTermHyperlinkTrigger`, `SetDirectoryTrigger`, `SetHostnameTrigger`, `StopTrigger`, `iTermSetTabStatusTrigger`, `ReaderModeBrowserTrigger`, `HighlightBrowserTrigger`, `HyperlinkBrowserTrigger`, `ReloadBrowserTrigger`, `InjectJavascriptURLTrigger`, `InjectJavascriptContentTrigger`, `iTermEnterWorkgroupBrowserTrigger`, `iTermExitWorkgroupBrowserTrigger`.

#### `sources/StatusBar/Components/iTermStatusBarBaseComponent.m`

- `sources/StatusBar/Components/iTermStatusBarBaseComponent.m:51` in `-[iTermStatusBarBuiltInComponentFactory initWithCoder:]`: `NSClassFromString` on `className`

  **OPEN-EXTERNAL.** `-[iTermStatusBarBuiltInComponentFactory initWithCoder:]` decodes a class name and later calls `[[_class alloc] initWithConfiguration:scope:]`. Input: drag-and-drop data of type `iTermStatusBarElementPasteboardType`, unarchived with `requiresSecureCoding = NO`. Check: non-nil, then `conformsToProtocol:@protocol(iTermStatusBarComponent)` (a class that does not conform makes the factory nil; added 2026-11-21, owner queue Q21 item 3; before, only non-nil). The decoding itself is still not secure coding. The citation for the unarchiving: the effective `requiresSecureCoding = NO` is in `-[NSData it_unarchivedObjectOfClasses:]` (NSData+iTerm.m in -[NSData(iTerm) it_unarchivedObjectOfClasses:]), called at iTermStatusBarSetupDestinationCollectionViewController.m in -[iTermStatusBarSetupDestinationCollectionViewController collectionView:acceptDrop:indexPath:dropOperation:]; the same method also sets it on an unarchiver that is never used. Writer: iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:] (section 5). Names the app writes: the component classes listed at iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], same history.

  Names: `iTermStatusBarActionComponent`, `iTermStatusBarActionMenuComponent`, `iTermStatusBarAttributedTextComponent`, `iTermStatusBarBatteryComponent`, `iTermStatusBarClockComponent`, `iTermStatusBarComposerComponent`, `iTermStatusBarCPUUtilizationComponent`, `iTermStatusBarFixedSpacerComponent`, `iTermStatusBarFunctionCallComponent`, `iTermStatusBarGitComponent`, `iTermStatusBarHostnameComponent`, `iTermStatusBarJobComponent`, `iTermStatusBarMemoryUtilizationComponent`, `iTermStatusBarNetworkUtilizationComponent`, `iTermStatusBarPlaceholderComponent`, `iTermStatusBarProgressComponent`, `iTermStatusBarRPCProvidedAttributedTextComponent`, `iTermStatusBarRPCProvidedTextComponent`, `iTermStatusBarSearchFieldComponent`, `iTermStatusBarSnippetMenuComponent`, `iTermStatusBarSparklinesComponent`, `iTermStatusBarSpringComponent`, `iTermStatusBarSwiftyStringComponent`, `iTermStatusBarTextComponent`, `iTermStatusBarTmuxLeftComponent`, `iTermStatusBarTmuxRightComponent`, `iTermStatusBarUsernameComponent`, `iTermStatusBarVariableBaseComponent`, `iTermStatusBarWorkingDirectoryComponent`, `iTermStatusBarFilterComponent`, `iTermStatusBarTriggersComponent`, `initWithConfiguration:scope:`.

#### `sources/StatusBar/Core/iTermStatusBarLayout.m`

- `sources/StatusBar/Core/iTermStatusBarLayout.m:112` in `+[iTermStatusBarLayout componentsArrayFromDictionary:scope:]`: `NSClassFromString` on `className`

  **OPEN-EXTERNAL.** Class name from a status bar layout dictionary in a profile (user defaults, Dynamic Profiles, the Python API). Check: `conformsToProtocol:@protocol(iTermStatusBarComponent)`, then `initWithConfiguration:scope:`. Names the app writes: the component classes, `iTermStatusBarActionComponent`, `iTermStatusBarActionMenuComponent`, `iTermStatusBarAttributedTextComponent`, `iTermStatusBarBatteryComponent`, `iTermStatusBarClockComponent`, `iTermStatusBarComposerComponent`, `iTermStatusBarCPUUtilizationComponent`, `iTermStatusBarFixedSpacerComponent`, `iTermStatusBarFunctionCallComponent`, `iTermStatusBarGitComponent`, `iTermStatusBarHostnameComponent`, `iTermStatusBarJobComponent`, `iTermStatusBarMemoryUtilizationComponent`, `iTermStatusBarNetworkUtilizationComponent`, `iTermStatusBarPlaceholderComponent`, `iTermStatusBarProgressComponent`, `iTermStatusBarRPCProvidedAttributedTextComponent`, `iTermStatusBarRPCProvidedTextComponent`, `iTermStatusBarSearchFieldComponent`, `iTermStatusBarSnippetMenuComponent`, `iTermStatusBarSparklinesComponent`, `iTermStatusBarSpringComponent`, `iTermStatusBarSwiftyStringComponent`, `iTermStatusBarTextComponent`, `iTermStatusBarTmuxLeftComponent`, `iTermStatusBarTmuxRightComponent`, `iTermStatusBarUsernameComponent`, `iTermStatusBarVariableBaseComponent`, `iTermStatusBarWorkingDirectoryComponent`, `iTermStatusBarFilterComponent`, `iTermStatusBarTriggersComponent` (from `@interface ... : ...Component` in sources and the two Swift classes with `@objc(Name)`). Writers: iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue] (section 5). Names written by older versions: git history of the component files shows only moves, no renamed or deleted component class, and there is no rename table. Persisted by name.

  Names: `iTermStatusBarActionComponent`, `iTermStatusBarActionMenuComponent`, `iTermStatusBarAttributedTextComponent`, `iTermStatusBarBatteryComponent`, `iTermStatusBarClockComponent`, `iTermStatusBarComposerComponent`, `iTermStatusBarCPUUtilizationComponent`, `iTermStatusBarFixedSpacerComponent`, `iTermStatusBarFunctionCallComponent`, `iTermStatusBarGitComponent`, `iTermStatusBarHostnameComponent`, `iTermStatusBarJobComponent`, `iTermStatusBarMemoryUtilizationComponent`, `iTermStatusBarNetworkUtilizationComponent`, `iTermStatusBarPlaceholderComponent`, `iTermStatusBarProgressComponent`, `iTermStatusBarRPCProvidedAttributedTextComponent`, `iTermStatusBarRPCProvidedTextComponent`, `iTermStatusBarSearchFieldComponent`, `iTermStatusBarSnippetMenuComponent`, `iTermStatusBarSparklinesComponent`, `iTermStatusBarSpringComponent`, `iTermStatusBarSwiftyStringComponent`, `iTermStatusBarTextComponent`, `iTermStatusBarTmuxLeftComponent`, `iTermStatusBarTmuxRightComponent`, `iTermStatusBarUsernameComponent`, `iTermStatusBarVariableBaseComponent`, `iTermStatusBarWorkingDirectoryComponent`, `iTermStatusBarFilterComponent`, `iTermStatusBarTriggersComponent`, `initWithConfiguration:scope:`.

#### `sources/Triggers/Trigger.m`

- `sources/Triggers/Trigger.m:77` in `+[Trigger triggerFromUntrustedDict:]`: `NSClassFromString` on `className`

  **OPEN-EXTERNAL.** Class name from a trigger dictionary's action key (`kTriggerActionKey`): profiles in user defaults, Dynamic Profiles files, the Python API, and pasteboard imports. Check: `isSubclassOfClass:[Trigger class]` and not `Trigger` itself. Names the app writes: the classes of `+[TriggerController triggerClassesForTerminal:]` (TriggerController.m in +[TriggerController triggerClassesForTerminal:]): `AlertTrigger`, `AnnotateTrigger`, `BellTrigger`, `BounceTrigger`, `iTermRPCTrigger`, `CaptureTrigger`, `iTermBufferInputTrigger`, `iTermFoldTrigger`, `iTermInjectTrigger`, `iTermEnterWorkgroupTrigger`, `iTermExitWorkgroupTrigger`, `iTermHighlightLineTrigger`, `iTermUserNotificationTrigger`, `iTermSetUserVariableTrigger`, `iTermSetProfileBooleanTrigger`, `iTermShellPromptTrigger`, `iTermSetTitleTrigger`, `iTermSetNamedMarkTrigger`, `iTermSGRTrigger`, `SendTextTrigger`, `ScriptTrigger`, `CoprocessTrigger`, `MuteCoprocessTrigger`, `HighlightTrigger`, `MarkTrigger`, `PasswordTrigger`, `iTermHyperlinkTrigger`, `SetDirectoryTrigger`, `SetHostnameTrigger`, `StopTrigger`, `iTermSetTabStatusTrigger`, `ReaderModeBrowserTrigger`, `HighlightBrowserTrigger`, `HyperlinkBrowserTrigger`, `ReloadBrowserTrigger`, `InjectJavascriptURLTrigger`, `InjectJavascriptContentTrigger`, `iTermEnterWorkgroupBrowserTrigger`, `iTermExitWorkgroupBrowserTrigger`. Of the Swift ones, `HighlightBrowserTrigger`, `HyperlinkBrowserTrigger` (no `@objc`) and `ReaderModeBrowserTrigger` (`@objc` without a name) have module-qualified runtime names, so the stored name depends on the Swift module name. `GrowlTrigger` is a real class: an empty subclass of `iTermUserNotificationTrigger` (iTermUserNotificationTrigger.m in the GrowlTrigger class) kept so that triggers saved under that name still load here, and also a synonym (`+synonyms`) used by `-[TriggerController indexOfAction:]`. Names written by older versions, from the comment at iTermUserNotificationTrigger.m in the comment above the GrowlTrigger class and git history: `GrowlTrigger` (all versions before 3.2.1 and from 3.2.2 on), `iTermUserNotificationTrigger` (3.2.1 and the 3.3.0 betas); `InteractiveScriptTrigger` was renamed to `CoprocessTrigger` long ago (commit bf9dc0159) with no compatibility class, so triggers saved under it no longer load; `iTermPromptStartTrigger` became `iTermShellPromptTrigger` (commits 2cf5a5904 to 7d07124e2, apparently before release). Persisted by name: every class in this list and `GrowlTrigger`.

  Names: `AlertTrigger`, `AnnotateTrigger`, `BellTrigger`, `BounceTrigger`, `iTermRPCTrigger`, `CaptureTrigger`, `iTermBufferInputTrigger`, `iTermFoldTrigger`, `iTermInjectTrigger`, `iTermEnterWorkgroupTrigger`, `iTermExitWorkgroupTrigger`, `iTermHighlightLineTrigger`, `iTermUserNotificationTrigger`, `iTermSetUserVariableTrigger`, `iTermSetProfileBooleanTrigger`, `iTermShellPromptTrigger`, `iTermSetTitleTrigger`, `iTermSetNamedMarkTrigger`, `iTermSGRTrigger`, `SendTextTrigger`, `ScriptTrigger`, `CoprocessTrigger`, `MuteCoprocessTrigger`, `HighlightTrigger`, `MarkTrigger`, `PasswordTrigger`, `iTermHyperlinkTrigger`, `SetDirectoryTrigger`, `SetHostnameTrigger`, `StopTrigger`, `iTermSetTabStatusTrigger`, `ReaderModeBrowserTrigger`, `HighlightBrowserTrigger`, `HyperlinkBrowserTrigger`, `ReloadBrowserTrigger`, `InjectJavascriptURLTrigger`, `InjectJavascriptContentTrigger`, `iTermEnterWorkgroupBrowserTrigger`, `iTermExitWorkgroupBrowserTrigger`, `GrowlTrigger`.

### Key-value coding, observing, bindings and sort keys

#### `sources/API/iTermScriptingWindow.m`

- `sources/API/iTermScriptingWindow.m:41` in `-[iTermScriptingWindow methodSignatureForSelector:]`: `methodSignatureForSelector:` on `selector`
- `sources/API/iTermScriptingWindow.m:60` in `-[iTermScriptingWindow valueForKey:]`: `valueForKey:` on `key`
- `sources/API/iTermScriptingWindow.m:64` in `-[iTermScriptingWindow setValue:forKey:]`: `setValue:forKey:` on `key`
- `sources/API/iTermScriptingWindow.m:68` in `-[iTermScriptingWindow valueForKeyPath:]`: `valueForKeyPath:` on `keyPath`
- `sources/API/iTermScriptingWindow.m:84` in `-[iTermScriptingWindow bind:toObject:withKeyPath:options:]`: `bind:toObject:withKeyPath:options:` on `binding`
- `sources/API/iTermScriptingWindow.m:84` in `-[iTermScriptingWindow bind:toObject:withKeyPath:options:]`: `bind:toObject:withKeyPath:options:` on `keyPath`

  **OPEN-EXTERNAL.** `iTermScriptingWindow` is an NSProxy that forwards messages, KVC and bindings to the wrapped window for AppleScript. Keys come from AppleScript via Cocoa Scripting, which only resolves keys declared for class `window` in `iTerm2.sdef` (`uniqueID`, `windowIdentifier`, `title`, `orderedIndex`, `boundsAsQDRect`, `hasCloseBox`, `isMiniaturizable`, `isMiniaturized`, `isResizable`, `isVisible`, `isZoomable`, `isZoomed`, `scriptFrontmost`, `tabs`, `currentTab`, `currentSession`, `isHotkeyWindow`, `hotkeyWindowProfile`, `scriptPosition`, `scriptOrigin`, `scriptSize`, `scriptFrame`). Other code holding the proxy may also call it. The sdef keys are pinned by the sdef binding tests ([phase0.md section 3](phase0.md)), not by this registry; the selector forwarded by `methodSignatureForSelector:`/`forwardInvocation:` is any message sent to the proxy.

  Names: none.

#### `sources/Categories/NSUserDefaults+iTerm.m`

- `sources/Categories/NSUserDefaults+iTerm.m:36` in `-[NSUserDefaults(iTerm) it_addObserverForKey:block:]`: `addObserver:forKeyPath:options:context:` on `key`

  **CLOSED.** KVO on `NSUserDefaults` for a user-defaults key. Callers pass `kPreferenceKeyTabStyle` (iTermApplicationDelegate.m in -[iTermApplicationDelegate applicationWillFinishLaunching:], iTermGlobalScopeController.m in -[iTermGlobalScopeController init], PTYSession.m in -[PTYSession initSynthetic:]). The key names a defaults entry, not a method; no app method is reached.

  Names: none.

#### `sources/Settings/Profiles/ProfileListView.m`

- `sources/Settings/Profiles/ProfileListView.m:784` in `-[ProfileListView tableView:didClickTableColumn:]`: `initWithKey:ascending:` on `[aTableColumn identifier]`
- `sources/Settings/Profiles/ProfileListView.m:794` in `-[ProfileListView tableView:didClickTableColumn:]`: `initWithKey:ascending:` on `[aTableColumn identifier]`

  **CLOSED.** Sort key is the clicked column's identifier. ProfileListView creates exactly three columns, with identifiers `name`, `shortcut` and `command`. The descriptors sort `ProfileTableRow` objects (ProfileModelWrapper.m in -[ProfileModelWrapper sort]). Reach: `-[ProfileTableRow name]`, `-[ProfileTableRow shortcut]`, `-[ProfileTableRow command]`.

  Names: `ProfileTableRow.name`, `ProfileTableRow.shortcut`, `ProfileTableRow.command`.

#### `sources/Settings/iTermUserDefaultsObserver.m`

- `sources/Settings/iTermUserDefaultsObserver.m:39` in `-[iTermUserDefaultsObserver dealloc]`: `removeObserver:forKeyPath:context:` on `key`
- `sources/Settings/iTermUserDefaultsObserver.m:49` in `-[iTermUserDefaultsObserver observeKey:block:]`: `addObserver:forKeyPath:options:context:` on `key`

  **CLOSED.** KVO on `NSUserDefaults` for user-defaults keys passed to `-observeKey:block:` (iTermKeyMappings.m, PTYSession.m, GeneralPreferencesViewController.m, PreferenceInfo.m, ProfilesSessionPreferencesViewController.m, iTermAdvancedSettingsModel.m in +[iTermAdvancedSettingsModel initialize], iTermPreferences.m, and Swift callers). Keys are defaults keys (some from data such as advanced-setting identifiers), not methods; no app method is reached.

  Names: none.

#### `sources/TIps/iTermTipCardActionButton.m`

- `sources/TIps/iTermTipCardActionButton.m:255` in `-[iTermTipCardActionButton mouseDragged:]`: `setValue:forKey:` on `kCATransactionDisableActions`
- `sources/TIps/iTermTipCardActionButton.m:274` in `-[iTermTipCardActionButton mouseDown:]`: `setValue:forKey:` on `kCATransactionDisableActions`

  **CLOSED.** `+[CATransaction setValue:forKey:]` with the SDK constant `kCATransactionDisableActions`. No app method is reached.

  Names: none.

#### `sources/VT100Screen/VT100ScreenConfiguration.m`

- `sources/VT100Screen/VT100ScreenConfiguration.m:347` in `-[VT100MutableScreenConfiguration init]`: `addObserver:forKeyPath:options:context:` on `name`
- `sources/VT100Screen/VT100ScreenConfiguration.m:358` in `-[VT100MutableScreenConfiguration dealloc]`: `removeObserver:forKeyPath:` on `selectorString`

  **CLOSED.** KVO on self for every `@dynamic` property of `VT100MutableScreenConfiguration` (via `it_enumerateDynamicProperties:`). The set is the 57 `@dynamic` declarations at VT100ScreenConfiguration.m in the @dynamic declarations of @implementation VT100MutableScreenConfiguration: `shouldPlacePromptAtFirstColumn`, `sessionGuid`, `stableID`, `treatAmbiguousCharsAsDoubleWidth`, `unicodeVersion`, `enableTriggersInInteractiveApps`, `triggerParametersUseInterpolatedStrings`, `triggerProfileDicts`, `isTmuxClient`, `printingAllowed`, `clipboardAccessAllowed`, `miniaturized`, `windowFrame`, `globalWindowFrame`, `screenFrames`, `theoreticalGridSize`, `iconTitle`, `windowTitle`, `clearScrollbackAllowed`, `profileName`, `cellSize`, `backingScaleFactor`, `maximumTheoreticalImageDimension`, `dimOnlyText`, `darkMode`, `useSeparateColorsForLightAndDarkMode`, `minimumContrast`, `faintTextAlpha`, `mutingAmount`, `normalization`, `appendToScrollbackWithStatusBar`, `saveToScrollbackInAlternateScreen`, `unlimitedScrollback`, `reduceFlicker`, `maxScrollbackLines`, `loggingEnabled`, `terminfoValues`, `alertOnNextMark`, `dimmingAmount`, `publishing`, `terminalCanChangeBlink`, `desiredComposerRows`, `autoComposerEnabled`, `useLineStyleMarks`, `optionIsMetaForSpecialChars`, `wantsCommandChangeNotifications`, `osc52`, `sessionIsVisible`, `audibleBell`, `showBellIndicator`, `flashBell`, `postUserNotifications`, `cursorBlinks`, `allowTitleReporting`, `allowTitleSetting`, `allowAlternateMouseScroll`, `isDirty`. Each must stay a KVO-observable property of that class with the `@dynamic` (D) attribute; a Swift port that drops the attribute silently stops the observation (no dirty tracking).

  Names: `VT100MutableScreenConfiguration.shouldPlacePromptAtFirstColumn`, `VT100MutableScreenConfiguration.sessionGuid`, `VT100MutableScreenConfiguration.stableID`, `VT100MutableScreenConfiguration.treatAmbiguousCharsAsDoubleWidth`, `VT100MutableScreenConfiguration.unicodeVersion`, `VT100MutableScreenConfiguration.enableTriggersInInteractiveApps`, `VT100MutableScreenConfiguration.triggerParametersUseInterpolatedStrings`, `VT100MutableScreenConfiguration.triggerProfileDicts`, `VT100MutableScreenConfiguration.isTmuxClient`, `VT100MutableScreenConfiguration.printingAllowed`, `VT100MutableScreenConfiguration.clipboardAccessAllowed`, `VT100MutableScreenConfiguration.miniaturized`, `VT100MutableScreenConfiguration.windowFrame`, `VT100MutableScreenConfiguration.globalWindowFrame`, `VT100MutableScreenConfiguration.screenFrames`, `VT100MutableScreenConfiguration.theoreticalGridSize`, `VT100MutableScreenConfiguration.iconTitle`, `VT100MutableScreenConfiguration.windowTitle`, `VT100MutableScreenConfiguration.clearScrollbackAllowed`, `VT100MutableScreenConfiguration.profileName`, `VT100MutableScreenConfiguration.cellSize`, `VT100MutableScreenConfiguration.backingScaleFactor`, `VT100MutableScreenConfiguration.maximumTheoreticalImageDimension`, `VT100MutableScreenConfiguration.dimOnlyText`, `VT100MutableScreenConfiguration.darkMode`, `VT100MutableScreenConfiguration.useSeparateColorsForLightAndDarkMode`, `VT100MutableScreenConfiguration.minimumContrast`, `VT100MutableScreenConfiguration.faintTextAlpha`, `VT100MutableScreenConfiguration.mutingAmount`, `VT100MutableScreenConfiguration.normalization`, `VT100MutableScreenConfiguration.appendToScrollbackWithStatusBar`, `VT100MutableScreenConfiguration.saveToScrollbackInAlternateScreen`, `VT100MutableScreenConfiguration.unlimitedScrollback`, `VT100MutableScreenConfiguration.reduceFlicker`, `VT100MutableScreenConfiguration.maxScrollbackLines`, `VT100MutableScreenConfiguration.loggingEnabled`, `VT100MutableScreenConfiguration.terminfoValues`, `VT100MutableScreenConfiguration.alertOnNextMark`, `VT100MutableScreenConfiguration.dimmingAmount`, `VT100MutableScreenConfiguration.publishing`, `VT100MutableScreenConfiguration.terminalCanChangeBlink`, `VT100MutableScreenConfiguration.desiredComposerRows`, `VT100MutableScreenConfiguration.autoComposerEnabled`, `VT100MutableScreenConfiguration.useLineStyleMarks`, `VT100MutableScreenConfiguration.optionIsMetaForSpecialChars`, `VT100MutableScreenConfiguration.wantsCommandChangeNotifications`, `VT100MutableScreenConfiguration.osc52`, `VT100MutableScreenConfiguration.sessionIsVisible`, `VT100MutableScreenConfiguration.audibleBell`, `VT100MutableScreenConfiguration.showBellIndicator`, `VT100MutableScreenConfiguration.flashBell`, `VT100MutableScreenConfiguration.postUserNotifications`, `VT100MutableScreenConfiguration.cursorBlinks`, `VT100MutableScreenConfiguration.allowTitleReporting`, `VT100MutableScreenConfiguration.allowTitleSetting`, `VT100MutableScreenConfiguration.allowAlternateMouseScroll`, `VT100MutableScreenConfiguration.isDirty`.

### Runtime method and property functions

#### `sources/AppKit/iTermApplication.m`

- `sources/AppKit/iTermApplication.m:119` in `iTermInstallCrashOnExceptionHook`: `method_setImplementation` on `method`

  **CLOSED.** Replaces the IMP of `+[NSApplication _crashOnException:]`, looked up with `NSSelectorFromString(@"_crashOnException:")` (string literal). Reach: that private AppKit class method only. Not our code.

  Names: `_crashOnException:`.

#### `sources/AppKit/iTermApplicationDelegate.m`

- `sources/AppKit/iTermApplicationDelegate.m:303` in `-[iTermApplicationDelegate init]`: `method_setImplementation` on `m`

  **CLOSED.** Replaces `-[NSAlert runModal]` (`@selector(runModal)`) in compare-rendering mode. Reach: AppKit only.

  Names: `runModal`.

#### `sources/Categories/NSObject+iTerm.m`

- `sources/Categories/NSObject+iTerm.m:130` in `+[NSObject(iTerm) load]`: `class_getInstanceMethod` on `originalSelector`
- `sources/Categories/NSObject+iTerm.m:131` in `+[NSObject(iTerm) load]`: `class_getInstanceMethod` on `swizzledSelector`
- `sources/Categories/NSObject+iTerm.m:135` in `+[NSObject(iTerm) load]`: `method_getImplementation` on `originalMethod`
- `sources/Categories/NSObject+iTerm.m:138` in `+[NSObject(iTerm) load]`: `method_exchangeImplementations` on `originalMethod`
- `sources/Categories/NSObject+iTerm.m:138` in `+[NSObject(iTerm) load]`: `method_exchangeImplementations` on `swizzledMethod`
- `sources/Categories/NSObject+iTerm.m:142` in `+[NSObject(iTerm) load]`: `class_addMethod` on `originalSelector`
- `sources/Categories/NSObject+iTerm.m:144` in `+[NSObject(iTerm) load]`: `method_getImplementation` on `swizzledMethod`

  **CLOSED.** Swizzle in `+[NSObject(iTerm) load]`: class `_NSThemeZoomWidgetCell` by string literal; `originalSelector` is `@selector(showMenu:)`, `swizzledSelector` is `@selector(swizzled__NSThemeZoomWidgetCell_showMenu:)`. Reach: `showMenu:` on the private AppKit class and `-[NSObject(iTerm) swizzled__NSThemeZoomWidgetCell_showMenu:]`.

  Names: `swizzled__NSThemeZoomWidgetCell_showMenu:`, `showMenu:`, `_NSThemeZoomWidgetCell`.

- `sources/Categories/NSObject+iTerm.m:215` in `+[NSObject(iTerm) it_enumerateDynamicProperties:]`: `class_copyPropertyList` on `self`
- `sources/Categories/NSObject+iTerm.m:223` in `+[NSObject(iTerm) it_enumerateDynamicProperties:]`: `property_getName` on `prop`

  **GENERIC.** `+it_enumerateDynamicProperties:` lists the properties of the receiving class that have the `@dynamic` attribute. Its only callers are VT100ScreenConfiguration.m in -[VT100MutableScreenConfiguration init] and -[VT100MutableScreenConfiguration dealloc] (receiver `VT100MutableScreenConfiguration`), classified at those rows.

  Names: none.

#### `sources/Categories/NSTextView+iTermUndoSafety.m`

- `sources/Categories/NSTextView+iTermUndoSafety.m:40` in `+[NSTextView(iTermUndoSafety) load]`: `class_getInstanceMethod` on `originalSelector`
- `sources/Categories/NSTextView+iTermUndoSafety.m:41` in `+[NSTextView(iTermUndoSafety) load]`: `class_getInstanceMethod` on `replacementSelector`
- `sources/Categories/NSTextView+iTermUndoSafety.m:43` in `+[NSTextView(iTermUndoSafety) load]`: `method_exchangeImplementations` on `originalMethod`
- `sources/Categories/NSTextView+iTermUndoSafety.m:43` in `+[NSTextView(iTermUndoSafety) load]`: `method_exchangeImplementations` on `replacementMethod`

  **CLOSED.** Swizzle in `+[NSTextView(iTermUndoSafety) load]`: `originalSelector = @selector(viewWillMoveToWindow:)`, `replacementSelector = @selector(iterm_undoSafety_viewWillMoveToWindow:)`. Reach: `-[NSTextView viewWillMoveToWindow:]` and `-[NSTextView(iTermUndoSafety) iterm_undoSafety_viewWillMoveToWindow:]`.

  Names: `iterm_undoSafety_viewWillMoveToWindow:`, `viewWillMoveToWindow:`.

#### `sources/Infrastructure/iTermSelectorSwizzler.m`

- `sources/Infrastructure/iTermSelectorSwizzler.m:39` in `-[iTermSwizzledSelector unswizzle]`: `method_setImplementation` on `self.originalMethod`

  **GENERIC.** `-[iTermSwizzledSelector unswizzle]` is called only from `-[iTermSelectorSwizzlerContext drain]` on the `iTermSwizzledSelector` objects that `-[NSObject(Swizzle) swizzleInstanceMethodSelector:withBlock:]` made. That method and `+[iTermSelectorSwizzler swizzleSelector:fromClass:withBlock:forBlock:]` were deleted as dead code on 2026-11-20 (unit `delete-unused-reflective-helpers`), so nothing creates an `iTermSwizzledSelector` any more. Dead.

  Names: none.

- `sources/Infrastructure/iTermSelectorSwizzler.m:11` in `+[iTermSelectorSwizzler permanentlySwizzleSelector:fromClass:withBlock:]`: `class_getClassMethod` on `selector`
- `sources/Infrastructure/iTermSelectorSwizzler.m:12` in `+[iTermSelectorSwizzler permanentlySwizzleSelector:fromClass:withBlock:]`: `class_getInstanceMethod` on `selector`
- `sources/Infrastructure/iTermSelectorSwizzler.m:16` in `+[iTermSelectorSwizzler permanentlySwizzleSelector:fromClass:withBlock:]`: `method_getImplementation` on `originalMethod`
- `sources/Infrastructure/iTermSelectorSwizzler.m:20` in `+[iTermSelectorSwizzler permanentlySwizzleSelector:fromClass:withBlock:]`: `imp_implementationWithBlock` on `replacementBlock`
- `sources/Infrastructure/iTermSelectorSwizzler.m:21` in `+[iTermSelectorSwizzler permanentlySwizzleSelector:fromClass:withBlock:]`: `method_setImplementation` on `originalMethod`

  **GENERIC.** `+permanentlySwizzleSelector:fromClass:withBlock:` has one caller, iTermWindowImpl.m in -preventTitlebarDivider (of each window class that includes the file): `@selector(_updateDividerLayerForController:animated:)` on `NSClassFromString(@"NSTitlebarContainerView")` (private AppKit, string literal).

  Names: `_updateDividerLayerForController:animated:`, `NSTitlebarContainerView`.

#### `sources/Language/iTermBuiltInFunctions.m`

- `sources/Language/iTermReflection.m:152` in `-[iTermReflection reflectedArguments]`: `class_getInstanceMethod` on `_selector`
- `sources/Language/iTermReflection.m:154` in `-[iTermReflection reflectedArguments]`: `method_getName` on `method`
- `sources/Language/iTermBuiltInFunctions.m:558` in `-[iTermBuiltInMethod callWithArguments:connectionKey:cancellation:completion:]`: `instanceMethodSignatureForSelector:` on `_action`
- `sources/Language/iTermBuiltInFunctions.m:561` in `-[iTermBuiltInMethod callWithArguments:connectionKey:cancellation:completion:]`: `setSelector:` on `_action`

  **CLOSED.** `_action` is the selector given to `-[iTermBuiltInMethod initWithName:...action:...]`; `iTermReflection` reads the same method's argument count and names from the runtime (`class_getInstanceMethod`, `method_getName`, split on `:`). Registrations (all `@selector`): PTYSession.m in -[PTYSession objectMethodRegistry], PTYTab.m in -[PTYTab objectMethodRegistry], PseudoTerminal.m in -[PseudoTerminal broadcastInputHelper:sessionsInTabWithSession:includeExited:] and -[PseudoTerminal broadcastInputHelperDidUpdate:]; ModernTests/ScriptCallCancellationTests.swift in ScriptCallCancellationTestTarget.init() registers a test method. Reach: `setNameWithCompletion:name:`, `sendTmuxCommandWithCompletion:command:`, `setStatusBarComponentUnreadCountWithCompletion:identifier:count:`, `stopCoprocessWithCompletion:`, `getCoprocessWithCompletion:`, `runCoprocessWithCompletion:commandLine:mute:`, `addAnnotationWithCompletion:startX:startY:endX:endY:text:`, `fetchTimeOffsetWithCompletion:`, `loadURLWithCompletion:url:connectionKey:cancellation:`, `browserSetToolbarHiddenWithCompletion:hidden:`, `browserEvalJSWithCompletion:js:connectionKey:cancellation:`, `setTitleWithCompletion:title:`, `selectPaneInDirectionWithCompletion:direction:`, `apiCreateTabGroupWithCompletion:tab_ids:name:color:parent_group_id:`, `apiAddTabToGroupWithCompletion:tab_id:group_id:`, `apiRemoveTabFromGroupWithCompletion:tab_id:`. The selector keywords after the first are the scripting-function argument names, so these selectors are part of the scripting API; the methods also depend on their type encodings (argument classes, see iTermBuiltInFunctions.m in +[iTermBuiltInMethod argumentDictionaryFromArray:]).

  Names: `setNameWithCompletion:name:`, `sendTmuxCommandWithCompletion:command:`, `setStatusBarComponentUnreadCountWithCompletion:identifier:count:`, `stopCoprocessWithCompletion:`, `getCoprocessWithCompletion:`, `runCoprocessWithCompletion:commandLine:mute:`, `addAnnotationWithCompletion:startX:startY:endX:endY:text:`, `fetchTimeOffsetWithCompletion:`, `loadURLWithCompletion:url:connectionKey:cancellation:`, `browserSetToolbarHiddenWithCompletion:hidden:`, `browserEvalJSWithCompletion:js:connectionKey:cancellation:`, `setTitleWithCompletion:title:`, `selectPaneInDirectionWithCompletion:direction:`, `apiCreateTabGroupWithCompletion:tab_ids:name:color:parent_group_id:`, `apiAddTabToGroupWithCompletion:tab_id:group_id:`, `apiRemoveTabFromGroupWithCompletion:tab_id:`.

#### `sources/Settings/iTermAdvancedSettingsModel.m`

- `sources/Settings/iTermAdvancedSettingsModel.m:352` in `+[iTermAdvancedSettingsModel enumerateMethods:]`: `class_copyMethodList` on `object_getClass([iTermAdvancedSettingsModel class])`
- `sources/Settings/iTermAdvancedSettingsModel.m:355` in `+[iTermAdvancedSettingsModel enumerateMethods:]`: `method_getName` on `method`
- `sources/Settings/iTermAdvancedSettingsModel.m:366` in `+[iTermAdvancedSettingsModel enumerateDictionaries:]`: `method_getImplementation` on `method`
- `sources/Settings/iTermAdvancedSettingsModel.m:1131` in `+[iTermAdvancedSettingsModel initialize]`: `method_getImplementation` on `method`
- `sources/Settings/iTermAdvancedSettingsModel.m:1154` in `+[iTermAdvancedSettingsModel loadAdvancedSettingsFromUserDefaults]`: `method_getImplementation` on `method`

  **CLOSED.** Walks the class method list of `iTermAdvancedSettingsModel` and calls methods by name prefix: `advancedSettingsModelDictionary_` (enumerateDictionaries:) and `load_` (+initialize, +loadAdvancedSettingsFromUserDefaults). Those methods are generated by the `DEFINE_*` macros (532 uses in iTermAdvancedSettingsModel.m): `DEFINE_BOILERPLATE` defines `advancedSettingsModelDictionary_<name>`, `<name>UserDefaultsKey`, `load_<name>` and `<name>` for each setting. Reach: every class method of the class with those prefixes (one pair per `DEFINE_*` use). The class must not be ported without the owner-reviewed design required by [hidden-callers.md section 5](hidden-callers.md).

  Names: `iTermAdvancedSettingsModel +advancedSettingsModelDictionary_*`, `iTermAdvancedSettingsModel +load_*`.

## 4. Callers of generic helpers

Sites that are not database rows: they pass a computed selector to an app helper (most often `-[NSObject(iTerm) it_performNonObjectReturningSelector:...]`, `NSObject+iTerm.m` in -[NSObject(iTerm) it_performNonObjectReturningSelector:withObject:] and its siblings) whose own call is a GENERIC row above. Callers that pass `@selector` literals are listed in the helper's entry and need nothing more. Callers in the same method as a database row (`iTermFindDriver.m` in -[iTermFindDriver doCommandBySelector:], the status bar knob controllers, `iTermStatusBarSetupDestinationCollectionViewController.m` in -[iTermStatusBarSetupDestinationCollectionView doCommandBySelector:], `TmuxGateway.m` in -[TmuxGateway invokeCurrentCallbackWithError:], `TmuxController.m` in -[TmuxController didListWindows:userData:]) are covered by that row's entry.

- `sources/Infrastructure/iTermGCDTimer.m:92` in `-[iTermGCDTimer didFire]`: `it_performNonObjectReturningSelector:withObject: [_selector]`

  **CLOSED.** Selector from `initWithInterval:...target:selector:` and `+scheduledWeakTimerWithTimeInterval:target:selector:queue:`. Callers: iTermEchoProbe.m in -[iTermEchoProbe beginProbeWithBackspace:password:] `timeout`, iTermSwipeTracker.m in -[iTermSwipeTracker updateTimer] `update:`, iTermTemporaryDoubleBufferedGridController.m in -[iTermTemporaryDoubleBufferedGridController scheduleTimer] `savedGridExpirationTimer:`, iTermRateLimitedUpdate.m in -[iTermRateLimitedUpdate scheduleTimerAfterDelay:] `performBlockIfNeeded:`. No Swift callers.

  Names: `timeout`, `update:`, `savedGridExpirationTimer:`, `performBlockIfNeeded:`.

- `sources/Notifications/iTermNotificationCenter.m:52` in `+[iTermBaseNotification subscribe:selector:]`: `it_performNonObjectReturningSelector:withObject: [selector]`

  **CLOSED.** Callers pass `@selector`: iTermActionsMenuController.m in -[iTermActionsMenuController awakeFromNib] `actionsDidChange:`, iTermSnippetsMenuController.m in -[iTermSnippetsMenuController awakeFromNib] `snippetsDidChange:`, PTYTab.m in -[PTYTab commonInit] `preferenceDidChange:`. No Swift callers.

  Names: `actionsDidChange:`, `snippetsDidChange:`, `preferenceDidChange:`.

- `sources/SemanticHistory/iTermURLActionHelper.m:480` in `-[iTermURLActionHelper finishOpeningTargetWithEvent:coord:inBackground:style:action:generation:smartSelectionActionsOnly:]`: `it_performNonObjectReturningSelector:withObject: [action.selector]`

  **CLOSED.** `action.selector` is set at iTermURLActionFactory.m in -[iTermURLActionFactory computeURLActionForSmartSelection:] from the smart-selection table (see that entry). Reach: the seven `contextMenuAction...:` selectors on `iTermTextViewContextMenuHelper`.

  Names: `contextMenuActionOpenFile:`, `contextMenuActionOpenURL:`, `contextMenuActionRunCommand:`, `contextMenuActionRunCoprocess:`, `contextMenuActionSendText:`, `contextMenuActionRunCommandInWindow:`, `contextMenuActionCopy:`.

- `sources/Settings/iTermBadgeConfigurationWindowController.m:224` in `-[iTermBadgeConfigurationBadgeView mouseDragged:]`: `it_performNonObjectReturningSelector:withObject: [_selector]`

  **CLOSED.** `_selector` is `edge.selector` from the C array in -[iTermBadgeConfigurationBadgeView edge:]: `adjustLeft:`, `adjustRight:`, `adjustTop:`, `adjustBottom:`.

  Names: `adjustLeft:`, `adjustRight:`, `adjustTop:`, `adjustBottom:`.

- `sources/Settings/iTermSlider.m:187` in `-[iTermSlider performAction]`: `it_performNonObjectReturningSelector:withObject: [_action]`

  **CLOSED.** `_action` is copied from the embedded `NSSlider`'s action (iTermSlider.m in -[iTermSlider awakeFromNib]). iTermSlider is used only in PreferencePanel.xib, where all ten embedded sliders have action `settingChanged:` (xib). Reach: `settingChanged:` on the preferences view controllers; pinned by the xib binding tests.

  Names: `settingChanged:`.

- `sources/StatusBar/Setup/iTermStatusBarSetupDestinationCollectionViewController.m:193` in `-[iTermStatusBarSetupDestinationCollectionViewController configureStatusBarComponentWithIdentifier:]`: `it_performNonObjectReturningSelector:withObject: [_configureButton.action]`

  **CLOSED.** `_configureButton` is an outlet whose action in iTermStatusBarSetupViewController.xib is `configureComponent:`.

  Names: `configureComponent:`.

- `sources/TIps/iTermTipCardActionButton.m:127` in `-[iTermTipCardActionButton accessibilityPerformPress]`: `it_performNonObjectReturningSelector:withObject: [self.action]`

  **CLOSED.** The only assignment of an action is iTermTipCardViewController.m in -[iTermTipCardViewController addActionWithTitle:shortcut:icon:block:], `@selector(buttonPressed:)`; iTermTipWindowController.m in -[iTermTipWindowController animateOut] and -[iTermTipWindowController rollInTip:fromRight:] set it to nil.

  Names: `buttonPressed:`.

- `sources/TIps/iTermTipCardActionButton.m:328` in `-[iTermTipCardActionButton mouseUp:]`: `it_performNonObjectReturningSelector:withObject: [self.action]`

  **CLOSED.** Same as the entry of -[iTermTipCardActionButton accessibilityPerformPress]: `buttonPressed:`.

  Names: `buttonPressed:`.

- `sources/Toolbelt/ToolProfiles.m:227` in `-[ToolProfiles open:]`: `it_performNonObjectReturningSelector:withObject: [[popup_ selectedItem] action]`

  **CLOSED.** The popup's items are added at ToolProfiles.m in -[ToolProfiles initWithFrame:] with `@selector(toolProfilesNewTab:)`, `toolProfilesNewWindow:`, `toolProfilesNewHorizontalSplit:`, `toolProfilesNewVerticalSplit:`, `toolProfilesNewFloatingPane:`.

  Names: `toolProfilesNewTab:`, `toolProfilesNewWindow:`, `toolProfilesNewHorizontalSplit:`, `toolProfilesNewVerticalSplit:`, `toolProfilesNewFloatingPane:`.

- `sources/tmux/TmuxWindowOpener.m:367` in `-[TmuxWindowOpener finishErroneously]`: `it_performNonObjectReturningSelector:withObject: [self.selector]`

  **CLOSED.** `selector` is assigned only at TmuxController.m in -[TmuxController openWindowWithIndex:name:size:layout:visibleLayout:affinities:windowFlags:profile:initial:tabIndex:] and -[TmuxController setLayoutInTab:toLayout:visibleLayout:zoomed:] (`windowDidOpen:`), -[TmuxController openBuriedSessionsForParkedWindow:layout:] (`buriedPanesDidOpen:`) and -[TmuxController unpausePanes:] (`panesDidUnpause:`).

  Names: `windowDidOpen:`, `buriedPanesDidOpen:`, `panesDidUnpause:`.

- `sources/tmux/TmuxWindowOpener.m:547` in `-[TmuxWindowOpener requestDidComplete]`: `it_performNonObjectReturningSelector:withObject: [self.selector]`

  **CLOSED.** Same as the entry of -[TmuxWindowOpener finishErroneously].

  Names: `windowDidOpen:`, `buriedPanesDidOpen:`, `panesDidUnpause:`.

- `sources/tmux/TmuxWindowOpener.m:709` in `-[TmuxWindowOpener requestDidComplete]`: `it_performNonObjectReturningSelector:withObject: [self.selector]`

  **CLOSED.** Same as the entry of -[TmuxWindowOpener finishErroneously].

  Names: `windowDidOpen:`, `buriedPanesDidOpen:`, `panesDidUnpause:`.

## 5. Selector and class names used as data

Sites the extractor does not record: a selector or class turned into a string that is then compared, matched by prefix or suffix, used as a key, persisted, or used to build another name ([hidden-callers.md section 2](hidden-callers.md)). Every use of the conversions in the scope was read; the ones that do more than log are below, grouped by what they do, and the rest are counted at the end.

- `sources/TerminalView/PTYTextView.m:599` in `-[PTYTextView validateMenuItem:]`: `NSStringFromSelector(theSel) hasPrefix:@"contextMenuAction"`

  **CLOSED.** A menu item validated against the text view is enabled when its action's name starts with `contextMenuAction`. Selectors with that prefix today: the seven smart-selection actions of `iTermTextViewContextMenuHelper` (`contextMenuActionOpenFile:`, `contextMenuActionOpenURL:`, `contextMenuActionRunCommand:`, `contextMenuActionRunCoprocess:`, `contextMenuActionSendText:`, `contextMenuActionRunCommandInWindow:`, `contextMenuActionCopy:`) and `-[SmartSelectionController contextMenuActionsChanged:useInterpolatedStrings:]`, which is not a menu action. Renaming one of the seven so that it loses the prefix disables its context menu item when the text view validates it; giving any new action a name with the prefix enables it unconditionally. Pattern row `contextMenuAction*` in the names table.

  Names: `contextMenuAction*`, `contextMenuActionOpenFile:`, `contextMenuActionOpenURL:`, `contextMenuActionRunCommand:`, `contextMenuActionRunCoprocess:`, `contextMenuActionSendText:`, `contextMenuActionRunCommandInWindow:`, `contextMenuActionCopy:`.

- `sources/ContextMenu/iTermTextViewContextMenuHelper.m:391` in `-[iTermTextViewContextMenuHelper validateMenuItem:]`: `containsObject:NSStringFromSelector(item.action)`

  **CLOSED.** Compares the item's action, as a string, with the values of `smartSelectionActionSelectorDictionary`. Reach: the seven selectors of that table; a renamed method whose table entry is not updated is disabled.

  Names: `contextMenuActionOpenFile:`, `contextMenuActionOpenURL:`, `contextMenuActionRunCommand:`, `contextMenuActionRunCoprocess:`, `contextMenuActionSendText:`, `contextMenuActionRunCommandInWindow:`, `contextMenuActionCopy:`.

- `sources/Infrastructure/Views/iTermFocusReportingTextField.m:95` in `-[iTermFocusReportingSearchField doCommandBySelector:]`: `NSStringFromSelector(selector) isEqualToString:@"noop:"`

  **CLOSED.** Compares the Cocoa text system's command with `noop:`, the command AppKit sends for a key with no binding (here control-C). An AppKit name, not a method of this class; a port must keep comparing with that exact name.

  Names: `noop:`.

- `sources/Infrastructure/iTermWeakReference.m:42` in `-[iTermWeakReference respondsToSelector:]`: `NSStringFromSelector(aSelector) isEqualToString:NSStringFromSelector(@selector(weaklyReferencedObject))`

  **CLOSED.** Answers YES for `weaklyReferencedObject` by name before forwarding (see the row entry for iTermWeakReference.m in -[iTermWeakReference respondsToSelector:]).

  Names: `weaklyReferencedObject`.

- `sources/Language/iTermGlobalScopeController.m:35, 43, 53` in `-[iTermGlobalScopeControllerModernImpl init]`: `forKeyPath:NSStringFromSelector(@selector(effectiveAppearance))`

  **CLOSED.** Observes `NSApp` for the key path `effectiveAppearance`, built from the selector, removes the observer in `dealloc` and compares the key path in `observeValueForKeyPath:ofObject:change:context:`. Reach: the AppKit property `-[NSApplication effectiveAppearance]`; nothing of ours.

  Names: `effectiveAppearance`.

- `sources/Settings/MenuItemPopupView.swift:58, 75` in `MenuItemPopupView`: `NSStringFromSelector(action) == "_toggleIPad:"`

  **CLOSED.** Hides menu items whose action is the private AppKit `_toggleIPad:` or `_moveToDisplay:`, compared by name. AppKit names only.

  Names: `_toggleIPad:`, `_moveToDisplay:`.

- `sources/AppKit/iTermApplication.m:186, 195, 1122 (also iTermApplicationDelegate.m:4196, iTermSearchFieldCell.m:254, iTermsStatusBarComposerViewController.m:279, iTermStatusBarLargeComposerViewController.m:61, PTYTextView.m:2805, PaneFocusFollowsMouseAppEnvironment.swift:381)` in `-[iTermApplication it_windowDidOrderOnScreen:]`: `NSStringFromClass(object.class) isEqualToString:@"NSPanelViewBridge"`

  **CLOSED.** Class names of AppKit's own objects compared with string literals: `NSPanelViewBridge` (iTermApplication.m in `it_windowDidOrderOnScreen:` and `it_windowDidOrderOffScreen:`), `NSPanel.ViewBridge.rendezvous` (`it_accentMenuOpen`), `NSToolTipPanel` (iTermApplicationDelegate.m in -[iTermApplicationDelegate hideStuckToolTips], `hideStuckToolTips`), `_NSKeyboardFocusClipView` (iTermSearchFieldCell.m in -[iTermSearchFieldCell reallyUpdateKeyboardClipView:] and iTermsStatusBarComposerViewController.m in -[iTermComposerComboBoxCell reallyUpdateKeyboardClipView:], `reallyUpdateKeyboardClipView:`), a class name containing `Popover` (iTermStatusBarLargeComposerViewController.m in -[iTermComposerView updateBackgroundView], `-[iTermComposerView updateBackgroundView]`, a substring match), and `NSToolbarFullScreenWindow` with `object_getClassName` (PTYTextView.m in -[PTYTextView isInKeyWindow], `isInKeyWindow`; PaneFocusFollowsMouseAppEnvironment.swift in PaneFocusFollowsMouseAppEnvironment.isInKeyWindow(_:)). SDK and AppKit-private names; none of ours.

  Names: `NSPanelViewBridge`, `NSPanel.ViewBridge.rendezvous`, `NSToolTipPanel`, `_NSKeyboardFocusClipView`, `NSToolbarFullScreenWindow`.

- `sources/Categories/NSWindow+iTerm.m:69` in `SearchForViewOfClass`: `NSStringFromClass(view.class) isEqual:className`

  **GENERIC.** Compares view class names with a parameter of `-[NSWindow(iTerm) it_titlebarViewOfClassWithName:]`. That method has no callers in Objective-C or Swift (`git grep`; no Swift row in the database). Dead; no names reachable today.

  Names: none.

- `sources/DataStructuresAlgorithms/IntervalTree.m:1319, 1364 (also iTermMark.m:64, PTYAnnotation.m:78, VT100RemoteHost.m:169, VT100WorkingDirectory.m:66)` in `-[IntervalTree dictionaryValueWithOffset:]`: `kIntervalTreeClassNameKey: NSStringFromClass(object.class)`

  **CLOSED.** Writers of persisted class names: `-[IntervalTree dictionaryValueWithOffset:]` and `-[IntervalTree encodeWithEncoder:offset:]` store each object's class name in saved session state and window arrangements; the `dictionaryValueWithTypeInformation` methods of `iTermMark`, `PTYAnnotation`, `VT100RemoteHost` and `VT100WorkingDirectory` store it under `class`. Read back by name at IntervalTree.m in -[IntervalTree restoreFromDictionary:] and -[IntervalTree restoreFromGraphRecord:offset:largeContentProvider:] and iTermMark.m in +[iTermMark intervalTreeObjectWithDictionaryWithTypeInformation:] (OPEN-EXTERNAL row entries), by this and other versions. Persisted by name: the interval-tree object classes.

  Names: `iTermMark`, `VT100ScreenMark`, `iTermCapturedOutputMark`, `iTermImageMark`, `iTermBlockMark`, `iTermButtonMark`, `iTermFoldMark`, `iTermPathMark`, `PortholeMark`, `PTYAnnotation`, `VT100RemoteHost`, `VT100WorkingDirectory`.

- `sources/Triggers/Trigger.m:563, 127 (also iTermAddTriggerViewController.m:1808, TriggerController.m:1476)` in `-[Trigger dictionaryValue]`: `kTriggerActionKey: NSStringFromClass(self.class)`

  **OPEN-EXTERNAL.** The trigger's action key is its class name: written to profiles by `-[Trigger dictionaryValue]` and by the trigger editor (`-[Trigger action]`; `-[iTermAddTriggerViewController action]`, iTermAddTriggerViewController.m in -[iTermAddTriggerViewController action]), and compared with a stored action in `-[TriggerController triggerDidChangeParameterOptions:]` (TriggerController.m in -[TriggerController triggerDidChangeParameterOptions:]). Input: trigger dictionaries in profiles, Dynamic Profiles and the Python API. Read back at Trigger.m in +[Trigger triggerFromUntrustedDict:] and TriggerController.m in -[TriggerController indexOfAction:]. Persisted by name: the trigger classes and `GrowlTrigger` (see the Trigger.m in +[Trigger triggerFromUntrustedDict:] entry for the history).

  Names: `AlertTrigger`, `AnnotateTrigger`, `BellTrigger`, `BounceTrigger`, `iTermRPCTrigger`, `CaptureTrigger`, `iTermBufferInputTrigger`, `iTermFoldTrigger`, `iTermInjectTrigger`, `iTermEnterWorkgroupTrigger`, `iTermExitWorkgroupTrigger`, `iTermHighlightLineTrigger`, `iTermUserNotificationTrigger`, `iTermSetUserVariableTrigger`, `iTermSetProfileBooleanTrigger`, `iTermShellPromptTrigger`, `iTermSetTitleTrigger`, `iTermSetNamedMarkTrigger`, `iTermSGRTrigger`, `SendTextTrigger`, `ScriptTrigger`, `CoprocessTrigger`, `MuteCoprocessTrigger`, `HighlightTrigger`, `MarkTrigger`, `PasswordTrigger`, `iTermHyperlinkTrigger`, `SetDirectoryTrigger`, `SetHostnameTrigger`, `StopTrigger`, `iTermSetTabStatusTrigger`, `ReaderModeBrowserTrigger`, `HighlightBrowserTrigger`, `HyperlinkBrowserTrigger`, `ReloadBrowserTrigger`, `InjectJavascriptURLTrigger`, `InjectJavascriptContentTrigger`, `iTermEnterWorkgroupBrowserTrigger`, `iTermExitWorkgroupBrowserTrigger`, `GrowlTrigger`.

- `sources/StatusBar/Core/iTermStatusBarLayout.m:166 (also iTermStatusBarBaseComponent.m:78)` in `-[iTermStatusBarLayout arrayValue]`: `iTermStatusBarLayoutKeyClass: NSStringFromClass([component class])`

  **CLOSED.** Writers of persisted status bar class names: the layout stored in a profile (iTermStatusBarLayout.m in -[iTermStatusBarLayout arrayValue]) and the drag-and-drop archive (`-[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]`, iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory encodeWithCoder:]). Read back at iTermStatusBarLayout.m in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:] and iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:]. Persisted by name: the component classes.

  Names: `iTermStatusBarActionComponent`, `iTermStatusBarActionMenuComponent`, `iTermStatusBarAttributedTextComponent`, `iTermStatusBarBatteryComponent`, `iTermStatusBarClockComponent`, `iTermStatusBarComposerComponent`, `iTermStatusBarCPUUtilizationComponent`, `iTermStatusBarFixedSpacerComponent`, `iTermStatusBarFunctionCallComponent`, `iTermStatusBarGitComponent`, `iTermStatusBarHostnameComponent`, `iTermStatusBarJobComponent`, `iTermStatusBarMemoryUtilizationComponent`, `iTermStatusBarNetworkUtilizationComponent`, `iTermStatusBarPlaceholderComponent`, `iTermStatusBarProgressComponent`, `iTermStatusBarRPCProvidedAttributedTextComponent`, `iTermStatusBarRPCProvidedTextComponent`, `iTermStatusBarSearchFieldComponent`, `iTermStatusBarSnippetMenuComponent`, `iTermStatusBarSparklinesComponent`, `iTermStatusBarSpringComponent`, `iTermStatusBarSwiftyStringComponent`, `iTermStatusBarTextComponent`, `iTermStatusBarTmuxLeftComponent`, `iTermStatusBarTmuxRightComponent`, `iTermStatusBarUsernameComponent`, `iTermStatusBarVariableBaseComponent`, `iTermStatusBarWorkingDirectoryComponent`, `iTermStatusBarFilterComponent`, `iTermStatusBarTriggersComponent`.

- `sources/StatusBar/Components/iTermStatusBarBaseComponent.m:142` in `+[iTermStatusBarBaseComponent statusBarComponentIdentifier]`: `[NSString stringWithFormat:@"com.iterm2.%@", NSStringFromClass(self.class)]`

  **OPEN-EXTERNAL.** The identifier of a built-in component is `com.iterm2.` plus its class name. It keys unread counts (iTermStatusBarViewController.m in -[iTermStatusBarViewController updateViews]), which scripts set through the scripting function `set_status_bar_component_unread_count` (`setStatusBarComponentUnreadCountWithCompletion:identifier:count:`) with an identifier string of their choosing, and it is compared at iTermStatusBarViewController.m in -[iTermStatusBarViewController componentWithIdentifier:] and by the composer (iTermComposerManager.m in -[iTermComposerManager statusBarComponentIfVisible] and -[iTermComposerManager showComposerInStatusBar:]). Renaming a component class, or a Swift component without `@objc(Name)`, changes the identifier that scripts and code use. Names: the component classes that do not override `statusBarComponentIdentifier` (all built-in components except the two RPC-provided ones, which override it).

  Names: `iTermStatusBarActionComponent`, `iTermStatusBarActionMenuComponent`, `iTermStatusBarAttributedTextComponent`, `iTermStatusBarBatteryComponent`, `iTermStatusBarClockComponent`, `iTermStatusBarComposerComponent`, `iTermStatusBarCPUUtilizationComponent`, `iTermStatusBarFixedSpacerComponent`, `iTermStatusBarFunctionCallComponent`, `iTermStatusBarGitComponent`, `iTermStatusBarHostnameComponent`, `iTermStatusBarJobComponent`, `iTermStatusBarMemoryUtilizationComponent`, `iTermStatusBarNetworkUtilizationComponent`, `iTermStatusBarPlaceholderComponent`, `iTermStatusBarProgressComponent`, `iTermStatusBarSearchFieldComponent`, `iTermStatusBarSnippetMenuComponent`, `iTermStatusBarSparklinesComponent`, `iTermStatusBarSpringComponent`, `iTermStatusBarSwiftyStringComponent`, `iTermStatusBarTextComponent`, `iTermStatusBarTmuxLeftComponent`, `iTermStatusBarTmuxRightComponent`, `iTermStatusBarUsernameComponent`, `iTermStatusBarVariableBaseComponent`, `iTermStatusBarWorkingDirectoryComponent`, `iTermStatusBarFilterComponent`, `iTermStatusBarTriggersComponent`.

- `sources/Composer/iTermMinimalComposerViewController.m:140 (also iTermHotkeyPreferencesWindowController.m:43, iTermBadgeConfigurationWindowController.m:377, iTermEditSnippetWindowController.m:31)` in `-[iTermMinimalComposerViewController init]`: `initWithNibName:NSStringFromClass(self.class)`

  **CLOSED.** The nib is named after the class: `NSStringFromClass(self.class)` is passed as the nib name, and the nibs are `Base.lproj/<ClassName>.xib`. A Swift port without `@objc(Name)` gets a module-qualified class name, the nib is not found, and the window or view does not load. A subclass would also look for a nib with its own name.

  Names: `iTermMinimalComposerViewController`, `iTermHotkeyPreferencesWindowController`, `iTermBadgeConfigurationWindowController`, `iTermEditSnippetWindowController`.

- `sources/Settings/PreferencePanel.m:1114` in `-[PreferencePanel bigSurSearchFieldToolbarItem]`: `setClass:[iTermPrefsSearchFieldCell class] forClassName:NSStringFromClass([NSSearchFieldCell class])`

  **CLOSED.** Unarchives an archived `NSSearchFieldCell` as `iTermPrefsSearchFieldCell`, the only `setClass:forClassName:` in scope. The substitute is named by symbol, so a port renaming it is caught by the compiler; the archived name is AppKit's.

  Names: `NSSearchFieldCell`.

- `sources/Settings/iTermAdvancedSettingsViewController.m:820 (also iTermPreferencesBaseViewController.m:1310)` in `-[iTermPreferencesBaseViewController documentOwnerIdentifier]`: `return NSStringFromClass(self.class)`

  **CLOSED.** Owner identifier of the preferences search index entries; set from the same method (iTermPreferencesBaseViewController.m in -[iTermPreferencesBaseViewController addViewToSearchIndex:displayName:phrases:key:], iTermAdvancedSettingsViewController.m in -[iTermAdvancedSettingsViewController searchableViewControllerDocuments]) and compared with it (PreferencePanel.m in -[PreferencePanel viewControllerForDocumentOwnerIdentifier:], ProfilePreferencesViewController.m in -[ProfilePreferencesViewController viewControllerWithOwnerIdentifier:]). In-process round trip; not persisted. No names.

  Names: none.

- `sources/API/iTermDependencyEditorWindowController.m:779 (also iTermRegisteredFunctionsTableViewDelegate.m:105, iTermSessionTabWindowOutlineDelegate.m:272, iTermVariablesOutlineDelegate.m:337, iTermJobTreeViewController.m:923, iTermJobTreeViewController.m:979)` in `-[iTermDependencyEditorWindowController tableView:viewForTableColumn:row:]`: `makeViewWithIdentifier:NSStringFromClass(...)`

  **CLOSED.** Table and outline cell reuse identifiers built from a class name. No xib declares a view with these identifiers (`git grep` of the xibs); the views are made in code and reused under the same expression, so the identifier is an in-process round trip. No names.

  Names: none.

- `sources/Categories/NSImage+iTerm.m:273 (also iTermMetalFrameData.m:457, iTermMetalFrameData.m:461, CPParser+Cache.m:26, iTermKeyboardHandler.m:64)` in `+[NSImage(iTerm) it_cacheableImageNamed:forClass:]`: `cache key from NSStringFromClass(...)`

  **CLOSED.** Class names inside cache and comparison keys: the image cache (NSImage+iTerm.m in +[NSImage(iTerm) it_cacheableImageNamed:forClass:]), the Metal renderer transient states (iTermMetalFrameData.m in -[iTermMetalFrameData transientStateForRenderer:] and -[iTermMetalFrameData setTransientState:forRenderer:]), the parser cache file key (CPParser+Cache.m in +[CPShiftReduceParser(Cache) it_keyWithBNF:start:]; it also contains the app version, so a new build misses the cache anyway) and the key mapper's class in the terminal values digest (iTermKeyboardHandler.m in -[iTermKeyboardHandler dictionaryValue], compared within the process at PTYSession.m in -[PTYSession updateConfigurationFields]). A rename changes the key consistently on both sides; nothing is reached by name. No names.

  Names: none.

- `sources/Settings/iTermAdvancedSettingsModel.m:363, 1129, 1152` in `+[iTermAdvancedSettingsModel enumerateDictionaries:]`: `NSString *name = NSStringFromSelector(selector)`

  **CLOSED.** Prefix tests and name slicing on the enumerated method names; part of the row entries for iTermAdvancedSettingsModel.m in +[iTermAdvancedSettingsModel enumerateMethods:] and +[iTermAdvancedSettingsModel loadAdvancedSettingsFromUserDefaults].

  Names: `iTermAdvancedSettingsModel +advancedSettingsModelDictionary_*`, `iTermAdvancedSettingsModel +load_*`.

- `sources/Language/iTermReflection.m:154` in `-[iTermReflection reflectedArguments]`: `NSStringFromSelector(method_getName(method))`

  **CLOSED.** Splits the selector name on `:` to get the scripting argument names; part of the row entry for iTermBuiltInFunctions.m in -[iTermBuiltInMethod callWithArguments:connectionKey:cancellation:completion:] and iTermReflection.m in -[iTermReflection reflectedArguments].

  Names: `setNameWithCompletion:name:`, `sendTmuxCommandWithCompletion:command:`, `setStatusBarComponentUnreadCountWithCompletion:identifier:count:`, `stopCoprocessWithCompletion:`, `getCoprocessWithCompletion:`, `runCoprocessWithCompletion:commandLine:mute:`, `addAnnotationWithCompletion:startX:startY:endX:endY:text:`, `fetchTimeOffsetWithCompletion:`, `loadURLWithCompletion:url:connectionKey:cancellation:`, `browserSetToolbarHiddenWithCompletion:hidden:`, `browserEvalJSWithCompletion:js:connectionKey:cancellation:`, `setTitleWithCompletion:title:`, `selectPaneInDirectionWithCompletion:direction:`, `apiCreateTabGroupWithCompletion:tab_ids:name:color:parent_group_id:`, `apiAddTabToGroupWithCompletion:tab_id:group_id:`, `apiRemoveTabFromGroupWithCompletion:tab_id:`.

- `sources/tmux/TmuxController.m:3683 (also TmuxGateway.m:1283)` in `-[TmuxController listWindowsInSessionNumber:target:selector:object:]`: `NSStringFromSelector(selector)`

  **CLOSED.** Selector stored as a string and converted back later; part of the row entries for TmuxController.m in -[TmuxController didListWindows:userData:] and TmuxGateway.m in -[TmuxGateway currentCommandSelector].

  Names: `setWindows:forSession:`, `didListWindows:forSession:`, `checkForUTF8Response:`, `didChangeWhetherPaneFloats:request:`, `didFetch:`, `didFetchDefaultTerminal:`, `didFetchNow:completion:`, `didFetchTmuxPid:`, `didGetCurrentWindow:beforeSelecting:`, `didListPanes:forBuriedPanes:`, `didListWindows:userData:`, `didListWindowsSubsequentToSettingLayout:`, `didLoadServerIdentity:`, `didLoadTmuxClientName:`, `didMakeFloatingPane:completion:`, `didPause:panes:`, `didSelectWindow:selection:`, `didSetLayout:`, `didSetLayoutWithMovedDivider:`, `didSplit:state:`, `didSubscribe:handleID:`, `didSwapWindows:`, `dumpHistoryResponse:paneAndAlternate:`, `dumpStateResponse:pane:`, `getAffinitiesResponse:`, `getBuriedIndexesResponse:`, `getHiddenWindowsResponse:`, `getHotkeysResponse:`, `getOriginsResponse:`, `getPaneIDsResponseAndSetHotkeys:`, `getPaneIDsResponseAndSetTabColors:`, `getPendingOutputResponse:pane:`, `getPerTabSettingsResponse:`, `getPerWindowSettingsResponse:`, `getSessionGuidResponse:`, `getTabColorsResponse:`, `getTabGroupParentsResponse:`, `getTabGroupsResponse:`, `getUserVarsResponse:pane:`, `guessVersion18Response:`, `guessVersion21Response:`, `guessVersion22Response:`, `guessVersion23Response:`, `handleDisplayMessageVersion:`, `handleListKeys:`, `handlePingResponse:`, `handleResizeWindowResponse:`, `handleShowBuffer:`, `handleShowSetTitles:`, `handleShowSize:`, `handleStatusIntervalResponse:`, `handleStatusResponse:`, `initialListWindowsResponse:`, `listedWindowsToOpenOne:forWindowIdAndAffinities:`, `listSessionsResponse:`, `listWindowsResponse:`, `newWindowWithAffinityCreated:affinityWindowAndCompletion:`, `parseListWindowsResponseAndUpdateLayouts:`, `phonyCommandDidComplete:`, `printTmuxCommandOutputToScreen:`, `recordPanes:state:`, `requestDidComplete`, `responseForListWindows:toSetPartialOrder:`, `saveWindowOriginsResponse:`, `selector:`, `sendTmuxCommandMethodDidComplete:completion:`, `showWindowOptionsResponse:`, `windowPaneBrokeOutWithWindowId:setAffinityTo:`, `handle:`, `didListClients:completion:`.

- `sources/ContextMenu/iTermTextViewContextMenuHelper.m:59, 60, 61, 62, 63, 64, 65, 413, 415, 417, 419, 423, 425, 427, 429, 432` in `-[iTermTextViewContextMenuHelper smartSelectionActionSelectorDictionary]`: `NSStringFromSelector(@selector(...)) as a table value`

  **CLOSED.** Table values converted back with `NSSelectorFromString`: the smart-selection table of -[iTermTextViewContextMenuHelper smartSelectionActionSelectorDictionary] (row entries in -[iTermTextViewContextMenuHelper selectorForSmartSelectionAction:] and -[iTermTextViewContextMenuHelper addCustomActionsToMenu:matchingText:line:]) and the image menu of -[iTermTextViewContextMenuHelper menuAtCoord:] (row entry in the same method).

  Names: `contextMenuActionOpenFile:`, `contextMenuActionOpenURL:`, `contextMenuActionRunCommand:`, `contextMenuActionRunCoprocess:`, `contextMenuActionSendText:`, `contextMenuActionRunCommandInWindow:`, `contextMenuActionCopy:`, `saveImageAs:`, `copyImage:`, `openImage:`, `inspectImage:`, `togglePauseAnimatingImage:`.

- `sources/iTermTests/iTermTests.m:30` in `+[iTermTest runTests:]`: `NSStringFromSelector(name)`

  **NOT-REFLECTIVE.** In the legacy test runner that no target compiles (section 9). Reaches nothing today.

  Names: none.

Hits of `NSStringFromSelector`, `sel_getName`, `NSStringFromClass`, `class_getName` and `object_getClassName` in the scope directories (Objective-C and Swift, `git grep`, macro definitions excluded): 225 in all (NSStringFromClass 168, NSStringFromSelector 55, object_getClassName 2). Entered above: 74 (one of them, `TriggerController.m` in -[TriggerController indexOfAction:], is covered by the section 3 entry for `TriggerController.m` in -[TriggerController indexOfAction:], which compares the name with a stored trigger action). The other 151 were each read and only log, assert, build a `description` or `debugDescription`, build a user-visible error message, or label a debug artifact (Metal pipeline labels, debug-info folder names, timer log strings); none compares, persists or converts back the name. By file:

`API/iTermOptionalComponentDownloadWindowController.m` (1), `API/iTermWebSocketFrame.m` (1), `Annotations/PTYAnnotation.m` (1), `AutomaticProfileSwitching/iTermAutomaticProfileSwitcher.m` (1), `Browser/Core/iTermBrowserWebView.swift` (1), `Categories/NSEvent+iTerm.m` (2), `Categories/NSObject+iTerm.m` (4), `Categories/NSObject.swift` (1), `Categories/NSScreen+iTerm.m` (1), `Categories/NSTextView+iTermUndoSafety.m` (2), `Categories/NSTimer+iTerm.m` (3), `ColorPicker/ColorPicker/CPKColor.m` (1), `ColorPicker/ColorPicker/CPKKDTreeNode.m` (1), `CommandExecution/iTermBackgroundCommandRunner.m` (2), `DataStructuresAlgorithms/AATree/AATree.m` (1), `DataStructuresAlgorithms/iTermTuple.m` (2), `Drawing/iTermAttributedStringBuilder.m` (1), `Drawing/iTermMutableAttributedStringBuilder.m` (1), `Drawing/iTermSharedImageStore.m` (1), `ExternalSessionState/iTermExternalAttributeIndex.m` (2), `FileTransfer/TransferrableFile.m` (1), `Hotkey/iTermBaseHotKey.m` (1), `Hotkey/iTermCarbonHotKeyController.m` (1), `Hotkey/iTermShortcut.m` (1), `Infrastructure/iTermPromise.m` (1), `Infrastructure/iTermRateLimitedUpdate.m` (1), `Infrastructure/iTermResult.m` (1), `Infrastructure/iTermTaskQueue.mm` (1), `Infrastructure/iTermThreadSafety.m` (1), `Infrastructure/iTermWarning.m` (2), `Infrastructure/iTermWeakReference.m` (1), `Keyboard/iTermKeyboardHandler.m` (4), `Keyboard/iTermKeystroke.m` (1), `Language/iTermBuiltInFunctions.m` (2), `Language/iTermExpressionParser.m` (2), `Language/iTermRecordedVariable.m` (2), `Language/iTermVariableReference.m` (1), `Language/iTermVariableScope.m` (1), `Language/iTermWeakVariables.m` (1), `LineBuffer/LineBlock.mm` (1), `LineBuffer/LineBlockMetadataArray.m` (1), `Marks/VT100ScreenMark.m` (2), `Marks/iTermImageMark.m` (1), `Marks/iTermMark.m` (2), `MetalRenderer/Glue/iTermCharacterSource.m` (2), `MetalRenderer/Infrastructure/iTermMetalCellRenderer.m` (1), `MetalRenderer/Infrastructure/iTermMetalDebugInfo.m` (2), `MetalRenderer/Infrastructure/iTermMetalFrameData.m` (4), `MetalRenderer/Infrastructure/iTermMetalRenderer.m` (3), `MetalRenderer/Infrastructure/iTermSubpixelModelBuilder.mm` (1), `MetalRenderer/Renderers/iTermImageRenderer.m` (1), `MetalRenderer/iTermMetalDriver.m` (3), `PTYSession/PTYSession.m` (1), `PTYSession/PTYSessionHostState.swift` (1), `PTYSession/iTermUpdateCadenceController.m` (1), `ProcessInfo/iTermSyntheticConfParser.m` (1), `ScreenChar/ScreenCharArray.m` (2), `SearchingFiltering/LineBufferHelpers.m` (4), `SearchingFiltering/SearchResult.m` (1), `SearchingFiltering/iTermDropDownFindViewController.m` (1), `Selection/SelectionExtraction.swift` (1), `SemanticHistory/iTermURLActionHelper.m` (1), `SessionCreation/iTermSessionFactory.m` (2), `Settings/PreferencePanel.m` (1), `Settings/Profiles/iTermDynamicProfileManager.m` (1), `Snippets/iTermSnippetsModel.m` (1), `StatusBar/Components/iTermStatusBarBaseComponent.m` (2), `StatusBar/Setup/iTermStatusBarSetupElement.m` (1), `Swipe/iTermScrollWheelStateMachine.m` (1), `Swipe/iTermSwipeState.m` (1), `Tasks/PTYTask.m` (1), `Tasks/iTermFileDescriptorMultiClient.m` (1), `Tasks/iTermFileDescriptorMultiClientChild.m` (1), `Tasks/iTermLegacyJobManager.m` (1), `Tasks/iTermMonoServerJobManager.m` (1), `Tasks/iTermMultiServerJobManager.m` (1), `TerminalView/PTYTab.m` (2), `TerminalView/iTermBackgroundColorView.m` (1), `TerminalView/iTermImageView.m` (1), `TerminalView/iTermTabBarAccessoryViewController.m` (1), `TerminalView/iTermWindowImpl.m` (14), `ThirdParty/PSMTabBarControl/source/PSMCachedTitle.m` (2), `ThirdParty/PSMTabBarControl/source/PSMTabBarCell.m` (1), `ThirdParty/PSMTabBarControl/source/PSMTabBarControl.m` (1), `ThirdParty/PSMTabBarControl/source/PSMTabDragAssistant.m` (3), `Toolbelt/CapturedOutput/CapturedOutput.m` (1), `Triggers/PTYTriggerEvaluator.m` (1), `Triggers/Trigger.m` (3), `Triggers/iTermExpect.m` (2), `VT100/VT100Parser.m` (1), `VT100Screen/VT100ScreenConfiguration.m` (1), `VT100Screen/VT100ScreenMutableState.m` (1), `tmux/TmuxGateway.m` (1), `tmux/iTermTmuxBufferSizeMonitor.m` (1), `tmux/iTermTmuxJobManager.m` (1), `tmux/iTermTmuxOptionMonitor.m` (1), `tmux/iTermTmuxSessionObject.m` (1).

## 6. Names persisted or sent between processes by the frameworks

Class names and selectors that no code of ours turns into or out of a string, but that a framework stores or sends by name: AppKit's window restoration, NSXPC, and keyed archives. A port that changes one of these runtime names breaks saved state or the other process without any reflective call in the source.

### Window restoration

Found by `git grep` in the scope (Objective-C and Swift) for `setRestorationClass`, `restorationClass`, `NSWindowRestoration`, `restoreWindowWithIdentifier`, `restorableStateKeyPaths`, `encodeRestorableState`, `restoreStateWithCoder`/`restoreState(with`, `willEncodeRestorableState` and `didDecodeRestorableState`. There are two restoration classes, both Objective-C, and no Swift adopter; no `restorableStateKeyPaths` override.

- `sources/TerminalView/PseudoTerminal.m:913 (also PseudoTerminalRestorer.h:26, PseudoTerminalRestorer.m:135, PseudoTerminalRestorer.m:154)`: in `-[PseudoTerminal finishInitializationWithSmartLayout:...]`: `setRestorationClass:[PseudoTerminalRestorer class]`

  **OPEN-EXTERNAL.** Every terminal window names `PseudoTerminalRestorer` as its restoration class. AppKit writes the restoration class's name into the saved application state with the window's encoded state, and at the next launch, which may be a different version of the app, looks the class up by that name and sends it `+restoreWindowWithIdentifier:state:completionHandler:` (`PseudoTerminalRestorer.m` in +[PseudoTerminalRestorer restoreWindowWithIdentifier:state:completionHandler:]). No code of ours reads or writes the name; the check between input and call is AppKit's (the class must exist and adopt `NSWindowRestoration`). AppKit still calls it by name when the app uses its own restorable-state controller: the method then ignores the system's state (`PseudoTerminalRestorer.m` in +[PseudoTerminalRestorer restoreWindowWithIdentifier:pseudoTerminalState:system:completionHandler:]). The app's own controller calls the same class by symbol (`iTermApplicationDelegate.m` in -[iTermApplicationDelegate restorableStateRestoreWithCoder:identifier:completion:] and -[iTermApplicationDelegate restorableStateRestoreWithRecord:identifier:completion:]), which the compiler checks. A port must keep the runtime name `PseudoTerminalRestorer` and the class method's selector, so that state saved by this or an earlier version still restores windows. Persisted by name (by AppKit).

  Names: `PseudoTerminalRestorer`, `restoreWindowWithIdentifier:state:completionHandler:`.

- `sources/Settings/Profiles/iTermProfilesWindowController.m:169, 85, 90`: in `-[iTermProfilesWindowController initWithWindowNibName:]`: `setRestorationClass:[iTermProfilesWindowRestorer class]`

  **OPEN-EXTERNAL.** Same mechanism for the Profiles window: AppKit stores the name `iTermProfilesWindowRestorer` (a class declared and implemented in iTermProfilesWindowController.m) in the saved application state and at the next launch sends `+restoreWindowWithIdentifier:state:completionHandler:` to the class it finds by that name. Persisted by name (by AppKit).

  Names: `iTermProfilesWindowRestorer`, `restoreWindowWithIdentifier:state:completionHandler:`.

- `sources/ProfilesPanel/iTermProfilesPanel.m:21, 27 (also iTermWindowImpl.m:241, iTermWindowImpl.m:246, PseudoTerminal.m:16987, PseudoTerminal.m:17056, iTermApplicationDelegate.m:1300, iTermApplicationDelegate.m:1340)`: restorable-state overrides and delegate methods

  **NOT-REFLECTIVE.** Overrides of `NSWindow`/`NSResponder` methods (`encodeRestorableStateWithCoder:`, `encodeRestorableStateWithCoder:backgroundQueue:`, `restoreStateWithCoder:`) and `NSWindowDelegate`/`NSApplicationDelegate` methods (`window:willEncodeRestorableState:`, `window:didDecodeRestorableState:`, `application:willEncodeRestorableState:`, `application:didDecodeRestorableState:`) that AppKit calls through declared API; in Swift, `override` and protocol conformance keep their selectors. The coder keys they use (`kTagsOpen`, `kCloseAfterOpening`, `kTerminalWindowStateRestorationWindowArrangementKey`, `iTermWindowStateKeyGUID`, the application delegate's `k...RestorableStateKey` constants) are strings stored in the archive, not class or method names: a port keeps their values, but no runtime name depends on them. What is encoded under them, as far as the code shows: booleans, the window's GUID string, the window arrangement dictionary (PseudoTerminal.m in -[PseudoTerminal setRestorableStateDecodePending:], iTermWindowImpl.m in -encodeRestorableStateWithCoder: (of each window class that includes the file)) and the application delegate's dictionaries and arrays (iTermApplicationDelegate.m in -[iTermApplicationDelegate application:willEncodeRestorableState:]). AppKit records the class name of each of those objects (see the keyed archives below). No `restorableStateKeyPaths` override exists in the scope (Objective-C or Swift, `git grep`), so no key-value coding names are restored by AppKit.

  Names: none.

### Classes and selectors sent between processes

Found by `git grep` in the scope for `NSXPCInterface`, `interfaceWithProtocol:`, `setClasses:`, `NSXPCConnection`, `NSXPCListener`, `exportedInterface`, `remoteObjectInterface` and `xpc_`. Two XPC interfaces; the protocols are `pidinfoProtocol` and `iTerm2SandboxedWorkerProtocol`, and their selectors and argument and reply types are part of a wire format. Other inter-process channels, checked by category: keyed archives on a pipe, one (the pidinfo child process, below); on the pasteboard, see the archive table; distributed notifications with archived payloads, none found (the three uses, iTermKeyCodeZeroCharacters.swift in iTermKeyCodeZeroCharacters.startObservingIfNeeded(), PasswordManagerDataSourceProvider.swift in PasswordManagerDataSourceProvider.init(browser:) and iTermPasswordManagerWindowController.m in -[iTermPasswordManagerWindowController awakeFromNib], only observe system notifications, and nothing posts one); distributed objects (`NSConnection`, `NSPortCoder`, `CFMessagePort`), none found (the `NSMachPort` uses only keep run loops alive); the multi-server protocol (`iTermMultiServerProtocol.c`) sends C structures over a socket, with no class names (its class-name uses are descriptions, section 5); the Companion transport (`Companion/`, `sources/Companion/`), no `NSKeyedArchiver`, `NSCoding` or `NSSecureCoding`, none found; the scripting API sends protocol buffers, not archives.

- `sources/SlowOperationXPC/iTermSlowOperationGateway.m:90, 158, 188 (also pidinfo/main.m:23, iTermGitState.m:113, PIDInfoGitState.m:36, pidinfo.m:1000)`: XPC service `com.iterm2.pidinfo`: `pidinfoProtocol`

  **CLOSED.** The app (`iTermSlowOperationGateway.m`, target iTerm2SharedARC) connects to the `pidinfo` XPC service (`pidinfo/main.m`, target pidinfo) with the interface `pidinfoProtocol` (`pidinfo/pidinfoProtocol.h`). NSXPC sends each message as the selector's name plus its arguments, and encodes object arguments and replies with `NSSecureCoding`, recording each object's class name; the receiving side looks the class up by name and accepts it only if it is in the classes allowed for that argument (`setClasses:forSelector:argumentIndex:ofReply:` calls at iTermSlowOperationGateway.m in -[iTermSlowOperationGateway connect], or the declared type). So the protocol's 15 selectors and the classes of its arguments and replies are a wire format: both sides must keep them. Our classes in it: `iTermGitState` (reply of `requestGitStateForPath:gitBase:timeout:includeDiffStats:completion:`), `iTermGitFileStatus` (inside `iTermGitState`, iTermGitState.m in -[iTermGitState encodeWithCoder:] and -[iTermGitState initWithCoder:]) and `iTermDirectoryEntry` (reply of `fetchDirectoryListingOfPath:completion:`); the other argument and reply classes are Foundation (`NSNumber`, `NSData`, `NSString`, `NSArray`, `NSDictionary`) and scalars. The service also passes `iTermGitState` through a pipe: it runs a copy of itself (pidinfo.m in -[pidinfo requestGitStateForPath:gitBase:timeout:includeDiffStats:completion:] onward) whose `PIDInfoGetGitState` writes a keyed archive of the state to standard output (PIDInfoGitState.m in PIDInfoGetGitState), which the parent decodes by class (pidinfo.m in -[pidinfo requestGitStateForPath:gitBase:timeout:includeDiffStats:completion:]). Both sides are built from the same sources into the same app bundle, so a rename is consistent, provided the class's runtime name is the same in every target that compiles it: `iTermGitState.m` and `iTermDirectoryEntry.m` are compiled into both iTerm2SharedARC and pidinfo (project file). A Swift port without `@objc(Name)` would give each target its own module-qualified name (`iTerm2SharedARC.iTermGitState` in the app, `pidinfo.iTermGitState` in the service), and every reply would fail to decode. Crosses a process boundary by name.

  Names: `getProcessInfoForProcessID:flavor:arg:size:reqid:withReply:`, `handshakeWithReply:`, `checkIfDirectoryExists:withReply:`, `checkIfExecutableRegularFile:searchPaths:withReply:`, `statFile:withReply:`, `resolvePathOfDirectory:withReply:`, `runShellScript:shell:mode:withReply:`, `findCompletionsWithPrefix:inDirectories:pwd:maxCount:executable:withReply:`, `requestGitStateForPath:gitBase:timeout:includeDiffStats:completion:`, `fetchRecentBranchesAt:count:completion:`, `findExistingFileWithPrefix:suffix:workingDirectory:trimWhitespace:pathsToIgnore:allowNetworkMounts:reqid:reply:`, `cancelFindExistingFileRequest:reply:`, `executeShellCommand:args:dir:env:reply:`, `fetchDirectoryListingOfPath:completion:`, `fetchUserShellWithReply:`, `iTermGitState`, `iTermGitFileStatus`, `iTermDirectoryEntry`.

- `sources/XPC/iTermSandboxedWorkerClient.m:24 (also iTerm2SandboxedWorker/main.m:68, iTerm2SandboxedWorkerProtocol.h:14, iTerm2SandboxedWorkerProtocol.h:15)`: XPC service `com.iterm2.sandboxed-worker`: `iTerm2SandboxedWorkerProtocol`

  **CLOSED.** The app (`iTermSandboxedWorkerClient.m`, compiled into iTerm2SharedARC) connects to the sandboxed image decoder (`iTerm2SandboxedWorker/main.m`, target iTerm2SandboxedWorker) with the interface `iTerm2SandboxedWorkerProtocol` (`sources/XPC/iTerm2SandboxedWorkerProtocol.h`). No `setClasses:` call: the reply's allowed class comes from the declared block parameter type, `iTermImage`. Its two selectors and the reply class are a wire format, as above. `iTermImage.m` is compiled into both iTerm2SharedARC and iTerm2SandboxedWorker, so the same two-target rule applies; what it encodes inside is Foundation (`NSMutableArray`, `NSNumber`, `NSData`, iTermImage.m in -[iTermImage encodeWithCoder:] and -[iTermImage initWithCoder:]). Crosses a process boundary by name.

  Names: `decodeImageFromData:withReply:`, `decodeImageFromSixelData:withReply:`, `iTermImage`.

### Keyed archives

`NSKeyedArchiver` records the class name of every object it encodes with `encodeObject:` (or as a root object), with no name-to-string call anywhere in the source, and `NSKeyedUnarchiver` finds each class by that name when decoding. So every class in the scope that adopts `NSCoding` or `NSSecureCoding` and whose instances are archived has its name in whatever the archive is written to. An object whose `-encodeWithCoder:` is sent to the archiver directly (rather than passed to `encodeObject:`) does not have its own class recorded, only the classes of the objects it encodes. The NSXPC coder (above) and AppKit's window-restoration coder record class names the same way.

The sites that create an archive in the scope (`git grep` for `NSKeyedArchiver` in Objective-C and Swift, 17 sites; the readers are `NSKeyedUnarchiver` sites and are given in the last column):

| Site | What is archived (class names recorded, as far as the code shows) | Where the data goes | Read back |
|---|---|---|---|
| `ColorPicker/ColorPicker/CPKFavorite.m` in -[CPKFavorite pasteboardPropertyListForType:] | `-[CPKFavorite encodeWithCoder:]` sent to the archiver directly, so `CPKFavorite` itself is not recorded; recorded: the classes of its name, color and identifier (Foundation, AppKit `NSColor`) | **pasteboard (may cross processes and app versions running side by side)**: type `kCPKFavoriteUTI`, dragging a favorite | CPKFavorite.m in -[CPKFavorite initWithPasteboardPropertyList:ofType:] |
| `ColorPicker/ColorPicker/CPKFavoritesView.m` in -[CPKFavoritesView encodedFavorites] | same encoding of each `CPKFavorite` | **disk or user defaults (persisted across versions)**: user defaults key `kCPFavoritesUserDefaultsKey` | CPKFavoritesView.m in -[CPKFavoritesView initWithFrame:colorSpace:] |
| `pidinfo/PIDInfoGitState.m` in PIDInfoGetGitState | `iTermGitState` (root, key `state`), `iTermGitFileStatus`, `NSArray`, `NSString` | **another process (same build)**: a pipe: standard output of a child pidinfo process, read by the parent pidinfo process (XPC entry above) | pidinfo.m in -[pidinfo requestGitStateForPath:gitBase:timeout:includeDiffStats:completion:] |
| `sources/Categories/NSColor+iTerm.m` in -[NSColor(iTerm) stringValue] | `-[NSColor encodeWithCoder:]` sent directly; AppKit's own objects only | **disk or user defaults (persisted across versions)**: base64 string read back by `+colorWithString:` (NSColor+iTerm.m in +[NSColor(iTerm) colorWithString:]), which the highlight triggers use for their stored parameters (HighlightTrigger.m in +[HighlightTrigger colorsPreservingColorSpace:param:], iTermHighlightLineTrigger.m in -[iTermHighlightLineTrigger colorsPreservingColorSpace:param:]) | NSColor+iTerm.m in +[NSColor(iTerm) colorWithString:] |
| `sources/Categories/NSData+iTerm.m` in +[NSData(iTerm) it_dataWithArchivedObject:] | `+it_dataWithArchivedObject:` (key `object`). Callers: iTermRecordingCodec.m in +[iTermRecordingCodec exportRecording:from:to:window:], an `NSDictionary` of the recording and its profile; iTermStatusBarSetupElement.m in -[iTermStatusBarSetupElement pasteboardPropertyListForType:], iTermStatusBarSetupViewController.m in -[iTermStatusBarSetupViewController collectionView:pasteboardWriterForItemAtIndex:] and iTermStatusBarSetupDestinationCollectionViewController.m in -[iTermStatusBarSetupDestinationCollectionViewController collectionView:pasteboardWriterForItemAtIndex:], an `iTermStatusBarSetupElement`, which encodes an `iTermStatusBarBuiltInComponentFactory` or `iTermStatusBarRPCComponentFactory` and a knob dictionary (iTermStatusBarSetupElement.m in -[iTermStatusBarSetupElement encodeWithCoder:]) | **persisted and pasteboard (one helper, several callers)**: the recording: a file the user saves; the status bar element: type `iTermStatusBarElementPasteboardType` | iTermRecordingCodec.m in +[iTermRecordingCodec loadRecording:]; iTermStatusBarSetupDestinationCollectionViewController.m in -[iTermStatusBarSetupDestinationCollectionViewController collectionView:acceptDrop:indexPath:dropOperation:]; iTermStatusBarSetupElement.m in -[iTermStatusBarSetupElement initWithPasteboardPropertyList:ofType:] |
| `sources/Categories/NSData+iTerm.m` in +[NSData(iTerm) it_dataWithSecurelyArchivedObject:error:] | `+it_dataWithSecurelyArchivedObject:error:`. Callers: iTermEncoderGraphRecord.m in -[iTermEncoderGraphRecord data], iTermGraphEncoder.m in -[iTermGraphEncoder encodePropertyList:withKey:] and -[iTermGraphEncoder encodeObject:key:], property-list values of the state-restoration graph | **disk or user defaults (persisted across versions)**: the state-restoration graph database | `-it_unarchivedObjectOfBasicClassesWithError:` (NSData+iTerm.m in -[NSData(iTerm) it_unarchivedObjectOfBasicClassesWithError:]; iTermGraphDatabase.m in -[iTermGraphDatabase loadLargeDataForRowID:], iTermGraphTableTransformer.m in iTermGraphDeltaEncoderMakeGraphRecord), which also allows `iTermTuple` |
| `sources/Categories/NSObject+iTerm.m` in -[NSObject(iTerm) it_keyValueCodedData] | `-it_keyValueCodedData` (key `root`). Caller: PTYSession.m in -[PTYSession encodeArrangementWithContents:encoder:replacementProfile:saveProgram:pendingJumps:options:], `_conductor.tree`, an `NSDictionary` (Conductor.swift in Conductor.tree) | **disk or user defaults (persisted across versions)**: session arrangement (window arrangements and state restoration) | PTYSession.m in +[PTYSession sessionFromArrangement:named:inView:withDelegate:forObjectType:partialAttachments:options:], through NSObject+iTerm.m in +[NSObject(iTerm) it_fromKeyValueCodedData:] (allows `NSArray`, `NSDictionary`, `NSString`, `NSNumber`, `NSDate`) |
| `sources/Codecs/CodableColor.swift` in CodableColor.encode(to:) | `NSColor.encode(with:)` sent directly; AppKit's own objects only | **disk or user defaults (persisted across versions)**: inside the property-list encoding of saved colors (VT100SavedColors.swift in SavedColors.plist and SavedColorsSlot.plist), stored in terminal state (VT100Terminal.m in -[VT100Terminal stateDictionary], VT100ScreenState.m in -[VT100ScreenState savedState]) | CodableColor.swift in CodableColor.init(from:) |
| `sources/Language/CPParser+Cache.m` in -[CPShiftReduceParser(Cache) it_writeToFile:] | the CoreParse parser's `-encodeWithCoder:` sent directly; CoreParse classes (ThirdParty/CoreParse, outside the scope) | **disk or user defaults (persisted across versions)**: a cache file; its key includes the app version (section 5, CPParser+Cache.m in +[CPShiftReduceParser(Cache) it_keyWithBNF:start:]), so a new build does not read an old file | CPParser+Cache.m in +[CPShiftReduceParser(Cache) it_cachedFromFile:] |
| `sources/Popups/PasteboardHistory.m` in -[PasteboardHistory _writeHistoryToDisk] | `NSDictionary` of an array of dictionaries of strings and numbers (`_entriesToDict`) | **disk or user defaults (persisted across versions)**: the paste history file | PasteboardHistory.m in -[PasteboardHistory _loadHistoryFromDisk] |
| `sources/SSH/SSHFilePanelFileList.swift` in SSHFilePanelFileList.outlineView(_:pasteboardWriterForItem:) | `NSDictionary` of the SSH identity's user-defaults object, strings and a boolean | **pasteboard (may cross processes and app versions running side by side)**: types `sshFileNodePasteboardType`, `sshFileNodeDirectoryPasteboardType` | SSHFilePanelSidebar.swift in SSHFilePanelSidebar.outlineView(_:acceptDrop:item:childIndex:) |
| `sources/SSH/SSHFilePanelFileList.swift` in SSHFilePanelFileList.outlineView(_:draggingSession:willBeginAt:forItems:) | same, for each dragged item | **pasteboard (may cross processes and app versions running side by side)**: same types | SSHFilePanelSidebar.swift in SSHFilePanelSidebar.outlineView(_:acceptDrop:item:childIndex:) |
| `sources/Settings/PreferencePanel.m` in -[PreferencePanel bigSurSearchFieldToolbarItem] | an `NSSearchFieldCell` (AppKit) | **in-process only**: unarchived at once with a class substitution (section 5, PreferencePanel.m in -[PreferencePanel bigSurSearchFieldToolbarItem]) | PreferencePanel.m in -[PreferencePanel bigSurSearchFieldToolbarItem] |
| `sources/Settings/Profiles/ProfileListView.m` in -[ProfileListView dataForRow:] | `NSMutableArray` of GUID strings | **pasteboard (may cross processes and app versions running side by side)**: dragging profile rows | ProfileListView.m in -[ProfileListView tableView:acceptDrop:row:dropOperation:] |
| `sources/Settings/TriggerController.m` in -[TriggerController tableView:writeRowsWithIndexes:toPasteboard:] | `NSMutableArray` of `NSNumber` row indexes | **pasteboard (may cross processes and app versions running side by side)**: type `kiTermTriggerControllerPasteboardType` | TriggerController.m in -[TriggerController tableView:acceptDrop:row:dropOperation:] |
| `sources/StateRestoration/iTermRestorableStateSQLite.m` in -[iTermRestorableStateSQLiteRecord unarchiver] | an integer only (`index`) | **in-process only**: unarchived at once | iTermRestorableStateSQLite.m in -[iTermRestorableStateSQLiteRecord unarchiver] |
| `sources/StateRestoration/iTermRestorableStateSaver.m` in -[iTermRestorableStateSaver restorableStateForWindow:] | what `-restorableStateEncodeWithCoder:window:` encodes (iTermApplicationDelegate.m in -[iTermApplicationDelegate restorableStateEncodeWithCoder:window:]): the window's GUID string or arrangement dictionary (PseudoTerminal.m in -[PseudoTerminal openPartialAttachmentsForArrangement:timeout:completion:], iTermWindowImpl.m in -encodeRestorableStateWithCoder: (of each window class that includes the file)) and `NSWindow`'s own restorable state | **disk or user defaults (persisted across versions)**: encrypted restorable-state files | iTermRestorableStateRecord.m in -[iTermRestorableStateRecord unarchiver] |

Totals: 17 sites; disk or user defaults (persisted across versions) 8, pasteboard (may cross processes and app versions running side by side) 5, persisted and pasteboard (one helper, several callers) 1, another process (same build) 1, in-process only 2.

Of the classes recorded, the ones of ours that persist or cross a process boundary are `iTermGitState` and `iTermGitFileStatus` (pipe and XPC, above), `iTermStatusBarSetupElement`, `iTermStatusBarBuiltInComponentFactory` and `iTermStatusBarRPCComponentFactory` (pasteboard, below), and `iTermTuple` (allowed on read, below); `iTermDirectoryEntry` and `iTermImage` are archived only by the NSXPC coder. Every other archive above holds Foundation and AppKit classes as far as the code shows, or classes outside the scope (CoreParse). They are in the names table, marked.

This is to be checked against stored data by the Phase 0 binding tests: [phase0.md section 3](phase0.md), "For every `NSCoding` class name found in the stored-state corpus, `NSClassFromString` finds it." The corpus now exists (`tests/stored-state-corpus/`); the reviewer of that corpus found that its archives hold Foundation classes only, and a scan of its property lists and SQLite blobs for this revision agrees (244 keyed archives; class names `NSArray`, `NSDictionary`, `NSMutableArray`, `NSMutableData`, `NSMutableDictionary`, `NSMutableSet`, `NSNull`). So the corpus does not yet exercise any class of ours; the classes listed here are the ones a corpus entry would need to cover.

- `sources/Categories/NSData+iTerm.m:292 (also iTermStatusBarSetupElement.m:115, iTermStatusBarSetupElement.m:98, iTermStatusBarBaseComponent.m:154, iTermStatusBarRPCProvidedTextComponent.m:256)`: status bar setup elements archived onto the pasteboard

  **OPEN-EXTERNAL.** The keyed archive on the drag pasteboard records the class names `iTermStatusBarSetupElement` (root) and `iTermStatusBarBuiltInComponentFactory` or `iTermStatusBarRPCComponentFactory` (its `componentFactory`); the built-in factory also stores its component class's name as a string (section 3, iTermStatusBarBaseComponent.m in -[iTermStatusBarBuiltInComponentFactory initWithCoder:]). The reader (iTermStatusBarSetupDestinationCollectionViewController.m in -[iTermStatusBarSetupDestinationCollectionViewController collectionView:acceptDrop:indexPath:dropOperation:]) finds these classes by name. Pasteboard data can come from another running copy of the app, possibly a different version. Crosses a process boundary by name (pasteboard archive).

  Names: `iTermStatusBarSetupElement`, `iTermStatusBarBuiltInComponentFactory`, `iTermStatusBarRPCComponentFactory`.

- `sources/Categories/NSData+iTerm.m:331 (also iTermURLStore.m:195, iTermURLStore.m:189)`: `iTermTuple` allowed when reading state-restoration archives

  **OPEN-EXTERNAL.** `-it_unarchivedObjectOfBasicClassesWithError:` allows `iTermTuple` (NSData+iTerm.m in -[NSData(iTerm) it_unarchivedObjectOfBasicClassesWithError:]) when decoding values of the state-restoration graph, and the URL store loads its keys as `iTermTuple` (iTermURLStore.m in -[iTermURLStore loadFromGraphRecord:]). No current writer was found that archives a tuple (`-[iTermURLStore encodeGraphWithEncoder:]` writes nothing), and the stored-state corpus holds none, but an archive that contains one is decoded by that class name. Persisted by name (allowed on read).

  Names: `iTermTuple`.

### Swift classes whose names are persisted or looked up by name

Every Swift class in the scope whose name is persisted or looked up by name in any entry of this file (the class names of the names table that are declared in Swift). A Swift class declared without `@objc(Name)` has a module-qualified runtime name: `NSStringFromClass` returns `<module>.<Name>` for a top-level class, and a keyed archive records the same string. This was confirmed with a Foundation-only probe built with `xcrun swiftc -module-name iTerm2SharedARC` (Swift 6.4): `NSStringFromClass` gave `iTerm2SharedARC.PortholeMark` for `@objc class PortholeMark` and `NamedMark` for `@objc(NamedMark)`, `NSClassFromString` of the qualified name round-tripped, `NSClassFromString("PortholeMark")` was nil, and a nested class got a mangled name (`_TtCO15iTerm2SharedARC5Outer5Inner`). The module is the one the database copy's Swift tables give for the file (`swift_objc_decl` rows joined to `swift_unit.module`; the USRs read `c:@M@iTerm2SharedARC@...`), which for `sources/` is `iTerm2SharedARC`, the target's `PRODUCT_NAME` (`$(TARGET_NAME)`, no `PRODUCT_MODULE_NAME` override in the project file). The stored name of a class without `@objc(Name)` is that module-qualified name, so adding `@objc(Name)` to it would change the name and old data would stop loading.

| Class | Declared at | Runtime name | How the name is set |
|---|---|---|---|
| `HighlightBrowserTrigger` | `sources/Triggers/HighlightBrowserTrigger.swift` in the HighlightBrowserTrigger class | `iTerm2SharedARC.HighlightBrowserTrigger` | no `@objc(Name)`; module iTerm2SharedARC; do not add or change `@objc(Name)`: the stored name is the current runtime name |
| `HyperlinkBrowserTrigger` | `sources/Triggers/HyperlinkBrowserTrigger.swift` in the HyperlinkBrowserTrigger class | `iTerm2SharedARC.HyperlinkBrowserTrigger` | no `@objc(Name)`; module iTerm2SharedARC; do not add or change `@objc(Name)`: the stored name is the current runtime name |
| `InjectJavascriptContentTrigger` | `sources/Triggers/InjectJavascriptTrigger.swift` in the InjectJavascriptContentTrigger class | `InjectJavascriptContentTrigger` | `@objc(InjectJavascriptContentTrigger)` |
| `InjectJavascriptURLTrigger` | `sources/Triggers/InjectJavascriptTrigger.swift` in the InjectJavascriptURLTrigger class | `InjectJavascriptURLTrigger` | `@objc(InjectJavascriptURLTrigger)` |
| `iTermBlockMark` | `sources/Marks/BlockMark.swift` in the BlockMark class | `iTermBlockMark` | `@objc(iTermBlockMark)` |
| `iTermBufferInputTrigger` | `sources/Triggers/BufferInputTrigger.swift` in the BufferInputTrigger class | `iTermBufferInputTrigger` | `@objc(iTermBufferInputTrigger)` |
| `iTermButtonMark` | `sources/Marks/ButtonMark.swift` in the ButtonMark class | `iTermButtonMark` | `@objc(iTermButtonMark)` |
| `iTermEnterWorkgroupBrowserTrigger` | `sources/Triggers/EnterWorkgroupBrowserTrigger.swift` in the EnterWorkgroupBrowserTrigger class | `iTermEnterWorkgroupBrowserTrigger` | `@objc(iTermEnterWorkgroupBrowserTrigger)` |
| `iTermEnterWorkgroupTrigger` | `sources/Triggers/EnterWorkgroupTrigger.swift` in the EnterWorkgroupTrigger class | `iTermEnterWorkgroupTrigger` | `@objc(iTermEnterWorkgroupTrigger)` |
| `iTermExitWorkgroupBrowserTrigger` | `sources/Triggers/ExitWorkgroupBrowserTrigger.swift` in the ExitWorkgroupBrowserTrigger class | `iTermExitWorkgroupBrowserTrigger` | `@objc(iTermExitWorkgroupBrowserTrigger)` |
| `iTermExitWorkgroupTrigger` | `sources/Triggers/ExitWorkgroupTrigger.swift` in the ExitWorkgroupTrigger class | `iTermExitWorkgroupTrigger` | `@objc(iTermExitWorkgroupTrigger)` |
| `iTermFoldMark` | `sources/Marks/FoldMark.swift` in the FoldMark class | `iTermFoldMark` | `@objc(iTermFoldMark)` |
| `iTermFoldTrigger` | `sources/Triggers/FoldTrigger.swift` in the FoldTrigger class | `iTermFoldTrigger` | `@objc(iTermFoldTrigger)` |
| `iTermInjectTrigger` | `sources/Triggers/InjectTrigger.swift` in the InjectTrigger class | `iTermInjectTrigger` | `@objc(iTermInjectTrigger)` |
| `iTermPathMark` | `sources/Marks/PathMark.swift` in the PathMark class | `iTermPathMark` | `@objc(iTermPathMark)` |
| `iTermScriptCallCancellation` | `sources/Language/iTermScriptCallCancellation.swift` in the iTermScriptCallCancellation class | `iTermScriptCallCancellation` | `@objc(iTermScriptCallCancellation)` |
| `iTermSetNamedMarkTrigger` | `sources/Triggers/SetNamedMarkTrigger.swift` in the SetNamedMarkTrigger class | `iTermSetNamedMarkTrigger` | `@objc(iTermSetNamedMarkTrigger)` |
| `iTermSetProfileBooleanTrigger` | `sources/Triggers/SetProfileBooleanTrigger.swift` in the SetProfileBooleanTrigger class | `iTermSetProfileBooleanTrigger` | `@objc(iTermSetProfileBooleanTrigger)` |
| `iTermSetTabStatusTrigger` | `sources/Triggers/SetTabStatusTrigger.swift` in the SetTabStatusTrigger class | `iTermSetTabStatusTrigger` | `@objc(iTermSetTabStatusTrigger)` |
| `iTermSetUserVariableTrigger` | `sources/Triggers/SetUserVariableTrigger.swift` in the SetUserVariableTrigger class | `iTermSetUserVariableTrigger` | `@objc(iTermSetUserVariableTrigger)` |
| `iTermSGRTrigger` | `sources/Triggers/SGRTrigger.swift` in the SGRTrigger class | `iTermSGRTrigger` | `@objc(iTermSGRTrigger)` |
| `iTermStatusBarFilterComponent` | `sources/StatusBar/Components/StatusBarFilterComponent.swift` in the StatusBarFilterComponent class | `iTermStatusBarFilterComponent` | `@objc(iTermStatusBarFilterComponent)` |
| `iTermStatusBarTriggersComponent` | `sources/StatusBar/Components/iTermStatusBarTriggersComponent.swift` in the StatusBarTriggersComponent class | `iTermStatusBarTriggersComponent` | `@objc(iTermStatusBarTriggersComponent)` |
| `PortholeMark` | `sources/Portholes/Porthole.swift` in the PortholeMark class | `iTerm2SharedARC.PortholeMark` | no `@objc(Name)`; module iTerm2SharedARC; do not add or change `@objc(Name)`: the stored name is the current runtime name |
| `ReaderModeBrowserTrigger` | `sources/Triggers/ReaderModeBrowserTrigger.swift` in the ReaderModeBrowserTrigger class | `iTerm2SharedARC.ReaderModeBrowserTrigger` | no `@objc(Name)`; module iTerm2SharedARC; do not add or change `@objc(Name)`: the stored name is the current runtime name |
| `ReloadBrowserTrigger` | `sources/Triggers/ReloadBrowserTrigger.swift` in the ReloadBrowserTrigger class | `ReloadBrowserTrigger` | `@objc(ReloadBrowserTrigger)` |

## 7. OPEN-EXTERNAL sites without an allowlist

For the owner. Each site below takes a name from outside the app. When the
list was written the only check before the call was that the name exists or
that the object responds. The owner's answer (owner queue Q21 item 3): the
two class lookups get a type check, no allowlist, and the four key-binding
selector sites are left as they are. Both class lookups now have the check;
the key-binding rows are unchanged. This is a factual list, not an
assessment.

| Site | Input | Check between input and call |
|---|---|---|
| `sources/StatusBar/Components/iTermStatusBarBaseComponent.m` in -[iTermStatusBarBuiltInComponentFactory initWithCoder:], `-[iTermStatusBarBuiltInComponentFactory initWithCoder:]` | Drag-and-drop data of type `iTermStatusBarElementPasteboardType`, unarchived with `requiresSecureCoding = NO` by `-[NSData it_unarchivedObjectOfClasses:]` (`NSData+iTerm.m` in -[NSData(iTerm) it_unarchivedObjectOfClasses:]), called at `iTermStatusBarSetupDestinationCollectionViewController.m` in -[iTermStatusBarSetupDestinationCollectionViewController collectionView:acceptDrop:indexPath:dropOperation:] | Fixed 2026-11-21 (owner queue Q21 item 3): the class must conform to `iTermStatusBarComponent`. The archive is still decoded without secure coding (the follow-up queued in owner queue Q22) |
| `sources/DataStructuresAlgorithms/IntervalTree.m` in -[IntervalTree restoreFromDictionary:], `-[IntervalTree restoreFromDictionary:]` | Saved interval-tree dictionaries (window arrangements, session restoration) | Fixed 2026-11-21 (owner queue Q21 item 3): the class must conform to `IntervalTreeObject`, as on the graph-record path |
| `sources/SearchingFiltering/iTermFindDriver.m` in -[iTermFindDriver doCommandBySelector:] (and the call at 762; reached from the find bar, iTermDropDownFindViewController.m in -[iTermDropDownFindViewController control:textView:doCommandBySelector:], and the status bar search field, iTermMiniSearchFieldViewController.m in -[iTermMiniSearchFieldViewController control:textView:doCommandBySelector:]) | Cocoa text system key bindings, including the user's `~/Library/KeyBindings/DefaultKeyBinding.dict` | `respondsToSelector:` on `iTermFindDriver`; any one-argument method of that class named by a binding is called |
| `sources/StatusBar/Setup/Knobs/iTermStatusBarKnobNumericViewController.m` in -[iTermStatusBarKnobNumericViewController control:textView:doCommandBySelector:] | Same key bindings | `respondsToSelector:` on the view controller |
| `sources/StatusBar/Setup/Knobs/iTermStatusBarKnobTextViewController.m` in -[iTermStatusBarKnobTextViewController control:textView:doCommandBySelector:] | Same key bindings | `respondsToSelector:` on the view controller |
| `sources/StatusBar/Setup/iTermStatusBarSetupDestinationCollectionViewController.m` in -[iTermStatusBarSetupDestinationCollectionView doCommandBySelector:] | Same key bindings | `respondsToSelector:` on the collection view's delegate |

The other OPEN-EXTERNAL sites check a class against a protocol or base class
(`Trigger.m` in +[Trigger triggerFromUntrustedDict:], `iTermStatusBarLayout.m` in +[iTermStatusBarLayout componentsArrayFromDictionary:scope:], `IntervalTree.m` in -[IntervalTree restoreFromGraphRecord:offset:largeContentProvider:],
`iTermMark.m` in +[iTermMark intervalTreeObjectWithDictionaryWithTypeInformation:]), resolve names only against the sdef (`iTermScriptingWindow`),
or only fire items that already exist in the main menu (`NSMenu+iTerm.m` in -[NSMenu(iTermAdditions) it_selectMenuItemWithTitle:identifier:],
`iTermAPIHelper.m` in -[iTermAPIHelper apiServerMenuItem:handler:]). The trigger action and status bar identifier entries
of section 5 are writers or in-process uses of the same names. The OPEN-EXTERNAL
entries of section 6 are checked by the framework: AppKit requires a window
restoration class to adopt `NSWindowRestoration`, and an unarchiver accepts
only the classes it is given (the status bar pasteboard reader allows
`iTermStatusBarSetupElement` but decodes with `requiresSecureCoding = NO`,
the table row above).

## 8. Non-dynamic reflective sites that matter to a port

Rows whose argument is a string literal or a named constant. The name is
visible in the source, so a search finds it, but the compiler does not check
it: a port that renames the target breaks these silently. Generated by query,
not read one by one; lines are as of the database capture.

```sql
SELECT kind, argument_text, function_or_selector, file, line
FROM reflective_call
WHERE argument_kind IN ('string-literal', 'constant') AND in_migration_scope = 1
ORDER BY kind, argument_text;
```

(`notes/literal_table.py` in the build's scratch directory groups these rows
by name and checks each name against `objc_method`, `objc_property` and
`swift_objc_decl`.) "Resolves" for a key means that a method with the key's
getter name exists somewhere in the database, which does not prove that the
receiver is that class.

| Kind | Name | Sites | Resolves | Where |
|---|---|---|---|---|
| class | `NSAutoresizingMaskLayoutConstraint` | 1 | not in database (SDK or private) | Categories/NSView+iTerm.m in -[NSView(iTerm) it_authoredConstraintCount] NSClassFromString |
| class | `NSTitlebarContainerView` | 1 | not in database (SDK or private) | TerminalView/iTermWindowImpl.m in -preventTitlebarDivider (of each window class that includes the file) NSClassFromString |
| class | `WKPreferences` | 1 | not in database (SDK or private) | Infrastructure/Views/iTermWebViewWrapperViewController.m in -[iTermWebViewFactory webViewWithDelegate:] NSClassFromString |
| class | `WKWebViewConfiguration` | 1 | not in database (SDK or private) | Infrastructure/Views/iTermWebViewWrapperViewController.m in -[iTermWebViewFactory webViewWithDelegate:] NSClassFromString |
| class | `WKWebsiteDataStore` | 1 | not in database (SDK or private) | Infrastructure/Views/iTermWebViewWrapperViewController.m in -[iTermWebViewFactory registerUserScriptInConfiguration:delegate:] NSClassFromString |
| class | `XCTestCase` | 1 | class in database | AppKit/iTermApplicationDelegate.m in -[iTermApplicationDelegate awakeFromNib] NSClassFromString |
| class | `_NSThemeZoomWidgetCell` | 1 | not in database (SDK or private) | Categories/NSObject+iTerm.m in +[NSObject(iTerm) load] NSClassFromString |
| key | `Log Smart Selection Debug Info` | 1 | no getter in database (SDK or dictionary key) | Settings/SmartSelectionController.m in +[SmartSelectionController logDebugInfo] valueForKey: |
| key | `developerExtrasEnabled` | 2 | no getter in database (SDK or dictionary key) | Infrastructure/Views/iTermWebViewWrapperViewController.m in -[iTermWebViewFactory webViewWithDelegate:] setValue:forKey:; Toolbelt/ToolWebView.m in -[ToolWebView initWithFrame:URL:identifier:] setValue:forKey: |
| key | `enabled` | 2 | getter in database | Toolbelt/ToolProfiles.m in -[ToolProfiles initWithFrame:] bind:toObject:withKeyPath:options:; Toolbelt/ToolProfiles.m in -[ToolProfiles initWithFrame:] bind:toObject:withKeyPath:options: |
| key | `position` | 1 | getter in database | StatusBar/Components/iTermStatusBarSparklinesComponent.m in -[iTermStatusBarTimeSeriesLayer animationToMoveLayer:positionXBy:] valueForKey: |
| key | `title` | 1 | getter in database | ThirdParty/PSMTabBarControl/source/PSMTabBarControl.m in -[PSMTabBarControl bindPropertiesForCell:andTabViewItem:] bind:toObject:withKeyPath:options: |
| key-path | `@sum.floatValue` | 1 | collection operator | ThirdParty/PSMTabBarControl/source/PSMYosemiteTabStyle.m in -[PSMYosemiteTabStyle frameForAddTabButtonWithCellWidths:height:] valueForKeyPath: |
| key-path | `doubleValue` | 2 | no getter in database (SDK or dictionary key) | Settings/iTermSlider.m in -[iTermSlider awakeFromNib] addObserver:forKeyPath:options:context:; Settings/iTermSlider.m in -[iTermSlider dealloc] removeObserver:forKeyPath:context: |
| key-path | `effectiveAppearance` | 2 | no getter in database (SDK or dictionary key) | PTYSession/PTYSession.m in -[PTYSession initSynthetic:] addObserver:forKeyPath:options:context:; PTYSession/PTYSession.m in -[PTYSession dealloc] removeObserver:forKeyPath: |
| key-path | `enabled` | 2 | getter in database | Settings/iTermSlider.m in -[iTermSlider awakeFromNib] addObserver:forKeyPath:options:context:; Settings/iTermSlider.m in -[iTermSlider dealloc] removeObserver:forKeyPath:context: |
| key-path | `hasSelection` | 2 | getter in database | Toolbelt/ToolProfiles.m in -[ToolProfiles initWithFrame:] bind:toObject:withKeyPath:options:; Toolbelt/ToolProfiles.m in -[ToolProfiles initWithFrame:] bind:toObject:withKeyPath:options: |
| key-path | `label` | 1 | getter in database | ThirdParty/PSMTabBarControl/source/PSMTabBarControl.m in -[PSMTabBarControl bindPropertiesForCell:andTabViewItem:] bind:toObject:withKeyPath:options: |
| key-path | `lastUse` | 1 | getter in database | ShellIntegration/iTermShellHistoryController.m in -[iTermShellHistoryController removeOldData] initWithKey:ascending:selector: |
| key-path | `modalWindow` | 2 | no getter in database (SDK or dictionary key) | AppKit/iTermApplication.m in -[iTermApplication dealloc] removeObserver:forKeyPath:; AppKit/iTermApplication.m in +[iTermApplication sharedApplication] addObserver:forKeyPath:options:context: |
| key-path | `score` | 1 | getter in database | Popups/PopupModel.m in -[PopupModel sortByScore] initWithKey:ascending: |
| predicate-format | `SELF MATCHES %@` | 1 | n/a | Categories/NSStringITerm.m in -[NSString(iTerm) sanitizedUsername] predicateWithFormat: |
| predicate-format | `lastUse < %f and starred == 0` | 1 | n/a | ShellIntegration/iTermShellHistoryController.m in -[iTermShellHistoryController removeOldData] predicateWithFormat: |
| predicate-format | `starred == 0` | 1 | n/a | ShellIntegration/iTermShellHistoryController.m in -[iTermShellHistoryController removeOldData] predicateWithFormat: |
| predicate-format | `time < %f` | 1 | n/a | ShellIntegration/iTermShellHistoryController.m in -[iTermShellHistoryController removeOldData] predicateWithFormat: |
| selector | `_crashOnException:` | 2 | no method in database | AppKit/iTermApplication.m in iTermInstallCrashOnExceptionHook NSSelectorFromString; AppKit/iTermApplication.m in iTermInstallCrashOnExceptionHook class_getClassMethod |
| selector | `installPythonRuntime:` | 2 | method in database | API/iTermScriptsMenuController.m in -[iTermScriptsMenuController updateInstallRuntimeMenuItem] NSSelectorFromString; API/iTermScriptsMenuController.m in -[iTermScriptsMenuController updateInstallRuntimeMenuItem] setAction: |

Names that resolve to nothing in the database: the classes
`NSAutoresizingMaskLayoutConstraint`, `NSTitlebarContainerView`,
`WKPreferences`, `WKWebViewConfiguration`, `WKWebsiteDataStore` and
`_NSThemeZoomWidgetCell` (SDK or AppKit-private classes, looked up by name to
avoid a link dependency or because they are private); the selector
`_crashOnException:` (private AppKit); the keys `developerExtrasEnabled`
(private WebKit preference), `doubleValue`, `effectiveAppearance` and
`modalWindow` (AppKit properties of SDK classes, not declared in parsed code)
and `Log Smart Selection Debug Info` (a dictionary key read with
`valueForKey:`). None of them is a dead name of ours. `installPythonRuntime:`
is the only string-literal selector of our own (`iTermScriptsMenuController.m` in -[iTermScriptsMenuController updateInstallRuntimeMenuItem]).

## 9. Known gaps

**Swift-side reflection is not in `reflective_call`.** A `git grep` survey of
the Swift files under the scope directories at the commit “Add a sanitized stored-state corpus and the tools that make and check it” (the four type-name and key-path rows at the commit “Add the Swift side of the code database”), by form:

| Form | Hits | Dynamic-looking (argument not a literal or `#selector`) |
|---|---|---|
| `Selector("...")`, `Selector((...))` | 0 | 0 |
| `NSSelectorFromString(` | 2 | 1 |
| `NSClassFromString(` | 0 | 0 |
| `perform(` with a selector (`perform(#selector...`, `.perform(sel...`) | 5 | 2 |
| `value(forKey:`, `value(forKeyPath:` | 0 | 0 |
| `setValue(_:forKey:)` (KVC, not `UserDefaults`) | 11 | 0 |
| `#keyPath(` | 0 | 0 |
| `responds(to:` | 4 | 2 |
| `addObserver`/`removeObserver` `forKeyPath:` | 17 | 2 (overrides that forward) |
| `method(for:` | 2 | 0 |
| `sendAction(` | 10 | 1 (an override that forwards) |
| `NSStringFromSelector(` compared with a string | 2 | 0 |
| `"\(type(of: x))"` (type name interpolated into a string) | 19 in 18 lines | 0 |
| `String(describing: type(of: x))` | 2 | 1 (below) |
| `\(Self.self)` | 7 | 0 |
| key-path KVO, `observe(\.x, ...)` | 7 | 0 |
| runtime functions (`class_getInstanceMethod`, `method_*`, `objc_msgSend`, `class_copyMethodList`, `class_addMethod`) | 0 | 0 |

The dynamic-looking ones; their names are in the names table:

- `sources/FloatingPanes/iTermFloatingPaneView.swift:280, 281, 282`: `NSSelectorFromString(diagonal)`, then `NSCursor.responds(to:)` and `NSCursor.perform(_:)`

  **CLOSED.** `diagonal` is one of two literals, private `NSCursor` class methods.

  Names: `_windowResizeNorthWestSouthEastCursor`, `_windowResizeNorthEastSouthWestCursor`.

- `sources/Browser/UI/iTermURLTextField.swift:236 (also iTermURLBar.swift:319)`: `target.perform(action, with: self)`

  **CLOSED.** The field's action is set only at `iTermURLBar.swift` in iTermURLBarGuts.setupTextFieldDelegate(), `#selector(textFieldSubmitted)` (`-[iTermURLBar textFieldSubmitted]`, no arguments).

  Names: `textFieldSubmitted`.

- `sources/Companion/CompanionWizardWindowController.swift:1012`: `validateMenuItem(_:)` returns `responds(to: action)`

  **CLOSED.** In the sense of the Toolbelt `validateMenuItem:` entries: it reaches only methods of that class that are menu actions: `closeCurrentSession:` (named on the same line) and the main-menu actions validated against the wizard window, which the census owns (section 2's rule).

  Names: `closeCurrentSession:`.

- `sources/MetalRenderer/iTermMetalView.swift:837 (also iTermMetalView_full.swift:729)`: overrides of `addObserver(_:forKeyPath:options:context:)` that forward to `super`

  **GENERIC.** Callers are AppKit and code observing the view; the key paths they pass are theirs.

  Names: none.

- `sources/Infrastructure/Views/PopoverHelpButton.swift:42`: override of `sendAction(_:to:)` that forwards to `super`

  **GENERIC.** The action is whatever the button's owner sets.

  Names: none.

- `sources/Browser/Core/iTermBrowserManager.swift:920 (also iTermBrowserWebView.swift:1011)`: `receiver.doCommand(by: sel)` replays a key-binding command selector

  **OPEN-EXTERNAL.** The selector, received from one broadcasting web view, is replayed on the other web views. It comes from the Cocoa text system key bindings (system and user `DefaultKeyBinding.dict`); `iTermBrowserWebView` overrides `doCommand(by:)` (iTermBrowserWebView.swift in iTermBrowserWebView.doCommand(by:)) and passes it to `WKWebView`, which handles editing commands. Any method of `iTermBrowserWebView` named like a key-binding command would also be reached through `NSResponder`. None is today: a search of iTermBrowserWebView.swift for the command families (`insert...`, `move...`, `delete...`, `scroll...`, `page...`, `select...`, `cancelOperation`) finds only `insertText(_:replacementRange:)` and `scrollWheel(with:)`, which are not commands. So no names. Found while rechecking Swift callers of `doCommandBySelector:` with the database's Swift rows.

  Names: none.

The type-name forms (`"\(type(of: x))"`, `String(describing: type(of: x))`, `\(Self.self)`) give the Swift type name, not the runtime name, and were each read: all but one build a `description`, a log or assertion message, or an error string. The one data use is `TerminalButtonRenderer.swift` in TerminalButtonRenderer.texture(for:tState:), where `String(describing: type(of: button.terminalButton))` is part of a texture cache key (`TextureKey.buttonClassName`) inside the process; a rename changes the key consistently and reaches nothing by name. Key-path KVO in Swift (`observe(\.bounds, ...)` and the like, 7 sites) names the property with a key-path literal that the compiler checks, so it is not a reflective site.

Literal uses worth knowing: `MenuItemPopupView.swift` in NSMenuItem.isWindowMenuItem(parent:) and NSMenuItem.isMoveToDisplayItem(parent:) compare
`NSStringFromSelector` with the private AppKit names `_toggleIPad:` and
`_moveToDisplay:`; `iTermBrowserKeyBindingActionPerformer.swift` in iTermBrowserKeyBindingActionPerformer.perform(keyBindingAction:event:) fires
the main-menu item whose action is `NSSelectorFromString("copy:")`. The
database's Swift side also records 50 `dynamic` references (optional protocol
requirements and `AnyObject` lookups); apart from `iTermURLTextField.swift` in iTermURLTextField.textView(_:doCommandBy:)
above they name their selector statically. The Swift side of the database was
not current when this was written (all 11 modules missing), so the survey is
by text only.

**Swift callers of the helpers.** Swift imports an Objective-C method under a
different name (`registerShortcut:target:selector:userData:` is called as
`register(_:target:selector:userData:)`), so a text search for the Objective-C
spelling misses Swift callers. Every caller list in sections 3 and 4 was
rechecked with the `swift_ref` table of a database copy that has Swift rows
(rows `call` and `init` by Objective-C selector, and the `selector-expr` rows on
the same lines for the `#selector` argument), each hit read in the current
source. The Swift rows reflect the tree a few hours before this revision.

**Code the database did not parse.** The query's "Not parsed" list, limited
to the scope directories:

- `ColorPicker/` (26 files, built by `ColorPicker/ColorPicker.xcodeproj`) and
  five files of `SignedArchive/` (`extract/main.m`, `resign/main.c`,
  `resign/main.m`, `sign/main.m`, `verify/main.m`, built by
  `SignedArchive/SignedArchive.xcodeproj`). A text search of the ColorPicker
  sources, the five `SignedArchive` files and the two unbuilt files below for
  every reflective form of [hidden-callers.md section 3](hidden-callers.md)
  (the compiled `ColorPicker.framework` binary excluded) finds:
  `performSelector` 1 (`iTermTests.m` in RunTestsInObject), `respondsToSelector:` 3
  (`CPKColorWell.m` in -[CPKColorWellView dealloc], `respondsToSelector:@selector(__target)`, a literal;
  `iTermTests.m` in RunTestsInObject), `NSStringFromSelector` 1 (`iTermTests.m` in RunTestsInObject),
  `NSStringFromClass` 2 (descriptions in `CPKColor.m` in -[CPKColor description], `CPKKDTreeNode.m` in -[CPKKDTreeNode description]),
  NSControl `sendAction:to:` 3 (below), runtime functions 2
  (`iTermTests.m` in RunTestsInObject), `setAction:` 9 (all `@selector` literals in
  `CPKColorWell.m`, `CPKControlsView.m`, `CPKSelectionView.m`), and none of
  `NSSelectorFromString`, `sel_registerName`, `sel_getUid`, `sel_getName`,
  `instancesRespondToSelector:`, `NSClassFromString`, `objc_getClass`,
  `objc_lookUpClass`, `tryToPerform:with:`, `targetForAction:`, key-value
  coding or observing with a string, `bind:`, `methodForSelector:`,
  `NSInvocation`, `methodSignatureForSelector:`, forwarding, timer or
  notification selectors, sort descriptors or predicates.
- `sources/iTermTests/iTermTests.m` (compiled by no target): a legacy test
  runner that walks a test class's method list (`class_copyMethodList`) and
  calls each method with `performSelector:`. Not built, so it reaches nothing
  today.
- `sources/ContentAnalysis/iTermWordExtractor.m` (compiled by no target): no
  reflective calls.
- Swift files of `BetterFontPicker/` and `SearchableComboListView/` are in no
  captured module; they are covered by the text survey above.

**Calls the extractor does not record.** `NSStringFromSelector`,
`sel_getName`, `NSStringFromClass`, `class_getName` and `object_getClassName`
are not in the extractor's table; every use was read and section 5 lists the
ones that do more than log. The macro classification with its lint
([hidden-callers.md section 6](hidden-callers.md)) is not part of this file
yet.

NSControl `-sendAction:to:` (two arguments) is not recorded either; only
`-[NSApplication sendAction:to:from:]` is. The sites in scope, by `git grep`:
`sources/Infrastructure/Views/iTermKeyboardNavigatableTableView.m` in -[iTermAutomaticKeyboardNavigatableTableView insertNewline:] and -[iTermAutomaticKeyboardNavigatableOutlineView insertNewline:]
(`-insertNewline:` of `iTermAutomaticKeyboardNavigatableTableView` and
`iTermAutomaticKeyboardNavigatableOutlineView` sends `[self doubleAction]` to
`[self target]`; **GENERIC**: the reach is whatever double action the owner of
each instance sets with `setDoubleAction:` or in a xib; no xib sets a
`doubleAction` on these classes (`git grep`), and the code that sets double
actions passes `@selector` or `#selector` literals), and `ColorPicker/ColorPicker/CPKColorWell.m` in -[CPKColorWell load] and -[CPKColorWell colorChangedByDrag:]
(the color well sends its own `action` to its `target`; **GENERIC**: the
reach is the action set on each color well, in xibs or with `setAction:`, and
those are pinned by the xib binding tests). In Swift the only `sendAction`
override is `PopoverHelpButton.swift` in PopoverHelpButton.sendAction(_:to:) (above). App helpers that take a selector and call it
through an IMP (for example `it_performNonObjectReturningSelector:`) are not
in the table either; they were found because their implementations are
recorded rows, and their callers are section 4.

**Non-code sources of names.** These belong to the entry-point census
([phase0.md section 2](phase0.md)) and the binding tests
([phase0.md section 3](phase0.md)), not to this registry:

- xib and storyboard files: custom classes, actions (including every
  main-menu action reached by the menu-dispatch sites above), outlets,
  bindings and user-defined runtime attributes;
- `iTerm2.sdef`: classes, keys and command methods (the `window` keys reached
  through `iTermScriptingWindow`);
- `Info.plist` files: `NSPrincipalClass`, services, URL handlers;
- Core Data model class names;
- class names in stored dictionaries are the OPEN-EXTERNAL entries of
  section 3 and the writers in section 5; class names that the frameworks
  record (keyed archives, NSXPC, window restoration) are section 6, which
  also lists the archives written to the pasteboard
  (`iTermStatusBarSetupElement.m` in -[iTermStatusBarSetupElement pasteboardPropertyListForType:] and others) and to disk. The
  stored-state corpus and the binding tests check them against real data.

## 10. Not yet classified

None. Every in-scope dynamic row of the database (167 rows, after the seven unused reflective helpers were deleted on 2026-11-20) has an entry.

**Not yet rechecked.** None. In this revision every GENERIC entry and every
CLOSED entry whose names come from callers' arguments was rechecked against
the database's `send` rows and Swift rows (see section 9, "Swift callers of the
helpers"), and the names of every entry were made complete under the rule of
section 2.
