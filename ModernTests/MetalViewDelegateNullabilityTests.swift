//
//  MetalViewDelegateNullabilityTests.swift
//  ModernTests
//
//  -[SessionView reallyUpdateMetalViewFrame] sends
//  metalView:drawableSizeWillChange: with its metal view, which is nil once the
//  view is gone, to a parameter that iTermMetalViewDelegate declared
//  non-optional (unit H1 of docs/swift-migration/nullability-triage.md). The
//  only conformer, -[iTermMetalDriver metalView:drawableSizeWillChange:],
//  ignores the view and reads only the size. The parameter is now optional;
//  calling the requirement with nil compiles only because it is.
//

import XCTest
@testable import iTerm2SharedARC

final class MetalViewDelegateNullabilityTests: XCTestCase {
    private final class Recorder: NSObject, iTermMetalViewDelegate {
        var sizes = [CGSize]()
        var views = [iTermMetalView?]()

        func metalView(_ view: iTermMetalView?, drawableSizeWillChange size: CGSize) {
            views.append(view)
            sizes.append(size)
        }

        func draw(in view: iTermMetalView) {
        }
    }

    func testDrawableSizeChangeAcceptsNoView() {
        let recorder = Recorder()
        let delegate: iTermMetalViewDelegate = recorder
        delegate.metalView(nil, drawableSizeWillChange: .zero)
        XCTAssertEqual(recorder.sizes, [.zero])
        XCTAssertEqual(recorder.views.count, 1)
        XCTAssertNil(recorder.views[0])
    }
}
