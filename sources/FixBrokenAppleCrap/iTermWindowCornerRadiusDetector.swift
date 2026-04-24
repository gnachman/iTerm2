//
//  iTermWindowCornerRadiusDetector.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/8/26.
//

import Foundation
import AppKit
import CoreGraphics

@objc(iTermWindowCornerRadiusDetector)
class iTermWindowCornerRadiusDetector: NSObject {

    // Track windows that are currently transitioning to/from fullscreen.
    // Detection is skipped during these transitions because the window is animating.
    private static var windowsTransitioningFullScreen = MutableAtomicObject(Set<Int>())

    // Private queue for corner radius detection
    private static let detectionQueue = DispatchQueue(label: "com.iterm2.cornerRadiusDetection",
                                                       qos: .userInitiated,
                                                       attributes: .concurrent)

    // In-flight detection tracking to merge redundant requests
    private struct WindowInfo {
        let windowID: CGWindowID
        let windowWidth: CGFloat
        weak var window: NSWindow?
    }

    private struct InFlightDetection {
        var windows: [WindowInfo]
        var completions: [(CGFloat, Bool) -> Void]
    }

    private static var inFlightDetections = MutableAtomicObject([String: InFlightDetection]())

    @objc static func windowWillTransitionFullScreen(_ window: NSWindow) {
        DLog("windowWillTransitionFullScreen windowNumber=\(window.windowNumber)")
        windowsTransitioningFullScreen.mutate { set in
            var newSet = set
            newSet.insert(window.windowNumber)
            return newSet
        }
    }

    @objc static func windowDidTransitionFullScreen(_ window: NSWindow) {
        DLog("windowDidTransitionFullScreen windowNumber=\(window.windowNumber)")
        windowsTransitioningFullScreen.mutate { set in
            var newSet = set
            newSet.remove(window.windowNumber)
            return newSet
        }
    }

    @objc static func windowDidClose(_ window: NSWindow) {
        DLog("windowDidClose windowNumber=\(window.windowNumber)")
        windowsTransitioningFullScreen.mutate { set in
            var newSet = set
            newSet.remove(window.windowNumber)
            return newSet
        }
    }

    private static func isTransitioningFullScreen(_ window: NSWindow) -> Bool {
        let result = windowsTransitioningFullScreen.access { $0.contains(window.windowNumber) }
        DLog("isTransitioningFullScreen windowNumber=\(window.windowNumber) result=\(result)")
        return result
    }

    @objc static func cachedCornerRadius(for window: NSWindow) -> NSNumber? {
        // Lion-style fullscreen windows always have square corners
        if window.styleMask.contains(.fullScreen) {
            DLog("cachedCornerRadius returning 0 for fullscreen window \(window.windowNumber)")
            return NSNumber(value: 0)
        }

        let key = cacheKey(for: window)
        guard let cache = iTermUserDefaults.windowCornerRadiusCache else {
            DLog("cachedCornerRadius no cache, returning nil for window \(window.windowNumber) key=\(key)")
            return nil
        }
        let result = cache[key]
        DLog("cachedCornerRadius window=\(window.windowNumber) key=\(key) result=\(result?.description ?? "nil")")
        return result
    }

    @objc static func detectCornerRadius(for window: NSWindow,
                                         completion: @escaping (CGFloat, Bool) -> Void) {
        DLog("detectCornerRadius called for window \(window.windowNumber) styleMask=\(window.styleMask.rawValue)")

        // Lion-style fullscreen windows always have square corners
        if window.styleMask.contains(.fullScreen) {
            DLog("detectCornerRadius returning 0 for fullscreen window \(window.windowNumber)")
            completion(0, true)
            return
        }

        // Don't detect during fullscreen transitions - the window is animating
        if isTransitioningFullScreen(window) {
            DLog("detectCornerRadius skipping - window \(window.windowNumber) is transitioning fullscreen")
            completion(0, false)
            return
        }

        guard let windowID = CGWindowID(exactly: window.windowNumber), windowID != 0 else {
            DLog("detectCornerRadius failed - invalid windowID for window \(window.windowNumber)")
            completion(0, false)
            return
        }

        // Capture window dimensions and cache key on main thread
        let windowWidth = window.frame.width
        let cacheKeyValue = cacheKey(for: window)
        let windowInfo = WindowInfo(windowID: windowID, windowWidth: windowWidth, window: window)

        // Check if there's already an in-flight detection for this cache key
        var shouldStartDetection = false
        inFlightDetections.mutate { dict in
            var newDict = dict
            if var existing = newDict[cacheKeyValue] {
                // Add this window and completion to existing detection
                DLog("detectCornerRadius merging request for key \(cacheKeyValue)")
                existing.windows.append(windowInfo)
                existing.completions.append(completion)
                newDict[cacheKeyValue] = existing
                shouldStartDetection = false
            } else {
                // Create new in-flight detection
                DLog("detectCornerRadius starting new detection for key \(cacheKeyValue)")
                newDict[cacheKeyValue] = InFlightDetection(windows: [windowInfo], completions: [completion])
                shouldStartDetection = true
            }
            return newDict
        }

        if shouldStartDetection {
            startDetectionForCacheKey(cacheKeyValue)
        }
    }

