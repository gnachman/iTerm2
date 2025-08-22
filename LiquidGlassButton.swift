import Cocoa

@available(macOS 26.0, *)
class LiquidGlassButton: NSButton {
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLiquidGlassAppearance()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLiquidGlassAppearance()
    }
    
    private func setupLiquidGlassAppearance() {
        // Set button type to bordered for liquid glass effect
        self.setButtonType(.momentaryPushIn)
        self.bezelStyle = .rounded
        
        // Enable the new liquid glass material
        if #available(macOS 26.0, *) {
            self.bezelStyle = .automatic
            self.isBordered = true
            
            // Apply translucent background material
            self.wantsLayer = true
            self.layer?.cornerRadius = 8
            self.layer?.masksToBounds = true
            
            // Use the new appearance APIs
            self.appearance = NSAppearance(named: .vibrantDark)
        }
        
        // Set up visual effect backing
        setupVisualEffectBacking()
    }
    
    private func setupVisualEffectBacking() {
        // Create a visual effect view for the liquid glass material
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .headerView
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        
        // Apply to button's background
        if let layer = self.layer {
            layer.backgroundColor = NSColor.clear.cgColor
        }
    }
    
    // Apply tint color using the new tint modifier approach
    func applyTint(_ color: NSColor) {
        if #available(macOS 26.0, *) {
            self.contentTintColor = color
            self.bezelColor = color.withAlphaComponent(0.3)
        }
    }
    
    // Override to add liquid glass hover effect
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        // Remove existing tracking areas
        for trackingArea in self.trackingAreas {
            self.removeTrackingArea(trackingArea)
        }
        
        // Add new tracking area for hover effects
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow]
        let trackingArea = NSTrackingArea(rect: self.bounds, options: options, owner: self, userInfo: nil)
        self.addTrackingArea(trackingArea)
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        animateLiquidGlassHover(isHovering: true)
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        animateLiquidGlassHover(isHovering: false)
    }
    
    private func animateLiquidGlassHover(isHovering: Bool) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            if let layer = self.layer {
                // Animate the liquid glass refraction effect
                if isHovering {
                    layer.shadowOpacity = 0.3
                    layer.shadowRadius = 10
                    layer.shadowOffset = CGSize(width: 0, height: 2)
                    layer.shadowColor = NSColor.systemBlue.withAlphaComponent(0.5).cgColor
                    layer.transform = CATransform3DMakeScale(1.02, 1.02, 1)
                } else {
                    layer.shadowOpacity = 0.1
                    layer.shadowRadius = 5
                    layer.shadowOffset = CGSize(width: 0, height: 1)
                    layer.shadowColor = NSColor.black.withAlphaComponent(0.3).cgColor
                    layer.transform = CATransform3DIdentity
                }
            }
        })
    }
}

// MARK: - SwiftUI Bridge for Liquid Glass Button
@available(macOS 26.0, *)
import SwiftUI

struct LiquidGlassButtonView: NSViewRepresentable {
    let title: String
    let action: () -> Void
    var tintColor: NSColor = .systemBlue
    
    func makeNSView(context: Context) -> LiquidGlassButton {
        let button = LiquidGlassButton(frame: .zero)
        button.title = title
        button.target = context.coordinator
        button.action = #selector(Coordinator.buttonClicked)
        button.applyTint(tintColor)
        return button
    }
    
    func updateNSView(_ nsView: LiquidGlassButton, context: Context) {
        nsView.title = title
        nsView.applyTint(tintColor)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }
    
    class Coordinator: NSObject {
        let action: () -> Void
        
        init(action: @escaping () -> Void) {
            self.action = action
        }
        
        @objc func buttonClicked() {
            action()
        }
    }
}

// MARK: - Example Usage
@available(macOS 26.0, *)
class LiquidGlassButtonExample: NSViewController {
    
    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        
        // Create liquid glass buttons with different tints
        let blueButton = createLiquidGlassButton(title: "Blue Glass", tint: .systemBlue, position: CGPoint(x: 50, y: 150))
        let greenButton = createLiquidGlassButton(title: "Green Glass", tint: .systemGreen, position: CGPoint(x: 150, y: 150))
        let purpleButton = createLiquidGlassButton(title: "Purple Glass", tint: .systemPurple, position: CGPoint(x: 250, y: 150))
        
        self.view.addSubview(blueButton)
        self.view.addSubview(greenButton)
        self.view.addSubview(purpleButton)
        
        // Set background to show off the translucent effect
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
    
    private func createLiquidGlassButton(title: String, tint: NSColor, position: CGPoint) -> LiquidGlassButton {
        let button = LiquidGlassButton(frame: NSRect(x: position.x, y: position.y, width: 100, height: 40))
        button.title = title
        button.applyTint(tint)
        button.target = self
        button.action = #selector(buttonPressed(_:))
        return button
    }
    
    @objc private func buttonPressed(_ sender: LiquidGlassButton) {
        print("Liquid Glass Button pressed: \(sender.title)")
    }
}