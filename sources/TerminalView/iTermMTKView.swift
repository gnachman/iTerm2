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

    // How often to keep an ordered-out or fully occluded window's Metal pipeline warm. Matches the
    // 1 Hz background update cadence (kBackgroundUpdateCadence) that hidden sessions already tick at.
    private static let occludedRedrawPeriod: TimeInterval = 1.0

    @objc(initWithFrame:device:)
    override init(frame: NSRect, device: MTLDevice?) {
        super.init(frame: frame, device: device)
        if iTermAdvancedSettingsModel.hdrCursor() {
            colorPixelFormat = .bgra8Unorm
        }
        // Timer is scheduled in viewDidMoveToWindow; a detached view shouldn't wake up.
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
        _timer = Timer.it_scheduledWeakTimer(
            withTimeInterval: iTermAdvancedSettingsModel.metalRedrawPeriod(),
            target: self,
            selector: #selector(it_redrawPeriodically(_:)),
            userInfo: nil,
            repeats: true)
    }

    @objc
    private func it_redrawPeriodically(_ timer: Timer) {
        DLog("Timer with interval \(timer.timeInterval) fired for MTKView under \(superview.d) in window \(window.d)")

        if (isHidden || alphaValue < 0.01 || bounds.size.width == 0 || bounds.size.height == 0 || window == nil) {
            DLog("Not visible \(self)")
            return;
        }
        if (round(1000 * timer.timeInterval) != round(1000 * iTermAdvancedSettingsModel.metalRedrawPeriod()))  {
            DLog("Recreate timer");
            _timer?.invalidate()
            _timer = nil
            it_schedule()
        }
        // An ordered-out or fully occluded window (e.g. a hidden hotkey window) can't be seen, but a
        // cold Metal pipeline hitches on its first draw after a period of inactivity, which is very
        // visible the moment the window is revealed. Keep it warm at the slow occludedRedrawPeriod
        // instead of stopping entirely so the content is fresh and the pipeline is warm on reveal.
        let occluded = window?.occlusionState.contains(.visible) != true
        let minInterval = occluded ? max(Self.occludedRedrawPeriod, iTermAdvancedSettingsModel.metalRedrawPeriod())
                                   : timer.timeInterval
        if (NSDate.it_timeSinceBoot() - _lastSetNeedsDisplay < minInterval) {
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
        super.viewDidMoveToWindow()
        colorspace = window?.screen?.colorSpace?.cgColorSpace
        if window != nil {
            if _timer == nil {
                it_schedule()
            }
        } else {
            _timer?.invalidate()
            _timer = nil
        }
    }

    @objc(enclosingWindowDidMoveToScreen:)
    func enclosingWindowDidMove(to screen: NSScreen?) {
        colorspace = window?.screen?.colorSpace?.cgColorSpace
    }

    @objc
    override public var colorspace: CGColorSpace? {
        set {
            RLog("Set colorspace of \(self) to \(String(describing: newValue))")
            super.colorspace = newValue
        }
        get {
            super.colorspace
        }
    }
}
