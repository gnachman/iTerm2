//
//  KittyImage.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/15/24.
//

import Foundation
import Compression
import Darwin
import zlib

@objc(iTermKittyImageControllerDelegate)
protocol KittyImageControllerDelegate: AnyObject {
    func kittyImageControllerReport(message: String)
    func kittyImageControllerPlacementsDidChange()
    func kittyImageControllerCursorCoord() -> VT100GridAbsCoord
    func kittyImageControllerMoveCursor(dx: Int, dy: Int)
    // Note this size is in pixels, not points.
    func kittyImageControllerCellSize() -> NSSize
    func kittyImageControllerScreenAbsLine() -> Int64
}

@objc(iTermKittyImageController)
class KittyImageController: NSObject {
    @objc weak var delegate: KittyImageControllerDelegate?

    private class AutoincrementingNumber {
        private var next = 0
        func allocate() -> Int {
            let value = next
            next += 1
            return value
        }
    }

    fileprivate struct Image {
        private static let autoincrement = AutoincrementingNumber()
        let uniqueId = UUID()
        let sequence = Self.autoincrement.allocate()
        var metadata: KittyImageCommand.ImageTransmission
        var rawData: Data?
        var decompressedData: Data?
        var image: ReferenceContainer<iTermImage?>
        var cost: Int {
            guard let image = image.value else {
                return 0
            }
            return Int(image.size.width * image.size.height * 4) * image.images.count
        }
    }

    fileprivate struct Placement {
        var image: Image
        var placementId: UInt32

        // The key under which this placement's image lives in _images. An image with no id (i=0) is
        // addressed only by its image number and is stored under lastImageKey with metadata.identifier
        // == 0, so its key is not simply its identifier. The delete paths work in _images keys, so
        // they compare against this rather than metadata.identifier.
        var imageKey: UInt64 {
            image.metadata.identifier == 0 ? KittyImageController.lastImageKey : UInt64(image.metadata.identifier)
        }

        struct Displacement {
            var x: Int32
            var y: Int32
        }
        enum Origin {
            // The relative placement can be offset from the parent’s location by a specified number of
            // cells, using the H and V keys for horizontal and vertical displacement. Positive values
            // move right and down. Negative values move left and up. The origin is the top left cell of
            // the parent placement.
            case absolute(VT100GridAbsCoord)
            // To specify that a placement should be relative to another, use the
            // P=<image_id>,Q=<placement_id> keys, when creating the relative placement. For example:
            //
            // <ESC>_Ga=p,i=<image_id>,p=<placement_id>,P=<parent_img_id>,Q=<parent_placement_id><ESC>\
            //
            // This will create a relative placement that refers to the parent placement specified
            // by the P and Q keys. When the parent placement moves, the relative placement moves
            // along with it. The relative placement can be offset from the parent’s location by a
            // specified number of cells, using the H and V keys for horizontal and vertical
            // displacement. Positive values move right and down. Negative values move left and up.
            // The origin is the top left cell of the parent placement.
            case relative(parentPlacementIdentifier: UInt32,
                          parentImageIdentifier: UInt32,
                          displacement: Displacement)
        }
        var origin: Origin
        var parentPlacementIdentifier: UInt32? {
            switch origin {
            case .absolute:
                nil
            case .relative(parentPlacementIdentifier: let ppid, parentImageIdentifier: _, displacement: _):
                ppid
            }
        }

        var parentImageIdentifier: UInt32? {
            switch origin {
            case .absolute:
                nil
            case .relative(parentPlacementIdentifier: _, parentImageIdentifier: let piid, displacement: _):
                piid
            }
        }

        var pixelOffset: NSPoint?

        // The requested source rectangle from the x/y/w/h keys, stored as fractions of the bitmap it
        // was requested against. Resolving multiplies by the current bitmap's pixel size, so
        // retransmitting the image id with a different-sized bitmap samples the same PROPORTIONAL
        // region rather than a stale absolute box, and the region can never fall outside the bitmap.
        // Values are in 0...1 with x+w <= 1 and y+h <= 1.
        //
        // ASSUMPTION (not yet confirmed against a running kitty): this matches kitty, whose
        // ImageRef.src_rect (graphics.c) appears to be stored as fractions. Confirm with
        // tests/kitty-crop-resize-retransmit.sh; if kitty samples absolute pixels instead, revert to
        // absolute-pixel storage clamped at resolve time.
        struct SourceRegion {
            var x: CGFloat
            var y: CGFloat
            var w: CGFloat
            var h: CGFloat
        }
        var sourceRegion: SourceRegion?

        // Resolve the normalized source region against the given bitmap pixel size. Returns nil when
        // no region was requested (meaning the whole image) or the request was empty (zero fraction),
        // which keeps a zero-size (NaN/out-of-bounds) source frame out of the drawing math.
        func resolvedSourceRect(imagePixelSize: NSSize) -> NSRect? {
            guard let region = sourceRegion else {
                return nil
            }
            let rect = NSRect(x: region.x * imagePixelSize.width,
                              y: region.y * imagePixelSize.height,
                              width: region.w * imagePixelSize.width,
                              height: region.h * imagePixelSize.height)
            guard rect.width > 0 && rect.height > 0 else {
                return nil
            }
            return rect
        }

        // Size in cells. If both are nonnil, stretch to fit. If exactly one is nonnil, pick the other
        // to maintain aspect ratio.
        var rows: UInt32?
        var columns: UInt32?

        // Negative values go beneath text.
        // Negative z-index values below INT32_MIN/2 (-1,073,741,824) will be drawn under cells with
        // non-default background colors.
        // If two images with the same z-index overlap then the image with the lower id is
        // considered to have the lower z-index. If the images have the same z-index and the same
        // id, then the behavior is undefined.
        var zIndex: Int32

        // NOTE: Virtual placements can be deleted by a deletion command only when the d key is
        // equal to i, I, r, R, n or N. The key values a, c, p, q, x, y, z and their capital
        // variants never affect virtual placements because they do not have a physical location
        // on the screen
        var virtual: Bool

        // Placement ids are unique per image, not globally, so a placement is identified by the
        // pair (imageId, placementId). The finder takes both.
        typealias PlacementFinder = ((_ imageId: UInt32, _ placementId: UInt32) -> Placement?)

        func parent(finder: PlacementFinder) -> Placement? {
            guard let pid = parentPlacementIdentifier, let iid = parentImageIdentifier else {
                return nil
            }
            return finder(iid, pid)
        }


        func intersects(coord: VT100GridAbsCoord, cellSize: NSSize, finder: PlacementFinder) -> Bool {
            return (intersects(column: coord.x, cellSize: cellSize, finder: finder) &&
                    intersects(row: coord.y, cellSize: cellSize, finder: finder))
        }

        func intersects(column: Int32, cellSize: NSSize, finder: PlacementFinder) -> Bool {
            guard let rect = pixelRect(cellSize: cellSize, finder: finder) else {
                return false
            }
            let myRange: Range<CGFloat> = rect.xRange
            let queryMin: CGFloat = CGFloat(column) * cellSize.width
            let queryMax: CGFloat = CGFloat(column + 1) * cellSize.width
            let queryRange = queryMin..<queryMax
            return myRange.overlaps(queryRange)
        }

        func intersects(row: Int64, cellSize: NSSize, finder: PlacementFinder) -> Bool {
            guard let rect = pixelRect(cellSize: cellSize, finder: finder) else {
                return false
            }
            let myRange = rect.yRange
            let queryMin: CGFloat = CGFloat(row) * cellSize.height
            let queryMax: CGFloat = CGFloat(row + 1) * cellSize.height
            let queryRange = queryMin..<queryMax
            return myRange.overlaps(queryRange)
        }

        private func pixelOrigin(cellSize: NSSize, finder: PlacementFinder) -> NSPoint? {
            let pixelOffset = self.pixelOffset ?? NSPoint.zero
            switch origin {
            case .absolute(let coord):
                return NSPoint(x: CGFloat(coord.x) * cellSize.width + pixelOffset.x,
                               y: CGFloat(coord.y) * cellSize.height + pixelOffset.y)
            case .relative(let parentPlacementIdentifier, let parentImageIdentifier, let displacement):
                guard let parent = finder(parentImageIdentifier, parentPlacementIdentifier) else {
                    return nil
                }
                guard let parentOrigin = parent.pixelOrigin(cellSize: cellSize, finder: finder) else {
                    return nil
                }
                return NSPoint(x: parentOrigin.x + CGFloat(displacement.x) * cellSize.width,
                               y: parentOrigin.y + CGFloat(displacement.y) * cellSize.height)
            }
        }

        // The natural (unscaled) footprint size in pixels, captured when the placement was created.
        // The on-screen footprint of a placement without explicit rows/columns is fixed at creation:
        // the cursor was advanced past it and later output was laid out around it. Retransmitting the
        // image id must scale the new bitmap into that same rect, not relayout the placement, so the
        // footprint is frozen here rather than recomputed from whatever bitmap the placement points
        // at now. (Which texels to sample still resolves against the live bitmap, via sourceRegion.)
        var frozenNaturalSize: NSSize?

        // The footprint size to use for sizing, preferring the frozen value and falling back to a
        // live computation only if it was never captured.
        private func footprintNaturalSize() -> NSSize? {
            return frozenNaturalSize ?? liveNaturalPixelSize()
        }

        // The image's natural size in pixels computed from the image the placement currently points
        // at. Used to capture frozenNaturalSize at creation. When a source region was requested it
        // defines the natural size, because the transmitted s/v dimensions describe the whole bitmap,
        // not the crop; otherwise fall back to s/v, then to the decoded bitmap size. Resolving the
        // region needs the bitmap pixel size, so that lookup comes first.
        func liveNaturalPixelSize() -> NSSize? {
            if sourceRegion != nil,
               let pixelSize = image.image.value?.size,
               let rect = resolvedSourceRect(imagePixelSize: pixelSize) {
                return rect.size
            }
            if image.metadata.width > 0 && image.metadata.height > 0 {
                return NSSize(width: CGFloat(image.metadata.width),
                              height: CGFloat(image.metadata.height))
            }
            return image.image.value?.size
        }

        // In pixels, not points.
        func pixelSize(forCellSize cellSize: NSSize) -> NSSize {
            if let rows, let columns {
                return NSSize(width: cellSize.width * CGFloat(columns),
                              height: cellSize.height * CGFloat(rows))
            }
            if let rows {
                let height = cellSize.height * CGFloat(rows)
                return NSSize(width: pixelWidth(forHeight: height),
                              height: height)
            }
            if let columns {
                let width = cellSize.width * CGFloat(columns)
                return NSSize(width: width,
                              height: pixelHeight(forWidth: width))
            }
            return footprintNaturalSize() ?? NSSize(width: 1, height: 1)
        }

        private func pixelWidth(forHeight height: CGFloat) -> CGFloat {
            guard let natural = footprintNaturalSize(), natural.width > 0, natural.height > 0 else {
                return 0
            }
            let aspectRatio = natural.width / natural.height
            return round(height * aspectRatio)
        }

        private func pixelHeight(forWidth width: CGFloat) -> CGFloat {
            guard let natural = footprintNaturalSize(), natural.width > 0, natural.height > 0 else {
                return 0
            }
            let aspectRatio = natural.width / natural.height
            return round(width / aspectRatio);
        }

        func pixelRect(cellSize: NSSize, finder: PlacementFinder) -> NSRect? {
            guard let pxStart = pixelOrigin(cellSize: cellSize, finder: finder) else {
                return nil
            }
            let pxSize = pixelSize(forCellSize: cellSize)
            return NSRect(origin: pxStart, size: pxSize)
        }

        func absRect(cellSize: NSSize, finder: PlacementFinder) -> VT100GridAbsCoordRange? {
            guard let pixelRect = self.pixelRect(cellSize: cellSize, finder: finder) else {
                return nil
            }
            return VT100GridAbsCoordRange(
                start: VT100GridAbsCoord(x: Int32(clamping: floor(pixelRect.minX / cellSize.width)),
                                         y: Int64(clamping: floor(pixelRect.minY / cellSize.height))),
                end: VT100GridAbsCoord(x: Int32(clamping: ceil(pixelRect.maxX / cellSize.width)),
                                       y: Int64(clamping: ceil(pixelRect.maxY / cellSize.height)) - 1))
        }
    }

