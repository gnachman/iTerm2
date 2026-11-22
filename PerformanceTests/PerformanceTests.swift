//
//  PerformanceTests.swift
//  PerformanceTests
//
//  Performance tests for VT100Screen fast-path optimizations.
//  This target builds with Deployment configuration (optimized, no ASan).
//

import XCTest
import iTerm2SharedARC

class PerformanceTests: XCTestCase {
    private var session = FakeSession()

    private func screen(width: Int32, height: Int32) -> VT100Screen {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session.asScreenDelegate
        XCTAssertEqual(FakeSession.missingScreenDelegateSelectors, [])
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal!.termType = "xterm"
            screen.destructivelySetScreenWidth(width, height: height, mutableState: mutableState)
        })
        return screen
    }

    private func makeMixedToken(_ string: String) -> VT100Token {
        let token = VT100Token()
        token.type = VT100_MIXED_ASCII_CR_LF;
        var data = string.data(using: .utf8)!
        data.withUnsafeMutableBytes { umrbp -> Void in
            let umbp = umrbp.assumingMemoryBound(to: CChar.self)
            token.setAsciiBytes(umbp.baseAddress!,
                                length: Int32(umbp.count))
            token.realizeCRLFs(withCapacity: 10)
            for i in 0..<umbp.count {
                if umbp[i] == 10 || umbp[i] == 13 {
                    token.appendCRLF(Int32(i))
                }
            }
        }
        return token
    }

    // MARK: - Performance Tests

    func testGang_fastPathPerformance() {
        // Use a wide, tall screen with plenty of scrollback so we don't hit
        // edge cases like block drops during the measured loop.
        let screen = self.screen(width: 120, height: 50)
        screen.performBlock(joinedThreads: { _, ms, _ in
            ms.maxScrollbackLines = 100_000
        })

        // Pre-build tokens: 100 lines of 80-char ASCII + CRLF per gang call.
        // This simulates a burst of plain text output (e.g. `cat` of a file).
        let lines = (0..<100).map { i -> String in
            let ch = Character(UnicodeScalar(65 + (i % 26))!)
            return String(repeating: ch, count: 80) + "\r\n"
        }
        let tokens = lines.map { makeMixedToken($0) }

        measure {
            // Each iteration sends 100 gang calls of 100 lines each = 10,000 lines.
            screen.performBlock(joinedThreads: { _, ms, _ in
                for _ in 0..<100 {
                    ms.terminalAppendMixedAsciiGang(tokens)
                }
            })
        }
    }

    func testGang_charAtATimePerformance() {
        // Same workload but using character-at-a-time appendString/CRLF
        // (the pre-gang-optimization path). This is the baseline to beat.
        let screen = self.screen(width: 120, height: 50)
        screen.performBlock(joinedThreads: { _, ms, _ in
            ms.maxScrollbackLines = 100_000
        })

        let lines = (0..<100).map { i -> String in
            let ch = Character(UnicodeScalar(65 + (i % 26))!)
            return String(repeating: ch, count: 80)
        }

        measure {
            screen.performBlock(joinedThreads: { _, ms, _ in
                for _ in 0..<100 {
                    for line in lines {
                        ms.appendString(atCursor: line)
                        ms.appendCarriageReturnLineFeed()
                    }
                }
            })
        }
    }
}

// MARK: - FakeSession

// Adapted from the FakeSession in ModernTests/VT100ScreenTests.swift, which is kept
// up to date with VT100ScreenDelegate. When the protocol changes, copy it again.
//
// This target tests the release configuration, which is built without testability,
// so the Swift classes that are internal to iTerm2SharedARC (CommandOutput,
// ProgramStatusReport, VT100TabStatusUpdate) cannot be named here, and a Swift class
// here cannot declare conformance to VT100ScreenDelegate, whose methods take them.
// Instead every member is exposed to Objective-C with @objcMembers, the methods that
// take those types take NSObject with the protocol's selector, and the conformance
// is added at run time by `asScreenDelegate`. The screen calls its delegate through
// Objective-C messaging, so it sees no difference.
@objcMembers
class FakeSession: NSObject {
    var keyReportingFlagsAtChange = [VT100TerminalKeyReportingFlags]()
    var tmuxInputHandler: ((VT100Token) -> Void)?
    var screen: VT100Screen?
    var configuration = VT100MutableScreenConfiguration()
    var selection = iTermSelection()

