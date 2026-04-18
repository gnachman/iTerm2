//
//  MomentermProjectWindowController.swift
//  iTerm2
//
//  Created by MomenTerm on 2026-04-19.
//
//  The main "Project Manager" panel window for MomenTerm.
//  It shows a project tree on the left and a file browser on the right.
//  Open via menu: Window > Project Manager  (or keyboard shortcut)
//

import AppKit

// MARK: - Window Controller

@objc(MomentermProjectWindowController)
final class MomentermProjectWindowController: NSWindowController {

    @objc static let shared = MomentermProjectWindowController()

    private let splitVC = MomentermProjectSplitVC()

    // MARK: - Init

    private init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: true
        )
        window.title = "MomenTerm — Project Manager"
        window.minSize = NSSize(width: 420, height: 300)
        window.isMovableByWindowBackground = false
        super.init(window: window)

        window.contentViewController = splitVC

        // Position near top-left of main screen
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.minX + 20
            let y = screen.visibleFrame.maxY - window.frame.height - 40
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) not implemented")
    }

    // MARK: - Show/Toggle

    @objc static func toggle() {
        if shared.window?.isVisible == true {
            shared.window?.orderOut(nil)
        } else {
            shared.showWindow(nil)
            shared.window?.makeKeyAndOrderFront(nil)
        }
    }

    @objc static func show() {
        shared.showWindow(nil)
        shared.window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Split View Controller

private final class MomentermProjectSplitVC: NSSplitViewController, MomentermProjectSidebarDelegate, MomentermFileTreeDelegate {

    private let sidebarVC = MomentermProjectSidebarVC()
    private let fileTreeVC = MomentermProjectFileTreeVC()
    private let detailVC = MomentermProjectDetailVC()

    // MARK: - Setup

    override func viewDidLoad() {
        super.viewDidLoad()

        splitView.dividerStyle = .thin
        splitView.isVertical = true
        splitView.autosaveName = "com.momenterm.projectSplitView"

        sidebarVC.delegate = self
        fileTreeVC.delegate = self

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.canCollapse = true
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 280
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.defaultLow.rawValue + 1)

        let fileTreeItem = NSSplitViewItem(viewController: fileTreeVC)
        fileTreeItem.canCollapse = true
        fileTreeItem.minimumThickness = 160
        fileTreeItem.maximumThickness = 260

        let detailItem = NSSplitViewItem(viewController: detailVC)
        detailItem.minimumThickness = 240

        addSplitViewItem(sidebarItem)
        addSplitViewItem(fileTreeItem)
        addSplitViewItem(detailItem)
    }

    // MARK: - MomentermProjectSidebarDelegate

    func sidebarDidSelectProject(_ project: MomentermProject, inSpace space: MomentermProjectSpace) {
        fileTreeVC.setRootPath(project.path)
        detailVC.setProject(project)
    }

    func sidebarDidSelectSpace(_ space: MomentermProjectSpace) {
        detailVC.clearProject()
    }

    func sidebarDidRequestAddSpace() {
        presentAddSpaceSheet()
    }

    func sidebarDidRequestAddProject(toSpace space: MomentermProjectSpace) {
        presentAddProjectSheet(toSpace: space)
    }

    func sidebarDidRequestOpenProject(_ project: MomentermProject, mode: MomentermOpenMode) {
        openProject(project, mode: mode)
        MomentermProjectStorage.shared.markOpened(projectId: project.id)
        sidebarVC.reloadData()
    }

    func sidebarDidRequestDeleteProject(_ project: MomentermProject) {
        let alert = NSAlert()
        alert.messageText = "Remove \"\(project.name)\"?"
        alert.informativeText = "This only removes the project from the registry. No files will be deleted."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                MomentermProjectStorage.shared.removeProject(withId: project.id)
                self?.sidebarVC.reloadData()
                self?.detailVC.clearProject()
            }
        }
    }

    func sidebarDidRequestDeleteSpace(_ space: MomentermProjectSpace) {
        guard !space.projects.isEmpty else {
            MomentermProjectStorage.shared.invalidateCache()
            var store = MomentermProjectStorage.shared.load()
            store.removeSpace(withId: space.id)
            MomentermProjectStorage.shared.save(store)
            sidebarVC.reloadData()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Delete space \"\(space.name)\"?"
        alert.informativeText = "\(space.projects.count) project(s) will be removed from the registry."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .critical
        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                var store = MomentermProjectStorage.shared.load()
                store.removeSpace(withId: space.id)
                MomentermProjectStorage.shared.save(store)
                self?.sidebarVC.reloadData()
                self?.detailVC.clearProject()
            }
        }
    }

    // MARK: - MomentermFileTreeDelegate

    func fileTreeDidSelectFile(atPath path: String) {
        // Open file in current terminal session via it2 or direct vi launch
        openFileInTerminal(path)
    }

    func fileTreeDidSelectDirectory(atPath path: String) {
        detailVC.setPath(path)
    }

    // MARK: - Sheet helpers

    private func presentAddSpaceSheet() {
        let alert = NSAlert()
        alert.messageText = "New Project Space"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Space name…"
        alert.accessoryView = field
        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                let name = field.stringValue.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    _ = MomentermProjectStorage.shared.addSpace(named: name)
                    self?.sidebarVC.reloadData()
                }
            }
        }
    }

    private func presentAddProjectSheet(toSpace space: MomentermProjectSpace) {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Project"
        panel.message = "Choose the project directory"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let project = MomentermProject(name: url.lastPathComponent, path: url.path)
            MomentermProjectStorage.shared.addProject(project, toSpace: space.id)
            self?.sidebarVC.reloadData()
        }
    }

    // MARK: - Open project in terminal

    private func openProject(_ project: MomentermProject, mode: MomentermOpenMode) {
        let cmd = project.buildOpenCommand()

        // Check AI tools availability and prompt if needed
        MomentermAIToolChecker.checkAndPromptIfNeeded(for: project) { [weak self] shouldLaunch in
            self?.sendCommandToTerminal(cmd, mode: mode)
        }
    }

    private func sendCommandToTerminal(_ command: String, mode: MomentermOpenMode) {
        // Use it2 CLI if available, otherwise use AppleScript
        let it2Path = "/usr/local/bin/it2"
        let fm = FileManager.default

        if fm.fileExists(atPath: it2Path) || fm.fileExists(atPath: "/opt/homebrew/bin/it2") {
            let actualPath = fm.fileExists(atPath: it2Path) ? it2Path : "/opt/homebrew/bin/it2"
            let tabArg = mode == .newTab ? "tab" : "window"
            // Create new tab/window then send command
            runShellCommand(actualPath, args: [tabArg, "new"])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                runShellCommand(actualPath, args: ["session", "send", command + "\n"])
            }
        } else {
            // Fallback: AppleScript
            let tabCmd = mode == .newTab ? "tell application \"iTerm2\" to tell current window to create tab with default profile" : "tell application \"iTerm2\" to create window with default profile"
            let script = """
            tell application "iTerm2"
                \(tabCmd)
                tell current session of current tab of current window
                    write text "\(command.replacingOccurrences(of: "\"", with: "\\\""))"
                end tell
            end tell
            """
            runAppleScript(script)
        }
    }

    private func openFileInTerminal(_ filePath: String) {
        let escapedPath = filePath.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "iTerm2"
            tell current session of current tab of current window
                write text "vi \"\(escapedPath)\""
            end tell
        end tell
        """
        runAppleScript(script)
    }
}

// MARK: - Shell helpers

private func runShellCommand(_ path: String, args: [String]) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = args
    try? task.run()
}

private func runAppleScript(_ source: String) {
    var error: NSDictionary?
    NSAppleScript(source: source)?.executeAndReturnError(&error)
    if let err = error {
        NSLog("[MomenTerm] AppleScript error: %@", err)
    }
}

// MARK: - Detail VC (right pane placeholder)

private final class MomentermProjectDetailVC: NSViewController {

    private var nameLabel: NSTextField!
    private var pathLabel: NSTextField!
    private var aiLabel: NSTextField!
    private var openTabBtn: NSButton!
    private var openWindowBtn: NSButton!

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        setupUI()
    }

    private func setupUI() {
        nameLabel = NSTextField(labelWithString: "Select a project")
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = .labelColor

        pathLabel = NSTextField(labelWithString: "")
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = .systemFont(ofSize: 12)
        pathLabel.textColor = .secondaryLabelColor

        aiLabel = NSTextField(labelWithString: "")
        aiLabel.translatesAutoresizingMaskIntoConstraints = false
        aiLabel.font = .systemFont(ofSize: 12)
        aiLabel.textColor = .tertiaryLabelColor

        openTabBtn = NSButton(title: "Open in New Tab", target: self, action: #selector(openInNewTab))
        openTabBtn.translatesAutoresizingMaskIntoConstraints = false
        openTabBtn.bezelStyle = .rounded
        openTabBtn.isEnabled = false

        openWindowBtn = NSButton(title: "Open in New Window", target: self, action: #selector(openInNewWindow))
        openWindowBtn.translatesAutoresizingMaskIntoConstraints = false
        openWindowBtn.bezelStyle = .rounded
        openWindowBtn.isEnabled = false

        view.addSubview(nameLabel)
        view.addSubview(pathLabel)
        view.addSubview(aiLabel)
        view.addSubview(openTabBtn)
        view.addSubview(openWindowBtn)

        NSLayoutConstraint.activate([
            nameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nameLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 40),

            pathLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pathLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 8),

            aiLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            aiLabel.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 4),

            openTabBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            openTabBtn.topAnchor.constraint(equalTo: aiLabel.bottomAnchor, constant: 24),

            openWindowBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            openWindowBtn.topAnchor.constraint(equalTo: openTabBtn.bottomAnchor, constant: 8),
        ])
    }

    private var currentProject: MomentermProject?

    func setProject(_ project: MomentermProject) {
        currentProject = project
        nameLabel.stringValue = project.name
        pathLabel.stringValue = project.displayPath
        aiLabel.stringValue = "AI: \(project.aiTool.displayName) · tmux: \(project.tmuxMode.displayName)"
        openTabBtn.isEnabled = true
        openWindowBtn.isEnabled = true
    }

    func setPath(_ path: String) {
        // Show directory info
        nameLabel.stringValue = (path as NSString).lastPathComponent
        pathLabel.stringValue = (path as NSString).abbreviatingWithTildeInPath
    }

    func clearProject() {
        currentProject = nil
        nameLabel.stringValue = "Select a project"
        pathLabel.stringValue = ""
        aiLabel.stringValue = ""
        openTabBtn.isEnabled = false
        openWindowBtn.isEnabled = false
    }

    @objc private func openInNewTab() {
        guard let project = currentProject else { return }
        MomentermProjectWindowController.shared.contentViewController
            .flatMap { $0 as? MomentermProjectSplitVC }?
            .sidebarDidRequestOpenProject(project, mode: .newTab)
    }

    @objc private func openInNewWindow() {
        guard let project = currentProject else { return }
        MomentermProjectWindowController.shared.contentViewController
            .flatMap { $0 as? MomentermProjectSplitVC }?
            .sidebarDidRequestOpenProject(project, mode: .newWindow)
    }
}
