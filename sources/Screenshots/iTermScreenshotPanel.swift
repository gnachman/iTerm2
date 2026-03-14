//
//  iTermScreenshotPanel.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/5/26.
//

import AppKit
import ColorPicker

@objc(iTermBlurredScreenshotObscureMethod)
class iTermBlurredScreenshotObscureMethod: NSObject {
    enum Kind {
        case blur(radius: CGFloat)
        case solidColor(NSColor)
    }

    let kind: Kind

    init(kind: Kind) {
        self.kind = kind
    }

    @objc static func blur(radius: CGFloat) -> iTermBlurredScreenshotObscureMethod {
        return iTermBlurredScreenshotObscureMethod(kind: .blur(radius: radius))
    }

    @objc static func solidColor(_ color: NSColor) -> iTermBlurredScreenshotObscureMethod {
        return iTermBlurredScreenshotObscureMethod(kind: .solidColor(color))
    }

    @objc var isBlur: Bool {
        if case .blur = kind {
            return true
        }
        return false
    }

    @objc var blurRadius: CGFloat {
        if case .blur(let radius) = kind {
            return radius
        }
        return 0
    }

    @objc var solidColorValue: NSColor? {
        if case .solidColor(let color) = kind {
            return color
        }
        return nil
    }
}

/// Represents a selection region in a session that should be obscured
@objc(iTermBlurredScreenshotSelectionRegion)
class iTermBlurredScreenshotSelectionRegion: NSObject {
    /// Rectangles in window coordinates (origin at bottom-left, in points)
    @objc let windowRects: [NSValue]

    @objc init(windowRects: [NSValue]) {
        self.windowRects = windowRects
    }
}

/// Information about terminal lines for the line range selector
@objc(iTermScreenshotTerminalInfo)
class iTermScreenshotTerminalInfo: NSObject {
    @objc let totalLines: Int
    @objc let visibleLines: Int
    @objc let firstVisibleLine: Int
    @objc let lineHeight: CGFloat
    @objc let terminalHeight: CGFloat  // Height of terminal content area in window
    @objc weak var textView: PTYTextView?  // Reference to text view for rendering

    @objc init(totalLines: Int, visibleLines: Int, firstVisibleLine: Int, lineHeight: CGFloat, terminalHeight: CGFloat, textView: PTYTextView?) {
        self.totalLines = totalLines
        self.visibleLines = visibleLines
        self.firstVisibleLine = firstVisibleLine
        self.lineHeight = lineHeight
        self.terminalHeight = terminalHeight
        self.textView = textView
    }
}

@objc(iTermScreenshotPanel)
class iTermScreenshotPanel: NSPanel {
    /// Track active panels by session for cleanup when session view loses window
    private static var activePanels = NSMapTable<PTYSession, iTermScreenshotPanel>.weakToWeakObjects()

    private var keepalive: iTermScreenshotPanel?
    private weak var session: PTYSession?
    private weak var screenshotTab: PTYTab?
    private var completion: ((URL?) -> Void)?
    private var terminalInfo: iTermScreenshotTerminalInfo?
    // Track the text view that currently has a selection (may differ from session.textview after app switch)
    private weak var currentTextViewWithSelection: PTYTextView?

    // Redaction management
    private let redactionManager = iTermScreenshotRedactionManager()

    // Obscure method controls
    private var segmentedControl: NSSegmentedControl!
    private var blurRadiusSlider: NSSlider!
    private var blurRadiusValueLabel: NSTextField!
    private var colorWell: CPKColorWell!
    private var blurControlsContainer: NSView!
    private var colorControlsContainer: NSView!

    // Preview
    private var onDemandPreview: iTermScreenshotOnDemandPreview!
    private var previewScrollView: NSScrollView!
    private var previewOverlay: iTermScreenshotPreviewOverlay!
    private var blurProgressIndicator: NSProgressIndicator!
    private var currentRenderToken: Any?
    private var previewUpdateGeneration: UInt64 = 0

    // Encoding progress UI
    private var encodingProgressContainer: NSView!
    private var encodingProgressBar: NSProgressIndicator!
    private var encodingProgressLabel: NSTextField!
    private var encodingCancelButton: NSButton!

    // Streaming encoder for large screenshots
    private var streamingEncoder: iTermStreamingScreenshotEncoder?

    // Multi-part save state
    private var multiPartSaveState: MultiPartSaveState?

    private struct MultiPartSaveState {
        let timestamp: String
        let desktopURL: URL
        let totalParts: Int
        let maxLinesPerPart: Int
        let fullLineRange: NSRange
        let method: iTermBlurredScreenshotObscureMethod
        var currentPart: Int = 0
        var savedURLs: [URL] = []
    }

    // Size limits for single-file output (also determines when streaming encoder is needed)
    // These are derived from the advanced setting screenshotMaxPixelHeight
    private var maxPixelHeight: Int {
        return Int(iTermAdvancedSettingsModel.screenshotMaxPixelHeight())
    }
    private var maxTotalPixels: Int {
        let maxHeight = Int(iTermAdvancedSettingsModel.screenshotMaxPixelHeight())
        return maxHeight * maxHeight / 5  // e.g., 30000^2/5 = 180M
    }

    // Line range controls
    private var lineRangeView: iTermScreenshotLineRangeView!
    private var startLineField: NSTextField!
    private var endLineField: NSTextField!
    private var startLineStepper: NSStepper!
    private var endLineStepper: NSStepper!

    // Annotations UI
    private var annotationsTableView: NSTableView!
    private var annotationsScrollView: NSScrollView!
    private var addRedactionButton: NSButton!
    private var addHighlightButton: NSButton!
    private var annotationActionsControl: NSSegmentedControl!  // "-" and "Clear All"
    private var emptyStateLabel: NSTextField!

    // Large screenshot warning and copy button
    private var largeScreenshotWarningLabel: NSTextField!
    private var copyButton: NSButton!

    // Cached values for consistent multi-part calculation
    private var cachedNumberOfParts: Int = 1
    private var cachedMaxLinesPerPart: Int = Int.max

    private let previewSize = NSSize(width: 400, height: 300)
    private let minimapWidth: CGFloat = 60
    private let redactionsListHeight: CGFloat = 100

    // Track the last rendered line range for viewport preservation
    private var lastRenderedLineRange: NSRange?

    /// Shows a floating screenshot panel for the given session
    @objc static func show(forSession session: PTYSession,
                           terminalInfo: iTermScreenshotTerminalInfo,
                           tab: PTYTab,
                           completion: @escaping (URL?) -> Void) {
        let panel = iTermScreenshotPanel(session: session, terminalInfo: terminalInfo, tab: tab)
        panel.completion = completion
        panel.keepalive = panel
        activePanels.setObject(panel, forKey: session)
        panel.showAsFloatingPanel()
    }

    /// Closes the screenshot panel for a session (if any). Called when session view loses its window.
    @objc static func closePanel(forSession session: PTYSession) {
        if let panel = activePanels.object(forKey: session) {
            panel.close()
        }
    }

