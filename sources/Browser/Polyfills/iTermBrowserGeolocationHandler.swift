//
//  iTermBrowserGeolocationHandler.swift
//  iTerm2
//
//  Created by George Nachman on 6/22/25.
//

import CoreLocation
import WebKit

@MainActor
class iTermBrowserGeolocationHandler: NSObject {
    private static var instances = [iTermBrowserUser: iTermBrowserGeolocationHandler]()
    static func instance(for user: iTermBrowserUser) -> iTermBrowserGeolocationHandler? {
        if #available(macOS 12, *) {
            if let existing = instances[user] {
                return existing
            }
            let instance = iTermBrowserGeolocationHandler(user: user)
            instances[user] = instance
            return instance
        } else {
            return nil
        }
    }

    static let messageHandlerName = "iTermGeolocation"
    private let user: iTermBrowserUser
    private let locationManager = CLLocationManager()
    private var pendingPermissionRequests = [String: CheckedContinuation<Bool, Never>]()
    private let secret: String
    
    // Active location requests
    private var pendingLocationRequests = [Int: LocationRequest]()
    private var activeWatches = [Int: WatchRequest]()

    // Location caching
    private var lastKnownLocation: CLLocation?
    private var locationTimestamp: Date?
    
    private struct LocationRequest {
        let operationId: Int
        weak var webView: iTermBrowserWebView?
        let options: GeolocationOptions
        let startTime: Date
    }
    
    private struct WatchRequest {
        let watchId: Int
        weak var webView: iTermBrowserWebView?
        let options: GeolocationOptions
    }
    
    private struct GeolocationOptions {
        let enableHighAccuracy: Bool
        let timeout: Double?
        let maximumAge: Double?
        
        init(from dict: [String: Any]) {
            self.enableHighAccuracy = dict["enableHighAccuracy"] as? Bool ?? false
            self.timeout = dict["timeout"] as? Double
            if let millis = dict["maximumAge"] as? Double {
                self.maximumAge = millis / 1000
            } else {
                self.maximumAge = 0
            }
        }
    }

    init(user: iTermBrowserUser) {
        self.user = user
        guard let secret = String.makeSecureHexString() else {
            it_fatalError("Failed to generate secure token for geolocation handler")
        }
        self.secret = secret
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
     }

    enum AuthorizationStatus {
        case denied
        case notDetermined
        case systemAuthorized
    }

    var systemAuthorizationStatus: AuthorizationStatus {
        switch CLLocationManager().authorizationStatus {
        case .notDetermined:
                .notDetermined
        case .restricted, .denied:
                .denied
        case .authorizedAlways, .authorized:
                .systemAuthorized
        @unknown default:
                .notDetermined
        }
    }

    func requestAuthorization(for origin: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            // Cancel any existing permission request from this origin
            let existingContinuation = pendingPermissionRequests[origin]
            // Store the new request
            pendingPermissionRequests[origin] = continuation
            if let existingContinuation {
                existingContinuation.resume(returning: false)
                DLog("Cancelled existing permission request from origin: \(origin)")
            }
            

            // Only request system permission if this is the first pending request
            if pendingPermissionRequests.count == 1 {
                locationManager.requestWhenInUseAuthorization()
            }
        }
    }
    
    // MARK: - JavaScript Bridge Support
    
    var javascript: String {
        return iTermBrowserTemplateLoader.loadTemplate(named: "geolocation-bridge",
                                                       type: "js",
                                                       substitutions: [ "SECRET": secret ])
    }
    
    func handleMessage(webView: iTermBrowserWebView, message: WKScriptMessage) {
        guard let messageDict = message.body as? [String: Any],
              let type = messageDict["type"] as? String,
              let sessionSecret = messageDict["sessionSecret"] as? String,
              sessionSecret == secret else {
            DLog("Invalid geolocation message format")
            return
        }
        let origin = message.frameInfo.securityOrigin
        Task {
            let originString = iTermBrowserPermissionManager.normalizeOrigin(from: origin)
            let permission = await iTermBrowserPermissionManager(user: user).requestPermission(
                for: .geolocation,
                origin: originString)
            if permission != .granted {
                DLog("Auth failed")
                return
            }
            switch type {
            case "getCurrentPosition":
                await handleGetCurrentPosition(webView: webView, messageDict: messageDict)
            case "watchPosition":
                await handleWatchPosition(webView: webView, messageDict: messageDict)
            case "clearWatch":
                await handleClearWatch(messageDict: messageDict)
            case "cancelOperation":
                await handleCancelOperation(messageDict: messageDict)
            default:
                DLog("Unknown geolocation message type: \(type)")
            }
        }
    }
}

// MARK: - Location Request Handling

