import AppKit
import Foundation

@objc(iTermAIMenuBarStatusController)
class AIMenuBarStatusController: NSObject {
    @objc(sharedInstance) static let instance = AIMenuBarStatusController()

    private var statusItem: NSStatusItem?
    private var badgeView: BadgeView?
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
        let prefOn = iTermAdvancedSettingsModel.showMenuBarItem()
        let legacyMode = iTermPreferences.bool(forKey: kPreferenceKeyUIElement) &&
            iTermAdvancedSettingsModel.statusBarIcon()
        let shouldShow = prefOn || legacyMode
        if shouldShow {
            installStatusItemIfNeeded()
            updateBadge()
        } else {
            removeStatusItem()
        }
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = ""
        item.button?.image = baseImage
        item.button?.image?.isTemplate = true
        (item.button?.cell as? NSButtonCell)?.highlightsBy = .changeBackgroundCellMask
        if let delegate = NSApp.delegate as? iTermApplicationDelegate {
            item.menu = delegate.statusBarMenu()
        }
        if let button = item.button {
            let badge = BadgeView(frame: .zero)
            badge.autoresizingMask = []
            button.addSubview(badge)
            badgeView = badge
        }
        statusItem = item
    }

    private func removeStatusItem() {
        badgeView?.removeFromSuperview()
        badgeView = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    private func updateBadge() {
        guard let button = statusItem?.button, let badge = badgeView else { return }
        let count = busyChatIDs.count
        if count == 0 {
            badge.isHidden = true
            return
        }
        badge.isHidden = false
        badge.count = count
        let badgeSize = badge.intrinsicContentSize
        let buttonSize = button.bounds.size
        badge.frame = NSRect(
            x: buttonSize.width - badgeSize.width,
            y: buttonSize.height - badgeSize.height,
            width: badgeSize.width,
            height: badgeSize.height)
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
            DispatchQueue.main.async {
                self?.handleOnMain(update: update)
            }
        }
    }

    private func handleOnMain(update: ChatBroker.Update) {
        switch update {
        case .typingStatus(_, let participant):
            guard participant == .agent else { return }
            let snapshot = TypingStatusModel.instance.chatIDs(forParticipant: .agent)
            if snapshot != busyChatIDs {
                busyChatIDs = snapshot
                updateBadge()
            }
        case .delivery:
            break
        }
    }
}

private class BadgeView: NSView {
    var count: Int = 0 {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    private let horizontalPadding: CGFloat = 3.0
    private let verticalPadding: CGFloat = 1.0
    private let minDiameter: CGFloat = 12.0

    private var label: String {
        return count > 9 ? "9+" : "\(count)"
    }

    private var labelFont: NSFont {
        return NSFont.systemFont(ofSize: 9.0, weight: .bold)
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        return [
            .font: labelFont,
            .foregroundColor: NSColor.white
        ]
    }

    override var intrinsicContentSize: NSSize {
        let textSize = (label as NSString).size(withAttributes: textAttributes)
        let width = max(minDiameter, textSize.width + horizontalPadding * 2.0)
        let height = max(minDiameter, textSize.height + verticalPadding * 2.0)
        return NSSize(width: width, height: height)
    }

    override var isFlipped: Bool {
        return false
    }

    override func draw(_ dirtyRect: NSRect) {
        guard count > 0 else { return }
        let rect = bounds
        NSColor.systemOrange.setFill()
        let path: NSBezierPath
        if rect.width == rect.height {
            path = NSBezierPath(ovalIn: rect)
        } else {
            path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2.0, yRadius: rect.height / 2.0)
        }
        path.fill()

        let attrs = textAttributes
        let textSize = (label as NSString).size(withAttributes: attrs)
        let origin = NSPoint(
            x: rect.midX - textSize.width / 2.0,
            y: rect.midY - textSize.height / 2.0)
        (label as NSString).draw(at: origin, withAttributes: attrs)
    }
}
