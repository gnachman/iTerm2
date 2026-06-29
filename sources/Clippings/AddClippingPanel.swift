//
//  AddClippingPanel.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/27/26.
//

import AppKit
import Foundation

@objc(iTermAddClippingPanel)
class AddClippingPanel: NSObject {
    private var window: NSPanel?
    private let titleField = NSTextField()
    private let detailScrollView = NSScrollView()
    private let detailTextView = AddClippingDetailTextView()
    private var completion: ((PTYSessionClipping?) -> Void)?

    @objc(presentOverWindow:completion:)
    func present(over parentWindow: NSWindow,
                 completion: @escaping (PTYSessionClipping?) -> Void) {
        self.completion = completion

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 290),
                            styleMask: [.titled],
                            backing: .buffered,
                            defer: true)
        panel.title = "New Clipping"
        panel.isFloatingPanel = false
        let content = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        content.autoresizingMask = [.width, .height]
        panel.contentView = content
        buildContent(in: content)
        self.window = panel

        parentWindow.beginSheet(panel) { [weak self] response in
            guard let self else { return }
            let cb = self.completion
            self.completion = nil
            self.window = nil
            if response == .OK {
                let clipping = PTYSessionClipping(
                    type: "",
                    title: self.titleField.stringValue,
                    detail: self.detailTextView.string)
                cb?(clipping)
            } else {
                cb?(nil)
            }
        }

        panel.makeFirstResponder(titleField)
    }

    private func buildContent(in container: NSView) {
        let pad: CGFloat = 16
        let labelW: CGFloat = 60
        let fieldX = pad + labelW + 8
        let fieldW = container.bounds.width - fieldX - pad
        let rowH: CGFloat = 22

        let buttonH: CGFloat = 32
        let buttonY: CGFloat = pad
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.sizeToFit()
        let cancelW = max(80, cancel.frame.width)
        cancel.frame = NSRect(x: container.bounds.width - pad - cancelW * 2 - 8,
                              y: buttonY,
                              width: cancelW,
                              height: buttonH)
        cancel.autoresizingMask = [.minXMargin, .maxYMargin]
        container.addSubview(cancel)

        let add = NSButton(title: "Add", target: self, action: #selector(addClicked))
        add.bezelStyle = .rounded
        add.keyEquivalent = "\r"
        add.sizeToFit()
        let addW = max(80, add.frame.width)
        add.frame = NSRect(x: container.bounds.width - pad - addW,
                           y: buttonY,
                           width: addW,
                           height: buttonH)
        add.autoresizingMask = [.minXMargin, .maxYMargin]
        container.addSubview(add)

        let topAreaY = buttonY + buttonH + pad

        let rowGap: CGFloat = 8
        let titleRowY = container.bounds.height - pad - rowH
        let detailLabelY = titleRowY - rowH - rowGap
        let detailFieldTopY = detailLabelY + rowH - 2
        let detailFieldHeight = max(60, detailFieldTopY - topAreaY)
        let detailFieldY = detailFieldTopY - detailFieldHeight

        let titleLabel = makeLabel("Title:", x: pad, y: titleRowY, width: labelW)
        titleLabel.autoresizingMask = [.minYMargin]
        container.addSubview(titleLabel)
        titleField.frame = NSRect(x: fieldX, y: titleRowY, width: fieldW, height: rowH)
        titleField.autoresizingMask = [.width, .minYMargin]
        titleField.bezelStyle = .squareBezel
        container.addSubview(titleField)

        let detailLabel = makeLabel("Detail:", x: pad, y: detailLabelY, width: labelW)
        detailLabel.autoresizingMask = [.minYMargin]
        container.addSubview(detailLabel)

        detailScrollView.frame = NSRect(x: fieldX, y: detailFieldY, width: fieldW, height: detailFieldHeight)
        detailScrollView.autoresizingMask = [.width, .height, .minYMargin]
        detailScrollView.borderType = .bezelBorder
        detailScrollView.hasVerticalScroller = true
        detailScrollView.drawsBackground = true

        detailTextView.frame = NSRect(x: 0, y: 0, width: fieldW, height: detailFieldHeight)
        detailTextView.minSize = NSSize(width: 0, height: detailFieldHeight)
        detailTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        detailTextView.isVerticallyResizable = true
        detailTextView.isHorizontallyResizable = false
        detailTextView.autoresizingMask = [.width]
        detailTextView.textContainer?.containerSize = NSSize(width: fieldW, height: CGFloat.greatestFiniteMagnitude)
        detailTextView.textContainer?.widthTracksTextView = true
        detailTextView.font = .systemFont(ofSize: 12)
        detailTextView.isAutomaticQuoteSubstitutionEnabled = false
        detailTextView.onShiftReturn = { [weak self] in
            self?.addClicked()
        }
        detailScrollView.documentView = detailTextView
        container.addSubview(detailScrollView)
    }

    private func makeLabel(_ string: String, x: CGFloat, y: CGFloat, width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.alignment = .right
        label.frame = NSRect(x: x, y: y + 2, width: width, height: 18)
        return label
    }

    @objc private func cancelClicked() {
        guard let window else { return }
        window.sheetParent?.endSheet(window, returnCode: .cancel)
    }

    @objc private func addClicked() {
        guard let window else { return }
        window.sheetParent?.endSheet(window, returnCode: .OK)
    }
}

private class AddClippingDetailTextView: NSTextView {
    var onShiftReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.shift),
           event.charactersIgnoringModifiers == "\r",
           let onShiftReturn {
            onShiftReturn()
            return
        }
        super.keyDown(with: event)
    }
}
