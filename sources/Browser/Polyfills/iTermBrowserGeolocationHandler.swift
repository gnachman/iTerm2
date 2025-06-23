//
//  iTermBrowserGeolocationHandler.swift
//  iTerm2
//
//  Created by George Nachman on 6/22/25.
//

import CoreLocation
import WebKit

@available(macOS 11.0, *)
class iTermBrowserGeolocationHandler: NSObject {
    static let instance: iTermBrowserGeolocationHandler? = {
        if #available(macOS 12, *) {
            return iTermBrowserGeolocationHandler()
        } else {
            return nil
        }
    }()
    static let messageHandlerName = "iTermGeolocation"
    
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
        weak var webView: WKWebView?
        let options: GeolocationOptions
        let startTime: Date
    }
    
    private struct WatchRequest {
        let watchId: Int
        weak var webView: WKWebView?
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

    override init() {
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
        switch CLLocationManager.authorizationStatus() {
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
    
    func handleMessage(webView: WKWebView, message: WKScriptMessage) {
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
            let permission = await iTermBrowserPermissionManager.shared.requestPermission(
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

@available(macOS 11.0, *)
extension iTermBrowserGeolocationHandler {
    private func handleGetCurrentPosition(webView: WKWebView, messageDict: [String: Any]) async {
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
    
    private func handleWatchPosition(webView: WKWebView, messageDict: [String: Any]) async {
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
    
    private func sendPositionSuccess(webView: WKWebView, operationId: Int, location: CLLocation) async {
        let coords = locationToCoordinates(location)
        let timestamp = Int64(location.timestamp.timeIntervalSince1970 * 1000) // JavaScript expects milliseconds
        
        let jsCode = """
            window.iTermGeolocationHandler.handlePositionSuccess('\(secret)', \(operationId), \(coords), \(timestamp));
        """
        
        await MainActor.run {
            webView.evaluateJavaScript(jsCode) { _, error in
                if let error = error {
                    DLog("Error sending position success: \(error)")
                }
            }
        }
    }
    
    private func sendPositionError(webView: WKWebView, operationId: Int, code: Int, message: String) async {
        let escapedMessage = message.replacingOccurrences(of: "'", with: "\\'")
        let jsCode = """
            window.iTermGeolocationHandler.handlePositionError('\(secret)', \(operationId), \(code), '\(escapedMessage)');
        """
        
        await MainActor.run {
            webView.evaluateJavaScript(jsCode) { _, error in
                if let error = error {
                    DLog("Error sending position error: \(error)")
                }
            }
        }
    }
    
    private func sendWatchPositionUpdate(webView: WKWebView, watchId: Int, location: CLLocation) async {
        let coords = locationToCoordinates(location)
        let timestamp = Int64(location.timestamp.timeIntervalSince1970 * 1000)
        
        let jsCode = """
            window.iTermGeolocationHandler.handleWatchPositionUpdate('\(secret)', \(watchId), \(coords), \(timestamp));
        """
        
        await MainActor.run {
            webView.evaluateJavaScript(jsCode) { _, error in
                if let error = error {
                    DLog("Error sending watch position update: \(error)")
                }
            }
        }
    }
    
    private func sendWatchError(webView: WKWebView, watchId: Int, code: Int, message: String) async {
        let escapedMessage = message.replacingOccurrences(of: "'", with: "\\'")
        let jsCode = """
            window.iTermGeolocationHandler.handleWatchError('\(secret)', \(watchId), \(code), '\(escapedMessage)');
        """
        
        await MainActor.run {
            webView.evaluateJavaScript(jsCode) { _, error in
                if let error = error {
                    DLog("Error sending watch error: \(error)")
                }
            }
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
    
    func updatePermissionState(for origin: String, webView: WKWebView) async {
        let decision = await iTermBrowserPermissionManager.shared.getPermissionDecision(
            for: .geolocation,
            origin: origin
        )
        
        let permissionString = decision == .granted ? "granted" : (decision == .denied ? "denied" : "prompt")
        let jsCode = "window.iTermGeolocationHandler.setPermission('\(secret)', '\(permissionString)');"
        
        await MainActor.run {
            webView.evaluateJavaScript(jsCode) { _, error in
                if let error = error {
                    DLog("Error updating geolocation permission state: \(error)")
                }
            }
        }
    }
}

@available(macOS 11.0, *)
extension iTermBrowserGeolocationHandler: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let requests = pendingPermissionRequests
        pendingPermissionRequests.removeAll()
        let authorized = systemAuthorizationStatus == .systemAuthorized
        for (origin, continuation) in requests {
            continuation.resume(returning: authorized)
            DLog("Authorization result for \(origin): \(authorized)")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
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
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
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
