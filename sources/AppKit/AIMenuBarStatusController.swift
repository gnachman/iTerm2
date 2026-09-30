import AppKit
import Foundation

// Publishes session status counts as application-scope variables
// (iterm2.workingSessionCount, iterm2.waitingSessionCount).
@objc(iTermSessionStatusCountVariables)
class SessionStatusCountVariables: NSObject {
    @objc(sharedInstance) static let instance = SessionStatusCountVariables()

    private var observerToken: NotifyingDictionaryObserverToken?
    private var published: (working: Int, waiting: Int)?

    // Must be called on the main thread.
    @objc func start() {
        guard observerToken == nil else { return }
        observerToken = SessionStatusController.instance.addObserver { [weak self] _, _, _ in
            DispatchQueue.main.async {
                self?.publish()
            }
        }
        publish()
    }

    private func publish() {
        MainActor.assumeIsolated {
            var working = 0
            var waiting = 0
            for status in SessionStatusController.instance.statuses.values {
                // Text only: an indicator with no text is not a reported state.
                switch WorkgroupIntrospection.reportedState(forTabStatus: status) {
                case .working: working += 1
                case .waiting: waiting += 1
                default: break
                }
            }
            if let published, published == (working, waiting) {
                return
            }
            published = (working, waiting)
            let globals = iTermVariables.globalInstance()
            globals.setValue(NSNumber(value: working), forVariableNamed: iTermVariableKeyApplicationWorkingSessionCount)
            globals.setValue(NSNumber(value: waiting), forVariableNamed: iTermVariableKeyApplicationWaitingSessionCount)
        }
    }
}

// Owns the menu bar status item. Its content is the interpolated string in the
// menuBarItemString advanced setting, evaluated in the global scope.
@objc(iTermAIMenuBarStatusController)
class AIMenuBarStatusController: NSObject, NSMenuDelegate {
    @objc(sharedInstance) static let instance = AIMenuBarStatusController()

    private var statusItem: NSStatusItem?
    private var swiftyString: iTermSwiftyString?
    private var evaluatedValue = ""
    private var started = false
    private lazy var baseImage: NSImage? = {
        let image = NSImage(named: "StatusItem")
        image?.isTemplate = true
        return image
    }()

    // Must be called on the main thread.
    @objc func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refresh),
            name: NSNotification.Name(iTermAdvancedSettingsDidChange),
            object: nil)
        refreshOnMain()
    }

    @objc func refresh() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.started else { return }
            self.refreshOnMain()
        }
    }

    private func refreshOnMain() {
        let template = iTermAdvancedSettingsModel.menuBarItemString() ?? ""
        // The effective UI-element state, not the raw preference: with
        // UIElementRequiresHotkeys set, updateProcessType turns it off while
        // ordinary windows are open.
        let legacyMode = iTermApplication.shared().isUIElement &&
            iTermAdvancedSettingsModel.statusBarIcon()
        if template.isEmpty {
            stopEvaluating()
            if legacyMode {
                installStatusItemIfNeeded()
                render()
            } else {
                removeStatusItem()
            }
            return
        }
        installStatusItemIfNeeded()
        startEvaluating(template)
        render()
    }

    private func startEvaluating(_ template: String) {
        if swiftyString?.swiftyString == template {
            return
        }
        stopEvaluating()
        // Globals are reachable both bare and as iterm2.*, the name badges and titles use.
        let scope = iTermVariableScope()
        scope.add(iTermVariables.globalInstance(), toScopeNamed: nil)
        scope.add(iTermVariables.globalInstance(), toScopeNamed: iTermVariableKeyGlobalScopeName)
        swiftyString = iTermSwiftyString(string: template,
                                         scope: scope,
                                         sideEffectsAllowed: false,
                                         observer: { [weak self] newValue, error in
            if let error {
                RLog("Menu bar item string failed to evaluate: \(error)")
                return newValue
            }
            self?.evaluatedValue = (newValue as? String) ?? ""
            self?.render()
            return newValue
        })
        evaluatedValue = swiftyString?.evaluatedString ?? ""
    }

    private func stopEvaluating() {
        swiftyString?.invalidate()
        swiftyString = nil
        evaluatedValue = ""
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = ""
        item.button?.image = baseImage
        item.button?.imagePosition = .imageLeading
        (item.button?.cell as? NSButtonCell)?.highlightsBy = .changeBackgroundCellMask
        if let delegate = NSApp.delegate as? iTermApplicationDelegate {
            let menu = delegate.statusBarMenu()
            menu?.delegate = self
            item.menu = menu
        }
        statusItem = item
    }

    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    private func render() {
        guard let button = statusItem?.button else { return }
        let value = evaluatedValue
        if iTermAdvancedSettingsModel.menuBarItemDrawsBadge(),
           let label = Self.badgeLabel(for: value) {
            button.title = ""
            if let label {
                let image = Self.renderBadgeImage(label: label, baseImage: baseImage)
                image.isTemplate = false
                button.image = image
            } else {
                button.image = baseImage
            }
            return
        }
        button.image = baseImage
        button.title = value
    }

    // nil: cannot be drawn as a badge. .some(nil): plain icon. .some(label): badge.
    private static func badgeLabel(for value: String) -> String?? {
        if value.isEmpty || value == "0" {
            return .some(nil)
        }
        if let number = Int(value), number > 9 {
            return "+"
        }
        if value.count == 1 {
            return value
        }
        return nil
    }

    private static func renderBadgeImage(label: String, baseImage: NSImage?) -> NSImage {
        let color = NSColor.systemOrange
        let size = baseImage?.size ?? NSSize(width: 28, height: 16)
        return NSImage(size: size, flipped: false) { rect in
            guard let baseImage else { return false }

            color.setFill()
            rect.fill()
            baseImage.draw(
                in: rect,
                from: NSRect(origin: .zero, size: baseImage.size),
                operation: .destinationIn,
                fraction: 1.0)

            let glyphClearRect = NSRect(x: 7.5, y: 3.0, width: 6.75, height: 11.5)
            glyphClearRect.fill(using: .clear)

            let labelRect = NSRect(x: 7.0, y: 2.0, width: 7.75, height: 12.5)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .bold),
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
            let textSize = (label as NSString).size(withAttributes: attrs)
            let textRect = NSRect(
                x: labelRect.minX,
                y: labelRect.midY - textSize.height / 2.0,
                width: labelRect.width,
                height: textSize.height)
            (label as NSString).draw(in: textRect, withAttributes: attrs)
            return true
        }
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Re-copy the main menu on open so it never shows stale items.
        guard let item = menu.items.first(where: { $0.identifier == Self.mainMenuItemIdentifier }) else {
            return
        }
        item.submenu = NSApp.mainMenu?.deepCopy()
    }

    static let mainMenuItemIdentifier = NSUserInterfaceItemIdentifier("iTermStatusMenuMainMenu")
}
