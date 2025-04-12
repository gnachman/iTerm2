//
//  PathCompletionHelper.swift
//  iTerm2
//
//  Created by George Nachman on 4/12/25.
//

@objc(iTermPathCompletionHelperDelegate)
@available(macOS 11.0, *)
protocol PathCompletionHelperDelegate: AnyObject {
    func pathCompletionHelper(_ helper: PathCompletionHelper,
                              rangeForInterval: Interval) -> VT100GridCoordRange
    func pathCompletionHelperWidth(_ helper: PathCompletionHelper) -> Int32
    func pathCompletionHelper(_ helper: PathCompletionHelper,
                              screenRectForCoordRange: VT100GridCoordRange) -> NSRect
    func pathCompletionHelperWindow(_ helper: PathCompletionHelper) -> NSWindow?
    func pathCompletionHelperFont(_ helper: PathCompletionHelper) -> NSFont
    func pathCompletionHelper(_ helper: PathCompletionHelper,
                              didSelect suggestion: String)
}

// Opens a window listing subdirectories of the path in a PathMark. Works over ssh when using ssh integration.
@objc(iTermPathCompletionHelper)
@available(macOS 11.0, *)
class PathCompletionHelper: NSObject {
    private let hostname: String?
    private let username: String?
    private let conductor: Conductor?
    private let pathMark: PathMarkReading
    private var valid = true
    weak var delegate: PathCompletionHelperDelegate?
    private var completionsWindow: CompletionsWindow?
    @objc var selection: String?

    @objc
    init(remoteHost: VT100RemoteHostReading?,
         conductor: Conductor?,
         pathMark: PathMarkReading) {
        self.hostname = remoteHost?.hostname
        self.username = remoteHost?.username
        self.conductor = conductor
        self.pathMark = pathMark
    }

    @objc
    func begin() {
        if pathMark.isLocalhost {
            openWindowAsIndicator()
            iTermSlowOperationGateway.sharedInstance().fetchDirectoryListing(ofPath: pathMark.path) { [weak self] entries in
                self?.handle(entries)
            }
        } else if let conductor, conductor.framing, conductor.sshIdentity.matches(host: hostname, user: username) {
            openWindowAsIndicator()
            Task {
                do {
                    let files = try await conductor.listFiles(pathMark.path, sort: .byName).map {
                        $0.directoryEntry
                    }
                    DispatchQueue.main.async {
                        self.handle(files)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.handle([])
                    }
                }
            }
        }
    }

    @objc
    func invalidate() {
        valid = false
        if let completionsWindow {
            completionsWindow.parent?.removeChildWindow(completionsWindow)
            completionsWindow.orderOut(nil)
            self.completionsWindow = nil
        }
    }

    private func handle(_ entries: [iTermDirectoryEntry]) {
        guard valid else {
            return
        }
        showUIForDirectories(entries.filter { $0.isDirectory })
    }

    private func attributedString(_ entry: iTermDirectoryEntry, font: NSFont) -> NSAttributedString {
        return CompletionsWindow.attributedString(font: font,
                                                  prefix: pathMark.path,
                                                  suffix: (pathMark.path.hasSuffix("/") ? "" : "/") + entry.name)
    }

    private func detail(_ entry: iTermDirectoryEntry, font: NSFont) -> NSAttributedString {
        return CompletionsWindow.attributedString(font: font, prefix: "", suffix: pathMark.path)
    }

    private func showUIForDirectories(_ entries: [iTermDirectoryEntry]) {
        DLog("Entered showUIForDirectories")
        defer {
            DLog("Exited showUIForDirectories")
        }
        guard let completionsWindow, let delegate else {
            return
        }
        let parent = { () -> String? in
            let candidate = pathMark.path.deletingLastPathComponent
            if !candidate.isEmpty, candidate != pathMark.path {
                return candidate
            }
            return nil
        }()
        guard parent != nil || !entries.isEmpty else {
            invalidate()
            return
        }
        DLog("will sort")
        let sorted = entries.sorted {
            $0.name < $1.name
        }
        DLog("will get font")
        let font = delegate.pathCompletionHelperFont(self)
        DLog("Will make items")
        var items = sorted.map {
            CompletionsWindow.Item(suggestion: pathMark.path.appending(pathComponent: $0.name),
                                   attributedString: attributedString($0, font: font),
                                   detail: detail($0, font: font),
                                   kind: .folder)
        }
        DLog("Done making items")
        if let parent {
            items.insert(CompletionsWindow.Item(suggestion: parent,
                                                attributedString: CompletionsWindow.attributedString(font: font,
                                                                                                     prefix: "",
                                                                                                     suffix: parent),
                                                detail: CompletionsWindow.attributedString(font: font,
                                                                                           prefix: "",
                                                                                           suffix: "Parent directory"),
                                                kind: .folder),
                         at: 0)
        }
        DLog("will switch mode")
        if completionsWindow.canceled {
            invalidate()
            return
        }
        completionsWindow.switchMode(to: .completions(items: items))
        DLog("will make key and order front")
        completionsWindow.makeKeyAndOrderFront(nil)
        completionsWindow.returnPressed = { [weak self] item in
            if let self {
                if let item {
                    self.delegate?.pathCompletionHelper(self, didSelect: item.suggestion)
                } else {
                    invalidate()
                }
            }
        }
    }

    private func openWindowAsIndicator() {
        guard let interval = pathMark.entry?.interval,
              let delegate,
              let window = delegate.pathCompletionHelperWindow(self) else {
            return
        }
        let range = delegate.pathCompletionHelper(self, rangeForInterval: interval)
        if range.start.x < 0 {
            return
        }
        let width = delegate.pathCompletionHelperWidth(self)
        let hull = VT100GridCoordRangeConvexHull(range, width)
        let rect = delegate.pathCompletionHelper(self, screenRectForCoordRange: hull)
        if rect.width * rect.height == 0 {
            return
        }
        completionsWindow = CompletionsWindow(parent: window,
                                              location: rect,
                                              mode: .indicator,
                                              placeholder: "Getting directory listing…")
        completionsWindow?.selectionDidChange = { [weak self] _, suggestion in
            self?.selection = suggestion
        }
        completionsWindow?.makeKeyAndOrderFront(nil)
    }
}
