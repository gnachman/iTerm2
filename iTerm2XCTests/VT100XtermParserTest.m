//
//  VT100XtermParserTest.m
//  iTerm2
//
//  Created by George Nachman on 12/30/14.
//
//

#import <XCTest/XCTest.h>
#import "CVector.h"
#import "iTermParser.h"
#import "VT100XtermParser.h"
#import "VT100Token.h"

@interface VT100XtermParserTest : XCTestCase
@end

@implementation VT100XtermParserTest {
    NSMutableDictionary *_savedState;
    iTermParserContext _context;
    CVector _incidentals;
}

- (void)setUp {
    _savedState = [NSMutableDictionary dictionary];
    CVectorCreate(&_incidentals, 1);
}

- (void)tearDown {
    CVectorDestroy(&_incidentals);
}

- (VT100Token *)tokenForDataWithFormat:(NSString *)formatString, ... {
    va_list args;
    va_start(args, formatString);
    NSString *string = [[[NSString alloc] initWithFormat:formatString arguments:args] autorelease];
    va_end(args);

    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    VT100Token *token = [[[VT100Token alloc] init] autorelease];
    _context = iTermParserContextMake((unsigned char *)data.bytes, data.length);
    [VT100XtermParser decodeFromContext:&_context
                            incidentals:&_incidentals
                                  token:token
                               encoding:NSUTF8StringEncoding
                             savedState:_savedState];
    return token;
}

- (void)testNoModeYet {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);

    // In case saved state gets used, verify it can continue from there.
    token = [self tokenForDataWithFormat:@"%c]0;title%c", VT100CC_ESC, VT100CC_BEL];
    XCTAssert(token->type == XTERMCC_WINICON_TITLE);
    XCTAssert([token.string isEqualToString:@"title"]);
}

- (void)testWellFormedSetWindowTitleTerminatedByBell {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;title%c", VT100CC_ESC, VT100CC_BEL];
    XCTAssert(token->type == XTERMCC_WINICON_TITLE);
    XCTAssert([token.string isEqualToString:@"title"]);
}

- (void)testWellFormedSetWindowTitleTerminatedByST {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;title%c\\", VT100CC_ESC, VT100CC_ESC];
    XCTAssert(token->type == XTERMCC_WINICON_TITLE);
    XCTAssert([token.string isEqualToString:@"title"]);
}

- (void)testIgnoreEmbeddedOSC {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;ti%c]tle%c", VT100CC_ESC, VT100CC_ESC, VT100CC_BEL];
    XCTAssert(token->type == XTERMCC_WINICON_TITLE);
    XCTAssert([token.string isEqualToString:@"title"]);
}

- (void)testIgnoreEmbeddedOSCTwoPart_OutOfDataAfterBracket {
    // Running out of data just after an embedded ESC ] hits a special path.
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;ti%c]", VT100CC_ESC, VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);

    token = [self tokenForDataWithFormat:@"%c]0;ti%c]tle%c", VT100CC_ESC, VT100CC_ESC, VT100CC_BEL];
    XCTAssert(token->type == XTERMCC_WINICON_TITLE);
    XCTAssert([token.string isEqualToString:@"title"]);
}

- (void)testIgnoreEmbeddedOSCTwoPart_OutOfDataAfterEsc {
    // Running out of data just after an embedded ESC hits a special path.
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;ti%c", VT100CC_ESC, VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);

    token = [self tokenForDataWithFormat:@"%c]0;ti%c]tle%c", VT100CC_ESC, VT100CC_ESC, VT100CC_BEL];
    XCTAssert(token->type == XTERMCC_WINICON_TITLE);
    XCTAssert([token.string isEqualToString:@"title"]);
}

- (void)testFailOnEmbddedEscapePlusCharacter {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;ti%cc", VT100CC_ESC, VT100CC_ESC];
    XCTAssert(token->type == VT100_NOTSUPPORT);
}

- (void)testNonstandardLinuxSetPalette {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]Pa123456", VT100CC_ESC];
    XCTAssert(token->type == XTERMCC_SET_PALETTE);
    XCTAssert([token.string isEqualToString:@"a123456"]);
}

- (void)testUnsupportedFirstParameterNoTerminator {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]x", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
}

