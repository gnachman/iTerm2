//
//  MomentermGitGraphVC.swift
//  iTerm2
//
//  Hosts the MomentermGitGraphView in a scrollable container at the bottom
//  of the terminal window. Subscribes to MomentermGitGraphPoller updates
//  and re-runs layout when the active session's cwd changes.
//

import AppKit

@objc(MomentermGitGraphVC)
final class MomentermGitGraphVC: NSViewController {

    private let scrollView = NSScrollView()
    private let graphView = MomentermGitGraphView()
    private let header = NSView()
    private let cwdLabel = NSTextField(labelWithString: "")
    private let refreshButton = NSButton(title: "↻", target: nil, action: nil)

    private(set) var currentCwd: String?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 140))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        setupSubviews()
        layoutSubviews()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(graphUpdated(_:)),
            name: MomentermGitGraphPoller.didUpdateNotification,
            object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public

    @objc func setCwd(_ cwd: String) {
        if cwd == currentCwd { return }
        currentCwd = cwd
        cwdLabel.stringValue = (cwd as NSString).abbreviatingWithTildeInPath
        refresh()
    }

    @objc func refresh() {
        guard let cwd = currentCwd, !cwd.isEmpty else { return }
        MomentermGitGraphPoller.shared.refresh(cwd: cwd)
    }

    // MARK: - Setup

    private func setupSubviews() {
        header.translatesAutoresizingMaskIntoConstraints = false
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.addSubview(header)

        cwdLabel.translatesAutoresizingMaskIntoConstraints = false
        cwdLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        cwdLabel.textColor = .secondaryLabelColor
        cwdLabel.lineBreakMode = .byTruncatingMiddle
        header.addSubview(cwdLabel)

        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.isBordered = false
        refreshButton.bezelStyle = .regularSquare
        refreshButton.font = .systemFont(ofSize: 14, weight: .medium)
        refreshButton.target = self
        refreshButton.action = #selector(refresh)
        refreshButton.toolTip = "Refresh git graph"
        header.addSubview(refreshButton)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = graphView
        view.addSubview(scrollView)

        graphView.onContextMenu = { [weak self] commit, event in
            self?.showContextMenu(for: commit, event: event)
        }
    }

    private func layoutSubviews() {
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 22),

            cwdLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
            cwdLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            refreshButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -6),
            refreshButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            refreshButton.widthAnchor.constraint(equalToConstant: 22),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func graphUpdated(_ note: Notification) {
        guard let cwd = note.userInfo?["cwd"] as? String, cwd == currentCwd else { return }
        let commits = MomentermGitGraphPoller.shared.commits(forCwd: cwd)
        let layout = MomentermGitGraphLayouter.layout(commits: commits)
        graphView.layout = layout
    }

    private func showContextMenu(for commit: MomentermGitCommit, event: NSEvent) {
        let menu = NSMenu()
        let title = NSMenuItem(title: "\(commit.shortSha) — \(commit.summary)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let copy = NSMenuItem(title: "Copy SHA", action: #selector(copyShaAction(_:)), keyEquivalent: "")
        copy.target = self
        copy.representedObject = commit.sha
        menu.addItem(copy)

        let copyShort = NSMenuItem(title: "Copy short SHA", action: #selector(copyShaAction(_:)), keyEquivalent: "")
        copyShort.target = self
        copyShort.representedObject = commit.shortSha
        menu.addItem(copyShort)

        let summary = NSMenuItem(title: "Copy summary", action: #selector(copyShaAction(_:)), keyEquivalent: "")
        summary.target = self
        summary.representedObject = commit.summary
        menu.addItem(summary)

        NSMenu.popUpContextMenu(menu, with: event, for: graphView)
    }

    @objc private func copyShaAction(_ sender: NSMenuItem) {
        let text = (sender.representedObject as? String) ?? ""
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
