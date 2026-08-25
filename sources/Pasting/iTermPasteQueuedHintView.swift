//
//  iTermPasteQueuedHintView.swift
//  iTerm2SharedARC
//
//  A lightweight callout (a rounded rectangle with a triangular pointer) used to
//  tell the user that their typing is being queued during a paste and point them
//  at the keyboard toggle in the paste indicator. It deliberately avoids
//  NSPopover, which is too heavyweight for this transient hint.
//

import AppKit
import QuartzCore

@objc(iTermPasteQueuedHintView)
class PasteQueuedHintView: NSView {
    private enum Metrics {
        static let cornerRadius: CGFloat = 7
        static let pointerHeight: CGFloat = 7
        static let pointerHalfWidth: CGFloat = 7
        static let horizontalPadding: CGFloat = 10
        static let verticalPadding: CGFloat = 7
        // How far the callout starts from its resting place (toward the button)
        // before springing out. Purely a translation, so the text is never
        // scaled/distorted.
        static let springTravel: CGFloat = 14
        // Playback speed multiplier applied to every animation (>1 is faster).
        // 1/0.7 makes them run 30% quicker.
        static let animationSpeedup: Float = 1.0 / 0.7
    }

    // The message shown inside the callout.
    @objc var message: String = ""

    // true: the pointer is on the top edge (the callout sits below its target).
    // false: the pointer is on the bottom edge (the callout sits above its target).
    @objc var pointerOnTopEdge: Bool = true

    // X coordinate of the pointer's tip, in the view's own coordinate space.
    @objc var pointerX: CGFloat = 0

    @objc override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // A shaped drop shadow that follows the callout outline (derived from the
        // layer's content alpha), not clipped to our bounds.
        let dropShadow = NSShadow()
        dropShadow.shadowOffset = NSSize(width: 0, height: -2)
        dropShadow.shadowBlurRadius = 8
        dropShadow.shadowColor = NSColor(white: 0, alpha: 0.35)
        shadow = dropShadow
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Text

    private var textAttributes: [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.alignment = .left
        return [.font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: style]
    }

    private func attributedMessage() -> NSAttributedString {
        return NSAttributedString(string: message, attributes: textAttributes)
    }

    private func textSize(forMaxWidth maxWidth: CGFloat) -> NSSize {
        let maxTextWidth = maxWidth - 2 * Metrics.horizontalPadding
        let rect = attributedMessage().boundingRect(
            with: NSSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin])
        return NSSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    // The size needed to lay the message out within `maxWidth`, including padding
    // and the pointer.
    @objc(sizeThatFitsMaxWidth:)
    func sizeThatFits(maxWidth: CGFloat) -> NSSize {
        let text = textSize(forMaxWidth: maxWidth)
        return NSSize(width: text.width + 2 * Metrics.horizontalPadding,
                      height: text.height + 2 * Metrics.verticalPadding + Metrics.pointerHeight)
    }

    // Don't intercept mouse events; the user must still be able to click the
    // keyboard button underneath/beside us.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    // MARK: - Drawing

