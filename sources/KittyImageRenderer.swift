//
//  KittyImageRenderer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/26/24.
//

import Foundation

// A sequence of draws to perform based on adjacent unicode placeholders.
@objc(iTermKittyImageRun)
class KittyImageRun: NSObject {
    let draw: iTermKittyImageDraw
    let sourceCoord: VT100GridCoord
    let destCoord: VT100GridCoord
    @objc var length: UInt

    @objc(initWithDraw:sourceCoord:destCoord:length:)
    init(draw: iTermKittyImageDraw,
         sourceCoord: VT100GridCoord,
         destCoord: VT100GridCoord,
         length: UInt) {
        self.draw = draw
        self.sourceCoord = sourceCoord
        self.destCoord = destCoord
        self.length = length
    }
}

@objc(iTermKittyImageRendererTransientState)
class KittyImageRendererTransientState: iTermMetalCellRendererTransientState {
    fileprivate var draws = [iTermKittyImageDraw]()
    fileprivate var textures = ReferenceContainer<[UUID: MTLTexture]>([:])
    fileprivate var cellRenderer: iTermMetalCellRenderer!
    @objc var visibleRect = NSRect.zero
    @objc var totalScrollbackOverflow = Int64(0)
    fileprivate var runs = [KittyImageRun]()

    private var scaledVisibleRect: NSRect {
        visibleRect * configuration.scale
    }

    @objc(addDraw:)
    func add(draw: iTermKittyImageDraw) {
        draws.append(draw)
    }

    @objc(addRuns:)
    func add(runs: [KittyImageRun]) {
        self.runs.append(contentsOf: runs)
    }

    struct Operation {
        var texture: MTLTexture
        var source: NSRect
        var destination: NSRect
        var quad: MTLBuffer
    }

    fileprivate func enumerateOperations(zRange: Range<Int>, closure: (Operation) -> ()) {
        let screenOrigin = scaledVisibleRect.origin.addingY(-configuration.extraMargins.top)
        for draw in draws {
            let texture = texture(for: draw)
            guard let texture else {
                continue
            }
            guard zRange.contains(Int(clamping: draw.zIndex)) else {
                continue
            }
            if draw.virtual {
                continue
            }
            var shiftedDestinationFrame = draw.destinationFrame
            shiftedDestinationFrame.shiftY(by: cellConfiguration.cellSize.height * CGFloat(-totalScrollbackOverflow))
            guard shiftedDestinationFrame.intersects(scaledVisibleRect) else {
                continue
            }
            let destinationFrame = shiftedDestinationFrame
                .translatedToOrigin(screenOrigin)
                .flipped(in: CGFloat(configuration.viewportSize.y))
            let quad = cellRenderer.newQuad(
                withFrame: destinationFrame,
                textureFrame: textureFrame(draw),
                poolContext: poolContext)
            closure(Operation(texture: texture,
                              source: draw.sourceFrame,
                              destination: draw.destinationFrame,
                              quad: quad))
        }

        // Now do unicode placeholders.
        let cellSizePoints = cellConfiguration.cellSize / configuration.scale
        for run in runs {
            guard let draw = draw(for: run) else {
                continue
            }
            let texture = texture(for: draw)
            guard let texture else {
                continue
            }
            let instructions =
            iTermKittyPlaceholderDrawInstructionsCreate(
                draw,
                cellConfiguration.cellSize / configuration.scale,
                run.sourceCoord,
                run.destCoord,
                NSPoint(x: cellSizePoints.width * CGFloat(run.destCoord.x) + self.margins.left / configuration.scale,
                        y: cellSizePoints.height * CGFloat(run.destCoord.y)),
                draw.imageID,
                draw.placementID,
                0)
            let quadTextureFrame = instructions.sourceRect.flipped(in: draw.image.scaledSize.height) / draw.image.scaledSize
            var dest = instructions.destRect
            dest += instructions.translation
            dest -= NSPoint(x: 0, y: instructions.destRect.height)
            dest *= configuration.scale
            dest.shiftY(by: margins.bottom)
            let quad = cellRenderer.newQuad(
                withFrame: dest.flipped(in: CGFloat(configuration.viewportSize.y)),
                textureFrame: quadTextureFrame.inverted,
                poolContext: poolContext)
            closure(Operation(texture: texture,
                              source: instructions.sourceRect,
                              destination: instructions.destRect,
                              quad: quad))
        }
    }