    // Stores state for multipart transmissions.
    // Note: decodedData stores already base64-decoded binary data, not the base64 string.
    // This allows senders to base64-encode each chunk independently (which may include
    // padding in non-final chunks) rather than requiring a single base64 stream.
    private struct Accumulator {
        var transmission: KittyImageCommand.ImageTransmission
        var decodedData: Data
        var query: Bool
        var display: KittyImageCommand.ImageDisplay?
    }

    static let defaultImageCacheBudget = 320 * 1024 * 1024

    // Identifier -> Image
    private var _images: LRUDictionary<UInt64, Image>
    // Key under which an image transmitted without an id (i=0, addressed only by its image number I)
    // is stored. Its metadata.identifier is 0, so it cannot be its own key. Static so Placement can
    // derive its own _images key (see Placement.imageKey).
    fileprivate static let lastImageKey = UInt64(UInt32.max) + 1
    private var accumulator: Accumulator?
    private var placements = [Placement]()

    @objc override init() {
        _images = LRUDictionary<UInt64, Image>(maximumSize: Self.defaultImageCacheBudget)
        super.init()
    }

    // Construct with a specific image-cache budget. Production uses init() (the default budget); tests
    // pass a small budget so eviction can be exercised deterministically.
    init(imageCacheBudget: Int) {
        _images = LRUDictionary<UInt64, Image>(maximumSize: imageCacheBudget)
        super.init()
    }

    // Whether a placement with the given image id and placement id exists, regardless of whether it
    // currently resolves to a drawable position (draws() only reports visible ones). Used by tests to
    // observe placements that are present but not currently drawable; read-only, no side effects.
    func hasPlacement(imageID: UInt32, placementID: UInt32) -> Bool {
        return placements.contains { $0.image.metadata.identifier == imageID && $0.placementId == placementID }
    }

    @objc(executeCommand:)
    func execute(command: KittyImageCommand) {
        DLog("execute(command:) BEGIN - category=\(command.category) action=\(command.action) payloadLength=\(command.payload.count)")
        switch command.category {
        case .imageTransmission(let imageTransmission):
            DLog("execute: .imageTransmission - id=\(imageTransmission.identifier) (0x\(String(imageTransmission.identifier, radix: 16))) imageNumber=\(imageTransmission.imageNumber) more=\(imageTransmission.more) medium=\(imageTransmission.medium) format=\(imageTransmission.format) compression=\(imageTransmission.compression) width=\(imageTransmission.width) height=\(imageTransmission.height) verbosity=\(imageTransmission.verbosity)")
            let result = executeTransmit(imageTransmission,
                                display: nil,
                                payload: command.payload,
                                query: command.action == .query)
            DLog("execute: .imageTransmission completed - result=\(result)")
        case .imageDisplay(let imageDisplay):
            DLog("execute: .imageDisplay - id=\(imageDisplay.identifier) (0x\(String(imageDisplay.identifier, radix: 16))) placement=\(imageDisplay.placement) createUnicodePlaceholder=\(imageDisplay.createUnicodePlaceholder) rows=\(imageDisplay.r) cols=\(imageDisplay.c) q=\(imageDisplay.q)")
            executeDisplay(imageDisplay)
        case .transmitAndDisplay(let imageTransmission, let imageDisplay):
            DLog("execute: .transmitAndDisplay - transmit.id=\(imageTransmission.identifier) (0x\(String(imageTransmission.identifier, radix: 16))) transmit.imageNumber=\(imageTransmission.imageNumber) transmit.more=\(imageTransmission.more) transmit.medium=\(imageTransmission.medium) transmit.format=\(imageTransmission.format) transmit.compression=\(imageTransmission.compression) transmit.verbosity=\(imageTransmission.verbosity)")
            DLog("execute: .transmitAndDisplay - display.id=\(imageDisplay.identifier) (0x\(String(imageDisplay.identifier, radix: 16))) display.placement=\(imageDisplay.placement) display.createUnicodePlaceholder=\(imageDisplay.createUnicodePlaceholder) display.rows=\(imageDisplay.r) display.cols=\(imageDisplay.c) display.q=\(imageDisplay.q)")
            let hadAccumulator = (accumulator != nil)
            let savedDisplay = accumulator?.display
            DLog("execute: .transmitAndDisplay - hadAccumulator=\(hadAccumulator) savedDisplay=\(String(describing: savedDisplay))")
            let transmitResult = executeTransmit(imageTransmission, display: imageDisplay, payload: command.payload, query: false)
            DLog("execute: .transmitAndDisplay - executeTransmit returned \(transmitResult)")
            if transmitResult {
                if (imageTransmission.more == .finalChunk) {
                    if let savedDisplay {
                        // If transmission was split up into multiple parts use the display commands
                        // from the first part.
                        DLog("execute: .transmitAndDisplay - calling executeDisplay with savedDisplay")
                        executeDisplay(savedDisplay)
                    } else {
                        DLog("execute: .transmitAndDisplay - calling executeDisplay with imageDisplay")
                        executeDisplay(imageDisplay)
                    }
                } else if !hadAccumulator, let accumulator, accumulator.display == nil {
                    // This is the first part of a multipart transmitAndDisplay. Save the display
                    // params in the accumulator.
                    DLog("execute: .transmitAndDisplay - saving display params to accumulator for multipart transmission")
                    self.accumulator?.display = imageDisplay
                } else {
                    DLog("execute: .transmitAndDisplay - not calling executeDisplay (more=\(imageTransmission.more), hadAccumulator=\(hadAccumulator))")
                }
            } else {
                DLog("execute: .transmitAndDisplay - executeTransmit failed, not calling executeDisplay")
            }
        case .animationFrameLoading(let animationFrameLoading):
            DLog("execute: .animationFrameLoading")
            executeLoadAnimationFrame(animationFrameLoading)
        case .animationFrameComposition(let animationFrameComposition):
            DLog("execute: .animationFrameComposition")
            executeComposeAnimationFrame(animationFrameComposition)
        case .animationControl(let animationControl):
            DLog("execute: .animationControl")
            executeControlAnimation(animationControl)
        case .deleteImage(let deleteImage):
            DLog("execute: .deleteImage - d='\(deleteImage.d)' imageId=\(deleteImage.imageId) placementId=\(deleteImage.placementId)")
            executeDeleteImage(deleteImage)
        }
        DLog("execute(command:) END")
    }

