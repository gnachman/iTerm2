//
//  iTermSplitSelectionViewTabEdgeTests.m
//  ModernTests
//
//  Covers the whole-tab drop zones a pane offers along whichever of its edges
//  are also the tab’s outer edges. The geometry lives entirely in
//  -[SplitSelectionView updateAtPoint:], so it can be tested on a bare view
//  with no sessions, tabs, or windows.
//

#import <XCTest/XCTest.h>

#import "iTermAdvancedSettingsModel.h"
#import "SplitSelectionView.h"

@interface iTermSplitSelectionViewTabEdgeTests : XCTestCase
@end

@implementation iTermSplitSelectionViewTabEdgeTests {
    CGFloat _zone;
}

- (void)setUp {
    [super setUp];
    _zone = [iTermAdvancedSettingsModel tabEdgeDropZoneSize];
}

- (SplitSelectionView *)viewWithSize:(NSSize)size edges:(iTermTabEdgeMask)edges {
    SplitSelectionView *view =
        [[SplitSelectionView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    view.tabEdges = edges;
    return view;
}

#pragma mark - Half classification

- (void)testOnlyTabEdgesAreTabEdges {
    XCTAssertTrue(SplitSessionHalfIsTabEdge(kTabTopEdge));
    XCTAssertTrue(SplitSessionHalfIsTabEdge(kTabBottomEdge));
    XCTAssertTrue(SplitSessionHalfIsTabEdge(kTabLeftEdge));
    XCTAssertTrue(SplitSessionHalfIsTabEdge(kTabRightEdge));

    XCTAssertFalse(SplitSessionHalfIsTabEdge(kNoHalf));
    XCTAssertFalse(SplitSessionHalfIsTabEdge(kNorthHalf));
    XCTAssertFalse(SplitSessionHalfIsTabEdge(kSouthHalf));
    XCTAssertFalse(SplitSessionHalfIsTabEdge(kEastHalf));
    XCTAssertFalse(SplitSessionHalfIsTabEdge(kWestHalf));
    XCTAssertFalse(SplitSessionHalfIsTabEdge(kFullPane));
}

- (void)testTabEdgeOrientationAndOrder {
    // Left and right produce side-by-side children; top and bottom stack them.
    XCTAssertTrue(SplitSessionHalfTabEdgeIsVertical(kTabLeftEdge));
    XCTAssertTrue(SplitSessionHalfTabEdgeIsVertical(kTabRightEdge));
    XCTAssertFalse(SplitSessionHalfTabEdgeIsVertical(kTabTopEdge));
    XCTAssertFalse(SplitSessionHalfTabEdgeIsVertical(kTabBottomEdge));

    // Top and left insert ahead of the existing content.
    XCTAssertTrue(SplitSessionHalfTabEdgeIsBefore(kTabTopEdge));
    XCTAssertTrue(SplitSessionHalfTabEdgeIsBefore(kTabLeftEdge));
    XCTAssertFalse(SplitSessionHalfTabEdgeIsBefore(kTabBottomEdge));
    XCTAssertFalse(SplitSessionHalfTabEdgeIsBefore(kTabRightEdge));
}

#pragma mark - Zone selection

- (void)testEachEligibleEdgeIsSelectedNearIt {
    if (_zone <= 0) {
        return;
    }
    const NSSize size = NSMakeSize(400, 300);
    const iTermTabEdgeMask all = (iTermTabEdgeMaskTop | iTermTabEdgeMaskBottom |
                                  iTermTabEdgeMaskLeft | iTermTabEdgeMaskRight);
    const CGFloat inside = _zone / 2;

    SplitSelectionView *view = [self viewWithSize:size edges:all];
    [view updateAtPoint:NSMakePoint(size.width / 2, size.height - inside)];
    XCTAssertEqual(view.half, kTabTopEdge);

    [view updateAtPoint:NSMakePoint(size.width / 2, inside)];
    XCTAssertEqual(view.half, kTabBottomEdge);

    [view updateAtPoint:NSMakePoint(inside, size.height / 2)];
    XCTAssertEqual(view.half, kTabLeftEdge);

    [view updateAtPoint:NSMakePoint(size.width - inside, size.height / 2)];
    XCTAssertEqual(view.half, kTabRightEdge);
}

- (void)testEdgeNotOnTheTabBoundaryIsNotOffered {
    if (_zone <= 0) {
        return;
    }
    const NSSize size = NSMakeSize(400, 300);
    // This pane touches the bottom of the tab but not the top.
    SplitSelectionView *view = [self viewWithSize:size edges:iTermTabEdgeMaskBottom];

    [view updateAtPoint:NSMakePoint(size.width / 2, size.height - _zone / 2)];
    XCTAssertFalse(SplitSessionHalfIsTabEdge(view.half));
    XCTAssertEqual(view.half, kNorthHalf);

    [view updateAtPoint:NSMakePoint(size.width / 2, _zone / 2)];
    XCTAssertEqual(view.half, kTabBottomEdge);
}

- (void)testNoEdgesMeansOnlyHalvesAreOffered {
    if (_zone <= 0) {
        return;
    }
    const NSSize size = NSMakeSize(400, 300);
    SplitSelectionView *view = [self viewWithSize:size edges:iTermTabEdgeMaskNone];
    [view updateAtPoint:NSMakePoint(size.width / 2, size.height - _zone / 2)];
    XCTAssertEqual(view.half, kNorthHalf);
}

- (void)testZoneIsClampedOnAShortPane {
    if (_zone <= 0) {
        return;
    }
    // A third of 30 points is 10, well inside the default zone, so the edge zone
    // must shrink or half-pane drops would be unreachable in this pane.
    const NSSize size = NSMakeSize(400, 30);
    SplitSelectionView *view = [self viewWithSize:size edges:iTermTabEdgeMaskTop];

    [view updateAtPoint:NSMakePoint(size.width / 2, size.height - 3)];
    XCTAssertEqual(view.half, kTabTopEdge);

    [view updateAtPoint:NSMakePoint(size.width / 2, size.height - 14)];
    XCTAssertFalse(SplitSessionHalfIsTabEdge(view.half));
}

- (void)testEdgeSelectionIsStickyWithinHysteresis {
    if (_zone <= 0) {
        return;
    }
    const NSSize size = NSMakeSize(400, 300);
    SplitSelectionView *view = [self viewWithSize:size edges:iTermTabEdgeMaskTop];

    [view updateAtPoint:NSMakePoint(size.width / 2, size.height - _zone / 2)];
    XCTAssertEqual(view.half, kTabTopEdge);

    // Just outside the zone but inside the hysteresis margin: keep the edge.
    [view updateAtPoint:NSMakePoint(size.width / 2, size.height - (_zone + 3))];
    XCTAssertEqual(view.half, kTabTopEdge);

    // Well outside: give it up in favor of a half.
    [view updateAtPoint:NSMakePoint(size.width / 2, size.height - (_zone + 20))];
    XCTAssertFalse(SplitSessionHalfIsTabEdge(view.half));
}

#pragma mark - Notifications

- (void)testTabEdgeDidChangeReportsEntryAndExit {
    if (_zone <= 0) {
        return;
    }
    const NSSize size = NSMakeSize(400, 300);
    SplitSelectionView *view = [self viewWithSize:size edges:iTermTabEdgeMaskTop];
    NSMutableArray<NSNumber *> *reported = [NSMutableArray array];
    view.tabEdgeDidChange = ^(SplitSessionHalf half) {
        [reported addObject:@(half)];
    };

    [view updateAtPoint:NSMakePoint(size.width / 2, size.height - _zone / 2)];
    XCTAssertEqualObjects(reported, @[ @(kTabTopEdge) ]);

    [view updateAtPoint:NSMakePoint(size.width / 2, size.height / 2)];
    XCTAssertEqualObjects(reported, (@[ @(kTabTopEdge), @(kNoHalf) ]));

    // Half-to-half moves are not the tab’s business.
    [view updateAtPoint:NSMakePoint(_zone / 2, size.height / 2)];
    XCTAssertEqual(reported.count, 2u);
}

@end
