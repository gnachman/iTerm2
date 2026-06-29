//
//  CompanionProtocolVersion.swift
//  CompanionCore
//
//  App-level compatibility between the Mac app and the phone app, enforced AFTER
//  the Noise channel is up (the transport/pairing version checks are separate).
//  Each build advertises two integers:
//    - revision: this build's companion-protocol revision (bump on any breaking
//      change to the app<->phone contract).
//    - minimumPeer: the oldest peer revision this build can talk to.
//  The two sides exchange these in a hello handshake; each evaluates from its own
//  side and, if incompatible, tells the user which app to upgrade. During early
//  development you force lockstep by setting minimumPeer == revision and bumping
//  both each release.
//
//  This is a single dedicated integer, NOT CFBundleVersion: the Mac and phone
//  build numbers are independent sequences, so comparing those would be
//  meaningless.
//

import Foundation

public enum CompanionProtocolVersion {
    /// This build's companion-protocol revision. BUMP on any breaking change to
    /// the app<->phone message contract.
    public static let current = 1

    /// The oldest peer revision this build accepts. Set equal to `current` to
    /// force lockstep (early development); lower it to support older peers.
    public static let minimumPeer = 1

    /// The verdict of a version handshake, from the evaluating side's view.
    public enum Compatibility: Equatable {
        /// Both sides are in range; proceed.
        case compatible
        /// The PEER (the other app) is too old for us; the user must upgrade it.
        case peerMustUpgrade
        /// WE are too old for the peer; the user must upgrade this app.
        case selfMustUpgrade
    }

    /// Evaluate compatibility given the peer's advertised (revision, minimumPeer).
    /// Defaults use this build's own values.
    public static func evaluate(localRevision: Int = current,
                                localMinimumPeer: Int = minimumPeer,
                                peerRevision: Int,
                                peerMinimumPeer: Int) -> Compatibility {
        // If WE predate what the peer requires, we must upgrade. Checked first so
        // that when both are simultaneously out of range we tell the user to
        // upgrade the app they are looking at (resolving the standoff locally on
        // each side toward "upgrade me").
        if localRevision < peerMinimumPeer { return .selfMustUpgrade }
        // If the PEER predates what we require, they must upgrade.
        if peerRevision < localMinimumPeer { return .peerMustUpgrade }
        return .compatible
    }
}
