// Minimal reproduction of the "explicit EDR poisons natural reference EDR" latch.
//
// Background: on a reference-mode EDR display (e.g. Pro Display XDR) a plain
// drawRect: view can render brighter than reference white via additive blending,
// riding the display's natural reference EDR (this is how iTerm2's Tahoe tab
// outline and the legacy HDR cursor glow, with no explicit EDR engagement).
// Separately, a CAMetalLayer can engage *explicit* EDR via
// wantsExtendedDynamicRangeContent. The bug: once explicit EDR has been engaged
// and then torn down, the window's natural reference EDR appears to stay
// poisoned (the drawRect swatch stops glowing) and does not recover.
//
// This app isolates that so we can test teardown variants and watch the screen's
// reported headroom, without any iTerm2 code in the way.
//
// Build & run:
//   swiftc -O -o /tmp/edrrepro tests/edr-latch-repro.swift \
//       -framework Cocoa -framework Metal -framework QuartzCore
//   /tmp/edrrepro
//
// Put the window on the XDR (or any EDR-capable) display. Compare the two
// swatches: the right one should look clearly brighter than the left when
// natural EDR is alive. Then Engage, and Remove (each variant), watching whether
// the right swatch survives/recovers and what the headroom readout does.

import Cocoa
import Metal
import QuartzCore

// A drawRect: view that rides natural reference EDR. Left half is reference-white
// (1.0); right half is pushed well past 1.0 with additive passes. If natural EDR
// is alive the right half is visibly brighter; if poisoned, both look the same.
final class HDRSwatchView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        let half = (b.width / 2).rounded()

        NSColor.white.set()
        NSRect(x: 0, y: 0, width: half, height: b.height).fill()

        let right = NSRect(x: half, y: 0, width: b.width - half, height: b.height)
        NSColor.black.set()
        right.fill()
        NSColor.white.set()
        for _ in 0..<5 {
            right.fill(using: .plusLighter)  // accumulate to ~5x reference white
        }

        let label = "1.0 (ref)   |   ~5x (additive)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.systemBlue
        ]
        label.draw(at: NSPoint(x: 8, y: 8), withAttributes: attrs)
    }
}

// Engages explicit EDR through a CAMetalLayer that clears to a bright value.
final class MetalEDR {
    let layer = CAMetalLayer()
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private var timer: Timer?
    private let clearValue: Double

    // pointSize: layer size in points (1 = effectively invisible).
    // clearValue: color each frame clears to (0 = draws nothing visible).
    // renderInterval: seconds between presents (0 = present exactly once).
    init?(host: CALayer, scale: CGFloat, pointSize: CGFloat, clearValue: Double, renderInterval: TimeInterval) {
        guard let dev = MTLCreateSystemDefaultDevice(),
              let q = dev.makeCommandQueue() else {
            return nil
        }
        device = dev
        queue = q
        self.clearValue = clearValue
        layer.device = dev
        layer.pixelFormat = .rgba16Float
        layer.framebufferOnly = false
        layer.isOpaque = false
        layer.wantsExtendedDynamicRangeContent = true
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedSRGB)
        layer.frame = CGRect(x: 0, y: 0, width: pointSize, height: pointSize)
        layer.contentsScale = scale
        layer.drawableSize = CGSize(width: max(1, pointSize * scale),
                                    height: max(1, pointSize * scale))
        host.addSublayer(layer)
        render()
        if renderInterval > 0 {
            timer = Timer.scheduledTimer(withTimeInterval: renderInterval, repeats: true) { [weak self] _ in
                self?.render()
            }
        }
    }

    func setFlag(_ on: Bool) {
        layer.wantsExtendedDynamicRangeContent = on
    }

    // Disengage EDR but keep the layer in the hierarchy (flag off, stop drawing).
    func pause() {
        timer?.invalidate()
        timer = nil
        layer.wantsExtendedDynamicRangeContent = false
        render()  // present one flag-off frame
    }

    func render() {
        guard layer.drawableSize.width > 0, let drawable = layer.nextDrawable() else {
            return
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let v = clearValue
        pass.colorAttachments[0].clearColor = MTLClearColor(red: v, green: v, blue: v, alpha: v > 0 ? 1 : 0)
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pass) else {
            return
        }
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }

    func teardown() {
        timer?.invalidate()
        timer = nil
        layer.removeFromSuperlayer()
    }
}