    init(session: PTYSession, terminalInfo: iTermScreenshotTerminalInfo, tab: PTYTab) {
        self.session = session
        self.terminalInfo = terminalInfo
        self.screenshotTab = tab
        self.currentTextViewWithSelection = session.textview
        super.init(contentRect: .zero,
                   styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                   backing: .buffered,
                   defer: true)
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = true
        self.hidesOnDeactivate = true  // Hide when iTerm2 is not active
        self.title = "Make Screenshot"
        self.isReleasedWhenClosed = false
        self.delegate = self
        setupUI()
        setupLineRangeView()
        setupRedactionManager()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView else { return }

        // Visual effect background
        let vev = NSVisualEffectView()
        vev.wantsLayer = true
        vev.blendingMode = .withinWindow
        vev.material = .hudWindow
        vev.state = .active
        vev.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(vev)

        // Line range minimap
        lineRangeView = iTermScreenshotLineRangeView()
        lineRangeView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(lineRangeView)

        // Preview scroll view with magnification support
        previewScrollView = NSScrollView()
        previewScrollView.translatesAutoresizingMaskIntoConstraints = false
        previewScrollView.hasVerticalScroller = true
        previewScrollView.hasHorizontalScroller = true
        previewScrollView.autohidesScrollers = true
        previewScrollView.allowsMagnification = true
        previewScrollView.minMagnification = 0.25
        previewScrollView.maxMagnification = 4.0
        previewScrollView.magnification = 1.0
        previewScrollView.wantsLayer = true
        previewScrollView.layer?.borderWidth = 1
        previewScrollView.layer?.borderColor = NSColor.separatorColor.cgColor
        previewScrollView.layer?.cornerRadius = 4
        previewScrollView.contentView.postsBoundsChangedNotifications = false
        contentView.addSubview(previewScrollView)

        // On-demand preview view (renders only visible tiles)
        onDemandPreview = iTermScreenshotOnDemandPreview()
        onDemandPreview.translatesAutoresizingMaskIntoConstraints = false
        previewScrollView.documentView = onDemandPreview

        // Preview overlay for selection interaction
        previewOverlay = iTermScreenshotPreviewOverlay()
        previewOverlay.translatesAutoresizingMaskIntoConstraints = false
        onDemandPreview.addSubview(previewOverlay)
        previewOverlay.onSelectionChanged = { [weak self] in
            self?.selectionChangedInPreview()
        }

        // Progress indicator for async blur (centered over preview)
        blurProgressIndicator = NSProgressIndicator()
        blurProgressIndicator.style = .spinning
        blurProgressIndicator.controlSize = .regular
        blurProgressIndicator.translatesAutoresizingMaskIntoConstraints = false
        blurProgressIndicator.isHidden = true
        contentView.addSubview(blurProgressIndicator)

        // Encoding progress container (centered over preview, shown during save/copy)
        encodingProgressContainer = NSVisualEffectView()
        encodingProgressContainer.translatesAutoresizingMaskIntoConstraints = false
        (encodingProgressContainer as! NSVisualEffectView).material = .hudWindow
        (encodingProgressContainer as! NSVisualEffectView).blendingMode = .withinWindow
        (encodingProgressContainer as! NSVisualEffectView).state = .active
        encodingProgressContainer.wantsLayer = true
        encodingProgressContainer.layer?.cornerRadius = 8
        encodingProgressContainer.isHidden = true
        contentView.addSubview(encodingProgressContainer)

        encodingProgressLabel = NSTextField(labelWithString: "Encoding…")
        encodingProgressLabel.translatesAutoresizingMaskIntoConstraints = false
        encodingProgressLabel.font = NSFont.systemFont(ofSize: 12)
        encodingProgressLabel.textColor = .labelColor
        encodingProgressLabel.alignment = .center
        encodingProgressContainer.addSubview(encodingProgressLabel)

        encodingProgressBar = NSProgressIndicator()
        encodingProgressBar.style = .bar
        encodingProgressBar.isIndeterminate = false
        encodingProgressBar.minValue = 0
        encodingProgressBar.maxValue = 100
        encodingProgressBar.doubleValue = 0
        encodingProgressBar.translatesAutoresizingMaskIntoConstraints = false
        encodingProgressContainer.addSubview(encodingProgressBar)

        encodingCancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelEncodingClicked(_:)))
        encodingCancelButton.bezelStyle = .rounded
        encodingCancelButton.controlSize = .small
        encodingCancelButton.translatesAutoresizingMaskIntoConstraints = false
        encodingProgressContainer.addSubview(encodingCancelButton)

        // Line range numerical controls
        let lineRangeLabel = NSTextField(labelWithString: "Line range:")
        lineRangeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(lineRangeLabel)

        startLineField = NSTextField()
        startLineField.translatesAutoresizingMaskIntoConstraints = false
        startLineField.alignment = .right
        startLineField.formatter = createLineNumberFormatter()
        startLineField.delegate = self
        contentView.addSubview(startLineField)

        startLineStepper = NSStepper()
        startLineStepper.translatesAutoresizingMaskIntoConstraints = false
        startLineStepper.minValue = 1
        startLineStepper.maxValue = 1
        startLineStepper.increment = 1
        startLineStepper.valueWraps = false
        startLineStepper.target = self
        startLineStepper.action = #selector(startLineStepperChanged(_:))
        contentView.addSubview(startLineStepper)

        let toLabel = NSTextField(labelWithString: "to")
        toLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(toLabel)

        endLineField = NSTextField()
        endLineField.translatesAutoresizingMaskIntoConstraints = false
        endLineField.alignment = .right
        endLineField.formatter = createLineNumberFormatter()
        endLineField.delegate = self
        contentView.addSubview(endLineField)

        endLineStepper = NSStepper()
        endLineStepper.translatesAutoresizingMaskIntoConstraints = false
        endLineStepper.minValue = 1
        endLineStepper.maxValue = 1
        endLineStepper.increment = 1
        endLineStepper.valueWraps = false
        endLineStepper.target = self
        endLineStepper.action = #selector(endLineStepperChanged(_:))
        contentView.addSubview(endLineStepper)

        // Annotations section
        let annotationsLabel = NSTextField(labelWithString: "Annotations:")
        annotationsLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(annotationsLabel)

        let instructionLabel = NSTextField(labelWithString: "Select text in the terminal, then click a button below.")
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.font = NSFont.systemFont(ofSize: 11)
        instructionLabel.textColor = .secondaryLabelColor
        contentView.addSubview(instructionLabel)

        addRedactionButton = NSButton(title: "Redact Selection", target: self, action: #selector(addRedactionClicked(_:)))
        addRedactionButton.translatesAutoresizingMaskIntoConstraints = false
        addRedactionButton.bezelStyle = .rounded
        addRedactionButton.isEnabled = false
        contentView.addSubview(addRedactionButton)

        addHighlightButton = NSButton(title: "Highlight Selection", target: self, action: #selector(addHighlightClicked(_:)))
        addHighlightButton.translatesAutoresizingMaskIntoConstraints = false
        addHighlightButton.bezelStyle = .rounded
        addHighlightButton.isEnabled = false
        contentView.addSubview(addHighlightButton)

        // Segmented control with "-" (remove selected) and "Clear All"
        annotationActionsControl = NSSegmentedControl(labels: ["−", "Clear All"],
                                                       trackingMode: .momentary,
                                                       target: self,
                                                       action: #selector(annotationActionClicked(_:)))
        annotationActionsControl.translatesAutoresizingMaskIntoConstraints = false
        annotationActionsControl.setEnabled(false, forSegment: 0)  // "-" disabled until selection
        annotationActionsControl.setEnabled(false, forSegment: 1)  // "Clear All" disabled until annotations exist
        contentView.addSubview(annotationActionsControl)

        // Annotations table view
        annotationsScrollView = NSScrollView()
        annotationsScrollView.translatesAutoresizingMaskIntoConstraints = false
        annotationsScrollView.hasVerticalScroller = true
        annotationsScrollView.autohidesScrollers = true
        annotationsScrollView.borderType = .bezelBorder
        contentView.addSubview(annotationsScrollView)

        annotationsTableView = NSTableView()
        annotationsTableView.translatesAutoresizingMaskIntoConstraints = false
        annotationsTableView.delegate = self
        annotationsTableView.dataSource = self
        annotationsTableView.headerView = nil
        annotationsTableView.rowHeight = 24
        annotationsTableView.usesAlternatingRowBackgroundColors = true

        let labelColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("label"))
        labelColumn.title = "Label"
        labelColumn.minWidth = 200
        annotationsTableView.addTableColumn(labelColumn)

        annotationsScrollView.documentView = annotationsTableView

        // Empty state label
        emptyStateLabel = NSTextField(labelWithString: "No annotations. Select text and click a button above.")
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.font = NSFont.systemFont(ofSize: 11)
        emptyStateLabel.textColor = .tertiaryLabelColor
        emptyStateLabel.alignment = .center
        contentView.addSubview(emptyStateLabel)

        // Method selection
        let methodLabel = NSTextField(labelWithString: "Redaction method:")
        methodLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(methodLabel)

        segmentedControl = NSSegmentedControl(labels: ["Blur", "Solid Color"],
                                               trackingMode: .selectOne,
                                               target: self,
                                               action: #selector(segmentChanged(_:)))
        segmentedControl.selectedSegment = 0
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(segmentedControl)

        // Blur controls container
        blurControlsContainer = NSView()
        blurControlsContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(blurControlsContainer)

        let blurLabel = NSTextField(labelWithString: "Blur radius:")
        blurLabel.translatesAutoresizingMaskIntoConstraints = false
        blurControlsContainer.addSubview(blurLabel)

        blurRadiusSlider = NSSlider(value: 8, minValue: 1, maxValue: 200, target: self, action: #selector(sliderChanged(_:)))
        blurRadiusSlider.isContinuous = true
        blurRadiusSlider.translatesAutoresizingMaskIntoConstraints = false
        blurControlsContainer.addSubview(blurRadiusSlider)

        blurRadiusValueLabel = NSTextField(labelWithString: "15")
        blurRadiusValueLabel.alignment = .right
        blurRadiusValueLabel.translatesAutoresizingMaskIntoConstraints = false
        blurControlsContainer.addSubview(blurRadiusValueLabel)

        // Color controls container
        colorControlsContainer = NSView()
        colorControlsContainer.translatesAutoresizingMaskIntoConstraints = false
        colorControlsContainer.isHidden = true
        contentView.addSubview(colorControlsContainer)

        let colorLabel = NSTextField(labelWithString: "Fill color:")
        colorLabel.translatesAutoresizingMaskIntoConstraints = false
        colorControlsContainer.addSubview(colorLabel)

        colorWell = CPKColorWell(frame: NSRect(x: 0, y: 0, width: 44, height: 24), colorSpace: .deviceRGB)
        colorWell.color = NSColor.black.usingColorSpace(.deviceRGB) ?? .black
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        colorWell.isContinuous = true
        // Make panel activating while color picker popover is open so clicks outside dismiss it
        colorWell.willOpenPopover = { [weak self] in
            self?.styleMask.remove(.nonactivatingPanel)
            self?.makeKey()
        }
        colorWell.willClosePopover = { [weak self] in
            self?.styleMask.insert(.nonactivatingPanel)
        }
        colorControlsContainer.addSubview(colorWell)

        // Buttons
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked(_:)))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cancelButton)

        copyButton = NSButton(title: "Copy to Clipboard", target: self, action: #selector(copyClicked(_:)))
        copyButton.bezelStyle = .rounded
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(copyButton)

        // Large screenshot warning label (shown when multi-file output needed)
        largeScreenshotWarningLabel = NSTextField(labelWithString: "")
        largeScreenshotWarningLabel.translatesAutoresizingMaskIntoConstraints = false
        largeScreenshotWarningLabel.font = NSFont.systemFont(ofSize: 11)
        largeScreenshotWarningLabel.textColor = .secondaryLabelColor
        largeScreenshotWarningLabel.isHidden = true
        contentView.addSubview(largeScreenshotWarningLabel)

        let saveButton = NSButton(title: "Save to Desktop", target: self, action: #selector(saveClicked(_:)))
        saveButton.keyEquivalent = "\r" // Return
        saveButton.bezelStyle = .rounded
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(saveButton)

        // Layout
        let margin: CGFloat = 20
        let innerSpacing: CGFloat = 12
        let controlHeight: CGFloat = 24
        let fieldWidth: CGFloat = 60

        NSLayoutConstraint.activate([
            // Visual effect view fills content
            vev.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            vev.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            vev.topAnchor.constraint(equalTo: contentView.topAnchor),
            vev.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            // Line range minimap (left side of preview)
            lineRangeView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: margin),
            lineRangeView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: margin),
            lineRangeView.widthAnchor.constraint(equalToConstant: minimapWidth),
            lineRangeView.heightAnchor.constraint(equalToConstant: previewSize.height),

            // Preview scroll view (right of minimap)
            previewScrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: margin),
            previewScrollView.leadingAnchor.constraint(equalTo: lineRangeView.trailingAnchor, constant: innerSpacing),
            previewScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -margin),
            previewScrollView.heightAnchor.constraint(equalToConstant: previewSize.height),

            // Progress indicator (centered over preview)
            blurProgressIndicator.centerXAnchor.constraint(equalTo: previewScrollView.centerXAnchor),
            blurProgressIndicator.centerYAnchor.constraint(equalTo: previewScrollView.centerYAnchor),

            // Encoding progress container (centered over preview)
            encodingProgressContainer.centerXAnchor.constraint(equalTo: previewScrollView.centerXAnchor),
            encodingProgressContainer.centerYAnchor.constraint(equalTo: previewScrollView.centerYAnchor),
            encodingProgressContainer.widthAnchor.constraint(equalToConstant: 280),
            encodingProgressContainer.heightAnchor.constraint(equalToConstant: 90),

            encodingProgressLabel.topAnchor.constraint(equalTo: encodingProgressContainer.topAnchor, constant: 12),
            encodingProgressLabel.leadingAnchor.constraint(equalTo: encodingProgressContainer.leadingAnchor, constant: 16),
            encodingProgressLabel.trailingAnchor.constraint(equalTo: encodingProgressContainer.trailingAnchor, constant: -16),

            encodingProgressBar.topAnchor.constraint(equalTo: encodingProgressLabel.bottomAnchor, constant: 8),
            encodingProgressBar.leadingAnchor.constraint(equalTo: encodingProgressContainer.leadingAnchor, constant: 16),
            encodingProgressBar.trailingAnchor.constraint(equalTo: encodingProgressContainer.trailingAnchor, constant: -16),

            encodingCancelButton.topAnchor.constraint(equalTo: encodingProgressBar.bottomAnchor, constant: 10),
            encodingCancelButton.centerXAnchor.constraint(equalTo: encodingProgressContainer.centerXAnchor),

            // Large screenshot warning (below preview, full width)
            largeScreenshotWarningLabel.topAnchor.constraint(equalTo: previewScrollView.bottomAnchor, constant: 6),
            largeScreenshotWarningLabel.leadingAnchor.constraint(equalTo: lineRangeView.leadingAnchor),
            largeScreenshotWarningLabel.trailingAnchor.constraint(equalTo: previewScrollView.trailingAnchor),

            // Line range numerical controls
            lineRangeLabel.topAnchor.constraint(equalTo: largeScreenshotWarningLabel.bottomAnchor, constant: 6),
            lineRangeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: margin),

            startLineField.centerYAnchor.constraint(equalTo: lineRangeLabel.centerYAnchor),
            startLineField.leadingAnchor.constraint(equalTo: lineRangeLabel.trailingAnchor, constant: 8),
            startLineField.widthAnchor.constraint(equalToConstant: fieldWidth),

            startLineStepper.centerYAnchor.constraint(equalTo: lineRangeLabel.centerYAnchor),
            startLineStepper.leadingAnchor.constraint(equalTo: startLineField.trailingAnchor, constant: 2),

            toLabel.centerYAnchor.constraint(equalTo: lineRangeLabel.centerYAnchor),
            toLabel.leadingAnchor.constraint(equalTo: startLineStepper.trailingAnchor, constant: 8),

            endLineField.centerYAnchor.constraint(equalTo: lineRangeLabel.centerYAnchor),
            endLineField.leadingAnchor.constraint(equalTo: toLabel.trailingAnchor, constant: 8),
            endLineField.widthAnchor.constraint(equalToConstant: fieldWidth),

            endLineStepper.centerYAnchor.constraint(equalTo: lineRangeLabel.centerYAnchor),
            endLineStepper.leadingAnchor.constraint(equalTo: endLineField.trailingAnchor, constant: 2),

            // Annotations section (more spacing from line range)
            annotationsLabel.topAnchor.constraint(equalTo: lineRangeLabel.bottomAnchor, constant: innerSpacing * 1.5),
            annotationsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: margin),

            instructionLabel.topAnchor.constraint(equalTo: annotationsLabel.bottomAnchor, constant: 4),
            instructionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: margin),

            addRedactionButton.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 8),
            addRedactionButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: margin),

            addHighlightButton.centerYAnchor.constraint(equalTo: addRedactionButton.centerYAnchor),
            addHighlightButton.leadingAnchor.constraint(equalTo: addRedactionButton.trailingAnchor, constant: 8),

            annotationActionsControl.centerYAnchor.constraint(equalTo: addRedactionButton.centerYAnchor),
            annotationActionsControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -margin),

            // Annotations table/scroll view (more spacing from buttons)
            annotationsScrollView.topAnchor.constraint(equalTo: addRedactionButton.bottomAnchor, constant: innerSpacing),
            annotationsScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: margin),
            annotationsScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -margin),
            annotationsScrollView.heightAnchor.constraint(equalToConstant: redactionsListHeight),

            // Empty state label (centered in scroll view area)
            emptyStateLabel.centerXAnchor.constraint(equalTo: annotationsScrollView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: annotationsScrollView.centerYAnchor),

            // Method label and segmented control
            methodLabel.topAnchor.constraint(equalTo: annotationsScrollView.bottomAnchor, constant: innerSpacing),
            methodLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: margin),

            segmentedControl.centerYAnchor.constraint(equalTo: methodLabel.centerYAnchor),
            segmentedControl.leadingAnchor.constraint(equalTo: methodLabel.trailingAnchor, constant: 8),

            // Blur controls container
            blurControlsContainer.topAnchor.constraint(equalTo: methodLabel.bottomAnchor, constant: innerSpacing),
            blurControlsContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: margin),
            blurControlsContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -margin),
            blurControlsContainer.heightAnchor.constraint(equalToConstant: controlHeight),

            blurLabel.leadingAnchor.constraint(equalTo: blurControlsContainer.leadingAnchor),
            blurLabel.centerYAnchor.constraint(equalTo: blurControlsContainer.centerYAnchor),
            blurLabel.widthAnchor.constraint(equalToConstant: 80),

            blurRadiusSlider.leadingAnchor.constraint(equalTo: blurLabel.trailingAnchor, constant: 8),
            blurRadiusSlider.centerYAnchor.constraint(equalTo: blurControlsContainer.centerYAnchor),

            blurRadiusValueLabel.leadingAnchor.constraint(equalTo: blurRadiusSlider.trailingAnchor, constant: 8),
            blurRadiusValueLabel.trailingAnchor.constraint(equalTo: blurControlsContainer.trailingAnchor),
            blurRadiusValueLabel.centerYAnchor.constraint(equalTo: blurControlsContainer.centerYAnchor),
            blurRadiusValueLabel.widthAnchor.constraint(equalToConstant: 40),

            // Color controls container (same position as blur controls)
            colorControlsContainer.topAnchor.constraint(equalTo: methodLabel.bottomAnchor, constant: innerSpacing),
            colorControlsContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: margin),
            colorControlsContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -margin),
            colorControlsContainer.heightAnchor.constraint(equalToConstant: controlHeight),

            colorLabel.leadingAnchor.constraint(equalTo: colorControlsContainer.leadingAnchor),
            colorLabel.centerYAnchor.constraint(equalTo: colorControlsContainer.centerYAnchor),
            colorLabel.widthAnchor.constraint(equalToConstant: 80),

            colorWell.leadingAnchor.constraint(equalTo: colorLabel.trailingAnchor, constant: 8),
            colorWell.centerYAnchor.constraint(equalTo: colorControlsContainer.centerYAnchor),
            colorWell.widthAnchor.constraint(equalToConstant: 44),
            colorWell.heightAnchor.constraint(equalToConstant: controlHeight),

            // Buttons
            saveButton.topAnchor.constraint(equalTo: blurControlsContainer.bottomAnchor, constant: innerSpacing * 1.5),
            saveButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -margin),
            saveButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -margin),

            copyButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),

            cancelButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -8),

            // Window width (wider to accommodate minimap and annotation buttons)
            contentView.widthAnchor.constraint(equalToConstant: previewSize.width + minimapWidth + innerSpacing + margin * 2 + 100),
        ])
    }

    private func setupLineRangeView() {
        guard let info = terminalInfo else { return }

        lineRangeView.totalLines = info.totalLines
        lineRangeView.visibleLines = info.visibleLines
        lineRangeView.firstVisibleLine = info.firstVisibleLine
        lineRangeView.selectVisibleRange()

        // Render minimap image from the text view
        if let textView = info.textView {
            // Calculate minimap height based on content rect (same as the view's drawing area)
            let minimapHeight = previewSize.height - 4  // Account for insets
            lineRangeView.minimapImage = textView.renderMinimap(withWidth: minimapWidth - 4, height: minimapHeight)
        }

        // Update numerical controls
        startLineStepper.maxValue = Double(info.totalLines)
        endLineStepper.maxValue = Double(info.totalLines)
        updateLineRangeFields()

        // Set up callbacks
        // This is called during dragging - only update lightweight UI elements
        lineRangeView.onRangeChanged = { [weak self] start, end in
            self?.updateLineRangeFields()
        }

        // This is called when dragging ends - do the expensive preview update
        lineRangeView.onRangeChangeEnded = { [weak self] start, end in
            self?.updatePreviewPreservingViewport()
        }
    }

    private func setupRedactionManager() {
        redactionManager.onRedactionsChanged = { [weak self] in
            self?.redactionsDidChange()
        }
        updateAnnotationsUI()

        // Observe selection changes from the text view
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionDidChange),
            name: NSNotification.Name("PTYTextViewSelectionDidChangeNotification"),
            object: nil
        )
    }

    @objc private func selectionDidChange(_ notification: Notification) {
        // Check selection on whichever text view sent the notification
        guard let textView = notification.object as? PTYTextView else {
            return
        }
        let hasSelection = textView.selection?.hasSelection ?? false
        if hasSelection {
            currentTextViewWithSelection = textView
        } else if textView === currentTextViewWithSelection {
            currentTextViewWithSelection = nil
        }
        updateAddButtonState()

        // Update the preview overlay to show the current selection
        previewOverlay.updateSelectionFromTextView()

        // Update the minimap to show selection
        updateMinimapSelection()
    }

    private func selectionChangedInPreview() {
        // Selection was changed by dragging in the preview - update UI
        updateAddButtonState()
        previewOverlay.updateSelectionFromTextView()
        updateMinimapSelection()
    }

    private func updateMinimapSelection() {
        guard let textView = terminalInfo?.textView,
              let selection = textView.selection,
              selection.hasSelection else {
            lineRangeView.selectedLines = []
            return
        }

        // Get scrollback overflow to convert absolute coords to buffer-relative
        let overflow = Int(textView.dataSource?.totalScrollbackOverflow() ?? 0)

        // Get the lines that have selection (convert to buffer-relative coordinates)
        var selectedLines = Set<Int>()
        for sub in selection.allSubSelections {
            // Convert absolute line numbers to buffer-relative
            let startLine = Int(sub.absRange.coordRange.start.y) - overflow
            let endLine = Int(sub.absRange.coordRange.end.y) - overflow
            guard startLine <= endLine else { continue }
            for line in startLine...endLine {
                if line >= 0 {
                    selectedLines.insert(line)
                }
            }
        }
        lineRangeView.selectedLines = selectedLines
    }

    private func updateAddButtonState() {
        let hasSelection = currentTextViewWithSelection?.selection?.hasSelection ?? false
        addRedactionButton.isEnabled = hasSelection
        addHighlightButton.isEnabled = hasSelection
    }

    private func redactionsDidChange() {
        annotationsTableView.reloadData()
        updateAnnotationsUI()
        updatePreviewPreservingViewport()
    }

    private func updateAnnotationsUI() {
        let hasAnnotations = redactionManager.count > 0
        emptyStateLabel.isHidden = hasAnnotations
        // "-" segment enabled only when a row is selected
        let hasSelection = annotationsTableView.selectedRow >= 0
        annotationActionsControl.setEnabled(hasSelection, forSegment: 0)
        // "Clear All" enabled when there are annotations
        annotationActionsControl.setEnabled(hasAnnotations, forSegment: 1)
        updateAddButtonState()
    }

    private func showAsFloatingPanel() {
        // Position panel near the terminal window
        if let sessionWindow = session?.delegate?.realParentWindow()?.window,
           let screen = sessionWindow.screen {
            let sessionFrame = sessionWindow.frame
            let screenFrame = screen.visibleFrame

            // Get actual panel size after layout
            layoutIfNeeded()
            let panelSize = frame.size

            // Vertically center the panel relative to the terminal window
            let panelY = sessionFrame.midY - (panelSize.height / 2)

            // Try to position to the right of the terminal window
            var panelX = sessionFrame.maxX + 20

            // Check if it fits on the right
            let fitsOnRight = panelX + panelSize.width <= screenFrame.maxX

            if !fitsOnRight {
                // Try to position to the left of the terminal window
                let leftX = sessionFrame.minX - panelSize.width - 20
                let fitsOnLeft = leftX >= screenFrame.minX

                if fitsOnLeft {
                    panelX = leftX
                } else {
                    // Neither side has room - overlap the terminal window
                    // Position at the right edge of the screen
                    panelX = screenFrame.maxX - panelSize.width
                }
            }

            setFrameOrigin(NSPoint(x: panelX, y: panelY))
        }

        makeKeyAndOrderFront(nil)
        updatePreview()
        updateLargeScreenshotUI()
    }

    private func createLineNumberFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.allowsFloats = false
        return formatter
    }

    private func updateLineRangeFields() {
        // Display as 1-based for users
        startLineField.integerValue = lineRangeView.rangeStart + 1
        endLineField.integerValue = lineRangeView.rangeEnd + 1
        startLineStepper.integerValue = lineRangeView.rangeStart + 1
        endLineStepper.integerValue = lineRangeView.rangeEnd + 1

        // Update large screenshot warning and copy button state
        updateLargeScreenshotUI()
    }

    /// Calculate maximum lines per part based on pixel limits
    private func maxLinesPerPart() -> Int {
        guard let info = terminalInfo, let textView = info.textView else {
            return Int.max
        }

        let scale = textView.window?.backingScaleFactor ?? 2.0
        let lineHeight = info.lineHeight
        let pixelWidth = textView.frame.size.width * scale
        let pixelLineHeight = lineHeight * scale

        // Limit by max height (configurable via advanced setting)
        let linesByHeight = Int(CGFloat(maxPixelHeight) / pixelLineHeight)

        // Limit by max total pixels (derived from max height)
        let linesByTotal = Int(CGFloat(maxTotalPixels) / (pixelWidth * pixelLineHeight))

        return max(1, min(linesByHeight, linesByTotal))
    }

    /// Calculate number of parts needed for current line range
    private func numberOfParts(maxLinesPerPart: Int? = nil) -> Int {
        let lineRange = currentLineRange()
        let maxLines = maxLinesPerPart ?? self.maxLinesPerPart()
        return (lineRange.length + maxLines - 1) / maxLines  // Ceiling division
    }

    /// Update warning label and copy button based on current line range
    private func updateLargeScreenshotUI() {
        // Cache the calculation for consistent behavior between UI and save
        cachedMaxLinesPerPart = maxLinesPerPart()
        cachedNumberOfParts = numberOfParts(maxLinesPerPart: cachedMaxLinesPerPart)

        let lineRange = currentLineRange()
        NSLog("updateLargeScreenshotUI: lineRange=\(lineRange), maxLinesPerPart=\(cachedMaxLinesPerPart), numberOfParts=\(cachedNumberOfParts)")

        if cachedNumberOfParts > 1 {
            largeScreenshotWarningLabel.stringValue = "⚠️ Large screenshot will be saved as \(cachedNumberOfParts) files."
            largeScreenshotWarningLabel.isHidden = false
            copyButton.isEnabled = false
        } else {
            largeScreenshotWarningLabel.stringValue = ""
            largeScreenshotWarningLabel.isHidden = true
            copyButton.isEnabled = true
        }
    }

    private func applyLineFieldValues() {
        lineRangeView.rangeStart = max(0, startLineField.integerValue - 1)
        lineRangeView.rangeEnd = max(0, endLineField.integerValue - 1)
        updatePreviewPreservingViewport()
    }

    @objc private func startLineStepperChanged(_ sender: NSStepper) {
        lineRangeView.rangeStart = max(0, sender.integerValue - 1)
        updateLineRangeFields()
        updatePreviewPreservingViewport()
    }

    @objc private func endLineStepperChanged(_ sender: NSStepper) {
        lineRangeView.rangeEnd = max(0, sender.integerValue - 1)
        updateLineRangeFields()
        updatePreviewPreservingViewport()
    }

    @objc private func addRedactionClicked(_ sender: Any) {
        addAnnotation(ofType: .redaction)
    }

    @objc private func addHighlightClicked(_ sender: Any) {
        addAnnotation(ofType: .highlight)
    }

    private func addAnnotation(ofType annotationType: iTermScreenshotAnnotationType) {
        guard let textView = currentTextViewWithSelection,
              let selection = textView.selection,
              selection.hasSelection else {
            return
        }

        let typePrefix = annotationType == .redaction ? "Redact" : "Highlight"
        let baseLabel = iTermScreenshotRedactionManager.labelForSelection(selection, textView: textView)
        let label = "\(typePrefix): \(baseLabel)"
        _ = redactionManager.addAnnotation(from: selection, annotationType: annotationType, label: label)

        // Clear the selection after adding
        selection.clear()
    }

    @objc private func annotationActionClicked(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0:  // "-" remove selected
            let selectedRow = annotationsTableView.selectedRow
            if selectedRow >= 0 {
                redactionManager.removeAnnotation(at: selectedRow)
            }
        case 1:  // "Clear All"
            redactionManager.clearAll()
        default:
            break
        }
    }

    private func currentSelectionRegions(for lineRange: NSRange) -> [iTermBlurredScreenshotSelectionRegion] {
        guard let textView = terminalInfo?.textView else { return [] }

        // Get window rects from all stored redactions for the given line range
        let allRects = redactionManager.allWindowRects(for: textView, lineRange: lineRange)
        if allRects.isEmpty {
            return []
        }
        return [iTermBlurredScreenshotSelectionRegion(windowRects: allRects)]
    }

    private func updatePreview() {
        updatePreview(preserveViewport: false)
    }

    private func updatePreviewPreservingViewport() {
        updatePreview(preserveViewport: true)
    }

    private func updatePreview(preserveViewport: Bool) {
        guard let info = terminalInfo, let textView = info.textView else {
            return
        }

        // Cancel any existing batched render
        if let token = currentRenderToken {
            textView.cancelBatchedRender(token)
            currentRenderToken = nil
        }

        // Increment generation to invalidate any in-flight async operations
        previewUpdateGeneration &+= 1

        let method = currentMethod()
        let lineRange = currentLineRange()

        // Capture current viewport state before updating
        var viewportCenterLine: CGFloat?
        var currentMagnification: CGFloat?
        var horizontalFraction: CGFloat?

        if preserveViewport, let oldRange = lastRenderedLineRange {
            let clipView = previewScrollView.contentView
            let visibleRect = clipView.documentVisibleRect
            currentMagnification = previewScrollView.magnification

            // In flipped coordinates (on-demand preview uses flipped), Y=0 is at top
            let centerY = visibleRect.midY
            let centerX = visibleRect.midX
            let lineHeight = info.lineHeight

            // Calculate which line is at the center of the viewport
            let lineInImage = centerY / lineHeight
            viewportCenterLine = CGFloat(oldRange.location) + lineInImage

            // Calculate horizontal position as fraction
            let contentWidth = textView.frame.size.width
            if contentWidth > 0 {
                horizontalFraction = centerX / contentWidth
            }
        }

        // Update the on-demand preview's properties
        onDemandPreview.textView = textView
        onDemandPreview.lineRange = lineRange
        onDemandPreview.redactionManager = redactionManager
        onDemandPreview.redactionMethod = method
        onDemandPreview.invalidateTileCache()

        // Calculate content size
        let lineHeight = info.lineHeight
        let contentWidth = textView.frame.size.width
        let contentHeight = CGFloat(lineRange.length) * lineHeight

        // Update frame to match content size
        onDemandPreview.frame = NSRect(origin: .zero, size: NSSize(width: contentWidth, height: contentHeight))

        // Update the overlay to match
        previewOverlay.frame = onDemandPreview.bounds
        previewOverlay.textView = textView
        previewOverlay.lineRange = lineRange
        previewOverlay.charWidth = textView.charWidth
        previewOverlay.lineHeight = lineHeight
        previewOverlay.updateSelectionFromTextView()

        // Store the current line range for next update
        lastRenderedLineRange = lineRange

        if preserveViewport,
           let centerLine = viewportCenterLine,
           let magnification = currentMagnification {
            // Restore viewport position
            restoreViewport(centerLine: centerLine,
                           horizontalFraction: horizontalFraction ?? 0.5,
                           magnification: magnification,
                           newLineRange: lineRange,
                           contentSize: NSSize(width: contentWidth, height: contentHeight))
        } else {
            zoomToFitContent(NSSize(width: contentWidth, height: contentHeight))
        }

        // Force display update
        onDemandPreview.needsDisplay = true
    }

    private func restoreViewport(centerLine: CGFloat,
                                  horizontalFraction: CGFloat,
                                  magnification: CGFloat,
                                  newLineRange: NSRange,
                                  contentSize: NSSize) {
        guard let info = terminalInfo else { return }

        // Keep the same magnification
        previewScrollView.magnification = magnification

        // Force layout so documentVisibleRect reflects the new magnification
        previewScrollView.layoutSubtreeIfNeeded()

        // Calculate where the center line falls in the new content
        let lineHeight = info.lineHeight
        let lineInNewContent = centerLine - CGFloat(newLineRange.location)

        // Clamp to valid range
        let clampedLineInContent = max(0, min(lineInNewContent, CGFloat(newLineRange.length)))

        // In flipped coordinates, Y=0 is at top, so line N is at Y = N * lineHeight
        let targetCenterY = clampedLineInContent * lineHeight

        // Calculate target center X from horizontal fraction
        let targetCenterX = horizontalFraction * contentSize.width

        // Get the visible rect size in document coordinates
        let clipView = previewScrollView.contentView
        let documentVisibleSize = clipView.documentVisibleRect.size

        // Calculate scroll origin to center on target point
        var scrollOrigin = NSPoint(
            x: targetCenterX - documentVisibleSize.width / 2,
            y: targetCenterY - documentVisibleSize.height / 2
        )

        // Clamp to valid scroll bounds
        let maxScrollX = max(0, contentSize.width - documentVisibleSize.width)
        let maxScrollY = max(0, contentSize.height - documentVisibleSize.height)
        scrollOrigin.x = max(0, min(scrollOrigin.x, maxScrollX))
        scrollOrigin.y = max(0, min(scrollOrigin.y, maxScrollY))

        clipView.scroll(to: scrollOrigin)
        previewScrollView.reflectScrolledClipView(clipView)
    }

    private func zoomToFitContent(_ contentSize: NSSize) {
        // Calculate magnification to fit the content in the preview area
        let widthRatio = previewSize.width / contentSize.width
        let heightRatio = previewSize.height / contentSize.height
        let fitMagnification = min(widthRatio, heightRatio, 1.0)

        previewScrollView.magnification = fitMagnification
    }

    private func currentMethod() -> iTermBlurredScreenshotObscureMethod {
        if segmentedControl.selectedSegment == 0 {
            return .blur(radius: CGFloat(blurRadiusSlider.doubleValue))
        } else {
            return .solidColor(colorWell.color)
        }
    }

    private func currentLineRange() -> NSRange {
        return NSRange(location: lineRangeView.rangeStart, length: lineRangeView.rangeEnd - lineRangeView.rangeStart + 1)
    }

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        let showBlur = sender.selectedSegment == 0
        blurControlsContainer.isHidden = !showBlur
        colorControlsContainer.isHidden = showBlur
        updatePreviewPreservingViewport()
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        blurRadiusValueLabel.stringValue = "\(Int(sender.doubleValue))"
        updatePreviewPreservingViewport()
    }

    @objc private func colorChanged(_ sender: Any) {
        updatePreviewPreservingViewport()
    }

    @objc private func cancelClicked(_ sender: Any) {
        finish(with: nil)
    }

    private func renderFinalImage() -> NSImage? {
        guard let info = terminalInfo, let textView = info.textView else {
            return nil
        }

        let method = currentMethod()
        let lineRange = currentLineRange()

        // Render the line range to an image (same as preview)
        guard var renderedImage = textView.renderLines(toImage: lineRange) else {
            return nil
        }

        // Apply redactions using image coordinates
        let redactionRects = redactionManager.imageRects(for: textView,
                                                          lineRange: lineRange,
                                                          annotationType: .redaction)
        if !redactionRects.isEmpty {
            if let obscuredImage = iTermAnnotatedScreenshot.applyObscuring(
                to: renderedImage,
                imageRects: redactionRects,
                method: method
            ) {
                renderedImage = obscuredImage
            }
        }

        // Apply highlights using image coordinates
        let groupedHighlightRects = redactionManager.groupedHighlightRects(for: textView, lineRange: lineRange)
        if !groupedHighlightRects.isEmpty {
            let bgColor = textView.colorMap.color(forKey: kColorMapBackground) ?? .black
            if let highlightedImage = iTermAnnotatedScreenshot.applyHighlights(
                to: renderedImage,
                groupedRects: groupedHighlightRects,
                outlineColor: .systemYellow,
                outlineWidth: 3,
                shadowRadius: 20,
                backgroundColor: bgColor
            ) {
                renderedImage = highlightedImage
            }
        }

        return renderedImage
    }

    @objc private func copyClicked(_ sender: Any) {
        let lineRange = currentLineRange()

        // Use streaming encoder when approaching pixel limits (copy is disabled for multi-part)
        let useStreaming = lineRange.length >= cachedMaxLinesPerPart
        if useStreaming {
            copyWithStreamingEncoder()
        } else {
            // Standard path for smaller screenshots
            guard let image = renderFinalImage() else {
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
        }
    }

    private func copyWithStreamingEncoder() {
        guard let info = terminalInfo, let textView = info.textView else {
            return
        }

        // Create temp file for streaming encode
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        let lineRange = currentLineRange()
        let method = currentMethod()

        // Create and start the streaming encoder
        let encoder = iTermStreamingScreenshotEncoder(
            textView: textView,
            lineRange: lineRange,
            destinationURL: tempURL,
            redactionManager: redactionManager,
            redactionMethod: method
        )

        streamingEncoder = encoder

        // Show encoding progress UI
        showEncodingProgress(title: "Copying…")

        let totalLines = lineRange.length
        encoder.onProgress = { [weak self] completed, _ in
            guard let self = self else { return }
            let percent = totalLines > 0 ? Double(completed) / Double(totalLines) * 100 : 0
            self.updateEncodingProgress(percent: percent)
        }

        encoder.onCompletion = { [weak self] url in
            guard let self = self else { return }
            self.hideEncodingProgress()
            self.streamingEncoder = nil

            // Copy to clipboard from temp file
            if let url = url {
                self.copyToClipboardFromFile(url)
                // Clean up temp file
                try? FileManager.default.removeItem(at: url)
            }
        }

        encoder.start()
    }

    private func copyToClipboardFromFile(_ url: URL) {
        guard let pngData = try? Data(contentsOf: url) else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
    }

    @objc private func saveClicked(_ sender: Any) {
        let lineRange = currentLineRange()

        // Use streaming encoder when approaching pixel limits or multi-part output is needed
        let useStreaming = lineRange.length >= cachedMaxLinesPerPart || cachedNumberOfParts > 1
        if useStreaming {
            saveWithStreamingEncoder()
        } else {
            // Standard path for smaller screenshots
            guard let image = renderFinalImage() else {
                finish(with: nil)
                return
            }
            let url = iTermAnnotatedScreenshot.saveToDesktop(nsImage: image)
            finish(with: url)
        }
    }

    private func saveWithStreamingEncoder() {
        guard let info = terminalInfo, info.textView != nil else {
            finish(with: nil)
            return
        }

        // Generate timestamp for filenames
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        guard let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
            finish(with: nil)
            return
        }

        let lineRange = currentLineRange()
        let method = currentMethod()

        // Use cached values for consistency with what the UI showed
        let totalParts = cachedNumberOfParts
        let maxLines = cachedMaxLinesPerPart

        NSLog("saveWithStreamingEncoder: lineRange=\(lineRange), totalParts=\(totalParts), maxLines=\(maxLines)")

        // Set up multi-part save state
        multiPartSaveState = MultiPartSaveState(
            timestamp: timestamp,
            desktopURL: desktopURL,
            totalParts: totalParts,
            maxLinesPerPart: maxLines,
            fullLineRange: lineRange,
            method: method
        )

        // Start saving the first part
        saveNextPart()
    }

    private func saveNextPart() {
        guard let state = multiPartSaveState,
              let info = terminalInfo,
              let textView = info.textView else {
            finish(with: nil)
            return
        }

        let partIndex = state.currentPart
        let totalParts = state.totalParts

        NSLog("saveNextPart: partIndex=\(partIndex), totalParts=\(totalParts), maxLinesPerPart=\(state.maxLinesPerPart), fullLineRange=\(state.fullLineRange)")

        // Calculate line range for this part
        let partStartLine = state.fullLineRange.location + partIndex * state.maxLinesPerPart
        let remainingLines = state.fullLineRange.location + state.fullLineRange.length - partStartLine
        let partLineCount = min(state.maxLinesPerPart, remainingLines)
        let partLineRange = NSRange(location: partStartLine, length: partLineCount)

        NSLog("saveNextPart: partStartLine=\(partStartLine), remainingLines=\(remainingLines), partLineCount=\(partLineCount), partLineRange=\(partLineRange)")

        // Generate filename
        let filename: String
        if totalParts == 1 {
            filename = "iTerm2-Screenshot-\(state.timestamp).png"
        } else {
            filename = "iTerm2-Screenshot-\(state.timestamp)-part-\(partIndex + 1)-of-\(totalParts).png"
        }
        let destinationURL = state.desktopURL.appendingPathComponent(filename)

        NSLog("saveNextPart: filename=\(filename)")

        // Create encoder for this part
        let encoder = iTermStreamingScreenshotEncoder(
            textView: textView,
            lineRange: partLineRange,
            destinationURL: destinationURL,
            redactionManager: redactionManager,
            redactionMethod: state.method
        )

        streamingEncoder = encoder

        // Show encoding progress UI with file number for multi-part
        if totalParts > 1 {
            showEncodingProgress(title: "Saving file \(partIndex + 1) of \(totalParts)")
        } else {
            showEncodingProgress(title: "Saving…")
        }

        // Calculate base progress from completed parts
        let linesPerPart = state.maxLinesPerPart
        let totalLines = state.fullLineRange.length
        let linesCompletedBefore = partIndex * linesPerPart

        encoder.onProgress = { [weak self] completedInPart, _ in
            guard let self = self else { return }
            // Calculate overall progress across all parts
            let overallCompleted = linesCompletedBefore + completedInPart
            let overallPercent = totalLines > 0 ? Double(overallCompleted) / Double(totalLines) * 100 : 0
            self.updateEncodingProgress(percent: overallPercent)
        }

        encoder.onCompletion = { [weak self] url in
            guard let self = self else { return }
            self.streamingEncoder = nil

            NSLog("saveNextPart completion: url=\(String(describing: url))")

            if let url = url {
                self.multiPartSaveState?.savedURLs.append(url)
            }

            // Move to next part
            self.multiPartSaveState?.currentPart += 1

            let newCurrentPart = self.multiPartSaveState?.currentPart ?? -1
            let totalParts = self.multiPartSaveState?.totalParts ?? -1
            NSLog("saveNextPart completion: after increment currentPart=\(newCurrentPart), totalParts=\(totalParts)")

            if let state = self.multiPartSaveState, state.currentPart < state.totalParts {
                NSLog("saveNextPart completion: saving next part")
                // Save next part
                self.saveNextPart()
            } else {
                NSLog("saveNextPart completion: all parts done, savedURLs count=\(self.multiPartSaveState?.savedURLs.count ?? 0)")
                // All parts done
                self.hideEncodingProgress()
                let firstURL = self.multiPartSaveState?.savedURLs.first
                self.multiPartSaveState = nil
                self.finish(with: firstURL)
            }
        }

        encoder.start()
    }

    @objc private func cancelEncodingClicked(_ sender: Any) {
        streamingEncoder?.cancel()
        streamingEncoder = nil
        multiPartSaveState = nil

        // Cancel any batched render for copy operation
        if let token = currentRenderToken, let textView = terminalInfo?.textView {
            textView.cancelBatchedRender(token)
            currentRenderToken = nil
        }

        hideEncodingProgress()
    }

    private func showEncodingProgress(title: String) {
        encodingProgressLabel.stringValue = title
        encodingProgressBar.doubleValue = 0
        encodingProgressContainer.isHidden = false
    }

    private func updateEncodingProgress(percent: Double) {
        encodingProgressBar.doubleValue = percent
    }

    private func hideEncodingProgress() {
        encodingProgressContainer.isHidden = true
        encodingProgressBar.doubleValue = 0
    }

    private func finish(with url: URL?) {
        // Cancel any in-progress streaming encoder
        streamingEncoder?.cancel()
        streamingEncoder = nil
        multiPartSaveState = nil

        orderOut(nil)
        NotificationCenter.default.removeObserver(self)
        completion?(url)
        completion = nil
        keepalive = nil
    }
}

