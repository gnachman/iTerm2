import AppKit

@objc(iTermShadowView)
class ShadowView: NSView {
    @objc
    var nsShadow: NSShadow = {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow.shadowOffset = CGSize(width: 4, height: -4)
        shadow.shadowBlurRadius = 12
        return shadow
    }()

    @objc
    var inset = 16.0

    @objc
    var cornerRadius = 8.0

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Save current graphics state.
        NSGraphicsContext.saveGraphicsState()

        // Set the shadow for subsequent drawing.
        nsShadow.set()

        // Define a rounded rectangle path.
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

        // Fill the path; the shadow will be applied.
        NSColor.white.setFill()
        path.fill()

        // Restore previous graphics state.
        NSGraphicsContext.restoreGraphicsState()
    }
}

@objc(iTermMenuItemTipController)
class MenuItemTipController: NSObject, NSMenuDelegate {
    @objc static var instance = MenuItemTipController()
    private var tipWindow: NSWindow?

    private var eventMonitor: Any?
    private var tipRegistry: [NSMenuItem: (NSImage?, NSAttributedString)] = [:]

    // MARK: - Public API

    @objc(registerTipForMenuItem:image:attributedString:)
    func registerTip(forMenuItem menuItem: NSMenuItem, image: NSImage?, attributedString: NSAttributedString) {
        it_assert(menuItem.parent?.submenu?.delegate === self || menuItem.parent?.submenu?.delegate == nil)
        menuItem.parent?.submenu?.delegate = self
        tipRegistry[menuItem] = (image, attributedString)
    }

    // MARK: - Show/Hide Tip

