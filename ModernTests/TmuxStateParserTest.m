//
//  TmuxStateParserTest.m
//  ModernTests
//

#import <XCTest/XCTest.h>

#import "TmuxStateParser.h"

@interface TmuxStateParserTest : XCTestCase
@end

@implementation TmuxStateParserTest

// Build a minimal tab-delimited state string for the given pane with the
// supplied extra fields appended.
- (NSString *)stateWithPaneId:(int)paneId extras:(NSString *)extras {
    NSString *base = [NSString stringWithFormat:@"pane_id=%%%d", paneId];
    if (extras.length == 0) {
        return base;
    }
    return [base stringByAppendingFormat:@"\t%@", extras];
}

- (NSMutableDictionary *)parseState:(NSString *)state forPaneId:(int)paneId {
    return [[TmuxStateParser sharedInstance] parsedStateFromString:state
                                                         forPaneId:paneId
                                                  workAroundTabBug:NO];
}

// The core regression: integer fields must convert to real NSNumbers. On
// macOS 26+ the framework added its own -[NSString numberValue] that returns
// nil and shadowed our category, so every numeric field parsed as nil. This
// asserts the it_-prefixed converter actually runs and returns the value.
- (void)testIntegerFieldsConvertToNumbers {
    NSString *state = [self stateWithPaneId:1 extras:@"cursor_x=5\tcursor_y=10\twrap_flag=1"];
    NSDictionary *dict = [self parseState:state forPaneId:1];

    XCTAssertEqualObjects(dict[kStateDictCursorX], @5);
    XCTAssertEqualObjects(dict[kStateDictCursorY], @10);
    XCTAssertEqualObjects(dict[kStateDictWrapMode], @1);
    // Guard against silent regression to nil/string.
    XCTAssertTrue([dict[kStateDictCursorX] isKindOfClass:[NSNumber class]]);
}

// The pane id uses the it_paneIdNumberValue converter, which strips the
// leading "%" and returns the numeric id.
- (void)testPaneIdConverter {
    NSString *state = [self stateWithPaneId:7 extras:@"cursor_x=1"];
    NSDictionary *dict = [self parseState:state forPaneId:7];

    // kStateDictPaneId ("pane_id") is private to TmuxStateParser.m.
    XCTAssertEqualObjects(dict[@"pane_id"], @7);
}

// The tabstops field uses the it_intlistValue converter, which splits on ","
// and yields an array of NSNumbers.
- (void)testTabstopsConvertToIntList {
    NSString *state = [self stateWithPaneId:1 extras:@"pane_tabs=0,8,16,24"];
    NSDictionary *dict = [self parseState:state forPaneId:1];

    NSArray *expected = @[ @0, @8, @16, @24 ];
    XCTAssertEqualObjects(dict[kStateDictTabstops], expected);
}

// A KVP whose key is the empty string (the field starts with "=") must be
// skipped rather than inserted with a zero-length key.
- (void)testEmptyKeyIsSkipped {
    NSString *state = [self stateWithPaneId:2 extras:@"=orphan_value\tcursor_x=3"];
    NSDictionary *dict = [self parseState:state forPaneId:2];

    XCTAssertNil(dict[@""], @"Empty key must not be inserted into result");
    XCTAssertEqualObjects(dict[kStateDictCursorX], @3,
                          @"Fields after the bad entry must still be parsed");
}

// An unknown key (one not in fieldTypes) passes through as a raw NSString.
// This covers future tmux fields iTerm2 does not yet know about.
- (void)testUnknownKeyIsPreservedAsString {
    NSString *state = [self stateWithPaneId:3 extras:@"future_tmux_key=somevalue\tcursor_x=7"];
    NSDictionary *dict = [self parseState:state forPaneId:3];

    XCTAssertEqualObjects(dict[@"future_tmux_key"], @"somevalue");
    XCTAssertEqualObjects(dict[kStateDictCursorX], @7);
}

// A field with no "=" must not crash (pre-existing guard; regression-tested
// so it stays working).
- (void)testFieldWithNoEqualsIsIgnored {
    NSString *state = [self stateWithPaneId:4 extras:@"bogus_no_equals\tcursor_x=2"];
    NSDictionary *dict = [self parseState:state forPaneId:4];

    XCTAssertNil(dict[@"bogus_no_equals"]);
    XCTAssertEqualObjects(dict[kStateDictCursorX], @2);
}

// When the state string contains multiple panes, only the requested pane is
// returned.
- (void)testCorrectPaneIsSelected {
    NSString *pane1 = @"pane_id=%1\tcursor_x=10";
    NSString *pane2 = @"pane_id=%2\tcursor_x=20";
    NSString *state = [NSString stringWithFormat:@"%@\n%@", pane1, pane2];

    NSDictionary *dict1 = [self parseState:state forPaneId:1];
    NSDictionary *dict2 = [self parseState:state forPaneId:2];

    XCTAssertEqualObjects(dict1[kStateDictCursorX], @10);
    XCTAssertEqualObjects(dict2[kStateDictCursorX], @20);
}

@end
