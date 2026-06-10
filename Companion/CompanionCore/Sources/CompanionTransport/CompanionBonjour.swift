//
//  CompanionBonjour.swift
//  CompanionCore
//
//  Local-network rendezvous for the companion. The QR code carries a pairing id
//  (pid) but no network address, so the mac advertises a Bonjour service whose
//  TXT record contains the pid, and the phone browses for the service whose pid
//  matches the code it scanned. This keeps the address out of the QR code and
//  lets pairing work across DHCP changes.
//

import Foundation
import Network

public enum CompanionBonjour {
    /// Bonjour service type. The label is 10 characters (the 15-character limit
    /// excludes the leading underscore and the transport label).
    public static let serviceType = "_iterm2cmpn._tcp"

    /// TXT-record key holding the pairing id.
    public static let pairingIDKey = "pid"

    /// TXT-record key holding the protocol version, so a browsing phone can skip
    /// services it cannot speak to before attempting a connection.
    public static let versionKey = "v"

    /// TCP with keepalives. Without them, a peer that vanishes silently (wifi
    /// turned off, sleep, walked away) leaves a half-open connection that
    /// looks ESTABLISHED forever, and the survivor never notices the loss.
    public static func tcpParameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 3
        return NWParameters(tls: nil, tcp: tcp)
    }
}
