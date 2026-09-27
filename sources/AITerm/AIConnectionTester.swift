//
//  AIConnectionTester.swift
//  iTerm2
//
//  Created by George Nachman on 8/2/26.
//

import AppKit

// Result of a test attempt. `.cancelled` means the user backed out of the
// API-key prompt; the caller should stay silent rather than show an alert.
@objc(iTermAIConnectionTestOutcome)
enum AIConnectionTestOutcome: Int {
    case success
    case failure
    case cancelled
}

// Drives a one-shot "does this configuration actually work?" probe for the
// manual AI model editor's Test button. Given the in-progress form values, it
// resolves the vendor exactly as request time would, obtains the API key that
// request time would send (the self-hosted placeholder for a local endpoint,
// otherwise that vendor's stored key, prompting for one via the normal
// registration sheet if none is configured), sends a minimal non-streaming
// completion through the same plugin path a real chat uses, and classifies the
// outcome into a success/failure message the caller shows in an alert.
@objc(iTermAIConnectionTester)
class AIConnectionTester: NSObject {
    // Sends the probe. `completion` is always called on the main thread.
    @objc(testModelName:url:api:functionCalling:supportsTemperature:customHeaders:inWindow:completion:)
    static func test(modelName: String,
                     url: String,
                     api: iTermAIAPI,
                     functionCalling: Bool,
                     supportsTemperature: Bool,
                     customHeaders: [[String: String]],
                     inWindow window: NSWindow,
                     completion: @escaping (AIConnectionTestOutcome, String) -> Void) {
        let vendor = LLMMetadata.objcManualVendor(api: api, url: url, modelName: modelName)
        // The App Review key wins over the placeholder policy, exactly as it
        // does in AITermController.registration: send() answers locally for it
        // and contacts nothing, which must not be pre-empted by substituting
        // the placeholder and probing a real endpoint.
        let storedKey = AITermControllerObjC.apiKey(for: vendor)
        // A self-hosted endpoint gets the placeholder key at request time, so the
        // probe must use it too. Sending the stored vendor key here made the test
        // pass against an authenticated local server that every real request then
        // 401'd (issue 13021). There is also nothing to prompt for: a key the user
        // typed would never be sent.
        if storedKey != AITermController.reviewPlaceholderAPIKey,
           let apiKey = unpromptedAPIKey(url: url, api: api) {
            send(modelName: modelName,
                 url: url,
                 api: api,
                 functionCalling: functionCalling,
                 supportsTemperature: supportsTemperature,
                 customHeaders: customHeaders,
                 apiKey: apiKey,
                 vendor: vendor,
                 completion: completion)
            return
        }
        // requestRegistration returns the stored key immediately when present,
        // otherwise presents the registration sheet on `window` and stores what
        // the user enters. A nil result means the user cancelled.
        AITermControllerRegistrationHelper.instance.requestRegistration(in: window, for: vendor) { registration in
            guard let registration else {
                completion(.cancelled, "")
                return
            }
            send(modelName: modelName,
                 url: url,
                 api: api,
                 functionCalling: functionCalling,
                 supportsTemperature: supportsTemperature,
                 customHeaders: customHeaders,
                 apiKey: registration.apiKey,
                 vendor: vendor,
                 completion: completion)
        }
    }

    // The key to probe with when it needs no input from the user, or nil when the
    // vendor's stored key applies (which may mean prompting for one).
    static func unpromptedAPIKey(url: String, api: iTermAIAPI) -> String? {
        guard AITermController.usesPlaceholderAPIKey(url: url, api: api) else {
            return nil
        }
        return AITermController.selfHostedPlaceholderAPIKey
    }

