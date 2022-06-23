//
//  ContentNavigationShortcut.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/22/22.
//

import Foundation
import QuartzCore
import AppKit

@objc(iTermContentNavigationShortcutView)
protocol ContentNavigationShortcutViewProtocol {
    var terminating: Bool { get }
    func pop(completion: @escaping () -> ())
    func dissolve(completion: @escaping () -> ())
}

@objc(iTermContentNavigationShortcut)
class ContentNavigationShortcut: NSObject {
    @objc let range: VT100GridAbsCoordRange
    @objc var action: (() -> ())!
    @objc var view: (NSView & ContentNavigationShortcutViewProtocol)?
    @objc let keyEquivalent: String

    @objc
    init(range: VT100GridAbsCoordRange,
         keyEquivalent: String,
         action: @escaping (ContentNavigationShortcutViewProtocol) -> ()) {
        self.range = range
        self.keyEquivalent = keyEquivalent
        super.init()
        self.action = { [weak self] in
            if let view = self?.view {
                action(view)
            }
        }
    }
}

class ContentNavigationShortcutView: NSView, ContentNavigationShortcutViewProtocol {
    @objc let target: NSRect
    private weak var shortcut: ContentNavigationShortcut?
    private let padding = NSSize(width: 2, height: 1)
    private let desiredSize: NSSize
    private let label: NSTextField
    // margin is per side so double for both left+right margins or top+bottom.
    let margin = NSSize(width: 12, height: 12)
    private(set) var terminating = false

    @objc
    init(shortcut: ContentNavigationShortcut,
         target: NSRect) {
        self.shortcut = shortcut
        self.target = target
        label = NSTextField(labelWithString: shortcut.keyEquivalent)
        label.textColor = NSColor.white
        label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
        label.sizeToFit()
        let desiredHeight = label.bounds.height + padding.height * 2
        // desired size excludes margins
        desiredSize = NSSize(width: max(desiredHeight, label.bounds.width + padding.width * 2),
                             height: desiredHeight)
        super.init(frame: NSRect.zero)

        let containerLayer = CALayer()
        containerLayer.masksToBounds = false
        layer = containerLayer

        sizeToFit()

        let shapeLayer = CAShapeLayer()
        let path = NSBezierPath(roundedRect: NSRect(x: margin.width,
                                                    y: margin.height,
                                                    width: desiredSize.width,
                                                    height: desiredSize.height),
                                xRadius: desiredSize.height / 2.0,
                                yRadius: desiredSize.height / 2.0)
        shapeLayer.path = path.iterm_CGPath()
        shapeLayer.masksToBounds = false

        shapeLayer.fillColor = NSColor.controlAccentColor.cgColor
        shapeLayer.strokeColor = NSColor(white: 1, alpha: 0.95).cgColor

        shapeLayer.shadowColor = NSColor.black.cgColor
        shapeLayer.shadowRadius = 2.0
        shapeLayer.shadowOpacity = 0.4
        shapeLayer.shadowOffset = CGSize.zero

        containerLayer.addSublayer(shapeLayer)

        addSubview(label)
        doLayout()
        setAnchorPoint()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool {
        return false
    }

    private func growtx(_ amount: CGFloat) -> CATransform3D {
        return CATransform3DMakeScale(amount, amount, 1.0)
        /*
        let size = bounds.size
        let txToOrigin = CATransform3DMakeTranslation(size.width * -0.5,
                                                      size.height * -0.5,
                                                      0)
        let txFromOrigin = CATransform3DMakeTranslation(size.width * 0.5,
                                                      size.height * 0.5,
                                                      0)
        let grow = CATransform3DMakeScale(amount, amount, 1.0)
        return CATransform3DConcat(txToOrigin, CATransform3DConcat(grow, txFromOrigin))
         */
    }

    @objc
    func animateIn() {
        // For whatever reason, changing the frame after calling animateIn messes up the animation
        // so just do it after a spin.
        DispatchQueue.main.async {
            self.setAnchorPoint()
            CATransaction.begin()
            let animation = CAKeyframeAnimation()
            animation.keyPath = "transform"
            let scales = [0.25, 1.3, 1.1, 1].map { self.growtx($0) }
            animation.values = scales
            animation.keyTimes = [0.0, 0.6, 0.8, 1.0]
            animation.duration = 0.1
            CATransaction.setCompletionBlock { [weak self] in
                // For some reason the anchor point gets set to 0,0 (perhaps by the animation?)
                self?.setAnchorPoint()
            }
            self.layer?.add(animation, forKey: "bouncein")
            CATransaction.commit()
        }
    }

    private let exitAnimationDuration = 0.2

    private func zoomToBigAnimation() -> CAAnimation {
        let animation = CAKeyframeAnimation()
        animation.keyPath = "transform"
        let startScale: CGFloat
        if layer?.animationKeys()?.contains("swell") ?? false {
            startScale = 1.2
            layer?.removeAnimation(forKey: "swell")
        } else {
            startScale = 1.0
        }
        let scales = [startScale, 2.0].map { growtx($0) }
        animation.values = scales
        animation.keyTimes = [0.0, 1]
        animation.duration = exitAnimationDuration
        return animation;
    }

    private func zoomToSmallAnimation() -> CAAnimation {
        let animation = CAKeyframeAnimation()
        animation.keyPath = "transform"
        let scales = [1.0, 0.1].map { growtx($0) }
        animation.values = scales
        animation.keyTimes = [0.0, 1]
        animation.duration = exitAnimationDuration
        return animation;
    }

    private func fadeAnimation() -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation()
        animation.keyPath = "opacity"
        animation.values = [1.0, 0.0]
        animation.keyTimes = [0.0, 1.0]
        animation.duration = exitAnimationDuration
        return animation
    }

