//
//  iTermRenderingComparer.swift
//  iTerm2SharedARC
//
//  Compares GPU and legacy terminal rendering, invoked via CLI flag.
//

import Foundation

// MARK: - Headless WindowControllerInterface stub

@objc(iTermHeadlessWindowController)
class iTermHeadlessWindowController: NSObject, WindowControllerInterface {
    private let frameRect: NSRect

    @objc init(frame: NSRect) {
        self.frameRect = frame
        super.init()
    }

    func sessionInitiatedResize(_ session: PTYSession!, width: Int32, height: Int32) -> Bool { true }
    func fullScreen() -> Bool { false }
    func anyFullScreen() -> Bool { false }
    func movesWhenDraggedOntoSelf() -> Bool { false }
    @objc(closeSession:) func close(_ s: PTYSession!) {}
    @objc(softCloseSession:) func softClose(_ s: PTYSession!) {}
    func nextTab(_ sender: Any!) {}
    func previousTab(_ sender: Any!) {}
    func createDuplicate(of tab: PTYTab!) {}
    func updateTabColors() {}
    func enableBlur(_ radius: Double) {}
    func disableBlur() {}
    func fitWindow(to tab: PTYTab!) {}
    func tabView() -> PTYTabView! { nil }
    func currentSession() -> PTYSession! { nil }
    func setWindowTitle() {}
    func currentTab() -> PTYTab! { nil }
    @objc(closeTab:) func close(_ tab: PTYTab!) {}
    func windowSetFrameTopLeftPoint(_ point: NSPoint) {}
    func windowPerformMiniaturize(_ sender: Any!) {}
    func windowDeminiaturize(_ sender: Any!) {}
    func windowOrderFront(_ sender: Any!) {}
    func windowOrderBack(_ sender: Any!) {}
    func windowIsMiniaturized() -> Bool { false }
    func windowFrame() -> NSRect { frameRect }
    func windowScreen() -> NSScreen! { NSScreen.main }
    func scrollbarShouldBeVisible() -> Bool { false }
    func scrollerStyle() -> NSScroller.Style { .overlay }
}

// MARK: - Rendering Comparer

@objc(iTermRenderingComparer)
class iTermRenderingComparer: NSObject {

    /// Parse the CLI argument, expanding \e, \x1b, \n, \r, \t escape sequences.
    @objc static func parseEscapes(_ input: String) -> Data {
        var result = Data()
        var chars = input.makeIterator()
        while let c = chars.next() {
            if c == "\\" {
                guard let next = chars.next() else {
                    result.append(UInt8(ascii: "\\"))
                    break
                }
                switch next {
                case "e":
                    result.append(0x1b)
                case "n":
                    result.append(0x0a)
                case "r":
                    result.append(0x0d)
                case "t":
                    result.append(0x09)
                case "\\":
                    result.append(UInt8(ascii: "\\"))
                case "x":
                    let h1 = chars.next(), h2 = chars.next()
                    if let h1, let h2, let byte = UInt8(String([h1, h2]), radix: 16) {
                        result.append(byte)
                    }
                default:
                    result.append(UInt8(ascii: "\\"))
                    for byte in String(next).utf8 { result.append(byte) }
                }
            } else {
                for byte in String(c).utf8 { result.append(byte) }
            }
        }
        return result
    }

    /// Called from applicationDidFinishLaunching when -compare-rendering is detected.
    @objc static func compareAndExit(_ inputString: String, rows: Int, columns: Int) {
        let data: Data
        if inputString.hasPrefix("file:"),
           let url = URL(string: inputString),
           let fileData = try? Data(contentsOf: url) {
            // Convert bare LF to CRLF since the data isn't going through a TTY.
            var converted = Data()
            var prev: UInt8 = 0
            for byte in fileData {
                if byte == 0x0a && prev != 0x0d {
                    converted.append(0x0d)
                }
                converted.append(byte)
                prev = byte
            }
            data = converted
        } else {
            data = parseEscapes(inputString)
        }

        guard let profile = ProfileModel.sharedInstance()?.defaultProfile() else {
            fputs("ERROR: No default profile found\n", stderr)
            NSApp.terminate(nil)
            return
        }
        guard let guid = profile[KEY_GUID] as? String else {
            fputs("ERROR: Default profile has no GUID\n", stderr)
            NSApp.terminate(nil)
            return
        }

        let legacyPath = "/tmp/iterm2-compare-legacy.png"
        let gpuPath = "/tmp/iterm2-compare-gpu.png"
        let diffPath = "/tmp/iterm2-compare-diff.png"

        // Render legacy
        let legacyImage: NSImage
        do {
            legacyImage = try renderLegacy(rows: rows, columns: columns, guid: guid, profile: profile, data: data)
            legacyImage.saveAsPNG(to: legacyPath)
        } catch {
            fputs("ERROR: Legacy render failed: \(error)\n", stderr)
            NSApp.terminate(nil)
            return
        }

        // Render GPU
        let gpuImage: NSImage
        do {
            gpuImage = try renderGPU(rows: rows, columns: columns, guid: guid, profile: profile, data: data)
        } catch {
            fputs("ERROR: GPU render failed: \(error)\n", stderr)
            NSApp.terminate(nil)
            return
        }

        // Compare
        let result = iTermImageComparison.compare(legacyImage, with: gpuImage, diffImagePath: diffPath)

        // Save GPU image
        gpuImage.saveAsPNG(to: gpuPath)

        // Output results
        print("COMPARE_RENDERING: legacy: \(legacyPath) gpu: \(gpuPath) diff: \(diffPath)")
        print("PIXELS_TOTAL: \(result.totalPixels)")
        print("PIXELS_DIFFERENT: \(result.differentPixels)")
        print(String(format: "PERCENT_DIFFERENT: %.2f", result.percentDifferent))
        print(String(format: "MAX_DIFFERENCE: %.4f", result.maxDifference))
        print("To view:\nimgcat \(legacyPath) \(gpuPath) \(diffPath)")

        let pass = result.percentDifferent < 0.1
        print("RESULT: \(pass ? "PASS" : "FAIL")")

        // Use NSApp.terminate instead of exit() so macOS properly clears its
        // window restoration crash tracking. A raw exit() causes macOS to show
        // a "unexpectedly quit while reopening windows" alert on next launch.
        NSApp.terminate(nil)
    }