    /// Raw OSC 72 content strings delivered via screenDidReceiveKittyDragAndDrop,
    /// in order. Used by KittyDnDParsingTests.
    var kittyDragAndDropContents = [String]()

    /// Every screenLogWorkingDirectory call, in order: the directory and whether the
    /// report proved it came from this machine.
    var loggedWorkingDirectories = [(directory: String?, locality: VT100ScreenWorkingDirectoryLocality)]()

    /// Number of times screenGetWorkingDirectory(forReportedChange:completion:) was invoked. Used by
    /// the OSC 7 receiver tests to assert a pathless report doesn't poll the local
    /// child process for its cwd.
    var getWorkingDirectoryCallCount = 0

    /// What screenGetWorkingDirectory(forReportedChange:completion:) reports, as if polled.
    var workingDirectoryFromPoll: String?

    /// Set true when screenDidReceiveOSC7WhileDisabled fires, so the acceptOSC7
    /// gate test can assert the warning path was taken.
    var didWarnOSC7Disabled = false

    /// OSC 7501 reports delivered via screenReportProgramStatusReports, in order.
    var programStatusReports = [NSObject]()

    /// Times OSC 7501 reports were delivered, however many each delivery held.
    var programStatusDeliveries = 0

    /// OSC 7501 reports and record removals, in the order they arrived.
    var programStatusEvents = [String]()

    /// Times screenRemoveProgramStatusRecords fired (a full reset).
    var removeProgramStatusRecordsCount = 0

    /// The answer to “Allow Terminal-Initiated Download?” and how many times it was asked.
    var allowsDownloads = true
    var downloadConfirmationRequests = 0

    func screenConvertAbsoluteRange(_ range: VT100GridAbsCoordRange, toTextDocumentOfType type: String?, filename: String?, forceWide: Bool) {

    }

    func screenDidReceiveKittyDragAndDrop(_ content: String) {
        kittyDragAndDropContents.append(content)
    }
    
    func screenDidHookSSHConductor(withToken token: String, uniqueID: String, boolArgs: String, sshargs: String, dcsID: String, parentDepth: Int32, savedState: [AnyHashable : Any]) {

    }

    func screenDidFailToParseSSHConductorHook(withToken token: String, uniqueID: String, dcsID: String, parentDepth: Int32, savedState: [AnyHashable : Any]) {

    }
    
    func screenDidReadSSHConductorLine(_ string: String, depth: Int32) {

    }
    
    func screenDidUnhookSSHConductor(withDCSID dcsID: String?, depth: Int32) {

    }
    
    func screenDidBeginSSHConductorCommand(withIdentifier identifier: String, depth: Int32) {

    }
    
    func screenDidEndSSHConductorCommand(withIdentifier identifier: String, type: String, status: UInt8, depth: Int32) {

    }
    
    func screenHandleSSHSideChannelOutput(_ string: String, pid: Int32, channel: UInt8, depth: Int32) {

    }
    
    func screenDidReadSSHPaneOutput(_ data: Data, pid: Int32, depth: Int32) {
    }

    func screenDidReadRawSSHData(_ data: Data) {

    }
    
    func screenDidTerminateSSHProcess(_ pid: Int32, code: Int32, depth: Int32) {

    }

    func screenHandleIT2(_ string: String?, depth: Int32) {

    }

    func screenHandlePulse(_ string: String?, depth: Int32) {

    }

    func screenWillBeginSSHIntegration() {

    }
    
    func screenBeginSSHIntegration(withToken token: String, uniqueID: String, encodedBA: String, sshArgs: String,
                                   injectShellIntegration: Bool) {

    }
    
    func screenEndSSH(_ uniqueID: String) -> Int {
        return 0
    }
    
    func screenSSHLocation() -> String? {
        return "localhost"
    }
    
