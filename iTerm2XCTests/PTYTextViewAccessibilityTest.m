#import <XCTest/XCTest.h>

#import "PTYTextView+Private.h"

@interface PTYTextViewAccessibilityTest : XCTestCase
@end

@implementation PTYTextViewAccessibilityTest

- (void)testSkipsUnchangedOldCursorLineAndEmptyLines {
    NSArray<NSString *> *actual =
        [PTYTextView accessibilityAnnouncementLinesForTrimmedLines:@[ @"pwd", @"", @"Users/deonnel" ]
                                                 firstAbsoluteLine:42
                                                   oldAbsoluteCursorY:42
                                                 oldCursorLineString:@"pwd   "];
    XCTAssertEqualObjects(actual, (@[ @"Users/deonnel" ]));
}

- (void)testAnnouncesChangedOldCursorLine {
    NSArray<NSString *> *actual =
        [PTYTextView accessibilityAnnouncementLinesForTrimmedLines:@[ @"hello", @"world" ]
                                                 firstAbsoluteLine:100
                                                   oldAbsoluteCursorY:100
                                                 oldCursorLineString:@"echo hello"];
    XCTAssertEqualObjects(actual, (@[ @"hello", @"world" ]));
}

- (void)testSkipsOnlyTheOriginalCursorLine {
    NSArray<NSString *> *actual =
        [PTYTextView accessibilityAnnouncementLinesForTrimmedLines:@[ @"prompt", @"prompt" ]
                                                 firstAbsoluteLine:7
                                                   oldAbsoluteCursorY:7
                                                 oldCursorLineString:@"prompt"];
    XCTAssertEqualObjects(actual, (@[ @"prompt" ]));
}

@end
