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
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState?.terminalEnabled = true
            mutableState!.terminal!.termType = "xterm"
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
            ms!.maxScrollbackLines = 100_000
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
                    ms!.terminalAppendMixedAsciiGang(tokens)
                }
            })
        }
    }

    func testGang_charAtATimePerformance() {
        // Same workload but using character-at-a-time appendString/CRLF
        // (the pre-gang-optimization path). This is the baseline to beat.
        let screen = self.screen(width: 120, height: 50)
        screen.performBlock(joinedThreads: { _, ms, _ in
            ms!.maxScrollbackLines = 100_000
        })

        let lines = (0..<100).map { i -> String in
            let ch = Character(UnicodeScalar(65 + (i % 26))!)
            return String(repeating: ch, count: 80)
        }

        measure {
            screen.performBlock(joinedThreads: { _, ms, _ in
                for _ in 0..<100 {
                    for line in lines {
                        ms!.appendString(atCursor: line)
                        ms!.appendCarriageReturnLineFeed()
                    }
                }
            })
        }
    }
}

// MARK: - FakeSession

class FakeSession: NSObject, VT100ScreenDelegate {
    var screen: VT100Screen?
    var configuration = VT100MutableScreenConfiguration()
    var selection = iTermSelection()

    func screenConvertAbsoluteRange(_ range: VT100GridAbsCoordRange, toTextDocumentOfType type: String?, filename: String?, forceWide: Bool) {}
    func screenDidHookSSHConductor(withToken token: String, uniqueID: String, boolArgs: String, sshargs: String, dcsID: String, savedState: [AnyHashable : Any]) {}
    func screenDidReadSSHConductorLine(_ string: String, depth: Int32) {}
    func screenDidUnhookSSHConductor() {}
    func screenDidBeginSSHConductorCommand(withIdentifier identifier: String, depth: Int32) {}
    func screenDidEndSSHConductorCommand(withIdentifier identifier: String, type: String, status: UInt8, depth: Int32) {}
    func screenHandleSSHSideChannelOutput(_ string: String, pid: Int32, channel: UInt8, depth: Int32) {}
    func screenDidReadRawSSHData(_ data: Data) {}
    func screenDidTerminateSSHProcess(_ pid: Int32, code: Int32, depth: Int32) {}
    func screenWillBeginSSHIntegration() {}
    func screenBeginSSHIntegration(withToken token: String, uniqueID: String, encodedBA: String, sshArgs: String) {}
    func screenEndSSH(_ uniqueID: String) -> Int { 0 }
    func screenSSHLocation() -> String { "localhost" }
    func screenBeginFramerRecovery(_ parentDepth: Int32) {}
    func screenHandleFramerRecoveryString(_ string: String) -> ConductorRecovery? { nil }
    func screenFramerRecoveryDidFinish() {}
    func screenDidResynchronizeSSH() {}
    func screenEnsureDefaultMode() {}
    func screenWillSynchronize() {}
    func screenDidSynchronize() {}
    func screenOpen(_ url: URL?, completion: @escaping () -> Void) { completion() }
    func screenReportIconTitle() {}
    func screenReportWindowTitle() {}
    func screenSetPointerShape(_ pointerShape: String) {}
    func screenFold(_ range: NSRange) {}
    func screenStatPath(_ path: String, queue: dispatch_queue_t, completion: @escaping (Int32, UnsafePointer<stat>) -> Void) {
        var s = stat()
        completion(0, &s)
    }
    func screenStartWrappedCommand(_ command: String, channel uid: String) {}
    func screenSync(_ mutableState: VT100ScreenMutableState) {}
    func screenUpdateCommandUse(withGuid screenmarkGuid: String, onHost lastRemoteHost: (any VT100RemoteHostReading)?, toReferToMark screenMark: any VT100ScreenMarkReading) {}
    func screenExecutorDidUpdate(_ update: VT100ScreenTokenExecutorUpdate) {}
    func screenSwitchToSharedState() -> VT100ScreenState { screen!.switchToSharedState() }
    func screenRestore(_ state: VT100ScreenState) {}
    func screenConfiguration() -> VT100MutableScreenConfiguration { configuration }
    func screenSyncExpect(_ mutableState: VT100ScreenMutableState) {}
    func screenOfferToDisableTriggersInInteractiveApps() {}
    func screenDidUpdateReturnCode(forMark mark: any VT100ScreenMarkReading, remoteHost: (any VT100RemoteHostReading)?) {}
    func screenCopyString(toPasteboard string: String) {}
    func screenReportPasteboard(_ pasteboard: String, completion: @escaping () -> Void) { completion() }
    func screenPostUserNotification(_ string: String, rich: Bool) {}
    func screenRestoreColors(from slot: SavedColorsSlot) {}
    func screenStringForKeypress(withCode keycode: UInt16, flags: NSEvent.ModifierFlags, characters: String, charactersIgnoringModifiers: String) -> String? { characters }
    func screenDidAppendImageData(_ data: Data) {}
    func screenAppend(_ array: ScreenCharArray, metadata: iTermImmutableMetadata, lineBufferGeneration: Int64) {}
    func screenApplicationKeypadModeDidChange(_ mode: Bool) {}
    func screenTerminalAttemptedPasteboardAccess() {}
    func screenReportFocusWillChange(to reportFocus: Bool) {}
    func screenReportPasteBracketingWillChange(to bracket: Bool) {}
    func screenDidReceiveLineFeed(atLineBufferGeneration lineBufferGeneration: Int64) {}
    func screenSoftAlternateScreenModeDidChange(to enabled: Bool, showingAltScreen showing: Bool) {}
    func screenReportKeyUpDidChange(_ reportKeyUp: Bool) {}
    func screenConfirmDownloadNamed(_ name: String, canExceedSize limit: Int) -> Bool { true }
    func screenConfirmDownloadAllowed(_ name: String, size: Int, displayInline: Bool, promptIfBig: UnsafeMutablePointer<ObjCBool>) -> Bool { true }
    func screenAskAboutClearingScrollback() {}
    func screenRangeOfVisibleLines() -> VT100GridRange { VT100GridRangeMake(0, 25) }
    func screenDidResize() {}
    func screenSuggestShellIntegrationUpgrade() {}
    func screenDidDetectShell(_ shell: String) {}
    func screenSetBackgroundImageFile(_ filename: String) {}
    func screenSetBadgeFormat(_ theFormat: String) {}
    func screenSetUserVar(_ kvp: String) {}
    func screenShouldReduceFlicker() -> Bool { false }
    func screenUnicodeVersion() -> Int { 9 }
    func screenSetUnicodeVersion(_ unicodeVersion: Int) {}
    func screenSetLabel(_ label: String, forKey keyName: String) {}
    func screenPushKeyLabels(_ value: String) {}
    func screenPopKeyLabels(_ value: String) {}
    func screenSendModifiersDidChange() {}
    func screenKeyReportingFlagsDidChange() {}
    func screenReportVariableNamed(_ name: String) {}
    func screenReportCapabilities() {}
    func screenCommandDidChange(to command: String, atPrompt: Bool, hadCommand: Bool, haveCommand: Bool) {}
    func screenDidExecuteCommand(_ command: String?, range: VT100GridCoordRange, onHost host: (any VT100RemoteHostReading)?, inDirectory directory: String?, mark: (any VT100ScreenMarkReading)?) {}
    func screenCommandDidExit(withCode code: Int32, mark maybeMark: (any VT100ScreenMarkReading)?) {}
    func screenCommandDidAbort(onLine line: Int32, outputRange: VT100GridCoordRange, command: String, mark: any VT100ScreenMarkReading) {}
    func screenLogWorkingDirectory(onAbsoluteLine absLine: Int64, remoteHost: (any VT100RemoteHostReading)?, withDirectory directory: String?, pushType: VT100ScreenWorkingDirectoryPushType, accepted: Bool) {}
    func screenDidClearScrollbackBuffer() {}
    func screenMouseModeDidChange() {}
    func screenFlashImage(_ identifier: String) {}
    func screenRequestAttention(_ request: VT100AttentionRequestType) {}
    func screenDidTryToUseDECRQCRA() {}
    func screenDisinterSession() {}
    func screenGetWorkingDirectory(completion: @escaping (String?) -> Void) { completion(nil) }
    func screenSetCursorVisible(_ visible: Bool) {}
    func screenSetHighlightCursorLine(_ highlight: Bool) {}
    func screenClearCapturedOutput() {}
    func screenCursorDidMove(toLine line: Int32) {}
    func screenHasView() -> Bool { true }
    func screenSaveScrollPosition() {}
    func screenDidAdd(_ mark: any iTermMarkProtocol, alert: Bool, completion: @escaping () -> Void) { completion() }
    func screenPromptDidStart(atLine line: Int32) {}
    func screenPromptDidEnd(withMark mark: any VT100ScreenMarkReading) {}
    func screenStealFocus() {}
    func screenSetProfile(toProfileNamed value: String) {}
    func screenSetPasteboard(_ value: String) {}
    func screenDidAddNote(_ note: any PTYAnnotationReading, focus: Bool, visible: Bool) {}
    func screenDidAdd(_ porthole: any ObjCPorthole) {}
    func screenCopyBufferToPasteboard() {}
    func screenAppendData(toPasteboard data: Data) {}
    func screenWillReceiveFileNamed(_ name: String, ofSize size: Int, preconfirmed: Bool) {}
    func screenDidFinishReceivingFile() {}
    func screenDidFinishReceivingInlineFile() {}
    func screenDidReceiveBase64FileData(_ data: String, confirm: (String, Int, Int) -> Void) { confirm("", 0, 1) }
    func screenFileReceiptEndedUnexpectedly() {}
    func screenRequestUpload(_ args: String, completion: @escaping () -> Void) { completion() }
    func screenSetCurrentTabColor(_ color: NSColor?) {}
    func screenSetTabColorRedComponent(to color: CGFloat) {}
    func screenSetTabColorGreenComponent(to color: CGFloat) {}
    func screenSetTabColorBlueComponent(to color: CGFloat) {}
    func screenSetColor(_ color: NSColor?, profileKey: String?) -> Bool { true }
    func screenResetColor(withColorMapKey key: Int32, profileKey: String, dark: Bool) -> [NSNumber : Any] { [:] }
    func screenSelectColorPresetNamed(_ name: String) {}
    func screenCurrentHostDidChange(_ host: any VT100RemoteHostReading, pwd workingDirectory: String?, ssh: Bool) {}
    func screenCurrentDirectoryDidChange(to newPath: String?, remoteHost: (any VT100RemoteHostReading)?) {}
    func screenDidReceiveCustomEscapeSequence(withParameters parameters: [String : String], payload: String) {}
    func screenMiniaturizeWindow(_ flag: Bool) {}
    func screenRaise(_ flag: Bool) {}
    func screenSetPreferredProxyIcon(_ value: String?) {}
    func screenWindowIsMiniaturized() -> Bool { false }
    func screenSendReport(_ data: Data) {}
    func screenSendTmuxOSC4Report(_ data: Data) {}
    func screenDidSendAllPendingReports() {}
    func screenWindowScreenFrame() -> NSRect { NSRect(x: 0, y: 0, width: 6000, height: 6000) }
    func screenWindowFrame() -> NSRect { NSRect(x: 0, y: 0, width: 1000, height: 1000) }
    func screenSize() -> NSSize { NSSize(width: 1000, height: 1000) }
    @objc(screenPushCurrentTitleForWindow:)
    func screenPushCurrentTitle(forWindow flag: Bool) {}
    @objc(screenPopCurrentTitleForWindow:completion:)
    func screenPopCurrentTitle(forWindow flag: Bool, completion: @escaping () -> Void) { completion() }
    func screenNumber() -> Int32 { 0 }
    func screenWindowIndex() -> Int32 { 0 }
    func screenTabIndex() -> Int32 { 0 }
    func screenViewIndex() -> Int32 { 0 }
    func screenStartTmuxMode(withDCSIdentifier dcsID: String) {}
    func screenHandleTmuxInput(_ token: VT100Token) {}
    func screenShouldTreatAmbiguousCharsAsDoubleWidth() -> Bool { false }
    func screenActivateBellAudibly(_ audibleBell: Bool, visibly flashBell: Bool, showIndicator showBellIndicator: Bool, quell: Bool) {}
    func screenPrintStringIfAllowed(_ printBuffer: String, completion: @escaping () -> Void) { completion() }
    func screenPrintVisibleAreaIfAllowed() {}
    func screenShouldSendContentsChangedNotification() -> Bool { false }
    func screenRemoveSelection() {}
    func screenMoveSelectionUp(by n: Int32, inRegion region: VT100GridRect) {}
    func screenResetTailFind() {}
    func screenSelection() -> iTermSelection { selection }
    func screenCellSize() -> NSSize { NSSize(width: 10, height: 10) }
    func screenClearHighlights() {}
    func screenNeedsRedraw() {}
    func screenScheduleRedrawSoon() {}
    func screenUpdateDisplay(_ redraw: Bool) {}
    func screenRefreshFindOnPageView() {}
    func screenSizeDidChange(withNewTopLine newTop: Int32) {}
    func screenSizeDidChangeWithNewTopLine(at newTop: Int32) {}
    func screenDidReset() {}
    func screenAllowTitleSetting() -> Bool { false }
    func screenDidAppendString(toCurrentLine string: String, isPlainText plainText: Bool, foreground fg: screen_char_t, background bg: screen_char_t, atPrompt: Bool) {}
    func screenDidAppendAsciiData(toCurrentLine asciiData: Data, foreground fg: screen_char_t, background bg: screen_char_t, atPrompt: Bool) {}
    func screenRevealComposer(withPrompt prompt: [ScreenCharArray]) {}
    func screenDismissComposer() {}
    func screenAppendString(toComposer string: String) {}
    func screenSetCursorBlinking(_ blink: Bool) {}
    func screenCursorIsBlinking() -> Bool { false }
    func screenSetCursorType(_ type: ITermCursorType) {}
    func screenGet(_ cursorTypeOut: UnsafeMutablePointer<ITermCursorType>, blinking: UnsafeMutablePointer<ObjCBool>) {}
    func screenResetCursorTypeAndBlink() {}
    func screenShouldInitiateWindowResize() -> PTYSessionResizePermission { .denied }
    func screenResize(toWidth width: Int32, height: Int32) {}
    func screenSetSize(_ proposedSize: VT100GridSize) {}
    func screenSetPointSize(_ proposedSize: NSSize) {}
    func screenSetWindowTitle(_ title: String) {}
    func screenWindowTitle() -> String? { "Window Title" }
    func screenIconTitle() -> String { "Icon Title" }
    func screenSetIconName(_ name: String) {}
    func screenSetSubtitle(_ subtitle: String) {}
    func screenName() -> String { "Name" }
    func screenWindowIsFullscreen() -> Bool { false }
    func screenMoveWindowTopLeftPoint(to point: NSPoint) {}
    let scope = iTermVariableScope()
    func triggerSideEffectVariableScope() -> iTermVariableScope { scope }
    func triggerSideEffectSetTitle(_ newName: String) {}
    func triggerSideEffectInvokeFunctionCall(_ invocation: String, withVariables temporaryVariables: [AnyHashable : Any], captures captureStringArray: [String], trigger: Trigger) {}
    func triggerSideEffectSetValue(_ value: Any?, forVariableNamed name: String) {}
    func triggerSideEffectCurrentDirectoryDidChange(_ newPath: String) {}
    func triggerSideEffectShowCapturedOutputTool() {}
    func triggerWriteTextWithoutBroadcasting(_ text: String) {}
    func triggerSideEffectShowAlert(withMessage message: String, rateLimit: iTermRateLimitedUpdate, disable: @escaping () -> Void) {}
    func triggerSideEffectRunBackgroundCommand(_ command: String, pool: iTermBackgroundCommandRunnerPool) {}
    func triggerSideEffectOpenPasswordManager(toAccountName accountName: String?) {}
    func triggerSideEffectShowCapturedOutputToolNotVisibleAnnouncementIfNeeded() {}
    func triggerSideEffectShowShellIntegrationRequiredAnnouncement() {}
    func triggerSideEffectDidCaptureOutput() {}
    func triggerSideEffectLaunchCoprocess(withCommand command: String, identifier: String?, silent: Bool, triggerTitle: String) {}
    func triggerSideEffectPostUserNotification(withMessage message: String) {}
    func triggerSideEffectStopScrolling(atLine absLine: Int64) {}
    func immutableColorMap(_ colorMap: (any iTermColorMapReading)!, didChangeColorForKey theKey: iTermColorMapKey, from before: NSColor!, to after: NSColor!) {}
    func immutableColorMap(_ colorMap: (any iTermColorMapReading)!, dimmingAmountDidChangeTo dimmingAmount: Double) {}
    func immutableColorMap(_ colorMap: (any iTermColorMapReading)!, mutingAmountDidChangeTo mutingAmount: Double) {}
    func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
    func objectScope() -> iTermVariableScope? { nil }
    func screenDidBecomeAutoComposerEligible() {}
    func screenDidExecuteCommand(_ command: String?, absRange range: VT100GridAbsCoordRange, onHost host: (any VT100RemoteHostReading)?, inDirectory directory: String?, mark: (any VT100ScreenMarkReading)?, paused: Bool) {}
    func screenOfferToDisableTriggers(inInteractiveApps stats: String) {}
    func screenExecDidFail() {}
    func screenSetProfileProperties(_ dict: [AnyHashable : Any]) {}
    func triggerSessionSetBufferInput(_ shouldBuffer: Bool) {}
    func screenOffscreenCommandLineShouldBeVisibleForCurrentCommand() -> Bool { false }
    func screenUpdateBlock(_ blockID: String, action: iTermUpdateBlockAction) {}
    func screenPollLocalDirectoryOnly() {}
}
