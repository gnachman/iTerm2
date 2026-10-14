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

        // A protocol instance references its task and, through it, the
        // session, so drop them before checking that the session is freed.
        func forgetInstances() {
            lock.withLock { started.removeAll() }
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
    fileprivate static let pluginCode = """
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

// Remembers the objects a plugin call creates, weakly, so a test can check
// that they are all freed once the call is over.
private final class WeakObjectTracker {
    private final class Entry {
        let label: String
        weak var object: AnyObject?
        init(label: String, object: AnyObject) {
            self.label = label
            self.object = object
        }
    }
    private let lock = NSLock()
    private var entries = [Entry]()

    func record(_ label: String, _ object: AnyObject) {
        lock.withLock { entries.append(Entry(label: label, object: object)) }
    }

    var labels: Set<String> {
        lock.withLock { Set(entries.map(\.label)) }
    }

    var liveLabels: [String] {
        lock.withLock { entries.filter { $0.object != nil }.map(\.label) }
    }
}

private final class Token {
    // Callers' closures often reach their own request's Cancellation.
    var cancellation: Cancellation?
}

private final class WeakBox {
    weak var object: AnyObject?
    init(_ object: AnyObject?) { self.object = object }
}

// Each AI request used to leak its URLSession, the session's delegate, its
// JSContext, and everything the request's closures captured, because the
// session was never invalidated and the JSContext's own blocks retained it.
final class AIPluginClientLifetimeTests: XCTestCase {
    private var tracker = WeakObjectTracker()

    override func setUp() {
        super.setUp()
        GatedURLProtocol.registry = GatedURLProtocol.Registry()
        tracker = WeakObjectTracker()
        let tracker = self.tracker
        PluginClient.objectCreatedForTesting = { label, object in
            tracker.record(label, object)
        }
        PluginClient.protocolClassesForTesting = [GatedURLProtocol.self]
        iTermAIClient.pluginOverrideForTesting = Plugin(testingCode: AIPluginClientConcurrentCancelTests.pluginCode)
    }

    override func tearDown() {
        PluginClient.objectCreatedForTesting = nil
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

    // Waits until every tracked object and `extra` are freed. This waits on
    // a condition, not a duration: it only fails if they are never freed.
    //
    // The URLSession object itself is not tracked: after invalidation
    // CFNetwork holds it for several more seconds before freeing it. The
    // delegate being freed shows the session was invalidated, because a
    // session retains its delegate until then.
    private func assertEverythingFreed(extra: WeakBox,
                                       file: StaticString = #filePath,
                                       line: UInt = #line) {
        GatedURLProtocol.registry.forgetInstances()
        let tracker = self.tracker
        let freed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                tracker.liveLabels.isEmpty && extra.object == nil
            },
            object: nil)
        _ = XCTWaiter().wait(for: [freed], timeout: 10)
        XCTAssertEqual(tracker.liveLabels, [], "Objects still alive after the request finished", file: file, line: line)
        XCTAssertNil(extra.object, "The request's closures were not released", file: file, line: line)
    }

    func testCompletedStreamingRequestFreesItsObjects() {
        let registry = GatedURLProtocol.registry
        let client = iTermAIClient()
        let started = expectation(description: "started")
        registry.expectStart("a", started)
        // Over-fulfilling fails the test, so this also checks completion runs once.
        let done = expectation(description: "completed")
        var chunks = [String]()
        var completions = 0
        var result: Result<WebResponse, PluginError>?
        let weakToken: WeakBox
        // The app keeps a request's Cancellation after the request ends.
        let cancellation: Cancellation
        do {
            let token = Token()
            weakToken = WeakBox(token)
            cancellation = client.request(webRequest: webRequest("a"),
                                          stream: { chunk in
                withExtendedLifetime(token) {
                    chunks.append(chunk)
                }
            }, completion: { r in
                withExtendedLifetime(token) {
                    completions += 1
                    result = r
                    done.fulfill()
                }
            })
        }
        wait(for: [started], timeout: 10)
        registry.protocolInstance("a")?.respond(body: "hello")
        wait(for: [done], timeout: 10)

        XCTAssertEqual(chunks, ["hello"])
        if case .success(let response) = result {
            XCTAssertEqual(response.data, "hello")
            XCTAssertEqual(response.error, "")
        } else {
            XCTFail("Request did not succeed: \(String(describing: result))")
        }
        XCTAssertEqual(tracker.labels, ["client", "context", "delegate"])
        assertEverythingFreed(extra: weakToken)
        XCTAssertEqual(completions, 1)
        withExtendedLifetime(cancellation) {}
    }

    func testCancelledRequestFreesItsObjects() {
        let registry = GatedURLProtocol.registry
        let client = iTermAIClient()
        let started = expectation(description: "started")
        registry.expectStart("a", started)
        let done = expectation(description: "completed")
        var completions = 0
        let weakToken: WeakBox
        let weakCancellation: WeakBox
        do {
            let token = Token()
            weakToken = WeakBox(token)
            let cancellation = client.request(webRequest: webRequest("a"),
                                              stream: { _ in
                withExtendedLifetime(token) {}
            }, completion: { _ in
                withExtendedLifetime(token) {
                    completions += 1
                    done.fulfill()
                }
            })
            token.cancellation = cancellation
            weakCancellation = WeakBox(cancellation)
            wait(for: [started], timeout: 10)
            let stopped = expectation(description: "transfer stopped")
            registry.expectStop("a", stopped)
            cancellation.cancel()
            wait(for: [stopped, done], timeout: 10)
        }

        XCTAssertEqual(tracker.labels, ["client", "context", "delegate"])
        assertEverythingFreed(extra: weakToken)
        // The token held the only other reference, so this is freed with it.
        XCTAssertNil(weakCancellation.object, "The request's Cancellation leaked")
        XCTAssertEqual(completions, 1)
    }

    // A call cancelled before its transfer starts cancels the task without
    // resuming it. That task's session must be freed too.
    func testCallCancelledBeforeTransferStartsFreesItsObjects() {
        let done = expectation(description: "call finished")
        do {
            let client = PluginClient()
            client.cancel()
            DispatchQueue.global().async {
                _ = try? client.call(code: AIPluginClientConcurrentCancelTests.pluginCode,
                                     functionName: "request",
                                     request: self.webRequest("a"),
                                     async: true,
                                     stream: nil) as WebResponse
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 10)
        XCTAssertFalse(GatedURLProtocol.registry.wasStarted("a"))
        XCTAssertEqual(tracker.labels, ["client", "context", "delegate"])
        assertEverythingFreed(extra: WeakBox(nil))
    }
}
