//
//  ChatViewController.swift
//  iTerm2
//
//  Created by George Nachman on 2/10/25.
//

import AppKit
import SwiftyMarkdown
import UniformTypeIdentifiers

protocol ChatViewControllerDelegate: AnyObject {
    func chatViewController(_ controller: ChatViewController, revealSessionWithGuid guid: String) -> Bool
    func chatViewControllerDeleteSession(_ controller: ChatViewController)
    func chatViewController(_ controller: ChatViewController,
                            forkAtMessageID: UUID,
                            ofChat chatID: String)
    func chatViewControllerDidUpdateToolbar(_ controller: ChatViewController)
}

// Document view for the chat scroll view. Hosts the tableView only —
// the iOS-style bottom contentInset on the clip view reserves the
// vertical room so the last row can scroll above the floating input
// view without anything wedged inside the document view.
//
// setFrameSize preserves clip-view origin verbatim. NSScrollView's
// generic `performWithoutScrolling` clamps origin.y to >= 0, which
// would bounce us back to the document's bottom (origin.y = 0 in this
// unflipped doc) every time the doc grew — visibly fighting our
// scrollToBottom which targets origin.y = -contentInsets.bottom.
class ChatViewControllerDocumentView: NSView {
    weak var tableView: NSTableView?

    override func setFrameSize(_ newSize: NSSize) {
        let oldOrigin = enclosingScrollView?.contentView.bounds.origin
        super.setFrameSize(newSize)
        guard let clipView = enclosingScrollView?.contentView,
              let oldOrigin,
              clipView.bounds.origin != oldOrigin else {
            return
        }
        clipView.setBoundsOrigin(oldOrigin)
        enclosingScrollView?.reflectScrolledClipView(clipView)
    }

    override func layout() {
        super.layout()
        guard let tableView else { return }
        tableView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
    }
}

// Inner container for the chat root view. The chat root only owns three
// subviews (a scroll view, the input view, and a hairline divider) but
// some hosts (the chat window controller toolbar layer) wrap it in
// additional decoration. Layout is handled in ChatViewController.viewDidLayout.
class ChatViewControllerInnerContainer: NSView {}

// Hairline divider between the input area and the rest of the chat
// surface. Lifted out of loadView so it can live at file scope —
// local types can't be nested inside closures in a generic context.
class ChatViewControllerDividerView: GradientView {}

// Root view for ChatViewController. Hooks both window-arrival (the
// inline-chat right-gutter panel uses this to defer load(chatID:) until
// after the panel has been added to the SessionView's window) and the
// synchronous layout pass (which runs the controller's manual layout
// before draw, in addition to whatever the joiner schedules).
class ChatViewControllerRootView: NSView {
    var didMoveToWindowHandler: (() -> Void)?
    var layoutHandler: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        didMoveToWindowHandler?()
    }

    override func layout() {
        super.layout()
        layoutHandler?()
    }
}

// Encoded into the buttonClicked identifier strings for two-button
// Approve/Deny client-local bubbles (workgroupPermissionRequest,
// enableOrchestrationRequest). Identifier format is
// "<prefix>:<choice>:<requestID>".
fileprivate enum ApprovalChoice: String {
    case approve
    case deny
}

// The chat view controller. Drives the table view, the input area,
// and the broker subscription. The same controller renders both
// chat modes (session-bound and orchestration); the mode is
// determined per-chat by Chat.orchestrationEnabled and is mutable
// at runtime. Hosted by ChatWindowController as the standalone
// chat window's content view, or as an inline right-gutter panel
// inside a SessionView.
@objc
class ChatViewController: NSViewController {
    weak var delegate: ChatViewControllerDelegate?
    private(set) var chatID: String? = UUID().uuidString

    private let inputView = ChatInputView()
    // Pending-but-unsent input per chat, so switching chats clears the field
    // but returning restores what was typed (tokens and attachments included).
    private struct InputDraft {
        let text: NSAttributedString
        let attachments: [HorizontalFileListView.File]
        var isEmpty: Bool { text.length == 0 && attachments.isEmpty }
    }
    private var inputDrafts = [String: InputDraft]()
    private var scrollView: NSScrollView!
    private var tableView: NSTableView!
    private var sendButton: NSButton!
    private var showTypingIndicator: Bool {
        get {
            model?.showTypingIndicator ?? false
        }
        set {
            model?.showTypingIndicator = newValue
            if showTypingIndicator {
                scrollToBottom(animated: true)
            }
            inputView.stoppable = showTypingIndicator
        }
    }
    private var eligibleForAutoPaste = true
    private var brokerSubscription: ChatBroker.Subscription?
    private var pickSessionPromise: iTermPromise<PTYSession>?
    private var model: ChatViewControllerModel?
    private let listModel: ChatListModel
    private let client: ChatClient
    // The provider popup item the user explicitly chose, so the selection stays
    // put even when the chat's model name is ambiguous (a manual config whose
    // name also matches a built-in model). Reset when the chat changes; falls
    // back to deriving from the model when nil or no longer consistent.
    var providerSelectionIdentifier: String?
    private var estimatedCount = 0
    private var _commandDidExitObserver: (any NSObjectProtocol)?
    private(set) var streaming = false {
        didSet {
            if let _commandDidExitObserver {
                NotificationCenter.default.removeObserver(_commandDidExitObserver)
                self._commandDidExitObserver = nil
            }
            if streaming, let model, model.terminalSessionGuid != nil {
                _commandDidExitObserver = NotificationCenter.default.addObserver(
                    forName: Notification.Name.PTYCommandDidExit,
                    object: nil,
                    queue: nil) { [weak self] notif in
                        if let self,
                           self.streaming,
                           let userInfo = notif.userInfo,
                           let binding = self.model?.terminalSessionGuid,
                           let liveGuid = notif.object as? String,
                           iTermSessionReferenceKeys(forGuid: liveGuid).contains(binding) {
                            self.streamLastCommand(userInfo)
                    }
                }
            }
        }
    }
    var terminalSessionGuid: String? { model?.terminalSessionGuid }
    var browserSessionGuid: String? { model?.browserSessionGuid }
    private let userDefaultsObserver = iTermUserDefaultsObserver()
    private(set) var chatToolbar: ChatToolbar!

    // MARK: - Right-gutter panel mode

    // Non-nil when this CVC is hosted as an inline chat in a SessionView's
    // right gutter. Holds the session whose inline-chat slot owns this panel
    // (weak so a session teardown can drop us). Also acts as the "is panel
    // mode" flag for behavior that should differ between window vs gutter
    // hosting.
    weak var panelAttachedSession: PTYSession?

    // Pending chatID to load once the panel's view is installed in a window.
    // load(chatID:) early-returns without a window, so attach() stashes the
    // ID here and the root view's viewDidMoveToWindow handler retries.
    var pendingPanelChatID: String?

    // Set non-nil only in panel mode; supplies the ChatViewControllerDelegate
    // implementation tailored for inline hosting (e.g., delete chat clears
    // the inline slot rather than asking a window controller).
    var inlinePanelCoordinator: InlinePanelCoordinator?

    // Panel-only toolbar (new chat / switch chat / session info / hide). The
    // chat window supplies its own NSToolbar or floating bar; the inline panel
    // hosts this instead. Non-nil only while attached as a gutter panel.
    private var inlineToolbarView: InlineChatToolbarView?

    // iTermRightGutterPanel.panelDelegate. Stored property so the protocol's
    // weak/var requirement is satisfied at the class level (extensions can't
    // declare stored properties).
    weak var panelDelegate: iTermRightGutterPanelDelegate?

    static let inlineChatPanelIdentifier = "com.iterm2.inlineChat"
    static let inlineChatPanelWidth: CGFloat = 400