- (void)testUnsupportedFirstParameter {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]x%c", VT100CC_ESC, VT100CC_BEL];
    XCTAssert(token->type == VT100_NOTSUPPORT);
}

- (void)testPartialNonstandardLinuxSetPalette {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]Pa12345", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
}

- (void)testCancelAbortsOSC {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0%c", VT100CC_ESC, VT100CC_CAN];
    XCTAssert(token->type == VT100_NOTSUPPORT);
}

- (void)testSubstituteAbortsOSC {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0%c", VT100CC_ESC, VT100CC_SUB];
    XCTAssert(token->type == VT100_NOTSUPPORT);
}

- (void)testUnfinishedMultitoken {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:abc", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
    XCTAssert(CVectorCount(&_incidentals) == 2);

    VT100Token *header = CVectorGetObject(&_incidentals, 0);
    XCTAssert(header->type = XTERMCC_MULTITOKEN_HEADER_SET_KVP);
    XCTAssert([header.kvpKey isEqualToString:@"File"]);
    XCTAssert([header.kvpValue isEqualToString:@"blah;foo=bar"]);

    VT100Token *body = CVectorGetObject(&_incidentals, 1);
    XCTAssert(body->type = XTERMCC_MULTITOKEN_BODY);
    XCTAssert([body.string isEqualToString:@"abc"]);
}

- (void)testCompleteMultitoken {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:abc%c",
                         VT100CC_ESC, VT100CC_BEL];
    XCTAssert(token->type == XTERMCC_MULTITOKEN_END);
    XCTAssert(CVectorCount(&_incidentals) == 2);

    VT100Token *header = CVectorGetObject(&_incidentals, 0);
    XCTAssert(header->type = XTERMCC_MULTITOKEN_HEADER_SET_KVP);
    XCTAssert([header.kvpKey isEqualToString:@"File"]);
    XCTAssert([header.kvpValue isEqualToString:@"blah;foo=bar"]);

    VT100Token *body = CVectorGetObject(&_incidentals, 1);
    XCTAssert(body->type = XTERMCC_MULTITOKEN_BODY);
    XCTAssert([body.string isEqualToString:@"abc"]);
}

- (void)testCompleteMultitokenInMultiplePasses {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]1337;File=blah;", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
    XCTAssert(CVectorCount(&_incidentals) == 0);

    // Give it some more header
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
    XCTAssert(CVectorCount(&_incidentals) == 0);

    // Give it the final colon so the header can be parsed
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
    XCTAssert(CVectorCount(&_incidentals) == 1);

    VT100Token *header = CVectorGetObject(&_incidentals, 0);
    XCTAssert(header->type = XTERMCC_MULTITOKEN_HEADER_SET_KVP);
    XCTAssert([header.kvpKey isEqualToString:@"File"]);
    XCTAssert([header.kvpValue isEqualToString:@"blah;foo=bar"]);

    // Give it some body.
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:a", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
    XCTAssert(CVectorCount(&_incidentals) == 2);

    VT100Token *body = CVectorGetObject(&_incidentals, 1);
    XCTAssert(body->type = XTERMCC_MULTITOKEN_BODY);
    XCTAssert([body.string isEqualToString:@"a"]);

    // More body
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:abc", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
    XCTAssert(CVectorCount(&_incidentals) == 3);

    body = CVectorGetObject(&_incidentals, 2);
    XCTAssert(body->type = XTERMCC_MULTITOKEN_BODY);
    XCTAssert([body.string isEqualToString:@"bc"]);

    // Start finishing up
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:abc%c", VT100CC_ESC, VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
    XCTAssert(CVectorCount(&_incidentals) == 3);

    // And, done.
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:abc%c\\", VT100CC_ESC, VT100CC_ESC];
    XCTAssert(token->type == XTERMCC_MULTITOKEN_END);
    XCTAssert(CVectorCount(&_incidentals) == 3);
}

