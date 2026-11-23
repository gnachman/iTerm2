//
//  BindingTestTables.swift
//  ModernTests
//
//  Checked-in tables for the binding tests (BindingTests.swift). Each is
//  data that a test compares the real tree with, so that a change shows up
//  as a failing test and a reviewable diff of this file.
//

import Foundation

enum BindingTestTables {
    // MARK: Where the sources are

    // For each place in the app bundle that holds compiled nibs, the
    // repository directories that hold their source xibs and storyboards. A
    // compiled nib is matched to the source of the same base name under
    // these directories; more than one candidate fails the test.
    static let nibSourceRoots: [(bundleLocation: String, sourceRoots: [String])] = [
        ("Contents/Resources", ["sources", "ThirdParty/UKCrashReporter"]),
        ("Contents/Frameworks/BetterFontPicker.framework", ["BetterFontPicker/BetterFontPicker"]),
        ("Contents/Frameworks/SearchableComboListView.framework", ["SearchableComboListView/SearchableComboView"]),
    ]

    // Compiled nibs in the app bundle that have no source in this
    // repository, or whose classes are not in the test host.
    static let excludedNibLocations: [String: String] = [
        "Contents/Frameworks/Sparkle.framework": "third-party binary framework (ThirdParty/Sparkle.framework); no source xib in the repository",
        "Contents/MacOS/iTerm2ImportStatus.app": "a separate helper app with its own process; its classes are not loaded in the test host",
    ]

    // MARK: Scripting

    // iTermScriptingWindow is an NSProxy (sources/API/iTermScriptingWindow.m)
    // that forwards valueForKey:, setValue:forKey: and every message it does
    // not implement to the window it wraps. iTermApplication
    // -orderedScriptingWindows wraps only windows conforming to the PTYWindow
    // protocol, so the sdef's window keys and methods are checked on every
    // app class that conforms to it.
    static let sdefForwardingProtocols: [String: String] = [
        "iTermScriptingWindow": "PTYWindow",
    ]

    // MARK: Info.plist

    // -[iTermApplicationDelegate applicationDidFinishLaunching:]
    // (sources/AppKit/iTermApplicationDelegate.m) calls
    // [NSApp setServicesProvider:[[iTermServiceProvider alloc] init]].
    static let servicesProvider = "iTermServiceProvider"

    // MARK: Names persisted or sent between processes

