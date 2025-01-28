//
//  iTermMetalView.swift
//  iTerm2
//
//  Created by George Nachman on 12/26/24.
//

@objc
public class iTermMTKView: iTermMetalView {
    private var _timer: Timer?
    private var _lastSetNeedsDisplay: TimeInterval = 0

    @objc(initWithFrame:device:)
    override init(frame: NSRect, device: MTLDevice?) {
        super.init(frame: frame, device: device)
        if iTermAdvancedSettingsModel.hdrCursor() {
            colorPixelFormat = .bgra8Unorm
        }
        it_schedule()
    }
    
    @MainActor required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        _timer?.invalidate()
    }

    override public var alphaValue: CGFloat {
        set {
            super.alphaValue = newValue
            DLog("Set alpha value of \(self) to \(newValue) from \(Thread.callStackSymbols)")
        }
        get {
            super.alphaValue
        }
    }
    private func it_schedule() {
        _timer = Timer.scheduledWeakTimer(
            withTimeInterval: iTermAdvancedSettingsModel.metalRedrawPeriod(),
            target: self,
            selector: #selector(it_redrawPeriodically(_:)),
            userInfo: nil,
            repeats: true)
    }

    @objc
    private func it_redrawPeriodically(_ timer: Timer) {
        DLog("Timer fired")
        if (isHidden || alphaValue < 0.01 || bounds.size.width == 0 || bounds.size.height == 0) {
            DLog("Not visible \(self)")
            return;
        }
        if (round(1000 * timer.timeInterval) != round(1000 * iTermAdvancedSettingsModel.metalRedrawPeriod()))  {
            DLog("Recreate timer");
            _timer?.invalidate()
            _timer = nil
            it_schedule()
        }
        if (NSDate.it_timeSinceBoot() - _lastSetNeedsDisplay < timer.timeInterval) {
            DLog("Redrew recently");
            return;
        }
        needsDisplay = true
    }

    override public var needsDisplay: Bool {
        set {
            DLog("setNeedsDisplay:\(needsDisplay)")
            if newValue {
                _lastSetNeedsDisplay = NSDate.it_timeSinceBoot()
            }
            super.needsDisplay = newValue
        }
        get {
            super.needsDisplay
        }
    }

    override public func viewDidMoveToWindow() {
        colorspace = window?.screen?.colorSpace?.cgColorSpace
    }

    @objc(enclosingWindowDidMoveToScreen:)
    func enclosingWindowDidMove(to screen: NSScreen?) {
        colorspace = window?.screen?.colorSpace?.cgColorSpace
    }

    @objc
    override public var colorspace: CGColorSpace? {
        set {
            DLog("Set colorspace of \(self) to \(String(describing: newValue))")
            super.colorspace = newValue
        }
        get {
            super.colorspace
        }
    }
}
