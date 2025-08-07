//
//  InstantReplayMovieBuilder.swift
//  iTerm2
//
//  Created by George Nachman on 8/1/25.
//

import AppKit
import CoreMedia
@preconcurrency import AVFoundation
import VideoToolbox
import QuartzCore
import ScreenCaptureKit

// Stream output handler class
class StreamOutput: NSObject, SCStreamOutput {
    var captureHandler: ((CMSampleBuffer, SCStreamOutputType) -> Void)?
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        captureHandler?(sampleBuffer, type)
    }
}

@MainActor
@available(macOS 12.3, *)
final class InstantReplayMovieBuilder: NSObject {
    private var recorders = [InMemoryVideoBuilder]()
    private let view: NSView
    // View's frame in window coordinates
    private var clipFrame: NSRect
    private let maxMemoryBytes: Int
    private let bitsPerPixel: Double
    private let profile: VideoProfile
    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var windowSize: NSSize
    private var scaleFactor: CGFloat
    private var frameRate: Double { iTermAdvancedSettingsModel.webInstantReplayFrameRate() }
    private var viewBoundsObservation: NSKeyValueObservation?
    private var viewWindowObservation: NSKeyValueObservation?
    private var frameObservations: [NSKeyValueObservation] = []
    private let maxRecorderFraction = 0.25
    private var dropFramesUntil: CFTimeInterval = 0

    init(view: NSView, maxMemoryMB: Int, bitsPerPixel: Double, profile: VideoProfile) {
        self.windowSize = view.window?.frame.size ?? view.frame.size
        self.scaleFactor = view.window?.backingScaleFactor ?? 1.0
        self.view = view
        self.maxMemoryBytes = maxMemoryMB * 1024 * 1024
        self.bitsPerPixel = bitsPerPixel
        self.profile = profile
        if view.window != nil {
            self.clipFrame = view.convert(view.bounds, to: nil) * scaleFactor
        } else {
            self.clipFrame = view.bounds * scaleFactor
        }
        super.init()
        
        // Only setup if we have both valid size and window initially
        if canStartCapture() {
            addRecorder()
            Task {
                await setupScreenCapture()
            }
        }
        
        // Observe view bounds changes
        viewBoundsObservation = view.observe(\.bounds, options: [.new]) { [weak self] _, change in
            DLog("View bounds changed")
            Task { @MainActor in
                await self?.handleViewChange()
            }
        }
        // Observe frame changes on view and its superviews
        setupFrameObservations()

        // Observe view window changes  
        viewWindowObservation = view.observe(\.window, options: [.new]) { [weak self] _, change in
            DLog("View's window changed")
            Task { @MainActor in
                // Re-setup frame observations when window changes
                self?.setupFrameObservations()
                await self?.handleViewChange()
            }
        }
    }

    deinit {
        viewBoundsObservation?.invalidate()
        viewWindowObservation?.invalidate()
        frameObservations.forEach { $0.invalidate() }
        frameObservations.removeAll()
        if let stream = self.stream {
            Task {
                try? await stream.stopCapture()
            }
        }
    }
}

extension InstantReplayMovieBuilder {
    // Returns a value in points
    func expectedSize() -> NSSize {
        return VideoStitcher.videoSize(forClipFrames: recorders.map(\.clipFrame)) / scaleFactor
    }

    func stop() {
        viewBoundsObservation?.invalidate()
        viewBoundsObservation = nil
        viewWindowObservation?.invalidate()
        viewWindowObservation = nil
        frameObservations.forEach { $0.invalidate() }
        frameObservations.removeAll()
        if let stream {
            Task {
                try? await stream.stopCapture()
            }
        }
        self.stream = nil
    }

    func save() async throws -> (URL, NSSize) {
        let directory = FileManager.default.temporaryDirectory
        var segments: [VideoStitcher.Segment] = []

        for recorder in recorders {
            if recorder.numberOfFrames == 0 {
                continue
            }
            let sampleBuffers = recorder.getSampleBuffers()
            if !sampleBuffers.isEmpty {
                segments.append(.init(windowSize: recorder.size,
                                      clipFrame: recorder.clipFrame,
                                      samples: sampleBuffers))
            }
        }

        let outputURL = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        let stitcher = VideoStitcher(inputSegments: segments,
                                     outputURL: outputURL,
                                     bitsPerPixel: bitsPerPixel,
                                     profile: profile,
                                     scaleFactor: scaleFactor)
        return try await stitcher.stitch()
    }

    func clear() {
        if stream != nil {
            stop()
            recorders = []
            if canStartCapture() {
                addRecorder()
                Task {
                    await setupScreenCapture()
                }
            }
        }
    }
}