    // MARK: - Private

    private static func createSession(rows: Int, columns: Int, guid: String, profile: [AnyHashable: Any], data: Data) -> PTYSession {
        let fontTable = FontTable.fontTable(forProfile: profile)
        let hSpacing = iTermProfilePreferences.double(forKey: KEY_HORIZONTAL_SPACING, inProfile: profile)
        let vSpacing = iTermProfilePreferences.double(forKey: KEY_VERTICAL_SPACING, inProfile: profile)
        let charSize = PTYTextView.charSize(
            for: fontTable.fontForCharacterSizeCalculations,
            horizontalSpacing: CGFloat(hSpacing),
            verticalSpacing: CGFloat(vSpacing))
        let sideMargins = CGFloat(iTermPreferences.int(forKey: kPreferenceKeySideMargins))
        let topBottomMargins = CGFloat(iTermPreferences.int(forKey: kPreferenceKeyTopBottomMargins))
        let frameSize = NSSize(
            width: CGFloat(columns) * charSize.width + sideMargins * 2,
            height: CGFloat(rows) * charSize.height + topBottomMargins * 2)

        let session = PTYSession(synthetic: true)!
        session.profile = profile
        let parent = iTermHeadlessWindowController(frame: NSRect(origin: .zero, size: frameSize))
        session.setScreenSize(frameSize, parent: parent)
        session.setPreferencesFromAddressBookEntry(profile)
        session.loadInitialColorTableAndResetCursorGuide()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        if !data.isEmpty {
            session.inject(data)
            session.screen.performBlock(joinedThreads: { _, _, _ in })
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        return session
    }

    private static func renderLegacy(rows: Int, columns: Int, guid: String, profile: [AnyHashable: Any], data: Data) throws -> NSImage {
        let session = createSession(rows: rows, columns: columns, guid: guid, profile: profile, data: data)
        let scrollback = Int(session.screen.numberOfScrollbackLines())
        session.textview.setDrawingHelperIsRetina((NSScreen.main?.backingScaleFactor ?? 2.0) > 1)
        let bgColor = session.processedBackgroundColor ?? .black
        guard let image = session.textview.renderImage(withLines: NSRange(location: scrollback, length: rows),
                                                       includeMargins: true,
                                                       backgroundColor: bgColor,
                                                       showCursor: true) else {
            throw NSError(domain: "iTermRenderingComparer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Legacy render returned nil"])
        }
        return image
    }

    private static func renderGPU(rows: Int, columns: Int, guid: String, profile: [AnyHashable: Any], data: Data) throws -> NSImage {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw NSError(domain: "iTermRenderingComparer", code: 2, userInfo: [NSLocalizedDescriptionKey: "No Metal device"])
        }
        let session = createSession(rows: rows, columns: columns, guid: guid, profile: profile, data: data)

        guard let screen = NSScreen.main else {
            throw NSError(domain: "iTermRenderingComparer", code: 3, userInfo: [NSLocalizedDescriptionKey: "No screen"])
        }
        let window = NSWindow(
            contentRect: NSRect(origin: screen.frame.origin, size: session.view.frame.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen)
        window.contentView = session.view
        window.orderFront(nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        session.useMetal = true
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 2.0))
        session.updateMetalDriver()

        guard let image = session.view.drawMetalFrameToImage() else {
            window.orderOut(nil)
            throw NSError(domain: "iTermRenderingComparer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Metal capture returned nil"])
        }
        window.orderOut(nil)
        return image
    }
}