    private func outlinePath() -> NSBezierPath {
        let W = bounds.width
        let H = bounds.height
        let r = Metrics.cornerRadius
        let ph = Metrics.pointerHeight
        let hw = Metrics.pointerHalfWidth
        let tipX = max(r + hw, min(W - r - hw, pointerX))

        let path = NSBezierPath()
        if pointerOnTopEdge {
            let bodyTop = H - ph
            path.move(to: NSPoint(x: W / 2, y: 0))
            path.appendArc(from: NSPoint(x: W, y: 0), to: NSPoint(x: W, y: bodyTop), radius: r)
            path.appendArc(from: NSPoint(x: W, y: bodyTop), to: NSPoint(x: 0, y: bodyTop), radius: r)
            path.line(to: NSPoint(x: tipX + hw, y: bodyTop))
            path.line(to: NSPoint(x: tipX, y: H))
            path.line(to: NSPoint(x: tipX - hw, y: bodyTop))
            path.appendArc(from: NSPoint(x: 0, y: bodyTop), to: NSPoint(x: 0, y: 0), radius: r)
            path.appendArc(from: NSPoint(x: 0, y: 0), to: NSPoint(x: W, y: 0), radius: r)
        } else {
            let bodyBottom = ph
            path.move(to: NSPoint(x: W / 2, y: H))
            path.appendArc(from: NSPoint(x: W, y: H), to: NSPoint(x: W, y: bodyBottom), radius: r)
            path.appendArc(from: NSPoint(x: W, y: bodyBottom), to: NSPoint(x: 0, y: bodyBottom), radius: r)
            path.line(to: NSPoint(x: tipX + hw, y: bodyBottom))
            path.line(to: NSPoint(x: tipX, y: 0))
            path.line(to: NSPoint(x: tipX - hw, y: bodyBottom))
            path.appendArc(from: NSPoint(x: 0, y: bodyBottom), to: NSPoint(x: 0, y: H), radius: r)
            path.appendArc(from: NSPoint(x: 0, y: H), to: NSPoint(x: W, y: H), radius: r)
        }
        path.close()
        return path
    }

    override func draw(_ dirtyRect: NSRect) {
        let outline = outlinePath()

        NSColor.windowBackgroundColor.setFill()
        outline.fill()

        NSColor.separatorColor.setStroke()
        outline.lineWidth = 1
        outline.stroke()

        // Body rect (excludes the pointer edge), then inset for text padding.
        var body = bounds
        body.size.height -= Metrics.pointerHeight
        if !pointerOnTopEdge {
            body.origin.y += Metrics.pointerHeight
        }
        let textArea = body.insetBy(dx: Metrics.horizontalPadding, dy: Metrics.verticalPadding)
        let size = textSize(forMaxWidth: bounds.width)
        let textRect = NSRect(x: textArea.minX,
                              y: textArea.midY - size.height / 2,
                              width: textArea.width,
                              height: size.height)
        attributedMessage().draw(with: textRect, options: [.usesLineFragmentOrigin])
    }

    // MARK: - Animation

    // Spring in from the direction of the pointer (a translation + fade; never a
    // scale, so the text stays crisp). Safe to call to interrupt a dismissal.
    @objc func animateIn() {
        // Interrupt any in-flight dismissal and resume from wherever it got to,
        // so a re-show never flashes.
        layer?.removeAnimation(forKey: "fadeOut")
        let fromOpacity = layer?.presentation()?.opacity ?? 0
        alphaValue = 1

        // A positional spring (translation only) so the text is never scaled. It
        // starts shifted toward the button and overshoots its resting place.
        let spring = CASpringAnimation(keyPath: "transform.translation.y")
        spring.fromValue = pointerOnTopEdge ? Metrics.springTravel : -Metrics.springTravel
        spring.toValue = 0
        spring.mass = 1
        spring.stiffness = 320
        spring.damping = 15
        spring.initialVelocity = 0
        spring.duration = spring.settlingDuration
        spring.speed = Metrics.animationSpeedup
        layer?.add(spring, forKey: "springIn")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fromOpacity
        fade.toValue = 1
        fade.duration = 0.18
        fade.speed = Metrics.animationSpeedup
        layer?.add(fade, forKey: "fadeIn")
    }

    // Fade out, then run `completion` (where the caller removes the view).
    @objc(animateOutWithCompletion:)
    func animateOut(completion: @escaping () -> Void) {
        let startAlpha = Float(alphaValue)
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = startAlpha
        fade.toValue = 0
        fade.duration = 0.14
        fade.speed = Metrics.animationSpeedup
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        alphaValue = 0
        layer?.add(fade, forKey: "fadeOut")
        CATransaction.commit()
    }
}
