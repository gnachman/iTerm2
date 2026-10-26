//
//  OllamaModelDiscoveryProxyTests.swift
//  iTerm2
//

import Network
import XCTest
@testable import iTerm2SharedARC

// Fetch Models in the manual model editor must honor the aiProxy advanced
// setting, like chat requests and Test Connection do.
final class OllamaModelDiscoveryProxyTests: XCTestCase {
    override func tearDown() {
        AIProxySetting.settingForTesting = nil
        super.tearDown()
    }

    func testFetchModelNamesGoesThroughAIProxy() throws {
        let listener = try NWListener(using: .tcp, on: .any)
        let queue = DispatchQueue(label: "OllamaModelDiscoveryProxyTests")
        let ready = expectation(description: "listener ready")
        let connected = expectation(description: "proxy saw CONNECT")
        let connections = MutableAtomicObject<[NWConnection]>([])
        listener.stateUpdateHandler = { state in
            if case .ready = state {
                ready.fulfill()
            }
        }
        listener.newConnectionHandler = { connection in
            connections.mutate { $0 + [connection] }
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                if text.hasPrefix("CONNECT qagw.invalid:8443") {
                    connected.fulfill()
                }
                connection.cancel()
            }
        }
        listener.start(queue: queue)
        wait(for: [ready], timeout: 10)
        defer { listener.cancel() }
        let port = try XCTUnwrap(listener.port?.rawValue)
        AIProxySetting.settingForTesting = "127.0.0.1:\(port)"

        let finished = expectation(description: "fetch finished")
        OllamaModelDiscovery.fetchModelNames(fromEndpoint: "https://qagw.invalid:8443/v1/chat/completions",
                                             headers: [],
                                             timeout: 10) { names, error in
            XCTAssertEqual(names, [])
            XCTAssertNotNil(error)
            finished.fulfill()
        }
        wait(for: [connected, finished], timeout: 20)
    }
}