    @objc
    func clear() {
        RLog("clear(): removing all images and \(placements.count) placements")
        _images.removeAll()
        accumulator = nil
        let hadPlacements = !placements.isEmpty
        placements = []
        if hadPlacements {
            delegate?.kittyImageControllerPlacementsDidChange()
        }
    }

    // MARK: - Transmit

    private func allocateIdentifier() -> UInt32 {
        for i in 1..<UInt32.max {
            if _images[UInt64(i)] == nil {
                return i
            }
        }
        return 0
    }

    private func executeTransmit(_ command: KittyImageCommand.ImageTransmission,
                                 display: KittyImageCommand.ImageDisplay?,
                                 payload: String,
                                 query: Bool) -> Bool {
        DLog("executeTransmit BEGIN - id=\(command.identifier) (0x\(String(command.identifier, radix: 16))) imageNumber=\(command.imageNumber) more=\(command.more) allocationAllowed=\(command.allocationAllowed) query=\(query) payloadLength=\(payload.count) hasDisplay=\(display != nil)")
        var modifiedCommand = command

        if command.allocationAllowed && command.imageNumber > 0 {
            // Have not yet recursed after allocating an image ID.
            DLog("executeTransmit: allocationAllowed && imageNumber > 0, checking identifier")
            if command.identifier > 0 {
                RLog("executeTransmit: ERROR - both i and I specified")
                respondToTransmit(command, display: display, error: "EINVAL:Can't give both i and I")
                return false
            }

            // Rewrite command to have an identifier and recurse.
            modifiedCommand.identifier = allocateIdentifier()
            DLog("executeTransmit: allocated identifier=\(modifiedCommand.identifier)")
            if modifiedCommand.identifier == 0 {
                RLog("executeTransmit: ERROR - out of identifiers")
                respondToTransmit(command, display: display, error: "ENOSPC:Out of identifiers")
                return false
            }
            modifiedCommand.allocationAllowed = false
        }

        DLog("executeTransmit: calling reallyExecuteTransmit with id=\(modifiedCommand.identifier) (0x\(String(modifiedCommand.identifier, radix: 16)))")
        let error = reallyExecuteTransmit(modifiedCommand, payload: payload, query: query)
        DLog("executeTransmit: reallyExecuteTransmit returned error=\(String(describing: error))")
        if error != nil || display == nil {
            DLog("executeTransmit: calling respondToTransmit (error=\(String(describing: error)), display=\(display == nil ? "nil" : "present"))")
            respondToTransmit(modifiedCommand, display: display, error: error)
        }
        let result = error == nil
        DLog("executeTransmit END - returning \(result)")
        return result
    }

    private func reallyExecuteTransmit(_ command: KittyImageCommand.ImageTransmission,
                                       payload: String,
                                       query: Bool,
                                       preDecodedData: Data? = nil) -> String? {
        DLog("reallyExecuteTransmit BEGIN - id=\(command.identifier) (0x\(String(command.identifier, radix: 16))) more=\(command.more) medium=\(command.medium) format=\(command.format) query=\(query) payloadLength=\(payload.count)")
        DLog("reallyExecuteTransmit: current accumulator state: \(accumulator == nil ? "nil" : "exists with id=\(accumulator!.transmission.identifier) (0x\(String(accumulator!.transmission.identifier, radix: 16))) decodedDataLength=\(accumulator!.decodedData.count) hasDisplay=\(accumulator!.display != nil)")")

        if let accumulator {
            // Validate this chunk belongs to the same image transmission.
            // Only reject if both have non-zero IDs that don't match.
            let idsMatch: Bool
            if command.identifier != 0 && accumulator.transmission.identifier != 0 {
                // Both have IDs - must match exactly
                idsMatch = command.identifier == accumulator.transmission.identifier
                DLog("reallyExecuteTransmit: both have non-zero IDs, idsMatch=\(idsMatch) (cmd.id=\(command.identifier) vs accum.id=\(accumulator.transmission.identifier))")
            } else {
                // At least one ID is 0 - assume they match (can't verify otherwise)
                idsMatch = true
                DLog("reallyExecuteTransmit: at least one ID is 0, assuming match (cmd.id=\(command.identifier), accum.id=\(accumulator.transmission.identifier))")
            }

            if !idsMatch {
                // Clear the abandoned accumulator. If the new command is a final chunk,
                // it's likely a new single-chunk transmission, so process it fresh rather
                // than returning an error. If it's expecting more chunks, return an error
                // since we can't know which transmission it belongs to.
                RLog("reallyExecuteTransmit: IDs don't match - clearing stale accumulator (accum.id=\(accumulator.transmission.identifier) (0x\(String(accumulator.transmission.identifier, radix: 16))), accum.decodedDataLength=\(accumulator.decodedData.count), cmd.id=\(command.identifier) (0x\(String(command.identifier, radix: 16))), cmd.more=\(command.more))")
                self.accumulator = nil
                if command.more == .expectMore {
                    DLog("reallyExecuteTransmit: returning error because new chunk expects more but accumulator was stale")
                    return "EINVAL:Image ID mismatch in chunked transmission"
                }
                DLog("reallyExecuteTransmit: falling through to process as new single-chunk transmission")
                // Fall through to process as a new single-chunk transmission
            } else {
                // Decode this chunk's base64 and append to accumulated data.
                // This allows senders to base64-encode each chunk independently
                // (which may include padding in non-final chunks).
                guard let chunkData = payload.base64DecodedData else {
                    DLog("reallyExecuteTransmit: ERROR - could not decode chunk payload (length=\(payload.count))")
                    self.accumulator = nil
                    return "EINVAL:could not decode payload chunk"
                }

                if command.more == .expectMore {
                    DLog("reallyExecuteTransmit: appending decoded chunk to accumulator (chunkBytes=\(chunkData.count), new total bytes=\(accumulator.decodedData.count + chunkData.count))")
                    self.accumulator?.decodedData += chunkData
                    DLog("reallyExecuteTransmit END - returning nil (accumulating)")
                    return nil
                }

                // Processing final chunk of accumulated transmission
                DLog("reallyExecuteTransmit: processing final chunk of accumulated transmission")
                let combinedData = accumulator.decodedData + chunkData
                let display = accumulator.display
                let accumulatedDataLength = accumulator.decodedData.count
                self.accumulator = nil
                var modifiedCommand = accumulator.transmission
                modifiedCommand.more = .finalChunk

                DLog("reallyExecuteTransmit: recursing with pre-decoded data (accum.bytes=\(accumulatedDataLength) + chunk.bytes=\(chunkData.count) = \(combinedData.count))")
                let result = reallyExecuteTransmit(modifiedCommand,
                                                   payload: "",
                                                   query: accumulator.query,
                                                   preDecodedData: combinedData)
                DLog("reallyExecuteTransmit: recursive call returned error=\(String(describing: result))")

                // If transmission succeeded and we have saved display parameters, execute display
                if result == nil, let display {
                    DLog("reallyExecuteTransmit: transmission succeeded, executing saved display params")
                    // Use lastImageKey when identifier is 0, matching storage behavior in transmissionDidFinish
                    let imageKey = modifiedCommand.identifier != 0 ? UInt64(modifiedCommand.identifier) : Self.lastImageKey
                    if let image = _images[imageKey] {
                        DLog("reallyExecuteTransmit: found image for key=\(imageKey) (id=\(modifiedCommand.identifier)), calling executeDisplay")
                        let displayError = executeDisplay(display, image: image)
                        if displayError != nil {
                            // Return display error as the overall error
                            DLog("reallyExecuteTransmit: executeDisplay returned error=\(String(describing: displayError))")
                            respondToTransmit(modifiedCommand, display: display, error: displayError)
                            return displayError
                        }
                        // Send the combined response for successful transmit+display
                        DLog("reallyExecuteTransmit: executeDisplay succeeded, sending response")
                        respondToTransmit(modifiedCommand, display: display, error: nil)
                    } else {
                        let error = "ENOENT:Image not found after transmission"
                        RLog("reallyExecuteTransmit: ERROR - image not found for key=\(imageKey) (id=\(modifiedCommand.identifier)) after transmission")
                        respondToTransmit(modifiedCommand, display: display, error: error)
                        return error
                    }
                }

                DLog("reallyExecuteTransmit END - returning result from recursive call: \(String(describing: result))")
                return result
            }
        } else if command.more == .expectMore {
            // First chunk of a new multipart transmission - decode and start accumulating
            guard let chunkData = payload.base64DecodedData else {
                DLog("reallyExecuteTransmit: ERROR - could not decode first chunk payload (length=\(payload.count))")
                return "EINVAL:could not decode payload chunk"
            }
            DLog("reallyExecuteTransmit: no accumulator and more expected, creating new accumulator with id=\(command.identifier) (0x\(String(command.identifier, radix: 16))) decodedBytes=\(chunkData.count)")
            accumulator = Accumulator(transmission: command, decodedData: chunkData, query: query)
            DLog("reallyExecuteTransmit END - returning nil (new accumulator created)")
            return nil
        }

        DLog("reallyExecuteTransmit: processing single-chunk transmission via medium=\(command.medium)")
        let result: String?
        switch command.medium {
        case .direct:
            result = executeTransmitDirect(command, payload: payload, query: query, preDecodedData: preDecodedData)
        case .file:
            result = executeTransmitFile(command, payload: payload, query: query)
        case .temporaryFile:
            result = executeTransmitTemporaryFile(command, payload: payload, query: query)
        case .sharedMemory:
            result = executeTransmitSharedMemory(command, payload: payload, query: query)
        }
        DLog("reallyExecuteTransmit END - medium handler returned error=\(String(describing: result))")
        return result
    }

