//
//  AIPluginClientConcurrentCancelTests.swift
//  ModernTests
//
//  Cancelling one AI request must cancel exactly that request's HTTP
//  transfer, even while another request (from another chat) is in flight.
//

import XCTest
@testable import iTerm2SharedARC

// Holds every request until the test releases it, so the test controls which
// requests are in flight. Records which requests were stopped (cancelled).
private final class GatedURLProtocol: URLProtocol {
    final class Registry {
        private let lock = NSLock()
        private var started = [String: GatedURLProtocol]()
        private var stopped = Set<String>()
        private var startExpectations = [String: XCTestExpectation]()
        private var stopExpectations = [String: XCTestExpectation]()

        func expectStart(_ name: String, _ expectation: XCTestExpectation) {
            lock.withLock { startExpectations[name] = expectation }
        }

        func expectStop(_ name: String, _ expectation: XCTestExpectation) {
            lock.withLock { stopExpectations[name] = expectation }
        }

        func didStart(_ name: String, _ proto: GatedURLProtocol) {
            let expectation = lock.withLock {
                started[name] = proto
                return startExpectations[name]
            }
            expectation?.fulfill()
        }

        func didStop(_ name: String) {
            let expectation = lock.withLock {
                stopped.insert(name)
                return stopExpectations.removeValue(forKey: name)
            }
            expectation?.fulfill()
        }

        func wasStopped(_ name: String) -> Bool {
            lock.withLock { stopped.contains(name) }
        }

        func wasStarted(_ name: String) -> Bool {
            lock.withLock { started[name] != nil }
        }

        func protocolInstance(_ name: String) -> GatedURLProtocol? {
            lock.withLock { started[name] }
        }
    }

    static var registry = Registry()

    private var clientRunLoop: CFRunLoop?
    // URLSession also calls stopLoading after a normal finish, so only a stop
    // before respond() finished the load counts as a cancellation.
    private let finished = MutableAtomicObject(false)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var name: String { request.url?.lastPathComponent ?? "" }

    override func startLoading() {
        // URLProtocol client callbacks must run on the loading thread's run loop.
        clientRunLoop = CFRunLoopGetCurrent()
        Self.registry.didStart(name, self)
    }

    override func stopLoading() {
        if !finished.value {
            Self.registry.didStop(name)
        }
    }

    // Completes the request with a 200 and the given body.
    func respond(body: String) {
        guard let clientRunLoop, let url = request.url else {
            return
        }
        CFRunLoopPerformBlock(clientRunLoop, CFRunLoopMode.commonModes.rawValue) {
            let response = HTTPURLResponse(url: url,
                                           statusCode: 200,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: nil)!
            self.finished.set(true)
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: body.data(using: .utf8)!)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        CFRunLoopWakeUp(clientRunLoop)
    }
}

final class AIPluginClientConcurrentCancelTests: XCTestCase {
    // A minimal plugin: one HTTP request whose body and error become the
    // WebResponse, the same shape the real plugin uses.
    private static let pluginCode = """
    function request(json) {
        const req = JSON.parse(json);
        return new Promise(function(resolve) {
            performHTTPRequest(req.method, req.url, req.headers, req.body, function(body, error) {
                resolve(JSON.stringify({ data: body || "", error: error }));
            });
        });
    }
    """

    override func setUp() {
        super.setUp()
        GatedURLProtocol.registry = GatedURLProtocol.Registry()
        PluginClient.protocolClassesForTesting = [GatedURLProtocol.self]
        iTermAIClient.pluginOverrideForTesting = Plugin(testingCode: Self.pluginCode)
    }

    override func tearDown() {
        PluginClient.protocolClassesForTesting = nil
        iTermAIClient.pluginOverrideForTesting = nil
        super.tearDown()
    }

    private func webRequest(_ name: String) -> WebRequest {
        WebRequest(headers: [:],
                   method: "POST",
                   body: .string("{}"),
                   url: "https://plugin-test.invalid/\(name)")
    }