    init(listModel: ChatListModel, client: ChatClient) {
        self.listModel = listModel
        self.client = client

        super.init(nibName: nil, bundle: nil)

        chatToolbar = ChatToolbar(dataSource: self)
        chatToolbar.dataSource = self
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionWillTerminate(_:)),
                                               name: NSNotification.Name.iTermSessionWillTerminate,
                                               object: nil)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    deinit {
        brokerSubscription?.unsubscribe()
    }

    // Trim leading whitespace at the rendering boundary only. The
    // persisted message body keeps the original bytes so the LLM sees
    // whatever it generated on the next request (Anthropic round-trips
    // any leading "\n\n" it emitted; clobbering it server-side would be
    // a separate decision). The chat bubble, however, shouldn't render
    // an empty paragraph at the top of every tool-using assistant
    // reply — Anthropic models routinely prefix tool-call responses
    // with "\n\n" and that becomes a stray blank line in the UI.
    fileprivate static func trimLeadingWhitespaceForDisplay(_ text: String) -> String {
        guard let firstNonWhitespace = text.firstIndex(where: { !$0.isWhitespace }) else {
            return text  // entirely whitespace; leave it alone
        }
        return String(text[firstNonWhitespace...])
    }

    @objc
    private func sessionWillTerminate(_ notif: Notification) {
        guard let session = notif.object as? PTYSession else {
            return
        }
        // The binding may be stored as either the session's stableID (new or
        // backfilled) or its legacy guid; match on either.
        let ids: Set<String> = [session.stableID, session.guid]
        if let ref = terminalSessionGuid, ids.contains(ref) {
            unlinkTerminalSession(nil)
        }
        if let ref = browserSessionGuid, ids.contains(ref) {
            unlinkBrowserSession(nil)
        }
    }

    // Holds the document view so layout() can reach the tableView.
    private var documentView: ChatViewControllerDocumentView!
    private var divider: NSView!
    // macOS 26 floating bar; positioned manually in performLayoutNow().
    private var floatingControlsView: NSView?

    private var lastTableViewWidth: CGFloat?

    // iOS-style deferred layout. AppKit's viewDidLayout (and any other
    // event that might mutate frames or content) marks layout dirty via
    // setNeedsLayoutNow(); the joiner coalesces multiple marks into a
    // single performLayoutNow() invocation on the next runloop tick. This
    // keeps our manual layout work strictly OUTSIDE AppKit's synchronous
    // layout pass — which is what trips the "more passes than views" guard
    // when the chat tree's auto-layout-internal subtrees (NSScrollView,
    // ChatInputTextFieldContainer) cycle.
    private let layoutJoiner = IdempotentOperationJoiner.asyncJoiner(.main)

    // MARK: - Layout

    func setNeedsLayoutNow() {
        layoutJoiner.setNeedsUpdate { [weak self] in
            self?.performLayoutNow()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        setNeedsLayoutNow()
    }

    func performLayoutNow() {
        guard isViewLoaded else { return }
        let bounds = view.bounds
        guard bounds.width > 0 else { return }
        let dividerHeight: CGFloat = 1

        // The inline-panel toolbar (if present) sits across the top edge; the
        // scroll view fills the remaining height below it. In window mode
        // there's no inline toolbar and the scroll view fills the full height.
        let toolbarHeight = inlineToolbarView != nil ? InlineChatToolbarView.height : 0
        if let inlineToolbarView {
            let toolbarFrame = NSRect(x: 0,
                                      y: bounds.height - toolbarHeight,
                                      width: bounds.width,
                                      height: toolbarHeight)
            if inlineToolbarView.frame != toolbarFrame {
                inlineToolbarView.frame = toolbarFrame
            }
        }

        let scrollFrame = NSRect(x: 0,
                                  y: 0,
                                  width: bounds.width,
                                  height: bounds.height - toolbarHeight)
        if scrollView.frame != scrollFrame {
            scrollView.frame = scrollFrame
        }

        let inputHeight = inputView.preferredHeight(forContainerWidth: bounds.width)
        let inputFrame = NSRect(x: 0, y: 0, width: bounds.width, height: inputHeight)
        if inputView.frame != inputFrame {
            inputView.frame = inputFrame
        }

        // Reserve room below the table content equal to the input
        // area's height so the last row can scroll above it. iOS
        // pattern: scroll view's contentInset.bottom == hovering view's
        // height, so the content can scroll up out from underneath.
        let currentInsets = scrollView.contentInsets
        if currentInsets.bottom != inputHeight ||
           currentInsets.top != 0 ||
           currentInsets.left != 0 ||
           currentInsets.right != 0 {
            scrollView.contentInsets = NSEdgeInsets(top: 0,
                                                    left: 0,
                                                    bottom: inputHeight,
                                                    right: 0)
        }

        // Divider sits at the top edge of the floating input area,
        // separating it from the scroll content above. y: inputHeight
        // puts it just above the input view (which lives at 0..inputHeight).
        // The previous y: bounds.maxY put the 1pt divider above the
        // chrome top, making it invisible.
        let dividerFrame = NSRect(x: 0,
                                  y: inputHeight,
                                  width: bounds.width,
                                  height: dividerHeight)
        if divider.frame != dividerFrame {
            divider.frame = dividerFrame
        }

        updateDocumentViewSize()

        let tableWidth = tableView.bounds.width
        if tableWidth != lastTableViewWidth {
            lastTableViewWidth = tableWidth
            // reloadData() inside an AppKit synchronous layout pass
            // re-dirties our own layout and can trigger the "more
            // layout passes than views" assertion on macOS 13+. Defer
            // via the joiner so it runs OUTSIDE the current pass.
            layoutJoiner.setNeedsUpdate { [weak self] in
                guard let self else { return }
                self.tableView.reloadData()
                self.updateDocumentViewSize()
            }
        }

        if let floating = floatingControlsView as? FloatingChatToolbarView {
            let preferred = floating.preferredSize()
            let availableWidth = max(0, bounds.width - 32)
            let width = min(availableWidth, preferred.width)
            let height = max(0, preferred.height)
            let x = floor((bounds.width - width) / 2)
            let topPadding: CGFloat = 8
            let y = bounds.height - topPadding - height
            let floatingFrame = NSRect(x: x, y: y, width: width, height: height)
            if floating.frame != floatingFrame {
                floating.frame = floatingFrame
            }
        }
    }

    func updateDocumentViewSize() {
        guard let documentView else { return }
        // The scroll view's clip view is sized asynchronously after
        // we set the scroll view's frame; reading clipView.bounds.width
        // here can still report 0 even though scrollView.bounds.width
        // is correct. Use scrollView.bounds.width directly, minus the
        // vertical scroller width if one is showing.
        var width = scrollView.bounds.width
        if let scroller = scrollView.verticalScroller,
           scrollView.scrollerStyle == .legacy,
           !scroller.isHidden {
            width -= scroller.frame.width
        }
        guard width > 0 else { return }
        // Document height = table content. We deliberately do NOT pad
        // to the clip view's height: the table view fills the document
        // (ChatViewControllerDocumentView.layout sets tableView.frame
        // = bounds), and an over-sized document would leave empty rows
        // beyond the actual content.
        let tableHeight = tableView.intrinsicContentSize.height
        let newSize = NSSize(width: width, height: tableHeight)
        if documentView.frame.size == newSize {
            return
        }
        documentView.setFrameSize(newSize)
        // setFrameSize marks documentView for layout but the actual
        // layout call happens asynchronously. Force it now so the
        // table view picks up the new bounds in the same pass.
        documentView.layout()
    }

    // MARK: - loadView

    override func loadView() {
        let view = ChatViewControllerRootView(
            frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        view.didMoveToWindowHandler = { [weak self] in
            self?.rootViewDidMoveToWindow()
        }
        view.layoutHandler = { [weak self] in
            // Run the manual layout synchronously inside AppKit's
            // layout pass so children have valid frames before draw —
            // the joiner path is for reacting to off-pass state
            // changes (text input, chat updates) and may run too
            // late for the first paint.
            self?.performLayoutNow()
        }

        tableView = NSTableView()
        let column = NSTableColumn(identifier:
                                     NSUserInterfaceItemIdentifier("MessageColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 40
        tableView.backgroundColor = .clear
        tableView.focusRingType = .none

        let documentView = ChatViewControllerDocumentView()
        documentView.addSubview(tableView)
        documentView.tableView = tableView
        self.documentView = documentView

        scrollView = NSScrollView()
        scrollView.contentView = NSClipView()
        scrollView.documentView = documentView
        scrollView.hasVerticalScroller = true
        scrollView.autoresizesSubviews = false
        // iOS-style: bottom contentInset on the clip view reserves
        // room below the content so the last row can scroll above
        // the floating input view. The exact value is updated in
        // performLayoutNow once the input view's preferred height
        // is known.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = .init()
        if #available(macOS 26, *) {
            scrollView.scrollerStyle = .overlay
        }

        let dividerView = ChatViewControllerDividerView(
            gradient: .init(
                stops: [
                    .init(
                        color: .it_dynamicColor(
                            forLightMode: .init(fromHexString: "#f2f2f2")!,
                            darkMode: .init(fromHexString: "#161616")!),
                        location: 0.25),
                    .init(
                        color: .it_dynamicColor(
                            forLightMode: .init(fromHexString: "#e3e3e3")!,
                            darkMode: .init(fromHexString: "#0b0b0b")!),
                        location: 0.75)]))
        self.divider = dividerView

        inputView.delegate = self

        // Disable autoresizing for the children we lay out manually
        // so AppKit doesn't move them on window resize. Empty mask
        // (not translatesAutoresizingMaskIntoConstraints=false, which
        // is the auto-layout opt-in switch).
        scrollView.autoresizingMask = []
        inputView.autoresizingMask = []
        dividerView.autoresizingMask = []
        documentView.autoresizingMask = []
        tableView.autoresizingMask = []

        view.addSubview(scrollView)
        view.addSubview(inputView)
        view.addSubview(dividerView)

        view.alphaValue = 0
        self.view = view

        chatToolbar.update()
    }

}

extension Message {
    var shouldCauseScrollToBottom: Bool {
        switch content {
        case .append, .commit:
            false
        case .explanationResponse(_, let update, markdown: _):
            update == nil
        default:
            true
        }
    }
}

extension ChatViewController {
    private static let chatSelectableProviders: [iTermAIVendor] = [
        .openAI,
        .anthropic,
        .gemini,
        .deepSeek,
        .llama
    ]

    private func model(named name: String?) -> AIMetadata.Model? {
        guard let name else {
            return nil
        }
        // A manual config wins over a built-in that shares the name, matching
        // how AIConversation resolves the pinned model at request time.
        if let manual = manualConfiguredModels.first(where: { $0.name == name }) {
            return manual
        }
        return AIMetadata.instance.models.first { $0.name == name }
    }

    private var storedChatModel: AIMetadata.Model? {
        guard let chatID else {
            return nil
        }
        return model(named: listModel.chat(id: chatID)?.modelName)
    }

    private var latestConfiguredMessageModel: AIMetadata.Model? {
        guard let chatID,
              let messages = listModel.messages(forChat: chatID, createIfNeeded: false) else {
            return nil
        }
        // Walk from the newest message backward, stopping at the first one that
        // carries a resolvable model. This avoids materializing the whole
        // DatabaseBackedArray (as `Array(messages)` would) on every toolbar and
        // row-event access, which is a hot path during a streamed response.
        var i = messages.count - 1
        while i >= 0 {
            if let result = model(named: messages[i].configuration?.model) {
                return result
            }
            i -= 1
        }
        return nil
    }

    // The model this chat was pinned to, whether or not it still resolves.
    private var pinnedChatModelName: String? {
        if let chatID, let name = listModel.chat(id: chatID)?.modelName {
            return name
        }
        guard let chatID,
              let messages = listModel.messages(forChat: chatID, createIfNeeded: false) else {
            return nil
        }
        var i = messages.count - 1
        while i >= 0 {
            if let name = messages[i].configuration?.model {
                return name
            }
            i -= 1
        }
        return nil
    }

    // If the chat was pinned to a model that has since been retired from
    // AIMetadata, keep it on the same provider (its recommended model) rather
    // than silently falling through to the global default, which could be a
    // different vendor the user has no key for and cannot change because the
    // provider picker is locked once a chat has messages.
    private var retiredModelFallback: AIMetadata.Model? {
        guard let name = pinnedChatModelName,
              model(named: name) == nil else {
            return nil
        }
        // vendor(forModelName:) returns nil for OpenAI names (gpt-*, o3, o4-mini,
        // codex, ...) because its nil is meaningful for manual-model
        // classification. Here nil just means "unrecognized", and OpenAI is the
        // right default (matching LLMMetadata.manualVendor), so a retired OpenAI
        // model stays on OpenAI instead of falling through to the global default
        // vendor - which the locked provider picker won't let the user change.
        let vendor = LLMMetadata.vendor(forModelName: name) ?? .openAI
        return recommendedModel(for: vendor)
    }

    private var effectiveChatModel: AIMetadata.Model? {
        return storedChatModel
            ?? latestConfiguredMessageModel
            ?? retiredModelFallback
            ?? AITermController.provider?.model
    }

    private var effectiveChatProvider: iTermAIVendor? {
        return effectiveChatModel?.vendor
    }

    private var manualConfiguredModels: [AIMetadata.Model] {
        return LLMMetadata.manualModels()
    }

    private var defaultManualConfiguredModel: AIMetadata.Model? {
        let models = manualConfiguredModels
        if let name = iTermPreferences.string(forKey: kPreferenceKeyAIModel),
           let model = models.first(where: { $0.name == name }) {
            return model
        }
        return models.first
    }

    private var currentProviderIdentifier: String? {
        // Honor the user's explicit pick as long as it still matches the chat's
        // model, so a selection (vendor or a specific manual model) never flips
        // on its own.
        if let providerSelectionIdentifier,
           providerSelectionIsConsistent(providerSelectionIdentifier) {
            return providerSelectionIdentifier
        }
        return derivedProviderIdentifier
    }

    // Classify the chat's model with no memory of what the user picked.
    private var derivedProviderIdentifier: String? {
        guard let effectiveChatModel else {
            return nil
        }
        let name = effectiveChatModel.name
        // A manual config wins over a built-in that shares the name (it wins at
        // request time), so a name present as a manual config is a manual
        // selection. Only a name that exists solely in the built-in catalog
        // belongs to that catalog model's vendor.
        if manualConfiguredModels.contains(where: { $0.name == name }) {
            return ChatProviderOption.manualModel(name: name).identifier
        }
        if let builtInVendor = AIMetadata.instance.models.first(where: { $0.name == name })?.vendor {
            return ChatProviderOption.vendorIdentifier(builtInVendor)
        }
        if let effectiveChatProvider {
            return ChatProviderOption.vendorIdentifier(effectiveChatProvider)
        }
        return nil
    }

    private func providerSelectionIsConsistent(_ identifier: String) -> Bool {
        guard let modelName = effectiveChatModel?.name else {
            return false
        }
        if let manualName = ChatProviderOption.manualName(from: identifier) {
            return manualName == modelName &&
                manualConfiguredModels.contains { $0.name == modelName }
        }
        if let vendor = ChatProviderOption.vendor(from: identifier) {
            return AIMetadata.instance.models.contains { $0.name == modelName && $0.vendor == vendor }
        }
        return false
    }

    private func providerIsAvailable(_ vendor: iTermAIVendor) -> Bool {
        guard !LLMMetadata.alternateModels(for: vendor).isEmpty else {
            return false
        }
        let key = AITermControllerObjC.apiKey(for: vendor)
        return key?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func recommendedModel(for provider: iTermAIVendor) -> AIMetadata.Model? {
        return LLMMetadata.recommendedModel(for: provider) ?? LLMMetadata.alternateModels(for: provider).first
    }

    private func setCurrentChatModelIfNeeded(_ modelName: String) {
        guard let chatID,
              listModel.chat(id: chatID)?.modelName != modelName else {
            return
        }
        do {
            try listModel.setModel(chatID: chatID, modelName: modelName)
        } catch {
            DLog("Failed to persist AI chat model \(modelName) for chat \(chatID): \(error)")
        }
    }

    private func ensureCurrentChatHasModel() {
        guard let chatID,
              listModel.chat(id: chatID)?.modelName == nil,
              let modelName = effectiveChatModel?.name else {
            return
        }
        do {
            try listModel.setModel(chatID: chatID, modelName: modelName)
        } catch {
            DLog("Failed to initialize AI chat model for chat \(chatID): \(error)")
        }
    }

    private var chatProviderIsLocked: Bool {
        if viewModelLocksProvider {
            return true
        }
        guard let chatID,
              let messages = listModel.messages(forChat: chatID, createIfNeeded: false) else {
            return false
        }
        return messages.contains { Self.messageLocksProvider($0) }
    }

    private var viewModelLocksProvider: Bool {
        guard let model else {
            return false
        }
        for i in 0..<model.items.count {
            let item = model.items[i]
            guard let message = item.existingMessage?.message else {
                continue
            }
            if Self.messageLocksProvider(message) {
                return true
            }
        }
        return false
    }

    private static func messageLocksProvider(_ message: Message) -> Bool {
        switch message.content {
        case .plainText, .markdown, .explanationRequest, .explanationResponse,
                .remoteCommandRequest, .remoteCommandResponse, .selectSessionRequest,
                .append, .appendAttachment, .terminalCommand, .multipart, .watcherEvent,
                .unsupported:
            return true
        case .clientLocal, .renameChat, .commit, .userCommand, .setPermissions, .vectorStoreCreated:
            return false
        }
    }

    var chatTitle: String {
        if let chatID,
           let chat = listModel.chat(id: chatID) {
            return chat.title
        }
        return "AI Chat"
    }

    func offerLink(to guid: String, terminal: Bool, name: String?) {
        if let chatID {
            try? client.publishClientLocalMessage(
                chatID: chatID,
                action: .offerLink(terminal: terminal, guid: guid, name: name))
        }
    }

    func offerOrchestration() {
        if let chatID {
            try? client.publishClientLocalMessage(
                chatID: chatID,
                action: .offerOrchestration)
        }
    }

    func load(chatID: String?) {
        if streaming {
            stopStreaming()
        }
        // The tracked provider pick belongs to the outgoing chat; let the new
        // chat derive its own from its stored model.
        providerSelectionIdentifier = nil
        guard let window = view.window else {
            return
        }
        let chat: Chat? = if let chatID {
            listModel.chat(id: chatID)
        } else {
            nil
        }
        if let chat {
            let m = ChatViewControllerModel(chatID: chat.id, listModel: listModel)
            m.delegate = self
            model = m
        } else {
            model = nil
        }
        // Stash the outgoing chat's pending input before we switch away, so it
        // comes back when the user returns. Drop the entry when nothing is
        // pending so the dictionary doesn't accumulate empty drafts. Only on an
        // actual chat change — a same-id reload must not disturb the field.
        let previousChatID = self.chatID
        let switchingChats = previousChatID != chat?.id
        if switchingChats, let previousChatID {
            let draft = InputDraft(text: inputView.attributedStringValue,
                                   attachments: inputView.attachedFiles)
            inputDrafts[previousChatID] = draft.isEmpty ? nil : draft
        }
        inputView.isEnabled = chatID != nil
        self.chatID = chat?.id
        // The @-mention session picker is only available in orchestration chats.
        // Read it lazily so a runtime toggle (e.g. via a tool call) takes effect
        // without re-wiring.
        inputView.orchestrationEnabledProvider = { [weak self] in
            guard let self, let chatID = self.chatID else {
                return false
            }
            return self.listModel.chat(id: chatID)?.orchestrationEnabled ?? false
        }
        inputView.refreshPlaceholder()

        // Switching chats clears the field; restore the incoming chat's saved
        // draft (if any) so a pending message survives the round trip. Skip on a
        // same-id reload so live (unsent) input isn't wiped.
        if switchingChats {
            inputView.clear()
            if let id = self.chatID, let draft = inputDrafts[id] {
                inputView.attributedStringValue = draft.text
                inputView.setAttachedFiles(draft.attachments)
            }
        }
        ensureCurrentChatHasModel()
        chatToolbar.update()

        // Update window title via window controller. Skip when this CVC is
        // hosted as an inline gutter panel — its window is the terminal
        // window, and clobbering its title with the chat title would be
        // wrong.
        if let windowController = view.window?.windowController as? ChatWindowController {
            windowController.updateTitle(chat?.title ?? "AI Chat")
        } else if isInlinePanel {
            updateInlineToolbarTitle()
        } else {
            // Fallback for compatibility
            view.window?.title = chat?.title ?? "AI Chat"
        }
        tableView.reloadData()
        brokerSubscription?.unsubscribe()
        if let chat {
            brokerSubscription = client.subscribe(chatID: chat.id, registrationProvider: window) { [weak self] update in
                // The broker publishes synchronously on whatever thread
                // the caller is on; appendMessage and the typing-indicator
                // setter run AppKit layout, so hop to main when needed.
                let apply = {
                    guard let self, let model = self.model else {
                        return
                    }
                    var shouldScroll = true
                    switch update {
                    case let .delivery(message, _, _):
                        // Hidden-from-client messages (setPermissions,
                        // remoteCommandResponse, renameChat, commit,
                        // vectorStoreCreated, userCommand) don't appear in
                        // the table, so they shouldn't trigger a scroll
                        // either — that was making button clicks in
                        // permissions bubbles bounce the chat.
                        shouldScroll = !message.hiddenFromClient && message.shouldCauseScrollToBottom
                        if !message.hiddenFromClient {
                            model.appendMessage(message)
                        } else if case .commit = message.content {
                            model.commit()
                        } else if case .remoteCommandResponse(_, let requestID, _, _) = message.content {
                            // The response itself is hidden, but it answers a
                            // visible remoteCommandRequest whose Allow/Deny
                            // buttons must now disable. This fires for a decision
                            // made on the companion phone too (the only path that
                            // doesn't optimistically disable the cell on click).
                            self.reloadCell(forMessageID: requestID)
                        }
                        if case .renameChat(let newName) = message.content {
                            // Update window title when chat is renamed. Skip
                            // for inline panels so the terminal window's title
                            // isn't clobbered.
                            if let windowController = self.view.window?.windowController as? ChatWindowController {
                                windowController.updateTitle(newName)
                            } else if self.isInlinePanel {
                                self.updateInlineToolbarTitle()
                            } else {
                                // Fallback for compatibility
                                self.view.window?.title = newName
                            }
                        }
                    case let .typingStatus(typing, participant):
                        switch participant {
                        case .user:
                            break
                        case .agent:
                            self.showTypingIndicator = typing
                            shouldScroll = typing
                        }
                    case .turnLifecycle:
                        // Turn-lifecycle boundaries drive the phone's reply
                        // notification, not the Mac UI (whose spinner is driven by
                        // typingStatus above). Suppress the default scroll so a turn
                        // boundary never yanks a scrolled-up reader to the bottom -
                        // and, at turn end, does not undo the no-scroll intent that
                        // typingStatus(false) just set.
                        shouldScroll = false
                    }
                    if shouldScroll {
                        DLog("Schedule scroll to bottom")
                        DispatchQueue.main.async { [weak self] in
                            DLog("Scroll to bottom")
                            self?.scrollToBottom(animated: true)
                        }
                    }
                }
                if Thread.isMainThread {
                    apply()
                } else {
                    DispatchQueue.main.async(execute: apply)
                }
            }
        }
        view.alphaValue = 1.0
        if let chatID {
            showTypingIndicator = TypingStatusModel.instance.isTyping(participant: .agent,
                                                                      chatID: chatID)
        } else {
            showTypingIndicator = false
        }
        if let chatID, let model, model.lastStreamingState == .active {
            try? client.publishClientLocalMessage(
                chatID: chatID,
                action: .streamingChanged(.stoppedAutomatically))
            model.lastStreamingState = .stoppedAutomatically
        }
        scrollToBottom(animated: false)
        inputView.makeTextViewFirstResponder()
    }

    // Pre-fill the input controls to send a message resembling
    // `message`. Pure input-view wrapper; works for both stacks.
    func stage(_ message: Message) {
        switch message.content {
        case .plainText(let text, context: _), .markdown(let text):
            inputView.stringValue = text
        case .multipart(let subs, vectorStoreID: _):
            for sub in subs {
                switch sub {
                case .plainText(let text), .markdown(let text):
                    inputView.stringValue = text
                case .attachment(let attachment):
                    switch attachment.type {
                    case .code, .statusUpdate, .fileID:
                        break
                    case .file(let file):
                        attach(filename: file.name,
                               content: file.content,
                               mimeType: file.mimeType)
                    }
                case .context:
                    break
                }
            }
        case .explanationRequest, .explanationResponse, .remoteCommandRequest,
                .remoteCommandResponse, .selectSessionRequest, .clientLocal,
                .renameChat, .append, .appendAttachment, .commit, .userCommand,
                .setPermissions, .vectorStoreCreated, .terminalCommand, .watcherEvent,
                .unsupported:
            break
        }
    }

    func attach(filename: String, content: Data, mimeType: String) {
        inputView.attach(filename: filename, content: content, mimeType: mimeType)
        inputView.makeTextViewFirstResponder()
    }

    func makeMessageInputFieldFirstResponder() {
        inputView.makeTextViewFirstResponder()
    }

    // Drop the given text into the input field iff the user hasn't
    // already started typing (eligibleForAutoPaste is reset by
    // textDidChange). Used by hosts that want to seed the chat with
    // pre-selected terminal text.
    func offerSelectedText(_ text: String) {
        if eligibleForAutoPaste {
            inputView.stringValue = text
        }
    }

    func reveal(messageID: UUID) {
        if let i = model?.index(ofMessageID: messageID) {
            scrollRowToCenter(i)
        }
    }

    private func scrollRowToCenter(_ row: Int) {
        let clipView = scrollView.contentView

        guard row >= 0, row < tableView.numberOfRows else {
            return
        }

        let rowRect = tableView.rect(ofRow: row)

        // Convert row rect to clipView's coordinate space
        let rowRectInClipView = tableView.convert(rowRect, to: clipView)

        // Calculate the new origin to center the row
        let newY = rowRectInClipView.midY - (clipView.bounds.height / 2)

        // Ensure we stay within the scrollable area
        let maxY = tableView.bounds.height - clipView.bounds.height
        let constrainedY = max(0, min(newY, maxY))

        // Animate the scroll
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            clipView.animator().setBoundsOrigin(NSPoint(x: 0, y: constrainedY))
        })
    }

    private static let webSearchUserDefaultsKey = "AI Web Search Enabled"
    private static let thinkUserDefaultsKey = "AI High Effort Enabled"
    static let reasoningEffortUserDefaultsKey = "NoSync AI Reasoning Effort"
    static let serviceTierUserDefaultsKey = "NoSync AI Service Tier"

    private var preferredReasoningEffort: ResponsesRequestBody.ReasoningOptions.Effort? {
        get {
            guard let value = iTermUserDefaults.userDefaults().string(
                forKey: Self.reasoningEffortUserDefaultsKey) else {
                return nil
            }
            return ResponsesRequestBody.ReasoningOptions.Effort(rawValue: value)
        }
        set {
            if let newValue {
                iTermUserDefaults.userDefaults().set(newValue.rawValue,
                                                     forKey: Self.reasoningEffortUserDefaultsKey)
            } else {
                iTermUserDefaults.userDefaults().removeObject(forKey: Self.reasoningEffortUserDefaultsKey)
            }
        }
    }

    private var preferredServiceTier: ResponsesRequestBody.ServiceTier? {
        get {
            guard let value = iTermUserDefaults.userDefaults().string(
                forKey: Self.serviceTierUserDefaultsKey) else {
                return nil
            }
            return ResponsesRequestBody.ServiceTier(rawValue: value)
        }
        set {
            if let newValue, newValue != .auto {
                iTermUserDefaults.userDefaults().set(newValue.rawValue,
                                                     forKey: Self.serviceTierUserDefaultsKey)
            } else {
                iTermUserDefaults.userDefaults().removeObject(forKey: Self.serviceTierUserDefaultsKey)
            }
        }
    }

    @objc private func toggleAlwaysAllow(_ sender: Any) {
        guard let menuItem = sender as? NSMenuItem,
              let category = menuItem.representedObject as? RemoteCommand.Content.PermissionCategory else {
            return
        }
        toggle(permissionCategory: category)
    }

    private func toggle(permissionCategory category: RemoteCommand.Content.PermissionCategory) {
        guard let chatID else {
            return
        }
        let maybeGuid = if category.isBrowserSpecific {
            model?.browserSessionGuid
        } else {
            model?.terminalSessionGuid
        }
        guard let guid = maybeGuid else {
            return
        }
        let existing = RemoteCommandExecutor.instance.permission(chatID: chatID,
                                                                 inSessionGuid: guid,
                                                                 category: category)
        var newPermission: RemoteCommandExecutor.Permission = switch existing {
        case .always: .never
        case .never: .ask
        case .ask: .always
        }
        if newPermission == .always,
           let autopopulationWarningText = category.autopopulationWarningText {
            let sel = iTermWarning.show(withTitle: autopopulationWarningText,
                                        actions: ["Send Automatically", "Ask Each Time", "Never Allow"],
                                        accessory: nil,
                                        identifier: nil,
                                        silenceable: .kiTermWarningTypePersistent,
                                        heading: "Confirm Change",
                                        window: view.window)
            switch sel {
            case .kiTermWarningSelection0:
                newPermission = .always
                // Explicitly choosing "Send Automatically" here IS the informed
                // consent, so record it globally: this user is never asked again by
                // the one-time auto-provide prompt, and auto-send takes effect (the
                // gate in ChatAgent.autoProvidedContext requires .granted).
                iTermUserDefaults.autoProvideConsent = .granted
            case .kiTermWarningSelection1:
                newPermission = .ask
            case .kiTermWarningSelection2:
                newPermission = .never
            default:
                it_fatalError()
            }
        }
        do {
            try listModel.setPermission(chat: chatID,
                                        permission: newPermission,
                                        guid: guid,
                                        category: category)
            try publishUpdatedPermissions()
        } catch {
            DLog("\(error)")
        }
    }

    private func publishUpdatedPermissions() throws {
        guard let chatID else {
            return
        }
        let rce = RemoteCommandExecutor.instance
        var allowedCategories = rce.allowedCategories(chatID: chatID,
                                                      terminalGuid: terminalSessionGuid,
                                                      browserGuid: browserSessionGuid)
        if shouldShareTerminalStateAutomatically {
            allowedCategories.remove(.checkTerminalState)
        }
        try client.publishUserMessage(
            chatID: chatID,
            content: .setPermissions(allowedCategories))
    }

    @objc private func objcLinkTerminalSession(_ sender: Any) {
        linkSession(terminal: true) { _ in }
    }

    @objc private func objcLinkBrowserSession(_ sender: Any) {
        linkSession(terminal: false) { _ in }
    }

    private func linkSession(terminal: Bool, _ completion: @escaping (PTYSession?) -> ()) {
        if let pickSessionPromise {
            SessionSelector.cancel(pickSessionPromise)
        }
        guard let chatID = self.chatID else {
            completion(nil)
            return
        }
        pickSessionPromise = SessionSelector.select(terminal: terminal, reason: "Link this session to AI chat?")
        let waitingMessage = Message(chatID: chatID,
                                     author: .agent,
                                     content: .clientLocal(ClientLocal(action: .pickingSession)),
                                     sentDate: Date(),
                                     uniqueID: UUID())
        if let pickSessionPromise {
            pickSessionPromise.then { [weak self] session in
                if let self, self.model != nil {
                    do {
                        try link(terminal: terminal, guid: session.guid, name: session.name)
                        completion(session)
                        self.pickSessionPromise = nil
                        reloadCell(forMessageID: waitingMessage.uniqueID)
                    } catch {
                        self.pickSessionPromise = nil
                        completion(nil)
                        self.reloadCell(forMessageID: waitingMessage.uniqueID)
                    }
                }
            }

            pickSessionPromise.catchError { [weak self] error in
                self?.pickSessionPromise = nil
                completion(nil)
                self?.reloadCell(forMessageID: waitingMessage.uniqueID)
            }
        }
        do {
            try client.publish(message: waitingMessage,
                                             toChatID: chatID,
                                             partial: false)
        } catch {
            DLog("\(error)")
            pickSessionPromise = nil
            completion(nil)
        }
    }

    private func link(terminal: Bool, guid: String, name: String?) throws {
        guard let model, let chatID else {
            return
        }
        // Store the reload-durable stableID (falling back to the guid if the
        // session is somehow unresolvable) so the binding, and the permission
        // grants keyed by it, survive a shell reload that rotates the guid.
        let reference = iTermController.sharedInstance()?.anySession(withGUID: guid)?.stableID ?? guid
        if terminal {
            try model.setTerminalSessionGuid(reference)
        } else {
            try model.setBrowserSessionGuid(reference)
        }
        try client.publishNotice(
            chatID: chatID,
            notice: "This chat has been linked to \(terminal ? "terminal" : "web browser") session “\(name?.escapedForMarkdownCode ?? "(Unnamed session)")”")
        try? client.publishClientLocalMessage(
            chatID: chatID,
            action: .permissions(terminal: terminal, guid: guid))
        try publishUpdatedPermissions()
    }

    private var haveLinkedTerminalSession: Bool {
        guard let model,
              let guid = model.terminalSessionGuid,
              iTermController.sharedInstance().anySession(forReference: guid) != nil else {
            return false
        }
        return true
    }

    private var haveLinkedBrowserSession: Bool {
        guard let model,
              let guid = model.browserSessionGuid,
              iTermController.sharedInstance().anySession(forReference: guid) != nil else {
            return false
        }
        return true
    }

    func stopStreaming() {
        if let chatID, streaming {
            try? client.publishMessageFromAgent(
                chatID: chatID,
                content: .clientLocal(.init(action: .streamingChanged(.stopped))))
        }
        streaming = false
        tableView.reloadData()
    }

    @objc private func toggleStream(_ sender: Any) {
        guard haveLinkedTerminalSession, let chatID else {
            return
        }
        if streaming {
            stopStreaming()
            return
        }
        let selection = iTermWarning.show(withTitle: "All terminal content will be sent to AI, which may go to a third party. Ensure this is safe to do before proceeding.",
                                          actions: ["OK", "Cancel"],
                                          accessory: nil,
                                          identifier: nil,
                                          silenceable: .kiTermWarningTypePersistent,
                                          heading: "Privacy Warning",
                                          window: nil)
        if selection == .kiTermWarningSelection0 {
            streaming = true
            tableView.reloadData()
            try? client.publishMessageFromAgent(
                chatID: chatID,
                content: .clientLocal(.init(action: .streamingChanged(.active))))
        }
    }

    @objc private func showLinkedSessionHelp(_ sender: Any) {
        chatToolbar.sessionButton.it_showWarning(withMarkdown: "When a terminal session is linked to this chat, the AI may view terminal contents and run commands in that session. You will be prompted to grant permission before it is able to view, type to, or modify a terminal session.")
    }

    @objc private func deleteChat(_ sender: Any) {
        delegate?.chatViewControllerDeleteSession(self)
    }

    @objc private func revealLinkedTerminalSession(_ sender: Any) {
        if let guid = model?.terminalSessionGuid {
            _ = delegate?.chatViewController(self, revealSessionWithGuid: guid)
        }
    }

    @objc private func revealLinkedBrowserSession(_ sender: Any) {
        if let guid = model?.browserSessionGuid {
            _ = delegate?.chatViewController(self, revealSessionWithGuid: guid)
        }
    }

    @objc private func putChatInLinkedTerminalSession(_ sender: Any) {
        installInLinkedSession(terminal: true)
    }

    @objc private func putChatInLinkedBrowserSession(_ sender: Any) {
        installInLinkedSession(terminal: false)
    }

    // Installs this chat as the inline (right-gutter) chat for the linked
    // session. The chat window's CVC remains; a fresh CVC is created in
    // the gutter via the registered factory once inlineChatID is set.
    private func installInLinkedSession(terminal: Bool) {
        guard let chatID else {
            return
        }
        let maybeGuid = terminal ? model?.terminalSessionGuid : model?.browserSessionGuid
        guard let guid = maybeGuid,
              let session = iTermController.sharedInstance().anySession(forReference: guid) else {
            return
        }
        session.inlineChatID = chatID
        session.inlineChatVisible = true
    }

    @objc private func unlinkTerminalSession(_ sender: Any?) {
        if let chatID {
            do {
                try listModel.setTerminalGuid(for: chatID, to: nil)
                try? client.publishNotice(
                    chatID: chatID,
                    notice: "This chat is no longer linked to a terminal session.")
                try publishUpdatedPermissions()
            } catch {
                DLog("\(error)")
            }
        }
    }

    @objc private func unlinkBrowserSession(_ sender: Any?) {
        if let chatID {
            do {
                try listModel.setBrowserGuid(for: chatID, to: nil)
                try? client.publishNotice(
                    chatID: chatID,
                    notice: "This chat is no longer linked to a web browser session.")
                try publishUpdatedPermissions()
            } catch {
                DLog("\(error)")
            }
        }
    }

    func scrollToBottom(animated: Bool) {
        guard let model else {
            return
        }
        let row = model.items.count - 1
        guard row >= 0 else { return }
        // Force the manual layout pass to run synchronously so the
        // input-view height has been measured, contentInsets.bottom
        // is current, and the document size reflects the latest row
        // heights. load(chatID:) calls us before the joiner has
        // fired; without this, insetBottom is 0 and setBoundsOrigin
        // (0, 0) clamps to the valid range — leaving the last
        // bubble(s) obscured by the input view.
        performLayoutNow()
        // documentView (ChatViewControllerDocumentView) is unflipped,
        // so doc.y=0 is the BOTTOM of the document (newest row).
        // Setting clipView.bounds.origin.y = -contentInsets.bottom
        // puts that bottom edge at insetBottom pixels above the
        // clip's lower edge — i.e., flush with the top of the input
        // view.
        let insetBottom = scrollView.contentInsets.bottom
        let target = NSPoint(x: 0, y: -insetBottom)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                scrollView.contentView.animator().setBoundsOrigin(target)
            }
        } else {
            scrollView.contentView.setBoundsOrigin(target)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    @available(macOS 26, *)
    func setupFloatingControls() {
        let floatingView = chatToolbar.createFloatingView()
        floatingView.autoresizingMask = []
        view.addSubview(floatingView)
        floatingControlsView = floatingView
        view.needsLayout = true
    }
}

extension ChatViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        guard let model else {
            estimatedCount = 0
            return 0
        }
        DLog("report \(model.items.count) items in table view")
        estimatedCount = model.items.count
        return model.items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let model else {
            return nil
        }
        let view = view(forItem: model.items[row], isLastMessage: model.indexIsLastMessage(row))
        DLog("Return view of class \(type(of: view)) for row \(row))")
        return view
    }

    private func view(forItem item: ChatViewControllerModel.Item, isLastMessage: Bool) -> NSView {
        switch item {
        case .agentTyping:
            return TypingIndicatorCellView()
        case .date(let date):
            let view = DateCellView()
            view.set(dateComponents: date)
            return view
        case .message(let message):
            switch message.message.content {
            case .terminalCommand:
                let cell = TerminalCommandMessageCellView()
                configure(cell: cell, for: message.message, isLast: isLastMessage)
                return cell
            case .clientLocal, .watcherEvent, .unsupported:
                // A message type this build can't decode renders as a
                // system-style placeholder bubble ("needs a newer
                // version"); see attributedStringValue.
                let cell = SystemMessageCellView()
                configure(cell: cell, for: message.message, isLast: isLastMessage)
                return cell
            case .multipart:
                let cell = MultipartMessageCellView()
                configure(cell: cell, for: message.message, isLast: isLastMessage)
                return cell

            case .userCommand:
                it_fatalError("User messages should not be in model")
            case .append, .appendAttachment:
                it_fatalError("Append-type messages should not be in model")

            case .plainText, .markdown, .explanationRequest, .explanationResponse,
                    .remoteCommandRequest, .remoteCommandResponse, .selectSessionRequest,
                    .renameChat, .commit, .setPermissions, .vectorStoreCreated:
                let cell = RegularMessageCellView()
                configure(cell: cell, for: message.message, isLast: isLastMessage)
                return cell
            }
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        false
    }
    private func reloadCell(forMessageID messageID: UUID) {
        if let model, let i = model.index(ofMessageID: messageID) {
            tableView.reloadData(forRowIndexes: IndexSet(integer: i),
                                 columnIndexes: IndexSet(integer: 0))
            tableView.invalidateIntrinsicContentSize()
        }
    }

    private func edit(_ messageID: UUID) {
        guard let model,
              let i = model.index(ofMessageID: messageID),
              case .message(let message) = model.items[i],
              case .plainText(let text, _) = message.message.content else {
            return
        }
        model.deleteFrom(index: i)
        inputView.stringValue = text
    }

    private func fork(_ messageID: UUID) {
        guard let model,
              let chatID,
              model.index(ofMessageID: messageID) != nil else {
            return
        }
        delegate?.chatViewController(self, forkAtMessageID: messageID, ofChat: chatID)
    }

    private func configure(cell: MultipartMessageCellView,
                                for message: Message,
                                isLast: Bool) {
        cell.configure(with: rendition(for: message, isLast: isLast),
                       maxBubbleWidth: max(16, tableView.bounds.width * 0.7))
    }

    private func configure(cell: TerminalCommandMessageCellView,
                                for message: Message,
                                isLast: Bool) {
        cell.configure(with: rendition(for: message, isLast: isLast),
                       tableViewWidth: tableView.bounds.width)
    }

    private func configure(cell: RegularMessageCellView,
                           for message: Message,
                           isLast: Bool) {
        cell.configure(with: rendition(for: message, isLast: isLast),
                       tableViewWidth: tableView.bounds.width)
        cell.editButtonClicked = { [weak self] messageID in
            self?.edit(messageID)
        }
        cell.forkButtonClicked = { [weak self] messageID in
            self?.fork(messageID)
        }
        let originalMessageID = message.uniqueID
        let chatID = self.chatID
        switch message.content {
        case .clientLocal(let clientLocal):
            switch clientLocal.action {
            case .pickingSession:
                cell.buttonClicked = { [weak self] identifier, messageID in
                    guard let self else {
                        return
                    }
                    guard messageID == originalMessageID else {
                        return
                    }
                    if let pickSessionPromise {
                        SessionSelector.cancel(pickSessionPromise)
                        self.pickSessionPromise = nil
                    }
                }
            case .executingCommand:
                cell.buttonClicked = { [weak self] identifier, messageID in
                    // buttonClicked closures get re-wired across reloads, so a
                    // tap on a stale "Executing..." bubble must not cancel
                    // whatever operation the agent has moved on to.
                    guard messageID == originalMessageID else { return }
                    if let guid = self?.model?.terminalSessionGuid,
                       let session = iTermController.sharedInstance().anySession(forReference: guid) {
                        session.cancelRemoteCommand()
                    }
                }
            case .notice:
                break
            case .streamingChanged(let state):
                if state == .active {
                    cell.buttonClicked = { [weak self] identifier, messageID in
                        guard let self else {
                            return
                        }
                        guard messageID == originalMessageID else {
                            return
                        }
                        stopStreaming()
                    }
                }
            case .offerLink(terminal: let terminal, guid: let guid, name: let name):
                cell.buttonClicked = { [weak self] identifier, messageID in
                    guard let self else {
                        return
                    }
                    guard messageID == originalMessageID else {
                        return
                    }
                    switch identifier {
                    case "link":
                        try? link(terminal: terminal, guid: guid, name: name)
                    case "orchestrate":
                        // Route through the menu action so the user
                        // gets the same confirmation alert + permission
                        // model warning as the menu-driven path.
                        enableOrchestration(nil)
                        // If the user cancelled the alert, no state
                        // change fires and the cell's enableButtons
                        // would never recompute, leaving both buttons
                        // greyed out from the optimistic-disable pass.
                        // Reloading the row recomputes enable state
                        // (both on cancel and on confirm), so this is
                        // safe in either branch.
                        reloadCell(forMessageID: messageID)
                    default:
                        break
                    }
                }
            case .offerOrchestration:
                cell.buttonClicked = { [weak self] identifier, messageID in
                    guard let self else {
                        return
                    }
                    guard messageID == originalMessageID else {
                        return
                    }
                    switch identifier {
                    case "orchestrate":
                        // Route through the menu action so the user gets
                        // the same confirmation alert + permission model
                        // warning as the menu-driven and offerLink paths.
                        enableOrchestration(nil)
                        // Recompute enable state whether the user
                        // confirmed or cancelled (see .offerLink note).
                        reloadCell(forMessageID: messageID)
                    default:
                        break
                    }
                }
            case .permissions:
                cell.buttonClicked = { [weak self] identifier, messageID in
                    guard let self else {
                        return
                    }
                    guard messageID == originalMessageID else {
                        return
                    }
                    guard let category = RemoteCommand.Content.PermissionCategory(rawValue: identifier) else {
                        return
                    }
                    toggle(permissionCategory: category)
                    // Button titles encode the current permission state
                    // ("Category: Allow"/"Ask"/"Never"), so reload the
                    // cell after a toggle to refresh them.
                    reloadCell(forMessageID: messageID)
                }
            case .workgroupPermissionRequest:
                let capturedChatID = self.chatID
                cell.buttonClicked = { [weak self] identifier, messageID in
                    // buttonClicked closures get re-wired across reloads, but
                    // a stale tap on a recycled cell could still arrive before
                    // the next reload runs. Match the sibling .permissions /
                    // .executingCommand / .offerLink handlers by gating on
                    // the original message ID so a stale click for a prior
                    // permission request doesn't publish a response keyed to
                    // an unrelated requestID.
                    guard messageID == originalMessageID else { return }
                    self?.handleWorkgroupPermissionButton(identifier: identifier,
                                                          chatID: capturedChatID)
                }
            case .enableOrchestrationRequest:
                let capturedChatID = self.chatID
                cell.buttonClicked = { [weak self] identifier, messageID in
                    guard messageID == originalMessageID else { return }
                    self?.handleEnableOrchestrationButton(identifier: identifier,
                                                          chatID: capturedChatID)
                }
            case .orchestrationPermissionGranted:
                let capturedChatID = self.chatID
                cell.buttonClicked = { [weak self] identifier, messageID in
                    guard messageID == originalMessageID else { return }
                    // The default buttonTapped path greys the button on
                    // click; the revoke notice OrchestratorClient publishes
                    // then reloads the cell, where enableButtons (derived
                    // from claimedScopes) keeps it greyed. No explicit
                    // reload here, which would briefly re-enable it before
                    // the async claim drop lands.
                    self?.handleRevokeOrchestrationPermissionButton(identifier: identifier,
                                                                    chatID: capturedChatID)
                }
            }
        case .vectorStoreCreated, .userCommand:
            DLog("Unexpected message content \(message.content)")
            cell.buttonClicked = nil

        case .selectSessionRequest(let originalMessage, let terminal):
            cell.buttonClicked = { [weak self] identifier, messageID in
                guard let self else {
                    return
                }
                guard messageID == originalMessageID else {
                    return
                }
                switch PickSessionButtonIdentifier(rawValue: identifier) {
                case .cancel:
                    if let pickSessionPromise {
                        SessionSelector.cancel(pickSessionPromise)
                        self.pickSessionPromise = nil
                    }
                    if let chatID {
                        try? self.client.respondSuccessfullyToRemoteCommandRequest(
                            inChat: chatID,
                            requestUUID: originalMessage.uniqueID,
                            message: "The user declined to allow this function call to execute.",
                            functionCallName: originalMessage.functionCallName ?? "Unknown function call name",
                            functionCallID: originalMessage.functionCallID,
                            userNotice: nil)
                    }
                    return
                case  .none:
                    return
                case .pickSession:
                    break
                }

                linkSession(terminal: terminal) { session in
                    if let chatID {
                        if session != nil {
                            try? self.client.publish(message: originalMessage,
                                                     toChatID: chatID,
                                                     partial: false)
                        } else {
                            try? self.client.respondSuccessfullyToRemoteCommandRequest(
                                inChat: chatID,
                                requestUUID: originalMessage.uniqueID,
                                message: "The user declined to allow this function call to execute.",
                                functionCallName: originalMessage.functionCallName ?? "Unknown function call name",
                                functionCallID: originalMessage.functionCallID,
                                userNotice: nil)
                        }
                    }
                }
            }
        case .remoteCommandRequest(let payload, safe: _):
            // Per-call gating only applies to .classic (session-bound)
            // payloads. .external payloads come from orchestration and
            // aren't gated per-call, so no button wiring is needed.
            guard case let .classic(remoteCommand) = payload else {
                cell.buttonClicked = nil
                return
            }
            let functionCallName = remoteCommand.llmMessage.function_call?.name ?? "Unknown function call name"
            let functionCallID = remoteCommand.llmMessage.functionCallID
            cell.buttonClicked = { [client, listModel] identifier, messageID in
                guard messageID == originalMessageID else {
                    return
                }
                guard let chatID else {
                    return
                }
                let browser = remoteCommand.content.permissionCategory.isBrowserSpecific
                let guid = if browser {
                    self.listModel.chat(id: chatID)?.browserSessionGuid
                } else {
                    self.listModel.chat(id: chatID)?.terminalSessionGuid
                }
                guard let guid,
                      let session = iTermController.sharedInstance().anySession(forReference: guid) else {
                    try? client.publishNotice(chatID: chatID, notice: "This chat is not linked to any \(browser ? "web browser" : "terminal") session.")
                    try? client.respondSuccessfullyToRemoteCommandRequest(
                        inChat: chatID,
                        requestUUID: messageID,
                        message: "The user did not link a \(browser ? "web browser" : "terminal") session to chat, so the function could not be run.",
                        functionCallName: functionCallName,
                        functionCallID: functionCallID,
                        userNotice: "AI attempted to perform an action, but no \(browser ? "web browser" : "terminal") session is linked to this chat so it failed.")
                    return
                }
                let allowed: Bool
                switch RemoteCommandButtonIdentifier(rawValue: identifier) {
                case .allowOnce:
                    allowed = true
                case .allowAlways:
                    do {
                        try listModel.setPermission(chat: chatID,
                                                    permission: .always,
                                                    guid: guid,
                                                    category: remoteCommand.content.permissionCategory)
                        allowed = true
                    } catch {
                        DLog("\(error)")
                        allowed = false
                    }
                case .denyOnce:
                    allowed = false
                case .denyAlways:
                    do {
                        try listModel.setPermission(chat: chatID,
                                                    permission: .never,
                                                    guid: guid,
                                                    category: remoteCommand.content.permissionCategory)
                    } catch {
                        DLog("\(error)")
                    }
                    allowed = false
                case .none:
                    return
                }
                if allowed {
                    try? self.client.performRemoteCommand(remoteCommand,
                                                          in: session,
                                                          chatID: chatID,
                                                          messageUniqueID: messageID)
                } else {
                    try? self.client.respondSuccessfullyToRemoteCommandRequest(
                        inChat: chatID,
                        requestUUID: messageID,
                        message: "The user declined to allow function calling. Try to find another way to assist.",
                        functionCallName: functionCallName,
                        functionCallID: functionCallID,
                        userNotice: nil)
                }
            }
        case .plainText, .markdown, .explanationRequest, .explanationResponse,
                .remoteCommandResponse, .renameChat, .append, .commit, .setPermissions,
                .appendAttachment, .multipart, .watcherEvent, .unsupported:
            cell.buttonClicked = nil

        case .terminalCommand:
            it_fatalError()
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let model else {
            DLog("no model, can't calculate height")
            return 0
        }
        let item = model.items[row]
        // Cells converted to manual layout report their own height;
        // the remainder still rely on auto-layout fittingSize via a
        // prototype.
        switch item {
        case .agentTyping:
            return TypingIndicatorCellView.cellHeight
        case .date(let components):
            return DateCellView.cellHeight(for: components)
        case .message(let message):
            let r = rendition(for: message.message,
                              isLast: model.indexIsLastMessage(row))
            switch r.flavor {
            case .regular:
                return RegularMessageCellView.cellHeight(
                    for: r, tableViewWidth: tableView.bounds.width)
            case .command:
                return TerminalCommandMessageCellView.cellHeight(
                    for: r, tableViewWidth: tableView.bounds.width)
            case .multipart:
                return MultipartMessageCellView.cellHeight(
                    for: r, tableViewWidth: tableView.bounds.width)
            }
        }
    }

    // Build the MessageRendition the cell views use to lay themselves
    // out. The clientLocal branch's button-enable logic is the only
    // stack-specific part; everything else (timestamp formatting,
    // multipart subpart construction, regular-flavor attributed-string
    // creation) is pure per-Message.
    /// Whether a .remoteCommandResponse has been recorded for the request with
    /// `requestID`. Scans the chat's full message list (which, unlike the
    /// display items, retains hiddenFromClient responses). Cheap in practice:
    /// only called for the rare remoteCommandRequest cells that are on screen.
    private func remoteCommandRequestWasAnswered(_ requestID: UUID) -> Bool {
        guard let chatID,
              let messages = listModel.messages(forChat: chatID, createIfNeeded: false) else {
            return false
        }
        for message in messages {
            if case .remoteCommandResponse(_, let answeredID, _, _) = message.content,
               answeredID == requestID {
                return true
            }
        }
        return false
    }

    func rendition(for message: Message, isLast: Bool) -> MessageRendition {
        var enableButtons = isLast
        var editable = false
        // @-mention rewriting (@<guid> -> linked session name) is an
        // orchestration-only feature. Gate it so ordinary chats don't mutate
        // user-typed text that merely contains an @<uuid>-looking substring
        // (e.g. turning it into "[defunct session]").
        let chatIsOrchestration = chatID.flatMap {
            listModel.chat(id: $0)?.orchestrationEnabled
        } ?? false
        switch message.content {
        case .plainText:
            editable = message.author == .user
        case .vectorStoreCreated:
            DLog("Unexpected vectorStoreCreated message in items")
            break
        case .clientLocal(let clientLocal):
            switch clientLocal.action {
            case .pickingSession:
                if pickSessionPromise == nil {
                    enableButtons = false
                }
            case .executingCommand(let remoteCommand):
                let browser = remoteCommand.content.permissionCategory.isBrowserSpecific
                let guid = if browser {
                    model?.browserSessionGuid
                } else {
                    model?.terminalSessionGuid
                }
                if let guid,
                   let controller = iTermController.sharedInstance(),
                   let session = controller.anySession(forReference: guid) {
                    if !session.isExecutingRemoteCommand {
                        enableButtons = false
                    }
                }
            case .notice:
                break
            case .streamingChanged:
                enableButtons = streaming
            case .offerLink(terminal: _, guid: let guid, name: _):
                // Both Link and Enable Orchestration become moot
                // once either choice has been committed — the chat is
                // either linked to a session (terminalSessionGuid /
                // browserSessionGuid set) or in orchestration mode.
                // Recheck on every render so a cell reload triggered
                // by the click handler (e.g. orchestration's notice
                // publish) reflects the new state instead of showing
                // freshly-recreated buttons as enabled.
                let chatIsOrchestration = chatID.flatMap {
                    listModel.chat(id: $0)?.orchestrationEnabled
                } ?? false
                enableButtons = (iTermController.sharedInstance()?.anySession(forReference: guid) != nil &&
                                 terminalSessionGuid == nil &&
                                 browserSessionGuid == nil &&
                                 !chatIsOrchestration)
            case .offerOrchestration:
                // The lone Enable Orchestration button becomes moot
                // once the chat is in orchestration mode. Recheck on
                // every render so the reload triggered by the click
                // handler reflects the new state.
                let chatIsOrchestration = chatID.flatMap {
                    listModel.chat(id: $0)?.orchestrationEnabled
                } ?? false
                enableButtons = !chatIsOrchestration
            case .permissions(terminal: _, guid: let guid):
                enableButtons = (iTermController.sharedInstance()?.anySession(forReference: guid) != nil)
            case .workgroupPermissionRequest:
                // Never appears in a session-bound chat. Cover for exhaustivity.
                break
            case .enableOrchestrationRequest:
                // Enable / Not Now stay tappable until the user answers.
                // No additional gating beyond isLast.
                break
            case .orchestrationPermissionGranted(let scope, _):
                // Revoke stays tappable for the life of the chat (not
                // just while last) as long as the claim is still in
                // effect. Once revoked, the scope drops out of
                // claimedScopes and the button greys out on the next
                // reload (revokeClaim publishes a notice, which reloads).
                enableButtons = chatID.flatMap {
                    listModel.claimedScopes(forChatID: $0).contains(scope)
                } ?? false
            }
        case .remoteCommandRequest:
            // Disable the Allow/Deny buttons once the request has been answered,
            // not just when it stops being the last message. A local click
            // optimistically disables the cell's buttons immediately, but a
            // decision made on the companion phone (or a fast command whose only
            // follow-up is a hidden .remoteCommandResponse) never touches this
            // cell and can leave the request as the last visible message - so
            // without this the buttons stay live after the phone already
            // answered. "Answered" == a .remoteCommandResponse exists for this
            // request's UUID.
            if enableButtons, remoteCommandRequestWasAnswered(message.uniqueID) {
                enableButtons = false
            }
        default:
            break
        }
        let timestamp = {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: message.sentDate)
        }()
        let flavor: MessageRendition.Flavor = switch message.content {
        case .terminalCommand(let cmd):
                .command(.init(command: cmd.command, url: cmd.url))
        case .multipart(let subparts, _):
                .multipart(subparts.compactMap { subpart in
                    switch subpart {
                    case .attachment(let attachment):
                        switch attachment.type {
                        case .code(let content):
                            MessageRendition.SubpartContainer(
                                kind: .codeAttachment,
                                attributedString: AttributedStringForCode(
                                    content,
                                    textColor: message.textColor))
                        case .statusUpdate(let statusUpdate):
                            MessageRendition.SubpartContainer(
                                kind: .statusUpdate,
                                attributedString: AttributedStringForStatusUpdate(
                                    statusUpdate,
                                    textColor: message.textColor))
                        case .file(let file):
                            MessageRendition.SubpartContainer(
                                kind: .fileAttachment(
                                    id: attachment.id, name: file.name, file: file),
                                icon: NSImage.iconImage(
                                    filename: file.name,
                                    size: .init(width: 16, height: 16)),
                                attributedString: AttributedStringForFilename(
                                    file.name,
                                    textColor: message.textColor))
                        case .fileID(id: let id, name: let name):
                            MessageRendition.SubpartContainer(
                                kind: .fileAttachment(
                                    id: id, name: name, file: nil),
                                icon: NSImage.iconImage(
                                    filename: name,
                                    size: .init(width: 16, height: 16)),
                                attributedString: AttributedStringForFilename(
                                    name,
                                    textColor: message.textColor))
                        }
                    case .plainText(let text):
                        MessageRendition.SubpartContainer(
                            kind: .regular,
                            attributedString: Message.Content.plainText(text, context: nil)
                                .attributedStringValue(
                                    linkColor: message.linkColor,
                                    textColor: message.textColor,
                                    renderMentions: chatIsOrchestration))
                    case .markdown(let text):
                        MessageRendition.SubpartContainer(
                            kind: .regular,
                            attributedString: Message.Content.markdown(text)
                                .attributedStringValue(
                                    linkColor: message.linkColor,
                                    textColor: message.textColor,
                                    renderMentions: chatIsOrchestration))
                    case .context:
                        nil
                    }
                })
        default:
                .regular(.init(attributedString: message.attributedStringValue(renderMentions: chatIsOrchestration),
                               buttons: message.buttons,
                               enableButtons: enableButtons,
                               keepsButtonsEnabledAfterClick: message.isPermissionsClientLocal))
        }
        return MessageRendition(isUser: message.author == .user,
                                messageUniqueID: message.uniqueID,
                                flavor: flavor,
                                timestamp: timestamp,
                                isEditable: editable,
                                linkColor: message.linkColor)
    }
}