    private static func startDetectionForCacheKey(_ cacheKeyValue: String) {
        // Get the first available window info
        guard let windowInfo = inFlightDetections.access({ $0[cacheKeyValue]?.windows.first }) else {
            DLog("startDetectionForCacheKey no windows available for key \(cacheKeyValue)")
            return
        }

        attemptDetection(attempt: 0,
                         maxAttempts: 3,
                         windowInfo: windowInfo,
                         cacheKey: cacheKeyValue)
    }

    private static func attemptDetection(attempt: Int,
                                          maxAttempts: Int,
                                          windowInfo: WindowInfo,
                                          cacheKey cacheKeyValue: String) {
        // If window was deallocated, try next window
        guard windowInfo.window != nil else {
            DLog("detectCornerRadius window deallocated, trying next window for key \(cacheKeyValue)")
            DispatchQueue.main.async {
                tryNextWindow(forCacheKey: cacheKeyValue)
            }
            return
        }

        detectionQueue.async { [weak window = windowInfo.window] in
            if let radius = detectRadius(windowID: windowInfo.windowID,
                                          windowWidth: windowInfo.windowWidth) {
                DispatchQueue.main.async {
                    DLog("detectCornerRadius completed for key \(cacheKeyValue) radius=\(radius)")
                    // Cache the result
                    var cache = iTermUserDefaults.windowCornerRadiusCache ?? [:]
                    cache[cacheKeyValue] = NSNumber(value: radius)
                    iTermUserDefaults.windowCornerRadiusCache = cache

                    // Call all completions and remove from in-flight
                    var completions: [(CGFloat, Bool) -> Void] = []
                    inFlightDetections.mutate { dict in
                        var newDict = dict
                        completions = newDict[cacheKeyValue]?.completions ?? []
                        newDict.removeValue(forKey: cacheKeyValue)
                        return newDict
                    }
                    for completion in completions {
                        completion(radius, true)
                    }
                }
                return
            }

            // Detection failed for this attempt
            let nextAttempt = attempt + 1
            if nextAttempt >= maxAttempts {
                // Max retries reached for this window, try next window
                DispatchQueue.main.async {
                    DLog("detectCornerRadius max retries for windowID \(windowInfo.windowID), trying next window")
                    tryNextWindow(forCacheKey: cacheKeyValue)
                }
                return
            }

            // Schedule retry with exponential backoff: 50ms, 100ms, 200ms, ...
            let delayMs = 50 * (1 << attempt)
            DLog("detectCornerRadius attempt \(attempt + 1) failed for windowID \(windowInfo.windowID), retrying in \(delayMs)ms")

            detectionQueue.asyncAfter(deadline: .now() + .milliseconds(delayMs)) { [weak window] in
                // Check if window still exists
                guard window != nil else {
                    DispatchQueue.main.async {
                        tryNextWindow(forCacheKey: cacheKeyValue)
                    }
                    return
                }
                attemptDetection(attempt: nextAttempt,
                                 maxAttempts: maxAttempts,
                                 windowInfo: windowInfo,
                                 cacheKey: cacheKeyValue)
            }
        }
    }

    private static func tryNextWindow(forCacheKey cacheKeyValue: String) {
        // Remove the first window (the one that failed) and try the next
        var nextWindowInfo: WindowInfo? = nil
        var completionsToFail: [(CGFloat, Bool) -> Void] = []

        inFlightDetections.mutate { dict in
            var newDict = dict
            guard var detection = newDict[cacheKeyValue] else { return newDict }
            if !detection.windows.isEmpty {
                detection.windows.removeFirst()
            }
            // Find first window that's still alive
            while let first = detection.windows.first {
                if first.window != nil {
                    newDict[cacheKeyValue] = detection
                    nextWindowInfo = first
                    return newDict
                }
                detection.windows.removeFirst()
            }
            // No more windows - extract completions and remove entry
            completionsToFail = detection.completions
            newDict.removeValue(forKey: cacheKeyValue)
            return newDict
        }

        if let windowInfo = nextWindowInfo {
            DLog("tryNextWindow starting detection with windowID \(windowInfo.windowID) for key \(cacheKeyValue)")
            attemptDetection(attempt: 0,
                             maxAttempts: 10,
                             windowInfo: windowInfo,
                             cacheKey: cacheKeyValue)
        } else if !completionsToFail.isEmpty {
            // No more windows to try, fail all completions
            DLog("tryNextWindow no more windows for key \(cacheKeyValue), failing all completions")
            for completion in completionsToFail {
                completion(0, false)
            }
        }
    }

