//
//  iTermMetalLayerBox.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/25/25.
//

import Foundation
import Metal

class iTermMetalLayerBox {
    struct LayerContext: Equatable {
        init(_ metalLayer: CAMetalLayer) {
            device = metalLayer.device
            framebufferOnly = metalLayer.framebufferOnly
            presentsWithTransaction = metalLayer.presentsWithTransaction
            pixelFormat = metalLayer.pixelFormat
            colorspace = metalLayer.colorspace
            size = metalLayer.drawableSize
        }

        static func == (lhs: LayerContext, rhs: LayerContext) -> Bool {
            return (lhs.device === rhs.device &&
                    lhs.framebufferOnly == rhs.framebufferOnly &&
                    lhs.presentsWithTransaction == rhs.presentsWithTransaction &&
                    lhs.pixelFormat == rhs.pixelFormat &&
                    lhs.colorspace === rhs.colorspace &&
                    lhs.size == rhs.size)
        }

        weak var device: MTLDevice?
        var framebufferOnly: Bool
        var presentsWithTransaction: Bool
        var pixelFormat: MTLPixelFormat
        var colorspace: CGColorSpace?
        var size: CGSize
    }

    private let metalLayer: MutableAtomicObject<CAMetalLayer>
    private let _layerContext: MutableAtomicObject<LayerContext>

    init(metalLayer: CAMetalLayer) {
        self.metalLayer = .init(metalLayer)
        self._layerContext = .init(.init(metalLayer))
    }
}

extension iTermMetalLayerBox {
    var layerContext: LayerContext {
        _layerContext.value
    }

    var device: MTLDevice? {
        get {
            return metalLayer.access { $0.device }
        }
        set {
            metalLayer.access {
                $0.device = newValue
                _layerContext.value = .init($0)
            }
        }
    }

    var delegate: CALayerDelegate? {
        get {
            metalLayer.access { $0.delegate }
        }
        set {
            metalLayer.access { $0.delegate = newValue }
        }

    }
    var allowsNextDrawableTimeout: Bool {
        get {
            return metalLayer.access { $0.allowsNextDrawableTimeout }
        }
        set {
            metalLayer.access { $0.allowsNextDrawableTimeout = newValue }
        }
    }

    var framebufferOnly: Bool {
        get {
            return metalLayer.access { $0.framebufferOnly }
        }
        set {
            metalLayer.access {
                $0.framebufferOnly = newValue
                _layerContext.value = .init($0)
            }
        }
    }

    var presentsWithTransaction: Bool {
        get {
            return metalLayer.access { $0.presentsWithTransaction }
        }
        set {
            metalLayer.access {
                $0.presentsWithTransaction = newValue
                _layerContext.value = .init($0)
            }
        }
    }

    var pixelFormat: MTLPixelFormat {
        get {
            return metalLayer.access { $0.pixelFormat }
        }
        set {
            metalLayer.access {
                $0.pixelFormat = newValue
                _layerContext.value = .init($0)
            }
        }
    }

    var wantsExtendedDynamicRangeContent: Bool {
        get {
            return metalLayer.access { $0.wantsExtendedDynamicRangeContent }
        }
        set {
            metalLayer.access {
                $0.wantsExtendedDynamicRangeContent = newValue
            }
        }
    }

    var colorspace: CGColorSpace? {
        get {
            return metalLayer.access { $0.colorspace }
        }
        set {
            metalLayer.access {
                $0.colorspace = newValue
                _layerContext.value = .init($0)
            }
        }
    }

    var drawableSize: CGSize {
        get {
            return metalLayer.access { $0.drawableSize }
        }
        set {
            metalLayer.access {
                $0.drawableSize = newValue
                _layerContext.value = .init($0)
            }
        }
    }

    var preferredDevice: MTLDevice? {
        return metalLayer.access { $0.preferredDevice }
    }

    var contentsScale: CGFloat {
        get {
            return metalLayer.access { $0.contentsScale }
        }
        set {
            metalLayer.access { $0.contentsScale = newValue }
        }
    }

    func nextDrawable() -> CAMetalDrawable? {
        return metalLayer.access { layer in
            return layer.nextDrawable()
        }
    }

    func nextContextualizedDrawable() -> (CAMetalDrawable, LayerContext)? {
        return metalLayer.access { layer in
            if let drawable = layer.nextDrawable() {
                // The access to layerContext is not a data race because it is only mutated while
                // both metalLayer and layerContext are locked.
                return (drawable, layerContext)
            }
            return nil
        }
    }
}

/// Helper class for acquiring Metal drawables with context validation.
/// Created on the main thread, can be used from any thread to acquire a drawable
/// and later validate that the layer context hasn't changed since acquisition.
@objc class iTermDrawableAcquisitionHelper: NSObject {
    private let box: iTermMetalLayerBox
    private var capturedContext: iTermMetalLayerBox.LayerContext?

    init(box: iTermMetalLayerBox) {
        self.box = box
        super.init()
    }

    /// Acquires a drawable from the Metal layer and captures the current layer context.
    /// Can be called from any thread.
    /// - Returns: The acquired drawable, or nil if unavailable.
    @objc func acquireDrawable() -> CAMetalDrawable? {
        if let tuple = box.nextContextualizedDrawable() {
            capturedContext = tuple.1
            return tuple.0
        }
        return nil
    }

    /// Checks if the layer context is still the same as when the drawable was acquired.
    /// This should be called before presenting to ensure the drawable is still compatible
    /// with the current view state (size, scale factor, etc.).
    /// - Returns: true if the context matches, false if it has changed.
    @objc func isContextStillValid() -> Bool {
        guard let captured = capturedContext else {
            return false
        }
        return captured == box.layerContext
    }
}
