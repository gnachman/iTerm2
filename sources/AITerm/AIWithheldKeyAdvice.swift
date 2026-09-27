//
//  AIWithheldKeyAdvice.swift
//  iTerm2
//
//  iTerm2 withholds the stored vendor API key from some endpoints (see
//  AITermController.apiKeyPolicy). When such an endpoint then refuses the
//  request, the refusal on its own is baffling: the user configured a key and
//  it looks ignored (issue 13021). This builds the sentence that explains the
//  refusal and names the header to add, and decides which failures deserve it.
//  Shared by the Test Connection probe and by chat, so the explanation reaches
//  the user wherever the failure happens.
//

import Foundation

enum AIWithheldKeyAdvice {
    // Advice for a request that carried no vendor key, or nil when none
    // applies: the key was sent, the model already authenticates itself, or the
    // model runs on-device and has no endpoint to authenticate to.
    static func hint(url: String,
                     api: iTermAIAPI,
                     customHeaders: [[String: String]]) -> String? {
        switch AITermController.apiKeyPolicy(url: url, api: api) {
        case .vendorKey, .placeholder(.onDevice):
            return nil
        case .placeholder(.localEndpoint):
            break
        }
        let credentialHeaders = LLMAuthorizationProvider.credentialHeaderNames(url: url, api: api)
        // A header the request will actually carry is the user's own
        // authentication, so the advice would be telling them to add what they
        // already have. Suppression accepts any plausible credential name, not
        // just this lane's canonical one: an OpenAI-compatible server fronted
        // by a proxy that wants X-Api-Key is authenticated even though the
        // lane's own name is Authorization. The message still names the
        // canonical one when it is shown. Accepting ANY header instead would
        // silence the advice for a model carrying an unrelated X-Request-Id,
        // which is exactly the case the advice exists for.
        //
        // Usable mirrors AICustomHeaders.merged exactly: names match
        // case-insensitively because merged overrides that way, and the entry
        // must pass merged's validity gate, because a header merged drops never
        // reaches the server and so must not silence advice that still applies.
        // An empty value passes, since merged sends it and it replaces the
        // built-in header.
        let authenticated = customHeaders.contains { entry in
            guard let name = entry["name"],
                  AICustomHeaders.isValidName(name),
                  AICustomHeaders.isValidValue(entry["value"] ?? "") else {
                return false
            }
            return credentialHeaders.union(commonCredentialHeaderNames).contains {
                $0.caseInsensitiveCompare(name) == .orderedSame
            }
        }
        guard !authenticated else {
            return nil
        }
        // “Custom headers” below is the model editor's own label for the
        // section. The header name is quoted rather than dropped into a frame
        // like "add a %@ header": the article would have to agree with the
        // injected value (“a Authorization”), which no single frame can do in
        // English, let alone in languages with gendered articles.
        //
        // Neither sentence says why no key was sent: the Settings hints have
        // room to explain that, and this one appears next to a server's own
        // error, where brevity matters more.
        if let headerName = credentialHeaders.sorted().first {
            return String(localized: "AIConnectionTester.SelfHostedAuthHint",
                          defaultValue: "iTerm2 did not send an API key with this request. If this endpoint requires authentication, add the header “\(headerName)” under “Custom headers”.",
                          comment: "Advice shown when a request to a self-hosted AI server fails and no credential header is configured; the placeholder is an HTTP header name such as Authorization or x-api-key, and “Custom headers” is the label of a section of the model editor")
        }
        // This lane has no credential header of its own to name: Gemini carries
        // its key as a query item, Ollama sends none at all. The advice still
        // applies, and for Ollama it is the likeliest fix there is, since a 401
        // from one means a reverse proxy in front of it wants a header.
        return String(localized: "AIConnectionTester.SelfHostedAuthHintGeneric",
                      defaultValue: "iTerm2 did not send an API key with this request. If this endpoint requires authentication, add the header it expects under “Custom headers”.",
                      comment: "Advice shown when a request to a self-hosted AI server fails and the selected API has no credential header to name; “Custom headers” is the label of a section of the model editor")
    }

    // Header names a reverse proxy or gateway plausibly authenticates with.
    // Unioned with the lane's own credential header for the suppression test,
    // so a user who authenticates through a non-canonical header is not told
    // to add one.
    private static let commonCredentialHeaderNames: Set<String> = [
        "Authorization",
        "Proxy-Authorization",
        "X-Api-Key",
        "Api-Key",
        "X-Auth-Token",
        "X-Access-Token"
    ]

    // Whether a server's refusal reads like one about credentials. The plugin
    // reports HTTP status text rather than a code (WebResponse carries none) and
    // a parsed error body may mention neither, so both forms are matched by
    // callers passing each in turn. Used to keep the advice off failures it
    // cannot explain: an Ollama server that is simply not running, a malformed
    // URL, a missing model.
    static func looksLikeAuthFailure(_ message: String) -> Bool {
        // Localization unneeded: these match what a server sends back, which is
        // the vendor's English, not iTerm2's UI language.
        let needles = ["status 401",
                       "status 403",
                       "unauthorized",
                       "unauthenticated",
                       "forbidden",
                       "authentication",
                       "api key",
                       "api-key",
                       "access key",
                       "access token"]
        let haystack = message.lowercased()
        return needles.contains { haystack.contains($0) }
    }

    // Appends the advice to a failure message when the failure is one the
    // advice explains. `statusText` is the transport's own error string, which
    // may carry a status code the parsed message has already discarded.
    static func amended(message: String,
                        statusText: String,
                        url: String,
                        api: iTermAIAPI,
                        customHeaders: [[String: String]]) -> String {
        guard looksLikeAuthFailure(message) || looksLikeAuthFailure(statusText),
              let hint = hint(url: url, api: api, customHeaders: customHeaders) else {
            return message
        }
        return message.isEmpty ? hint : message + "\n\n" + hint
    }
}