private extension InstantReplayMovieBuilder {
    func setupFrameObservations() {
        // Clear existing observations
        frameObservations.forEach { $0.invalidate() }
        frameObservations.removeAll()
        
        // Observe frame changes on view and all superviews up to window
        var currentView: NSView? = view
        while let v = currentView {
            // Observe frame changes
            let frameObservation = v.observe(\.frame, options: [.new]) { [weak self] _, _ in
                DLog("Frame changed for view: \(v)")
                Task { @MainActor in
                    await self?.updateClipFrame()
                }
            }
            frameObservations.append(frameObservation)
            
            // Observe superview changes (parent changes)
            let superviewObservation = v.observe(\.superview, options: [.new]) { [weak self] _, _ in
                DLog("Superview changed for view: \(v)")
                Task { @MainActor in
                    // Re-setup all observations when hierarchy changes
                    self?.setupFrameObservations()
                    await self?.updateClipFrame()
                }
            }
            frameObservations.append(superviewObservation)
            
            currentView = v.superview
        }
    }
    
    func updateClipFrame() async {
        guard view.window != nil else { return }

        let newClipFrame = view.convert(view.bounds, to: nil) * scaleFactor
        guard newClipFrame != clipFrame else { return }
        
        DLog("Updating clipFrame from \(clipFrame) to \(newClipFrame)")
        clipFrame = newClipFrame
        
        // If we're currently recording and the clip frame changed significantly,
        // we might need to start a new recorder
        guard stream != nil, !recorders.isEmpty else { return }
        
        // Check if the new clip frame is different enough to warrant a new recorder
        guard let lastRecorder = recorders.last else { return }
        
        let lastClipFrame = lastRecorder.clipFrame
        if lastClipFrame.size != newClipFrame.size {
            DLog("Clip frame size changed, adding new recorder")
            addRecorder()
        }
    }
    
    func addRecorder() {
        do {
            DLog("addRecorder called")
            let pixelWidth = Int(windowSize.width * scaleFactor)
            let pixelHeight = Int(windowSize.height * scaleFactor)
            if clipFrame.size.area == 0 {
                DLog("No clip frame")
                return
            }
            if windowSize.area == 0 {
                DLog("Zero window")
                return
            }
            let recorder = try InMemoryVideoBuilder(pixelSize: NSSize(width: pixelWidth,
                                                                      height: pixelHeight),
                                                    clipFrame: clipFrame,
                                                    scaleFactor: scaleFactor,
                                                    frameRate: frameRate,
                                                    bitsPerPixel: bitsPerPixel,
                                                    profile: profile)
            recorders.append(recorder)
            DLog("addRecorder: added \(ObjectIdentifier(recorder))")
            // Remove old recorders if we exceed memory budget
            var totalMemory = recorders.map(\.memoryUsage).reduce(0, +)
            while totalMemory > Int(Double(maxMemoryBytes) * (1.0 + maxRecorderFraction)) && recorders.count > 1 {
                let removed = recorders.removeFirst()
                let removedMemory = removed.memoryUsage
                totalMemory -= removedMemory
                DLog("addRecorder: removed \(ObjectIdentifier(removed)) with \(removedMemory) bytes, total now \(totalMemory) bytes")
            }
        } catch {
            DLog("addRecorder failed: \(error)")
        }
    }

    func setupScreenCapture() async {
        do {
            DLog("setupScreenCapture called")
            guard canStartCapture() else {
                DLog("Can't capture yet")
                return
            }
            let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            guard let window = view.window,
                  let scWindow = availableContent.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                DLog("Could not find window for screen capture")
                return
            }
            
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)

            DLog("Start streaming \(scWindow)")
            let config = SCStreamConfiguration()
            let pixelWidth = Int(windowSize.width * scaleFactor)
            let pixelHeight = Int(windowSize.height * scaleFactor)
            
            DLog("Window size: \(windowSize), scale factor: \(scaleFactor), pixel size: \(pixelWidth)x\(pixelHeight)")
            
            config.width = pixelWidth
            config.height = pixelHeight
            config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(frameRate))
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = false
            
            stream = SCStream(filter: filter, configuration: config, delegate: self)
            
            // Add stream output to receive frames
            streamOutput = StreamOutput()
            streamOutput?.captureHandler = { [weak self] sampleBuffer, type in
                Task { @MainActor in
                    await self?.handleStreamOutput(sampleBuffer: sampleBuffer, type: type)
                }
            }
            try stream?.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: DispatchQueue(label: "screen.capture.output"))
            
            try await stream?.startCapture()
            
        } catch {
            DLog("setupScreenCapture failed: \(error)")
        }
    }
}

