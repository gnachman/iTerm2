//
//  Affordance.swift
//  BetterFontPicker
//
//  Created by George Nachman on 4/8/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

import Foundation

@objc(BFPAffordanceDelegate)
public protocol AffordanceDelegate: class {
    func affordance(_ affordance: Affordance, didSelectFontFamily fontFamily: String)
}

@objc(BFPAffordance)
public class Affordance : NSPopUpButton, MainViewControllerDelegate {
    @objc public weak var delegate: AffordanceDelegate?
    @objc public var familyName: String? {
        get {
            return vc.fontFamilyName
        }
        set {
            vc.fontFamilyName = newValue
            title = newValue ?? ""
        }
    }
    public weak var memberPicker: FontFamilyMemberPickerView? = nil {
        didSet {
            guard let memberPicker = memberPicker else {
                return
            }
            memberPicker.familyName = vc.fontFamilyName
        }
    }

    public override var title: String {
        didSet {
            memberPicker?.familyName = title
        }
    }

    let vc = MainViewController()
    private var internalPanel: FontPickerPanel?
    private var panel: FontPickerPanel {
        get {
            if let internalPanel = internalPanel {
                return internalPanel
            }
            let newPanel = FontPickerPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                           styleMask: [.resizable, .fullSizeContentView],
                                           backing: .buffered,
                                           defer: true)
            newPanel.hidesOnDeactivate = false
            newPanel.orderOut(nil)
            newPanel.contentView?.addSubview(vc.view)
            internalPanel = newPanel
            return newPanel
        }
    }

    private func postInit() {
        vc.delegate = self
        title = "Select Font"
    }

    override public init(frame buttonFrame: NSRect, pullsDown flag: Bool) {
        super.init(frame: buttonFrame, pullsDown: false)
        addItem(withTitle: "")
        postInit()
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        postInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        postInit()
    }

    init() {
        super.init(frame: NSRect.zero)
        postInit()
    }

    deinit {
        if let internalPanel = internalPanel {
            internalPanel.close()
        }
    }
    
    override public func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.cancelTrackingWithoutAnimation()
        showPicker()
    }

    private func showPicker() {
        let insets = vc.insets
        let initialSize = CGSize(width: bounds.width + insets.left + insets.right,
                                 height: 340)
        let myFrameInWindowCoords = convert(bounds, to: nil)
        let myFrameInScreenCoords = window!.convertToScreen(myFrameInWindowCoords)
        vc.view.frame = panel.contentView!.bounds
        window?.addChildWindow(panel, ordered: .above)
        let panelFrame = NSRect(origin: CGPoint(x: myFrameInScreenCoords.minX - insets.left,
                                                y: myFrameInScreenCoords.maxY - initialSize.height + insets.top),
                                size: initialSize)
        panel.setFrame(panelFrame, display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    public func mainViewController(_ mainViewController: MainViewController,
                                   didSelectFontWithName name: String) {
        title = name
        delegate?.affordance(self, didSelectFontFamily: name)
    }

}
