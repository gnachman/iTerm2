//
//  iTermScriptHistoryCall.swift
//  iTerm2SharedARC
//

import Foundation

// A message between a script and iTerm2, as the Script Console's Calls tab shows it.
//
// Describing a message is slow, and the description can be many times the size of the message (the
// response to a request for a session's contents is megabytes of text). Every message gets one of
// these but few are ever looked at, so keep the serialized message and describe it when asked to.
@objc(iTermScriptHistoryCall)
class ScriptHistoryCall: NSObject {
    private enum Origin {
        case client
        case server
    }
    private let origin: Origin
    private let date: String
    private var data: Data

    private init(origin: Origin, data: Data, date: String) {
        self.origin = origin
        self.data = data
        self.date = date
    }

    @objc(callWithClientOriginatedMessageData:date:)
    static func call(clientOriginatedMessageData data: Data, date: String) -> ScriptHistoryCall {
        return ScriptHistoryCall(origin: .client, data: data, date: date)
    }

    @objc(callWithServerOriginatedMessageData:date:)
    static func call(serverOriginatedMessageData data: Data, date: String) -> ScriptHistoryCall {
        return ScriptHistoryCall(origin: .server, data: data, date: date)
    }

    // Filtering rereads the whole history. Keep the text and release both
    // the serialized message and the temporary protobuf objects after each call.
    @objc private(set) lazy var text: String = autoreleasepool {
        defer { data = Data() }
        switch origin {
        case .client:
            let message = try? ITMClientOriginatedMessage.parse(from: data)
            return "Script → iTerm2 \(date):\n\(message?.description ?? "")\n\n"
        case .server:
            let message = try? ITMServerOriginatedMessage.parse(from: data)
            return "Script ← iTerm2 \(date):\n\(message?.description ?? "")\n\n"
        }
    }
}