    // From docs/swift-migration/reflective-sites.md: every class row of the
    // "Names that must be preserved" table (section 2) whose note says
    // "persisted by name" or "crosses a process boundary", with its "Runtime
    // name" column. Section 6 explains each group. Keep in step with that
    // registry; the test does not parse the markdown.
    static let persistedNames: [BindingPersistedNamesChecker.Name] = [
        .init(name: "AlertTrigger", runtimeName: "AlertTrigger", kind: .persisted),
        .init(name: "AnnotateTrigger", runtimeName: "AnnotateTrigger", kind: .persisted),
        .init(name: "BellTrigger", runtimeName: "BellTrigger", kind: .persisted),
        .init(name: "BounceTrigger", runtimeName: "BounceTrigger", kind: .persisted),
        .init(name: "CaptureTrigger", runtimeName: "CaptureTrigger", kind: .persisted),
        .init(name: "CoprocessTrigger", runtimeName: "CoprocessTrigger", kind: .persisted),
        .init(name: "GrowlTrigger", runtimeName: "GrowlTrigger", kind: .persisted),
        .init(name: "HighlightBrowserTrigger", runtimeName: "iTerm2SharedARC.HighlightBrowserTrigger", kind: .persisted),
        .init(name: "HighlightTrigger", runtimeName: "HighlightTrigger", kind: .persisted),
        .init(name: "HyperlinkBrowserTrigger", runtimeName: "iTerm2SharedARC.HyperlinkBrowserTrigger", kind: .persisted),
        .init(name: "InjectJavascriptContentTrigger", runtimeName: "InjectJavascriptContentTrigger", kind: .persisted),
        .init(name: "InjectJavascriptURLTrigger", runtimeName: "InjectJavascriptURLTrigger", kind: .persisted),
        .init(name: "iTermBlockMark", runtimeName: "iTermBlockMark", kind: .persisted),
        .init(name: "iTermBufferInputTrigger", runtimeName: "iTermBufferInputTrigger", kind: .persisted),
        .init(name: "iTermButtonMark", runtimeName: "iTermButtonMark", kind: .persisted),
        .init(name: "iTermCapturedOutputMark", runtimeName: "iTermCapturedOutputMark", kind: .persisted),
        .init(name: "iTermDirectoryEntry", runtimeName: "iTermDirectoryEntry", kind: .xpc),
        .init(name: "iTermEnterWorkgroupBrowserTrigger", runtimeName: "iTermEnterWorkgroupBrowserTrigger", kind: .persisted),
        .init(name: "iTermEnterWorkgroupTrigger", runtimeName: "iTermEnterWorkgroupTrigger", kind: .persisted),
        .init(name: "iTermExitWorkgroupBrowserTrigger", runtimeName: "iTermExitWorkgroupBrowserTrigger", kind: .persisted),
        .init(name: "iTermExitWorkgroupTrigger", runtimeName: "iTermExitWorkgroupTrigger", kind: .persisted),
        .init(name: "iTermFoldMark", runtimeName: "iTermFoldMark", kind: .persisted),
        .init(name: "iTermFoldTrigger", runtimeName: "iTermFoldTrigger", kind: .persisted),
        .init(name: "iTermGitFileStatus", runtimeName: "iTermGitFileStatus", kind: .xpc),
        .init(name: "iTermGitState", runtimeName: "iTermGitState", kind: .xpc),
        .init(name: "iTermHighlightLineTrigger", runtimeName: "iTermHighlightLineTrigger", kind: .persisted),
        .init(name: "iTermHyperlinkTrigger", runtimeName: "iTermHyperlinkTrigger", kind: .persisted),
        .init(name: "iTermImage", runtimeName: "iTermImage", kind: .xpc),
        .init(name: "iTermImageMark", runtimeName: "iTermImageMark", kind: .persisted),
        .init(name: "iTermInjectTrigger", runtimeName: "iTermInjectTrigger", kind: .persisted),
        .init(name: "iTermMark", runtimeName: "iTermMark", kind: .persisted),
        .init(name: "iTermPathMark", runtimeName: "iTermPathMark", kind: .persisted),
        .init(name: "iTermProfilesWindowRestorer", runtimeName: "iTermProfilesWindowRestorer", kind: .appkit),
        .init(name: "iTermRPCTrigger", runtimeName: "iTermRPCTrigger", kind: .persisted),
        .init(name: "iTermSetNamedMarkTrigger", runtimeName: "iTermSetNamedMarkTrigger", kind: .persisted),
        .init(name: "iTermSetProfileBooleanTrigger", runtimeName: "iTermSetProfileBooleanTrigger", kind: .persisted),
        .init(name: "iTermSetTabStatusTrigger", runtimeName: "iTermSetTabStatusTrigger", kind: .persisted),
        .init(name: "iTermSetTitleTrigger", runtimeName: "iTermSetTitleTrigger", kind: .persisted),
        .init(name: "iTermSetUserVariableTrigger", runtimeName: "iTermSetUserVariableTrigger", kind: .persisted),
        .init(name: "iTermSGRTrigger", runtimeName: "iTermSGRTrigger", kind: .persisted),
        .init(name: "iTermShellPromptTrigger", runtimeName: "iTermShellPromptTrigger", kind: .persisted),
        .init(name: "iTermStatusBarActionComponent", runtimeName: "iTermStatusBarActionComponent", kind: .persisted),
        .init(name: "iTermStatusBarActionMenuComponent", runtimeName: "iTermStatusBarActionMenuComponent", kind: .persisted),
        .init(name: "iTermStatusBarAttributedTextComponent", runtimeName: "iTermStatusBarAttributedTextComponent", kind: .persisted),
        .init(name: "iTermStatusBarBatteryComponent", runtimeName: "iTermStatusBarBatteryComponent", kind: .persisted),
        .init(name: "iTermStatusBarBuiltInComponentFactory", runtimeName: "iTermStatusBarBuiltInComponentFactory", kind: .pasteboard),
        .init(name: "iTermStatusBarClockComponent", runtimeName: "iTermStatusBarClockComponent", kind: .persisted),
        .init(name: "iTermStatusBarComposerComponent", runtimeName: "iTermStatusBarComposerComponent", kind: .persisted),
        .init(name: "iTermStatusBarCPUUtilizationComponent", runtimeName: "iTermStatusBarCPUUtilizationComponent", kind: .persisted),
        .init(name: "iTermStatusBarFilterComponent", runtimeName: "iTermStatusBarFilterComponent", kind: .persisted),
        .init(name: "iTermStatusBarFixedSpacerComponent", runtimeName: "iTermStatusBarFixedSpacerComponent", kind: .persisted),
        .init(name: "iTermStatusBarFunctionCallComponent", runtimeName: "iTermStatusBarFunctionCallComponent", kind: .persisted),
        .init(name: "iTermStatusBarGitComponent", runtimeName: "iTermStatusBarGitComponent", kind: .persisted),
        .init(name: "iTermStatusBarHostnameComponent", runtimeName: "iTermStatusBarHostnameComponent", kind: .persisted),
        .init(name: "iTermStatusBarJobComponent", runtimeName: "iTermStatusBarJobComponent", kind: .persisted),
        .init(name: "iTermStatusBarMemoryUtilizationComponent", runtimeName: "iTermStatusBarMemoryUtilizationComponent", kind: .persisted),
        .init(name: "iTermStatusBarNetworkUtilizationComponent", runtimeName: "iTermStatusBarNetworkUtilizationComponent", kind: .persisted),
        .init(name: "iTermStatusBarPlaceholderComponent", runtimeName: "iTermStatusBarPlaceholderComponent", kind: .persisted),
        .init(name: "iTermStatusBarProgressComponent", runtimeName: "iTermStatusBarProgressComponent", kind: .persisted),
        .init(name: "iTermStatusBarRPCComponentFactory", runtimeName: "iTermStatusBarRPCComponentFactory", kind: .pasteboard),
        .init(name: "iTermStatusBarRPCProvidedAttributedTextComponent", runtimeName: "iTermStatusBarRPCProvidedAttributedTextComponent", kind: .persisted),
        .init(name: "iTermStatusBarRPCProvidedTextComponent", runtimeName: "iTermStatusBarRPCProvidedTextComponent", kind: .persisted),
        .init(name: "iTermStatusBarSearchFieldComponent", runtimeName: "iTermStatusBarSearchFieldComponent", kind: .persisted),
        .init(name: "iTermStatusBarSetupElement", runtimeName: "iTermStatusBarSetupElement", kind: .pasteboard),
        .init(name: "iTermStatusBarSnippetMenuComponent", runtimeName: "iTermStatusBarSnippetMenuComponent", kind: .persisted),
        .init(name: "iTermStatusBarSparklinesComponent", runtimeName: "iTermStatusBarSparklinesComponent", kind: .persisted),
        .init(name: "iTermStatusBarSpringComponent", runtimeName: "iTermStatusBarSpringComponent", kind: .persisted),
        .init(name: "iTermStatusBarSwiftyStringComponent", runtimeName: "iTermStatusBarSwiftyStringComponent", kind: .persisted),
        .init(name: "iTermStatusBarTextComponent", runtimeName: "iTermStatusBarTextComponent", kind: .persisted),
        .init(name: "iTermStatusBarTmuxLeftComponent", runtimeName: "iTermStatusBarTmuxLeftComponent", kind: .persisted),
        .init(name: "iTermStatusBarTmuxRightComponent", runtimeName: "iTermStatusBarTmuxRightComponent", kind: .persisted),
        .init(name: "iTermStatusBarTriggersComponent", runtimeName: "iTermStatusBarTriggersComponent", kind: .persisted),
        .init(name: "iTermStatusBarUsernameComponent", runtimeName: "iTermStatusBarUsernameComponent", kind: .persisted),
        .init(name: "iTermStatusBarVariableBaseComponent", runtimeName: "iTermStatusBarVariableBaseComponent", kind: .persisted),
        .init(name: "iTermStatusBarWorkingDirectoryComponent", runtimeName: "iTermStatusBarWorkingDirectoryComponent", kind: .persisted),
        .init(name: "iTermTuple", runtimeName: "iTermTuple", kind: .persisted),
        .init(name: "iTermUserNotificationTrigger", runtimeName: "iTermUserNotificationTrigger", kind: .persisted),
        .init(name: "MarkTrigger", runtimeName: "MarkTrigger", kind: .persisted),
        .init(name: "MuteCoprocessTrigger", runtimeName: "MuteCoprocessTrigger", kind: .persisted),
        .init(name: "PasswordTrigger", runtimeName: "PasswordTrigger", kind: .persisted),
        .init(name: "PortholeMark", runtimeName: "iTerm2SharedARC.PortholeMark", kind: .persisted),
        .init(name: "PseudoTerminalRestorer", runtimeName: "PseudoTerminalRestorer", kind: .appkit),
        .init(name: "PTYAnnotation", runtimeName: "PTYAnnotation", kind: .persisted),
        .init(name: "ReaderModeBrowserTrigger", runtimeName: "iTerm2SharedARC.ReaderModeBrowserTrigger", kind: .persisted),
        .init(name: "ReloadBrowserTrigger", runtimeName: "ReloadBrowserTrigger", kind: .persisted),
        .init(name: "ScriptTrigger", runtimeName: "ScriptTrigger", kind: .persisted),
        .init(name: "SendTextTrigger", runtimeName: "SendTextTrigger", kind: .persisted),
        .init(name: "SetDirectoryTrigger", runtimeName: "SetDirectoryTrigger", kind: .persisted),
        .init(name: "SetHostnameTrigger", runtimeName: "SetHostnameTrigger", kind: .persisted),
        .init(name: "StopTrigger", runtimeName: "StopTrigger", kind: .persisted),
        .init(name: "VT100RemoteHost", runtimeName: "VT100RemoteHost", kind: .persisted),
        .init(name: "VT100ScreenMark", runtimeName: "VT100ScreenMark", kind: .persisted),
        .init(name: "VT100WorkingDirectory", runtimeName: "VT100WorkingDirectory", kind: .persisted),
    ]