extension LLM.Message.Attachment {
    func localPathCreatingIfNeeded() -> String {
        if let path = existingLocalPath() {
            return path
        }
        let path = proposedLocalPath()
        switch type {
        case .code(let text):
            do {
                try text.write(toFile: path, atomically: false, encoding: .utf8)
            } catch {
                RLog("Failed to write to \(path): \(error)")
            }
        case .statusUpdate:
            it_fatalError()
        case .file(let file):
            do {
                try file.content.write(to: URL(fileURLWithPath: path))
            } catch {
                RLog("Failed to write to \(path): \(error)")
            }
        case .fileID:
            // TODO: Download the file
            it_fatalError()
        }
        return path
    }

    private var basePathForAttachments: String {
        NSTemporaryDirectory() + "iTerm2ChatAttachments/"
    }

    private func possibleLocalPaths() -> [String] {
        switch type {
        case .code:
            [basePathForAttachments.appendingPathComponent(id).appendingPathComponent("code.txt")]
        case .file(let file):
            [file.localPath,
             basePathForAttachments.appendingPathComponent(id).appendingPathComponent(file.name.lastPathComponent)].compactMap { $0 }
        case .statusUpdate:
            it_fatalError()
        case .fileID:
            // TODO: Download the file
            []
        }
    }

