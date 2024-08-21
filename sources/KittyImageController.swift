//
//  KittyImage.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/15/24.
//

import Foundation
import Compression
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

        var pixelOffset: NSPoint?
        var sourceRect: NSRect?

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

        // Placement IDs. When this placement is deleted already remove these.
        var children = [UInt32]()

        typealias PlacementFinder = ((UInt32) -> Placement?)

        func parent(finder: PlacementFinder) -> Placement? {
            guard let pid = parentPlacementIdentifier else {
                return nil
            }
            return finder(pid)
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
            case .relative(let parentPlacementIdentifier, _, let displacement):
                guard let parent = finder(parentPlacementIdentifier) else {
                    return nil
                }
                guard let parentOrigin = parent.pixelOrigin(cellSize: cellSize, finder: finder) else {
                    return nil
                }
                return NSPoint(x: parentOrigin.x + CGFloat(displacement.x) * cellSize.width,
                               y: parentOrigin.y + CGFloat(displacement.y) * cellSize.height)
            }
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
            if image.metadata.width > 0 && image.metadata.height > 0 {
                return NSSize(width: CGFloat(image.metadata.width),
                              height: CGFloat(image.metadata.height))
            }
            if let sourceRect {
                return sourceRect.size
            }
            return image.image.value?.size ?? NSSize(width: 1, height: 1)
        }

        private func pixelWidth(forHeight height: CGFloat) -> CGFloat {
            if image.metadata.height == 0 || image.metadata.width == 0 {
                return 0
            }
            let aspectRatio = CGFloat(image.metadata.width) / CGFloat(image.metadata.height)
            return round(height * aspectRatio)
        }

        private func pixelHeight(forWidth width: CGFloat) -> CGFloat {
            if image.metadata.height == 0 || image.metadata.width == 0 {
                return 0
            }
            let aspectRatio = CGFloat(image.metadata.width) / CGFloat(image.metadata.height)
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
    private struct Accumulator {
        var transmission: KittyImageCommand.ImageTransmission
        var payload: String
        var query: Bool
        var display: KittyImageCommand.ImageDisplay?
    }

    // Identifier -> Image
    private var _images = LRUDictionary<UInt64, Image>(maximumSize: 320 * 1024 * 1024)
    private let lastImageKey = UInt64(UInt32.max) + 1
    private var accumulator: Accumulator?
    private var placements = [Placement]()

    @objc(executeCommand:)
    func execute(command: KittyImageCommand) {
        switch command.category {
        case .imageTransmission(let imageTransmission):
            _ = executeTransmit(imageTransmission,
                                display: nil,
                                payload: command.payload,
                                query: command.action == .query)
        case .imageDisplay(let imageDisplay):
            executeDisplay(imageDisplay)
        case .transmitAndDisplay(let imageTransmission, let imageDisplay):
            let hadAccumulator = (accumulator != nil)
            let savedDisplay = accumulator?.display
            if executeTransmit(imageTransmission, display: imageDisplay, payload: command.payload, query: false) {
                if (imageTransmission.more == .finalChunk) {
                    if let savedDisplay {
                        // If transmission was split up into multiple parts use the display commands
                        // from the first part.
                        executeDisplay(savedDisplay)
                    } else {
                        executeDisplay(imageDisplay)
                    }
                } else if !hadAccumulator, let accumulator, accumulator.display == nil {
                    // This is the first part of a multipart transmitAndDisplay. Save the display
                    // params in the accumulator.
                    self.accumulator?.display = imageDisplay
                }
            }
        case .animationFrameLoading(let animationFrameLoading):
            executeLoadAnimationFrame(animationFrameLoading)
        case .animationFrameComposition(let animationFrameComposition):
            executeComposeAnimationFrame(animationFrameComposition)
        case .animationControl(let animationControl):
            executeControlAnimation(animationControl)
        case .deleteImage(let deleteImage):
            executeDeleteImage(deleteImage)
        }
    }

    @objc 
    func clear() {
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
        var modifiedCommand = command

        if command.allocationAllowed && command.imageNumber > 0 {
            // Have not yet recursed after allocating an image ID.
            if command.identifier > 0 {
                respondToTransmit(command, display: display, error: "EINVAL:Can't give both i and I")
                return false
            }

            // Rewrite command to have an identifier and recurse.
            modifiedCommand.identifier = allocateIdentifier()
            if modifiedCommand.identifier == 0 {
                respondToTransmit(command, display: display, error: "ENOSPC:Out of identifiers")
                return false
            }
            modifiedCommand.allocationAllowed = false
        }

        let error = reallyExecuteTransmit(modifiedCommand, payload: payload, query: query)
        if error != nil || display == nil {
            respondToTransmit(modifiedCommand, display: display, error: error)
        }
        return error == nil
    }

    private func reallyExecuteTransmit(_ command: KittyImageCommand.ImageTransmission,
                                       payload: String,
                                       query: Bool) -> String? {
        if let accumulator {
            if command.more == .expectMore {
                self.accumulator?.payload += payload
                return nil
            }
            self.accumulator = nil
            var modifiedCommand = accumulator.transmission
            modifiedCommand.more = .finalChunk
            return reallyExecuteTransmit(modifiedCommand,
                                   payload: accumulator.payload + payload,
                                   query: accumulator.query)
        } else if command.more == .expectMore {
            accumulator = Accumulator(transmission: command, payload: payload, query: query)
            return nil
        }

        return switch command.medium {
        case .direct:
            executeTransmitDirect(command, payload: payload, query: query)
        case .file:
            executeTransmitFile(command, payload: payload, query: query)
        case .temporaryFile:
            executeTransmitTemporaryFile(command, payload: payload, query: query)
        case .sharedMemory:
            executeTransmitSharedMemory(command, payload: payload, query: query)
        }
    }

    // Direct (the data is transmitted within the escape code itself)
    private func executeTransmitDirect(_ command: KittyImageCommand.ImageTransmission,
                                       payload: String,
                                       query: Bool) -> String? {
        guard let data = decodeDirectTransmission(command, payload: payload) else {
            return "could not decode payload"
        }
        let image = switch command.format {
        case .raw24:
            image(data: data, bpp: 3, width: command.width, height: command.height)
        case .raw32:
            image(data: data, bpp: 4, width: command.width, height: command.height)
        case .png:
            iTermImage.init(compressedData: data)
        }
        guard let image else {
            return "invalid payload"
        }
        transmissionDidFinish(image: Image(metadata: command, image: ReferenceContainer(image)),
                              query: query)
        return nil
    }

    private func transmissionDidFinish(image: Image, query: Bool) {
        if !query && image.metadata.identifier != 0 {
            handleEvictions(_images.insert(key: UInt64(image.metadata.identifier), value: image, cost: image.cost))
        } else {
            handleEvictions(_images.insert(key: lastImageKey, value: image, cost: image.cost))
        }
    }

    private func handleEvictions(_ kvps: [(UInt64, Image)]) {
        for kvp in kvps {
            kvp.1.image.value = nil
        }
    }

    private func dataByAddingAlphaTo3bppData(_ data: Data, _ alpha: UInt8) -> Data {
        var rgbaData = Data(capacity: (data.count / 3) * 4)
        for i in stride(from: 0, to: data.count, by: 3) {
            rgbaData.append(contentsOf: data[i..<i+3])
            rgbaData.append(alpha)
        }
        return rgbaData
    }

    private func image(data: Data, bpp: UInt, width: UInt, height: UInt) -> iTermImage? {
        guard bpp == 3 || bpp == 4 else {
            return nil
        }

        let bytesPerPixel = 4
        let bytesPerRow = Int(clamping: width) * bytesPerPixel
        let unpaddedBytes = Int(clamping: bpp) * Int(clamping: width) * Int(clamping: height)

        guard data.count == unpaddedBytes else {
            return nil
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo: CGBitmapInfo = [.byteOrder32Big, CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)]

        let rgbaData =
            if bpp == 4 {
                data
            } else {
                dataByAddingAlphaTo3bppData(data, 0xff)
            }

        guard let provider = CGDataProvider(data: rgbaData as CFData) else { return nil }

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
            return nil
        }

        let nsimage = NSImage(cgImage: cgImage, size: NSSize(width: Int(width), height: Int(height)))
        return iTermImage(nativeImage: nsimage)
    }

    private func decodeDirectTransmission(_ command: KittyImageCommand.ImageTransmission, payload: String) -> Data? {
        return switch command.compression {
        case .zlib:
            decompressAndDecode(payload)
        case .uncompressed:
            decode(payload)
        }
    }

    func inflate(data compressedData: Data) -> Data? {
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
        if inflateInit_(&z, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) != Z_OK {
            return nil
        }

        // Decompress the data
        var result: Int32
        repeat {
            z.next_out = buffer
            z.avail_out = uInt(bufferSize)

            result = zlib.inflate(&z, Z_NO_FLUSH)

            if result == Z_STREAM_ERROR || result == Z_DATA_ERROR || result == Z_MEM_ERROR {
                inflateEnd(&z)
                return nil
            }

            let bytesDecompressed = bufferSize - Int(z.avail_out)
            decompressedData.append(buffer, count: bytesDecompressed)

        } while result != Z_STREAM_END

        // Clean up
        inflateEnd(&z)

        return decompressedData
    }

    private func decompressAndDecode(_ payload: String) -> Data? {
        guard let compressed = Data(base64Encoded: payload) else {
            return nil
        }
        return inflate(data: compressed)
    }

    private func decode(_ payload: String) -> Data? {
        return Data(base64Encoded: payload)
    }

    func executeTransmitFile(_ command: KittyImageCommand.ImageTransmission,
                             payload: String,
                             query: Bool) -> String? {
        return "EBADF:Unimplemented"  // TODO
    }

    func executeTransmitTemporaryFile(_ command: KittyImageCommand.ImageTransmission,
                                      payload: String,
                                      query: Bool) -> String? {
        return "EBADF:Unimplemented"  // TODO
    }

    func executeTransmitSharedMemory(_ command: KittyImageCommand.ImageTransmission,
                                     payload: String,
                                     query: Bool) -> String? {
        return "EBADF:Unimplemented"  // TODO
    }

    func respondToTransmit(_ imageTransmission: KittyImageCommand.ImageTransmission,
                            display: KittyImageCommand.ImageDisplay?,
                            error: String?) {
        if imageTransmission.more == .expectMore {
            // This is undocumented by the spec.
            return
        }
        var args = [String]()
        if imageTransmission.imageNumber > 0 {
            args.append("i=\(imageTransmission.identifier)")
            args.append("I=\(imageTransmission.imageNumber)")
        } else if error != nil {
            args.append("i=\(imageTransmission.identifier)")
        }
        if let p = display?.placement {
            args.append("p=\(p)")
        }
        let semi = args.isEmpty ? "" : ";"
        let payload = args.joined(separator: ",") + semi + (error ?? "OK")
        let message = "\u{1B}_G\(payload)\u{1B}\\"
        switch imageTransmission.verbosity {
        case .normal:
            delegate?.kittyImageControllerReport(message: message)
        case .query:
            if error != nil {
                delegate?.kittyImageControllerReport(message: message)
            }
            return
        case .quiet:
            return
        }
    }

    // MARK: - Display

    func executeDisplay(_ command: KittyImageCommand.ImageDisplay) {
        if command.identifier != 0 {
            // The spec alludes to multiple images having the same ID but doesn't say what to do
            // when you try to display that ID ("Delete newest image with the specified number…")
            if let image = _images[UInt64(command.identifier)] {
                respondToDisplay(error: executeDisplay(command, image: image),
                                 identifier: command.identifier,
                                 placement: command.placement,
                                 q: command.q)
            } else {
                respondToDisplay(error: "ENOENT:Put command refers to non-existent image with id: \(command.identifier) and number: 0",
                                 identifier: command.identifier,
                                 placement: command.placement,
                                 q: command.q)
            }
        } else if let lastImage = _images[lastImageKey] {
            respondToDisplay(error: executeDisplay(command, image: lastImage),
                             identifier: command.identifier,
                             placement: command.placement,
                             q: command.q)
        }
    }

    private func executeDisplay(_ command: KittyImageCommand.ImageDisplay,
                                image: Image) -> String? {
        guard let delegate else {
            return "Client unavailable"
        }
        let pixelOffset: NSPoint? =
            if command.X > 0 || command.Y > 0 {
                NSPoint(x: CGFloat(command.X), y: CGFloat(command.Y))
            } else {
                nil
            }
        let sourceRect: NSRect? =
            if command.x > 0 || command.y > 0 || command.w > 0 || command.h > 0 {
                if let image = image.image.value {
                    NSRect(x: CGFloat(command.x),
                           y: CGFloat(command.y),
                           width: command.w > 0 ? CGFloat(command.w) : (image.size.width - CGFloat(command.x)),
                           height: command.h > 0 ? CGFloat(command.h) : (image.size.height - CGFloat(command.y)))
                } else {
                    NSRect(origin: .init(x: CGFloat(command.x), y: CGFloat(command.y)),
                           size: .init(width: 1.0, height: 1.0))
                }
            } else {
                nil
            }
        let virtual = command.createUnicodePlaceholder == .createPlaceholder
        if virtual {
            if command.parentImageIdentifier != nil || command.parentPlacement != nil {
                return "EINVAL"
            }
        }
        let origin =
            if let p = command.parentPlacement, let i = command.parentImageIdentifier {
                Placement.Origin.relative(parentPlacementIdentifier: p,
                                          parentImageIdentifier: i,
                                          displacement: Placement.Displacement(x: command.H, y: command.V))
            } else {
                Placement.Origin.absolute(delegate.kittyImageControllerCursorCoord())
            }
        let placement = Placement(image: image,
                                  placementId: command.placement,
                                  origin: origin,
                                  pixelOffset: pixelOffset,
                                  sourceRect: sourceRect,
                                  rows: command.c > 0 ? command.c : nil,
                                  columns: command.r > 0 ? command.r : nil,
                                  zIndex: command.z,
                                  virtual: virtual)
        if addingFormsCycle(placement: placement) {
            return "ECYCLE"
        }
        if placement.parentPlacementIdentifier != nil && placement.parent(finder: finder) == nil {
            return "ENOPARENT"
        }
        if command.placement != 0 {
            placements.removeAll { $0.placementId == command.placement }
        }
        placements.append(placement)
        delegate.kittyImageControllerPlacementsDidChange()
        switch command.cursorMovementPolicy {
        case .doNotMoveCursor:
            break
        case .moveCursorToAfterImage:
            if command.parentPlacement == nil && !placement.virtual {
                // Since a relative placement gets its position specified based on another placement,
                // instead of the cursor, the cursor must not move after a relative position, 
                // regardless of the value of the C key to control cursor movement.
                //
                // It is not written in the spec, but I assume you don't move the cursor for virtual
                // placements either as that doesn't make any sense.
                let cellSize = delegate.kittyImageControllerCellSize()
                if let rect = placement.absRect(cellSize: cellSize, finder: finder) {
                    delegate.kittyImageControllerMoveCursor(dx: Int(rect.width),
                                                            dy: Int(rect.height))
                }
            }
        }
        return nil
    }

    private func addingFormsCycle(placement: Placement) -> Bool {
        if placement.placementId == placement.parentPlacementIdentifier {
            return true
        }
        var currentId = placement.parentPlacementIdentifier
        let newPlacementId = placement.placementId

        while currentId != nil {
            if currentId == newPlacementId {
                return true
            }

            // Find the parent of the currentId
            if let parentPlacement = placements.first(where: { $0.placementId == currentId }) {
                currentId = parentPlacement.parentPlacementIdentifier
            } else {
                return false
            }
        }

        return false
    }

    private func find(placement: UInt32) -> Placement? {
        return placements.first { $0.placementId == placement }
    }

    private func respondToDisplay(error: String?, identifier: UInt32, placement: UInt32, q: UInt32) {
        if q == 2 {
            return
        }
        if q == 1 && error == nil {
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

    private func finder(placementId: UInt32) -> Placement? {
        placements.first { candidate in
            candidate.placementId == placementId
        }
    }

    func executeDeleteImage(_ command: KittyImageCommand.DeleteImage) {
        guard let delegate else {
            return
        }
        let count = placements.count
        switch command.d {
        case "":
            // Delete all images visible on the screen
            // I don't know if the spec means all images or all images in the mutable area. And I
            // don't know if dangling placements are allowed.
            // I'll make the simplifying assumption that it is all images and placements.
            _images.removeAll()
            placements = []

        case "a", "A":
            // Delete all placements visible on screen
            removePlacements(where: { _ in true })

        case "i", "I":
            // Delete all images with the specified id, specified using the i key. If you specify a
            // p key for the placement id as well, then only the placement with the specified image
            // id and placement id will be deleted.
            if command.placementId != 0 {
                removePlacements { placement in
                    placement.image.metadata.identifier == command.imageId && placement.placementId == command.placementId
                }
            } else {
                // I assume you have to remove dangingling placements, but the spec is silent.
                removeImage(UInt64(command.imageId), placements: true, notify: false)
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
                    removePlacements { placement in
                        return command.placementId == placement.placementId
                    }
                }
            }

        case "c", "C":
            // Delete all placements that intersect with the current cursor position.
            let cursorCoord = delegate.kittyImageControllerCursorCoord()
            let cellSize = delegate.kittyImageControllerCellSize()
            removePlacements { placement in
                placement.intersects(coord: cursorCoord, cellSize: cellSize, finder: self.finder(placementId:))
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
                placement.intersects(coord: coord, cellSize: cellSize, finder: self.finder(placementId:))
            }

        case "q", "Q":
            // Delete all placements that intersect a specific cell having a specific z-index. 
            // The cell and z-index is specified using the x, y and z keys.
            let offset = delegate.kittyImageControllerScreenAbsLine()
            let coord = VT100GridAbsCoord(x: Int32(clamping: command.x),
                                          y: Int64(command.y) + offset)
            let cellSize = delegate.kittyImageControllerCellSize()

            removePlacements { placement in
                placement.zIndex == command.z && placement.intersects(coord: coord, cellSize: cellSize, finder: self.finder(placementId:))
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
                placement.intersects(column: Int32(clamping: command.x) - 1, cellSize: cellSize, finder: self.finder(placementId:))
            }

        case "y", "Y":
            // Delete all placements that intersect the specified row, specified using the y key.
            let offset = delegate.kittyImageControllerScreenAbsLine()
            let cellSize = delegate.kittyImageControllerCellSize()
            removePlacements { placement in
                placement.intersects(row: Int64(command.y) - 1 + offset, cellSize: cellSize, finder: self.finder(placementId:))
            }

        case "z", "Z":
            // Delete all placements that have the specified z-index, specified using the z key.
            removePlacements { placement in
                placement.zIndex == command.z
            }

        default:
            // Undocumented
            break
        }

        if placements.count != count {
            delegate.kittyImageControllerPlacementsDidChange()
        }
    }

    private func removePlacements(where test: (Placement) -> Bool) {
        var closure = placements.indexes(where: test)
        var current = closure
        while !current.isEmpty {
            var next = IndexSet()
            for i in current {
                for child in placements[i].children {
                    let childId = Int(child)
                    if closure.contains(childId) {
                        continue
                    }
                    next.insert(childId)
                    closure.insert(childId)
                }
            }
            current = next
        }
        placements.remove(at: closure)
    }

    private func removeImage(_ id: UInt64, placements: Bool, notify: Bool) {
        _images.delete(forKey: id)
        if placements {
            removePlacements { placement in
                placement.image.metadata.identifier == id
            }
            if notify {
                delegate?.kittyImageControllerPlacementsDidChange()
            }
        }
    }

    @objc(draws)
    func draws() -> [iTermKittyImageDraw] {
        guard let delegate else {
            return []
        }
        let cellSize = delegate.kittyImageControllerCellSize()
        return placements.filter { candidate in
            guard candidate.pixelRect(cellSize: cellSize, finder: finder(placementId:)) != nil else {
                return false
            }
            return true
        }.compactMap { placement in
            return iTermKittyImageDraw(placement: placement, cellSize: cellSize, finder: finder)
        }.sorted { lhs, rhs in
            lhs.zIndex < rhs.zIndex
        }
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
        self.imageID = placement.image.metadata.imageNumber
        self.destinationFrame = destinationFrame
        // Size in pixels
        let pixelSize = image.size
        // Size in physical units (i.e., NSImage.size, which is pixel size divided by DPI or whatever)
        let physicalSize = image.scaledSize
        // Multiply by this to convert pixels to physical size.
        let pxToPhys = physicalSize.multiplied(by: pixelSize.inverted)
        // sourceFrame is in physical units.
        sourceFrame = if let sourceRect = placement.sourceRect {
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