    // Section 6, "Classes and selectors sent between processes": the two XPC
    // protocols and their selectors, a wire format.
    static let xpcProtocols: [(name: String, selectors: [String])] = [
        ("pidinfoProtocol", [
            "getProcessInfoForProcessID:flavor:arg:size:reqid:withReply:",
            "handshakeWithReply:",
            "checkIfDirectoryExists:withReply:",
            "checkIfExecutableRegularFile:searchPaths:withReply:",
            "statFile:withReply:",
            "resolvePathOfDirectory:withReply:",
            "runShellScript:shell:mode:environment:withReply:",
            "findCompletionsWithPrefix:inDirectories:pwd:maxCount:executable:withReply:",
            "requestGitStateForPath:gitBase:timeout:includeDiffStats:completion:",
            "fetchRecentBranchesAt:count:completion:",
            "findExistingFileWithPrefix:suffix:workingDirectory:trimWhitespace:pathsToIgnore:allowNetworkMounts:reqid:reply:",
            "cancelFindExistingFileRequest:reply:",
            "executeShellCommand:args:dir:env:reply:",
            "fetchDirectoryListingOfPath:completion:",
            "fetchUserShellWithReply:",
        ]),
        ("iTerm2SandboxedWorkerProtocol", [
            "decodeImageFromData:withReply:",
            "decodeImageFromSixelData:withReply:",
        ]),
    ]

