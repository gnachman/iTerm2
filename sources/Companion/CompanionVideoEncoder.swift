//
//  CompanionVideoEncoder.swift
//  iTerm2
//
//  A streaming HEVC encoder for the Companion live-view feature. Unlike
//  InMemoryVideoBuilder (which stores frames for later stitching into an Instant
//  Replay movie), this emits each compressed access unit immediately via a
//  callback so the host can push it on the media channel.
//
//  Configured for low latency: HEVC, real-time rate control, no frame
//  reordering (DTS == PTS, no reorder delay), and keyframes only on demand
//  (forceKeyframe) rather than on a periodic interval, since the stream is
//  change-driven and mostly static.
//

import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

final class CompanionVideoEncoder: @unchecked Sendable {
    /// One compressed frame ready for the wire.
    struct EncodedFrame: Equatable {
        /// The access unit in AVCC framing (length-prefixed NAL units).
        var accessUnit: Data
        var isKeyframe: Bool
        /// VPS/SPS/PPS, present on keyframes (the host puts them in streamConfig).
        var parameterSets: [Data]?
        var ptsMilliseconds: UInt64
    }

    enum EncoderError: Error, Equatable {
        case sessionCreationFailed(OSStatus)
    }

    private let width: Int32
    private let height: Int32
    private let onFrame: (EncodedFrame) -> Void
    private var session: VTCompressionSession?

    /// Create an encoder for `width` x `height` frames. `onFrame` is called (on a
    /// VideoToolbox thread) for each compressed access unit. Throws if the system
    /// cannot create an HEVC compression session (e.g. unsupported hardware).
    init(width: Int,
         height: Int,
         averageBitRate: Int = 1_000_000,
         onFrame: @escaping (EncodedFrame) -> Void) throws {
        self.width = Int32(width)
        self.height = Int32(height)
        self.onFrame = onFrame

        var created: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: self.width,
            height: self.height,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: encoderOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &created)
        guard status == noErr, let session = created else {
            throw EncoderError.sessionCreationFailed(status)
        }
        self.session = session

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel,
                             value: kVTProfileLevel_HEVC_Main_AutoLevel)
        // Keyframes on demand only: a very large interval plus explicit
        // forceKeyframe, so an idle screen never spends bits on periodic IDRs.
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                             value: Int.max as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: averageBitRate as CFNumber)
        // Hard ceiling: allow short bursts up to 2x the average per second.
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits,
                             value: [averageBitRate * 2, 1] as CFArray)
        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    deinit {
        if let session {
            VTCompressionSessionInvalidate(session)
        }
    }

    /// Submit a frame. PTS is milliseconds from the capture clock; pass
    /// `forceKeyframe` on (re)subscribe, after a decode error, or on resume.
    func encode(_ pixelBuffer: CVPixelBuffer, ptsMilliseconds: UInt64, forceKeyframe: Bool) {
        guard let session else { return }
        let pts = CMTime(value: CMTimeValue(ptsMilliseconds), timescale: 1000)
        var properties: CFDictionary?
        if forceKeyframe {
            properties = [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary
        }
        VTCompressionSessionEncodeFrame(session,
                                        imageBuffer: pixelBuffer,
                                        presentationTimeStamp: pts,
                                        duration: .invalid,
                                        frameProperties: properties,
                                        sourceFrameRefcon: nil,
                                        infoFlagsOut: nil)
    }

    /// Flush any in-flight frames, firing the callback for each. Used at teardown
    /// and in tests to make encoding synchronous.
    func finish() {
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        }
    }

    // Called from the C callback for each emitted sample.
    fileprivate func handleEncodedSample(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        var bytes = [UInt8](repeating: 0, count: length)
        guard CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length,
                                         destination: &bytes) == kCMBlockBufferNoErr else {
            return
        }

        let isKeyframe = Self.isKeyframe(sampleBuffer)
        var parameterSets: [Data]?
        if isKeyframe, let format = CMSampleBufferGetFormatDescription(sampleBuffer) {
            parameterSets = Self.hevcParameterSets(from: format)
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let ptsMs = pts.timescale == 0 ? 0 : UInt64(max(0, pts.value * 1000 / Int64(pts.timescale)))

        onFrame(EncodedFrame(accessUnit: Data(bytes),
                             isKeyframe: isKeyframe,
                             parameterSets: parameterSets,
                             ptsMilliseconds: ptsMs))
    }

    private static func isKeyframe(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[CFString: Any]], let first = attachments.first else {
            return true  // no attachments => not explicitly a non-sync sample
        }
        // A sample is a keyframe unless it is explicitly marked "not a sync sample".
        let notSync = (first[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false
        return !notSync
    }

    private static func hevcParameterSets(from format: CMFormatDescription) -> [Data] {
        var count = 0
        guard CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
            format, parameterSetIndex: 0,
            parameterSetPointerOut: nil, parameterSetSizeOut: nil,
            parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil) == noErr else {
            return []
        }
        var sets = [Data]()
        sets.reserveCapacity(count)
        for index in 0..<count {
            var pointer: UnsafePointer<UInt8>?
            var size = 0
            if CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                format, parameterSetIndex: index,
                parameterSetPointerOut: &pointer, parameterSetSizeOut: &size,
                parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr,
               let pointer {
                sets.append(Data(bytes: pointer, count: size))
            }
        }
        return sets
    }
}

private let encoderOutputCallback: VTCompressionOutputCallback = {
    refcon, _, status, _, sampleBuffer in
    guard status == noErr, let sampleBuffer, let refcon else { return }
    let encoder = Unmanaged<CompanionVideoEncoder>.fromOpaque(refcon).takeUnretainedValue()
    encoder.handleEncodedSample(sampleBuffer)
}