    func screenBeginFramerRecovery(_ parentDepth: Int32) -> Bool {
        return true
    }
    
    func screenHandleFramerRecoveryString(_ string: String) -> iTerm2SharedARC.ConductorRecovery? {
        nil
    }
    
    func screenFramerRecoveryDidFinish() {

    }
    
    func screenDidResynchronizeSSH() {

    }
    
    func screenEnsureDefaultMode() {

    }
    
    func screenWillSynchronize() {

    }
    
    func screenDidSynchronize() {

    }
    
    @objc(screenOpenURL:completion:)
    func screenOpen(_ url: URL?, completion: @escaping () -> Void) {
        completion()
    }
    
    func screenReportIconTitle() {

    }
    
    func screenReportWindowTitle() {

    }
    
    func screenSetPointerShape(_ pointerShape: String) {

    }
    
    func screenDidShiftLines(atAbsLine absLine: Int64, by delta: Int64, mark: (any iTermWidthSavingMark)?, reason: iTermLinesShiftedReason, replacedRange: NSRange, converter: @escaping (VT100GridCoord) -> VT100GridCoord) {

    }

    func screenDidClearFromAbsoluteLine(toEnd absY: Int64) {

    }

    func screenResizeResilientCoordinates(_ convert: @escaping (VT100GridAbsCoord) -> VT100GridAbsCoord) {

    }

    func screenResizeResilientCoordinates(forSavedTree convert: @escaping (VT100GridAbsCoord) -> VT100GridAbsCoord,
                                          guid savedTreeMainGuid: String) {

    }

    @objc(screenSetTabStatus:)
    func screenSetTabStatus(_ status: NSObject) {

    }

    @objc(screenReportProgramStatusReports:)
    func screenReportProgramStatusReports(_ reports: [NSObject]) {
        programStatusDeliveries += 1
        programStatusReports.append(contentsOf: reports)
        programStatusEvents.append(contentsOf: reports.map { _ in "report" })
    }

    func screenDidClearTabStatusForReset() {

    }

    func screenRemoveProgramStatusRecords() {
        removeProgramStatusRecordsCount += 1
        programStatusEvents.append("remove")
    }

    func screenProgressWasReset(withGeneration generation: Int) {

    }

    @objc(screenProgressProtocolDidReportProgress:generation:)
    func screenProgressProtocolDidReport(_ progress: VT100ScreenProgress, generation: Int) {

    }

    /// (progress, generation) for each screenProgressWasRestored call, in order.
    var restoredProgressReports = [(VT100ScreenProgress, Int)]()

    func screenProgressWasRestored(_ progress: VT100ScreenProgress, generation: Int) {
        restoredProgressReports.append((progress, generation))
    }

    func screenStatPath(_ path: String, queue: dispatch_queue_t, completion: @escaping (Int32, UnsafePointer<stat>) -> Void) {
        var s = stat()
        completion(0, &s)
    }
    
    func screenStartWrappedCommand(_ command: String, channel uid: String) {

    }
    
    func screenSync(_ mutableState: VT100ScreenMutableState) {

    }
    
    func screenUpdateCommandUse(withGuid screenmarkGuid: String, onHost lastRemoteHost: (any VT100RemoteHostReading)?, toReferToMark screenMark: any VT100ScreenMarkReading) {

    }
    
    func screenExecutorDidUpdate(_ update: VT100ScreenTokenExecutorUpdate) {

    }
    
    func screenSwitchToSharedState() -> VT100ScreenState {
        screen!.switchToSharedState()
    }
    
    // Like PTYSession. Without this, the screen keeps reading the mutable state through the
    // sanitizing adapter after the first join, racing the mutation queue.
    @objc(screenRestoreState:)
    func screenRestore(_ state: VT100ScreenState) {
        screen?.restore(state)
    }
    
    func screenConfiguration() -> VT100MutableScreenConfiguration {
        configuration
    }
    
    func screenSyncExpect(_ mutableState: VT100ScreenMutableState) {

    }
    
    func screenOfferToDisableTriggersInInteractiveApps() {

    }
    
