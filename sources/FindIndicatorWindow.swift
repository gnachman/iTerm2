//
//  FindIndicatorWindow.swift
//
//  Created by George Nachman on 6/20/22.
//

import Foundation
import AppKit

// View that shows the image of the match. This view is inset within its superview and is animated
// to zoom and fade.
private class FindIndicatorView: NSView, CALayerDelegate {
    override var isFlipped: Bool {
        return true
    }

    init(frame: NSRect, image: NSImage, scale: CGFloat) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.delegate = self
        layer?.actions = ["contents": NSNull()]
        layer?.backgroundColor = nil
        layer?.contents = image.layerContents(forContentsScale: scale)
        layer?.contentsGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func action(for layer: CALayer, forKey event: String) -> CAAction? {
        return nil
    }
}

// Container view for the find indicator.
private class FindIndicatorWindowContentView: NSView, CALayerDelegate {
    override var isFlipped: Bool {
        return true
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.delegate = self
        layer?.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func action(for layer: CALayer, forKey event: String) -> CAAction? {
        return nil
    }
}

// Borderless window that exists briefly when showing the location of a search match. Emulates
// NSTextView.showFindIndicator(for:).
class FindIndicatorWindow: NSWindow, PTYTrackingChildWindow {
    private let view: NSView
    private let parentView: NSView
    private let growth = 1.22
    private let vShift = 0.0
    private var firstVisibleLine: Int64
    var requestRemoval: (() -> ())?

    @objc(showWithImage:view:rect:firstVisibleLine:)
    static func show(image: NSImage,
                     parent: NSView,
                     rect: NSRect,
                     firstVisibleLine: Int64) -> FindIndicatorWindow? {
        return FindIndicatorWindow(image: image, parent: parent, rect: rect, firstVisibleLine: firstVisibleLine)
    }

    private init?(image: NSImage, parent: NSView, rect: NSRect, firstVisibleLine: Int64) {
        guard let parentWindow = parent.window else {
            return nil
        }
        self.firstVisibleLine = firstVisibleLine
        self.parentView = parent
        let windowRect = parent.convert(rect, to: nil)
        var myRect = parentWindow.convertToScreen(windowRect)
        myRect.size.width *= growth
        myRect.size.width = ceil(myRect.size.width)
        myRect.size.height *= growth
        myRect.size.height = ceil(myRect.size.height)
        myRect.size.height += vShift
        let hinset = (myRect.width - rect.width) / 2.0
        let vinset = (myRect.height - rect.height) / 2.0
        myRect.origin.x -= hinset
        myRect.origin.x = floor(myRect.origin.x)
        myRect.origin.y -= vinset
        myRect.origin.y = floor(myRect.origin.y)

        // This frame is just temporary - the origin is wrong. I will set the origin later
        // by converting the frame to and from screen coords. This is necessary because
        // windows must be point-aligned while the image has to be pixel-aligned.
        view = FindIndicatorView(frame: NSRect(x: 0,
                                               y: 0,
                                               width: rect.width,
                                               height: rect.height),
                                 image: image,
                                 scale: parentWindow.backingScaleFactor)

        var contentRect = myRect
        contentRect.origin = .zero
        super.init(contentRect: contentRect,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)
        backgroundColor = .clear

        contentView = FindIndicatorWindowContentView(frame: contentView!.bounds)

        contentView?.addSubview(view)

        parentWindow.addChildWindow(self, ordered: .above)
        setFrame(myRect, display: false)


        let rectInParentWindow = parent.convert(rect, to: nil)
        let rectInScreen = parent.window!.convertToScreen(rectInParentWindow)
        let rectInMyWindow = convertFromScreen(rectInScreen)
        let rectInContentView = contentView!.convert(rectInMyWindow, from: nil)
        view.frame = rectInContentView
        orderFront(nil)

        animate()
    }

