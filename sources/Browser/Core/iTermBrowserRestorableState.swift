//
//  iTermBrowserRestorableState.swift
//  iTerm2
//
//  Created by George Nachman on 6/27/25.
//

@available(macOS 11, *)
struct iTermBrowserRestorableState {
    var interactionState: NSData?

    var dictionaryValue: [String: Any] {
        let dict: [CodingKeys: Any?] = [
            .interactionState: interactionState
        ]
        return dict.compactMapValues {
            $0
        }.reduce(into: [:]) { result, element in
            result[element.key.rawValue] = element.value
        }
    }

    private enum CodingKeys: String, CodingKey {
        case interactionState
    }

    static func create(from dictionary: [String: Any]) -> Self {
        return Self(
            interactionState: dictionary[CodingKeys.interactionState.rawValue] as? NSData)
    }
}