    private func existingLocalPath() -> String? {
        let candidates = possibleLocalPaths()
        return candidates.first { candidate in
            FileManager.default.fileExists(atPath: candidate)
        }
    }

    private func proposedLocalPath() -> String {
        let path = possibleLocalPaths()[0]
        do {
            try FileManager.default.createDirectory(atPath: path.deletingLastPathComponent,
                                                    withIntermediateDirectories: true)
        } catch {
            RLog("Failed to create \(path): \(error)")
        }
        return path
    }
}

extension ChatViewController: ChatInputViewDelegate {
    func textDidChange() {
        eligibleForAutoPaste = inputView.stringValue.isEmpty
    }

    func mimeType(_ filename: String) -> String {
        let ext = filename.pathExtension
        if let mime = openAIExtensionToMime[ext] {
            return mime
        }
        let url = URL(fileURLWithPath: filename)
        if let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
           let mimeType = UTType(uti)?.preferredMIMEType {
            return mimeType
        }
        return "application/octet-stream"
    }

    func stopButtonClicked() {
        guard let chatID else { return }
        let message = Message(chatID: chatID,
                              author: .user,
                              content: .userCommand(.stop),
                              sentDate: Date(),
                              uniqueID: UUID())
        try? client.publish(message: message,
                            toChatID: chatID,
                            partial: false)
        showTypingIndicator = false
    }

