//
//  CompanionVideoView.swift
//  iTerm2Companion
//
//  Plays the live terminal stream. The Mac sends a stream config (HEVC parameter
//  sets) then a push stream of access units. We decode each access unit with a
//  VTDecompressionSession and display the most-recently-decoded frame directly as
//  the view's layer contents.
//
//  We deliberately do NOT use AVSampleBufferDisplayLayer: with a change-driven,
//  variable-frame-rate stream it holds the final frame in its decode/presentation
//  pipeline and does not present it until another frame is enqueued, so when the
//  screen goes idle the last update (e.g. the end of a selection drag) stays
//  invisible until something nudges a new frame through. Decoding ourselves and
//  setting layer.contents on each decoded frame shows the latest frame
//  deterministically, and the same decoded buffer feeds the selection magnifier.
//

import CoreImage
import CoreMedia
import UIKit
import VideoToolbox

final class CompanionVideoView: UIView {
    /// Called when the view needs a fresh keyframe: no config/decoder yet, or a
    /// decode failed (a lost P-frame reference). The owner forwards a requestKeyframe.
    var onNeedsKeyframe: (() -> Void)?

    private var formatDescription: CMFormatDescription?
    private var decompressionSession: VTDecompressionSession?
    private let ciContext = CIContext(options: nil)

    // The latest decoded frame, shared with the selection magnifier, and the PTS
    // of the frame currently shown so out-of-order async callbacks never regress
    // the display.
    private let frameLock = NSLock()
    private var _latestPixelBuffer: CVPixelBuffer?
    private var lastDisplayedPTSSeconds = -Double.greatestFiniteMagnitude

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.contentsGravity = .resizeAspect  // letterbox, never distort
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    /// The most recently decoded frame, for the magnifier. nil until one decodes.
    func latestPixelBuffer() -> CVPixelBuffer? {
        frameLock.lock(); defer { frameLock.unlock() }
        return _latestPixelBuffer
    }

    /// Apply a new stream configuration (parameter sets decoded from
    /// streamConfig.codecExtradata). Rebuilds the decoder; discards any prior format.
    func configure(parameterSets: [Data]) {
        formatDescription = try? CompanionHEVCSampleBuilder.makeFormatDescription(parameterSets: parameterSets)
        guard formatDescription != nil else {
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

    /// Decode one access unit and display it. `isKeyframe`/`sequence` are for logs.
    func enqueue(accessUnit: Data, ptsMilliseconds: UInt64, isKeyframe: Bool, sequence: UInt32) {
        guard let formatDescription, let session = decompressionSession else {
            // A frame arrived before (or without) a usable config/decoder: ask for
            // a keyframe, which the host always precedes with a fresh config.
            companionLog("CDIAG decode SKIP seq=\(sequence) (no decoder) -> request keyframe")
            onNeedsKeyframe?()
            return
        }
        guard let sample = try? CompanionHEVCSampleBuilder.makeSampleBuffer(
            accessUnit: accessUnit,
            format: formatDescription,
            ptsMilliseconds: ptsMilliseconds,
            displayImmediately: true) else {
            companionLog("CDIAG decode SKIP seq=\(sequence) (sample build failed)")
            return
        }
        companionLog("CDIAG decode submit seq=\(sequence) pts=\(ptsMilliseconds) key=\(isKeyframe)")
        let status = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sample,
            flags: [._EnableAsynchronousDecompression],
            infoFlagsOut: nil) { [weak self] status, _, imageBuffer, pts, _ in
                guard let self else { return }
                guard status == noErr, let imageBuffer else {
                    // A decode error usually means a lost reference frame; recover
                    // with a fresh keyframe.
                    companionLog("CDIAG decode FAILED seq=\(sequence) status=\(status) -> request keyframe")
                    self.onNeedsKeyframe?()
                    return
                }
                self.present(imageBuffer, ptsSeconds: pts.seconds, sequence: sequence)
            }
        if status != noErr {
            companionLog("CDIAG decode submit FAILED seq=\(sequence) status=\(status) -> request keyframe")
            onNeedsKeyframe?()
        }
    }

    /// Store and display a decoded frame. Called on a VideoToolbox thread; the
    /// CGImage is built here (off the main thread) and only the cheap layer
    /// contents assignment hops to main.
    private func present(_ pixelBuffer: CVPixelBuffer, ptsSeconds: Double, sequence: UInt32) {
        frameLock.lock()
        _latestPixelBuffer = pixelBuffer
        frameLock.unlock()
        let pts = ptsSeconds.isFinite ? ptsSeconds : 0
        guard let cgImage = ciContext.createCGImage(CIImage(cvPixelBuffer: pixelBuffer),
                                                    from: CIImage(cvPixelBuffer: pixelBuffer).extent) else {
            companionLog("CDIAG decode->display seq=\(sequence) FAILED (createCGImage nil)")
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard pts >= self.lastDisplayedPTSSeconds else {
                companionLog("CDIAG display SKIP seq=\(sequence) (pts \(pts) < shown \(self.lastDisplayedPTSSeconds))")
                return
            }
            self.lastDisplayedPTSSeconds = pts
            self.layer.contents = cgImage
            companionLog("CDIAG display seq=\(sequence) pts=\(pts)")
        }
    }

    /// Clear the screen and forget the decoder (on stop / teardown).
    func reset() {
        if let decompressionSession {
            VTDecompressionSessionInvalidate(decompressionSession)
        }
        decompressionSession = nil
        formatDescription = nil
        frameLock.lock(); _latestPixelBuffer = nil; frameLock.unlock()
        lastDisplayedPTSSeconds = -Double.greatestFiniteMagnitude
        layer.contents = nil
    }
}
