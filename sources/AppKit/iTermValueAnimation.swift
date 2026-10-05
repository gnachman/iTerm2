//
//  iTermValueAnimation.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/4/26.
//

import AppKit

// Animates a number from one value to another, passing each frame's value to
// `apply`. Unlike an NSView animator animation, it can be canceled reliably:
// after stop(), neither `apply` nor `completion` runs again.
@objc(iTermValueAnimation)
class ValueAnimation: NSAnimation {
    private let from: CGFloat
    private let to: CGFloat
    private let apply: (CGFloat) -> Void
    private let completion: () -> Void
    private var stopped = false

    @objc
    init(from: CGFloat,
         to: CGFloat,
         duration: TimeInterval,
         apply: @escaping (CGFloat) -> Void,
         completion: @escaping () -> Void) {
        self.from = from
        self.to = to
        self.apply = apply
        self.completion = completion
        super.init(duration: duration, animationCurve: .easeInOut)
        animationBlockingMode = .nonblocking
        frameRate = 60
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    override func stop() {
        stopped = true
        super.stop()
    }

    override var currentProgress: NSAnimation.Progress {
        get {
            super.currentProgress
        }
        set {
            super.currentProgress = newValue
            apply(from + (to - from) * CGFloat(currentValue))
            if newValue >= 1 {
                // Deferred so the completion can release this animation
                // without doing so in the middle of this setter.
                DispatchQueue.main.async { [self] in
                    if !stopped {
                        completion()
                    }
                }
            }
        }
    }
}