    func sendButtonClicked(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let chatID else {
            return
        }
        let attachments = inputView.attachedFiles.flatMap { item -> [Message.Subpart] in
            switch item {
            case let .inMemory(filename: filename, content: data, mimeType: mimeType):
                return [
                    Message.Subpart.attachment(.init(
                        inline: false,
                        id: UUID().uuidString,
                        type: .file(.init(name: filename.lastPathComponent,
                                          content: data,
                                          mimeType: mimeType))))]

            case .regular(let filename):
                let resolved = FileManager.default.realPath(of: filename)
                var isDirectory = ObjCBool(false)
                if FileManager.default.fileExists(atPath: filename, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        guard let sequence = FileManager.default.recursiveRegularFileIterator(
                            at: URL(fileURLWithPath: filename)) else {
                            return []
                        }
                        return sequence.compactMap { childURL -> Message.Subpart? in
                            guard let data = try? Data(contentsOf: childURL) else {
                                return nil
                            }
                            return Message.Subpart.attachment(.init(
                                inline: false,
                                id: UUID().uuidString,
                                type: .file(.init(name: String(childURL.path.removing(prefix: resolved).removing(prefix: "/")),
                                                  content: data,
                                                  mimeType: mimeType(childURL.path)))))
                            }
                    } else {
                        if let data = try? Data(contentsOf: URL(fileURLWithPath: filename)) {
                            return [
                                Message.Subpart.attachment(.init(
                                    inline: false,
                                    id: UUID().uuidString,
                                    type: .file(.init(name: filename.lastPathComponent,
                                                      content: data,
                                                      mimeType: mimeType(filename)))))]
                        } else {
                            return []
                        }
                    }
                } else {
                    return []
                }
            case .placeholder:
                return []
            }
        }
        let vectorStoreIDs = [listModel.chat(id: chatID)?.vectorStore].compactMap { $0 }
        var configuration = Message.Configuration(hostedWebSearchEnabled: webSearchEnabled,
                                                  vectorStoreIDs: vectorStoreIDs,
                                                  shouldThink: thinkingEnabled,
                                                  reasoningEffort: selectedReasoningEffort,
                                                  serviceTier: selectedServiceTier)

        // Set the chat-pinned model for this request. The model selector only
        // offers models from the chat's provider, so switching OpenAI/Gemini/
        // Anthropic/DeepSeek mid-conversation cannot corrupt the request chain.
        if let modelIdentifier = chatToolbar.selectedModelIdentifier ?? effectiveModel {
            configuration.model = modelIdentifier
            setCurrentChatModelIfNeeded(modelIdentifier)
        }

        // Terminal state / visible screen auto-population moved server-side to
        // ChatAgent (autoProvidedContext) so phone- and desktop-originated turns are
        // handled uniformly and are not doubled; nothing is attached here.
        var message = {
            if attachments.isEmpty {
                return Message(chatID: chatID,
                               author: .user,
                               content: .plainText(trimmed, context: nil),
                               sentDate: Date(),
                               uniqueID: UUID(),
                               configuration: configuration)
            } else {
                let parts = [.plainText(trimmed)] + attachments
                return Message(chatID: chatID,
                               author: .user,
                               content: .multipart(parts,
                                                   vectorStoreID: listModel.chat(id: chatID)?.vectorStore),
                               sentDate: Date(),
                               uniqueID: UUID(),
                               configuration: configuration)
            }
        }()
        // Wire the new user message to the last agent response so
        // the LLM can resume from that point on edit/retry.
        if message.inResponseTo == nil,
           let lastAgentMessage = model?.items.last(where: { item in
               item.existingMessage?.message.author == .agent
           }) {
            message.inResponseTo = lastAgentMessage.existingMessage?.message.responseID
        }
        do {
            try client.publish(message: message,
                               toChatID: chatID,
                               partial: false)
            inputView.clear()
            eligibleForAutoPaste = true
        } catch {
            DLog("\(error)")
        }
    }

    private var session: PTYSession? {
        guard let guid = model?.terminalSessionGuid else {
            return nil
        }
        return iTermController.sharedInstance().anySession(forReference: guid)
    }

    private var shouldShareTerminalStateAutomatically: Bool {
        let rce = RemoteCommandExecutor.instance
        if let chatID,
           let guid = model?.terminalSessionGuid,
           session != nil {
            return rce.permission(chatID: chatID,
                                  inSessionGuid: guid,
                                  category: .checkTerminalState) == .always
        }
        return false
    }
}

extension ChatViewController {
    func streamLastCommand(_ userInfo: [AnyHashable: Any]) {
        it_assert(streaming)
        guard haveLinkedTerminalSession else {
            return
        }
        guard let command = userInfo[PTYCommandDidExitUserInfoKeyCommand] as? String else {
            return
        }
        guard let chatID else {
            return
        }

        let exitCode = (userInfo[PTYCommandDidExitUserInfoKeyExitCode] as? Int32) ?? 0
        let directory = userInfo[PTYCommandDidExitUserInfoKeyDirectory] as? String
        let remoteHost = userInfo[PTYCommandDidExitUserInfoKeyRemoteHost] as? VT100RemoteHostReading
        // Defensive extraction: this is a notification observer with no
        // type contract on the userInfo dict. A malformed post (future
        // shape change, third-party poster, etc.) shouldn't crash the
        // chat window; just log and skip the stream.
        guard let startLine = userInfo[PTYCommandDidExitUserInfoKeyStartLine] as? Int32,
              let lineCount = userInfo[PTYCommandDidExitUserInfoKeyLineCount] as? Int32,
              let dataSource = userInfo[PTYCommandDidExitUserInfoKeyDataSource] as? iTermTextDataSource,
              let url = userInfo[PTYCommandDidExitUserInfoKeyURL] as? URL else {
            RLog("PTYCommandDidExit notification missing required userInfo keys: \(userInfo)")
            return
        }
        let extractor = iTermTextExtractor(dataSource: dataSource)
        let content = extractor.content(
            in: VT100GridWindowedRange(
                coordRange: VT100GridCoordRange(
                    start: VT100GridCoord(x: 0, y: startLine),
                    end: VT100GridCoord(x: 0, y: startLine + lineCount)),
                columnWindow: VT100GridRange(location: 0, length: 0)),
            attributeProvider: nil,
            nullPolicy: .kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal,
            pad: false,
            includeLastNewline: false,
            trimTrailingWhitespace: true,
            cappedAtSize: -1,
            truncateTail: false,
            continuationChars: nil,
            coords: nil,
            deduplicateDECDHL: true) as! String
        let cmd = TerminalCommand(username: remoteHost?.username,
                                  hostname: remoteHost?.hostname,
                                  directory: directory,
                                  command: command,
                                  output: content,
                                  exitCode: exitCode,
                                  url: url)
        try? client.publishMessageFromUser(chatID: chatID,
                                                         content: .terminalCommand(cmd))
    }
}

extension ChatViewController: ChatViewControllerModelDelegate {
    private func assertMessageTypeAllowed(_ message: Message?) {
        ChatViewControllerModel.assertMessageTypeAllowed(message)
    }

    func chatViewControllerModel(didInsertItemAtIndex i: Int) {
        if let model {
            assertMessageTypeAllowed(model.items[i].existingMessage?.message)
        }
        if viewModelLocksProvider {
            chatToolbar.update()
        }
        DLog("Insert tableview row at \(i)")
        estimatedCount += 1
        it_assert(i <= estimatedCount)
        tableView.insertRows(at: IndexSet(integer: i))

        // Disable buttons in message that just became second-to-last.
        if let model,
           model.items.count > 1,
           model.items[model.items.count - 2].hasButtons {
            let rows = IndexSet(integer: model.items.count - 2)
            tableView.beginUpdates()
            tableView.reloadData(forRowIndexes: rows,
                                  columnIndexes: IndexSet(integer: 0))
            tableView.noteHeightOfRows(withIndexesChanged: rows)
            tableView.endUpdates()
        }
        setNeedsLayoutNow()
    }