final class Controller: NSObject {
    private let window: NSWindow
    private let swatch = HDRSwatchView()
    private let metalHost = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 60))
    private let readout = NSTextField(labelWithString: "")
    private var metal: MetalEDR?
    private var readoutTimer: Timer?
    private var lastLoggedCurrent: CGFloat = -1

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered,
                          defer: false)
        super.init()
        window.title = "EDR Latch Repro"

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 520))

        swatch.frame = NSRect(x: 20, y: 160, width: 720, height: 320)
        swatch.autoresizingMask = [.width, .height]
        content.addSubview(swatch)

        metalHost.wantsLayer = true
        metalHost.frame = NSRect(x: 620, y: 20, width: 120, height: 120)
        metalHost.autoresizingMask = [.minXMargin]
        content.addSubview(metalHost)

        let engage = button("Engage Metal EDR", #selector(engage))
        engage.frame = NSRect(x: 20, y: 110, width: 200, height: 28)
        content.addSubview(engage)

        let engageOnce = button("Engage invisible (1px, once)", #selector(engageInvisibleOnce))
        engageOnce.frame = NSRect(x: 230, y: 110, width: 240, height: 28)
        content.addSubview(engageOnce)

        let engageSlow = button("Engage invisible (1px, 1fps)", #selector(engageInvisibleSlow))
        engageSlow.frame = NSRect(x: 480, y: 110, width: 240, height: 28)
        content.addSubview(engageSlow)

        let removeNaive = button("Remove (naive)", #selector(removeNaive))
        removeNaive.frame = NSRect(x: 20, y: 78, width: 200, height: 28)
        content.addSubview(removeNaive)

        let removeFlag = button("Remove (flag off first)", #selector(removeFlagFirst))
        removeFlag.frame = NSRect(x: 230, y: 78, width: 220, height: 28)
        content.addSubview(removeFlag)

        let removeFlagPresent = button("Remove (flag off + present)", #selector(removeFlagPresent))
        removeFlagPresent.frame = NSRect(x: 230, y: 46, width: 220, height: 28)
        content.addSubview(removeFlagPresent)

        let disengageKeep = button("Disengage (keep layer, flag off)", #selector(disengageKeep))
        disengageKeep.frame = NSRect(x: 460, y: 78, width: 260, height: 28)
        content.addSubview(disengageKeep)

        let redraw = button("Redraw swatch", #selector(redraw))
        redraw.frame = NSRect(x: 20, y: 46, width: 200, height: 28)
        content.addSubview(redraw)

        readout.frame = NSRect(x: 20, y: 18, width: 720, height: 20)
        readout.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        readout.autoresizingMask = [.width]
        content.addSubview(readout)

        window.contentView = content
        window.center()
        window.makeKeyAndOrderFront(nil)

        readoutTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateReadout()
        }
        log("launch")
    }

    private func headroom() -> (cur: CGFloat, pot: CGFloat, ref: CGFloat) {
        let screen = window.screen ?? NSScreen.main
        return (screen?.maximumExtendedDynamicRangeColorComponentValue ?? 0,
                screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 0,
                screen?.maximumReferenceExtendedDynamicRangeColorComponentValue ?? 0)
    }

    // Log the current headroom with a label, and again after 0.5s to catch the
    // settled value (engagement/teardown changes can land a moment later).
    private func log(_ label: String) {
        let h = headroom()
        NSLog("EDRREPRO [%@] metalEDR=%@ current=%.3f potential=%.3f reference=%.3f",
              label, metal == nil ? "off" : "on", h.cur, h.pot, h.ref)
        lastLoggedCurrent = h.cur
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            let h2 = self.headroom()
            NSLog("EDRREPRO [%@ +0.5s] metalEDR=%@ current=%.3f potential=%.3f reference=%.3f",
                  label, self.metal == nil ? "off" : "on", h2.cur, h2.pot, h2.ref)
            self.lastLoggedCurrent = h2.cur
        }
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        return b
    }

    private func updateReadout() {
        swatch.needsDisplay = true
        let screen = window.screen ?? NSScreen.main
        let h = headroom()
        readout.stringValue = String(format: "screen=%@  current=%.3f  potential=%.3f  reference=%.3f  metalEDR=%@",
                                     screen?.localizedName ?? "?",
                                     h.cur, h.pot, h.ref,
                                     metal == nil ? "off" : "on")
        // Log spontaneous headroom changes (not driven by a button) so drift is captured.
        if abs(h.cur - lastLoggedCurrent) > 0.01 {
            NSLog("EDRREPRO [drift] metalEDR=%@ current=%.3f potential=%.3f reference=%.3f",
                  metal == nil ? "off" : "on", h.cur, h.pot, h.ref)
            lastLoggedCurrent = h.cur
        }
    }

    // Always start fresh so re-engage works even after a disengage-keep.
    private func startMetal(pointSize: CGFloat, clearValue: Double, renderInterval: TimeInterval, label: String) {
        metal?.teardown()
        metal = nil
        metalHost.layoutSubtreeIfNeeded()
        metal = MetalEDR(host: metalHost.layer!, scale: window.backingScaleFactor,
                         pointSize: pointSize, clearValue: clearValue, renderInterval: renderInterval)
        log(label)
    }

    @objc private func engage() {
        startMetal(pointSize: metalHost.bounds.width, clearValue: 4.0, renderInterval: 1.0 / 30.0, label: "engage")
    }

    @objc private func engageInvisibleOnce() {
        startMetal(pointSize: 1, clearValue: 0.0, renderInterval: 0, label: "engageInvisibleOnce")
    }

    @objc private func engageInvisibleSlow() {
        startMetal(pointSize: 1, clearValue: 0.0, renderInterval: 1.0, label: "engageInvisibleSlow")
    }

    @objc private func removeNaive() {
        metal?.teardown()
        metal = nil
        log("removeNaive")
    }

    @objc private func removeFlagFirst() {
        metal?.setFlag(false)
        metal?.teardown()
        metal = nil
        log("removeFlagFirst")
    }

    @objc private func removeFlagPresent() {
        metal?.setFlag(false)
        metal?.render()
        // Give the compositor a moment to present the flag-off frame before teardown.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.metal?.teardown()
            self?.metal = nil
            self?.log("removeFlagPresent")
        }
    }

    @objc private func disengageKeep() {
        metal?.pause()
        // Intentionally keep `metal` non-nil so the layer stays in the hierarchy.
        log("disengageKeep")
    }

    @objc private func redraw() {
        swatch.needsDisplay = true
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let controller = Controller()
app.activate(ignoringOtherApps: true)
app.run()
