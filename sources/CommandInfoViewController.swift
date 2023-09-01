//
//  CommandInfoViewController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/23/23.
//

import Cocoa

@objc(iTermCommandInfoViewControllerDelegate)
protocol CommandInfoViewControllerDelegate: AnyObject {
    @objc func commandInfoSend(_ string: String)
    @objc func commandInfoOpenInCompose(_ string: String)
    @objc func commandInfoSelectOutput(_ mark: VT100ScreenMarkReading)
    @objc func commandInfoDisable()
}

@objc(iTermCommandInfoViewController)
class CommandInfoViewController: NSViewController {
    @IBOutlet weak var proxyIcon: DraggableImageView!
    @IBOutlet weak var command: NSTextField!
    @IBOutlet weak var directory: NSTextField!
    @IBOutlet weak var returnCode: NSTextField!
    @IBOutlet weak var runningTime: NSTextField!
    @IBOutlet weak var output: NSTextField!
    @IBOutlet weak var sendCommand: NSButton!
    @IBOutlet weak var copyCommand: NSButton!
    @IBOutlet weak var sendDirectory: NSButton!
    @IBOutlet weak var copyDirectory: NSButton!
    @IBOutlet weak var copyOutput: NSButton!
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    @IBOutlet weak var startedAtStackView: NSStackView!
    @IBOutlet weak var startedAt: NSTextField!
    @IBOutlet weak var stackView: NSStackView!
    @IBOutlet weak var copiedView: CopiedView!

    weak var delegate: CommandInfoViewControllerDelegate?

    private let _command: String
    private let _directory: String?
    private let _returnCode: iTermPromise<NSNumber>
    private let _runningTime: TimeInterval?
    private let _size: Int
    private let _outputPromise: iTermRenegablePromise<NSString>
    private let _outputProgress: Progress
    private let _startDate: Date?
    private weak var enclosingPopover: NSPopover?
    private var timer: Timer?
    private var runtimeConstraint: NSLayoutConstraint?
    private var _mark: VT100ScreenMarkReading

    @objc(presentOffscreenCommandLine:directory:outputSize:outputPromise:outputProgress:inView:at:delegate:)
    static func present(offscreenCommandLine: iTermOffscreenCommandLine,
                        directory: String?,
                        outputSize: Int,
                        outputPromise: iTermRenegablePromise<NSString>,
                        outputProgress: Progress,
                        inView view: NSView,
                        at p: NSPoint,
                        delegate: CommandInfoViewControllerDelegate?) {
        present(mark: offscreenCommandLine.mark,
                date: offscreenCommandLine.date,
                directory: directory,
                outputSize: outputSize,
                outputPromise: outputPromise,
                outputProgress: outputProgress,
                inView: view,
                at: p,
                delegate: delegate)
    }

    @objc(presentMark:date:directory:outputSize:outputPromise:outputProgress:inView:at:delegate:)
    static func present(mark: VT100ScreenMarkReading,
                        date: Date?,
                        directory: String?,
                        outputSize: Int,
                        outputPromise: iTermRenegablePromise<NSString>,
                        outputProgress: Progress,
                        inView view: NSView,
                        at p: NSPoint,
                        delegate: CommandInfoViewControllerDelegate?) {
        let mark = mark
        let runningTime: TimeInterval?
        let codePromise: iTermPromise<NSNumber>
        if let endDate = mark.endDate, let startDate = mark.startDate {
            runningTime = endDate.timeIntervalSince(startDate)
            codePromise = iTermPromise(value: NSNumber(value: Int(mark.code)))
        } else if let startDate = mark.startDate {
            runningTime = -startDate.timeIntervalSinceNow
            codePromise = mark.returnCodePromise;
        } else {
            runningTime = nil
            codePromise = mark.returnCodePromise
        }

        let viewController = CommandInfoViewController(
            mark: mark,
            command: mark.command,
            directory: directory,
            returnCode: codePromise,
            runningTime: runningTime,
            size: outputSize,
            outputPromise: outputPromise,
            outputProgress: outputProgress,
            startDate: date)
        viewController.delegate = delegate
        viewController.loadView()
        viewController.sizeToFit()
        let popover = NSPopover()
        viewController.enclosingPopover = popover
        popover.contentViewController = viewController
        popover.behavior = .transient
        popover.show(relativeTo: NSRect(origin: p, size: NSSize(width: 1.0, height: 1.0)),
                     of: view,
                     preferredEdge: .minY)
    }