    @objc func shiftVertically(_ delta: CGFloat) {
        guard let parentViewWindow = parentView.window else {
            remove()
            return
        }
        guard parent == parentViewWindow else {
            remove()
            return
        }
        var frame = self.frame
        frame.origin.y += delta

        let parentViewFrameInWindowCoords = parentView.convert(parentView.bounds, to: nil)
        let parentViewFrameInScreenCoords = parentViewWindow.convertToScreen(parentViewFrameInWindowCoords)
        guard parentViewFrameInScreenCoords.intersects(frame) else {
            remove()
            return
        }
        setFrame(frame, display: true)
    }

    override var acceptsFirstResponder: Bool {
        return false
    }

    override var canBecomeKey: Bool {
        return false
    }

    override var canBecomeMain: Bool {
        return false
    }
}

extension FindIndicatorWindow: CAAnimationDelegate {
    private func growtx(_ amount: CGFloat) -> CATransform3D {
        let size = view.bounds.size
        let txToOrigin = CATransform3DMakeTranslation(size.width * -0.5,
                                                      size.height * -0.5,
                                                      0)
        let txFromOrigin = CATransform3DMakeTranslation(size.width * 0.5,
                                                      size.height * 0.5,
                                                      0)
        let grow = CATransform3DMakeScale(amount, amount, 1.0)
        let shiftDown = CATransform3DMakeTranslation(0, 0 /* vShift */, 0)
        return CATransform3DConcat(CATransform3DConcat(txToOrigin, CATransform3DConcat(grow, txFromOrigin)), shiftDown)
    }

    // This determines the overall duration. Convert frames to seconds using by dividing by fps.
    private var totalNumberOfFrames: Double { 38.0 }

    // This is useful for debugging.
    // 1.0 -> regular speed
    // 0.5 -> half speed
    private var playbackSpeed: Double { 1.0 }

    private var fps: Double { 60.0 * playbackSpeed }
    private var totalDuration: Double { totalNumberOfFrames / fps }

    // This gives the curve for the zoom animation as fractions (where 1.0 means the original size).
    // The first 3 frames or so seem to get dropped, so add some no-ops to the beginning.
    private static let scales = [1.0, 1.0, 1.0, 1.0, 1.0, 1.04, 1.20, 1.22, 1.22, 1.04, 1.0]

    // Delay in frames between animation stages.
    private static let timeBetweenEndOfZoomAndStartOfFade = 12.0

    private func t(_ time: Double) -> Double {
        return time / totalNumberOfFrames
    }

    private func zoomAnimation() -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation()
        animation.keyPath = "transform"
        animation.values = Self.scales.map { growtx($0) } + [growtx(1.0)]
        animation.keyTimes = Self.scales.enumerated().map {
            NSNumber(value: t(Double($0.offset)))
        } + [NSNumber(value: t(totalNumberOfFrames))]
        animation.duration = totalDuration
        return animation
    }

    private func fadeAnimation() -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation()
        animation.keyPath = "opacity"
        animation.values = [1.0, 1.0, 0.0, 0.0]
        // I don't know why but it needs a few extra frames at the end to complete the animation
        // before hiding.
        animation.keyTimes = [0.0,
                              t(Double(Self.scales.count) + Self.timeBetweenEndOfZoomAndStartOfFade),
                              t(totalNumberOfFrames - 4.0),
                              t(totalNumberOfFrames)].map { NSNumber(value: $0) }
        animation.duration = totalDuration
        return animation
    }

    private func animate() {
        guard let layer = view.layer else {
            return
        }
        let group = CAAnimationGroup()
        let zoom = zoomAnimation()
        let fade = fadeAnimation()
        group.animations = [zoom, fade]
        group.fillMode = .forwards
        group.duration = totalDuration
        group.delegate = self
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.opacity = 0.0
        layer.add(group, forKey: "pop")
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        remove()
    }

    private func remove() {
        requestRemoval?()
        parent?.removeChildWindow(self)
        orderOut(nil)
    }
}