    func screenDidUpdateReturnCode(forMark mark: any VT100ScreenMarkReading, remoteHost: (any VT100RemoteHostReading)?) {

    }
    
    func screenCopyString(toPasteboard string: String) {

    }
    
    func screenReportPasteboard(_ pasteboard: String, completion: @escaping () -> Void) {
        completion()
    }
    
    func screenPostUserNotification(_ string: String, rich: Bool) {

    }
    
    @objc(screenRestoreColorsFromSlot:)
    func screenRestoreColors(from slot: SavedColorsSlot) {
    }
    
    func screenStringForKeypress(withCode keycode: UInt16, flags: NSEvent.ModifierFlags, characters: String, charactersIgnoringModifiers: String) -> String? {
        characters
    }
    
    func screenDidAppendImageData(_ data: Data) {

    }
    
    @objc(screenAppendScreenCharArray:metadata:lineBufferGeneration:)
    func screenAppend(_ array: ScreenCharArray, metadata: iTermImmutableMetadata, lineBufferGeneration: Int64) {

    }
    
    func screenApplicationKeypadModeDidChange(_ mode: Bool) {

    }
    
    func screenTerminalAttemptedPasteboardAccess() {

    }
    
    func screenReportFocusWillChange(to reportFocus: Bool) {

    }
    
    func screenReportPasteBracketingWillChange(to bracket: Bool) {

    }
    
    func screenDidReceiveLineFeed(atLineBufferGeneration lineBufferGeneration: Int64) {

    }
    
    func screenSoftAlternateScreenModeDidChange(to enabled: Bool, showingAltScreen showing: Bool) {

    }
    
    func screenReportKeyUpDidChange(_ reportKeyUp: Bool) {

    }
    
    func screenConfirmDownloadNamed(_ name: String, canExceedSize limit: Int) -> Bool {
        true
    }
    
    func screenConfirmDownloadAllowed(_ name: String, size: Int, displayInline: Bool, promptIfBig: UnsafeMutablePointer<ObjCBool>) -> Bool {
        downloadConfirmationRequests += 1
        return allowsDownloads
    }
    
    func screenAskAboutClearingScrollback() {

    }

    func screenDidClearScrollbackWithPermission() {
    }
    
    func screenRangeOfVisibleLines() -> VT100GridRange {
        return VT100GridRangeMake(0, 25)

    }
    
    func screenDidResize() {

    }
    
    func screenSuggestShellIntegrationUpgrade() {

    }
    
    func screenDidDetectShell(_ shell: String) {

    }

    func screenDidReportShellIntegrationVersion(_ version: Int, shell: String?) {
    }
    
    func screenSetBackgroundImageFile(_ filename: String) {

    }
    
    func screenSetBadgeFormat(_ theFormat: String) {

    }
    
    func screenSetUserVar(_ kvp: String) {

    }
    
    func screenShouldReduceFlicker() -> Bool {
        false
    }
    
    func screenUnicodeVersion() -> Int {
        9
    }
    
    func screenSetUnicodeVersion(_ unicodeVersion: Int) {

    }
    
    func screenSetLabel(_ label: String, forKey keyName: String, absLineOfCursor: Int64) {

    }
    
    func screenPushKeyLabels(_ value: String) {

    }
    
    func screenPopKeyLabels(_ value: String) {

    }
    
    func screenSendModifiersDidChange() {

    }
    
    func screenDidResetKeyReportingLocally() {

    }

    func screenKeyReportingFlagsDidChange(_ wholeValueReplaced: Bool) {
        keyReportingFlagsAtChange.append(screen!.terminalKeyReportingFlags)
    }
    
    func screenReportVariableNamed(_ name: String) {

    }
    
    func screenReportCapabilities() {

    }
    
    func screenCommandDidChange(to command: String, atPrompt: Bool, hadCommand: Bool, haveCommand: Bool) {

    }
    
    func screenDidExecuteCommand(_ command: String?, range: VT100GridCoordRange, onHost host: (any VT100RemoteHostReading)?, inDirectory directory: String?, mark: (any VT100ScreenMarkReading)?) {

    }
    
