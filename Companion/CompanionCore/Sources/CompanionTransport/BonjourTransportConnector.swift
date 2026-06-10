//
//  BonjourTransportConnector.swift
//  CompanionCore
//
//  Local-network conformance of TransportConnector (phone side). Browses for the
//  mac's advertised companion service whose TXT pid matches the scanned code,
//  connects to it, and returns a started NWMessageTransport ready for the Noise
//  handshake. This is one transport among potentially many; see TransportConnector.
//

import Foundation
import Network
import CompanionProtocol

public struct BonjourTransportConnector: TransportConnector {
    public let transportName = "bonjour"

    public init() {}

    public func connect(to rendezvous: PairingRendezvous,
                        timeout: TimeInterval) async throws -> MessageTransport {
        let endpoint = try await discover(pairingID: rendezvous.pairingID, timeout: timeout)
        let connection = NWConnection(to: endpoint, using: CompanionBonjour.tcpParameters())
        let transport = NWMessageTransport(connection: connection)
        // A multi-homed peer can advertise addresses the connecting device
        // cannot reach (other subnets, VPN tunnels); NWConnection then sits in
        // .preparing trying candidates. Bound the wait so the failure is
        // visible instead of an eternal spinner.
        try await withDeadline(seconds: 15, label: "TCP connection to \(endpoint)") {
            try await transport.start()
        }
        return transport
    }

    private func discover(pairingID: String,
                          timeout: TimeInterval) async throws -> NWEndpoint {
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: CompanionBonjour.serviceType, domain: nil),
            using: .init())
        let queue = DispatchQueue(label: "com.googlecode.iterm2.companion.browse")
        let resumed = BrowseResumeOnce()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NWEndpoint, Error>) in
                resumed.bind(continuation, browser: browser)

                browser.browseResultsChangedHandler = { results, _ in
                    CompanionLog.log("BonjourTransportConnector: \(results.count) result(s)")
                    for result in results {
                        guard case let .bonjour(txt) = result.metadata,
                              txt[CompanionBonjour.pairingIDKey] == pairingID else {
                            continue
                        }
                        CompanionLog.log("BonjourTransportConnector: matched pid at \(result.endpoint)")
                        resumed.succeed(result.endpoint)
                        return
                    }
                }
                browser.stateUpdateHandler = { state in
                    CompanionLog.log("BonjourTransportConnector: browser state \(state)")
                    if case .failed(let error) = state {
                        resumed.fail(TransportError.translating(error))
                    }
                }
                queue.asyncAfter(deadline: .now() + timeout) {
                    resumed.fail(TransportError.connectionFailed(
                        "No iTerm2 companion service found for this pairing code"))
                }
                browser.start(queue: queue)
            }
        } onCancel: {
            // Resume the parked continuation (which also cancels the browser in
            // finish()). Cancelling the browser alone would leave the
            // continuation suspended forever, hanging the awaiting task group.
            resumed.fail(CancellationError())
        }
    }
}

/// Resumes the discovery continuation exactly once and always cancels the
/// browser afterward.
private final class BrowseResumeOnce: @unchecked Sendable {
    private let lock = UnfairLock()
    private var continuation: CheckedContinuation<NWEndpoint, Error>?
    private var browser: NWBrowser?
    private var done = false

    func bind(_ continuation: CheckedContinuation<NWEndpoint, Error>, browser: NWBrowser) {
        lock.withLock {
            self.continuation = continuation
            self.browser = browser
        }
    }

    func succeed(_ endpoint: NWEndpoint) {
        finish { $0.resume(returning: endpoint) }
    }

    func fail(_ error: Error) {
        finish { $0.resume(throwing: error) }
    }

    private func finish(_ body: (CheckedContinuation<NWEndpoint, Error>) -> Void) {
        let (continuation, browser): (CheckedContinuation<NWEndpoint, Error>?, NWBrowser?) =
            lock.withLock {
                if done { return (nil, nil) }
                done = true
                let c = self.continuation
                let b = self.browser
                self.continuation = nil
                self.browser = nil
                return (c, b)
            }
        browser?.cancel()
        if let continuation {
            body(continuation)
        }
    }
}
