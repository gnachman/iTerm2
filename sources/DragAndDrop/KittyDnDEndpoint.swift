//
//  KittyDnDEndpoint.swift
//  iTerm2SharedARC
//
//  Kitty drag-and-drop protocol (OSC 72). See docs/kitty-dnd-design.md.
//
//  The endpoint abstracts the destination host for the Tier 2 value-add:
//  materializing a dropped file on the machine where the program actually runs.
//  In production it is backed by an SSH-integration conductor (which can write
//  files on the remote host) or by localhost (which cannot, and does not need
//  to). Faked in tests.
//

import Foundation

@MainActor
protocol KittyDnDEndpoint: AnyObject {
    /// Whether this endpoint can write files on the host where the program runs.
    /// True for an SSH-integration conductor; false for localhost (Tier 1) and
    /// for a plain-ssh session with no conductor (Tier 3).
    var canMaterializeFiles: Bool { get }

    /// Write `contents` to a fresh file derived from `name` on the endpoint's
    /// host and return its absolute path there. Only called when
    /// `canMaterializeFiles` is true.
    func materializeFile(named name: String, contents: Data) async throws -> String
}