    init(mark: VT100ScreenMarkReading,
         command: String,
         directory: String?,
         returnCode: iTermPromise<NSNumber>,
         runningTime: TimeInterval?,
         size: Int,
         outputPromise: iTermRenegablePromise<NSString>,
         outputProgress: Progress,
         startDate: Date?) {
        _mark = mark
        _command = command
        _directory = directory
        _returnCode = returnCode
        _runningTime = runningTime
        _size = size
        _outputPromise = outputPromise
        _outputProgress = outputProgress
        _startDate = startDate

        super.init(nibName: NSNib.Name("CommandInfoViewController"),
                   bundle: Bundle(for: CommandInfoViewController.self))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        _outputPromise.renege()
        timer?.invalidate()
    }

    private func timerDidFire() {
        updateRunningTime()
        if _returnCode.hasValue {
            timer?.invalidate()
            timer = nil
            return
        }
        if let runtimeConstraint {
            runtimeConstraint.constant = max(runtimeConstraint.constant,
                                             runningTime.intrinsicContentSize.width)
        } else {
            runtimeConstraint = NSLayoutConstraint(item: runningTime!,
                                                   attribute: .width,
                                                   relatedBy: .greaterThanOrEqual,
                                                   toItem: nil,
                                                   attribute: .notAnAttribute,
                                                   multiplier: 1,
                                                   constant: runningTime.intrinsicContentSize.width)
            runningTime.addConstraint(runtimeConstraint!)
        }
    }

    private func commandDidFinish(returnCode code: Int) {
        returnCode.stringValue = String(code)
        if code != 0 {
            returnCode.textColor = .red
            returnCode.stringValue += " 🛑"
        } else {
            returnCode.stringValue += " ✅"
        }
    }

    private func updateRunningTime() {
        guard let _startDate else {
            return
        }
        if let endDate = _mark.endDate, let startDate = _mark.startDate {
            runningTime.stringValue = endDate.timeIntervalSince(startDate).formattedHMS
        } else {
            runningTime.stringValue = (-_startDate.timeIntervalSinceNow).formattedHMS
        }
    }

    override func awakeFromNib() {
        proxyIcon.url = _directory.map { URL(fileURLWithPath: $0) }
        command.stringValue = _command
        directory.stringValue = _directory ?? ""
        sendDirectory.isEnabled = (_directory != nil)
        copyDirectory.isEnabled = (_directory != nil)
        if let codeNumber = _returnCode.maybeValue {
            commandDidFinish(returnCode: codeNumber.intValue)
        } else {
            returnCode.stringValue = "Still Running"
            if _startDate != nil {
                timer = Timer.scheduledTimer(withTimeInterval: 0.017, repeats: true) { [weak self] timer in
                    self?.timerDidFire()
                }
            }
            _returnCode.then { [weak self] number in
                self?.commandDidFinish(returnCode: number.intValue)
            }
        }
        if let _runningTime {
            runningTime.stringValue = String(_runningTime.formattedHMS)
        } else {
            runningTime.stringValue = "Unknown"
        }
        output.stringValue = NSString.stringWithHumanReadableSize(UInt64(_size)) as String
        copyOutput.isEnabled = false
        progressIndicator.isHidden = false
        _outputProgress.addObserver(owner: self, queue: .main) { [weak self] progress in
            self?.updateOutputProgress(progress)
        }
        _outputPromise.then { [weak self] _ in
            DispatchQueue.main.async {
                self?.outputDidBecomeAvailable()
            }
        }
        if let _startDate {
            startedAt.stringValue = "Started at " + formattedDate(_startDate)
        } else {
            startedAtStackView.isHidden = true
            stackView.removeArrangedSubview(startedAtStackView)
            startedAtStackView.removeFromSuperview()
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "h:mm:ss 'on' MMM d, yyyy"
        return dateFormatter.string(from: date)
    }

    private func updateOutputProgress(_ progress: Double) {
        progressIndicator.doubleValue = progress
        if progress >= 1.0 {
            progressIndicator.isHidden = true
        }
    }

    private func outputDidBecomeAvailable() {
        _outputProgress.removeObservers(for: self)
        copyOutput.isEnabled = true
        progressIndicator.isHidden = true
    }

    func sizeToFit() {
        _ = self.view
        var rect = view.frame
        rect.size = view.fittingSize
        view.frame = rect
    }

    private var largestWidth: CGFloat {
        let controls: [NSTextField] = [command, directory, returnCode, runningTime]
        let xs = controls.map {
            $0.bounds.size.width
        }
        return xs.max()!
    }

    @IBAction func disableOffscrenCommandLine(_ sender: Any) {
        enclosingPopover?.close()
        delegate?.commandInfoDisable()
    }
    @IBAction func selectOutput(_ sender: Any) {
        delegate?.commandInfoSelectOutput(_mark)
    }

    @IBAction func sendCommand(_ sender: Any) {
        send(_command)
    }

    @IBAction func copyCommand(_ sender: Any) {
        copyString(command.stringValue)
        if let view = sender as? NSView {
            showCopiedToast(view)
        }
    }

    @IBAction func sendDirectory(_ sender: Any) {
        if let _directory {
            send(_directory)
        }
    }

    @IBAction func copyDirectory(_ sender: Any) {
        copyString(directory.stringValue)
        if let view = sender as? NSView {
            showCopiedToast(view)
        }
    }

    @IBAction func copyOutput(_ sender: Any) {
        _outputPromise.wait().whenFirst { string in
            self.copyString(string as String)
            if let view = sender as? NSView {
                showCopiedToast(view)
            }
        }
    }

    private func showCopiedToast(_ view: NSView) {
        var frame = copiedView.frame
        let viewFrame = copiedView.superview!.convert(view.bounds, from: view)
        frame.origin.x = NSMidX(viewFrame) - frame.width / 2.0
        frame.origin.y = NSMinY(viewFrame) - frame.height - 2.0
        copiedView.frame = frame
        copiedView.alphaValue = 0.8
        copiedView.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            NSView.animate(withDuration: 0.25) {
                self.copiedView.animator().alphaValue = 0.0
            } completion: { _ in
                self.copiedView.alphaValue = 1.0
                self.copiedView.isHidden = true
            }
        }
    }

