import AppKit
import Foundation

@objc(iTermAIMenuBarStatusController)
class AIMenuBarStatusController: NSObject {
    @objc(sharedInstance) static let instance = AIMenuBarStatusController()

    private var statusItem: NSStatusItem?
    // Count currently drawn into the button, or nil when there is no item.
    private var renderedCount: Int?
    private let baseImage: NSImage?
    private var sessionStatusObserverToken: NotifyingDictionaryObserverToken?
    private var brokerSubscription: ChatBroker.Subscription?

    override init() {
        let image = NSImage(named: "StatusItem")
        image?.isTemplate = true
        self.baseImage = image
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refresh),
            name: NSNotification.Name("iTermProcessTypeDidChangeNotification"),
            object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil)

        sessionStatusObserverToken = SessionStatusController.instance.addObserver { [weak self] _, _, _ in
            self?.refresh()
        }

        subscribeToBrokerIfPossible()
    }

    private func subscribeToBrokerIfPossible() {
        // Called from init on the main thread, and the retry below re-enters on main.
        MainActor.assumeIsolated {
            guard brokerSubscription == nil else { return }
            guard let broker = ChatBroker.instance else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.subscribeToBrokerIfPossible()
                }
                return
            }
            brokerSubscription = broker.subscribe(chatID: nil, registrationProvider: nil) { [weak self] update in
                switch update {
                case .typingStatus(_, let participant):
                    guard participant == .agent else { return }
                    self?.refresh()
                case .delivery, .turnLifecycle:
                    break
                }
            }
        }
    }

    @objc func start() {
        refresh()
    }

    @objc private func defaultsChanged() {
        refresh()
    }

    @objc func refresh() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshOnMain()
        }
    }

    private func refreshOnMain() {
        let prefOn = iTermAdvancedSettingsModel.showMenuBarItem()
        let legacyMode = iTermPreferences.bool(forKey: kPreferenceKeyUIElement) &&
            iTermAdvancedSettingsModel.statusBarIcon()
        let shouldShow = prefOn || legacyMode
        if shouldShow {
            installStatusItemIfNeeded()
            updateImage()
        } else {
            removeStatusItem()
        }
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = ""
        (item.button?.cell as? NSButtonCell)?.highlightsBy = .changeBackgroundCellMask
        if let delegate = NSApp.delegate as? iTermApplicationDelegate {
            item.menu = delegate.statusBarMenu()
        }
        statusItem = item
        renderedCount = nil
    }

    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        renderedCount = nil
    }

    private func busyCount() -> Int {
        // hasIndicator is set independently of the status text, and agents such as
        // Claude Code keep the dot set while idle. Only the text says “working”.
        let workingSessionIDs = SessionStatusController.instance.statuses.values
            .filter { Self.isWorkingStatus($0.statusText) }
            .map { $0.sessionID }
        // TypingStatusModel is @MainActor; this only runs from refreshOnMain().
        let busyChatIDs = MainActor.assumeIsolated {
            TypingStatusModel.instance.chatIDs(forParticipant: .agent)
        }
        var unique = Set<String>()
        for id in workingSessionIDs { unique.insert("session:\(id)") }
        for id in busyChatIDs { unique.insert("chat:\(id)") }
        return unique.count
    }

    // Prefix, not equality: emitters append progress, e.g. “Working… 24s”.
    private static func isWorkingStatus(_ text: String?) -> Bool {
        guard let text = text?.trimmingCharacters(in: .whitespaces) else {
            return false
        }
        return text.lowercased().hasPrefix("working")
    }

    private func updateImage() {
        guard let button = statusItem?.button else { return }
        let count = busyCount()
        guard count != renderedCount else { return }
        renderedCount = count
        if count == 0 {
            button.image = baseImage
            button.image?.isTemplate = true
        } else {
            let image = Self.renderActiveImage(count: count, baseImage: baseImage)
            image.isTemplate = false
            button.image = image
        }
    }

    private static func renderActiveImage(count: Int, baseImage: NSImage?) -> NSImage {
        let label = count > 9 ? "+" : "\(count)"
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
}
