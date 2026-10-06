import XCTest
import ProtobufRuntime
@testable import it2core

private func summary(_ id: String) -> ITMSessionSummary {
    let s = ITMSessionSummary()
    s.uniqueIdentifier = id
    return s
}

final class FloatingPaneTests: XCTestCase {
    func testCollectSessionIdsIncludesFloatsAfterTheTree() {
        let tab = ITMListSessionsResponse_Tab()
        let link = ITMSplitTreeNode_SplitTreeLink()
        link.session = summary("tiled")
        tab.root.linksArray.add(link)
        for id in ["back", "front"] {
            let floatingPane = ITMFloatingPane()
            floatingPane.session = summary(id)
            tab.floatingPanesArray.add(floatingPane)
        }

        XCTAssertEqual(collectSessionIds(in: tab), ["tiled", "back", "front"])
        XCTAssertEqual(collectSessionIds(from: tab.root), ["tiled"], "the tree alone has no floats")
    }
}