    private static func send(modelName: String,
                             url: String,
                             api: iTermAIAPI,
                             functionCalling: Bool,
                             supportsTemperature: Bool,
                             customHeaders: [[String: String]],
                             apiKey: String,
                             vendor: iTermAIVendor,
                             completion: @escaping (AIConnectionTestOutcome, String) -> Void) {
        // The reviewer placeholder key contacts no service, so a live probe would
        // fail. Report success and explain, matching the runtime short-circuit.
        if apiKey == AITermController.reviewPlaceholderAPIKey {
            completion(.success, String(localized: "AIConnectionTester.ReviewPlaceholder",
                                        defaultValue: "Placeholder key in use: AI responses are simulated for App Review and no external service is contacted.",
                                        comment: "Result of the AI connection test when the App Review placeholder key is configured"))
            return
        }
        var features = Set<AIMetadata.Model.Feature>()
        if functionCalling {
            features.insert(.functionCalling)
        }
        // Probe non-streaming with a tiny response cap: the whole point is to
        // confirm auth + endpoint reachability, not to exercise streaming.
        var model = AIMetadata.Model(name: modelName,
                                     contextWindowTokens: 8_192,
                                     maxResponseTokens: 64,
                                     url: url,
                                     api: api,
                                     features: features,
                                     vectorStoreConfig: .disabled,
                                     vendor: vendor)
        // Honor the editor's "Supports temperature" toggle so the probe omits
        // the temperature field for endpoints that 400 on it, matching what a
        // real chat request does for the saved model.
        model.supportsTemperature = supportsTemperature
        // Include the editor's custom headers so the probe carries the same
        // auth header a real request to the saved model would (issue 12975):
        // otherwise an endpoint gated by a custom Authorization header always
        // 401s the test even though real requests would succeed.
        model.customHeaders = customHeaders
        let provider = LLMProvider(model: model)
        guard provider.urlIsValid else {
            completion(.failure, String(localized: "AIConnectionTester.InvalidURL",
                                        defaultValue: "The URL is not valid.",
                                        comment: "Result of the AI connection test when the configured URL cannot be parsed"))
            return
        }
        let builder = LLMRequestBuilder(provider: provider,
                                        apiKey: apiKey,
                                        messages: [LLM.Message(role: .user, content: "Hi")],
                                        stream: false,
                                        hostedTools: HostedTools())
        let request: WebRequest
        do {
            request = try builder.webRequest()
        } catch {
            completion(.failure, String(localized: "AIConnectionTester.CouldNotBuildRequest",
                                        defaultValue: "Could not build a request: \(error.localizedDescription)",
                                        comment: "Result of the AI connection test when the request could not be constructed; the placeholder is an error description"))
            return
        }
        _ = iTermAIClient.instance.request(webRequest: request, stream: nil) { result in
            switch result {
            case .success(let response):
                let (result, message) = outcome(for: response, provider: provider)
                // The withheld-key advice only belongs on a refusal the server
                // itself sent back over credentials. Appending it to every
                // failure told someone whose Ollama server was merely down to
                // go configure authentication it does not even use.
                //
                // response.error is passed separately because outcome() prefers
                // a parsed error body, which discards the "status 401" the
                // plugin reported: a gateway that answers 401 with structured
                // JSON would otherwise lose the advice entirely.
                guard result == .failure else {
                    completion(result, message)
                    return
                }
                completion(.failure,
                           AIWithheldKeyAdvice.amended(message: message,
                                                       statusText: response.error ?? "",
                                                       url: url,
                                                       api: api,
                                                       customHeaders: customHeaders))
            case .failure(let error):
                // Same treatment as a WebResponse failure: if the plugin ever
                // reports an HTTP refusal this way, the explanation must not be
                // lost. looksLikeAuthFailure gates whether anything is added.
                completion(.failure,
                           AIWithheldKeyAdvice.amended(message: error.reason,
                                                       statusText: error.reason,
                                                       url: url,
                                                       api: api,
                                                       customHeaders: customHeaders))
            }
        }
    }

    // Classifies a successful round-trip. The plugin reports transport failures
    // via WebResponse.error; a well-formed HTTP error from the vendor arrives as
    // a 200-to-us body that decodes into an error payload. Both are failures.
    private static func outcome(for response: WebResponse,
                                provider: LLMProvider) -> (AIConnectionTestOutcome, String) {
        if let error = response.error, !error.isEmpty {
            if let reason = LLMErrorParser.errorReason(data: response.data.lossyData), !reason.isEmpty {
                return (.failure, reason)
            }
            return (.failure, error)
        }
        if let reason = LLMErrorParser.errorReason(data: response.data.lossyData), !reason.isEmpty {
            return (.failure, reason)
        }
        var parser = provider.responseParser()
        do {
            _ = try parser.parse(data: response.data.lossyData)
            return (.success, String(localized: "AIConnectionTester.Succeeded",
                                     defaultValue: "The connection succeeded. The model responded normally.",
                                     comment: "Result of a successful AI connection test"))
        } catch {
            return (.failure, String(localized: "AIConnectionTester.UnparseableReply",
                                     defaultValue: "The server responded but its reply could not be understood: \(error.localizedDescription)",
                                     comment: "Result of the AI connection test when the server's reply could not be parsed; the placeholder is an error description"))
        }
    }
}
