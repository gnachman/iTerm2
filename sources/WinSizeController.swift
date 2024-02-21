//
//  WinSizeControllr.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/27/22.
//

import Foundation

@objc(iTermWinSizeControllerDelegate)
protocol WinSizeControllerDelegate {
    func winSizeControllerIsReady() -> Bool
    @objc(winSizeControllerSetGridSize:viewSize:scaleFactor:)
    func winSizeControllerSet(size: VT100GridSize, viewSize: NSSize, scaleFactor: CGFloat)
}

@objc(iTermWinSizeController)
class WinSizeController: NSObject {
    private struct Request: Equatable, CustomDebugStringConvertible {
        static func == (lhs: WinSizeController.Request, rhs: WinSizeController.Request) -> Bool {
            return (VT100GridSizeEquals(lhs.size, rhs.size) &&
                    lhs.viewSize == rhs.viewSize &&
                    lhs.scaleFactor == rhs.scaleFactor)
        }

        var size: VT100GridSize
        var viewSize: NSSize
        var scaleFactor: CGFloat
        var regular: Bool  // false for the first resize of a jiggle
        var completion: (() -> ())?

        static var defaultRequest: Request {
            return Request(size: VT100GridSizeMake(80, 25),
                           viewSize: NSSize(width: 800, height: 250),
                           scaleFactor: 2.0,
                           regular: true,
                           completion: nil)
        }

        func sanitized(_ last: Request?) -> Request {
            if scaleFactor < 1 {
                return Request(size: size,
                               viewSize: viewSize,
                               scaleFactor: last?.scaleFactor ?? 2,
                               regular: regular,
                               completion: completion)
            }
            return self
        }

        var withoutCompletion: Request {
            return Request(size: size, viewSize: viewSize, scaleFactor: scaleFactor, regular: regular, completion: nil)
        }

        var debugDescription: String {
            return "<Request size=\(size) viewSize=\(viewSize) scaleFactor=\(scaleFactor) regular=\(regular)>"
        }
    }
    private var queue = [Request]()
    private var notBefore = TimeInterval(0)
    private var lastRequest: Request?
    private var deferCount = 0 {
        didSet {
            if deferCount == 0 {
                dequeue()
            }
        }
    }
    @objc weak var delegate: WinSizeControllerDelegate?
    private var lastJiggleTime = TimeInterval(0)
    @objc var timeSinceLastJiggle: TimeInterval {
        if lastJiggleTime == 0 {
            return TimeInterval.infinity
        }
        return NSDate.it_timeSinceBoot() - lastJiggleTime
    }

    // Cause the slave to receive a SIGWINCH and change the tty's window size. If `size` equals the
    // tty's current window size then no action is taken.
    // Returns false if it could not be set because we don't yet have a file descriptor. Returns true if
    // it was either set or nothing was done because the value didn't change.
    // NOTE: maybeScaleFactor will be 0 if the session is not attached to a window. For example, if
    // a different space is active.
    @discardableResult
    @objc(setGridSize:viewSize:scaleFactor:)
    func set(size: VT100GridSize, viewSize: NSSize, scaleFactor: CGFloat) -> Bool {
        set(Request(size: size,
                    viewSize: viewSize,
                    scaleFactor: scaleFactor,
                    regular: true))
    }

    // Doesn't change the size. Remembers the initial size to avoid unnecessary ioctls in the future.
    @objc
    func setInitialSize(_ size: VT100GridSize, viewSize: NSSize, scaleFactor: CGFloat) {
        guard lastRequest == nil else {
            DLog("Already have initial size")
            return
        }
        lastRequest = Request(size: size,
                              viewSize: viewSize,
                              scaleFactor: scaleFactor,
                              regular: true)
    }

    @objc
    func forceJiggle() {
        DLog("Force jiggle")
        reallyJiggle()
    }

    @objc
    func jiggle() {
        DLog("Jiggle")
        guard queue.isEmpty else {
            DLog("Queue empty")
            return
        }
        reallyJiggle()
    }

    private func reallyJiggle() {
        var base = lastRequest ?? Request.defaultRequest
        var adjusted = base
        adjusted.size = VT100GridSizeMake(base.size.width + 1, base.size.height)
        adjusted.regular = false
        adjusted.completion = { [weak self] in
            self?.lastJiggleTime = NSDate.it_timeSinceBoot()
        }
        set(adjusted)
        base.regular = true
        base.completion = { [weak self] in
            self?.lastJiggleTime = NSDate.it_timeSinceBoot()
        }
        set(base)
    }

    @objc
    func check() {
        dequeue()
    }

    @objc
    static func batchDeferChanges(_ controllers: [WinSizeController], closure: () -> ()) {
        for controller in controllers {
            controller.deferCount += 1
        }
        closure()
        for controller in controllers {
            controller.deferCount -= 1
        }
    }
    @objc
    func deferChanges(_ closure: () -> ()) {
        deferCount += 1
        closure()
        deferCount -= 1
    }

    @discardableResult
    private func set(_ request: Request) -> Bool {
        DLog("set \(request)")
        guard delegate?.winSizeControllerIsReady() ?? false else {
            DLog("delegate unready")
            return false
        }
        var combinedCompletion = request.completion
        if request.regular && (queue.last?.regular ?? false) {
            DLog("Replace last request \(String(describing: queue.last))")
            if let completion = queue.last?.completion {
                let orig = request.completion
                combinedCompletion = {
                    completion()
                    orig?()
                }
            }
            queue.removeLast()
        }
        if !request.regular,
           let i = queue.firstIndex(where: { !$0.regular }) {
            DLog("Remove up to previously added jiggle in queue \(queue) at index \(i)")
            let comps = queue[0...i].compactMap { $0.completion }
            if !comps.isEmpty {
                combinedCompletion = {
                    for c in comps {
                        c()
                    }
                    request.completion?()
                }
            }
            queue.removeFirst(i + 1)
            DLog("\(queue)")
        }
        var sanitized = request.sanitized(request)
        lastRequest = sanitized.withoutCompletion
        sanitized.completion = combinedCompletion
        queue.append(sanitized)
        dequeue()
        return true
    }

    private var shouldWait: Bool {
        return Date.timeIntervalSinceReferenceDate < notBefore || deferCount > 0
    }

    private func dequeue() {
        guard !shouldWait else {
            DLog("too soon to dequeue or resizing is deferred")
            return
        }
        guard delegate?.winSizeControllerIsReady() ?? false else {
            DLog("delegate unready")
            return
        }
        guard let request = get() else {
            DLog("queue empty")
            return
        }
        DLog("set window size to \(request)")
        let delay = TimeInterval(0.2)
        notBefore = Date.timeIntervalSinceReferenceDate + delay
        DLog("notBefore set to \(notBefore)")
        delegate?.winSizeControllerSet(size: request.size,
                                       viewSize: request.viewSize,
                                       scaleFactor: request.scaleFactor)
        request.completion?()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            DLog("Delay finished")
            self?.dequeue()
        }
    }

    private func get() -> Request? {
        guard let result = queue.first else {
            return nil
        }
        queue.removeFirst()
        return result
    }
}

extension VT100GridSize: CustomDebugStringConvertible {
    public var debugDescription: String {
        return VT100GridSizeDescription(self)
    }
}