    @objc(screenCommandDidExitWithCode:keyReportingFlags:mark:output:)
    func screenCommandDidExit(withCode code: Int32, keyReportingFlags: VT100TerminalKeyReportingFlags, mark maybeMark: (any VT100ScreenMarkReading)?, output: NSObject?) {

    }
    
    @objc(screenCommandDidAbortWithOutput:command:mark:)
    func screenCommandDidAbort(with output: NSObject?, command: String, mark: any VT100ScreenMarkReading) {

    }
    
    func screenLogWorkingDirectory(onAbsoluteLine absLine: Int64, remoteHost: (any VT100RemoteHostReading)?, withDirectory directory: String?, pushType: VT100ScreenWorkingDirectoryPushType, locality: VT100ScreenWorkingDirectoryLocality, accepted: Bool) {
        loggedWorkingDirectories.append((directory: directory, locality: locality))

    }
    
    func screenDidClearScrollbackBuffer() {

    }
    
    func screenMouseModeDidChange() {

    }
    
    func screenFlashImage(_ identifier: String) {

    }
    
    func screenRequestAttention(_ request: VT100AttentionRequestType) {

    }
    
    func screenDidUseDECRQCRA() {
    }

    func screenDidTryToUseDECRQCRA() {

    }
    
    func screenDisinterSession() {

    }
    
    func screenGetWorkingDirectory(forReportedChange reportedChange: Bool, completion: @escaping (String?) -> Void) {
        getWorkingDirectoryCallCount += 1
        completion(workingDirectoryFromPoll)
    }
    
    func screenSetCursorVisible(_ visible: Bool) {

    }
    
    func screenSetHighlightCursorLine(_ highlight: Bool) {

    }
    
    func screenClearCapturedOutput() {

    }
    
    func screenCursorDidMove(toLine line: Int32) {

    }
    
    func screenHasView() -> Bool {
        true
    }
    
    func screenSaveScrollPosition() {

    }
    
    @objc(screenDidAddMark:alert:completion:)
    func screenDidAdd(_ mark: any iTermMarkProtocol, alert: Bool, completion: @escaping () -> Void) {
        completion()
    }
    
    /// Number of screenPromptDidStart(atLine:) calls. Used by the OSC 7 receiver
    /// tests to assert a shell-integration OSC 7 (machineID present) does not
    /// establish the prompt, while a third-party OSC 7 does.
    var promptDidStartCallCount = 0
    func screenPromptDidStart(atLine line: Int32) {
        promptDidStartCallCount += 1
    }

    func screenPromptOfNonInitialKindDidStart(_ kind: VT100PromptKind) {

    }

    func screenPromptDidEnd(withMark mark: any VT100ScreenMarkReading, command: String?, cursor: VT100GridAbsCoord, workingDirectory: String?, encoding: UInt) {

    }
    
    func screenStealFocus() {

    }
    
    func screenSetProfile(toProfileNamed value: String) {

    }
    
    func screenSetPasteboard(_ value: String) {

    }
    
    func screenDidAddNote(_ note: any PTYAnnotationReading, focus: Bool, visible: Bool) {

    }
    
    @objc(screenDidAddPorthole:)
    func screenDidAdd(_ porthole: any iTerm2SharedARC.ObjCPorthole) {

    }
    
    func screenCopyBufferToPasteboard() {

    }
    
    func screenAppendData(toPasteboard data: Data) {

    }
    
    func screenWillReceiveFileNamed(_ name: String, ofSize size: Int, preconfirmed: Bool) {

    }
    
    func screenDidFinishReceivingFile() {

    }
    
    func screenDidFinishReceivingInlineFile() {

    }
    
    func screenDidReceiveBase64FileData(_ data: String, confirm: (String, Int, Int) -> Void) {
        confirm("string", 0, 1)
    }
    
    func screenFileReceiptEndedUnexpectedly() {

    }

    func screenRequestUpload(_ args: String, completion: @escaping () -> Void) {
        completion()
    }

    func screenSetCurrentTabColor(_ color: NSColor?) {

    }
    