// MARK: - SCStreamDelegate  
extension InstantReplayMovieBuilder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        DLog("Screen capture stopped with error: \(error)")
    }
    
    func handleStreamOutput(sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) async {
        if stream == nil {
            // We were stopped
            return
        }
        guard type == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        // Drop frames if we're in the drop window after bounds change
        if CACurrentMediaTime() < dropFramesUntil {
            DLog("Dropping frame due to recent bounds change")
            return
        }
        
        let originalPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let mediaTime = CACurrentMediaTime()

        handleNewFrame(pixelBuffer, originalPTS: originalPTS, mediaTime: mediaTime)
    }
    
    func handleNewFrame(_ pixelBuffer: CVPixelBuffer, originalPTS: CMTime, mediaTime: CFTimeInterval) {
        let currentSize = NSSize(width: CVPixelBufferGetWidth(pixelBuffer),
                                height: CVPixelBufferGetHeight(pixelBuffer))
        let windowSize = view.window?.frame.size ?? view.bounds.size
        
        // Check if window size changed and we need to reconfigure stream
        if windowSize != self.windowSize {
            self.windowSize = windowSize
            Task {
                await reconfigureStreamForNewSize()
            }
            return
        }
        
        if currentSize != recorders.last?.size {
            addRecorder()
        }
        
        // Check if current recorder would exceed x% of memory budget
        let maxRecorderMemory = Int(Double(maxMemoryBytes) * maxRecorderFraction)
        if let currentRecorder = recorders.last,
           currentRecorder.memoryUsage > maxRecorderMemory {
            DLog("Current recorder exceeded 25% memory limit (\(currentRecorder.memoryUsage) > \(maxRecorderMemory)), creating new one")
            addRecorder()
        }
        
        recorders.last?.recordFrame(pixelBuffer, presentationTime: originalPTS, mediaTime: mediaTime)
    }
    
    func reconfigureStreamForNewSize() async {
        DLog("Reconfiguring stream for new size: \(windowSize)")
        
        // Stop current stream
        if let currentStream = stream {
            try? await currentStream.stopCapture()
        }
        
        // Add new recorder for new size
        addRecorder()
        
        // Restart stream with new configuration
        await setupScreenCapture()
    }
    
    func canStartCapture() -> Bool {
        let hasWindow = view.window != nil
        let windowSize = view.window?.frame.size ?? view.bounds.size
        let hasValidSize = windowSize.width > 0 && windowSize.height > 0
        let result = hasValidSize && hasWindow
        DLog("canStartCapture returning \(result) because hasValidSize=\(hasValidSize) and hasWindow=\(hasWindow)")
        return result
    }
    
    func handleViewChange() async {
        let currentTime = CACurrentMediaTime()
        dropFramesUntil = currentTime + 0.25  // Drop frames for 250ms
        
        // Mark frames from the last 125ms for dropping
        let cutoffTime = currentTime - 0.125
        for recorder in recorders {
            recorder.markFramesForDropping(after: cutoffTime)
        }
        
        let currentWindowSize = view.window?.frame.size ?? view.bounds.size
        let currentScaleFactor = view.window?.backingScaleFactor ?? 1.0

        // Update clipFrame
        if view.window != nil {
            clipFrame = view.convert(view.bounds, to: nil) * currentScaleFactor
        }
        
        DLog("View change - window size: \(currentWindowSize), scale: \(currentScaleFactor), window: \(view.window != nil), clipFrame: \(clipFrame)")

        let wasCapturing = stream != nil
        let canCapture = canStartCapture()
        DLog("wasCapturing=\(wasCapturing) canCapture=\(canCapture)")
        
        // If we weren't capturing but now can, start capture
        if !wasCapturing && canCapture {
            DLog("Starting capture - size: \(currentWindowSize), scale: \(currentScaleFactor)")
            windowSize = currentWindowSize
            scaleFactor = currentScaleFactor
            addRecorder()
            await setupScreenCapture()
            return
        }
        
        // If we were capturing and still can, check if size or scale factor changed
        if wasCapturing && canCapture && (currentWindowSize != windowSize || currentScaleFactor != scaleFactor) {
            DLog("Size/scale change while capturing: \(windowSize)@\(scaleFactor) -> \(currentWindowSize)@\(currentScaleFactor)")
            
            // Scale factor change requires clearing all recorders (different pixel dimensions)
            if currentScaleFactor != scaleFactor {
                DLog("Scale factor changed - clearing all recorders")
                recorders.removeAll()
            }
            
            windowSize = currentWindowSize
            scaleFactor = currentScaleFactor
            await reconfigureStreamForNewSize()
            return
        }
        
        // If we were capturing but no longer can (e.g., window removed), stop
        if wasCapturing && !canCapture {
            DLog("Stopping capture - no longer valid")
            if let currentStream = stream {
                try? await currentStream.stopCapture()
                stream = nil
            }
        }
    }
}