    func chatViewControllerModel(didRemoveItemsInRange range: Range<Int>) {
        DLog("Remove tableview row at \(range)")
        it_assert(range.upperBound <= estimatedCount)
        estimatedCount -= range.count
        tableView.removeRows(at: IndexSet(ranges: [range]))
        setNeedsLayoutNow()
    }

    func chatViewControllerModel(didModifyItemsAtIndexes indexSet: IndexSet) {
        if let model {
            for i in indexSet {
                assertMessageTypeAllowed(model.items[i].existingMessage?.message)
            }
        }
        if viewModelLocksProvider {
            chatToolbar.update()
        }
        guard let scrollView = tableView.enclosingScrollView,
              scrollView.documentView != nil else {
            return
        }
        tableView.beginUpdates()
        tableView.noteHeightOfRows(withIndexesChanged: indexSet)
        tableView.reloadData(forRowIndexes: indexSet,
                              columnIndexes: IndexSet(integer: 0))
        tableView.endUpdates()
        setNeedsLayoutNow()
    }
}

// ChatViewControllerModelDelegate conformance + handler methods
// live in the base (they're pure table view reactions, no
// session-binding state involved).

fileprivate enum RemoteCommandButtonIdentifier: String {
    case allowOnce
    case allowAlways
    case denyOnce
    case denyAlways
}

fileprivate enum PickSessionButtonIdentifier: String {
    case pickSession
    case cancel
}

// Switches over every Message.Content case to produce the rendered
// attributed-string body. Several cases (.remoteCommandRequest,
// .selectSessionRequest, .clientLocal(.permissions/.offerLink/
// .executingCommand/.pickingSession)) produce AITerm session-bound
// strings and never appear in orchestrator transcripts.
extension Message.Content {
    func attributedStringValue(linkColor: NSColor,
                               textColor: NSColor,
                               renderMentions: Bool = false) -> NSAttributedString {
        switch self {
        case .multipart:
            it_fatalError()  // TODO: This will be hit. We need a different cell type for multipart messages.
        case .renameChat, .append, .commit, .setPermissions, .terminalCommand, .appendAttachment,
                .vectorStoreCreated, .userCommand:
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ]
            return NSAttributedString(string: "A vector store was created", attributes: attributes)
        case .watcherEvent(let payload):
            // Render with the system-message styling so the user
            // sees it's not their own message. Symbol prefix marks
            // it as an iTerm2-posted event.
            return AttributedStringForSystemMessageMarkdown("📡 \(payload.detail)") {}
        case .unsupported:
            // A message a newer iTerm2 sent that this build can't decode.
            return AttributedStringForSystemMessageMarkdown(
                "This message requires a newer version of iTerm2 to view.") {}
        case .plainText(let string, context: _):
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ]
            let rendered = NSAttributedString(
                string: ChatViewController.trimLeadingWhitespaceForDisplay(string),
                attributes: attributes
            )
            // The user can @-mention sessions in orchestration chats; their
            // sent message carries @<guid> the same way the orchestrator's do,
            // so rewrite those to clickable session names here too. Only in
            // orchestration chats — see renderMentions.
            guard renderMentions else {
                return rendered
            }
            return OrchestrationMentionRenderer.link(rendered, linkColor: linkColor)
        case .markdown(let string), .explanationResponse(_, _, let string):
            let rendered = AttributedStringForGPTMarkdown(
                ChatViewController.trimLeadingWhitespaceForDisplay(string),
                linkColor: linkColor,
                textColor: textColor) { }
            // Turn any @-prefixed session/workgroup ids the orchestrator
            // emitted into clickable links to the entity's current name.
            // Orchestration chats only (see renderMentions) so ordinary
            // markdown that happens to contain an @<uuid> isn't mutated.
            guard renderMentions else {
                return rendered
            }
            return OrchestrationMentionRenderer.link(rendered, linkColor: linkColor)
        case .explanationRequest(request: let request):
            let string =
            if let url = request.url {
                "Explain the output of \(request.subjectMatter) based on [attached terminal content](\(url))."
            } else {
                "Explain the output of \(request.subjectMatter) based on some no-longer-available content."
            }
            let epilogue = if request.truncated {
                "\n*Note: The command output was truncated because it exceeded the maximum number of lines supported by AI Chat*"
            } else {
                ""
            }
            return AttributedStringForGPTMarkdown(string + epilogue,
                                                  linkColor: linkColor,
                                                  textColor: textColor) { }
        case .remoteCommandRequest(let payload, safe: let safe):
            switch payload {
            case .classic(let request):
                let specific = request.permissionDescription + "."
                let warning = if safe == false {
                    "⚠️ **The AI safety check flagged this command as potentially dangerous. Review it with care.**\n\n"
                } else {
                    ""
                }
                let general =  "Would you like to grant AI **\(request.content.permissionCategory.rawValue)** permission?"
                let info = "*If you grant or deny permission, it affects only this chat conversation while linked to this particular terminal session. You can change permissions in the chat Info menu.*"
                return AttributedStringForGPTMarkdown(warning + specific + " " + general + "\n\n" + info,
                                                      linkColor: linkColor,
                                                      textColor: textColor) {}
            case .external(let ext):
                // External payloads (from orchestration mode) render as
                // a system-message bubble showing what the agent did.
                // No Approve / Deny buttons, because the orchestrator's
                // permission gate is the workgroup-claim prompt, not
                // per-call. Run it through the mention renderer so the
                // @<guid> session/workgroup targets the activity line
                // carries become clickable links (or "[defunct session]"
                // once the target is gone).
                let rendered = AttributedStringForSystemMessageMarkdown(ext.markdownDescription) {}
                return OrchestrationMentionRenderer.link(rendered, linkColor: linkColor)
            }
        case .remoteCommandResponse(let response, _, _, _):
            switch response {
            case .success(let object):
                it_fatalError("\(object)")
            case .failure(let error):
                return AttributedStringForGPTMarkdown(error.localizedDescription,
                                                      linkColor: linkColor,
                                                      textColor: textColor) {}
            }
        case .clientLocal(let clientLocal):
            switch clientLocal.action {
            case .pickingSession:
                return AttributedStringForSystemMessageMarkdown("Waiting for a session to be selected…") { }
            case .executingCommand(let command):
                return AttributedStringForSystemMessageMarkdown(command.markdownDescription) { }
            case .notice(let message):
                return AttributedStringForSystemMessagePlain(message, textColor: textColor)
            case .streamingChanged(let state):
                return switch state {
                case .stopped:
                    AttributedStringForSystemMessageMarkdown("Terminal commands will no longer be sent to AI automatically.") {}
                case .active:
                    AttributedStringForSystemMessageMarkdown("All terminal commands in the linked session will be sent to AI automatically.") {}
                case .stoppedAutomatically:
                    AttributedStringForSystemMessageMarkdown("Terminal commands will no longer be sent to AI automatically. Automatic sending always terminates when iTerm2 restarts or the current chat changes.") {}
                }
            case let .offerLink(terminal: terminal, guid: _, name: name):
                let displayName = name ?? "Unnamed session"
                let kind = terminal ? "terminal" : "browser"
                let body = "**Link this chat to \(kind) session \u{201C}\(displayName)\u{201D}, "
                    + "or enable orchestration?**\n\n"
                    + "Linking gives the AI access to this \(kind) session subject to "
                    + "your per-call permission. **Orchestration** is an alternative "
                    + "mode where the AI can coordinate multiple sessions. "
                    + "It uses automatic safety checking and one-time per-session approval instead of "
                    + "fine-grained permissions."
                return AttributedStringForSystemMessageMarkdown(body) {}
            case .offerOrchestration:
                let body = "**Enable orchestration for this chat?**\n\n"
                    + "**Orchestration** lets the AI coordinate across "
                    + "multiple terminal sessions. It can read the contents "
                    + "of any session, and you grant a one-time approval "
                    + "before it controls a session instead of approving "
                    + "every call. It also runs in **auto mode**: each "
                    + "command the AI proposes is checked for safety by your "
                    + "AI provider, and anything risky is held for your review."
                return AttributedStringForSystemMessageMarkdown(body) {}
            case .permissions:
                return AttributedStringForSystemMessageMarkdown("You can use these buttons or the info button menu at the top of the chat window to control AI permissions for this chat.") {}
            case let .workgroupPermissionRequest(_, workgroupID, workgroupName, summary):
                // Three distinct prompt shapes share this content type:
                //   - "spawn": the orchestrator wants to open a brand-new
                //     session. There's no real workgroup_id and the
                //     workgroupName field is just a placeholder ("New
                //     session"), so we don't quote it — heading reads
                //     "**Open a new session?**" and the specifics
                //     (window placement, command being run) come from
                //     the summary text promptForSpawn built.
                //   - synthetic "session:<guid>": a standalone session,
                //     not part of any user-configured workgroup. The
                //     user never sees the word "workgroup" anywhere
                //     else in that flow, so use the session phrasing.
                //   - real workgroup_id: workgroup phrasing.
                let body: String
                if workgroupID == WorkgroupIntrospection.spawnWorkgroupID {
                    body = "**Open a new session?**\n\n\(summary)"
                } else if workgroupID == WorkgroupIntrospection.commandApprovalWorkgroupID {
                    // Per-command safety approval: the orchestrator's safety
                    // gate flagged a command (or file write) and is asking the
                    // user to approve it before it runs. The specifics live in
                    // the summary the dispatcher built.
                    body = "**Run this command?**\n\n\(summary)"
                } else {
                    let kind = workgroupID.hasPrefix(WorkgroupIntrospection.syntheticWorkgroupIDPrefix)
                        ? "session"
                        : "workgroup"
                    body = "**Allow agent to control \(kind) \u{201C}\(workgroupName)\u{201D}?**\n\n\(summary)"
                }
                return AttributedStringForSystemMessageMarkdown(body) {}
            case .enableOrchestrationRequest:
                let body = """
                **Enable orchestration?**

                Orchestration mode lets the agent read screen contents from any session. To type \
                into a session still requires your permission.
                
                This is a more permissive model than when an agent is linked to \
                a single session, where there are very fine-grained permission settings.

                Enabling will detach any linked terminal or browser session and switch \
                the chat to Orchestration mode.
                """
                return AttributedStringForSystemMessageMarkdown(body) {}
            case let .orchestrationPermissionGranted(_, name):
                let body = "**Granted this chat permission to control "
                    + "\u{201C}\(name)\u{201D}.**\n\n"
                    + "You @-mentioned it, so the agent can act there "
                    + "without asking. Revoke to require approval again."
                return AttributedStringForSystemMessageMarkdown(body) {}
            }

        case .selectSessionRequest(_, terminal: let terminal):
            return AttributedStringForGPTMarkdown(
                "The AI agent needs to run commands in a live \(terminal ? "terminal" : "web browser") session, but none is attached to this chat.",
                linkColor: linkColor,
                textColor: textColor,
                didCopy: {})
        }
    }
}

extension Message {
    var linkColor: NSColor {
        return author == .user ? .white : .linkColor
    }
    var textColor: NSColor {
        return author == .user ? .white : .textColor
    }

    // True when this is the permissions toggle bubble. Its buttons are
    // meant to be re-tappable so the user can cycle Allow/Ask/Never;
    // RegularMessageCellView reads this to skip the default
    // disable-on-click loop in buttonTapped.
    var isPermissionsClientLocal: Bool {
        if case .clientLocal(let clientLocal) = content,
           case .permissions = clientLocal.action {
            return true
        }
        return false
    }

    var buttons: [MessageRendition.Regular.Button] {
        switch content {
        case .plainText, .markdown, .explanationRequest, .explanationResponse,
                .remoteCommandResponse, .renameChat, .append, .commit, .setPermissions,
                .terminalCommand, .appendAttachment, .multipart, .vectorStoreCreated, .userCommand,
                .watcherEvent, .unsupported:
            return []
        case .clientLocal(let clientLocal):
            switch clientLocal.action {
            case .pickingSession, .executingCommand:
                return [.init(title: "Cancel", destructive: true, identifier: "")]
            case .notice: return []
            case .streamingChanged(let state):
                switch state {
                case .active:
                    return [.init(title: "Stop", destructive: true, identifier: "")]
                case .stopped, .stoppedAutomatically:
                    return []
                }
            case .offerLink(terminal: _, guid: _, name: _):
                // Identifiers picked up by the offerLink buttonClicked
                // handler in configure(cell:RegularMessageCellView,...);
                // empty-string ids would conflict with the
                // single-button cases above.
                return [.init(title: "Link", destructive: false, identifier: "link"),
                        .init(title: "Enable Orchestration", destructive: false, identifier: "orchestrate")]
            case .offerOrchestration:
                // Identifier matches the offerOrchestration buttonClicked
                // handler in configure(cell:RegularMessageCellView,...).
                return [.init(title: "Enable Orchestration", destructive: false, identifier: "orchestrate")]
            case let .permissions(terminal: terminal, guid: guid):
                let rce = RemoteCommandExecutor.instance
                var buttons = [MessageRendition.Regular.Button]()
                for category in RemoteCommand.Content.PermissionCategory.allCases {
                    if category.isBrowserSpecific && terminal {
                        continue
                    }
                    if !category.isBrowserSpecific && !terminal {
                        continue
                    }
                    let state = switch rce.permission(chatID: chatID, inSessionGuid: guid, category: category) {
                    case .always:
                        if category.autopopulatedWhenAlways {
                            "Provided automatically"
                        } else {
                            "Always"
                        }
                    case .never:
                        "Never"
                    case .ask:
                        "Ask"
                    }
                    buttons.append(.init(title: category.rawValue + ": " + state,
                                         destructive: false,
                                         identifier: category.rawValue))
                }
                return buttons
            case let .workgroupPermissionRequest(requestID, _, _, _):
                // Button identifiers carry the choice + requestID joined
                // by a colon. configure(cell:RegularMessageCellView,...)
                // wires the buttonClicked handler that parses them and
                // publishes the matching workgroupPermissionResponse.
                return [
                    .init(title: "Approve",
                          destructive: false,
                          identifier: "workgroupPermission:\(ApprovalChoice.approve.rawValue):\(requestID)"),
                    .init(title: "Deny",
                          destructive: true,
                          identifier: "workgroupPermission:\(ApprovalChoice.deny.rawValue):\(requestID)"),
                ]
            case let .enableOrchestrationRequest(requestID):
                return [
                    .init(title: "Enable Orchestration",
                          destructive: false,
                          identifier: "enableOrchestration:\(ApprovalChoice.approve.rawValue):\(requestID)"),
                    .init(title: "Not Now",
                          destructive: true,
                          identifier: "enableOrchestration:\(ApprovalChoice.deny.rawValue):\(requestID)"),
                ]
            case let .orchestrationPermissionGranted(scope, _):
                // Identifier carries the scope after the first colon.
                // The scope itself can contain a colon ("session:<guid>"),
                // so handleRevokeOrchestrationPermissionButton splits with
                // maxSplits 1 and keeps everything after it verbatim.
                return [
                    .init(title: "Revoke",
                          destructive: true,
                          identifier: "revokeOrchestrationPermission:\(scope)"),
                ]
            }
        case .selectSessionRequest:
            return [.init(title: "Select a Session", destructive: false, identifier: PickSessionButtonIdentifier.pickSession.rawValue),
                    .init(title: "Cancel", destructive: true, identifier: PickSessionButtonIdentifier.cancel.rawValue)]
        case .remoteCommandRequest(let payload, safe: _):
            switch payload {
            case .classic:
                return [.init(title: "Allow Once", destructive: false, identifier: RemoteCommandButtonIdentifier.allowOnce.rawValue),
                        .init(title: "Always Allow", destructive: false, identifier: RemoteCommandButtonIdentifier.allowAlways.rawValue),
                        .init(title: "Deny this Time", destructive: true, identifier: RemoteCommandButtonIdentifier.denyOnce.rawValue),
                        .init(title: "Always Deny", destructive: true, identifier: RemoteCommandButtonIdentifier.denyAlways.rawValue)]
            case .external:
                // Orchestration tool calls aren't per-call gated; no buttons.
                return []
            }
        }
    }