    private func showTip(for menuItem: NSMenuItem, image: NSImage?, text: NSAttributedString) {
        guard let screen = NSScreen.main else { return }

        let contentView = NSStackView()
        contentView.wantsLayer = true
        contentView.orientation = .vertical
        contentView.alignment = .centerX
        contentView.spacing = 8

        let width: CGFloat
        if let image {
            let imageView = NSImageView(image: image)
            contentView.addArrangedSubview(imageView)
            width = image.size.width
        } else {
            width = 250
        }

        let textField = NSTextField(labelWithAttributedString: text)
        textField.maximumNumberOfLines = 0
        textField.preferredMaxLayoutWidth = width
        textField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        contentView.addArrangedSubview(textField)

        let contentSize = contentView.fittingSize

        let inset = 24.0
        let largeFrame = NSRect(origin: .zero,
                                size: NSSize(width: contentSize.width + inset * 2, height: contentSize.height + inset * 2))

        let windowContentView = NSView(frame: largeFrame)

        let shadowView = ShadowView(frame: largeFrame)
        shadowView.inset = inset
        windowContentView.addSubview(shadowView)

        // Create NSVisualEffectView for background blur with rounded corners
        let visualEffectView = NSVisualEffectView(frame: NSRect(origin: NSPoint(x: inset, y: inset), size: contentSize))
        windowContentView.addSubview(visualEffectView)
        visualEffectView.material = .toolTip
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.autoresizingMask = [.width, .height]

        visualEffectView.layer?.shadowColor = NSColor.black.cgColor
        visualEffectView.layer?.shadowOffset = CGSize(width: 4, height: 4)
        visualEffectView.layer?.shadowRadius = 8
        visualEffectView.layer?.shadowOpacity = 0.5

        // Add rounded corners
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 8


        visualEffectView.layer?.borderWidth = 1
        if NSApp.effectiveAppearance.it_isDark {
            visualEffectView.layer?.borderColor = NSColor.init(white: 0.75, alpha: 0.5).cgColor
        } else {
            visualEffectView.layer?.borderColor = NSColor.init(white: 0.25, alpha: 0.5).cgColor
        }

        // Add contentView as a subview of the visualEffectView
        visualEffectView.addSubview(contentView)

        windowContentView.translatesAutoresizingMaskIntoConstraints = false
        shadowView.translatesAutoresizingMaskIntoConstraints = false

        // Ensure contentView is centered in visualEffectView with padding
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 8),
            contentView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 8),
            contentView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -8),
            contentView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -8),

            windowContentView.topAnchor.constraint(equalTo: shadowView.topAnchor),
            windowContentView.leadingAnchor.constraint(equalTo: shadowView.leadingAnchor),
            windowContentView.trailingAnchor.constraint(equalTo: shadowView.trailingAnchor),
            windowContentView.bottomAnchor.constraint(equalTo: shadowView.bottomAnchor),
        ])

        // Increase window size to account for padding and corner radius
        let paddedSize = NSSize(width: contentSize.width + 16, height: contentSize.height + 16)

        let tipWindow = NSWindow(contentRect: NSRect(origin: .zero, size: paddedSize),
                                 styleMask: [.borderless],
                                 backing: .buffered,
                                 defer: false)
        tipWindow.contentView = windowContentView
        tipWindow.isOpaque = false
        tipWindow.backgroundColor = NSColor.clear
        tipWindow.hasShadow = false
        tipWindow.setContentBorderThickness(0, for: .maxX)
        tipWindow.setContentBorderThickness(0, for: .maxY)
        tipWindow.setContentBorderThickness(0, for: .minX)
        tipWindow.setContentBorderThickness(0, for: .minY)
        guard var windowOrigin = calculateTipPosition(for: menuItem, tipSize: paddedSize, screen: screen)else {
            return
        }
        windowOrigin.x -= inset
        windowOrigin.y += inset
        tipWindow.setFrameOrigin(windowOrigin)

        DLog("Show tip window at \(windowOrigin) of size \(tipWindow.frame.size)")

        self.tipWindow = tipWindow
        tipWindow.makeKeyAndOrderFront(nil)

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.hideTip()
            return event
        }
    }

    private func hideTip() {
        tipWindow?.orderOut(nil)
        tipWindow = nil
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func calculateTipPosition(for menuItem: NSMenuItem, tipSize: NSSize, screen: NSScreen) -> NSPoint? {
        if let sub = menuItem.submenu?.items.first {
            return calculateTipPosition(for: sub, tipSize: tipSize, screen: screen)
        }
        guard let itemBounds = getMenuItemBounds(menuItem) else {
            return nil
        }
        if itemBounds.width == 0 || itemBounds.height == 0 {
            return nil
        }

        let x = min(itemBounds.maxX + 8, screen.visibleFrame.maxX - tipSize.width - 8)
        let y = max(itemBounds.maxY - tipSize.height, screen.visibleFrame.minY)

        return NSPoint(x: x, y: y)
    }

    private var timerGeneration = 0
    private func startHoverTimer(for menuItem: NSMenuItem) {
        timerGeneration += 1
        let generation = timerGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + iTermAdvancedSettingsModel.menuTipDelay()) { [weak self] in
            self?.timerDidFire(generation, menuItem: menuItem)
        }
    }

    @objc private func timerDidFire(_ generation: Int, menuItem: NSMenuItem) {
        DLog("Timer fired")
        if generation != timerGeneration {
            DLog("Ignoring, was superceded")
            return
        }
        guard let (image, text) = tipRegistry[menuItem] else {
            return
        }
        self.showTip(for: menuItem, image: image, text: text)
    }

    // MARK: - NSMenuDelegate Methods

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        let delay = tipWindow == nil
        hideTip()
        timerGeneration += 1
        DLog("Will highlight \(item?.title ?? "nil")")
        guard let menuItem = item, tipRegistry[menuItem] != nil else {
            hideTip()
            return
        }
        if delay {
            startHoverTimer(for: menuItem)
        } else if let item {
            timerDidFire(timerGeneration, menuItem: item)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        timerGeneration += 1
        hideTip()
    }

    // MARK: - Accessibility API to Get Menu Item Bounds

    private func getMenuItemBounds(_ menuItem: NSMenuItem) -> NSRect? {
        guard let axElement = getAXUIElement(for: menuItem) else { return nil }

        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        // Get AXPosition
        let posResult = AXUIElementCopyAttributeValue(axElement, kAXPositionAttribute as CFString, &positionValue)
        guard posResult == .success, let positionValue else { return nil }
        let posValue = positionValue as! AXValue

        // Get AXSize
        let sizeResult = AXUIElementCopyAttributeValue(axElement, kAXSizeAttribute as CFString, &sizeValue)
        guard sizeResult == .success, let sizeValue else { return nil }

        // Convert AXPosition to CGPoint
        var position = CGPoint.zero
        if !AXValueGetValue(posValue, .cgPoint, &position) {
            return nil
        }

        // Convert AXSize to CGSize
        var size = CGSize.zero
        if !AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) {
            return nil
        }

        // Get the primary screen height to adjust for inverted coordinates
        guard let screenHeight = NSScreen.screens.first?.frame.height else { return nil }

        // Flip Y-axis to convert from AX coordinates to standard screen coordinates
        position.y = screenHeight - position.y - size.height

        // Create a CGRect from position and size
        return NSRect(origin: position, size: size)
    }

    private func getAXUIElement(for menuItem: NSMenuItem) -> AXUIElement? {
        guard menuItem.parent?.submenu != nil else {
            return nil
        }

        // Get the process ID of the current process
        let pid = getpid()
        let axApp = AXUIElementCreateApplication(pid)

        // Build the path to the target menu item
        let itemPath = buildMenuItemPath(for: menuItem)
        guard !itemPath.isEmpty else { return nil }

        var mainMenu: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, "AXMenuBar" as CFString, &mainMenu) == .success,
              let mainMenu else {
            DLog("No menu")
            return nil
        }
        // Recursively search for the menu item
        return findAXElement(in: mainMenu as! AXUIElement, withPath: itemPath)
    }

    // Build a path of menu item titles up to the root
    private func buildMenuItemPath(for menuItem: NSMenuItem) -> [String] {
        var path: [String] = []
        var currentItem: NSMenuItem? = menuItem

        while let item = currentItem {
            let title = item.title
            if !title.isEmpty {
                path.insert(title, at: 0)
            }
            currentItem = item.parent
        }

        return path
    }

    // Recursively search the AX hierarchy using the path of menu titles
    private func findAXElement(in element: AXUIElement, withPath path: [String]) -> AXUIElement? {
        guard !path.isEmpty else { return nil }

        var childrenValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
        guard result == .success, let children = childrenValue as? [AXUIElement] else {
            DLog("Failed to get children of \(element)")
            return nil
        }

        let remainingPath = Array(path.dropFirst())
        DLog("Searching \(children.count) children of \(element) for \(path.first!)")
        for child in children {
            var titleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleValue) == .success else {
                DLog("Failed to get title of item \(child)")
                DLog("Recursing anyway")
                if let result = findAXElement(in: child, withPath: path) {
                    DLog("Who knew, it worked. Result is \(result)")
                    return result
                }
                DLog("No luck with wild hair in \(child), keep going from where I was")
                continue
            }
            guard let title = titleValue as? String else {
                DLog("Nil title for \(child).")
                continue
            }
            guard title == path.first else {
                DLog("Title of \(child) is \(title) but I wanted \(path.first.d)")
                continue
            }
            // If it's the target item, return it
            if remainingPath.isEmpty {
                DLog("Success")
                return child
            }
            DLog("Found \(path.first!)! Recursing for the rest of \(Array(path.dropFirst()).joined(separator: ", "))…")
            // Recur for the next level in the path
            return findAXElement(in: child, withPath: remainingPath)
        }

        return nil
    }
}
