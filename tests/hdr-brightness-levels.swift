// Shows which HDR brightness levels a display can actually distinguish.
//
// Each swatch is an fp16 CAMetalLayer with wantsExtendedDynamicRangeContent,
// in the same extended (gamma-encoded) color space iTerm2's HDR cursor uses,
// cleared to a component value. The values are the same units as the Metal
// renderer's HDR cursor color, so if
// the swatches from some value upward all look the same, the display is
// clipping there and brightness settings above it have no visible effect.
// The window title shows the screen's current and potential headroom, which
// is only meaningful while EDR is engaged (i.e., while this window is up).
//
// Build & run:
//   swiftc -O -o /tmp/hdrlevels tests/hdr-brightness-levels.swift \
//       -framework Cocoa -framework Metal -framework QuartzCore
//   /tmp/hdrlevels

import Cocoa
import Metal
import QuartzCore

let levels: [Double] = [1.0, 1.1, 1.25, 1.5, 2.0, 3.0, 4.0, 8.0]

final class Swatch {
    let layer = CAMetalLayer()
    private let queue: MTLCommandQueue
    private let value: Double

    init(device: MTLDevice, queue: MTLCommandQueue, value: Double, colorspace: CGColorSpace?) {
        self.queue = queue
        self.value = value
        layer.device = device
        layer.pixelFormat = .rgba16Float
        layer.framebufferOnly = false
        layer.isOpaque = true
        layer.wantsExtendedDynamicRangeContent = true
        layer.colorspace = colorspace
    }

    func render() {
        guard layer.drawableSize.width > 0, let drawable = layer.nextDrawable() else {
            return
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: value, green: value, blue: value, alpha: 1)
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pass) else {
            return
        }
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var swatches: [Swatch] = []
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let width = CGFloat(levels.count) * 90
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: width, height: 200),
                          styleMask: [.titled, .closable],
                          backing: .buffered,
                          defer: false)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 200))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = content

        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            fatalError("No Metal device")
        }
        let wide = window.screen?.canRepresent(.p3) ?? false
        let colorspace = CGColorSpace(name: wide ? CGColorSpace.extendedDisplayP3 : CGColorSpace.extendedSRGB)
        let scale = window.backingScaleFactor
        for (i, value) in levels.enumerated() {
            let swatch = Swatch(device: device, queue: queue, value: value, colorspace: colorspace)
            swatch.layer.frame = CGRect(x: CGFloat(i) * 90 + 5, y: 30, width: 80, height: 160)
            swatch.layer.contentsScale = scale
            swatch.layer.drawableSize = CGSize(width: 80 * scale, height: 160 * scale)
            content.layer?.addSublayer(swatch.layer)
            swatches.append(swatch)

            // Component value, then the linear multiple of white it encodes.
            let linear = pow((value + 0.055) / 1.055, 2.4)
            let label = NSTextField(labelWithString: String(format: "%.2f (%.1fx)", value, linear))
            label.textColor = .systemBlue
            label.frame = NSRect(x: CGFloat(i) * 90 + 5, y: 6, width: 80, height: 18)
            content.addSubview(label)
        }
        window.makeKeyAndOrderFront(nil)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.swatches.forEach { $0.render() }
            if let screen = self.window.screen {
                self.window.title = String(format: "current headroom %.2f, potential %.2f",
                                           screen.maximumExtendedDynamicRangeColorComponentValue,
                                           screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
