//
//  AIModelCredential.swift
//  iTerm2
//
//  Created by George Nachman on 10/7/26.
//

// Which secret a manually-configured model authorizes with (issue 13105).
// Inferring it from the model name and URL guesses wrong for gateways like
// Open WebUI or OpenRouter, whose model names mention another vendor
// ("gemini/gemma-4-31b-it"), so the user can choose it explicitly.
//
// The vendor (AIMetadata.Model.vendor) still decides the request dialect and
// provider binding. This only decides which key is sent.
enum AIModelCredential: Equatable {
    // Today's inference: the stored key of the vendor resolved from the API,
    // model name, and URL, withheld from local endpoints. The default, and the
    // value of every configuration saved before this setting existed.
    case automatic
    // The stored key of this vendor, sent even to a local endpoint, since the
    // user chose it.
    case vendorKey(iTermAIVendor)
    // A key stored for this model alone, in the keychain under the model's
    // configuration ID.
    case modelKey
    // No key. Authentication, if any, comes from custom headers.
    case none

    // Persisted in the manual model configuration under ManualModelKey.credential.
    // Localization unneeded: stored identifiers.
    private static let modelKeyValue = "model"
    private static let noneValue = "none"
    private static let vendorPrefix = "vendor:"

    // Anything unrecognized (absent, hand-edited, or written by a newer build)
    // reads as automatic, which is how the model behaved before.
    init(storedValue: Any?) {
        guard let string = storedValue as? String else {
            self = .automatic
            return
        }
        switch string {
        case Self.modelKeyValue:
            self = .modelKey
        case Self.noneValue:
            self = .none
        default:
            if string.hasPrefix(Self.vendorPrefix),
               let raw = UInt(string.dropFirst(Self.vendorPrefix.count)),
               let vendor = iTermAIVendor(rawValue: raw),
               AIModelCredential.selectableVendors.contains(vendor) {
                self = .vendorKey(vendor)
            } else {
                self = .automatic
            }
        }
    }

    // nil for automatic, so the key is simply left out of the configuration.
    var storedValue: String? {
        switch self {
        case .automatic:
            return nil
        case .vendorKey(let vendor):
            return Self.vendorPrefix + String(vendor.rawValue)
        case .modelKey:
            return Self.modelKeyValue
        case .none:
            return Self.noneValue
        }
    }

    // The vendors whose stored key a model can be pointed at: those with a key
    // the user can enter in Settings.
    static let selectableVendors: [iTermAIVendor] = [.openAI, .anthropic, .gemini, .deepSeek]
}

extension AIMetadata.Model {
    // The vendor whose stored key authorizes this model, which is also the one
    // to prompt for when that key is missing.
    var keyVendor: iTermAIVendor? {
        if case .vendorKey(let vendor) = credential {
            return vendor
        }
        return vendor
    }
}

// Objective-C view of AIModelCredential for the Settings UI.
@objc(iTermAICredentialKind)
enum AICredentialKind: Int {
    case automatic
    case vendorKey
    case modelKey
    case none
}

@objc(iTermAIModelCredential)
class AIModelCredentialObjC: NSObject {
    @objc(kindForStoredValue:)
    static func kind(storedValue: Any?) -> AICredentialKind {
        switch AIModelCredential(storedValue: storedValue) {
        case .automatic:
            return .automatic
        case .vendorKey:
            return .vendorKey
        case .modelKey:
            return .modelKey
        case .none:
            return .none
        }
    }

    // Meaningful only when kind is vendorKey.
    @objc(vendorForStoredValue:)
    static func vendor(storedValue: Any?) -> iTermAIVendor {
        if case .vendorKey(let vendor) = AIModelCredential(storedValue: storedValue) {
            return vendor
        }
        return .openAI
    }

    @objc(storedValueForKind:vendor:)
    static func storedValue(kind: AICredentialKind, vendor: iTermAIVendor) -> String? {
        return credential(kind: kind, vendor: vendor).storedValue
    }

    @objc static var selectableVendors: [NSNumber] {
        return AIModelCredential.selectableVendors.map { NSNumber(value: $0.rawValue) }
    }

    static func credential(kind: AICredentialKind, vendor: iTermAIVendor) -> AIModelCredential {
        switch kind {
        case .automatic:
            return .automatic
        case .vendorKey:
            return .vendorKey(vendor)
        case .modelKey:
            return .modelKey
        case .none:
            return .none
        }
    }
}