    func screenSetTabColorRedComponent(to color: CGFloat) {

    }
    
    func screenSetTabColorGreenComponent(to color: CGFloat) {

    }
    
    func screenSetTabColorBlueComponent(to color: CGFloat) {

    }
    
    func screenSetColor(_ color: NSColor?, profileKey: String?) -> Bool {
        true
    }

    @objc func screenSetColorBinding(_ expression: String, forProfileKey profileKey: String) {
    }

    func screenResetColor(withColorMapKey key: Int32, profileKey: String, dark: Bool) -> [NSNumber : Any] {
        [:]
    }
    
    func screenSelectColorPresetNamed(_ name: String) {

    }
    
    func screenCurrentHostDidChange(_ host: any VT100RemoteHostReading, pwd workingDirectory: String?, viaSSHIntegration: Bool) {

    }
    
    func screenCurrentDirectoryDidChange(to newPath: String?, remoteHost: (any VT100RemoteHostReading)?) {

    }
    
    func screenDidReceiveCustomEscapeSequence(withParameters parameters: [String : String], payload: String) {

    }
    
    func screenMiniaturizeWindow(_ flag: Bool) {

    }
    
    func screenRaise(_ flag: Bool) {

    }
    
    func screenSetPreferredProxyIcon(_ value: String?) {

    }
    
    func screenWindowIsMiniaturized() -> Bool {
        false
    }
    
    @objc(screenSendReportData:)
    func screenSendReport(_ data: Data) {

    }

    func screenSendTmuxOSC4Report(_ data: Data) {

    }
    
    func screenDidSendAllPendingReports() {

    }
    
    func screenWindowScreenFrame() -> NSRect {
        NSRect(x: 0, y: 0, width: 6000, height: 6000)
    }
    
    func screenWindowFrame() -> NSRect {
        NSRect(x: 0, y: 0, width: 1000, height: 1000)
    }
    
    func screenSize() -> NSSize {
        NSSize(width: 1000, height: 1000)
    }

    @objc(screenPushCurrentTitleForWindow:)
    func screenPushCurrentTitle(forWindow flag: Bool) {

    }

    @objc(screenPopCurrentTitleForWindow:completion:)
    func screenPopCurrentTitle(forWindow flag: Bool, completion: @escaping () -> Void) {
        completion()
    }
    
    func screenNumber() -> Int32 {
        0
    }
    
    func screenWindowIndex() -> Int32 {
        0
    }
    
    func screenTabIndex() -> Int32 {
        0
    }
    
    func screenViewIndex() -> Int32 {
        0
    }
    
    func screenStartTmuxMode(withDCSIdentifier dcsID: String) {

    }
    
    func screenHandleTmuxInput(_ token: VT100Token) {
        tmuxInputHandler?(token)
    }
    
    func screenShouldTreatAmbiguousCharsAsDoubleWidth() -> Bool {
        false
    }
    
    func screenActivateBellAudibly(_ audibleBell: Bool, visibly flashBell: Bool, showIndicator showBellIndicator: Bool, quell: Bool) {

    }
    
    func screenPrintStringIfAllowed(_ printBuffer: String, completion: @escaping () -> Void) {
        completion()
    }
    
    func screenPrintVisibleAreaIfAllowed() {

    }
    
    func screenShouldSendContentsChangedNotification() -> Bool {
        false
    }
    
    func screenRemoveSelection() {

    }
    
    func screenMoveSelectionUp(by n: Int32, inRegion region: VT100GridRect, regionAbsTop: Int64) {

    }
    
    func screenResetTailFind() {

    }
    
    func screenSelection() -> iTermSelection {
        selection
    }
    
    func screenCellSize() -> NSSize {
        NSSize(width: 10, height: 10)
    }
    
    func screenClearHighlights() {

    }
    
    func screenNeedsRedraw() {

    }
    
    func screenScheduleRedrawSoon() {

    }
    
    func screenUpdateDisplay(_ redraw: Bool) {

    }
    
    func screenRefreshFindOnPageView() {

    }
    
    func screenSizeDidChangeWithNewTopLine(at newTop: Int32) {

    }
    
