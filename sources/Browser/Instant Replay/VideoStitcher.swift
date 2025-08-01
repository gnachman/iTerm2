//
//  VideoStitcher.swift
//  iTerm2
//
//  Created by George Nachman on 8/1/25.
//

import AppKit
import CoreMedia
@preconcurrency import AVFoundation
import VideoToolbox
import QuartzCore
import CoreImage

// Global decompression callback
private let decompressionCallback: VTDecompressionOutputCallback = { _, frameRefcon, status, _, imageBuffer, _, _ in
    guard let frameRefcon = frameRefcon else { 
        DLog("No frameRefcon in callback")
        return 
    }
    
    let pixelBufferPtr = frameRefcon.assumingMemoryBound(to: Optional<CVPixelBuffer>.self)
    
    if status == noErr, let imageBuffer = imageBuffer {
        pixelBufferPtr.pointee = imageBuffer
    } else {
        DLog("Decompression callback failed with status: \(status)")
    }
}

final class VideoStitcher {
    let inputSegments: [Segment]
    let outputURL: URL
    let bitsPerPixel: Double
    let profile: VideoProfile
    let scaleFactor: CGFloat

    enum RuntimeError: Error {
        case noValidSegments
        case decompressionFailed
        case bufferCreationFailed
    }

    struct Segment {
        // All sizes are in pixels.
        var windowSize: NSSize
        var clipFrame: NSRect
        var samples: [CMSampleBuffer]
    }
    init(inputSegments: [Segment], outputURL: URL, bitsPerPixel: Double, profile: VideoProfile, scaleFactor: CGFloat) {
        self.inputSegments = inputSegments
        self.outputURL = outputURL
        self.bitsPerPixel = bitsPerPixel
        self.profile = profile
        self.scaleFactor = scaleFactor
    }

    static func videoSize(forClipFrames clipFrames: [NSRect]) -> NSSize {
        return clipFrames.reduce(CGSize.zero) { currentMax, clipFrame in
            let size = clipFrame.size
            return CGSize(
                width: max(currentMax.width, size.width),
                height: max(currentMax.height, size.height)
            )
        }
    }

