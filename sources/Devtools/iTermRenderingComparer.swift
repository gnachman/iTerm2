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
    func windowSetFrame(_ frame: NSRect) {}
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
            terminate(status: 1)
            return
        }
        guard let guid = profile[KEY_GUID] as? String else {
            fputs("ERROR: Default profile has no GUID\n", stderr)
            terminate(status: 1)
            return
        }

        let cwd = FileManager.default.currentDirectoryPath
        let legacyPath = (cwd as NSString).appendingPathComponent("iterm2-compare-legacy.png")
        let gpuPath = (cwd as NSString).appendingPathComponent("iterm2-compare-gpu.png")
        let diffPath = (cwd as NSString).appendingPathComponent("iterm2-compare-diff.png")

        // Render legacy
        let legacyImage: NSImage
        do {
            legacyImage = try renderLegacy(rows: rows, columns: columns, guid: guid, profile: profile, data: data)
        } catch {
            fputs("ERROR: Legacy render failed: \(error)\n", stderr)
            terminate(status: 1)
            return
        }

        // Render GPU
        let gpuImage: NSImage
        do {
            gpuImage = try renderGPU(rows: rows, columns: columns, guid: guid, profile: profile, data: data)
        } catch {
            fputs("ERROR: GPU render failed: \(error)\n", stderr)
            terminate(status: 1)
            return
        }

        let report = saveAndCompare(legacyImage: legacyImage,
                                    gpuImage: gpuImage,
                                    paths: Paths(legacy: legacyPath, gpu: gpuPath, diff: diffPath))
        for line in report.errors {
            fputs(line + "\n", stderr)
        }
        for line in report.output {
            print(line)
        }
        terminate(status: report.exitStatus)
    }

    struct Paths {
        var legacy: String
        var gpu: String
        var diff: String
    }

    struct Report {
        // Lines for stderr.
        var errors = [String]()
        // Lines for stdout.
        var output = [String]()
        var exitStatus: Int32 = 0
    }

    /// Saves both images and their diff, compares them, and describes the result. Not localized:
    /// this is command-line tool output.
    static func saveAndCompare(legacyImage: NSImage, gpuImage: NSImage, paths: Paths) -> Report {
        var report = Report()
        if !legacyImage.saveAsPNG(to: paths.legacy) {
            report.errors.append("ERROR: Could not save the legacy image to \(paths.legacy)")
        }
        if !gpuImage.saveAsPNG(to: paths.gpu) {
            report.errors.append("ERROR: Could not save the GPU image to \(paths.gpu)")
        }
        let result = iTermImageComparison.compare(legacyImage, with: gpuImage, diffImagePath: paths.diff)
        if result.diffImageWriteFailed.boolValue {
            report.errors.append("ERROR: Could not save the diff image to \(paths.diff)")
        }

        let saved = report.errors.isEmpty
        if saved {
            report.output.append("COMPARE_RENDERING: legacy: \(paths.legacy) gpu: \(paths.gpu) diff: \(paths.diff)")
        }
        report.output.append("PIXELS_TOTAL: \(result.totalPixels)")
        report.output.append("PIXELS_DIFFERENT: \(result.differentPixels)")
        report.output.append(String(format: "PERCENT_DIFFERENT: %.2f", result.percentDifferent))
        report.output.append(String(format: "MAX_DIFFERENCE: %.4f", result.maxDifference))
        if saved {
            report.output.append("To view:\nimgcat \(paths.legacy) \(paths.gpu) \(paths.diff)")
            let pass = result.percentDifferent < 0.1
            report.output.append("RESULT: \(pass ? "PASS" : "FAIL")")
        } else {
            report.output.append("RESULT: ERROR: could not save the images")
            report.exitStatus = 1
        }
        return report
    }

    private static var exitStatus: Int32 = 0

    // Use NSApp.terminate instead of exit() so macOS properly clears its
    // window restoration crash tracking. A raw exit() causes macOS to show
    // a "unexpectedly quit while reopening windows" alert on next launch.
    // NSApp.terminate always exits with status 0, so a nonzero status is
    // applied by an atexit handler, which runs only after AppKit has
    // finished terminating.
    private static func terminate(status: Int32) {
        if status != 0 {
            exitStatus = status
            atexit {
                fflush(stdout)
                fflush(stderr)
                _exit(iTermRenderingComparer.exitStatus)
            }
        }
        NSApp.terminate(nil)
        if status != 0 {
            // Termination was cancelled. Don't leave the handler to change
            // the status of a later, unrelated quit.
            fflush(stdout)
            fflush(stderr)
            _exit(status)
        }
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
        let sideMargins = CGFloat(iTermPreferences.sideMargins())
        let topBottomMargins = CGFloat(iTermPreferences.topBottomMargins())
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
        guard let textview = session.textview else {
            // Localization unneeded
            throw NSError(domain: "iTermRenderingComparer", code: 5, userInfo: [NSLocalizedDescriptionKey: "Session has no textview"])
        }
        let scrollback = Int(session.screen.numberOfScrollbackLines())
        textview.setDrawingHelperIsRetina((NSScreen.main?.backingScaleFactor ?? 2.0) > 1)
        // Renderer skips the fill when bgColor is nil, leaving margins
        // transparent — fall back to black so the comparer's pixel diffs
        // are stable.
        let bgColor = session.processedBackgroundColor ?? .black
        guard let image = textview.renderImage(withLines: NSRange(location: scrollback, length: rows),
                                               includeMargins: true,
                                               backgroundColor: bgColor,
                                               showCursor: true) else {
            // Localization unneeded
            throw NSError(domain: "iTermRenderingComparer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Legacy render returned nil"])
        }
        return image
    }

    private static func renderGPU(rows: Int, columns: Int, guid: String, profile: [AnyHashable: Any], data: Data) throws -> NSImage {
        guard MTLCreateSystemDefaultDevice() != nil else {
            // Localization unneeded
            throw NSError(domain: "iTermRenderingComparer", code: 2, userInfo: [NSLocalizedDescriptionKey: "No Metal device"])
        }
        let session = createSession(rows: rows, columns: columns, guid: guid, profile: profile, data: data)
        guard let sessionView = session.view else {
            // Localization unneeded
            throw NSError(domain: "iTermRenderingComparer", code: 6, userInfo: [NSLocalizedDescriptionKey: "Session has no view"])
        }

        guard let screen = NSScreen.main else {
            // Localization unneeded
            throw NSError(domain: "iTermRenderingComparer", code: 3, userInfo: [NSLocalizedDescriptionKey: "No screen"])
        }
        let window = NSWindow(
            contentRect: NSRect(origin: screen.frame.origin, size: sessionView.frame.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen)
        window.contentView = sessionView
        window.orderFront(nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        session.useMetal = true
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 2.0))
        session.updateMetalDriver()

        guard let image = sessionView.drawMetalFrameToImage() else {
            window.orderOut(nil)
            // Localization unneeded
            throw NSError(domain: "iTermRenderingComparer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Metal capture returned nil"])
        }
        window.orderOut(nil)
        return image
    }
}