    func screenDidReset() {

    }

    func screenDidReceiveOSC7WhileDisabled() {
        // The screen has already applied the policy; "presenting" is just a record.
        didWarnOSC7Disabled = true
    }

    func screenAllowTitleSetting() -> Bool {
        false
    }
    
    func screenDidAppendString(toCurrentLine string: String, isPlainText plainText: Bool, foreground fg: screen_char_t, background bg: screen_char_t, atPrompt: Bool, encoding: UInt) {

    }
    
    func screenDidAppendAsciiData(toCurrentLine asciiData: Data, foreground fg: screen_char_t, background bg: screen_char_t, atPrompt: Bool) {

    }
    
    func screenRevealComposer(withPrompt prompt: [ScreenCharArray]) {

    }
    
    func screenDismissComposer() {

    }
    
    func screenAppendString(toComposer string: String) {

    }
    
    func screenSetCursorBlinking(_ blink: Bool) {

    }
    
    func screenCursorIsBlinking() -> Bool {
        false
    }
    
    func screenSetCursorType(_ type: ITermCursorType) {

    }
    
    @objc(screenGetCursorType:blinking:)
    func screenGet(_ cursorTypeOut: UnsafeMutablePointer<ITermCursorType>, blinking: UnsafeMutablePointer<ObjCBool>) {

    }
    
    func screenResetCursorTypeAndBlink() {

    }
    
    func screenShouldInitiateWindowResize() -> PTYSessionResizePermission {
        .denied
    }
    
    func screenResize(toWidth width: Int32, height: Int32) {

    }
    
    func screenSetSize(_ proposedSize: VT100GridSize) {

    }
    
    func screenSetPointSize(_ proposedSize: NSSize) {

    }
    
    func screenSetWindowTitle(_ title: String) {

    }
    
    func screenWindowTitle() -> String? {
        "Window Title"
    }
    
    func screenIconTitle() -> String {
        "Icon Title"
    }
    
    func screenSetIconName(_ name: String) {

    }
    
    func screenSetSubtitle(_ subtitle: String) {

    }
    
    func screenName() -> String {
        return "Name"
    }
    
    func screenWindowIsFullscreen() -> Bool {
        false
    }
    
    func screenMoveWindowTopLeftPoint(to point: NSPoint) {

    }

    func screenSetWindowFrame(_ frame: NSRect) {

    }

    let scope = iTermVariableScope()
    func triggerSideEffectVariableScope() -> iTermVariableScope {
        return scope
    }
    
    func triggerSideEffectSetTitle(_ newName: String) {
    }
    
    func triggerSideEffectInvokeFunctionCall(_ invocation: String, withVariables temporaryVariables: [AnyHashable : Any], captures captureStringArray: [String], trigger: Trigger) {
    }
    
    func triggerSideEffectSetValue(_ value: Any?, forVariableNamed name: String) {
    }
    
    func triggerSideEffectCurrentDirectoryDidChange(_ newPath: String) {
    }
    
    func triggerSideEffectShowCapturedOutputTool() {
    }
    
    func triggerWriteTextWithoutBroadcasting(_ text: String) {
    }
    
    func triggerSideEffectShowAlert(withMessage message: String, rateLimit: iTermRateLimitedUpdate, disable: @escaping () -> Void) {
    }
    
    func triggerSideEffectRunBackgroundCommand(_ command: String, pool: iTermBackgroundCommandRunnerPool) {
    }
    
    func triggerSideEffectOpenPasswordManager(toAccountName accountName: String?) {
    }
    
    func triggerSideEffectShowCapturedOutputToolNotVisibleAnnouncementIfNeeded() {

    }

    func triggerSideEffectShowShellIntegrationRequiredAnnouncement() {

    }

    func triggerSideEffectDidCaptureOutput() {

    }

    func triggerSideEffectLaunchCoprocess(withCommand command: String, identifier: String?, silent: Bool, triggerTitle: String) {

    }

    func triggerSideEffectPostUserNotification(withMessage message: String) {

    }

    func triggerSideEffectStopScrolling(atLine absLine: Int64) {

    }

