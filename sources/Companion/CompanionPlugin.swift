//
//  CompanionPlugin.swift
//  iTerm2
//
//  Discovers, signature-verifies, and version-checks the companion consent
//  plugin, modeled on the AI plugin (AIPluginClient.swift). The plugin is a
//  separate signed .app; iTerm2 finds it by bundle id, loads its JavaScript,
//  and verifies an EdDSA signature against a key baked into iTerm2 before
//  running any of it. The shipped binary has no relay endpoint, so installing
//  the plugin is the consent and the capability.
//

import CryptoKit
import JavaScriptCore
import CompanionTransport

struct CompanionPlugin {
    static private var _instance = MutableAtomicObject<Result<CompanionPlugin, PluginError>?>(nil)

    // The Curve25519 public key the plugin's JS is signed against. The matching
    // private key is held out-of-band (not in the repo); the plugin .app bundles
    // iTermCompanionPlugin.{js,sig} and the signature is verified before any of
    // the plugin runs.
    private static let publicKeyB64 = "GHS0N02DR3kF7u3gqB5GF52dmre/oUkJuarQzEv8crw="

    private let bundleID = "com.googlecode.iterm2.iTermCompanion"
    let client: CompanionPluginClient
    /// Where the verified plugin .app lives on disk (for "Reveal in Finder").
    let bundleURL: URL

    /// Cached: the plugin is found and verified once, then reused.
    static func instance() -> Result<CompanionPlugin, PluginError> {
        _instance.mutableAccess { result in
            if case .success(let plugin) = result { return .success(plugin) }
            let loaded = load()
            result = loaded
            return loaded
        }
    }

    static func reload() {
        _instance.mutableAccess { $0 = load() }
    }

    private static func load() -> Result<CompanionPlugin, PluginError> {
        do {
            return .success(try CompanionPlugin())
        } catch let error as PluginError {
            DLog("\(error.reason)")
            return .failure(error)
        } catch {
            return .failure(PluginError(reason: error.localizedDescription))
        }
    }

    init() throws {
        guard let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw PluginError(reason: "Companion plugin not installed")
        }
        let jsURL = bundleURL.appendingPathComponent("Contents/Resources/iTermCompanionPlugin.js")
        guard let codeData = try? Data(contentsOf: jsURL) else {
            throw PluginError(reason: "Companion plugin code missing or unreadable")
        }
        guard let code = String(data: codeData, encoding: .utf8) else {
            throw PluginError(reason: "Companion plugin code is not valid UTF-8")
        }
        let signatureURL = bundleURL.appendingPathComponent("Contents/Resources/iTermCompanionPlugin.sig")
        guard let signatureB64 = try? String(contentsOf: signatureURL),
              let signature = Data(base64Encoded: signatureB64.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw PluginError(reason: "Companion plugin signature missing or malformed")
        }
        try CompanionPlugin.checkSignature(message: codeData, signature: signature)
        self.client = CompanionPluginClient(code: code)
        self.bundleURL = bundleURL
    }

    private static func checkSignature(message: Data, signature: Data) throws {
        guard let keyData = Data(base64Encoded: publicKeyB64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              publicKey.isValidSignature(signature, for: message) else {
            throw PluginError(reason: "The companion plugin's signature is invalid. Reinstall the plugin or upgrade iTerm2.")
        }
        DLog("Companion plugin signature is good")
    }

    /// A relay socket factory that routes all egress through this plugin.
    func webSocketFactory() -> RelayWebSocketFactory {
        PluginRelayWebSocketFactory(client: client)
    }

    func version() async throws -> Decimal {
        let string = try await client.version()
        guard let decimal = Decimal(string: string) else {
            throw PluginError(reason: "Invalid companion plugin version: \(string)")
        }
        return decimal
    }
}