    // Direct (the data is transmitted within the escape code itself)
    // preDecodedData is used for multipart transmissions where chunks were already base64-decoded during accumulation.
    private func executeTransmitDirect(_ command: KittyImageCommand.ImageTransmission,
                                       payload: String,
                                       query: Bool,
                                       preDecodedData: Data? = nil) -> String? {
        DLog("executeTransmitDirect BEGIN - id=\(command.identifier) (0x\(String(command.identifier, radix: 16))) format=\(command.format) compression=\(command.compression) payloadLength=\(payload.count) preDecodedDataLength=\(preDecodedData?.count ?? 0)")
        let data: Data
        if let preDecodedData {
            // Multipart transmission: data was already base64-decoded during chunk accumulation
            if command.compression == .zlib {
                guard let decompressed = inflate(data: preDecodedData) else {
                    DLog("executeTransmitDirect: ERROR - could not decompress pre-decoded data (length=\(preDecodedData.count))")
                    return "could not decompress payload"
                }
                data = decompressed
            } else {
                data = preDecodedData
            }
        } else {
            // Single-chunk transmission: decode base64 (and decompress if needed)
            guard let decoded = decodeDirectTransmission(command, payload: payload) else {
                DLog("executeTransmitDirect: ERROR - could not decode payload (payloadLength=\(payload.count), compression=\(command.compression))")
                return "could not decode payload"
            }
            data = decoded
        }
        DLog("executeTransmitDirect: decoded payload to \(data.count) bytes")
        let result = handle(command: command, data: data, query: query)
        DLog("executeTransmitDirect END - handle returned error=\(String(describing: result))")
        return result
    }

    private func handle(command: KittyImageCommand.ImageTransmission,
                        data: Data,
                        query: Bool) -> String? {
        DLog("handle BEGIN - id=\(command.identifier) (0x\(String(command.identifier, radix: 16))) format=\(command.format) dataLength=\(data.count) width=\(command.width) height=\(command.height)")
        let image = switch command.format {
        case .raw24:
            image(data: data, bpp: 3, width: command.width, height: command.height)
        case .raw32:
            image(data: data, bpp: 4, width: command.width, height: command.height)
        case .png:
            iTermImage.init(compressedData: data)
        }
        guard let image else {
            RLog("handle: ERROR - invalid payload, could not create image (format=\(command.format), dataLength=\(data.count))")
            return "invalid payload"
        }
        DLog("handle: created image with size=\(image.size)")
        transmissionDidFinish(image: Image(metadata: command, image: ReferenceContainer(image)),
                              query: query)
        DLog("handle END - success")
        return nil
    }

    private func transmissionDidFinish(image: Image, query: Bool) {
        // Coalesce placements-changed notifications: eviction and re-pointing each mutate placements,
        // but a single transmission should post one notification, not one per step. Each redundant
        // notification triggers a full draws() rebuild plus a redraw request in the delegate.
        var changed = false
        if !query && image.metadata.identifier != 0 {
            DLog("transmissionDidFinish: storing image with identifier=\(image.metadata.identifier) (0x\(String(image.metadata.identifier, radix: 16))) cost=\(image.cost)")
            let evicted = handleEvictions(_images.insert(key: UInt64(image.metadata.identifier), value: image, cost: image.cost))
            let repointed = repointPlacements(toReplacementImage: image)
            changed = evicted || repointed
        } else {
            DLog("transmissionDidFinish: storing image with lastImageKey (query=\(query), identifier=\(image.metadata.identifier))")
            changed = handleEvictions(_images.insert(key: Self.lastImageKey, value: image, cost: image.cost))
        }
        DLog("transmissionDidFinish: total images in cache: \(_images.keys.count)")
        if changed {
            delegate?.kittyImageControllerPlacementsDidChange()
        }
    }

    // Returns whether any placements were removed.
    private func handleEvictions(_ kvps: [(UInt64, Image)]) -> Bool {
        var removedAny = false
        for kvp in kvps {
            kvp.1.image.value = nil
            // Drop the evicted image's OWN placements so they cannot resurrect via repointPlacements
            // when the id is later reused (their bitmap is gone and they can never draw again). Match
            // on the evicted Image's unique id, NOT its cache key: several id-less images share the
            // single lastImageKey slot, so keying on the slot would also remove the still-drawable
            // placements of earlier id-less images whose bitmaps are still alive. Do NOT use the
            // relative-child cascade here: eviction is internal memory pressure, not a user delete, so
            // it must not remove a live placement of a different, still-resident image just because it
            // was positioned relative to the evicted one (that child simply becomes unanchored until
            // its parent is displayed again). An explicit a=d delete does cascade.
            let indexes = placements.indexes { $0.image.uniqueId == kvp.1.uniqueId }
            if !indexes.isEmpty {
                placements.remove(at: indexes)
                removedAny = true
            }
        }
        return removedAny
    }

    // A placement captures the Image value that existed when it was displayed. When a program
    // retransmits under an image id that is already in use, a VIRTUAL placement (referenced by
    // Unicode placeholder cells) is a live reference to (imageID, placementID) and must reflect the
    // new bitmap, so we re-point virtual placements at it. This is the case issue 13028 is about, and
    // kitty renders it that way (confirmed: tests/kitty-stale-placement.sh).
    //
    // NON-virtual placements are deliberately NOT re-pointed: they were drawn at a fixed position as a
    // snapshot (the cursor advanced past them and later output, including scrollback, was laid out
    // around them). Re-pointing them would retroactively rewrite scrollback history -- a program that
    // reuses one id for a sequence of pictures (icat/frame tools hardcoding i=1) would have its whole
    // scrollback of that id collapse to the newest bitmap. They keep their captured bitmap instead.
    //
    // Returns whether any placement was re-pointed. Id-less images (identifier 0) are never
    // re-pointed because they cannot be retransmitted (there is no id to retransmit under).
    private func repointPlacements(toReplacementImage image: Image) -> Bool {
        let identifier = image.metadata.identifier
        // Only swap the image on virtual placements. A placement's requested source region is stored
        // normalized and resolved against the current bitmap at draw time, so it adapts to the new
        // bitmap's size without any destructive rewriting here.
        var changed = false
        for i in placements.indices where placements[i].virtual && placements[i].image.metadata.identifier == identifier {
            placements[i].image = image
            changed = true
        }
        if changed {
            DLog("repointPlacements: re-pointed virtual placements of imageID=\(identifier) at the newly transmitted bitmap")
        }
        return changed
    }

    private func dataByAddingAlphaTo3bppData(_ data: Data, _ alpha: UInt8) -> Data {
        var rgbaData = Data(capacity: (data.count / 3) * 4)
        for i in stride(from: 0, to: data.count, by: 3) {
            rgbaData.append(contentsOf: data[i..<i+3])
            rgbaData.append(alpha)
        }
        return rgbaData
    }

    private func image(data rawData: Data, bpp: UInt, width: UInt, height: UInt) -> iTermImage? {
        DLog("image(data:bpp:width:height:): rawDataLength=\(rawData.count) bpp=\(bpp) width=\(width) height=\(height)")
        guard bpp == 3 || bpp == 4 else {
            DLog("image(data:bpp:width:height:): FAILED - invalid bpp=\(bpp) (must be 3 or 4)")
            return nil
        }

        let bytesPerPixel = 4
        let bytesPerRow = Int(clamping: width) * bytesPerPixel
        let unpaddedBytes = Int(clamping: bpp) * Int(clamping: width) * Int(clamping: height)

        guard rawData.count >= unpaddedBytes else {
            DLog("image(data:bpp:width:height:): FAILED - data too short: have \(rawData.count) bytes, need \(unpaddedBytes) bytes (bpp=\(bpp) * width=\(width) * height=\(height))")
            return nil
        }
        var data = rawData
        data.count = unpaddedBytes

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo: CGBitmapInfo = [.byteOrder32Big, CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)]

        let rgbaData =
            if bpp == 4 {
                data
            } else {
                dataByAddingAlphaTo3bppData(data, 0xff)
            }

        guard let provider = CGDataProvider(data: rgbaData as CFData) else {
            DLog("image(data:bpp:width:height:): FAILED - could not create CGDataProvider")
            return nil
        }

        let cgImage = CGImage(
            width: Int(clamping: width),
            height: Int(clamping: height),
            bitsPerComponent: 8,
            bitsPerPixel: bytesPerPixel * 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent)

        guard let cgImage else {
            DLog("image(data:bpp:width:height:): FAILED - CGImage creation failed (width=\(width), height=\(height), bytesPerRow=\(bytesPerRow))")
            return nil
        }

