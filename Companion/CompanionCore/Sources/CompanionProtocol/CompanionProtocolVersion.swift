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
    ///
    /// Revision 2 adds the contentless-wakeup push: a single content-free wakeup
    /// (the all-zeros CompanionPushWakeup.collapseSentinel) drives a unified
    /// syncSince fetch covering chat messages AND terminal alerts, replacing the
    /// per-chat collapse-token push. See docs/companion-push-relay.md.
    ///
    /// Revision 3 adds live session streaming (startSessionStream and the binary
    /// media channel). It is additive and backward-compatible: control frames are
    /// unchanged on the wire, so minimumPeer stays at 1 and a peer offers
    /// streaming only when the other side advertises at least `streamingRevision`.
    ///
    /// Revision 4 adds per-stream screen geometry (cellGeometry in streamConfig,
    /// generationId + liveTop in the media frame header) so the phone can map a
    /// touch to a terminal cell. Still additive: the geometry fields are optional /
    /// version-negotiated, so older peers stream without selection.
    ///
    /// Revision 5 adds per-chat muting (setChatMuted, the muted flag on chat-list
    /// entries). By itself that is additive: an older mac ignores the message and
    /// omits the flag, so the phone offers muting only when the mac advertises at
    /// least `chatMuteRevision`.
    ///
    /// Revision 5 also moves the companion relays (the push relay and the main
    /// pairing/transport relay) to new addresses. Every build before this one has
    /// the old relays hardcoded and registers / parks on servers that are going
    /// away, so a cross-revision pairing cannot actually deliver pushes or, once
    /// the old relay is retired, even connect. This is a HARD incompatibility, not
    /// a gracefully-degradable feature, so minimumPeer is raised to 5 to refuse
    /// any peer that predates the move.
    ///
    /// Revision 6 adds phone-driven session resize (the resizeSession message,
    /// which the mac drives into -[PTYSession reallySetCellSize:]). It is additive
    /// and backward-compatible: an older mac decodes the unknown message as
    /// `.unsupported` and ignores it, so minimumPeer stays at 5 and the phone
    /// offers the resize control only when the mac advertises at least
    /// `sessionResizeRevision`.
    ///
    /// Revision 7 adds the auto-provide consent flow (fetchAutoProvideConsent /
    /// grantAutoProvideConsent and the autoProvideConsent reply) so the phone can ask,
    /// before sending, to include a session's terminal state and visible screen with
    /// AI messages. Additive: an older mac ignores the unknown messages, so the phone
    /// offers the consent prompt only when the mac advertises at least
    /// `autoProvideConsentRevision`.
    ///
    /// Revision 8 adds the explicit turn-lifecycle event (turnLifecycle: started /
    /// ended), so the phone drives its reply notification off explicit turn
    /// boundaries instead of inferring them from typing-status edges (a mid-turn
    /// park toggles typing and would otherwise corrupt the notification). Additive:
    /// an older peer decodes the unknown message as `.unsupported` and ignores it,
    /// so minimumPeer stays 5; the mac keeps emitting typing edges so a pre-8 phone
    /// infers boundaries exactly as before, and only a peer at `turnLifecycleRevision`
    /// consumes turnLifecycle (see peerConsumesTurnLifecycle).
    public static let current = 8

    /// The oldest peer revision this build accepts. Raised to 5 (lockstep with
    /// `current`) for the relay move: peers older than revision 5 have the old
    /// relay addresses baked in and cannot interoperate, so they are refused with
    /// an upgrade wall rather than allowed to pair into a broken state. See
    /// CompanionPushRegistry.peerRevision.
    public static let minimumPeer = 5

    /// The first revision that supports live session streaming. A peer offers
    /// streaming only when the other side advertises at least this revision;
    /// otherwise it uses the static PNG-tile session view.
    public static let streamingRevision = 3

    /// The first revision that carries screen geometry with the stream (cell size,
    /// margins, generationId, liveTop). The phone offers touch selection only when
    /// the mac advertises at least this revision.
    public static let selectionGeometryRevision = 4

    /// The minimum peer revision that understands the contentless wakeup + unified
    /// syncSince (and therefore terminal alerts). Below this, the mac sends the
    /// legacy per-chat collapse push and the alert UI is disabled.
    public static let contentlessWakeupRevision = 2

    /// The first revision whose mac persists per-chat mute state (setChatMuted and
    /// the muted flag on chat-list entries). The phone offers the mute UI only when
    /// the mac advertises at least this revision.
    public static let chatMuteRevision = 5

    /// The first revision whose mac can resize a session on the phone's behalf
    /// (the resizeSession message). The phone offers the resize control only when
    /// the mac advertises at least this revision; an older mac would silently
    /// ignore the message.
    public static let sessionResizeRevision = 6

    /// The first revision whose mac supports the auto-provide consent flow
    /// (fetchAutoProvideConsent / grantAutoProvideConsent). The phone offers the
    /// consent prompt only when the mac advertises at least this revision.
    public static let autoProvideConsentRevision = 7

    /// The revision that carries the explicit turn-lifecycle event (turnLifecycle:
    /// started / ended), decoupling turn boundaries from the typing-status spinner
    /// hint so a mid-turn park can no longer corrupt the phone's reply
    /// notification. A peer at this revision drives its reply notification off these
    /// boundaries; below it, both sides fall back to typing-edge inference, and the
    /// mac emits typing edges regardless so older phones keep working. Additive
    /// either way (an unknown message decodes to `.unsupported`), so minimumPeer
    /// stays 5.
    public static let turnLifecycleRevision = 8

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
