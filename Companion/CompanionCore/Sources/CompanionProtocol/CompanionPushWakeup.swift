//
//  CompanionPushWakeup.swift
//  CompanionCore
//
//  The fixed, content-free collapse id for a "contentless wakeup" push (protocol
//  revision >= 2). All-zeros 128-bit hex: no real HMAC(roomSecret, chatID) token
//  can equal it, so the NSE distinguishes a wakeup (meaning "sync everything new")
//  from a legacy per-chat push (a real collapse token) purely by this sentinel.
//  Being fixed, it also lets APNs coalesce queued wakeups into one while the phone
//  is offline, and leaks no per-chat cardinality to the relay or Apple (every
//  wakeup looks identical).
//
//  Lives in the package so BOTH the mac (CompanionPushSender) and the NSE
//  (NotificationService, which links only CompanionCore) reference one definition.
//
//  When the collapse id is the sentinel vs a real per-chat token:
//
//    Sender -> Receiver            collapse id
//    --------------------------    -----------------------------------------
//    new mac -> new phone (r2)     sentinel (all-zeros), always
//    new mac -> old phone (r1)     real HMAC(roomSecret, chatID); the mac picks
//                                  the legacy push by the phone's peerRevision
//    old mac -> any phone          real HMAC(roomSecret, chatID); an old mac
//                                  only knows the per-chat push
//
//  So for a fully updated pairing every push is the sentinel: uniform, no
//  per-chat cardinality leak to the relay or Apple. The non-sentinel value a NEW
//  NSE still encounters is "new phone paired with an OLD mac", which is exactly
//  why NotificationService.didReceive branches on the sentinel (sentinel ->
//  syncSince; real token -> the legacy messagesSince path) instead of assuming
//  every push is a wakeup. On that legacy path the per-chat collapse id leaks
//  per-chat cardinality as before - unavoidable until that mac updates.
//

import Foundation

public enum CompanionPushWakeup {
    public static let collapseSentinel = String(repeating: "0", count: 32)
}
