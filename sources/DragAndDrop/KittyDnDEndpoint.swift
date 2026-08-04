//
//  KittyDnDEndpoint.swift
//  iTerm2SharedARC
//
//  Kitty drag-and-drop protocol (OSC 72). See docs/kitty-dnd-design.md.
//
//  Tells the controller whether the program runs on a different machine than the
//  terminal, which is ground truth when the session has an SSH-integration
//  conductor (even if the program sent no machine id). A remote drop is then
//  transferred in-band (X=1) rather than handed over as a local path. Faked in
//  tests.
//

import Foundation

@MainActor
protocol KittyDnDEndpoint: AnyObject {
    /// Whether the program runs on a remote host (an SSH-integration conductor is
    /// present). False for localhost.
    var isRemoteHost: Bool { get }
}
