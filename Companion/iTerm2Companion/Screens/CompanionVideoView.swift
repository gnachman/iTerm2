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

    /// Apply a new stream configuration (parameter sets decoded from
    /// streamConfig.codecExtradata). Discards any prior format.
    func configure(parameterSets: [Data]) {
        formatDescription = try? CompanionHEVCSampleBuilder.makeFormatDescription(parameterSets: parameterSets)
        if formatDescription == nil {
            onNeedsKeyframe?()
        }
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
    }

    /// Clear the screen and forget the format (on stop / teardown).
    func reset() {
        displayLayer.flushAndRemoveImage()
        formatDescription = nil
    }
}
