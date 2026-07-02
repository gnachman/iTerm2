//
//  CompanionHEVCSampleBuilder.swift
//  iTerm2
//
//  Reconstructs decodable CMSampleBuffers on the receiving (phone) side from the
//  media stream: a CMVideoFormatDescription from the HEVC parameter sets carried
//  in stream config, and a CMSampleBuffer wrapping one AVCC access unit, tagged
//  for immediate display (the phone is the clock; show on arrival). Lives in
//  shared code so the full encode -> wire -> reconstruct path can be tested on
//  macOS; the runtime consumer is the iOS app's video view.
//

import CoreMedia
import Foundation

enum CompanionHEVCSampleBuilder {
    enum BuildError: Error, Equatable {
        case noParameterSets
        case formatCreationFailed(OSStatus)
        case blockBufferCreationFailed(OSStatus)
        case sampleBufferCreationFailed(OSStatus)
    }

    /// Build an HEVC format description from VPS/SPS/PPS (4-byte NAL length).
    static func makeFormatDescription(parameterSets: [Data]) throws -> CMFormatDescription {
        guard !parameterSets.isEmpty else { throw BuildError.noParameterSets }

        // Copy each set into stable heap storage so the pointers stay valid for
        // the duration of the create call.
        let buffers: [UnsafeMutablePointer<UInt8>] = parameterSets.map { set in
            let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: max(1, set.count))
            set.copyBytes(to: pointer, count: set.count)
            return pointer
        }
        defer { buffers.forEach { $0.deallocate() } }

        let pointers = buffers.map { UnsafePointer($0) }
        let sizes = parameterSets.map { $0.count }

        var format: CMFormatDescription?
        let status = pointers.withUnsafeBufferPointer { pointerBuffer in
            sizes.withUnsafeBufferPointer { sizeBuffer in
                CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: parameterSets.count,
                    parameterSetPointers: pointerBuffer.baseAddress!,
                    parameterSetSizes: sizeBuffer.baseAddress!,
                    nalUnitHeaderLength: Int32(CompanionHEVCFraming.nalLengthSize),
                    extensions: nil,
                    formatDescriptionOut: &format)
            }
        }
        guard status == noErr, let format else {
            throw BuildError.formatCreationFailed(status)
        }
        return format
    }

    /// Wrap one AVCC access unit in a CMSampleBuffer ready to enqueue on an
    /// AVSampleBufferDisplayLayer. When `displayImmediately` is set the layer
    /// shows it on arrival rather than scheduling against its timebase, which is
    /// what a variable-frame-rate live stream wants.
    static func makeSampleBuffer(accessUnit: Data,
                                 format: CMFormatDescription,
                                 ptsMilliseconds: UInt64,
                                 displayImmediately: Bool) throws -> CMSampleBuffer {
        var blockBuffer: CMBlockBuffer?
        let length = accessUnit.count
        var createStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: length,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: length,
            flags: 0,
            blockBufferOut: &blockBuffer)
        guard createStatus == kCMBlockBufferNoErr, let blockBuffer else {
            throw BuildError.blockBufferCreationFailed(createStatus)
        }
        createStatus = accessUnit.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!,
                                          blockBuffer: blockBuffer,
                                          offsetIntoDestination: 0,
                                          dataLength: length)
        }
        guard createStatus == kCMBlockBufferNoErr else {
            throw BuildError.blockBufferCreationFailed(createStatus)
        }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: CMTimeValue(ptsMilliseconds), timescale: 1000),
            decodeTimeStamp: .invalid)
        var sampleSize = length
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer)
        guard sampleStatus == noErr, let sampleBuffer else {
            throw BuildError.sampleBufferCreationFailed(sampleStatus)
        }

        if displayImmediately,
           let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let raw = CFArrayGetValueAtIndex(attachments, 0)
            let dictionary = unsafeBitCast(raw, to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sampleBuffer
    }
}