    func stitch() async throws -> (URL, NSSize) {
        guard !inputSegments.isEmpty else {
            throw RuntimeError.noValidSegments
        }

        // Find maximum size across all segments
        let maxSize = Self.videoSize(forClipFrames: inputSegments.map(\.clipFrame))
        DLog("maxSize=\(maxSize), clipFrames=\(inputSegments.map(\.clipFrame))")

        // Validate size
        guard maxSize.width > 0 && maxSize.height > 0 else {
            DLog("Invalid maxSize: \(maxSize)")
            throw RuntimeError.noValidSegments
        }
        // Create writer with final video settings
        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(maxSize.width),
            AVVideoHeightKey: Int(maxSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(maxSize.width * maxSize.height * 60.0 * bitsPerPixel), // Use provided bitsPerPixel
                AVVideoProfileLevelKey: profile == .high ? AVVideoProfileLevelH264HighAutoLevel : 
                                       profile == .medium ? AVVideoProfileLevelH264MainAutoLevel :
                                       AVVideoProfileLevelH264BaselineAutoLevel
            ]
        ]

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov) // Must be .mov for QuickTime metadata
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false
        
        // Add pixel density metadata for Retina displays
        if scaleFactor > 1.0 {
            let pixelDensityItem = AVMutableMetadataItem()
            pixelDensityItem.keySpace = .quickTimeMetadata
            pixelDensityItem.key = "com.apple.quicktime.pixeldensity" as (NSCopying & NSObjectProtocol)
            
            // Create data with 4 uint32_t values: pixel width, pixel height, display width, display height
            let pixelWidth = UInt32(maxSize.width)
            let pixelHeight = UInt32(maxSize.height)
            let displayWidth = UInt32(maxSize.width / scaleFactor)
            let displayHeight = UInt32(maxSize.height / scaleFactor)
            
            var data = Data()
            data.append(withUnsafeBytes(of: pixelWidth.bigEndian) { Data($0) })
            data.append(withUnsafeBytes(of: pixelHeight.bigEndian) { Data($0) })
            data.append(withUnsafeBytes(of: displayWidth.bigEndian) { Data($0) })
            data.append(withUnsafeBytes(of: displayHeight.bigEndian) { Data($0) })
            
            pixelDensityItem.value = data as NSData
            pixelDensityItem.dataType = kCMMetadataBaseDataType_RawData as String
            
            input.metadata = [pixelDensityItem]
            DLog("Added pixel density metadata: \(pixelWidth)x\(pixelHeight) -> \(displayWidth)x\(displayHeight)")
        }

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(maxSize.width),
            kCVPixelBufferHeightKey as String: Int(maxSize.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Process each segment
        var segmentStartTime = CMTime.zero
        
        for segment in inputSegments {
            let sampleBuffers = segment.samples
            guard !sampleBuffers.isEmpty else { continue }
            
            // Create one decompression session per segment
            DLog("Creating decompression session for segment")
            let decompressionSession = try createDecompressionSession(from: sampleBuffers.first!)
            defer { VTDecompressionSessionInvalidate(decompressionSession) }
            
            // Find the first frame's timestamp to calculate offset
            let firstFramePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffers.first!)
            
            for sampleBuffer in sampleBuffers {
                while !input.isReadyForMoreMediaData {
                    let ms = 1.0
                    try await Task.sleep(nanoseconds: UInt64(ms * 1_000_000.0))
                }

                // Decompress frame
                do {
                    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    let pixelBuffer = try await decompressSampleBuffer(sampleBuffer, using: decompressionSession)
                    // Create letterboxed frame
                    let letterboxedBuffer = try createLetterboxedFrame(
                        from: pixelBuffer,
                        sourceSize: segment.windowSize,
                        targetSize: maxSize,
                        clipFrame: segment.clipFrame)

                    // Use original timing, but offset by segment start time
                    let relativeTime = CMTimeSubtract(pts, firstFramePTS)
                    let finalPTS = CMTimeAdd(segmentStartTime, relativeTime)
                    adaptor.append(letterboxedBuffer, withPresentationTime: finalPTS)
                } catch {
                    DLog("Failed to decompress sample buffer: \(error)")
                    throw error
                }
            }
            
            // Update segment start time for next segment
            if let lastFrame = sampleBuffers.last {
                let lastPTS = CMSampleBufferGetPresentationTimeStamp(lastFrame)
                let lastDuration = CMSampleBufferGetDuration(lastFrame)
                let relativeLast = CMTimeSubtract(lastPTS, firstFramePTS)
                segmentStartTime = CMTimeAdd(segmentStartTime, CMTimeAdd(relativeLast, lastDuration))
            }
        }

        input.markAsFinished()
        await writer.finishWriting()

        if let error = writer.error {
            throw error
        }
        
        return (outputURL, maxSize / scaleFactor)
    }

    // MARK: - Private Methods
    
    private func createDecompressionSession(from sampleBuffer: CMSampleBuffer) throws -> VTDecompressionSession {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw RuntimeError.decompressionFailed
        }
        
        var callbackRecord = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decompressionCallback,
            decompressionOutputRefCon: nil
        )
        
        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDesc,
            decoderSpecification: nil,
            imageBufferAttributes: nil,
            outputCallback: &callbackRecord,
            decompressionSessionOut: &session
        )
        
        guard status == noErr, let decompressionSession = session else {
            throw RuntimeError.decompressionFailed
        }
        
        return decompressionSession
    }
    
    private func decompressSampleBuffer(_ sampleBuffer: CMSampleBuffer, using session: VTDecompressionSession) async throws -> CVPixelBuffer {
        // Validate sample buffer
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            DLog("Sample buffer data is not ready!")
            throw RuntimeError.decompressionFailed
        }
        
        guard CMSampleBufferGetNumSamples(sampleBuffer) > 0 else {
            DLog("Sample buffer has no samples!")
            throw RuntimeError.decompressionFailed
        }
        
        var outputBuffer: CVPixelBuffer?
        
        let status = withUnsafeMutablePointer(to: &outputBuffer) { bufferPtr in
            return VTDecompressionSessionDecodeFrame(
                session,
                sampleBuffer: sampleBuffer,
                flags: [],
                frameRefcon: bufferPtr,
                infoFlagsOut: nil
            )
        }
        
        guard status == noErr else {
            DLog("VTDecompressionSessionDecodeFrame failed with status: \(status)")
            throw RuntimeError.decompressionFailed
        }
        
        guard let pixelBuffer = outputBuffer else {
            DLog("Decompression succeeded but no pixel buffer returned")
            throw RuntimeError.decompressionFailed
        }
        
        return pixelBuffer
    }
    
    private func createLetterboxedFrame(from sourceBuffer: CVPixelBuffer,
                                        sourceSize: NSSize,
                                        targetSize: CGSize,
                                        clipFrame: NSRect) throws -> CVPixelBuffer {

        do {
            // Create target pixel buffer with proper alignment
            let width = Int(targetSize.width)
            let height = Int(targetSize.height)

            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferBytesPerRowAlignmentKey as String: 16,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            
            var targetBuffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32BGRA,
                attributes as CFDictionary,
                &targetBuffer
            )

            guard status == kCVReturnSuccess, let target = targetBuffer else {
                throw RuntimeError.bufferCreationFailed
            }

            CVPixelBufferLockBaseAddress(sourceBuffer, .readOnly)
            CVPixelBufferLockBaseAddress(target, [])
            defer {
                CVPixelBufferUnlockBaseAddress(sourceBuffer, .readOnly)
                CVPixelBufferUnlockBaseAddress(target, [])
            }

            // Calculate positioning - we want to extract the clip region and center it
            let offset = CGPoint(
                x: (targetSize.width - clipFrame.width) / 2,
                y: (targetSize.height - clipFrame.height) / 2
            )

            // Create contexts
            guard let sourceData = CVPixelBufferGetBaseAddress(sourceBuffer),
                  let targetData = CVPixelBufferGetBaseAddress(target) else {
                throw RuntimeError.bufferCreationFailed
            }

            let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(sourceBuffer)
            let targetBytesPerRow = CVPixelBufferGetBytesPerRow(target)
            let sourcePixelFormat = CVPixelBufferGetPixelFormatType(sourceBuffer)
            
            DLog("Source: \(Int(sourceSize.width))x\(Int(sourceSize.height)), bytesPerRow: \(sourceBytesPerRow), format: \(sourcePixelFormat)")
            DLog("Target: \(Int(targetSize.width))x\(Int(targetSize.height)), bytesPerRow: \(targetBytesPerRow)")
            
            // Check if we need to convert pixel format
            if sourcePixelFormat != kCVPixelFormatType_32BGRA {
                DLog("Source is not BGRA format (\(sourcePixelFormat)), need to convert")
                // Convert using Core Image or other method
                return try convertAndLetterbox(sourceBuffer: sourceBuffer, sourceSize: sourceSize, targetSize: targetSize, clipFrame: clipFrame)
            }

            let colorSpace = CGColorSpaceCreateDeviceRGB()

            guard let sourceContext = CGContext(
                data: sourceData,
                width: Int(sourceSize.width),
                height: Int(sourceSize.height),
                bitsPerComponent: 8,
                bytesPerRow: sourceBytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ),
                  let targetContext = CGContext(
                    data: targetData,
                    width: Int(targetSize.width),
                    height: Int(targetSize.height),
                    bitsPerComponent: 8,
                    bytesPerRow: targetBytesPerRow,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                  ) else {
                throw RuntimeError.bufferCreationFailed
            }

            // Fill with black (letterbox bars)
            targetContext.setFillColor(CGColor.black)
            targetContext.fill(CGRect(origin: .zero, size: targetSize))

            // Draw only the clip region from the source
            if let sourceImage = sourceContext.makeImage() {
                // Create a sub-image from just the clip region
                if let clippedImage = sourceImage.cropping(to: clipFrame) {
                    // Draw the clipped portion at the calculated offset
                    targetContext.draw(clippedImage, in: CGRect(origin: offset, size: clipFrame.size))
                }
            }

            return target
        } catch {
            DLog("Failed to create letterboxed frame: \(error)")
            throw error
        }
    }
    
    private func convertAndLetterbox(sourceBuffer: CVPixelBuffer, sourceSize: NSSize, targetSize: CGSize, clipFrame: NSRect) throws -> CVPixelBuffer {
        // Use Core Image to convert pixel format and do letterboxing
        let ciImage = CIImage(cvPixelBuffer: sourceBuffer)
        
        // Create target pixel buffer
        let width = Int(targetSize.width)
        let height = Int(targetSize.height)
        
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferBytesPerRowAlignmentKey as String: 16,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        var targetBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &targetBuffer
        )
        
        guard status == kCVReturnSuccess, let target = targetBuffer else {
            throw RuntimeError.bufferCreationFailed
        }
        
        // First, extract just the clip frame portion from the source
        let croppedImage = ciImage.cropped(to: clipFrame)
        
        // Now position this cropped content in the target frame
        // The cropped image needs to be translated because cropping changes the extent
        let translateToCenterX = (targetSize.width - clipFrame.width) / 2
        let translateToCenterY = (targetSize.height - clipFrame.height) / 2
        
        // Translate from the clip frame's origin to the center position
        let translateTransform = CGAffineTransform(translationX: translateToCenterX - clipFrame.origin.x, 
                                                   y: translateToCenterY - clipFrame.origin.y)
        let transformedImage = croppedImage.transformed(by: translateTransform)
        
        // Create black background
        let blackImage = CIImage(color: CIColor.black).cropped(to: CGRect(origin: .zero, size: targetSize))
        
        // Composite clipped image over black background
        let compositedImage = transformedImage.composited(over: blackImage)
        
        // Render to target buffer
        let context = CIContext()
        context.render(compositedImage, to: target)
        
        return target
    }
    
    private func convertPixelBufferFormat(_ sourceBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        // Use Core Image for simple format conversion
        let ciImage = CIImage(cvPixelBuffer: sourceBuffer)
        
        let width = CVPixelBufferGetWidth(sourceBuffer)
        let height = CVPixelBufferGetHeight(sourceBuffer)
        
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferBytesPerRowAlignmentKey as String: 16,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        var targetBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &targetBuffer
        )
        
        guard status == kCVReturnSuccess, let target = targetBuffer else {
            throw RuntimeError.bufferCreationFailed
        }
        
        // Render to target buffer
        let context = CIContext()
        context.render(ciImage, to: target)
        
        return target
    }
    
}
