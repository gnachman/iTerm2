import AppKit
import Foundation

@objc(iTermAIMenuBarStatusController)
class AIMenuBarStatusController: NSObject {
    @objc(sharedInstance) static let instance = AIMenuBarStatusController()

    private var statusItem: NSStatusItem?
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
            case .delivery:
                break
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
    }

    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    private func busyCount() -> Int {
        let tabIndicatorSessionIDs = SessionStatusController.instance.statuses.values
            .filter { $0.hasIndicator }
            .map { $0.sessionID }
        let busyChatIDs = TypingStatusModel.instance.chatIDs(forParticipant: .agent)
        var unique = Set<String>()
        for id in tabIndicatorSessionIDs { unique.insert("session:\(id)") }
        for id in busyChatIDs { unique.insert("chat:\(id)") }
        return unique.count
    }

    private func updateImage() {
        guard let button = statusItem?.button else { return }
        let count = busyCount()
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