    // Section 6, "Window restoration".
    static let restorationClasses = ["PseudoTerminalRestorer", "iTermProfilesWindowRestorer"]
    static let restorationSelector = "restoreWindowWithIdentifier:state:completionHandler:"

    // MARK: Known failures

    // Names that do not resolve on the real tree today. Each is a finding,
    // not a reason to weaken a test: the test fails when a new problem
    // appears and when one of these stops happening. Keys are
    // file|kind|element id|name, as printed by a failing test.
    static let knownFailures: [String: String] = [
        "iTerm2.sdef|propertyKey|class application|name":
            "no -name on iTermApplication or NSApplication; Cocoa scripting may answer the standard application name outside key-value coding, and iTermApplication's -valueForUndefinedKey: returns an empty array, so unconfirmed (check in Script Editor)",
        "iTerm2.sdef|propertyKey|class application|version":
            "no -version on iTermApplication or NSApplication; same as name: possibly answered outside key-value coding, unconfirmed",
        "iTerm2.sdef|propertyKey|class session|useUnderlineColor":
            "defect: the sdef property “use underline color” (added in f7772b24c) has no -useUnderlineColor on PTYSession; only underlineColor was implemented",
        "iTerm2.sdef|propertyKey|class tab|currentSession":
            "not a defect: PTYTab+Scripting.m overrides -valueForKey: and answers currentSession there, which the runtime check cannot see",
        "iTerm2.sdef|propertyKey|class window|scriptFrame":
            "defect: the deprecated window property “frame” (added to the sdef in 2a55712c1, 2015) was never implemented; no -scriptFrame anywhere",
        "iTerm2.sdef|propertyKey|class window|scriptOrigin":
            "defect: the deprecated window property “origin” was never implemented; no -scriptOrigin anywhere",
        "iTerm2.sdef|propertyKey|class window|scriptPosition":
            "defect: the deprecated window property “position” was never implemented; no -scriptPosition anywhere",
        "iTerm2.sdef|propertyKey|class window|scriptSize":
            "defect: the deprecated window property “size” was never implemented; no -scriptSize anywhere",
        "iTerm2.sdef|propertySetter|class application|currentScriptingWindow":
            "declared read-write in the sdef (no access attribute) but there is no setter, so setting it from AppleScript should fail with an undefined-key error (not tried)",
        "iTerm2.sdef|propertySetter|class session|isAtShellPrompt":
            "declared read-write in the sdef (no access attribute) but there is no setter, so setting it from AppleScript should fail with an undefined-key error (not tried)",
        "iTerm2.sdef|propertySetter|class session|isProcessing":
            "declared read-write in the sdef (no access attribute) but there is no setter, so setting it from AppleScript should fail with an undefined-key error (not tried)",
        "iTerm2.sdef|propertySetter|class session|text":
            "declared read-write in the sdef (no access attribute) but there is no setter, so setting it from AppleScript should fail with an undefined-key error (not tried) (property “contents”; “text” is declared read-only)",
        "iTerm2.sdef|propertySetter|class tab|indexOfTab":
            "declared read-write in the sdef (no access attribute) but there is no setter, so setting it from AppleScript should fail with an undefined-key error (not tried)",
        "iTerm2.sdef|propertySetter|class tab|title":
            "declared read-write in the sdef (no access attribute) but there is no setter, so setting it from AppleScript should fail with an undefined-key error (not tried)",
        "iTerm2.sdef|propertySetter|class window|currentSession":
            "declared read-write in the sdef (no access attribute) but there is no setter, so setting it from AppleScript should fail with an undefined-key error (not tried)",
        "iTerm2.sdef|propertySetter|class window|currentTab":
            "declared read-write in the sdef (no access attribute) but there is no setter, so setting it from AppleScript should fail with an undefined-key error (not tried)",
        "iTerm2.sdef|propertySetter|class window|hotkeyWindowProfile":
            "declared read-write in the sdef (no access attribute) but there is no setter, so setting it from AppleScript should fail with an undefined-key error (not tried)",
        "iTerm2.sdef|propertySetter|class window|isHotkeyWindow":
            "declared read-write in the sdef (no access attribute) but there is no setter, so setting it from AppleScript should fail with an undefined-key error (not tried)",
        "iTerm2.sdef|propertySetter|class window|scriptFrontmost":
            "declared read-write in the sdef (no access attribute) but there is no setter, so setting it from AppleScript should fail with an undefined-key error (not tried)",
        "SearchableComboListView/SearchableComboView/SearchableComboView.xib|customClass|-2|iTerm2SharedARC.SearchableComboListViewController":
            "stale module in the xib: the File's Owner hint names module iTerm2SharedARC but the class is compiled into SearchableComboListView. A placeholder is never instantiated and the real owner is passed in, so this is harmless at run time, but its outlets and actions go unchecked here",
        "SearchableComboListView/SearchableComboView/SearchableComboView.xib|outlet|vP3-ph-tDM|tableView":
            "defect: dead outlet since 817462d8d (2021); SearchableComboContentView has no tableView property. AppKit logs “Failed to connect (tableView) outlet ... missing setter or instance variable” on every load and leaves it unconnected",
    ]
}