    @IBAction func openInComposer(_ sender: Any) {
        var lines = [String]()
        if let _directory {
            lines.append("cd " + (_directory as NSString).withEscapedShellCharacters(includingNewlines: true))
        }
        lines.append(_command)
        delegate?.commandInfoOpenInCompose(lines.joined(separator: "\n"))
        enclosingPopover?.close()
    }

    private func copyString(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func send(_ string: String) {
        delegate?.commandInfoSend(string)
    }
}

extension TimeInterval {
    var formattedHMS: String {
        let intfloor = Int(floor(self))
        let hours = Int(floor(self / 3600))
        let minutes = (intfloor % 3600) / 60
        let seconds = intfloor % 60
        let millis = Int(floor((self - floor(self)) * 1000))
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d.%03d", minutes, seconds, millis)
        }
    }
}

@objc(iTermDraggableImageView)
class DraggableImageView: NSImageView {
    @objc var url: URL? {
        didSet {
            if let url {
                let workspace = NSWorkspace.shared
                image = workspace.icon(forFile: url.path)
            } else {
                image = nil
            }
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func awakeFromNib() {
        registerForDraggedTypes([.fileURL])
    }

    private enum DragState {
        case ground
        case pending(NSPoint)
        case dragging
    }
    private var draggingState = DragState.ground

    override func mouseDown(with event: NSEvent) {
        draggingState = .ground
        guard url != nil else {
            return
        }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setDataProvider(self, forTypes: [NSPasteboard.PasteboardType.fileURL])

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: image)

        let draggingSession = beginDraggingSession(with: [draggingItem],
                                                   event: event,
                                                   source: self)
        draggingSession.draggingFormation = .none
    }


    override func mouseUp(with event: NSEvent) {
        draggingState = .ground
        if event.clickCount == 2, let url {
            NSWorkspace.shared.open(url)
        }
    }

    private func haveDraggedFarEnough(_ event: NSEvent) -> Bool {
        switch draggingState {
        case .ground, .dragging:
            return false
        case .pending(let draggingStart):
            let windowPoint = event.locationInWindow
            let point = convert(windowPoint, from: nil)
            let distance = draggingStart.distance(point)
            return distance > 2
        }
    }

    override func mouseDragged(with event: NSEvent) {
        switch draggingState {
        case .ground:
            if url != nil {
                draggingState = .pending(event.locationInWindow)
            }
            return
        case .pending:
            if haveDraggedFarEnough(event) {
                startDrag(event)
            } else {
                return
            }
        case .dragging:
            return
        }
    }

    private func startDrag(_ event: NSEvent) {
        guard url != nil else {
            draggingState = .ground
            return
        }
        draggingState = .dragging

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setDataProvider(self, forTypes: [NSPasteboard.PasteboardType.fileURL])

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: image)

        let draggingSession = beginDraggingSession(with: [draggingItem],
                                                   event: event,
                                                   source: self)
        draggingSession.draggingFormation = .none
    }
}

extension DraggableImageView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .link
    }
}

extension DraggableImageView: NSPasteboardItemDataProvider {
    func pasteboard(_ pasteboard: NSPasteboard?,
                    item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        if type == NSPasteboard.PasteboardType.fileURL, let url {
            pasteboard?.setData(url.dataRepresentation, forType: .fileURL)
        }
    }
}

@objc
class CommandInfoView: NSView {
}

@objc
class CopiedView: NSView {
    required init?(coder: NSCoder) {
        super.init(coder: coder)

        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        layer?.borderColor = NSColor.textColor.cgColor
        layer?.borderWidth = 1.0
        layer?.cornerRadius = 4.0
    }
}
