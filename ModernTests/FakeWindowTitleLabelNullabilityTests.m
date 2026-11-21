//
//  FakeWindowTitleLabelNullabilityTests.m
//  ModernTests
//
//  -[iTermFakeWindowTitleLabel setTitle:subtitle:icon:alignmentProvider:] is
//  called by iTermRootTerminalView with a nil subtitle and a nil icon, the
//  normal case for a new window, under nonnull claims (unit N10 of
//  docs/swift-migration/nullability-triage.md). The body stores copies and
//  handles a missing subtitle and icon explicitly. The header is not visible
//  to Swift, so the claims are pinned here in Objective-C. Before they were
//  made nullable, this call was a -Wnonnull warning and a nullability
//  sanitizer report.
//

#import <XCTest/XCTest.h>

#import "iTermFakeWindowTitleLabel.h"

@interface FakeWindowTitleLabelNullabilityTests : XCTestCase
@end

@implementation FakeWindowTitleLabelNullabilityTests

- (void)testNilSubtitleAndIconShowOnlyTheTitle {
    iTermFakeWindowTitleLabel *label = [[iTermFakeWindowTitleLabel alloc] init];
    [label setTitle:@"Title"
           subtitle:nil
               icon:nil
  alignmentProvider:^NSTextAlignment(NSTextField *scratch) {
        return NSTextAlignmentLeft;
    }];
    XCTAssertEqualObjects(label.stringValue, @"Title");
    XCTAssertEqualObjects(label.windowTitle, @"Title");
    XCTAssertNil(label.subtitle);
    XCTAssertEqual(label.maximumNumberOfLines, 1);
}

@end
