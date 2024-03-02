//
//  MiniFilterViewController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/31/21.
//

import Foundation

protocol MiniFilterViewControllerDelegate: AnyObject {
    func closeFilterComponent()
    func searchQueryDidChange(_ query: String, editor: NSTextView?)
}

@objc(iTermMiniFilterField)
class MiniFilterField: iTermMiniSearchField {
    private var iconSet = false

    @objc override func viewDidMoveToWindow() {
        if let searchFieldCell = self.cell as? NSSearchFieldCell,
           let cell = searchFieldCell.searchButtonCell, !iconSet {
            changeIcon(cell)
        }
    }

    private func changeIcon(_ cell: NSButtonCell) {
        guard #available(macOS 11, *) else {
            return
        }
        cell.setButtonType(.toggle)
        let filterImage = NSImage(systemSymbolName: "line.horizontal.3.decrease.circle",
                                  accessibilityDescription: "Filter")
        cell.image = filterImage
        cell.alternateImage = filterImage
    }
}

@objc(iTermMiniFilterViewController)
class MiniFilterViewController: NSViewController, NSTextFieldDelegate, iTermFilterViewController {
    @objc var canClose = false {
        didSet { _ = self.view }
    }
    @IBOutlet var searchField: NSSearchField!
    @IBOutlet var closeButton: NSButton!
    private var timer: Timer? = nil
    weak var delegate: MiniFilterViewControllerDelegate? = nil

    init() {
        super.init(nibName: "MiniFilterViewController", bundle: Bundle(for: Self.self))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func sizeToFit(size: NSSize) {
        let searchFieldSize = searchField.sizeThatFits(NSSize(width: size.width, height: view.frame.size.height))

        let mySize = NSSize(width: size.width, height: searchFieldSize.height)
        var rect = view.frame
        rect.size = mySize
        view.frame = rect
        updateSubviews()
    }

    @objc override func awakeFromNib() {
        updateSubviews()
    }

    private var shouldUseLargeControls: Bool {
        if #available(macOS 11, *) {
            return iTermAdvancedSettingsModel.statusBarHeight() >= 32
        }
        return false
    }

    @objc func setFont(_ font: NSFont) {
        searchField.font = font
        if #available(macOS 11, *) {
            if shouldUseLargeControls {
                searchField.controlSize = .large
                closeButton.controlSize = .large
            }
        }
        updateSubviews()
    }
    private func updateSubviews() {
        let size = view.frame.size
        var searchFieldSize = searchField.frame.size
        searchField.sizeToFit()
        searchFieldSize.height = searchField.frame.height

        let globalOffset = CGFloat(PSMShouldExtendTransparencyIntoMinimalTabBar() ? 0.5 : 0)
        // This makes the close button and text field line up vertically
        let verticalOffset =
            if shouldUseLargeControls {
                (searchFieldSize.height - closeButton.frame.height) / 2.0
            } else {
                CGFloat(1) + globalOffset
            }
        let closeWidth: CGFloat
        if canClose {
            closeButton.isHidden = false
            closeButton.frame = NSRect(x: size.width - closeButton.frame.width,
                                       y: verticalOffset,
                                       width: closeButton.frame.width,
                                       height: searchFieldSize.height)
            closeWidth = closeButton.frame.width
        } else {
            closeButton.isHidden = true
            closeWidth = 0
        }
        let rightMargin = CGFloat(3)
        let leftMargin = CGFloat(2)
        let used = leftMargin + closeWidth + rightMargin
        searchField.frame = NSRect(x: leftMargin,
                                   y: globalOffset,
                                   width: view.frame.width - used,
                                   height: searchFieldSize.height)
    }

    func setFilterProgress(_ progress: Double) {
        guard let cell = searchField.cell as? iTermSearchFieldCell else {
            return
        }
        if round(progress * 100.0) != round(Double(cell.fraction) * 100.0) {
            searchField.needsDisplay = true
        }
        cell.fraction = CGFloat(progress)
        if cell.needsAnimation && timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1 / 60.0, repeats: true, block: { [weak self] timer in
                self?.redrawSearchField()
            })
        }
    }

    @objc func focus() {
        view.window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    private func redrawSearchField() {
        guard let cell = searchField.cell as? iTermSearchFieldCell else {
            return
        }
        cell.willAnimate()
        if !cell.needsAnimation {
            timer?.invalidate()
            timer = nil
        }
        searchField.needsDisplay = true
    }

    @IBAction func closeButton(_ sender: Any) {
        delegate?.closeFilterComponent()
    }

    func controlTextDidChange(_ obj: Notification) {
        let field = obj.object as? NSTextField
        if field !== searchField {
            return
        }
        delegate?.searchQueryDidChange(searchField.stringValue,
                                       editor: obj.userInfo?["NSFieldEditor"] as? NSTextView)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control !== searchField {
            return false
        }
        if commandSelector == #selector(cancelOperation(_:)) {
            delegate?.closeFilterComponent()
            searchField.stringValue = ""
            return true
        }
        return false
    }
}
