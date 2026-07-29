//
//  CompanionWireVectors.swift
//  CompanionCore
//
//  THE single source of truth for the messagesSince wire vectors, compiled into
//  BOTH test targets: the package's CompanionProtocolTests (which checks the slim
//  NSEMessagesSince mirror) and the app's ModernTests (which checks the production
//  CompanionMessages enums). The two targets cannot link each other, so before
//  this they each pinned a SEPARATELY transcribed JSON literal and could silently
//  diverge. Now both assert against these same constants, so any change to the
//  wire shape must be reflected here once - and the other side's test fails if it
//  doesn't match.
//
//  This file is a member of both targets (auto-included by the SwiftPM test
//  target; added to ModernTests via the Xcode project).
//

import Foundation

enum CompanionWireVectors {
    /// messagesSince REQUEST (phone -> mac), including the one-time push nonce.
    static let messagesSinceRequest =
        #"{"requestID":9,"payload":{"messagesSince":{"collapseToken":"tok","seq":5,"limit":10,"nonce":"ab12"}}}"#

    /// messagesSince REQUEST without a nonce (older NSE / nonce-less push).
    static let messagesSinceRequestNoNonce =
        #"{"requestID":9,"payload":{"messagesSince":{"collapseToken":"tok","seq":5,"limit":10}}}"#

    /// messagesSince REPLY (mac -> phone): one agent preview, truncated, no reset.
    static let messagesSinceReply = """
    {"requestID":42,"payload":{"messagesSince":{"chatName":"Chat A",\
    "previews":[{"uniqueID":"550E8400-E29B-41D4-A716-446655440000","author":"agent","body":"hello"}],\
    "maxSeq":7,"truncated":true,"reset":false}}}
    """

    /// The uniqueID embedded in `messagesSinceReply`.
    static let replyPreviewUUID = "550E8400-E29B-41D4-A716-446655440000"

    /// syncSince REQUEST (phone -> mac), including the one-time push nonce.
    static let syncSinceRequest =
        #"{"requestID":9,"payload":{"syncSince":{"messageSeq":5,"alertSeq":3,"limit":10,"nonce":"ab12"}}}"#

    /// syncSince REQUEST without a nonce (nonce-less wakeup).
    static let syncSinceRequestNoNonce =
        #"{"requestID":9,"payload":{"syncSince":{"messageSeq":5,"alertSeq":3,"limit":10}}}"#

    /// The alertID embedded in `syncSinceReply`.
    static let replyAlertUUID = "770E8400-E29B-41D4-A716-446655440000"

    /// syncSince REPLY (mac -> phone): one message item then one alert item,
    /// truncated, no resets.
    static let syncSinceReply = """
    {"requestID":42,"payload":{"syncSince":{"items":[\
    {"message":{"chatID":"c1","chatName":"Chat A",\
    "uniqueID":"550E8400-E29B-41D4-A716-446655440000","author":"agent","body":"hello","seq":7}},\
    {"alert":{"alertID":"770E8400-E29B-41D4-A716-446655440000","threadKey":"sess-1",\
    "title":"Mark Set","body":"done","seq":4}}],\
    "maxMessageSeq":7,"maxAlertSeq":4,"messageReset":false,"alertReset":false,"truncated":true}}}
    """

    static func object(_ json: String) -> NSDictionary? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? NSDictionary
    }
}
