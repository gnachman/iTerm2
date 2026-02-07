//
//  iTermBrowserIndicatorsView.swift
//  iTerm2
//
//  Created by George Nachman on 8/5/25.
//

import Cocoa

@MainActor
@objc(iTermBrowserIndicatorsView)
class iTermBrowserIndicatorsView: NSView {
    private var scrollView: NSScrollView!
    private var containerView: NSView!
    private var indicatorButtons: [String: NSButton] = [:]
    private var indicatorsHelper: iTermIndicatorsHelper?
    private var sessionGuid: String?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupScrollView()
        setupTransparentBackground()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupScrollView()
        setupTransparentBackground()
    }

    private func setupTransparentBackground() {
        wantsLayer = true
        if let layer = layer {
            layer.backgroundColor = NSColor.clear.cgColor
        }
    }

    private func setupScrollView() {
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        addSubview(scrollView)

        containerView = NSView()
        containerView.wantsLayer = true
        if let layer = containerView.layer {
            layer.backgroundColor = NSColor.clear.cgColor
        }
        scrollView.documentView = containerView
    }
    
    override func layout() {
        super.layout()
        
        // Position scroll view to fill the entire frame
        scrollView.frame = bounds
        
        layoutIndicators()
    }
    
    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        layout()
    }
    
    func configure(indicatorsHelper: iTermIndicatorsHelper, sessionGuid: String) {
        self.indicatorsHelper = indicatorsHelper
        self.sessionGuid = sessionGuid
        updateIndicators()
    }
    
    func updateIndicators() {
        guard let indicatorsHelper = indicatorsHelper else { return }
        
        // Get visible top-right indicators
        struct Indicator {
            var identifier: String
            var image: NSImage
        }
        var visibleIndicators: [Indicator] = []
        let dummyFrame = NSRect(x: 0, y: 0, width: 1000, height: 100)

        indicatorsHelper.enumerateTopRightIndicators(inFrame: dummyFrame, andDraw: false) { identifier, image, _, _ in
            if let identifier, let image {
                let indicator = Indicator(identifier: identifier, image: image)
                visibleIndicators.append(indicator)
            }
        }
        
        // Remove buttons for indicators that are no longer visible
        let visibleIdentifiers = Set(visibleIndicators.map { $0.identifier })
        for (identifier, button) in indicatorButtons {
            if !visibleIdentifiers.contains(identifier) {
                button.removeFromSuperview()
                indicatorButtons.removeValue(forKey: identifier)
            }
        }
        
        // Create or update buttons for visible indicators
        for indicator in visibleIndicators {
            if let existingButton = indicatorButtons[indicator.identifier] {
                existingButton.image = indicator.image
            } else {
                let button = NSButton()
                button.image = indicator.image
                button.isBordered = false
                button.title = ""
                button.target = self
                button.action = #selector(indicatorButtonClicked(_:))
                button.identifier = .init(rawValue: indicator.identifier)
                button.toolTip = indicator.identifier
                button.imageScaling = .scaleProportionallyUpOrDown

                containerView.addSubview(button)
                indicatorButtons[indicator.identifier] = button
            }
        }
        
        layoutIndicators()
    }
    
    private func layoutIndicators() {
        let buttonSpacing: CGFloat = 4
        
        // Get the order of indicators as they appear in the helper
        let orderedIdentifiers = iTermIndicatorsHelper.sequentialIndicatorIdentifiers()!
        
        // Calculate total width needed for all indicators
        var totalIndicatorsWidth: CGFloat = 0
        var buttonCount = 0
        for identifier in orderedIdentifiers {
            guard let button = indicatorButtons[identifier] else { continue }
            let buttonSize = button.image?.size ?? NSSize(width: 20, height: 20)
            totalIndicatorsWidth += buttonSize.width
            buttonCount += 1
        }
        
        // Add spacing between buttons (buttonCount - 1 spaces)
        if buttonCount > 1 {
            totalIndicatorsWidth += CGFloat(buttonCount - 1) * buttonSpacing
        }
        
        // Always position indicators starting from the appropriate edge within container
        let containerWidth = max(bounds.width, totalIndicatorsWidth)
        let startX = containerWidth - totalIndicatorsWidth  // Right-align within container
        var currentX = startX
        
        for identifier in orderedIdentifiers {
            guard let button = indicatorButtons[identifier] else { continue }
            
            let buttonSize = button.image?.size ?? NSSize(width: 20, height: 20)
            // Use a consistent button size that's sized for the image
            let buttonFrame = NSSize(width: buttonSize.width, height: bounds.height)
            
            // Round coordinates to avoid blurriness
            let roundedX = round(currentX)
            let roundedY = 0
            
            button.frame = NSRect(x: roundedX, y: CGFloat(roundedY), width: buttonFrame.width, height: buttonFrame.height)
            currentX += buttonFrame.width + buttonSpacing
        }
        
        // Update container view size for horizontal scrolling
        containerView.frame = NSRect(x: 0, y: 0, width: containerWidth, height: bounds.height)
    }
    
    @objc private func indicatorButtonClicked(_ sender: NSButton) {
        guard let indicatorsHelper = indicatorsHelper,
              let sessionGuid = sessionGuid else { return }
        
        // Find the identifier for this button
        let clickedIdentifier = indicatorButtons.keys.first(where: { $0 == sender.identifier?.rawValue })
        guard let identifier = clickedIdentifier else { return }
        
        // Get help text for this indicator
        if let helpText = indicatorsHelper.helpTextForIndicator(withName: identifier, sessionID: sessionGuid) {
            sender.it_showInformativeMessage(withMarkdown: helpText)
        }
    }
}
