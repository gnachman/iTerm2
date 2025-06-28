//
//  iTermBrowserAdblockManager.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

import Foundation
import WebKit

@available(macOS 11.0, *)
@objc(iTermBrowserAdblockManager)
class iTermBrowserAdblockManager: NSObject {
    
    // MARK: - Singleton
    
    @objc static let shared = iTermBrowserAdblockManager()
    
    // MARK: - Notifications
    
    @objc static let didUpdateRulesNotification = NSNotification.Name("iTermBrowserAdblockManagerDidUpdateRules")
    @objc static let didFailWithErrorNotification = NSNotification.Name("iTermBrowserAdblockManagerDidFailWithError")
    @objc static let errorKey = "error"
    
    // MARK: - Properties
    
    private var updateTimer: Timer?
    private var compiledRuleList: WKContentRuleList?
    private let updateInterval: TimeInterval = 24 * 60 * 60 // 24 hours
    private let maxFailureDays = 7
    
    // File paths
    private var compiledRulesPath: String {
        let appSupport = FileManager.default.applicationSupportDirectory()!
        return "\(appSupport)/adblock-compiled.json"
    }
    
    // User defaults keys for failure tracking
    private let lastUpdateKey = "NoSyncAdblockLastUpdate"

    // MARK: - Lifecycle
    
    private override init() {
        super.init()
        schedulePeriodicUpdates()
    }
    
    deinit {
        updateTimer?.invalidate()
    }
    
    // MARK: - Public Interface
    
    @objc func updateRulesIfNeeded() {
        guard iTermAdvancedSettingsModel.adblockEnabled() else {
            clearRules()
            return
        }
        
        let shouldUpdate = shouldPerformUpdate()
        if shouldUpdate {
            downloadAndUpdateRules()
        } else {
            // Load existing rules if available
            loadExistingRules()
        }
    }
    
    @objc func forceUpdate() {
        guard iTermAdvancedSettingsModel.adblockEnabled() else {
            clearRules()
            return
        }
        
        downloadAndUpdateRules()
    }
    
    @objc func getRuleList() -> WKContentRuleList? {
        return compiledRuleList
    }
    
    @objc func getRuleCount() -> Int {
        guard FileManager.default.fileExists(atPath: compiledRulesPath) else {
            return 0
        }
        
        do {
            let jsonString = try String(contentsOfFile: compiledRulesPath, encoding: .utf8)
            let jsonData = try JSONSerialization.jsonObject(with: jsonString.data(using: .utf8)!, options: []) as! [[String: Any]]
            return jsonData.count
        } catch {
            return 0
        }
    }
    
    @objc func clearRules() {
        compiledRuleList = nil
        NotificationCenter.default.post(name: Self.didUpdateRulesNotification, object: self)
    }
    
    // MARK: - Private Implementation
    