// MARK: - NSTextFieldDelegate
extension iTermScreenshotPanel: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField,
              textField === startLineField || textField === endLineField else {
            return
        }
        applyLineFieldValues()
    }
}

// MARK: - NSTableViewDataSource
extension iTermScreenshotPanel: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return redactionManager.count
    }
}

// MARK: - NSTableViewDelegate
extension iTermScreenshotPanel: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let annotation = redactionManager.annotation(at: row) else {
            return nil
        }

        if tableColumn?.identifier.rawValue == "label" {
            let cellIdentifier = NSUserInterfaceItemIdentifier("LabelCell")
            var containerView = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTableCellView
            if containerView == nil {
                containerView = NSTableCellView()
                containerView?.identifier = cellIdentifier

                let textField = NSTextField(labelWithString: "")
                textField.lineBreakMode = .byTruncatingTail
                textField.translatesAutoresizingMaskIntoConstraints = false
                containerView?.addSubview(textField)
                containerView?.textField = textField

                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: containerView!.leadingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: containerView!.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: containerView!.centerYAnchor)
                ])
            }
            containerView?.textField?.stringValue = annotation.label
            return containerView
        }
        return nil
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateAnnotationsUI()
    }
}

// MARK: - NSWindowDelegate
extension iTermScreenshotPanel: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        finish(with: nil)
    }
}
