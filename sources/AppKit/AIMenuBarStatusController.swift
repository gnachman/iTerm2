import AppKit
import Foundation

@objc(iTermAIMenuBarStatusController)
class AIMenuBarStatusController: NSObject {
    @objc(sharedInstance) static let instance = AIMenuBarStatusController()

    private var statusItem: NSStatusItem?
    private var busyChatIDs = Set<String>()
    private var subscription: ChatBroker.Subscription?
    private let baseImage: NSImage?

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

        subscribeToBrokerIfPossible()
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
        let prefOn = iTermPreferences.bool(forKey: kPreferenceKeyShowMenuBarItem)
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

    private func updateImage() {
        guard let button = statusItem?.button, let base = baseImage else { return }
        let count = busyChatIDs.count
        if count == 0 {
            button.image = base
            button.image?.isTemplate = true
        } else {
            let composite = badgedImage(base: base, count: count)
            composite.isTemplate = false
            button.image = composite
        }
    }

    private func badgedImage(base: NSImage, count: Int) -> NSImage {
        let size = base.size
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        if let ctx = NSGraphicsContext.current {
            ctx.imageInterpolation = .high
        }

        base.draw(in: NSRect(origin: .zero, size: size),
                  from: .zero,
                  operation: .sourceOver,
                  fraction: 1.0)

        let label = count > 9 ? "9+" : "\(count)"
        let fontSize = max(8.0, floor(size.height * 0.55))
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let textSize = (label as NSString).size(withAttributes: textAttrs)
        let padding: CGFloat = 2.0
        let badgeDiameter = max(textSize.width + padding * 2, textSize.height + padding * 1.2)
        let badgeRect = NSRect(
            x: size.width - badgeDiameter,
            y: size.height - badgeDiameter,
            width: badgeDiameter,
            height: badgeDiameter)

        NSColor.systemOrange.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()

        let textOrigin = NSPoint(
            x: badgeRect.midX - textSize.width / 2.0,
            y: badgeRect.midY - textSize.height / 2.0)
        (label as NSString).draw(at: textOrigin, withAttributes: textAttrs)

        return image
    }

    private func subscribeToBrokerIfPossible() {
        guard subscription == nil else { return }
        guard let broker = ChatBroker.instance else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.subscribeToBrokerIfPossible()
            }
            return
        }
        subscription = broker.subscribe(chatID: nil, registrationProvider: nil) { [weak self] update in
            self?.handle(update: update)
        }
    }

    private func handle(update: ChatBroker.Update) {
        switch update {
        case .typingStatus(_, let participant):
            guard participant == .agent else { return }
            let snapshot = TypingStatusModel.instance.chatIDs(forParticipant: .agent)
            if snapshot != busyChatIDs {
                busyChatIDs = snapshot
                updateImage()
            }
        case .delivery:
            break
        }
    }
}