    private func schedulePeriodicUpdates() {
        updateTimer?.invalidate()
        
        // Schedule timer to run every hour and check if update is needed
        updateTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.updateRulesIfNeeded()
        }
    }
    
    private func shouldPerformUpdate() -> Bool {
        let lastUpdate = UserDefaults.standard.object(forKey: lastUpdateKey) as? Date ?? Date.distantPast
        let timeSinceUpdate = Date().timeIntervalSince(lastUpdate)
        
        // Check if we need to update (24 hours have passed)
        if timeSinceUpdate >= updateInterval {
            return true
        }
        
        // Check if we have rules loaded
        if compiledRuleList == nil && FileManager.default.fileExists(atPath: compiledRulesPath) {
            return false // Rules exist but not loaded, load them instead
        }
        
        // Check if no rules exist at all
        if !FileManager.default.fileExists(atPath: compiledRulesPath) {
            return true
        }
        
        return false
    }
    
    private func downloadAndUpdateRules() {
        let urlString = iTermAdvancedSettingsModel.adblockListURL()!
        guard let url = URL(string: urlString) else {
            let error = NSError(domain: "iTermBrowserAdblockManager", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid adblock list URL: \(urlString)"
            ])
            handleFailure(error)
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.handleFailure(error)
                    return
                }
                
                guard let data = data, let content = String(data: data, encoding: .utf8) else {
                    let error = NSError(domain: "iTermBrowserAdblockManager", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to parse adblock list response"
                    ])
                    self?.handleFailure(error)
                    return
                }
                
                self?.processDownloadedContent(content)
            }
        }
        
        task.resume()
    }
    
    private func processDownloadedContent(_ content: String) {
        // Validate JSON format
        guard let jsonData = content.data(using: .utf8),
              let _ = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Any]] else {
            let error = NSError(domain: "iTermBrowserAdblockManager", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Downloaded content is not valid JSON format"
            ])
            handleFailure(error)
            return
        }
        
        // Save compiled JSON
        do {
            try content.write(toFile: compiledRulesPath, atomically: true, encoding: .utf8)
        } catch {
            handleFailure(error)
            return
        }
        
        // Compile rules for WebKit
        compileRules(from: content)
    }
    
    private func loadExistingRules() {
        guard FileManager.default.fileExists(atPath: compiledRulesPath) else {
            // No existing rules, trigger download
            downloadAndUpdateRules()
            return
        }
        
        do {
            let jsonString = try String(contentsOfFile: compiledRulesPath, encoding: .utf8)
            compileRules(from: jsonString)
        } catch {
            // Failed to load existing rules, trigger download
            downloadAndUpdateRules()
        }
    }
    
    private func compileRules(from jsonString: String) {
        let array = try! JSONSerialization.jsonObject(with: jsonString.data(using: .utf8)!, options: []) as! [[String: Any]]
        // If a rule is bad you can binary search it with this code:
        /*
        var low = 0
        var high = array.count
        low = (low + high) / 2
        low = (low + high) / 2
        low = (low + high) / 2
        low = (low + high) / 2
        high = (low + high) / 2
        low = (low + high) / 2
        low = (low + high) / 2
        high = (low + high) / 2
        high = (low + high) / 2
        high = (low + high) / 2
        low = (low + high) / 2
        high = (low + high) / 2
        low = (low + high) / 2
        low = (low + high) / 2
        low = (low + high) / 2

//        low = (low + high) / 2
        high = (low + high) / 2
        print("\(low)..<\(high)")
        let sub = array[low..<high]
        let string = try! JSONSerialization.data(withJSONObject: Array(sub), options: []).lossyString
         */

        let string = try! JSONSerialization.data(withJSONObject: array, options: []).lossyString
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "iTerm2-Adblock",
            encodedContentRuleList: string
        ) { [weak self] ruleList, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.handleFailure(error)
                    return
                }
                
                self?.compiledRuleList = ruleList
                self?.handleSuccess()
            }
        }
    }
    
    private func handleSuccess() {
        // Record successful update
        UserDefaults.standard.set(Date(), forKey: lastUpdateKey)

        NotificationCenter.default.post(name: Self.didUpdateRulesNotification, object: self)
    }
    
    private func handleFailure(_ error: Error) {
        DLog("Adblock update failed: \(error.localizedDescription)")

        // Check if we should notify user about prolonged failures
        checkForProlongedFailure()
        
        NotificationCenter.default.post(
            name: Self.didFailWithErrorNotification,
            object: self,
            userInfo: [Self.errorKey: error]
        )
    }
    
    private func checkForProlongedFailure() {
        guard let lastUpdate = UserDefaults.standard.object(forKey: lastUpdateKey) as? Date else {
            return // Never had a successful update
        }
        
        let daysSinceUpdate = Calendar.current.dateComponents([.day], from: lastUpdate, to: Date()).day ?? 0
        
        if daysSinceUpdate >= maxFailureDays {
            let error = NSError(domain: "iTermBrowserAdblockManager", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Adblock rules haven't been updated for \(daysSinceUpdate) days"
            ])
            NotificationCenter.default.post(
                name: Self.didFailWithErrorNotification,
                object: self,
                userInfo: [Self.errorKey: error]
            )
        }
    }
}
