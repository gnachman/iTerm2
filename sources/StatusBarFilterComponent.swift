//
//  StatusBarFilterComponent.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/31/21.
//

import Foundation

@objc(iTermStatusBarFilterComponent)
class StatusBarFilterComponent: iTermStatusBarBaseComponent, iTermFilterViewController {
    @objc(isTemporaryKey) static let isTemporaryKey = "filter: temporary"

    private lazy var viewController: MiniFilterViewController & iTermFilterViewController = {
        viewController = MiniFilterViewController()
        viewController.delegate = self
        let config: [iTermStatusBarComponentConfigurationKey : Any] = configuration
        let knobValues: [AnyHashable: Any] = (config[iTermStatusBarComponentConfigurationKey.knobValues] as? [AnyHashable: Any]) ?? [:]
        let isTemporary = (knobValues[Self.isTemporaryKey] as? NSNumber) ?? NSNumber(false)
        let canClose = isTemporary.boolValue
        viewController.canClose = canClose
        if let font = advancedConfiguration.font {
            viewController.setFont(font)
        }
        return viewController
    }()

    @IBAction @objc(closeButton:) func closeButton(_ sender: Any) {
        delegate?.statusBarRemoveTemporaryComponent(self)
    }
    override func statusBarComponentMinimumWidth() -> CGFloat {
        return 125
    }

    override func statusBarComponentSizeView(_ view: NSView, toFitWidth width: CGFloat) {
        viewController.sizeToFit(size: NSSize(width: width, height: view.frame.height))
    }

    override func statusBarComponentPreferredWidth() -> CGFloat {
        return 200
    }

    override func statusBarComponentCanStretch() -> Bool {
        return true
    }

    override func statusBarComponentShortDescription() -> String {
        return "Filter Tool"
    }

    override func statusBarComponentDetailedDescription() -> String {
        return "Filter tool to remove non-matching lines from terminal window."
    }

    override func statusBarComponentKnobs() -> [iTermStatusBarComponentKnob] {
        return []
    }

    override func statusBarComponentExemplar(withBackgroundColor backgroundColor: NSColor, textColor: NSColor) -> Any {
        return "⥹ Filter"
    }

    override func statusBarComponentView() -> NSView {
        updateForTerminalBackgroundColor()
        return viewController.view
    }

    override func statusBarTerminalBackgroundColorDidChange() {
        updateForTerminalBackgroundColor()
    }

    private func updateForTerminalBackgroundColor() {
        let view = viewController.view
        let tabStyle = iTermPreferencesTabStyle(rawValue: iTermPreferences.int(forKey: kPreferenceKeyTabStyle))
        if tabStyle == .TAB_STYLE_MINIMAL {
            if delegate?.statusBarComponentTerminalBackgroundColorIsDark(self) ?? false {
                view.appearance = NSAppearance(named: .darkAqua)
            } else {
                view.appearance = NSAppearance(named: .aqua)
            }
        } else {
            view.appearance = nil
        }
    }

    override func statusBarComponentFilterViewController() -> (NSViewController & iTermFilterViewController)? {
        return viewController
    }

    @objc func focus() {
        viewController.focus()
    }

    func setFilterProgress(_ progress: Double) {
        viewController.setFilterProgress(progress)
    }
}


extension StatusBarFilterComponent: MiniFilterViewControllerDelegate {
    func closeFilterComponent() {
        delegate?.statusBarSetFilter(nil)
        delegate?.statusBarRemoveTemporaryComponent(self)
    }

    func searchQueryDidChange(_ query: String, editor: NSTextView?) {
        let range = editor?.selectedRange()
        delegate?.statusBarSetFilter(query)
        viewController.searchField.window?.makeFirstResponder(viewController.searchField)
        if let range = range {
            editor?.setSelectedRange(range)
        }
    }
}
