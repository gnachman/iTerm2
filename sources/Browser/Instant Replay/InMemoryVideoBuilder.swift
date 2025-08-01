//
//  InMemoryVideoBuilder.swift
//  iTerm2
//
//  Created by George Nachman on 8/1/25.
//

import AppKit
import CoreMedia
@preconcurrency import AVFoundation
import VideoToolbox
import QuartzCore

enum VideoProfile {
    case low, medium, high
    
    var cfString: CFString {
        switch self {
        case .low: return kVTProfileLevel_H264_Baseline_AutoLevel
        case .medium: return kVTProfileLevel_H264_Main_AutoLevel
        case .high: return kVTProfileLevel_H264_High_AutoLevel
        }
    }
}

final class InMemoryVideoBuilder {
    enum RuntimeError: Error {
        case sessionCreationError
    }
    
    struct Frame {
        let sampleBuffer: CMSampleBuffer
        let mediaTime: CFTimeInterval
        var shouldDrop: Bool = false
    }
    
    let clipFrame: NSRect
    let scaleFactor: CGFloat
    let frameRate: Double
    let pixelSize: NSSize
    private var session: VTCompressionSession!
    private var frames: [Frame] = []
    private var firstPTS: CMTime?
    private let queue = DispatchQueue(label: "InMemoryVideoBuilder.store")
    private var previousPTS: CMTime?

    init(pixelSize: NSSize,
         clipFrame: NSRect,
         scaleFactor: CGFloat,
         frameRate: Double,
         bitsPerPixel: Double,
         profile: VideoProfile) throws {
        self.pixelSize = pixelSize
        self.clipFrame = clipFrame
        self.scaleFactor = scaleFactor
        self.frameRate = frameRate
        
        // Calculate bitrate from bitsPerPixel
        let bitrate = Int(Double(pixelSize.width * pixelSize.height) * frameRate * bitsPerPixel)
        DLog("Setting bitrate to \(bitrate) bps for \(pixelSize)px at \(frameRate)fps with \(bitsPerPixel) bpp")

        // Create VideoToolbox session
        var s: VTCompressionSession?
        VTCompressionSessionCreate(
            allocator: nil,
            width: Int32(pixelSize.width),
            height: Int32(pixelSize.height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: compressionCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &s
        )
        guard let sess = s else {
            DLog("Failed to create rolling recorder of size \(pixelSize)px")
            throw RuntimeError.sessionCreationError
        }
        session = sess
        VTSessionSetProperty(session,
                             key: kVTCompressionPropertyKey_RealTime,
                             value: kCFBooleanFalse)
        VTSessionSetProperty(session,
                             key: kVTCompressionPropertyKey_AllowFrameReordering,
                             value: kCFBooleanFalse)
        VTSessionSetProperty(session,
                             key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                             value: 30 as CFNumber)
        VTSessionSetProperty(session,
                             key: kVTCompressionPropertyKey_AverageBitRate,
                             value: bitrate as CFNumber)
        // Also set expected frame rate to help with bitrate allocation
        VTSessionSetProperty(session,
                             key: kVTCompressionPropertyKey_ExpectedFrameRate,
                             value: frameRate as CFNumber)
        // Set data rate limits to enforce bitrate
        VTSessionSetProperty(session,
                             key: kVTCompressionPropertyKey_DataRateLimits,
                             value: [bitrate * 2, 1] as CFArray)  // Allow bursts up to 2x bitrate per second
        VTSessionSetProperty(session,
                             key: kVTCompressionPropertyKey_ProfileLevel,
                             value: profile.cfString)
        VTCompressionSessionPrepareToEncodeFrames(session)
        DLog("Allocating a new rolling recorder of size \(pixelSize): \(ObjectIdentifier(self))")
    }
}

// MARK: - API

extension InMemoryVideoBuilder {
    var numberOfFrames: Int {
        queue.sync { frames.count }
    }
    var size: NSSize {
        return queue.sync { pixelSize }
    }
    var memoryUsage: Int {
        return queue.sync {
            return frames.reduce(0) { $0 + $1.sampleBuffer.compressedDataLength }
        }
    }
    func recordFrame(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime, mediaTime: CFTimeInterval) {
        queue.sync {
            if firstPTS == nil {
                firstPTS = presentationTime
            }
            
            // Convert to relative time from first frame, keeping nanosecond precision
            let relativeTime = CMTimeSubtract(presentationTime, firstPTS!)
            appendFrame(pixelBuffer, at: relativeTime, mediaTime: mediaTime)
        }
    }

    func getSampleBuffers() -> [CMSampleBuffer] {
        return queue.sync {
            return frames.filter { !$0.shouldDrop }.map { $0.sampleBuffer }
        }
    }
    
    func markFramesForDropping(after mediaTime: CFTimeInterval) {
        queue.sync {
            for i in frames.indices {
                if frames[i].mediaTime > mediaTime {
                    frames[i].shouldDrop = true
                }
            }
        }
    }
}

// MARK: - Private implementation methods
private extension InMemoryVideoBuilder {
    func appendFrame(_ buffer: CVPixelBuffer,
                     at pts: CMTime,
                     mediaTime: CFTimeInterval) {
        if let previousPTS, pts <= previousPTS {
            DLog("Drop frame for being out of order")
            return
        }
        
        // Calculate duration based on time since previous frame, or use default
        let duration: CMTime
        if let previousPTS = previousPTS {
            duration = CMTimeSubtract(pts, previousPTS)
        } else {
            // Default duration for first frame (1/60 second in nanosecond timescale)
            duration = CMTime(value: 16_666_667, timescale: 1_000_000_000)
        }
        
        previousPTS = pts
        
        // Pass media time through sourceFrameRefcon
        let mediaTimePtr = UnsafeMutablePointer<CFTimeInterval>.allocate(capacity: 1)
        mediaTimePtr.pointee = mediaTime
        
        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: buffer,
            presentationTimeStamp: pts,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: mediaTimePtr,
            infoFlagsOut: nil
        )
    }

}

fileprivate extension InMemoryVideoBuilder {
    func store(_ sb: CMSampleBuffer, mediaTime: CFTimeInterval) {
        queue.async {
            self._store(sb, mediaTime: mediaTime)
        }
    }

    func _store(_ sb: CMSampleBuffer, mediaTime: CFTimeInterval) {
        frames.append(Frame(sampleBuffer: sb, mediaTime: mediaTime))
    }
}

private let compressionCallback: VTCompressionOutputCallback = {
    refCon, sourceFrameRefcon, status, _, sampleBuffer in

    guard status == noErr,
          let sb = sampleBuffer,
          CMSampleBufferDataIsReady(sb) else {
        if let mediaTimePtr = sourceFrameRefcon {
            mediaTimePtr.deallocate()
        }
        return
    }

    let recorder = Unmanaged<InMemoryVideoBuilder>
        .fromOpaque(refCon!)
        .takeUnretainedValue()
    
    if let mediaTimePtr = sourceFrameRefcon?.assumingMemoryBound(to: CFTimeInterval.self) {
        let mediaTime = mediaTimePtr.pointee
        mediaTimePtr.deallocate()
        recorder.store(sb, mediaTime: mediaTime)
    }
}

extension CMSampleBuffer {
    /// Rough byte‐size of the compressed data in this sample.
    var compressedDataLength: Int {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(self) else {
            return 0
        }
        return CMBlockBufferGetDataLength(blockBuffer)
    }
}