    func attributedStringValue(renderMentions: Bool) -> NSAttributedString {
        return content.attributedStringValue(linkColor: linkColor,
                                             textColor: textColor,
                                             renderMentions: renderMentions)
    }
}

extension ChatViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleAlwaysAllow(_:)),
           let category = menuItem.representedObject as?  RemoteCommand.Content.PermissionCategory,
           let autoTitle = category.autopopulationTitle {
            if menuItem.state == .on {
                menuItem.title = autoTitle
            } else {
                menuItem.title = "AI can \(category.rawValue)"
            }
        }
        return true
    }
}

extension ChatViewController: ChatToolbarDataSource {
    private func reasoningEffort(for model: AIMetadata.Model) -> ResponsesRequestBody.ReasoningOptions.Effort? {
        guard !model.reasoningEfforts.isEmpty else {
            return nil
        }
        if let preferredReasoningEffort,
           model.supports(reasoningEffort: preferredReasoningEffort) {
            return preferredReasoningEffort
        }
        let fallback = iTermUserDefaults.userDefaults().bool(forKey: Self.thinkUserDefaultsKey)
            ? model.thinkingOnEffort
            : model.thinkingOffEffort
        if model.supports(reasoningEffort: fallback) {
            return fallback
        }
        return model.reasoningEfforts.first
    }

    private func serviceTier(for model: AIMetadata.Model) -> ResponsesRequestBody.ServiceTier? {
        guard !model.serviceTiers.isEmpty else {
            return nil
        }
        if let preferredServiceTier,
           model.supports(serviceTier: preferredServiceTier) {
            return preferredServiceTier
        }
        return nil
    }

    var provider: LLMProvider? {
        if let model = effectiveChatModel {
            return LLMProvider(model: model)
        }
        return AITermController.provider
    }

    var availableProviderOptions: [ChatProviderOption] {
        // Providers the user has configured a key for come first.
        var options = Self.chatSelectableProviders
            .filter { providerIsAvailable($0) }
            .map { ChatProviderOption.vendor($0) }

        // Keep the current chat's provider visible even if its key was removed
        // (e.g. an existing/locked chat), so its selection can still be shown.
        if let currentProviderIdentifier,
           let vendor = ChatProviderOption.vendor(from: currentProviderIdentifier),
           !options.contains(where: { $0.identifier == currentProviderIdentifier }),
           !LLMMetadata.alternateModels(for: vendor).isEmpty {
            options.append(ChatProviderOption.vendor(vendor))
        }

        // Then a separator followed by each manually-configured model.
        let manualModels = manualConfiguredModels
        if !manualModels.isEmpty {
            if !options.isEmpty {
                options.append(ChatProviderOption.separator())
            }
            for model in manualModels {
                options.append(ChatProviderOption.manualModel(name: model.name))
            }
        }
        return options
    }

    var effectiveProviderIdentifier: String? {
        return currentProviderIdentifier
    }

    var canChangeProvider: Bool {
        return chatID != nil && !chatProviderIsLocked
    }

    var canChangeModel: Bool {
        // Only the PROVIDER locks once a conversation starts; switching
        // models within the provider stays allowed mid-chat (availableModels
        // is already restricted to the effective provider's own models, and
        // ChatProviderBinding enforces the same rule at the model layer).
        return chatID != nil
    }

    var availableModels: [AIMetadata.Model] {
        // A manual model is the whole selection (it lives in the provider
        // popup), so there is no sub-model list to offer.
        if let identifier = currentProviderIdentifier,
           ChatProviderOption.manualName(from: identifier) != nil {
            return effectiveChatModel.map { [$0] } ?? []
        }
        guard let model = effectiveChatModel else {
            return []
        }
        guard let vendor = effectiveChatProvider else {
            return [model]
        }
        return LLMMetadata.alternateModels(for: vendor)
    }

