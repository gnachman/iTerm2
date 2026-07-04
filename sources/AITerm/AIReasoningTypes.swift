//
//  AIReasoningTypes.swift
//  iTerm2
//
//  Small, platform-neutral enums shared by two places that must not depend on
//  each other:
//    - The OpenAI Responses request body (ResponsesRequestBody), which
//      typealiases its nested Effort/ServiceTier names to these.
//    - The persisted Message.Configuration, which is compiled into the iOS
//      Companion app and therefore cannot pull in the heavy, Mac-coupled
//      ResponsesAPIRequest.swift.
//
//  Keep this Foundation-only. The raw values are the wire format for persisted
//  chat history, so do not rename or reorder cases without a migration story.
//

import Foundation

enum AIReasoningEffort: String, Codable, CaseIterable {
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh
}

enum AIServiceTier: String, Codable {
    case auto
    case `default`
    case flex
    case priority
}
