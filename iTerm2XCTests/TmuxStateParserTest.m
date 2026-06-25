//
//  TmuxStateParserTest.m
//  iTerm2
//

#import <XCTest/XCTest.h>
#import "TmuxStateParser.h"

@interface TmuxStateParserTest : XCTestCase
@end

@implementation TmuxStateParserTest

// Build a minimal tab-delimited state string for pane 1 with the given
// extra fields appended.
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

// Normal round-trip: known integer and string fields parse to expected types.
- (void)testNormalParsing {
    NSString *state = [self stateWithPaneId:1 extras:@"cursor_x=5\tcursor_y=10\twrap_flag=1"];
    NSDictionary *dict = [self parseState:state forPaneId:1];

    XCTAssertEqualObjects(dict[kStateDictCursorX], @5);
    XCTAssertEqualObjects(dict[kStateDictCursorY], @10);
    XCTAssertEqualObjects(dict[kStateDictWrapMode], @1);
}

// A KVP whose key is the empty string (i.e. the field starts with "=") must
// be silently skipped rather than inserted into the dictionary with a zero-
// length key (which could cause downstream keyed lookups to misbehave).
- (void)testEmptyKeyIsSkipped {
    // "=orphan_value" has an empty key — this should not crash and the
    // returned dict should not contain an empty-string key.
    NSString *state = [self stateWithPaneId:2 extras:@"=orphan_value\tcursor_x=3"];
    NSDictionary *dict = [self parseState:state forPaneId:2];

    XCTAssertNil(dict[@""], @"Empty key must not be inserted into result");
    XCTAssertEqualObjects(dict[kStateDictCursorX], @3,
                          @"Fields after the bad entry must still be parsed");
}

// An unknown key (one not in fieldTypes) is passed through as a raw NSString.
// This covers future tmux fields that iTerm2 doesn't yet know about.
- (void)testUnknownKeyIsPreservedAsString {
    NSString *state = [self stateWithPaneId:3 extras:@"future_tmux_key=somevalue\tcursor_x=7"];
    NSDictionary *dict = [self parseState:state forPaneId:3];

    XCTAssertEqualObjects(dict[@"future_tmux_key"], @"somevalue");
    XCTAssertEqualObjects(dict[kStateDictCursorX], @7);
}

// A field with no "=" must not crash (already handled before our change, but
// regression-test it explicitly so we know it stays working).
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