@MainActor
extension iTermBrowserGeolocationHandler {
    private func handleGetCurrentPosition(webView: iTermBrowserWebView, messageDict: [String: Any]) async {
        guard let operationId = messageDict["operationId"] as? Int else {
            DLog("Missing operationId in getCurrentPosition request")
            return
        }

        let options = GeolocationOptions(from: messageDict["options"] as? [String: Any] ?? [:])
        let request = LocationRequest(operationId: operationId, webView: webView, options: options, startTime: Date())
        pendingLocationRequests[operationId] = request
        
        // Check if we can use cached position
        if let cachedPosition = getCachedPosition(maxAge: options.maximumAge) {
            await sendPositionSuccess(webView: webView, operationId: operationId, location: cachedPosition)
            pendingLocationRequests.removeValue(forKey: operationId)
            return
        }
        
        // Set timeout if specified
        if let timeout = options.timeout {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if pendingLocationRequests[operationId] != nil {
                    pendingLocationRequests.removeValue(forKey: operationId)
                    await sendPositionError(webView: webView, operationId: operationId, code: 3, message: "Timeout expired")
                }
            }
        }
        
        // Configure location manager for this request
        locationManager.desiredAccuracy = options.enableHighAccuracy ? kCLLocationAccuracyBest : kCLLocationAccuracyKilometer
        locationManager.startUpdatingLocation()
    }
    
    private func handleWatchPosition(webView: iTermBrowserWebView, messageDict: [String: Any]) async {
        guard let watchId = messageDict["watchId"] as? Int else {
            DLog("Missing watchId in watchPosition request")
            return
        }
        
        let options = GeolocationOptions(from: messageDict["options"] as? [String: Any] ?? [:])
        let watch = WatchRequest(watchId: watchId, webView: webView, options: options)
        activeWatches[watchId] = watch
        
        // Configure location manager for watching
        locationManager.desiredAccuracy = options.enableHighAccuracy ? kCLLocationAccuracyBest : kCLLocationAccuracyKilometer
        locationManager.startUpdatingLocation()
        
        // Send cached position immediately if available and fresh enough
        if let cachedPosition = getCachedPosition(maxAge: options.maximumAge) {
            await sendWatchPositionUpdate(webView: webView, watchId: watchId, location: cachedPosition)
        }
    }
    
    private func handleClearWatch(messageDict: [String: Any]) async {
        guard let watchId = messageDict["watchId"] as? Int else {
            DLog("Missing watchId in clearWatch request")
            return
        }
        
        activeWatches.removeValue(forKey: watchId)
        
        // Stop location updates if no more active watches or pending requests
        if activeWatches.isEmpty && pendingLocationRequests.isEmpty {
            locationManager.stopUpdatingLocation()
        }
    }
    
    private func handleCancelOperation(messageDict: [String: Any]) async {
        guard let operationId = messageDict["operationId"] as? Int else {
            DLog("Missing operationId in cancelOperation request")
            return
        }
        
        // Remove the cancelled operation
        pendingLocationRequests.removeValue(forKey: operationId)
        
        // Stop location updates if no more active watches or pending requests
        if activeWatches.isEmpty && pendingLocationRequests.isEmpty {
            locationManager.stopUpdatingLocation()
        }
        
        DLog("Cancelled location operation: \(operationId)")
    }
    
    // MARK: - Helper Methods
    
    private func getCachedPosition(maxAge: Double?) -> CLLocation? {
        guard let lastLocation = lastKnownLocation,
              let timestamp = locationTimestamp else {
            return nil
        }
        
        let age = Date().timeIntervalSince(timestamp)
        let maxAgeSeconds = maxAge ?? 0
        
        return age <= maxAgeSeconds ? lastLocation : nil
    }
    
    private func sendPositionSuccess(webView: iTermBrowserWebView, operationId: Int, location: CLLocation) async {
        let coords = locationToCoordinates(location)
        let timestamp = Int64(location.timestamp.timeIntervalSince1970 * 1000) // JavaScript expects milliseconds
        
        let jsCode = """
            window.iTermGeolocationHandler.handlePositionSuccess('\(secret)', \(operationId), \(coords), \(timestamp));
        """

        do {
            _ = try await webView.evaluateJavaScript(jsCode, contentWorld: .page)
        } catch {
            DLog("Error sending position success: \(error)")
        }
    }
    
    private func sendPositionError(webView: iTermBrowserWebView, operationId: Int, code: Int, message: String) async {
        let escapedMessage = message.replacingOccurrences(of: "'", with: "\\'")
        let jsCode = """
            window.iTermGeolocationHandler.handlePositionError('\(secret)', \(operationId), \(code), '\(escapedMessage)');
        """
        
        do {
            _ = try await webView.evaluateJavaScript(jsCode, contentWorld: .page)
        } catch {
            DLog("Error sending position error: \(error)")
        }
    }
    
    private func sendWatchPositionUpdate(webView: iTermBrowserWebView, watchId: Int, location: CLLocation) async {
        let coords = locationToCoordinates(location)
        let timestamp = Int64(location.timestamp.timeIntervalSince1970 * 1000)
        
        let jsCode = """
            window.iTermGeolocationHandler.handleWatchPositionUpdate('\(secret)', \(watchId), \(coords), \(timestamp));
        """
        
        do {
            _ = try await webView.evaluateJavaScript(jsCode, contentWorld: .page)
        } catch {
            DLog("Error sending watch position update: \(error)")
        }
    }
    
    private func sendWatchError(webView: iTermBrowserWebView, watchId: Int, code: Int, message: String) async {
        let escapedMessage = message.replacingOccurrences(of: "'", with: "\\'")
        let jsCode = """
            window.iTermGeolocationHandler.handleWatchError('\(secret)', \(watchId), \(code), '\(escapedMessage)');
        """
        
        do {
            _ = try await webView.evaluateJavaScript(jsCode, contentWorld: .page)
        } catch {
            DLog("Error sending watch error: \(error)")
        }
    }
    
    private func locationToCoordinates(_ location: CLLocation) -> String {
        let coords: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude": location.altitude < 0 ? "null" : "\(location.altitude)",
            "accuracy": location.horizontalAccuracy,
            "altitudeAccuracy": location.verticalAccuracy < 0 ? "null" : "\(location.verticalAccuracy)",
            "heading": location.course < 0 ? "null" : "\(location.course)",
            "speed": location.speed < 0 ? "null" : "\(location.speed)"
        ]
        
        let coordsString = coords.map { key, value in
            "\"\(key)\": \(value)"
        }.joined(separator: ", ")
        
        return "{\(coordsString)}"
    }
    
    // MARK: - Permission State Updates
    
    func updatePermissionState(for origin: String, webView: iTermBrowserWebView) async {
        let decision = await iTermBrowserPermissionManager(user: user).getPermissionDecision(
            for: .geolocation,
            origin: origin
        )
        
        let permissionString = decision == .granted ? "granted" : (decision == .denied ? "denied" : "prompt")
        let jsCode = "window.iTermGeolocationHandler.setPermission('\(secret)', '\(permissionString)');"
        
        do {
            _ = try await webView.evaluateJavaScript(jsCode, contentWorld: .page)
        } catch {
            DLog("Error updating geolocation permission state: \(error)")
        }
    }
}