    private func rotateAnimation() -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        let iterations = 1.0
        animation.duration = exitAnimationDuration / iterations
        animation.repeatCount = Float(iterations)
        animation.isAdditive = true
        animation.fromValue = 0
        animation.toValue = Double.pi
        return animation;
    }

    @objc
    func pop(completion: @escaping () -> ()) {
        guard let layer = layer else {
            return
        }
        if terminating {
            return
        }
        terminating = true
        CATransaction.begin()
        let group = CAAnimationGroup()
        let zoom = zoomToBigAnimation()
        let fade = fadeAnimation()
        let rotate = rotateAnimation()
        group.animations = [zoom, fade, rotate]
        group.fillMode = .forwards
        group.duration = exitAnimationDuration
        DLog("begin animation of duration \(group.duration)")
        CATransaction.setCompletionBlock { [weak self] in
            DLog("transaction completed")
            self?.removeFromSuperview()
            completion()
        }
        layer.opacity = 0
        layer.add(group, forKey: "zoom")
        CATransaction.commit()
    }

    func dissolve(completion: @escaping () -> ()) {
        if terminating {
            return
        }
        guard let layer = layer else {
            completion()
            return
        }
        terminating = true
        if layer.anchorPoint == CGPoint.zero {
            // dispatch to avoid mutation during enumeration
            DispatchQueue.main.async {
                completion()
            }
            return
        }
        DLog("dissolve")

        CATransaction.begin()
        let group = CAAnimationGroup()
        let zoom = self.zoomToSmallAnimation()
        let fade = self.fadeAnimation()
        group.animations = [zoom, fade]
        group.fillMode = .forwards
        group.duration = self.exitAnimationDuration
        CATransaction.setCompletionBlock { [weak self] in
            self?.removeFromSuperview()
            completion()
        }
        layer.opacity = 0
        layer.add(group, forKey: "zoom")
        CATransaction.commit()
    }

    override var frame: NSRect  {
        set {
            super.frame = newValue
            setAnchorPoint()
        }
        get {
            return super.frame
        }
    }

    func sizeToFit() {
        frame = NSRect(x: 0,
                       y: 0,
                       width: desiredSize.width + margin.width * 2,
                       height: desiredSize.height + margin.height * 2)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        doLayout()
    }

    private func doLayout() {
        label.frame = NSRect(x: (bounds.width - label.bounds.width) / 2.0,
                             y: (bounds.height - label.bounds.height) / 2.0,
                             width: label.frame.width,
                             height: label.frame.height)
    }

    private func setAnchorPoint() {
        if let layer = layer {
            CATransaction.begin()
            CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
            let center = layer.frame.center
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = center
            CATransaction.commit()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let animation = CAKeyframeAnimation()
        animation.keyPath = "transform"
        let scales = [1.0, 1.2].map { growtx($0) }
        animation.values = scales
        animation.keyTimes = [0.0, 1]
        animation.duration = 0.2
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        layer?.add(animation, forKey: "swell")
    }

    override func mouseUp(with event: NSEvent) {
        if let shortcut = shortcut, event.clickCount == 1 {
            shortcut.action()
        } else {
            CATransaction.begin()
            let animation = CAKeyframeAnimation()
            animation.keyPath = "transform"
            let scales = [1.2, 1.0].map { growtx($0) }
            animation.values = scales
            animation.keyTimes = [0.0, 1]
            animation.duration = 0.2
            layer?.removeAnimation(forKey: "swell")
            layer?.add(animation, forKey: "unswell")
            CATransaction.commit()
        }
    }
}

@objc
class ContentNavigationShortcutLayerOuter: NSObject {
    var views: [ContentNavigationShortcutView] = []

    @objc(addView:) func add(view: ContentNavigationShortcutView) {
        views.append(view)
    }

    @objc
    func layout(within bounds: NSRect) {
        for view in views {
            layout(view, within: bounds)
        }
    }

    private func layout(_ view: ContentNavigationShortcutView,
                        within bounds: NSRect) {
        let frame = topLeft(view, within: bounds)
        view.frame = frame
    }

    private func topLeft(_ view: ContentNavigationShortcutView,
                         within bounds: NSRect) -> NSRect {
        let y: CGFloat
        if view.target.height < view.bounds.height - view.margin.height * 2 {
            // Shortcut is taller than target. Center it vertically.
            y = view.target.midY - view.bounds.height / 2.0
        } else {
            // Target is taller than shortcut. Place shortcut in top right of target area.
            y = view.target.minY - view.margin.height
        }
        let x = max(2 - view.margin.width,
                     view.target.minX - view.bounds.width + view.margin.width - 2)
        return NSRect(x: x,
                      y: y,
                      width: view.bounds.width,
                      height: view.bounds.height)
    }
}

extension NSRect {
    var center: NSPoint {
        return NSPoint(x: midX, y: midY)
    }
}

extension NSPoint {
    func distance(_ point: NSPoint) -> CGFloat {
        return sqrt(pow(point.x - x, 2) + pow(point.y - y, 2))
    }
}