    func triggerSideEffectEnterWorkgroup(withIdentifier workgroupUniqueIdentifier: String) {

    }

    func triggerSideEffectExitWorkgroupLeaderOnly(_ leaderOnly: Bool) {

    }

    func triggerSideEffectSetSessionSpecificProfileBool(_ value: Bool, forKey profileKey: String) {

    }

    private let colorMap = iTermColorMap()

    func immutableColorMap(_ colorMap: (any iTermColorMapReading)!, didChangeColorForKey theKey: iTermColorMapKey, from before: NSColor!, to after: NSColor!) {
    }
    
    func immutableColorMap(_ colorMap: (any iTermColorMapReading)!, dimmingAmountDidChangeTo dimmingAmount: Double) {
    }
    
    func immutableColorMap(_ colorMap: (any iTermColorMapReading)!, mutingAmountDidChangeTo mutingAmount: Double) {
    }
    
    func objectMethodRegistry() -> iTermBuiltInFunctions? {
        return nil
    }
    
    func objectScope() -> iTermVariableScope? {
        return nil
    }

    func screenDidBecomeAutoComposerEligible() {
    }

    func screenDidExecuteCommand(_ command: String?, absRange range: VT100GridAbsCoordRange, onHost host: (any VT100RemoteHostReading)?, inDirectory directory: String?, mark: (any VT100ScreenMarkReading)?, keyReportingFlags: VT100TerminalKeyReportingFlags, paused: Bool) {
    }

    func screenOfferToDisableTriggers(inInteractiveApps stats: String) {
    }

    func screenExecDidFail() {
    }
    func screenSetProfileProperties(_ dict: [AnyHashable : Any]) {
    }

    func triggerSessionSetBufferInput(_ shouldBuffer: Bool) {
    }

    func screenOffscreenCommandLineShouldBeVisibleForCurrentCommand() -> Bool {
        return false
    }

    func screenUpdateBlock(_ blockID: String, action: iTermUpdateBlockAction) {
    }

    func screenPollLocalDirectoryOnly() {
    }
}

extension FakeSession {
    private static let addScreenDelegateConformance: Void = {
        guard let proto = objc_getProtocol("VT100ScreenDelegate") else {
            fatalError("VT100ScreenDelegate is not registered with the Objective-C runtime")
        }
        // Nothing checks the selectors at compile time, so check them here: a method
        // whose Swift name maps to a different selector than the protocol's would
        // otherwise surface as an unrecognized selector in the middle of a measurement.
        missingScreenDelegateSelectors = requiredSelectors(of: proto).filter {
            !class_respondsToSelector(FakeSession.self, $0)
        }.map { NSStringFromSelector($0) }.sorted()
        class_addProtocol(FakeSession.self, proto)
    }()

    // Required VT100ScreenDelegate selectors FakeSession does not implement. Tests
    // assert that this is empty after calling `asScreenDelegate`.
    private(set) static var missingScreenDelegateSelectors = [String]()

    // Required instance methods of `proto` and of the protocols it adopts.
    private static func requiredSelectors(of proto: Protocol) -> [Selector] {
        var result = [Selector]()
        var count: UInt32 = 0
        if let list = protocol_copyMethodDescriptionList(proto, true, true, &count) {
            for i in 0..<Int(count) {
                if let name = list[i].name {
                    result.append(name)
                }
            }
            free(list)
        }
        var protocolCount: UInt32 = 0
        if let adopted = protocol_copyProtocolList(proto, &protocolCount) {
            for i in 0..<Int(protocolCount) where String(cString: protocol_getName(adopted[i])) != "NSObject" {
                result.append(contentsOf: requiredSelectors(of: adopted[i]))
            }
        }
        return result
    }

    // This object as a VT100ScreenDelegate. See the comment on the class.
    var asScreenDelegate: VT100ScreenDelegate {
        _ = Self.addScreenDelegateConformance
        guard let delegate = self as AnyObject as? VT100ScreenDelegate else {
            fatalError("FakeSession does not conform to VT100ScreenDelegate")
        }
        return delegate
    }
}