        let nsimage = NSImage(cgImage: cgImage, size: NSSize(width: Int(width), height: Int(height)))
        DLog("image(data:bpp:width:height:): success - created image \(width)x\(height)")
        return iTermImage(nativeImage: nsimage)
    }

    private func decodeDirectTransmission(_ command: KittyImageCommand.ImageTransmission, payload: String) -> Data? {
        DLog("decodeDirectTransmission: compression=\(command.compression) payloadLength=\(payload.count)")
        let result: Data?
        switch command.compression {
        case .zlib:
            result = decompressAndDecode(payload)
        case .uncompressed:
            result = decode(payload)
        }
        if let result {
            DLog("decodeDirectTransmission: success - decodedLength=\(result.count)")
        } else {
            DLog("decodeDirectTransmission: FAILED to decode payload")
        }
        return result
    }

    func inflate(data compressedData: Data) -> Data? {
        DLog("inflate: compressedDataLength=\(compressedData.count)")
        var z = z_stream()
        z.zalloc = nil
        z.zfree = nil
        z.opaque = nil
        z.avail_in = uInt(compressedData.count)
        compressedData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            z.next_in = UnsafeMutablePointer<Bytef>(mutating: ptr.bindMemory(to: Bytef.self).baseAddress)
        }

        // Initial buffer allocation
        var decompressedData = Data()
        let bufferSize = 16384
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer {
            buffer.deallocate()
        }

        // Initialize the zlib stream
        let initResult = inflateInit_(&z, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        if initResult != Z_OK {
            DLog("inflate: FAILED inflateInit - result=\(initResult)")
            return nil
        }

        // Decompress the data
        var result: Int32
        repeat {
            z.next_out = buffer
            z.avail_out = uInt(bufferSize)

            result = zlib.inflate(&z, Z_NO_FLUSH)

            if result == Z_STREAM_ERROR || result == Z_DATA_ERROR || result == Z_MEM_ERROR {
                DLog("inflate: FAILED during decompression - result=\(result) (Z_STREAM_ERROR=\(Z_STREAM_ERROR), Z_DATA_ERROR=\(Z_DATA_ERROR), Z_MEM_ERROR=\(Z_MEM_ERROR))")
                inflateEnd(&z)
                return nil
            }

            let bytesDecompressed = bufferSize - Int(z.avail_out)
            decompressedData.append(buffer, count: bytesDecompressed)

        } while result != Z_STREAM_END

        // Clean up
        inflateEnd(&z)

        DLog("inflate: success - decompressedLength=\(decompressedData.count)")
        return decompressedData
    }

    private func decompressAndDecode(_ payload: String) -> Data? {
        DLog("decompressAndDecode: payloadLength=\(payload.count)")
        guard let compressed = payload.base64DecodedData else {
            let prefix = String(payload.prefix(20))
            let suffix = String(payload.suffix(20))
            let paddingNeeded = (4 - (payload.count % 4)) % 4
            DLog("decompressAndDecode: FAILED base64 decode - length=\(payload.count) mod4=\(payload.count % 4) paddingNeeded=\(paddingNeeded) prefix=\(prefix) suffix=\(suffix)")
            return nil
        }
        DLog("decompressAndDecode: base64 decoded to \(compressed.count) bytes, calling inflate")
        let result = inflate(data: compressed)
        if result == nil {
            DLog("decompressAndDecode: inflate returned nil")
        }
        return result
    }

    private func decode(_ payload: String) -> Data? {
        let result = payload.base64DecodedData
        if result == nil {
            let prefix = String(payload.prefix(20))
            let suffix = String(payload.suffix(20))
            let paddingNeeded = (4 - (payload.count % 4)) % 4
            DLog("decode: FAILED - length=\(payload.count) mod4=\(payload.count % 4) paddingNeeded=\(paddingNeeded) prefix=\(prefix) suffix=\(suffix)")
        }
        return result
    }

    func executeTransmitFile(_ command: KittyImageCommand.ImageTransmission,
                             payload: String,
                             query: Bool) -> String? {
        DLog("executeTransmitFile: id=\(command.identifier) (0x\(String(command.identifier, radix: 16))) payloadLength=\(payload.count)")
        let fileURL = URL(fileURLWithPath: payload.base64Decoded ?? "").resolvingSymlinksInPath().standardizedFileURL.absoluteURL
        DLog("executeTransmitFile: fileURL=\(fileURL.path)")
        return handle(command: command, fileURL: fileURL, query: query)
    }

    func executeTransmitTemporaryFile(_ command: KittyImageCommand.ImageTransmission,
                                      payload: String,
                                      query: Bool) -> String? {
        DLog("executeTransmitTemporaryFile: id=\(command.identifier) (0x\(String(command.identifier, radix: 16))) payloadLength=\(payload.count)")
        let tempPath = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let fileURL = URL(fileURLWithPath: payload.base64Decoded ?? "").resolvingSymlinksInPath().standardizedFileURL.absoluteURL
        DLog("executeTransmitTemporaryFile: fileURL=\(fileURL.path) tempPath=\(tempPath)")
        if !fileURL.path.hasPrefix("/tmp/") && !fileURL.path.hasPrefix(tempPath) {
            RLog("executeTransmitTemporaryFile: ERROR - invalid filename (not in /tmp/ or tempPath)")
            return "EBADF:Invalid filename"
        }
        guard fileURL.path.contains("tty-graphics-protocol") else {
            RLog("executeTransmitTemporaryFile: ERROR - bad filename (missing tty-graphics-protocol)")
            return "EBADF:Bad filename"
        }
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        return handle(command: command, fileURL: fileURL, query: query)
    }

    private func filenameIsSafe(fileURL: URL) -> Bool {
        let path = fileURL.path

        // Sensitive directories - block the directory itself and anything inside it.
        // The path has already been canonicalized via resolvingSymlinksInPath().standardizedFileURL
        // so we don't need to worry about /usr/../dev or //dev tricks.
        let sensitiveDirs = [
            "/dev",
            "/System",
            "/private/var/db",
            "/private/etc",
            "/private/var/root",
            "/Library/Keychains"
        ]

        for dir in sensitiveDirs {
            // Block /dev, /dev/, and /dev/anything but not /developer
            if path == dir || path.hasPrefix(dir + "/") {
                return false
            }
        }

        // .ssh can appear anywhere in user home directories (e.g., /Users/foo/.ssh/)
        if path.contains("/.ssh/") || path.hasSuffix("/.ssh") {
            return false
        }

        return true
    }

    private func handle(command: KittyImageCommand.ImageTransmission,
                        fileURL: URL,
                        query: Bool) -> String? {
        DLog("handle(fileURL) BEGIN - id=\(command.identifier) (0x\(String(command.identifier, radix: 16))) fileURL=\(fileURL.path)")
        do {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                DLog("handle(fileURL): ERROR - not a regular file")
                return "EBADF:Not a file"
            }
            guard filenameIsSafe(fileURL: fileURL) else {
                RLog("handle(fileURL): ERROR - unsafe filename")
                return "EBADF:Invalid path"
            }
            let content = try Data(contentsOf: fileURL)
            DLog("handle(fileURL): read \(content.count) bytes from file")
            return handle(command: command, data: content, query: query)
        } catch {
            RLog("handle(fileURL): ERROR - \(error.localizedDescription)")
            return "EBADF:\(error.localizedDescription)"
        }
    }

    func executeTransmitSharedMemory(_ command: KittyImageCommand.ImageTransmission,
                                     payload: String,
                                     query: Bool) -> String? {
        DLog("executeTransmitSharedMemory: id=\(command.identifier) (0x\(String(command.identifier, radix: 16))) payloadLength=\(payload.count)")
        do {
            guard let name = payload.base64Decoded else {
                RLog("executeTransmitSharedMemory: ERROR - invalid name (base64 decode failed)")
                return "EBADF:Invalid name"
            }
            DLog("executeTransmitSharedMemory: shm name=\(name)")
            let data = try readPOSIXSharedMemory(named: name)
            DLog("executeTransmitSharedMemory: read \(data.count) bytes from shared memory")
            return handle(command: command, data: data, query: query)
        } catch {
            RLog("executeTransmitSharedMemory: ERROR - \(error.localizedDescription)")
            return "EBADF:\(error.localizedDescription)"
        }
    }

    /// Reads a POSIX shared memory object and then unlinks and closes it.
    /// - Parameter name: The shm object name, with or without a leading "/".
    /// - Returns: The contents as `Data`.
    /// - Throws: A POSIX error if any step fails.
    func readPOSIXSharedMemory(named name: String) throws -> Data {
        let fd = FileManager.default.it_shmOpen(name, oflag: O_RDONLY, mode: 0)
        if fd == -1 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL)
        }

        var unlinkDone = false
        defer {
            if !unlinkDone {
                _ = shm_unlink(name)
            }
            _ = close(fd)
        }

        var st = stat()
        if fstat(fd, &st) == -1 {
            let err = errno
            _ = shm_unlink(name)
            unlinkDone = true
            throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EINVAL)
        }

        let size = Int(st.st_size)
        if size == 0 {
            _ = shm_unlink(name)
            unlinkDone = true
            return Data()
        }

        let ptr = mmap(nil, size, PROT_READ, MAP_SHARED, fd, 0)
        if ptr == MAP_FAILED {
            let err = errno
            _ = shm_unlink(name)
            unlinkDone = true
            throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EINVAL)
        }

        defer {
            _ = munmap(ptr, size)
        }

        let data = Data(bytes: ptr!, count: size)

        _ = shm_unlink(name)
        unlinkDone = true

        return data
    }
    func respondToTransmit(_ imageTransmission: KittyImageCommand.ImageTransmission,
                            display: KittyImageCommand.ImageDisplay?,
                            error: String?) {
        DLog("respondToTransmit: id=\(imageTransmission.identifier) (0x\(String(imageTransmission.identifier, radix: 16))) more=\(imageTransmission.more) verbosity=\(imageTransmission.verbosity) error=\(String(describing: error))")
        if imageTransmission.more == .expectMore {
            // This is undocumented by the spec.
            DLog("respondToTransmit: more=expectMore, not sending response")
            return
        }
        var args = [String]()
        args.append("i=\(imageTransmission.identifier)")
        if imageTransmission.imageNumber > 0 {
            args.append("I=\(imageTransmission.imageNumber)")
        }
        if let p = display?.placement {
            args.append("p=\(p)")
        }
        let semi = args.isEmpty ? "" : ";"
        let payload = args.joined(separator: ",") + semi + (error ?? "OK")
        let message = "\u{1B}_G\(payload)\u{1B}\\"

        switch imageTransmission.verbosity {
        case .normal:
            DLog("respondToTransmit: verbosity=normal, sending response: \(payload)")
            delegate?.kittyImageControllerReport(message: message)
        case .query:
            if error != nil {
                DLog("respondToTransmit: verbosity=query with error, sending response: \(payload)")
                delegate?.kittyImageControllerReport(message: message)
            } else {
                DLog("respondToTransmit: verbosity=query with no error, NOT sending response")
            }
            return
        case .quiet:
            DLog("respondToTransmit: verbosity=quiet, NOT sending response (error would have been: \(String(describing: error)))")
            return
        }
    }

    // MARK: - Display

    func executeDisplay(_ command: KittyImageCommand.ImageDisplay) {
        DLog("executeDisplay BEGIN - identifier=\(command.identifier) (0x\(String(command.identifier, radix: 16))) placement=\(command.placement) createUnicodePlaceholder=\(command.createUnicodePlaceholder) rows=\(command.r) cols=\(command.c) q=\(command.q)")
        DLog("executeDisplay: _images has \(_images.keys.count) images, keys=\(_images.keys.map { "0x\(String($0, radix: 16))" })")
        if command.identifier != 0 {
            // The spec alludes to multiple images having the same ID but doesn't say what to do
            // when you try to display that ID ("Delete newest image with the specified number…")
            if let image = _images[UInt64(command.identifier)] {
                DLog("executeDisplay: found image for identifier=\(command.identifier) (0x\(String(command.identifier, radix: 16))), imageSize=\(image.image.value?.size ?? .zero)")
                let displayError = executeDisplay(command, image: image)
                DLog("executeDisplay: executeDisplay(command, image:) returned error=\(String(describing: displayError))")
                respondToDisplay(error: displayError,
                                 identifier: command.identifier,
                                 placement: command.placement,
                                 q: command.q)
            } else {
                RLog("executeDisplay: NO IMAGE FOUND for identifier=\(command.identifier) (0x\(String(command.identifier, radix: 16))) - available keys: \(_images.keys.map { "0x\(String($0, radix: 16))" })")
                respondToDisplay(error: "ENOENT:Put command refers to non-existent image with id: \(command.identifier) and number: 0",
                                 identifier: command.identifier,
                                 placement: command.placement,
                                 q: command.q)
            }
        } else if let lastImage = _images[Self.lastImageKey] {
            DLog("executeDisplay: using lastImage (identifier=\(lastImage.metadata.identifier) (0x\(String(lastImage.metadata.identifier, radix: 16))))")
            let displayError = executeDisplay(command, image: lastImage)
            DLog("executeDisplay: executeDisplay(command, image:) returned error=\(String(describing: displayError))")
            respondToDisplay(error: displayError,
                             identifier: command.identifier,
                             placement: command.placement,
                             q: command.q)
        } else {
            DLog("executeDisplay: no identifier specified and no lastImage available - available keys: \(_images.keys.map { "0x\(String($0, radix: 16))" })")
        }
        DLog("executeDisplay END")
    }

    private func executeDisplay(_ command: KittyImageCommand.ImageDisplay,
                                image: Image) -> String? {
        DLog("executeDisplay(image) BEGIN - imageID=\(image.metadata.identifier) (0x\(String(image.metadata.identifier, radix: 16))) placementID=\(command.placement) virtual=\(command.createUnicodePlaceholder == .createPlaceholder) imageSize=\(image.image.value?.size ?? .zero)")
        guard let delegate else {
            DLog("executeDisplay(image): ERROR - no delegate")
            return "Client unavailable"
        }
        let pixelOffset: NSPoint? =
            if command.X > 0 || command.Y > 0 {
                NSPoint(x: CGFloat(command.X), y: CGFloat(command.Y))
            } else {
                nil
            }
        // Reject an out-of-range source crop the way kitty does (EINVAL) rather than silently
        // widening it to the whole image. A zero w/h means "to the far edge", valid as long as the
        // origin is inside the bitmap.
        let hasSourceCrop = command.x > 0 || command.y > 0 || command.w > 0 || command.h > 0
        if hasSourceCrop, let pixelSize = image.image.value?.size, pixelSize.width > 0, pixelSize.height > 0 {
            if CGFloat(command.x) >= pixelSize.width ||
                CGFloat(command.y) >= pixelSize.height ||
                (command.w > 0 && CGFloat(command.x) + CGFloat(command.w) > pixelSize.width) ||
                (command.h > 0 && CGFloat(command.y) + CGFloat(command.h) > pixelSize.height) {
                RLog("executeDisplay(image): ERROR - source rectangle out of range")
                return "EINVAL:source rectangle out of range"
            }
        }
        // Normalize the x/y/w/h crop to fractions of the bitmap it was requested against, so a later
        // retransmission to a different-sized bitmap samples the same proportional region (matching
        // kitty) and the region can never fall outside the bitmap (see Placement.resolvedSourceRect).
        // The crop was validated in-range above, so the resolved fractions are always positive.
        let sourceRegion: Placement.SourceRegion? = {
            guard hasSourceCrop else {
                return nil
            }
            guard let pixelSize = image.image.value?.size,
                  pixelSize.width > 0,
                  pixelSize.height > 0 else {
                return nil
            }
            let x = min(CGFloat(command.x), pixelSize.width)
            let y = min(CGFloat(command.y), pixelSize.height)
            let requestedW = command.w > 0 ? CGFloat(command.w) : (pixelSize.width - x)
            let requestedH = command.h > 0 ? CGFloat(command.h) : (pixelSize.height - y)
            let w = max(0, min(requestedW, pixelSize.width - x))
            let h = max(0, min(requestedH, pixelSize.height - y))
            return Placement.SourceRegion(x: x / pixelSize.width,
                                          y: y / pixelSize.height,
                                          w: w / pixelSize.width,
                                          h: h / pixelSize.height)
        }()
        let virtual = command.createUnicodePlaceholder == .createPlaceholder
        DLog("executeDisplay(image): virtual=\(virtual) pixelOffset=\(String(describing: pixelOffset)) sourceRegion=\(String(describing: sourceRegion))")
        if virtual {
            if command.parentImageIdentifier != nil || command.parentPlacement != nil {
                RLog("executeDisplay(image): ERROR - virtual placement cannot have parent")
                return "EINVAL"
            }
        }
        let cursorCoord = delegate.kittyImageControllerCursorCoord()
        let origin =
            if let p = command.parentPlacement, let i = command.parentImageIdentifier {
                Placement.Origin.relative(parentPlacementIdentifier: p,
                                          parentImageIdentifier: i,
                                          displacement: Placement.Displacement(x: command.H, y: command.V))
            } else {
                Placement.Origin.absolute(cursorCoord)
            }
        DLog("executeDisplay(image): origin=\(origin) cursorCoord=(\(cursorCoord.x), \(cursorCoord.y))")
        var placement = Placement(image: image,
                                  placementId: command.placement,
                                  origin: origin,
                                  pixelOffset: pixelOffset,
                                  sourceRegion: sourceRegion,
                                  rows: command.r > 0 ? command.r : nil,
                                  columns: command.c > 0 ? command.c : nil,
                                  zIndex: command.z,
                                  virtual: virtual)
        // Freeze the footprint now, against the bitmap present at creation, so a later retransmission
        // of this image id scales the new bitmap into this rect instead of relaying out the placement.
        placement.frozenNaturalSize = placement.liveNaturalPixelSize()
        if addingFormsCycle(placement: placement) {
            RLog("executeDisplay(image): ERROR - adding would form cycle")
            return "ECYCLE"
        }
        if placement.parentPlacementIdentifier != nil && placement.parent(finder: finder) == nil {
            RLog("executeDisplay(image): ERROR - parent placement not found")
            return "ENOPARENT"
        }
        if placement.virtual {
            // Virtual placements are resolved purely by (imageID, placementID) at draw time,
            // with no screen position, so a new one supersedes any existing virtual placement
            // with the same pair, even when the placement id is the default of 0. Without this,
            // retransmitting an image under a reused id and displaying it leaves the old placement
            // behind, and the placeholder finder returns that stale (oldest) placement instead of
            // the newly transmitted image. Issue 13028.
            let removedCount = placements.count
            placements.removeAll {
                $0.virtual &&
                $0.placementId == command.placement &&
                $0.image.metadata.identifier == placement.image.metadata.identifier
            }
            let actuallyRemoved = removedCount - placements.count
            if actuallyRemoved > 0 {
                DLog("executeDisplay(image): superseded \(actuallyRemoved) existing virtual placements with imageID=\(placement.image.metadata.identifier) placementId=\(command.placement)")
            }
        } else if command.placement != 0 {
            // Placement ids are unique per image, not globally, so only supersede a prior placement
            // of the same image; a different image reusing this placement id is a distinct placement.
            let removedCount = placements.count
            placements.removeAll {
                $0.placementId == command.placement &&
                $0.image.metadata.identifier == placement.image.metadata.identifier
            }
            let actuallyRemoved = removedCount - placements.count
            if actuallyRemoved > 0 {
                DLog("executeDisplay(image): removed \(actuallyRemoved) existing placements with imageID=\(placement.image.metadata.identifier) placementId=\(command.placement)")
            }
        }
        DLog("executeDisplay(image): appending placement - imageID=\(placement.image.metadata.identifier) (0x\(String(placement.image.metadata.identifier, radix: 16))) placementID=\(placement.placementId) virtual=\(placement.virtual) rows=\(String(describing: placement.rows)) columns=\(String(describing: placement.columns)) zIndex=\(placement.zIndex)")
        placements.append(placement)
        DLog("executeDisplay(image): total placements now \(placements.count), calling kittyImageControllerPlacementsDidChange")
        delegate.kittyImageControllerPlacementsDidChange()
        switch command.cursorMovementPolicy {
        case .doNotMoveCursor:
            DLog("executeDisplay(image): cursorMovementPolicy=doNotMoveCursor")
            break
        case .moveCursorToAfterImage:
            DLog("executeDisplay(image): cursorMovementPolicy=moveCursorToAfterImage parentPlacement=\(String(describing: command.parentPlacement)) virtual=\(placement.virtual)")
            if command.parentPlacement == nil && !placement.virtual {
                // Since a relative placement gets its position specified based on another placement,
                // instead of the cursor, the cursor must not move after a relative position,
                // regardless of the value of the C key to control cursor movement.
                //
                // It is not written in the spec, but I assume you don't move the cursor for virtual
                // placements either as that doesn't make any sense.
                let cellSize = delegate.kittyImageControllerCellSize()
                if let rect = placement.absRect(cellSize: cellSize, finder: finder) {
                    DLog("executeDisplay(image): moving cursor by dx=\(rect.width) dy=\(rect.height)")
                    delegate.kittyImageControllerMoveCursor(dx: Int(rect.width),
                                                            dy: Int(rect.height))
                }
            }
        }
        DLog("executeDisplay(image) END - success")
        return nil
    }

    private func addingFormsCycle(placement: Placement) -> Bool {
        // Parents resolve by (imageId, placementId) with newest-wins (see indexOfPlacement). Once this
        // placement is appended it becomes the newest of its own pair, so ANY ancestry chain that
        // reaches its pair will resolve back to it. Therefore, walk the parent chain by pair and
        // report a cycle if it reaches this placement's own pair. This correctly catches both the
        // direct self-parent case (P/Q naming this placement's pair) and the indirect case where a
        // chain loops through the pair this placement is about to become the newest of. Comparing by
        // resolved index instead would miss these, because the new placement is not in the array yet.
        let selfImageId = placement.image.metadata.identifier
        let selfPlacementId = placement.placementId
        guard var currentImageId = placement.parentImageIdentifier,
              var currentPlacementId = placement.parentPlacementIdentifier else {
            return false
        }
        // The existing placements are acyclic (this check runs before every insert), so the walk
        // terminates; bound it by the placement count as defense against a corrupted chain.
        for _ in 0...placements.count {
            if currentImageId == selfImageId && currentPlacementId == selfPlacementId {
                return true
            }
            guard let parent = finder(imageId: currentImageId, placementId: currentPlacementId),
                  let nextImageId = parent.parentImageIdentifier,
                  let nextPlacementId = parent.parentPlacementIdentifier else {
                return false
            }
            currentImageId = nextImageId
            currentPlacementId = nextPlacementId
        }
        return true
    }

    private func respondToDisplay(error: String?, identifier: UInt32, placement: UInt32, q: UInt32) {
        DLog("respondToDisplay: identifier=\(identifier) (0x\(String(identifier, radix: 16))) placement=\(placement) q=\(q) error=\(String(describing: error))")
        if q == 2 {
            DLog("respondToDisplay: q=2 (quiet), NOT sending response (error would have been: \(String(describing: error)))")
            return
        }
        if q == 1 && error == nil {
            DLog("respondToDisplay: q=1 and no error, NOT sending response")
            return
        }
        let parameters = {
            let dict = ["i": identifier, "p": placement]
            return dict.keys.compactMap { key in
                guard let value = dict[key] else {
                    return nil
                }
                if value == 0 {
                    return nil
                }
                return "\(key)=\(value)"
            }.joined(separator: ",")
        }()
        let pre = "\u{1B}_G"
        let post = "\u{1B}\\"
        let errorOrOK = error ?? "OK"
        let message =
            if parameters.isEmpty {
                errorOrOK
            } else {
                parameters + ";" + errorOrOK
            }
        DLog("respondToDisplay: sending response: \(message)")
        delegate?.kittyImageControllerReport(message: pre + message + post)
    }

    func executeLoadAnimationFrame(_ command: KittyImageCommand.AnimationFrameLoading) {
        // TODO
    }

    func executeComposeAnimationFrame(_ command: KittyImageCommand.AnimationFrameComposition) {
        // TODO
    }

    func executeControlAnimation(_ command: KittyImageCommand.AnimationControl) {
        // TODO
    }

    // The index of the placement identified by (imageId, placementId). The pair is NOT unique: two
    // non-virtual placements of one image with the default placement id 0 can coexist (displaying an
    // image twice with no p= is normal). When ambiguous, prefer the most recently created placement.
    private func indexOfPlacement(imageId: UInt32, placementId: UInt32) -> Int? {
        return placements.lastIndex { candidate in
            candidate.placementId == placementId && candidate.image.metadata.identifier == imageId
        }
    }

    private func finder(imageId: UInt32, placementId: UInt32) -> Placement? {
        guard let index = indexOfPlacement(imageId: imageId, placementId: placementId) else {
            return nil
        }
        return placements[index]
    }

    func executeDeleteImage(_ command: KittyImageCommand.DeleteImage) {
        guard let delegate else {
            return
        }
        DLog("executeDeleteImage: d='\(command.d)' imageId=\(command.imageId) placementId=\(command.placementId) current placements=\(placements.count)")
        let count = placements.count
        switch command.d {
        case "":
            // Delete all images visible on the screen
            // I don't know if the spec means all images or all images in the mutable area. And I
            // don't know if dangling placements are allowed.
            // I'll make the simplifying assumption that it is all images and placements.
            DLog("executeDeleteImage: case '' - deleting ALL images and placements")
            _images.removeAll()
            placements = []

        case "a", "A":
            // Delete all placements visible on screen
            DLog("executeDeleteImage: case 'a/A' - deleting all placements")
            removePlacements(where: { _ in true })

        case "i", "I":
            // Delete all images with the specified id, specified using the i key. If you specify a
            // p key for the placement id as well, then only the placement with the specified image
            // id and placement id will be deleted.
            // i=0 addresses id-less images, which live under lastImageKey (their metadata identifier
            // is 0, not their storage key).
            let key = command.imageId == 0 ? Self.lastImageKey : UInt64(command.imageId)
            if command.placementId != 0 {
                let matcher = matchesImage(underKey: key)
                removePlacements { command.placementId == $0.placementId && matcher($0) }
            } else {
                // I assume you have to remove dangingling placements, but the spec is silent.
                removeImage(key, placements: true, notify: false)
            }

        case "n", "N":
            // Delete newest image with the specified number, specified using the I key. If you
            // specify a p key for the placement id as well, then only the placement with the 
            // specified number and placement id will be deleted.
            let candidates = _images.keys.filter {
                _images[$0]?.metadata.imageNumber == command.I
            }
            let identifier = candidates.max { lhs, rhs in
                _images[lhs]!.sequence < _images[rhs]!.sequence
            }
            if let identifier {
                if command.placementId == 0 {
                    removeImage(identifier, placements: true, notify: false)
                } else {
                    let matcher = matchesImage(underKey: identifier)
                    removePlacements { command.placementId == $0.placementId && matcher($0) }
                }
            }

        case "c", "C":
            // Delete all placements that intersect with the current cursor position.
            let cursorCoord = delegate.kittyImageControllerCursorCoord()
            let cellSize = delegate.kittyImageControllerCellSize()
            removePlacements { placement in
                placement.intersects(coord: cursorCoord, cellSize: cellSize, finder: self.finder(imageId:placementId:))
            }

        case "f", "F":
            // Delete animation frames.
            // TODO
            break

        case "p", "P":
            // Delete all placements that intersect a specific cell, the cell is specified using the x and y keys
            let offset = delegate.kittyImageControllerScreenAbsLine()
            let coord = VT100GridAbsCoord(x: Int32(clamping: command.x) - 1,
                                          y: Int64(command.y) - 1 + offset)
            let cellSize = delegate.kittyImageControllerCellSize()
            removePlacements { placement in
                placement.intersects(coord: coord, cellSize: cellSize, finder: self.finder(imageId:placementId:))
            }

        case "q", "Q":
            // Delete all placements that intersect a specific cell having a specific z-index. 
            // The cell and z-index is specified using the x, y and z keys.
            let offset = delegate.kittyImageControllerScreenAbsLine()
            let coord = VT100GridAbsCoord(x: Int32(clamping: command.x),
                                          y: Int64(command.y) + offset)
            let cellSize = delegate.kittyImageControllerCellSize()

            removePlacements { placement in
                placement.zIndex == command.z && placement.intersects(coord: coord, cellSize: cellSize, finder: self.finder(imageId:placementId:))
            }

        case "r", "R":
            // Delete all images whose id is greater than or equal to the value of the x key and
            // less than or equal to the value of the y (added in kitty version 0.33.0).
            let imagesToRemove = _images.keys.filter { key in
                key >= command.x && key <= command.y
            }
            for id in imagesToRemove {
                // I don't know if this is supposed to remove placements as well, but it seems as though
                // it should.
                removeImage(UInt64(id), placements: true, notify: false)
            }

        case "x", "X":
            // Delete all placements that intersect the specified column, specified using the x key.
            let cellSize = delegate.kittyImageControllerCellSize()
            removePlacements { placement in
                placement.intersects(column: Int32(clamping: command.x) - 1, cellSize: cellSize, finder: self.finder(imageId:placementId:))
            }

        case "y", "Y":
            // Delete all placements that intersect the specified row, specified using the y key.
            let offset = delegate.kittyImageControllerScreenAbsLine()
            let cellSize = delegate.kittyImageControllerCellSize()
            removePlacements { placement in
                placement.intersects(row: Int64(command.y) - 1 + offset, cellSize: cellSize, finder: self.finder(imageId:placementId:))
            }

        case "z", "Z":
            // Delete all placements that have the specified z-index, specified using the z key.
            removePlacements { placement in
                placement.zIndex == command.z
            }

        default:
            // Undocumented
            RLog("executeDeleteImage: unrecognized delete command '\(command.d)'")
            break
        }

        DLog("executeDeleteImage: finished, placements changed from \(count) to \(placements.count)")
        if placements.count != count {
            delegate.kittyImageControllerPlacementsDidChange()
        }
    }

    private func removePlacements(where test: (Placement) -> Bool) {
        var closure = placements.indexes(where: test)
        // Deleting a placement also deletes the relative placements that refer to it, transitively
        // (kitty spec). Without this, an orphaned child lingers in the array holding its bitmap alive,
        // and because placements are freely re-created it could resurrect if a new placement later
        // reused its parent's key. Cascade to a child only when its ACTUAL resolved parent (the one
        // indexOfPlacement/finder would pick) is being removed, not merely when some placement with
        // the parent's (imageId, placementId) pair is: that pair is not unique (two non-virtual p=0
        // placements of one image can coexist), so key-matching would wrongly delete a child that is
        // positioned relative to the other, still-present placement. Iterate to a fixed point.
        var frontierChanged = true
        while frontierChanged {
            frontierChanged = false
            for index in placements.indices where !closure.contains(index) {
                guard let parentImageId = placements[index].parentImageIdentifier,
                      let parentPlacementId = placements[index].parentPlacementIdentifier,
                      let parentIndex = indexOfPlacement(imageId: parentImageId, placementId: parentPlacementId) else {
                    continue
                }
                if closure.contains(parentIndex) {
                    closure.insert(index)
                    frontierChanged = true
                }
            }
        }
        DLog("removePlacements: removing \(closure.count) placements at indexes \(closure)")
        for i in closure {
            let p = placements[i]
            DLog("  removing: imageID=\(p.image.metadata.identifier) (0x\(String(p.image.metadata.identifier, radix: 16))) placementID=\(p.placementId) virtual=\(p.virtual)")
        }
        placements.remove(at: closure)
        DLog("removePlacements: total placements now \(placements.count)")
    }

    // A predicate matching placements of the image stored under `key`. The shared lastImageKey slot is
    // occupied by whichever id-less image was transmitted most recently; match that occupant by its
    // unique id so earlier id-less images' still-live placements are not swept up (mirrors the
    // eviction path). For a real image id, match by the placement's storage key. Capture this before
    // deleting the image from the cache, since it reads the current occupant.
    private func matchesImage(underKey key: UInt64) -> (Placement) -> Bool {
        if key == Self.lastImageKey {
            let uniqueId = _images[key]?.uniqueId
            return { $0.image.uniqueId == uniqueId }
        }
        return { $0.imageKey == key }
    }

    private func removeImage(_ id: UInt64, placements removePlacements: Bool, notify: Bool) {
        DLog("removeImage: id=\(id) (0x\(String(id, radix: 16))) removePlacements=\(removePlacements) notify=\(notify)")
        let matcher = matchesImage(underKey: id)
        _images.delete(forKey: id)
        if removePlacements {
            self.removePlacements(where: matcher)
            if notify {
                delegate?.kittyImageControllerPlacementsDidChange()
            }
        }
    }

    @objc(draws)
    func draws() -> [iTermKittyImageDraw] {
        guard let delegate else {
            DLog("draws(): no delegate, returning empty array")
            return []
        }
        let cellSize = delegate.kittyImageControllerCellSize()
        DLog("draws(): cellSize=\(cellSize), placements.count=\(placements.count)")
        if gDebugLogging.boolValue {
            for (index, placement) in placements.enumerated() {
                DLog("draws(): placement[\(index)]: imageID=\(placement.image.metadata.identifier) (0x\(String(placement.image.metadata.identifier, radix: 16))) placementID=\(placement.placementId) virtual=\(placement.virtual) rows=\(String(describing: placement.rows)) columns=\(String(describing: placement.columns))")
            }
        }
        let result = placements.filter { candidate in
            guard candidate.pixelRect(cellSize: cellSize, finder: finder(imageId:placementId:)) != nil else {
                DLog("draws(): filtering out placement with nil pixelRect: imageID=\(candidate.image.metadata.identifier)")
                return false
            }
            return true
        }.compactMap { placement in
            return iTermKittyImageDraw(placement: placement, cellSize: cellSize, finder: finder)
        }.sorted { lhs, rhs in
            lhs.zIndex < rhs.zIndex
        }
        DLog("draws(): returning \(result.count) draws")
        if gDebugLogging.boolValue {
            for (index, draw) in result.enumerated() {
                DLog("draws(): result[\(index)]: \(draw)")
            }
        }
        return result
    }
}

