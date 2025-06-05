//
//  SSHFilePanelLocationButton.swift
//  iTerm2
//
//  Created by George Nachman on 6/3/25.
//
@available(macOS 11, *)
class SSHFilePanelLocationButton: NSPopUpButton {
    private var pathComponents: [String] = ["/"]
    private(set) var currentPath: String?
    private(set) var sshIdentity: SSHIdentity?

    init() {
        super.init(frame: .zero, pullsDown: false)
        // Configure the button cell for proper behavior
        if let cell = cell as? NSPopUpButtonCell {
            cell.bezelStyle = .rounded
            cell.alignment = .left
            cell.arrowPosition = .arrowAtBottom
            cell.preferredEdge = .minY
        }
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    func set(path: String, sshIdentity: SSHIdentity) {
        self.currentPath = path
        self.sshIdentity = sshIdentity

        // Build path components from current path
        pathComponents = buildPathComponents(from: path)

        // Add path components in reverse order (deepest first, root last)
        // This makes the menu open with current location at top, root at bottom
        for (index, component) in pathComponents.enumerated().reversed() {
            let displayName = component == "/" ? sshIdentity.hostname : component
            let fullPath = buildPathFromComponents(upToIndex: index)

            addItem(withTitle: displayName)
            lastItem?.representedObject = fullPath

            // Set the appropriate icon with proper sizing
            let iconSize = NSSize(width: 16, height: 16)

            if index == 0 {
                // For the root/computer, use NSComputer icon
                if let computerImage = NSImage(named: NSImage.computerName) {
                    computerImage.size = iconSize
                    lastItem?.image = computerImage
                }
            } else {
                // For folders, use the system's folder icon
                if let folderImage = NSImage(named: NSImage.folderName) {
                    folderImage.size = iconSize
                    lastItem?.image = folderImage
                }
            }
        }

        // Select the first item (which is now the current/deepest path)
        selectItem(at: 0)

        // Configure the popup button for proper alignment and behavior
        if let cell = cell as? NSPopUpButtonCell {
            cell.bezelStyle = .rounded
            cell.alignment = .left  // Left align text instead of center
            cell.arrowPosition = .arrowAtBottom  // Position arrow at bottom for proper menu alignment
            cell.preferredEdge = .minY  // Menu opens below the button
        }
    }

    private func buildPathComponents(from path: String) -> [String] {
        if path == "/" {
            return ["/"]
        }

        var components = ["/"]
        let pathParts = path.components(separatedBy: "/").filter { !$0.isEmpty }
        components.append(contentsOf: pathParts)
        return components
    }

    private func buildPathFromComponents(upToIndex index: Int) -> String {
        if index == 0 {
            return "/"
        }

        let relevantComponents = Array(pathComponents[1...index])
        return "/" + relevantComponents.joined(separator: "/")
    }
}
