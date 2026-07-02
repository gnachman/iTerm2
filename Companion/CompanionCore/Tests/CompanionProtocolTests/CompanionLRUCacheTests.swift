import XCTest
@testable import CompanionProtocol

final class CompanionLRUCacheTests: XCTestCase {
    func testStoresAndReturns() {
        let cache = CompanionLRUCache<Int, String>(capacity: 4)
        cache[1] = "a"
        cache[2] = "b"
        XCTAssertEqual(cache[1], "a")
        XCTAssertEqual(cache[2], "b")
        XCTAssertEqual(cache.count, 2)
    }

    func testEvictsLeastRecentlyUsed() {
        let cache = CompanionLRUCache<Int, String>(capacity: 2)
        cache[1] = "a"
        cache[2] = "b"
        // Touch 1 so 2 becomes least-recently-used, then overflow.
        _ = cache[1]
        cache[3] = "c"
        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache[1], "a")
        XCTAssertNil(cache[2], "the least-recently-used entry should be evicted")
        XCTAssertEqual(cache[3], "c")
    }

    func testWritingNilRemoves() {
        let cache = CompanionLRUCache<Int, String>(capacity: 4)
        cache[1] = "a"
        cache[1] = nil
        XCTAssertNil(cache[1])
        XCTAssertEqual(cache.count, 0)
    }

    func testRemoveAllWherePrunesMatchingKeys() {
        let cache = CompanionLRUCache<Int, String>(capacity: 8)
        for i in 0..<6 { cache[i] = "v\(i)" }
        cache.removeAll(where: { $0 < 3 })
        XCTAssertNil(cache[0])
        XCTAssertNil(cache[2])
        XCTAssertEqual(cache[3], "v3")
        XCTAssertEqual(cache.count, 3)
    }

    func testRemoveAllEmpties() {
        let cache = CompanionLRUCache<Int, String>(capacity: 4)
        cache[1] = "a"; cache[2] = "b"
        cache.removeAll()
        XCTAssertEqual(cache.count, 0)
        XCTAssertNil(cache[1])
    }

    func testOverwriteDoesNotDoubleCountOrder() {
        let cache = CompanionLRUCache<Int, String>(capacity: 2)
        cache[1] = "a"
        cache[1] = "a2"
        cache[2] = "b"
        cache[3] = "c"
        // 1 was overwritten (most recent at that point) but then 2 and 3 arrived;
        // capacity 2 keeps the two most recent (2 then 3), evicting 1.
        XCTAssertNil(cache[1])
        XCTAssertEqual(cache[2], "b")
        XCTAssertEqual(cache[3], "c")
        XCTAssertEqual(cache.count, 2)
    }
}