    // Two chats each have their own iTermAIClient. Pressing Stop in the chat
    // whose request started first must cancel that request's transfer and
    // leave the other chat's request running to a normal completion.
    func testCancellingFirstOfTwoConcurrentRequestsCancelsOnlyIt() {
        let registry = GatedURLProtocol.registry
        let clientA = iTermAIClient()
        let clientB = iTermAIClient()

        let startedA = expectation(description: "A started")
        registry.expectStart("a", startedA)
        let doneA = expectation(description: "A completed")
        let cancellationA = clientA.request(webRequest: webRequest("a"), stream: nil) { _ in
            doneA.fulfill()
        }
        wait(for: [startedA], timeout: 10)

        let startedB = expectation(description: "B started")
        registry.expectStart("b", startedB)
        let doneB = expectation(description: "B completed")
        var resultB: Result<WebResponse, PluginError>?
        _ = clientB.request(webRequest: webRequest("b"), stream: nil) { result in
            resultB = result
            doneB.fulfill()
        }
        wait(for: [startedB], timeout: 10)

        let stoppedA = expectation(description: "A's transfer stopped")
        registry.expectStop("a", stoppedA)
        cancellationA.cancel()
        wait(for: [stoppedA, doneA], timeout: 10)
        XCTAssertFalse(registry.wasStopped("b"), "Cancelling A stopped B's transfer")

        registry.protocolInstance("b")?.respond(body: "hello from b")
        wait(for: [doneB], timeout: 10)
        switch resultB {
        case .success(let response):
            XCTAssertEqual(response.data, "hello from b")
            XCTAssertEqual(response.error, "")
        case .failure(let error):
            XCTFail("B failed: \(error)")
        case .none:
            XCTFail("B never completed")
        }
        XCTAssertFalse(registry.wasStopped("b"))
    }

    // Cancelling a request that already finished must not touch a request
    // that another chat started afterwards.
    func testCancellingFinishedRequestDoesNotAffectLaterRequest() {
        let registry = GatedURLProtocol.registry
        let clientA = iTermAIClient()
        let clientB = iTermAIClient()

        let startedA = expectation(description: "A started")
        registry.expectStart("a", startedA)
        let doneA = expectation(description: "A completed")
        let cancellationA = clientA.request(webRequest: webRequest("a"), stream: nil) { _ in
            doneA.fulfill()
        }
        wait(for: [startedA], timeout: 10)
        registry.protocolInstance("a")?.respond(body: "a")
        wait(for: [doneA], timeout: 10)

        let startedB = expectation(description: "B started")
        registry.expectStart("b", startedB)
        let doneB = expectation(description: "B completed")
        var resultB: Result<WebResponse, PluginError>?
        _ = clientB.request(webRequest: webRequest("b"), stream: nil) { result in
            resultB = result
            doneB.fulfill()
        }
        wait(for: [startedB], timeout: 10)

        cancellationA.cancel()
        registry.protocolInstance("b")?.respond(body: "hello from b")
        wait(for: [doneB], timeout: 10)
        XCTAssertFalse(registry.wasStopped("b"), "Cancelling finished A stopped B's transfer")
        if case .success(let response) = resultB {
            XCTAssertEqual(response.data, "hello from b")
            XCTAssertEqual(response.error, "")
        } else {
            XCTFail("B did not succeed: \(String(describing: resultB))")
        }
    }

    // A cancel that lands before the plugin starts its HTTP transfer must keep
    // the transfer from starting, and the call must still finish.
    func testCancelBeforeTransferStartsNeverStartsIt() {
        let registry = GatedURLProtocol.registry
        let client = PluginClient()
        client.cancel()
        let done = expectation(description: "call finished")
        var result: Result<WebResponse, Error>?
        DispatchQueue.global().async {
            result = Result {
                try client.call(code: Self.pluginCode,
                                functionName: "request",
                                request: self.webRequest("a"),
                                async: true,
                                stream: nil)
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        XCTAssertFalse(registry.wasStarted("a"), "A cancelled call started its transfer")
        // If the transfer did start, release it so the call's thread unblocks.
        registry.protocolInstance("a")?.respond(body: "")
        switch result {
        case .success(let response):
            // The error text comes from Foundation and may be localized.
            XCTAssertFalse(response.error?.isEmpty ?? true, "A cancelled call reported success")
        case .failure(let error):
            XCTFail("Call threw: \(error)")
        case .none:
            XCTFail("Call never finished")
        }
    }
}