// Describes a drawing operation the main thread should perform. In the case of virtual placements,
// it simply provides the linkage to the image while the location to draw is given by Unicode
// placeholders.
@objc
class iTermKittyImageDraw: NSObject {
    @objc var destinationFrame: NSRect
    @objc var sourceFrame: NSRect
    @objc var image: iTermImage
    @objc var index: UInt
    @objc var zIndex: Int32
    @objc var virtual: Bool
    @objc var placementID: UInt32
    @objc var imageID: UInt32
    @objc var placementSize: VT100GridSize
    @objc var imageUniqueID: UUID

    fileprivate init?(placement: KittyImageController.Placement,
                      cellSize: NSSize,
                      finder: KittyImageController.Placement.PlacementFinder) {
        guard let destinationFrame = placement.pixelRect(cellSize: cellSize, finder: finder) else {
            return nil
        }
        guard let image = placement.image.image.value else {
            return nil
        }
        self.imageUniqueID = placement.image.uniqueId
        self.virtual = placement.virtual
        self.placementID = placement.placementId
        self.imageID = placement.image.metadata.identifier
        self.destinationFrame = destinationFrame
        // Size in pixels
        let pixelSize = image.size
        // Size in physical units (i.e., NSImage.size, which is pixel size divided by DPI or whatever)
        let physicalSize = image.scaledSize
        // Multiply by this to convert pixels to physical size.
        let pxToPhys = physicalSize.multiplied(by: pixelSize.inverted)
        // sourceFrame is in physical units. Resolve the requested region against this bitmap's pixel
        // size so a retransmit to a different-sized bitmap adapts and never exceeds the bounds.
        sourceFrame = if let sourceRect = placement.resolvedSourceRect(imagePixelSize: pixelSize) {
            NSRect(x: sourceRect.origin.x * pxToPhys.width,
                   y: sourceRect.origin.y * pxToPhys.height,
                   width: sourceRect.width * pxToPhys.width,
                   height: sourceRect.height * pxToPhys.height).flipped(in: physicalSize.height)
        } else {
            NSRect(origin: .zero,
                   size: image.scaledSize)
        }
        self.image = image
        self.index = 0
        self.zIndex = placement.zIndex
        placementSize = VT100GridSize(width: Int32(clamping: placement.columns ?? 0),
                                      height: Int32(clamping: placement.rows ?? 0))
    }

    @objc
    func gridRect(cellSize: NSSize) -> VT100GridRect {
        let origin = VT100GridCoord(x: Int32(clamping: floor(destinationFrame.origin.x / cellSize.width)),
                                    y: Int32(clamping: floor(destinationFrame.origin.y / cellSize.height)))
        return VT100GridRect(origin: origin,
                             size: VT100GridSize(width: Int32(clamping: ceil(destinationFrame.maxX / cellSize.width)),
                                                 height: Int32(clamping: ceil(destinationFrame.maxY / cellSize.height))))
    }
}

extension iTermKittyImageDraw {
    override var description: String {
        return "<iTermKittyImageDraw: \(it_addressString) dest=\(destinationFrame) source=\(sourceFrame) index=\(index) zIndex=\(zIndex) virtual=\(virtual) placement=\(placementID) image=\(imageID) placementSize=\(placementSize) imageUniqueID=\(imageUniqueID)>"
    }
}