- (void)testLateFailureMultitokenInMultiplePasses {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]1337;File=blah;", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
    XCTAssert(CVectorCount(&_incidentals) == 0);

    // Give it some more header
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
    XCTAssert(CVectorCount(&_incidentals) == 0);

    // Give it the final colon so the header can be parsed
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
    XCTAssert(CVectorCount(&_incidentals) == 1);

    VT100Token *header = CVectorGetObject(&_incidentals, 0);
    XCTAssert(header->type = XTERMCC_MULTITOKEN_HEADER_SET_KVP);
    XCTAssert([header.kvpKey isEqualToString:@"File"]);
    XCTAssert([header.kvpValue isEqualToString:@"blah;foo=bar"]);

    // Give it some body.
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:a", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
    XCTAssert(CVectorCount(&_incidentals) == 2);

    VT100Token *body = CVectorGetObject(&_incidentals, 1);
    XCTAssert(body->type = XTERMCC_MULTITOKEN_BODY);
    XCTAssert([body.string isEqualToString:@"a"]);

    // More body
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:abc", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
    XCTAssert(CVectorCount(&_incidentals) == 3);

    body = CVectorGetObject(&_incidentals, 2);
    XCTAssert(body->type = XTERMCC_MULTITOKEN_BODY);
    XCTAssert([body.string isEqualToString:@"bc"]);

    // Now a bogus character.
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:abc%c", VT100CC_ESC, VT100CC_SUB];
    XCTAssert(token->type == VT100_NOTSUPPORT);
}

- (void)testUnfinishedMultitokenWithDeprecatedMode {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]50;File=blah;foo=bar:abc", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
    XCTAssert(CVectorCount(&_incidentals) == 2);

    VT100Token *header = CVectorGetObject(&_incidentals, 0);
    XCTAssert(header->type = XTERMCC_MULTITOKEN_HEADER_SET_KVP);
    XCTAssert([header.kvpKey isEqualToString:@"File"]);
    XCTAssert([header.kvpValue isEqualToString:@"blah;foo=bar"]);

    VT100Token *body = CVectorGetObject(&_incidentals, 1);
    XCTAssert(body->type = XTERMCC_MULTITOKEN_BODY);
    XCTAssert([body.string isEqualToString:@"abc"]);
}

- (void)testUnterminatedOSCWaits {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;foo", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
}

- (void)testUnterminateOSCWaits_2 {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
}

- (void)testMultiPartOSC {
    // Pass in a partial escape code. The already-parsed data should be saved in the saved-state
    // dictionary.
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;foo", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
    XCTAssert(_savedState.allKeys.count > 0);

    // Give it a more-formed code. The first three characters have changed. Normally they would be
    // the same, but it's done here to ensure that they are ignored.
    token = [self tokenForDataWithFormat:@"%c]0;XXXbar", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
    XCTAssert(_savedState.allKeys.count > 0);

    // Now a fully-formed code. The entire string value must come from saved state.
    token = [self tokenForDataWithFormat:@"%c]0;XXXXXX%c", VT100CC_ESC, VT100CC_BEL];
    XCTAssert(token->type == XTERMCC_WINICON_TITLE);
    XCTAssert([token.string isEqualToString:@"foobar"]);
}

- (void)testEmbeddedColon {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]1;foo:bar%c", VT100CC_ESC, VT100CC_BEL];
    XCTAssert(token->type == XTERMCC_ICON_TITLE);
    XCTAssert([token.string isEqualToString:@"foo:bar"]);
}

- (void)testUnsupportedMode {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]999;foo%c", VT100CC_ESC, VT100CC_BEL];
    XCTAssert(token->type == VT100_NOTSUPPORT);
}

- (void)testBelAfterEmbeddedOSC {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]1;%c]%c", VT100CC_ESC, VT100CC_ESC, VT100CC_BEL];
    XCTAssert(token->type == XTERMCC_ICON_TITLE);
    XCTAssert([token.string isEqualToString:@""]);
}

- (void)testIgnoreEmbeddedOSCWhenFailing {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]x%c]%c", VT100CC_ESC, VT100CC_ESC, VT100CC_BEL];
    XCTAssert(token->type == VT100_NOTSUPPORT);
    XCTAssert(iTermParserNumberOfBytesConsumed(&_context) == 6);
}

#pragma mark - Regression tests

// Bug 3371
- (void)testDefaultModeForDtermCodes {
    VT100Token *token = [self tokenForDataWithFormat:@"%c];Foo%c", VT100CC_ESC, VT100CC_BEL];
    XCTAssert(token->type == XTERMCC_WINICON_TITLE);
    XCTAssert([token.string isEqualToString:@"Foo"]);
}

@end
