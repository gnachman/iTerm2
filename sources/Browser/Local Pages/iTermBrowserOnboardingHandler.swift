//
//  iTermBrowserOnboardingHandler.swift
//  iTerm2
//
//  Created for iTerm2 Browser onboarding flow
//

import Foundation
@preconcurrency import WebKit

@available(macOS 11.0, *)
struct iTermBrowserOnboardingSettings {
    let adBlockerEnabled: Bool
    let instantReplayEnabled: Bool
}

@available(macOS 11.0, *)
protocol iTermBrowserOnboardingHandlerDelegate: AnyObject {
    @MainActor func onboardingHandlerEnableAdBlocker(_ handler: iTermBrowserOnboardingHandler)
    @MainActor func onboardingHandlerEnableInstantReplay(_ handler: iTermBrowserOnboardingHandler) 
    @MainActor func onboardingHandlerCreateBrowserProfile(_ handler: iTermBrowserOnboardingHandler) -> String?
    @MainActor func onboardingHandlerSwitchToProfile(_ handler: iTermBrowserOnboardingHandler, guid: String)
    @MainActor func onboardingHandlerCheckBrowserProfileExists(_ handler: iTermBrowserOnboardingHandler) -> Bool
    @MainActor func onboardingHandlerFindBrowserProfileGuid(_ handler: iTermBrowserOnboardingHandler) -> String?
    @MainActor func onboardingHandlerGetSettings(_ handler: iTermBrowserOnboardingHandler) -> iTermBrowserOnboardingSettings
}

@available(macOS 11.0, *)
@objc(iTermBrowserOnboardingHandler)
@MainActor
class iTermBrowserOnboardingHandler: NSObject, iTermBrowserPageHandler {
    static let setupURL = URL(string: "\(iTermBrowserSchemes.about):onboarding-setup")!
    static let profileURL = URL(string: "\(iTermBrowserSchemes.about):onboarding-profile")!

    weak var delegate: iTermBrowserOnboardingHandlerDelegate?
    private let secret: String
    private let user: iTermBrowserUser
    private var createdProfileGuid: String?

    init(user: iTermBrowserUser) {
        self.user = user
        guard let secret = String.makeSecureHexString() else {
            it_fatalError("Failed to generate secure hex string for onboarding handler")
        }
        self.secret = secret
        super.init()
    }

    // MARK: - iTermBrowserPageHandler

    func start(urlSchemeTask: WKURLSchemeTask, url: URL) {
        // Determine which template to load based on URL
        let templateName: String
        if url == Self.profileURL {
            templateName = "onboarding-profile"
        } else {
            templateName = "onboarding-setup"
        }
        
        let htmlToServe = iTermBrowserTemplateLoader.loadTemplate(
            named: templateName,
            type: "html",
            substitutions: ["SECRET": secret]
        )

        guard let data = htmlToServe.data(using: .utf8) else {
            urlSchemeTask.didFailWithError(NSError(domain: "iTermBrowserOnboardingHandler", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode HTML"]))
            return
        }

        let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    // MARK: - Message Handling

    func handleOnboardingMessage(_ message: [String: Any], webView: iTermBrowserWebView) {
        guard let action = message["action"] as? String,
              let sessionSecret = message["sessionSecret"] as? String,
              sessionSecret == secret else {
            DLog("Invalid or missing session secret for onboarding action")
            return
        }

        switch action {
        case "enableAdBlocker":
            delegate?.onboardingHandlerEnableAdBlocker(self)
            updateUIStatus("adblocker-status", enabled: true, webView: webView)

        case "enableInstantReplay":
            delegate?.onboardingHandlerEnableInstantReplay(self)
            updateUIStatus("replay-status", enabled: true, webView: webView)

        case "createBrowserProfile":
            if let guid = delegate?.onboardingHandlerCreateBrowserProfile(self) {
                createdProfileGuid = guid
                let script = "onProfileCreated(true);"
                Task { @MainActor in
                    _ = try? await webView.safelyEvaluateJavaScript(script, contentWorld: .page)
                }
            } else {
                // Profile already existed
                createdProfileGuid = delegate?.onboardingHandlerFindBrowserProfileGuid(self)
                let script = "onProfileCreated(false);"
                Task { @MainActor in
                    _ = try? await webView.safelyEvaluateJavaScript(script, contentWorld: .page)
                }
            }
            
        case "checkProfileExists":
            let exists = delegate?.onboardingHandlerCheckBrowserProfileExists(self) ?? false
            if exists {
                createdProfileGuid = delegate?.onboardingHandlerFindBrowserProfileGuid(self)
                let script = "onProfileCreated(false);" // false means it already existed
                Task { @MainActor in
                    _ = try? await webView.safelyEvaluateJavaScript(script, contentWorld: .page)
                }
            }
            
        case "switchToProfile":
            if let guid = createdProfileGuid ?? delegate?.onboardingHandlerFindBrowserProfileGuid(self) {
                delegate?.onboardingHandlerSwitchToProfile(self, guid: guid)
            } else {
                DLog("No browser profile found to switch to")
            }
            
        case "getSettingsStatus":
            sendSettingsStatus(to: webView)
            
        case "completeOnboarding":
            UserDefaults.standard.set(true, forKey: "NoSyncBrowserOnboardingCompleted")

        default:
            DLog("Unknown onboarding action: \(action)")
        }
    }

    private func updateUIStatus(_ statusId: String, enabled: Bool, webView: iTermBrowserWebView) {
        let script = "updateStatus('\(statusId)', \(enabled));"
        Task { @MainActor in
            _ = try? await webView.safelyEvaluateJavaScript(script, contentWorld: .page)
        }
    }
    
    private func sendSettingsStatus(to webView: iTermBrowserWebView) {
        let settings = delegate?.onboardingHandlerGetSettings(self) ?? iTermBrowserOnboardingSettings(adBlockerEnabled: false, instantReplayEnabled: false)
        let profileExists = delegate?.onboardingHandlerCheckBrowserProfileExists(self) ?? false
        
        let script = """
        updateInitialStatus({
            adBlockerEnabled: \(settings.adBlockerEnabled),
            instantReplayEnabled: \(settings.instantReplayEnabled),
            profileExists: \(profileExists)
        });
        """
        Task { @MainActor in
            _ = try? await webView.safelyEvaluateJavaScript(script, contentWorld: .page)
        }
    }
    
    func injectJavaScript(into webView: iTermBrowserWebView) {

    }

    func resetState() {

    }
}
