//
//  CompanionVideoView.swift
//  iTerm2Companion
//
//  Plays the live terminal stream. The view is backed by an
//  AVSampleBufferDisplayLayer; the Mac sends a stream config (HEVC parameter
//  sets) then a push stream of access units. We rebuild a format description
//  from the config and enqueue each access unit tagged for immediate display, so
//  a variable-frame-rate stream shows each frame on arrival and a silent period
//  simply leaves the last frame on screen.
//

import AVFoundation
import UIKit
import VideoToolbox

final class CompanionVideoView: UIView {
    /// Called when the view needs a fresh keyframe: no config yet, or the display
    /// layer failed and was flushed. The owner forwards a requestKeyframe.
    var onNeedsKeyframe: (() -> Void)?

    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    private var displayLayer: AVSampleBufferDisplayLayer {
        // Safe: layerClass guarantees the backing layer's type.
        layer as! AVSampleBufferDisplayLayer
    }

    private var formatDescription: CMFormatDescription?

    // A second, parallel decode of the same access units to CVPixelBuffers, so the
    // selection magnifier can sample the current frame's pixels (the display layer
    // never hands decoded pixels back). HEVC decode of small terminal frames is
    // cheap; the latest buffer is kept under a lock and read on the main thread.
    private var decompressionSession: VTDecompressionSession?
    private let frameLock = NSLock()
    private var _latestPixelBuffer: CVPixelBuffer?

    /// The most recently decoded frame, for the magnifier. nil until one decodes.
    func latestPixelBuffer() -> CVPixelBuffer? {
        frameLock.lock(); defer { frameLock.unlock() }
        return _latestPixelBuffer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        displayLayer.videoGravity = .resizeAspect  // letterbox, never distort
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    /// Apply a new stream configuration (parameter sets decoded from
    /// streamConfig.codecExtradata). Discards any prior format.
    func configure(parameterSets: [Data]) {
        formatDescription = try? CompanionHEVCSampleBuilder.makeFormatDescription(parameterSets: parameterSets)
        if formatDescription == nil {
            onNeedsKeyframe?()
            return
        }
        makeDecompressionSession()
    }

    private func makeDecompressionSession() {
        if let decompressionSession {
            VTDecompressionSessionInvalidate(decompressionSession)
        }
        decompressionSession = nil
        guard let formatDescription else { return }
        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault,
                                                  formatDescription: formatDescription,
                                                  decoderSpecification: nil,
                                                  imageBufferAttributes: nil,
                                                  outputCallback: nil,
                                                  decompressionSessionOut: &session)
        if status == noErr { decompressionSession = session }
    }

    /// Enqueue one access unit for immediate display.
    func enqueue(accessUnit: Data, ptsMilliseconds: UInt64) {
        guard let formatDescription else {
            // A frame arrived before (or without) a usable config: ask for a
            // keyframe, which the host always precedes with a fresh config.
            onNeedsKeyframe?()
            return
        }
        if displayLayer.status == .failed {
            displayLayer.flush()
            onNeedsKeyframe?()
        }
        guard let sample = try? CompanionHEVCSampleBuilder.makeSampleBuffer(
            accessUnit: accessUnit,
            format: formatDescription,
            ptsMilliseconds: ptsMilliseconds,
            displayImmediately: true) else {
            return
        }
        displayLayer.enqueue(sample)

        // Parallel decode for the magnifier (async, off the main thread).
        if let decompressionSession {
            _ = VTDecompressionSessionDecodeFrame(
                decompressionSession,
                sampleBuffer: sample,
                flags: [._EnableAsynchronousDecompression],
                infoFlagsOut: nil) { [weak self] status, _, imageBuffer, _, _ in
                    guard let self, status == noErr, let imageBuffer else { return }
                    self.frameLock.lock()
                    self._latestPixelBuffer = imageBuffer
                    self.frameLock.unlock()
                }
        }
    }

    /// Clear the screen and forget the format (on stop / teardown).
    func reset() {
        displayLayer.flushAndRemoveImage()
        formatDescription = nil
        if let decompressionSession {
            VTDecompressionSessionInvalidate(decompressionSession)
        }
        decompressionSession = nil
        frameLock.lock(); _latestPixelBuffer = nil; frameLock.unlock()
    }
}
