//
//  AIPluginClient.swift
//  iTerm2
//
//  Created by George Nachman on 6/5/25.
//

import CryptoKit
import JavaScriptCore

struct WebRequest: CustomDebugStringConvertible, Codable {
    var debugDescription: String {
        return "\(method) \(url)\n\(headers.debugDescription)\n\n\(body)"
    }
    var headers: [String: String]
    var method: String
    enum Body {
        case string(String)
        case bytes([UInt8])
    }
    var body: Body
    var url: String

    enum CodingKeys: String, CodingKey {
        case headers
        case method
        case body
        case url
    }

    init(headers: [String: String], method: String, body: Body, url: String) {
        self.headers = headers
        self.method = method
        self.body = body
        self.url = url
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        headers = try container.decode([String: String].self, forKey: .headers)
        method = try container.decode(String.self, forKey: .method)
        url = try container.decode(String.self, forKey: .url)

        if let stringValue = try? container.decode(String.self, forKey: .body) {
            body = .string(stringValue)
        } else if let byteArray = try? container.decode([UInt8].self, forKey: .body) {
            body = .bytes(byteArray)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .body, in: container, debugDescription: "Expected string or [UInt8] for body")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(headers, forKey: .headers)
        try container.encode(method, forKey: .method)
        try container.encode(url, forKey: .url)

        switch body {
        case .string(let s):
            try container.encode(s, forKey: .body)
        case .bytes(let bytes):
            try container.encode(bytes, forKey: .body)
        }
    }
}

struct WebResponse: Codable {
    var data: String
    var error: String?
}

struct PluginError: Error, Equatable, CustomDebugStringConvertible {
    static let cancelled = PluginError(reason: "cancelled")

    var debugDescription: String {
        return "<PluginError \(reason)>"
    }
    var localizedDescription: String {
        reason
    }
    var reason: String
}


struct Plugin {
    static private var _instance = MutableAtomicObject<Result<Plugin, PluginError>?>(nil)
    private static let publicKeyB64 = "fYLUx58QwucuPJRYxBjp7M//uVM0vTfgUo7d6u4TQR8="

    static func instance() -> Result<Plugin, PluginError> {
        return _instance.mutableAccess { result in
            switch result {
            case .success(let plugin):
                return .success(plugin)
            case .failure, .none:
                break
            }
            let temp = load()
            result = temp
            return temp
        }
    }

    private static func load() -> Result<Plugin, PluginError> {
        do {
            return  Result<Plugin, PluginError>.success(try Plugin())
        } catch let error as PluginError {
            let temp = Result<Plugin, PluginError>.failure(error)
            DLog("\(error.reason)")
            return temp
        } catch {
            DLog("\(error.localizedDescription)")
            let temp = Result<Plugin, PluginError>.failure(PluginError(reason: error.localizedDescription))
            return temp
        }
    }
    static func reload() {
        _instance.mutableAccess { result in
            result = load()
        }
    }

    private let bundleID = "com.googlecode.iterm2.iTermAI"
    private let code: String
    init() throws {
        guard let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw PluginError(reason: "Plugin not found")
        }
        let jsURL = bundleURL.appendingPathComponent("Contents/Resources/iTermAIPlugin.js")
        guard let codeData = try? Data(contentsOf: jsURL) else {
            throw PluginError(reason: "Plugin missing from app bundle or not readable")
        }
        guard let code = String(data: codeData, encoding: .utf8) else {
            throw PluginError(reason: "Plugin code not valid UTF-8")
        }
        let signatureURL = bundleURL.appendingPathComponent("Contents/Resources/iTermAIPlugin.sig")
        guard let signatureB64 = try? String(contentsOf: signatureURL) else {
            throw PluginError(reason: "Signature missing from app bundle or not readable")
        }
        guard let signatureData = Data(base64Encoded: signatureB64.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw PluginError(reason: "Signature of AI plugin is malformed")
        }
        try Plugin.checkSignature(message: codeData, signature: signatureData)
        self.code = code
    }

    private static func checkSignature(message: Data, signature: Data) throws {
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: publicKeyB64)!)
        guard publicKey.isValidSignature(signature, for: message) else {
            throw PluginError(reason: "The plugin's signature is invalid. Reinstall the plugin or upgrade iTerm2.")
        }
        DLog("Signature is good")
    }

    func version() throws -> Decimal {
        let string: String = try PluginClient.instance.call(code: code,
                                                            functionName: "version",
                                                            request: nil as Optional<String>,
                                                            async: false,
                                                            stream: nil)
        guard let decimal = Decimal(string: string) else {
            throw PluginError(reason: "Invalid version string: \(string)")
        }
        return decimal
    }

    func load(webRequest: WebRequest, stream: ((String) -> ())?) throws -> WebResponse {
        DLog("load \(webRequest)")
        return try PluginClient.instance.call(code: code,
                                              functionName: "request",
                                              request: webRequest,
                                              async: true,
                                              stream: stream)
    }

    func cancel() {
        PluginClient.instance.cancel()
    }
}

class iTermAIClient {
    private let executionQueue = DispatchQueue(label: "com.googlecode.iterm2.ai-execution")
    private let outputQueue = DispatchQueue(label: "com.googlecode.iterm2.ai-output")
    static let instance = iTermAIClient()

    var available: Bool {
        return Plugin.instance().isSuccess
    }

    func version() throws -> Decimal {
        DLog("version")
        switch Plugin.instance() {
        case .success(let plugin):
            return try plugin.version()
        case .failure(let error):
            throw error
        }
    }

    private let requiredVersion = "1.1"

    // Runs on any queue. Throws a PluginError or does nothing.
    func validate() throws {
        DLog("validate")
        if (!iTermAdvancedSettingsModel.generativeAIAllowed()) {
            throw PluginError(reason: "Plugin not allowed by administator.")
        }
        switch Plugin.instance() {
        case .success(let plugin):
            guard let pluginVersion = try? plugin.version() else {
                throw PluginError(reason: "Unable to determine version of AI plugin. Reinstall it and upgrade iTerm2 if possible.")
            }

            guard pluginVersion == Decimal(string: requiredVersion) else {
                throw PluginError(reason: "Plugin has version \(pluginVersion) but iTerm2 expects \(requiredVersion). Upgrade one or both.")
            }
            return
        case .failure(let error):
            DLog("\(error)")
            throw error
        }
    }

    func validate(_ completion: @escaping (String?) -> ()) {
        executionQueue.async {
            do {
                try self.validate()
                DispatchQueue.main.async {
                    completion(nil)
                }
            } catch let error as PluginError {
                DispatchQueue.main.async {
                    completion(error.reason)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(error.localizedDescription)
                }
            }
        }
    }

    func reload(_ completion: @escaping () -> ()) {
        executionQueue.async {
            do {
                Plugin.reload()
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }

    func request(webRequest: WebRequest,
                 stream: ((String) -> ())?,
                 completion: @escaping (Result<WebResponse, PluginError>) -> ()) -> Cancellation {
        let cancellation = Cancellation()
        executionQueue.async {
            switch Plugin.instance() {
            case .success(let plugin):
                do {
                    if cancellation.canceled {
                        throw PluginError.cancelled
                    }
                    cancellation.impl = {
                        plugin.cancel()
                    }
                    let response = try plugin.load(webRequest: webRequest, stream: stream)
                    DispatchQueue.main.async {
                        completion(.success(response))
                    }
                } catch let error as PluginError {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion(.failure(PluginError(reason: "Unexpected exception: \(error.localizedDescription)")))
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
        return cancellation
    }
}
