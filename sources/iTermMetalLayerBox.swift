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
}