    var webSearchEnabled: Bool {
        get {
            guard let model = provider?.model else {
                return false
            }
            if !model.features.contains(.hostedWebSearch) {
                return false
            }
            if #available(macOS 11, *) {
                return iTermUserDefaults.userDefaults().bool(forKey: Self.webSearchUserDefaultsKey)
            }
            return false
        }
        set {
            return iTermUserDefaults.userDefaults().set(newValue, forKey: Self.webSearchUserDefaultsKey)
        }
    }
    var thinkingEnabled: Bool {
        get {
            guard let model = provider?.model else {
                return false
            }
            if !model.features.contains(.configurableThinking) {
                return false
            }
            if let effort = reasoningEffort(for: model) {
                return effort != model.thinkingOffEffort
            }
            return iTermUserDefaults.userDefaults().bool(forKey: Self.thinkUserDefaultsKey)
        }
        set {
            iTermUserDefaults.userDefaults().set(newValue, forKey: Self.thinkUserDefaultsKey)
            guard let model = provider?.model,
                  !model.reasoningEfforts.isEmpty else {
                return
            }
            let effort = newValue ? model.thinkingOnEffort : model.thinkingOffEffort
            if model.supports(reasoningEffort: effort) {
                preferredReasoningEffort = effort
            } else {
                preferredReasoningEffort = model.reasoningEfforts.first
            }
        }
    }

    var selectedReasoningEffort: ResponsesRequestBody.ReasoningOptions.Effort? {
        guard let model = provider?.model else {
            return nil
        }
        return reasoningEffort(for: model)
    }

    var selectedServiceTier: ResponsesRequestBody.ServiceTier? {
        guard let model = provider?.model else {
            return nil
        }
        return serviceTier(for: model)
    }

    func showSessionButtonMenu(_ sender: NSButton) {
        guard let chatID else {
            return
        }
        let menu = NSMenu()

        // Orchestration mode is mutually exclusive with session/
        // browser binding. The toggle clears any binding when
        // enabled and clears claimed workgroups + watchers when
        // disabled (see ChatListModel.setOrchestrationEnabled).
        let orchestrationOn = listModel.chat(id: chatID)?.orchestrationEnabled ?? false
        if orchestrationOn {
            menu.addItem(withTitle: "Disable Orchestration",
                         action: #selector(disableOrchestration(_:)),
                         target: self)
        } else {
            menu.addItem(withTitle: "Enable Orchestration",
                         action: #selector(enableOrchestration(_:)),
                         target: self)
        }
        menu.addItem(NSMenuItem.separator())

        // Terminal / Browser session items are only meaningful in
        // session-bound mode. In orchestration mode the chat
        // coordinates workgroups rather than a single bound session,
        // so suppress the link/unlink/permission items entirely
        // (rather than letting the user create a chat that has both
        // a binding and orchestrationEnabled, which the model
        // prohibits).
        if !orchestrationOn {
            // Terminal session items
            if let guid = model?.terminalSessionGuid,
               iTermController.sharedInstance().anySession(forReference: guid) != nil {

                menu.addItem(withTitle: "Reveal Linked Terminal Session", action: #selector(revealLinkedTerminalSession(_:)), target: self)
                menu.addItem(withTitle: "Unlink Terminal Session", action: #selector(unlinkTerminalSession(_:)), target: self)
                // Inline-panel CVCs are already hosted in their session — no
                // need to offer to put themselves there.
                if !isInlinePanel {
                    menu.addItem(withTitle: "Put Chat in Linked Terminal Session",
                                 action: #selector(putChatInLinkedTerminalSession(_:)),
                                 target: self)
                }
                menu.addItem(NSMenuItem.separator())

                let rce = RemoteCommandExecutor.instance
                for category in RemoteCommand.Content.PermissionCategory.allCases {
                    if category.isBrowserSpecific {
                        continue
                    }
                    menu.addItem(withTitle: category.regularTitle,
                                 action: #selector(toggleAlwaysAllow(_:)),
                                 target: self,
                                 state: rce.controlState(chatID: chatID,
                                                         guid: guid,
                                                         category: category),
                                 object: category)

                }
                menu.addItem(NSMenuItem.separator())

                if haveLinkedTerminalSession {
                    menu.addItem(withTitle: "Send Commands & Output to AI Automatically",
                                 action: #selector(toggleStream(_:)),
                                 target: self,
                                 state: streaming ? .on : .off,
                                 object: nil)
                    menu.addItem(NSMenuItem.separator())
                }
            } else {
                menu.addItem(withTitle: "Link Terminal Session", action: #selector(objcLinkTerminalSession(_:)), target: self)
                menu.addItem(NSMenuItem.separator())
            }

            // Browser session items
            if let guid = model?.browserSessionGuid,
               iTermController.sharedInstance().anySession(forReference: guid) != nil {

                menu.addItem(withTitle: "Reveal Linked Web Browser Session", action: #selector(revealLinkedBrowserSession(_:)), target: self)
                menu.addItem(withTitle: "Unlink Web Browser Session", action: #selector(unlinkBrowserSession(_:)), target: self)
                if !isInlinePanel {
                    menu.addItem(withTitle: "Put Chat in Linked Browser Session",
                                 action: #selector(putChatInLinkedBrowserSession(_:)),
                                 target: self)
                }
                menu.addItem(NSMenuItem.separator())

                let rce = RemoteCommandExecutor.instance
                for category in RemoteCommand.Content.PermissionCategory.allCases {
                    if !category.isBrowserSpecific {
                        continue
                    }
                    menu.addItem(withTitle: "AI can \(category.rawValue)",
                                 action: #selector(toggleAlwaysAllow(_:)),
                                 target: self,
                                 state: rce.controlState(chatID: chatID,
                                                         guid: guid,
                                                         category: category),
                                 object: category)

                }
                menu.addItem(NSMenuItem.separator())
            } else {
                menu.addItem(withTitle: "Link Browser Session", action: #selector(objcLinkBrowserSession(_:)), target: self)
                menu.addItem(NSMenuItem.separator())
            }
        }


        menu.addItem(withTitle: "Help", action: #selector(showLinkedSessionHelp(_:)), target: self)

        // Position the menu just below the button
        let location = NSPoint(x: 0, y: sender.bounds.height)
        menu.popUp(positioning: nil, at: location, in: sender)
    }

    func toggleWebSearch() {
        webSearchEnabled = !webSearchEnabled
    }

    func toggleThinking() {
        thinkingEnabled = !thinkingEnabled
    }

    func toolbarDidUpdate() {
        guard isViewLoaded else {
            return
        }
        if let floating = floatingControlsView as? FloatingChatToolbarView {
            floating.setNeedsLayoutNow()
        }
        view.needsLayout = true
        delegate?.chatViewControllerDidUpdateToolbar(self)
    }

    func selectedModelDidChange() {
        guard canChangeModel else {
            chatToolbar.update()
            return
        }
        guard let modelName = chatToolbar.selectedModelIdentifier,
              model(named: modelName) != nil else {
            return
        }
        setCurrentChatModelIfNeeded(modelName)
    }

    func selectedProviderDidChange() {
        guard canChangeProvider,
              let identifier = chatToolbar.selectedProviderIdentifier else {
            chatToolbar.update()
            return
        }
        // A specific manual model was chosen.
        if let manualName = ChatProviderOption.manualName(from: identifier),
           let model = manualConfiguredModels.first(where: { $0.name == manualName }) {
            providerSelectionIdentifier = identifier
            setCurrentChatModelIfNeeded(model.name)
            return
        }
        // A vendor was chosen: pin to its recommended model.
        guard let provider = ChatProviderOption.vendor(from: identifier),
              let model = recommendedModel(for: provider) else {
            chatToolbar.update()
            return
        }
        providerSelectionIdentifier = identifier
        setCurrentChatModelIfNeeded(model.name)
    }

    func selectedReasoningEffortDidChange() {
        guard let rawValue = chatToolbar.reasoningEffortButton?.selectedItem?.representedObject as? String,
              let effort = ResponsesRequestBody.ReasoningOptions.Effort(rawValue: rawValue),
              let model = provider?.model,
              model.supports(reasoningEffort: effort) else {
            return
        }
        preferredReasoningEffort = effort
        iTermUserDefaults.userDefaults().set(effort != model.thinkingOffEffort,
                                             forKey: Self.thinkUserDefaultsKey)
    }

    func selectedServiceTierDidChange() {
        guard let rawValue = chatToolbar.serviceTierButton?.selectedItem?.representedObject as? String,
              let tier = ResponsesRequestBody.ServiceTier(rawValue: rawValue),
              let model = provider?.model,
              model.supports(serviceTier: tier) else {
            return
        }
        preferredServiceTier = tier
    }

    var effectiveModel: String? {
        return provider?.model.name
    }
}

// MARK: - Inline (right-gutter) chat support

extension ChatViewController {
    // Whether this CVC is acting as an inline right-gutter panel rather
    // than the chat window's main content view. Read from many call sites
    // to skip behavior that only makes sense in window mode (e.g., updating
    // the window title, offering "Put Chat in Linked Session").
    var isInlinePanel: Bool {
        return panelAttachedSession != nil || inlinePanelCoordinator != nil
    }

    fileprivate func rootViewDidMoveToWindow() {
        guard view.window != nil else { return }
        // Install the panel toolbar here rather than in attach(to:): the gutter
        // controller accesses our view (forcing loadView) only after attach, so
        // the view isn't loaded during attach. By the time the view is in a
        // window it is loaded and isInlinePanel is true.
        if isInlinePanel {
            installInlineToolbarIfNeeded()
        }
        if let chatID = pendingPanelChatID {
            pendingPanelChatID = nil
            load(chatID: chatID)
            // load(chatID:) ran reloadData while the gutter controller had
            // not yet set the panel's frame (its positionPanels runs right
            // after attach, and no layout pass has happened yet), so every
            // row's height was measured against a table width of 0 and the
            // bubbles came out hugely too tall, leaving big gaps. Re-measure
            // on the next runloop now that the panel is at its final width.
            // performLayoutNow() lays the table out at that width first;
            // reloadData() then re-queries heightOfRow against it. A plain
            // scrollToBottom isn't enough: performLayoutNow's width-change
            // path only re-measures on a CHANGE, and lastTableViewWidth has
            // already latched the final width by now, so it wouldn't re-fire.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.performLayoutNow()
                self.tableView.reloadData()
                self.scrollToBottom(animated: false)
            }
        }
    }
}

extension ChatViewController: iTermRightGutterPanel {
    // The protocol's `view` requirement is satisfied by NSViewController's
    // own `view` property. Same goes for `panelDelegate` (declared as a
    // stored property on the class so the weak ref has somewhere to live).

    var panelIdentifier: String { Self.inlineChatPanelIdentifier }

    var width: CGFloat {
        iTermGutterPanelWidths.width(forIdentifier: Self.inlineChatPanelIdentifier,
                                     defaultValue: Self.inlineChatPanelWidth)
    }

    var visible: Bool {
        guard let session = currentInlinePanelSession else { return false }
        return session.inlineChatID != nil && session.inlineChatVisible
    }

    func attach(to session: PTYSession) {
        panelAttachedSession = session
        let coordinator = InlinePanelCoordinator(session: session)
        coordinator.controller = self
        inlinePanelCoordinator = coordinator
        delegate = coordinator
        if let chatID = session.inlineChatID {
            pendingPanelChatID = chatID
            // If we've already been hosted in a window (the controller sets
            // panelDelegate before adding the view, but a re-attach can
            // happen later), try loading immediately.
            if view.window != nil {
                rootViewDidMoveToWindow()
            }
            // Intentionally does NOT auto-link to the session. New inline chats
            // are created unlinked (PTYSession.createInlineChat) with an
            // .offerLink message so the user chooses Link vs Enable
            // Orchestration, the same as the chat window's new-chat flow.
            // Already-linked and orchestration chats are left as-is on attach.
        }
    }

    func detach() {
        // Tear down streaming so a hidden inline chat doesn't keep
        // mirroring commands. Also tear down the broker subscription
        // explicitly: relying on deinit to do it is fragile because the
        // CVC can stay alive through retained closures and panel-registry
        // weak references long after detach, during which time broker
        // deliveries would still flow through and mutate self.model /
        // post hidden-title side effects on an invisible controller.
        if streaming {
            stopStreaming()
        }
        brokerSubscription?.unsubscribe()
        brokerSubscription = nil
        chatID = nil
        panelAttachedSession = nil
        pendingPanelChatID = nil
        inlinePanelCoordinator = nil
        delegate = nil
        inlineToolbarView?.removeFromSuperview()
        inlineToolbarView = nil
    }

    private func installInlineToolbarIfNeeded() {
        guard isViewLoaded, inlineToolbarView == nil else { return }
        let toolbar = InlineChatToolbarView()
        toolbar.delegate = self
        toolbar.titleLabel.stringValue = chatTitle
        toolbar.autoresizingMask = []
        view.addSubview(toolbar)
        inlineToolbarView = toolbar
        setNeedsLayoutNow()
    }

    func updateInlineToolbarTitle() {
        inlineToolbarView?.titleLabel.stringValue = chatTitle
    }

    // The panel may outlive its initial session if SessionView's delegate
    // is swapped (peer reassignment). Mirror the resolution pattern used by
    // iTermClippingsGutterPanel: prefer the SessionView's current delegate
    // if our hosted view is still attached, falling back to the captured
    // session.
    private var currentInlinePanelSession: PTYSession? {
        if let live = view.superview as? SessionView,
           let session = live.delegate as? PTYSession {
            return session
        }
        return panelAttachedSession
    }
}

// MARK: - Inline panel toolbar delegate

extension ChatViewController: InlineChatToolbarViewDelegate {
    func inlineChatToolbarDidTapNewChat() {
        // Gate user-initiated chat creation the same way PTYSession.toggleInlineChat
        // does (createInlineChat itself only checks ChatClient), so the "+"
        // button can't create a chat in states the menu entry point refuses.
        guard iTermAITermGatekeeper.check() else {
            return
        }
        guard let session = currentInlinePanelSession,
              let newID = session.createInlineChat() else {
            return
        }
        session.inlineChatVisible = true
        load(chatID: newID)
        updateInlineToolbarTitle()
    }

    func inlineChatToolbarDidTapSwitchChat(_ sender: NSButton) {
        let menu = NSMenu()
        let currentID = chatID
        let sessionGuid = currentInlinePanelSession?.guid
        let menuFont = NSFont.menuFont(ofSize: 0)
        let boldMenuFont = NSFontManager.shared.convert(menuFont, toHaveTrait: .boldFontMask)
        // chatStorage is kept most-recent-first (see ChatListModel).
        for i in 0..<listModel.count {
            let chat = listModel.chat(at: i)
            let title = chat.title.isEmpty ? "Untitled Chat" : chat.title
            let item = NSMenuItem(title: title,
                                  action: #selector(switchToChatFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = chat.id
            let isCurrent = (chat.id == currentID)
            item.state = isCurrent ? .on : .off
            // Bold marks the chat linked to this panel's session. Leave the
            // text color to AppKit (pass nil) so a highlighted row inverts to
            // white the way a plain title would; baking a foreground color
            // (e.g. to dim other-session chats) defeats that, so we convey
            // "this session" with weight only.
            let linkedToThisSession = sessionGuid.map { chat.isLinked(toSessionGuid: $0) } ?? false
            let font = linkedToThisSession ? boldMenuFont : menuFont
            item.attributedTitle = ChatTitleStyling.attributedTitle(
                title,
                orchestrator: chat.orchestrationEnabled,
                font: font,
                color: nil,
                includeGlyph: false)
            // Orchestrator chats get a wand in the item's image well: a
            // template image, so the menu re-tints it for dark mode and the
            // blue highlight (an embedded attachment glyph would not invert).
            // The .on checkmark lives in a separate state-image column, so it
            // coexists with the image on the current item.
            if chat.orchestrationEnabled {
                item.image = ChatTitleStyling.orchestratorTemplateImage(pointSize: font.pointSize)
            }
            menu.addItem(item)
        }
        if menu.items.isEmpty {
            let item = NSMenuItem(title: "No Chats", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: sender.bounds.height),
                   in: sender)
    }

    @objc private func switchToChatFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let session = currentInlinePanelSession else {
            return
        }
        // The menu was built from a snapshot of listModel; the chat may have
        // been deleted (from the chat window, or another instance) while it was
        // open. Don't bind the session to a missing chat: that would leave
        // inlineChatID pointing at a deleted chat (reserving panel width and
        // persisting into the arrangement) while load(chatID:) shows an empty
        // panel.
        guard listModel.index(of: id) != nil else {
            return
        }
        session.inlineChatID = id
        load(chatID: id)
        updateInlineToolbarTitle()
    }

    func inlineChatToolbarDidTapSessionInfo(_ sender: NSButton) {
        // Reuses the chat window's session menu; it already handles inline
        // panel mode (suppresses "Put Chat in Linked Session" etc.).
        showSessionButtonMenu(sender)
    }

    func inlineChatToolbarDidTapClose() {
        guard let session = currentInlinePanelSession else {
            return
        }
        session.inlineChatVisible = false
        // Hiding the panel leaves first responder dangling on the now-gone
        // chat view; return focus to the terminal.
        session.takeFocus()
    }
}

// MARK: - Inline panel delegate

// In-window CVCs are owned by ChatWindowController which acts as the
// delegate; inline-panel CVCs need a delegate too, but the window
// controller's behavior (e.g., dismissing the host window on chat delete)
// doesn't apply. This coordinator provides the small set of behaviors that
// make sense for the gutter case.
class InlinePanelCoordinator: NSObject, ChatViewControllerDelegate {
    weak var session: PTYSession?
    weak var controller: ChatViewController?

    init(session: PTYSession) {
        self.session = session
    }

    func chatViewController(_ controller: ChatViewController,
                            revealSessionWithGuid guid: String) -> Bool {
        if let session = iTermController.sharedInstance().anySession(forReference: guid) {
            session.reveal()
            return true
        }
        return false
    }

    func chatViewControllerDeleteSession(_ controller: ChatViewController) {
        guard let chatID = controller.chatID else { return }
        let warning = iTermWarning()
        warning.title = "Are you sure you want to delete this chat? This action cannot be undone."
        warning.heading = "Delete Chat?"
        let action = iTermWarningAction(label: "Delete") { [weak self] _ in
            // Runs from iTermWarning.runModal() on the main thread.
            MainActor.assumeIsolated {
                do {
                    try ChatClient.instance?.delete(chatID: chatID)
                } catch {
                    DLog("\(error)")
                }
            }
            // Clearing the inline-chat ID drops this panel out of the gutter
            // because the registered widthProvider returns 0 once the ID is
            // nil; the layout cascade tears down the panel. Defer to the
            // next runloop so the menu/warning host this is called from has
            // unwound before the panel is deallocated.
            DispatchQueue.main.async {
                self?.session?.inlineChatID = nil
            }
        }
        action.destructive = true
        warning.warningActions = [iTermWarningAction(label: "Cancel"), action]
        warning.warningType = .kiTermWarningTypePersistent
        warning.runModal()
    }

    func chatViewController(_ controller: ChatViewController,
                            forkAtMessageID messageID: UUID,
                            ofChat chatID: String) {
        // Forking spawns a brand-new chat; surface it in the chat window
        // since the inline panel only hosts one chat per session.
        ChatWindowController.instance(showErrors: true)?.showChatWindow()
    }

    func chatViewControllerDidUpdateToolbar(_ controller: ChatViewController) {
        // Inline panel doesn't drive a toolbar.
    }
}

// MARK: - Right-gutter panel registration

@objc(iTermInlineChatGutterPanelRegistration)
class iTermInlineChatGutterPanelRegistration: NSObject {
    @objc static func register() {
        iTermRightGutterPanelRegistry.sharedInstance().registerPanelType(
            ChatViewController.inlineChatPanelIdentifier,
            factory: {
                // Panel construction happens on the main thread.
                MainActor.assumeIsolated {
                    // The widthProvider gates panel creation on the singletons
                    // being available, so this force-construct is reachable
                    // only when both are non-nil.
                    ChatViewController(listModel: ChatListModel.instance!,
                                       client: ChatClient.instance!)
                }
            },
            widthProvider: { _, session in
                // Called on the main-thread layout-budget path.
                MainActor.assumeIsolated {
                    guard let session,
                          let id = session.inlineChatID,
                          session.inlineChatVisible,
                          let listModel = ChatListModel.instance,
                          ChatClient.instance != nil else {
                        return 0
                    }
                    // The bound chat may no longer exist: an optimistic restore
                    // (restoreInlineChat binds before the DB is open) or a
                    // deletion from the chat window / another instance. Don't
                    // reserve width for, or build a panel onto, a missing chat;
                    // drop the stale binding so it doesn't persist into future
                    // arrangements. The clear is deferred to avoid re-entering
                    // this layout-budget query from inlineChatID's didSet.
                    guard listModel.index(of: id) != nil else {
                        DispatchQueue.main.async {
                            if session.inlineChatID == id {
                                session.inlineChatID = nil
                            }
                        }
                        return 0
                    }
                    return iTermGutterPanelWidths.width(
                        forIdentifier: ChatViewController.inlineChatPanelIdentifier,
                        defaultValue: ChatViewController.inlineChatPanelWidth)
                }
            })
    }
}

// MARK: - New methods (introduced in this branch)
//
// Methods added on top of origin/master, grouped here so the diff
// against origin highlights actual new behavior rather than
// re-ordered content.
extension ChatViewController {
    // Identifier format: "enableOrchestration:<approve|deny>:<requestID>".
    // The agent's request_orchestration_enable tool parks a
    // completion keyed by requestID; the agent's broker-driven
    // handleOrchestrationResponse resumes it when this message lands.
    fileprivate func handleEnableOrchestrationButton(identifier: String,
                                                      chatID: String?) {
        let parts = identifier.split(separator: ":", maxSplits: 2,
                                      omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == "enableOrchestration",
              let choice = ApprovalChoice(rawValue: String(parts[1])),
              let chatID else {
            return
        }
        let approved = (choice == .approve)
        let requestID = String(parts[2])
        do {
            try client.publishUserMessage(
                chatID: chatID,
                content: .userCommand(
                    .enableOrchestrationResponse(requestID: requestID,
                                                  approved: approved)))
        } catch {
            RLog("Chat VC: failed to publish enable-orchestration response: \(error)")
        }
    }

    // Identifier format: "workgroupPermission:<approve|deny>:<requestID>".
    // The orchestrator dispatcher (subscribed on the broker for this
    // chat) resumes its parked tool-call continuation when the
    // response lands.
    fileprivate func handleWorkgroupPermissionButton(identifier: String,
                                                    chatID: String?) {
        let parts = identifier.split(separator: ":", maxSplits: 2,
                                      omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == "workgroupPermission",
              let choice = ApprovalChoice(rawValue: String(parts[1])),
              let chatID else {
            return
        }
        let approved = (choice == .approve)
        let requestID = String(parts[2])
        do {
            try client.publishUserMessage(
                chatID: chatID,
                content: .userCommand(
                    .workgroupPermissionResponse(requestID: requestID,
                                                approved: approved)))
        } catch {
            RLog("Chat VC: failed to publish workgroup permission response: \(error)")
        }
    }

    // Identifier format: "revokeOrchestrationPermission:<scope>". The
    // scope can itself contain a colon ("session:<guid>"), so split with
    // maxSplits 1 and keep the remainder verbatim. OrchestratorClient
    // (subscribed on the broker) drops the scope from claimedScopes.
    fileprivate func handleRevokeOrchestrationPermissionButton(identifier: String,
                                                               chatID: String?) {
        let parts = identifier.split(separator: ":", maxSplits: 1,
                                      omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0] == "revokeOrchestrationPermission",
              let chatID else {
            return
        }
        let scope = String(parts[1])
        do {
            try client.publishUserMessage(
                chatID: chatID,
                content: .userCommand(
                    .revokeOrchestrationPermission(scope: scope)))
        } catch {
            RLog("Chat VC: failed to publish revoke-orchestration-permission: \(error)")
        }
    }

    // MARK: - Orchestration toggle

    @objc fileprivate func enableOrchestration(_ sender: Any?) {
        // Confirm before flipping, because orchestration's permission
        // model is more permissive than the session-bound one: the
        // per-call Allow Once / Always Allow / Deny prompts (with
        // separate categories like RunCommands, WriteToClipboard,
        // etc.) are replaced by one-time per-session approvals that
        // stick for the rest of the chat. Users coming from the
        // menu-driven toggle won't know that without being told.
        let alert = NSAlert()
        alert.messageText = "Enable orchestration mode?"
        alert.informativeText = """
            Orchestration mode lets the agent coordinate across any iTerm2 sessions. \
            It can read screen contents from any session, but to type into a session requires \
            your permission. This is a more permissive model than when an agent is linked to \
            a single session, where there are very fine-grained permission settings.

            Enabling will detach any linked terminal or browser session and switch \
            the chat to Orchestration mode.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Enable Orchestration")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        setOrchestrationEnabled(true)
    }

    @objc fileprivate func disableOrchestration(_ sender: Any?) {
        setOrchestrationEnabled(false)
    }

    // Flip this chat between session-bound and orchestrator modes.
    // The list-model setter clears the fields that don't belong in
    // the new mode (session GUIDs / vector store on enable,
    // claimed workgroups / watchers on disable). The in-flight
    // ChatAgent is dropped FIRST so the next user turn spins up a
    // fresh agent in the right mode; the existing AIConversation
    // history is discarded along with it.
    //
    // Order matters: dropAgent must run BEFORE
    // listModel.setOrchestrationEnabled. The in-flight
    // OrchestratorDispatcher (if any) caches claimedScopes /
    // watchers in memory and persists them on tab-status / session-
    // terminate notifications. If the listModel clear runs first,
    // any queued notification firing between the listModel write and
    // the agent teardown would write the dispatcher's stale caches
    // back to disk, undoing the clear. dropAgent first → dispatcher
    // deinits, unsubscribes its observers, can no longer persist.
    // Turn on orchestration for the currently loaded chat. Used by the
    // "try orchestration" onboarding entry point, which creates a fresh
    // chat and switches it straight into orchestration rather than merely
    // offering it. setOrchestrationEnabled is fileprivate; this is the
    // cross-file door into it.
    func enableOrchestration() {
        setOrchestrationEnabled(true)
    }

    fileprivate func setOrchestrationEnabled(_ enabled: Bool) {
        guard let chatID else { return }
        if streaming {
            stopStreaming()
        }
        ChatService.instance?.dropAgent(forChatID: chatID)
        // Also drop the client-side orchestrator dispatcher (and its
        // persisted-watcher and broker-subscription state) so it
        // rebuilds fresh on the next orchestration tool call. Mirrors
        // dropAgent: order matters, dispatcher tear-down before the
        // listModel write so a tab-status notification that fires
        // between the two doesn't get the dispatcher persisting stale
        // claim / watcher state back to disk after the model clear.
        OrchestratorClient.instance?.dropDispatcher(forChatID: chatID)
        do {
            try listModel.setOrchestrationEnabled(enabled, forChatID: chatID)
        } catch {
            RLog("Failed to toggle orchestration: \(error)")
            return
        }
        inputView.refreshPlaceholder()
        let notice = enabled
            ? "Orchestration enabled. Agent can see content of all sessions."
            : "Orchestration disabled."
        try? client.publishNotice(chatID: chatID, notice: notice)
    }

}