    @objc static func cacheKey(for window: NSWindow) -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let mask = window.styleMask.rawValue
        let titleVis = window.titleVisibility == .hidden ? 0 : 1
        let scale = window.backingScaleFactor
        return "mask_\(mask)_tv_\(titleVis)_os_\(version.majorVersion)_\(version.minorVersion)_scale_\(scale)"
    }

    // MARK: - Private

    private static func detectRadius(windowID: CGWindowID,
                                     windowWidth: CGFloat) -> CGFloat? {
        guard let image = captureWindow(windowID: windowID) else {
            DLog("detectRadius failed - captureWindow returned nil for windowID=\(windowID)")
            return nil
        }

        DLog("detectRadius captured image \(image.width)x\(image.height) for windowID=\(windowID)")

        // Calculate actual scale factor from image pixels vs window points.
        let actualScaleFactor = CGFloat(image.width) / windowWidth

        // Analyze top-left corner region
        let cornerSize = min(50, image.width, image.height)
        guard let context = createBitmapContext(width: cornerSize, height: cornerSize),
              let croppedImage = image.cropping(to: CGRect(x: 0, y: 0,
                                                           width: cornerSize,
                                                           height: cornerSize)) else {
            DLog("detectRadius failed - could not create context or crop image")
            saveImageToTmp(image, windowID: windowID, suffix: "full")
            return nil
        }

        context.draw(croppedImage, in: CGRect(x: 0, y: 0, width: cornerSize, height: cornerSize))

        guard let data = context.data else {
            DLog("detectRadius failed - context.data is nil")
            saveImageToTmp(image, windowID: windowID, suffix: "full")
            return nil
        }
        let buffer = data.bindMemory(to: UInt8.self, capacity: cornerSize * cornerSize * 4)

        // Sample points along the curved edge by scanning each row.
        // For each row y, find the x where the content becomes opaque.
        // Use a threshold to skip antialiased pixels at the corner edge.
        let alphaThreshold: UInt8 = 180
        var edgePoints: [(x: Double, y: Double)] = []

        // Scan rows (for each y, find first x with alpha >= threshold)
        for y in 0..<cornerSize {
            for x in 0..<cornerSize {
                let offset = (y * cornerSize + x) * 4
                let alpha = buffer[offset + 3]
                if alpha >= alphaThreshold {
                    DLog("row scan: y=\(y) x=\(x) alpha=\(alpha)")
                    edgePoints.append((x: Double(x), y: Double(y)))
                    break
                }
            }
            // Stop when we reach x=0 - we've passed the curved portion
            if let lastPoint = edgePoints.last, lastPoint.x == 0 {
                break
            }
        }

        guard edgePoints.count >= 3 else {
            DLog("detectRadius failed - only \(edgePoints.count) edge points found (need >= 3)")
            saveImageToTmp(image, windowID: windowID, suffix: "full")
            return nil
        }

        // Find the radius that minimizes geometric error by trying all integer radii.
        // For a circle tangent to both axes, center is at (r, r) and radius is r.
        let radiusPixels = findBestRadius(points: edgePoints, maxRadius: cornerSize)
        DLog("radiusPixels=\(radiusPixels) edgePoints.count=\(edgePoints.count)")

        saveImageToTmp(image, windowID: windowID, suffix: "radius-\(radiusPixels)")

        return CGFloat(radiusPixels) / actualScaleFactor
    }

    /// Calculate sum of squared geometric errors for a given radius.
    /// For a circle centered at (r, r), the error for each point is |distance - r|.
    private static func sumOfSquaredErrors(points: [(x: Double, y: Double)],
                                           radius: Double) -> Double {
        var sse = 0.0
        for point in points {
            let dx = point.x - radius
            let dy = point.y - radius
            let dist = sqrt(dx * dx + dy * dy)
            let error = dist - radius
            sse += error * error
        }
        return sse
    }

    /// Find the radius that minimizes geometric SSE by trying all integer radii.
    private static func findBestRadius(points: [(x: Double, y: Double)],
                                       maxRadius: Int) -> Double {
        var bestRadius = 1.0
        var bestSSE = Double.infinity

        for r in 1...maxRadius {
            let radius = Double(r)
            let sse = sumOfSquaredErrors(points: points, radius: radius)
            if sse < bestSSE {
                bestSSE = sse
                bestRadius = radius
            }
        }

        return bestRadius
    }

    // Separate function to isolate the deprecation warning
    @available(macOS, deprecated: 14.0, message: "Use ScreenCaptureKit instead")
    private static func captureWindow(windowID: CGWindowID) -> CGImage? {
        return CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming]
        )
    }

    private static func createBitmapContext(width: Int, height: Int) -> CGContext? {
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func saveImageToTmp(_ image: CGImage, windowID: CGWindowID, suffix: String) {
//    let url = URL(fileURLWithPath: "/tmp/corner_debug_\(windowID)_\(suffix).png")
//    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) else {
//        DLog("failed to create image destination for \(url.path)")
//        return
//    }
//    CGImageDestinationAddImage(dest, image, nil)
//    if CGImageDestinationFinalize(dest) {
//        DLog("saved debug image to \(url.path)")
//    } else {
//        DLog("failed to save debug image to \(url.path)")
//    }
    }

    private static func saveCroppedImageToTmp(_ image: CGImage, windowID: CGWindowID) {
//      saveImageToTmp(image, windowID: windowID, suffix: "cropped")
    }
}