extension iTermBrowserGeolocationHandler: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let requests = pendingPermissionRequests
            pendingPermissionRequests.removeAll()
            let authorized = systemAuthorizationStatus == .systemAuthorized
            for (origin, continuation) in requests {
                continuation.resume(returning: authorized)
                DLog("Authorization result for \(origin): \(authorized)")
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }

            // Update cache
            lastKnownLocation = location
            locationTimestamp = Date()

            // Handle pending single requests
            let requests = Array(pendingLocationRequests.values)
            pendingLocationRequests.removeAll()

            for request in requests {
                if let webView = request.webView {
                    Task {
                        await sendPositionSuccess(webView: webView, operationId: request.operationId, location: location)
                    }
                }
            }

            // Handle active watches
            for watch in activeWatches.values {
                if let webView = watch.webView {
                    Task {
                        await sendWatchPositionUpdate(webView: webView, watchId: watch.watchId, location: location)
                    }
                }
            }

            // Stop location updates if no more active watches
            if activeWatches.isEmpty {
                locationManager.stopUpdatingLocation()
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            let code: Int
            let message: String

            if let clError = error as? CLError {
                switch clError.code {
                case .denied:
                    code = 1
                    message = "User denied the request for Geolocation."
                case .network:
                    code = 2
                    message = "Network error while retrieving location."
                case .locationUnknown:
                    code = 2
                    message = "Location information is unavailable."
                default:
                    code = 2
                    message = "An error occurred while retrieving location: \(clError.localizedDescription)"
                }
            } else {
                code = 2
                message = "An error occurred while retrieving location: \(error.localizedDescription)"
            }

            // Handle pending single requests
            let requests = Array(pendingLocationRequests.values)
            pendingLocationRequests.removeAll()

            for request in requests {
                if let webView = request.webView {
                    Task {
                        await sendPositionError(webView: webView, operationId: request.operationId, code: code, message: message)
                    }
                }
            }

            // Handle active watches
            for watch in activeWatches.values {
                if let webView = watch.webView {
                    Task {
                        await sendWatchError(webView: webView, watchId: watch.watchId, code: code, message: message)
                    }
                }
            }

            locationManager.stopUpdatingLocation()
        }
    }
}