    private func draw(for run: KittyImageRun) -> iTermKittyImageDraw? {
        return iTermFindKittyImageDrawForVirtualPlaceholder(draws,
                                                            run.draw.placementID,
                                                            run.draw.imageID)
    }

    private func textureFrame(_ draw: iTermKittyImageDraw) -> NSRect {
        return NSRect(x: draw.sourceFrame.minX / draw.image.scaledSize.width,
                      y: draw.sourceFrame.minY / draw.image.scaledSize.height,
                      width: draw.sourceFrame.width / draw.image.scaledSize.width,
                      height: draw.sourceFrame.height / draw.image.scaledSize.height).inverted
    }

    private func texture(for draw: iTermKittyImageDraw) -> MTLTexture? {
        if let texture = textures.value[draw.imageUniqueID] {
            return texture
        }
        guard let texture = createTexture(draw) else {
            return nil
        }
        textures.value[draw.imageUniqueID] = texture
        return texture
    }

    private func createTexture(_ draw: iTermKittyImageDraw) -> MTLTexture? {
        guard let image = draw.image.images.firstObject as? NSImage else {
            return nil
        }
        return cellRenderer.texture(fromImage: iTermImageWrapper(image: image),
                                    context: poolContext,
                                    colorSpace: configuration.colorSpace)
    }
}

@objc(iTermKittyImageRenderer)
class KittyImageRenderer: NSObject, iTermMetalCellRendererProtocol {
    @objc var rendererDisabled = false
    private let cellRenderer: iTermMetalCellRenderer
    private var textures = ReferenceContainer([UUID: MTLTexture]())
    @objc var minZ: Int32 = 0
    @objc var maxZ: Int32 = 0
    @objc(initWithDevice:)
    init?(device: MTLDevice) {
        let maybeCellRenderer = iTermMetalCellRenderer(device: device,
                                                       vertexFunctionName: "KittyImageVertexShader",
                                                       fragmentFunctionName: "KittyImageFragmentShader",
                                                       blending: iTermMetalBlending.compositeSourceOver(),
                                                       piuElementSize: 0,
                                                       transientStateClass: KittyImageRendererTransientState.self)
        guard let cellRenderer = maybeCellRenderer else {
            return nil
        }
        self.cellRenderer = cellRenderer
    }

    func createTransientStateStat() -> iTermMetalFrameDataStat {
        return .pqCreateImageTS
    }
    
    func draw(with frameData: iTermMetalFrameData, transientState: iTermMetalCellRendererTransientState) {
        guard let tState = transientState as? KittyImageRendererTransientState else {
            return
        }
        let zRange = Range(Int(minZ)...Int(maxZ))
        tState.enumerateOperations(zRange: zRange) { op in
            guard let renderEncoder = frameData.renderEncoder else {
                return
            }
            cellRenderer.draw(with: transientState,
                              renderEncoder: renderEncoder,
                              numberOfVertices: 6,
                              numberOfPIUs: 0,
                              vertexBuffers: [ NSNumber(value: iTermVertexInputIndexVertices.rawValue): op.quad ],
                              fragmentBuffers: [:],
                              textures: [ NSNumber(value: iTermTextureIndexPrimary.rawValue): op.texture ])
        }
    }

    func createTransientState(forCellConfiguration configuration: iTermCellRenderConfiguration, commandBuffer: any MTLCommandBuffer) -> iTermMetalRendererTransientState? {
        let transientState = cellRenderer.createTransientState(forCellConfiguration: configuration,
                                                               commandBuffer: commandBuffer) as! KittyImageRendererTransientState
        initializeTransientState(transientState)
        return transientState
    }

    private func initializeTransientState(_ tState: KittyImageRendererTransientState) {
        tState.cellRenderer = cellRenderer;
        tState.textures = textures;
    }
}
