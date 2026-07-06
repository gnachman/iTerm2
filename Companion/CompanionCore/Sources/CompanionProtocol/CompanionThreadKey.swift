//
//  CompanionThreadKey.swift
//  CompanionCore
//
//  HMAC-SHA256(roomSecret, input) truncated to 128 bits, lowercase hex. This is
//  byte-identical to the app/Mac CompanionCollapseToken.make (same algorithm, same
//  DataHex encoder), but lives in the package so the Notification Service Extension
//  - which links only CompanionCore, not the chat-model layer that defines
//  CompanionCollapseToken - can compute it. The NSE uses it for the contentless
//  wakeup to (a) key the per-chat watermark (the value MUST match what the phone
//  app's CompanionClient writes, i.e. make(roomSecret, chatID)) and (b) derive a
//  stable on-device notification threadIdentifier from a chatID or an alert key.
//
//  Why HMAC here, honestly: on the CONTENTLESS WAKEUP path the HMAC buys NO
//  privacy. Its security value (an opaque, third-party-uncomputable per-chat tag)
//  applies only on the LEGACY per-chat push, where HMAC(roomSecret, chatID) is the
//  apns-collapse-id that the relay and Apple can see - there it keeps the chatID
//  off the wire. On the wakeup path the collapse id is the all-zeros sentinel, not
//  this value; the two uses above are BOTH on-device only (a UserDefaults key and
//  a local notification threadIdentifier), neither of which leaves the phone, so
//  the raw chatID would work just as well. The HMAC is kept solely for
//  INTEROPERABILITY: the app already writes watermarks under
//  HMAC(roomSecret, chatID) (CompanionClient.advancePushWatermark, from when the
//  watermark HAD to equal the legacy collapse token because the old NSE only had
//  the token, not the chatID), so the sync-path NSE recomputes the same value to
//  land on the same keys.
//
//  Cleanup: when revision-1 support is dropped (see CLAUDE.md), the legacy path -
//  the only place this value is exposed off-device - goes away, and the
//  watermark/thread keying can be simplified to the raw chatID, dropping this
//  HMAC (a coordinated change with CompanionClient.advancePushWatermark).
//

import Foundation
import CryptoKit

public enum CompanionThreadKey {
    public static func make(roomSecret: Data, input: String) -> String {
        let code = HMAC<SHA256>.authenticationCode(for: Data(input.utf8),
                                                   using: SymmetricKey(data: roomSecret))
        return Data(Data(code).prefix(16)).hexEncodedString()
    }
}
