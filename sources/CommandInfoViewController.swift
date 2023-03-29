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

    weak var delegate: CommandInfoViewControllerDelegate?

    private let _command: String
    private let _directory: String?
    private let _returnCode: Int?
    private let _runningTime: TimeInterval
    private let _size: Int
    private let _outputPromise: iTermRenegablePromise<NSString>
    private let _outputProgress: Progress

    @objc(presentOffscreenCommandLine:directory:outputSize:outputPromise:outputProgress:inView:at:delegate:)
    static func present(offscreenCommandLine: iTermOffscreenCommandLine,
                        directory: String?,
                        outputSize: Int,
                        outputPromise: iTermRenegablePromise<NSString>,
                        outputProgress: Progress,
                        inView view: NSView,
                        at p: NSPoint,
                        delegate: CommandInfoViewControllerDelegate?) {
        let mark = offscreenCommandLine.mark
        let runningTime: TimeInterval
        let code: Int?
        if let endDate = mark.endDate {
            runningTime = endDate.timeIntervalSince(mark.startDate)
            code = Int(mark.code)
        } else {
            runningTime = -mark.startDate.timeIntervalSinceNow
            code = nil
        }

        let viewController = CommandInfoViewController(
            command: offscreenCommandLine.mark.command,
            directory: directory,
            returnCode: code,
            runningTime: runningTime,
            size: outputSize,
            outputPromise: outputPromise,
            outputProgress: outputProgress)
        viewController.delegate = delegate
        viewController.loadView()
        viewController.sizeToFit()
        let popover = NSPopover()
        popover.contentViewController = viewController
        popover.behavior = .transient
        popover.show(relativeTo: NSRect(origin: p, size: NSSize(width: 1.0, height: 1.0)),
                     of: view,
                     preferredEdge: .minY)
    }

    init(command: String,
         directory: String?,
         returnCode: Int?,
         runningTime: TimeInterval,
         size: Int,
         outputPromise: iTermRenegablePromise<NSString>,
         outputProgress: Progress) {
        _command = command
        _directory = directory
        _returnCode = returnCode
        _runningTime = runningTime
        _size = size
        _outputPromise = outputPromise
        _outputProgress = outputProgress

        super.init(nibName: NSNib.Name("CommandInfoViewController"),
                   bundle: Bundle(for: CommandInfoViewController.self))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        _outputPromise.renege()
    }

    override func awakeFromNib() {
        proxyIcon.url = _directory.map { URL(fileURLWithPath: $0) }
        command.stringValue = _command
        directory.stringValue = _directory ?? ""
        sendDirectory.isEnabled = (_directory != nil)
        copyDirectory.isEnabled = (_directory != nil)
        returnCode.stringValue = _returnCode.map { String($0) } ?? ""
        runningTime.stringValue = _runningTime.formattedHMS
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

    @IBAction func sendCommand(_ sender: Any) {
        send(_command)
    }

    @IBAction func copyCommand(_ sender: Any) {
        copyString(command.stringValue)
    }

    @IBAction func sendDirectory(_ sender: Any) {
        if let _directory {
            send(_directory)
        }
    }

    @IBAction func copyDirectory(_ sender: Any) {
        copyString(directory.stringValue)
    }

    @IBAction func copyOutput(_ sender: Any) {
        _outputPromise.wait().whenFirst { string in
            self.copyString(string as String)
        }
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
