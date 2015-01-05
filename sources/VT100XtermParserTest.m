//
//  VT100XtermParserTest.m
//  iTerm2
//
//  Created by George Nachman on 12/30/14.
//
//

#import "VT100XtermParserTest.h"
#import "VT100XtermParser.h"
#import "VT100Token.h"

@implementation VT100XtermParserTest {
    NSMutableDictionary *_savedState;
}

- (void)setup {
    _savedState = [NSMutableDictionary dictionary];
}

- (VT100Token *)tokenForDataWithFormat:(NSString *)formatString, ... {
    va_list args;
    va_start(args, formatString);
    NSString *string = [[[NSString alloc] initWithFormat:formatString arguments:args] autorelease];
    va_end(args);
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    VT100Token *token = [[[VT100Token alloc] init] autorelease];
    int bytesUsed = 0;
    [VT100XtermParser decodeBytes:(unsigned char *)data.bytes
                           length:data.length
                        bytesUsed:&bytesUsed
                            token:token
                         encoding:NSUTF8StringEncoding
                       savedState:_savedState];
    return token;
}

- (void)testWellFormedSetWindowTitleTerminatedByBell {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;title%c", ESC, VT100CC_BEL];
    assert(token->type == XTERMCC_WINICON_TITLE);
    assert([token.string isEqualToString:@"title"]);
}

- (void)testWellFormedSetWindowTitleTerminatedByST {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;title%c\\", ESC, ESC];
    assert(token->type == XTERMCC_WINICON_TITLE);
    assert([token.string isEqualToString:@"title"]);
}

- (void)testIgnoreEmbeddedOSC {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;ti%c]tle%c", ESC, ESC, VT100CC_BEL];
    assert(token->type == XTERMCC_WINICON_TITLE);
    assert([token.string isEqualToString:@"title"]);
}

- (void)testFailOnEmbddedEscapePlusCharacter {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;ti%cc", ESC, ESC];
    assert(token->type == VT100_NOTSUPPORT);
}

- (void)testNonstandardLinuxSetPalette {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]Pa123456", ESC];
    assert(token->type == XTERMCC_SET_PALETTE);
    assert([token.string isEqualToString:@"a123456"]);
}

- (void)testUnsupportedFirstParameterNoTerminator {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]x", ESC];
    assert(token->type == VT100_WAIT);
}

- (void)testUnsupportedFirstParameter {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]x%c", ESC, VT100CC_BEL];
    assert(token->type == VT100_NOTSUPPORT);
}

- (void)testPartialNonstandardLinuxSetPalette {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]Pa12345", ESC];
    assert(token->type == VT100_WAIT);
}

- (void)testCancelAbortsOSC {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0%c", ESC, VT100CC_CAN];
    assert(token->type == VT100_NOTSUPPORT);
}

- (void)testSubstituteAbortsOSC {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0%c", ESC, VT100CC_SUB];
    assert(token->type == VT100_NOTSUPPORT);
}

- (void)testCustomFileCodeParsesUpToColon {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:abc", ESC];
    assert(token->type == XTERMCC_SET_KVP);
    assert([token.kvpKey isEqualToString:@"File"]);
    assert([token.kvpValue isEqualToString:@"blah;foo=bar"]);
}

- (void)testDeprecatedCustomFileCodeParsesUpToColon {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]50;File=blah;foo=bar:abc", ESC];
    assert(token->type == XTERMCC_SET_KVP);
    assert([token.kvpKey isEqualToString:@"File"]);
    assert([token.kvpValue isEqualToString:@"blah;foo=bar"]);
}

- (void)testUnterminatedOSCWaits {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;foo", ESC];
    assert(token->type == VT100_WAIT);
}

- (void)testUnterminateOSCWaits_2 {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0", ESC];
    assert(token->type == VT100_WAIT);
}

- (void)testMultiPartOSC {
    // Pass in a partial escape code. The already-parsed data should be saved in the saved-state
    // dictionary.
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;foo", ESC];
    assert(token->type == VT100_WAIT);
    assert(_savedState.allKeys.count == 2);

    // Give it a more-formed code. The first three characters have changed. Normally they would be
    // the same, but it's done here to ensure that they are ignored.
    token = [self tokenForDataWithFormat:@"%c]0;XXXbar", ESC];
    assert(token->type == VT100_WAIT);
    assert(_savedState.allKeys.count == 2);

    // Now a fully-formed code. The entire string value must come from saved state.
    token = [self tokenForDataWithFormat:@"%c]0;XXXXXX%c", ESC, VT100CC_BEL];
    assert(token->type == XTERMCC_WINICON_TITLE);
    assert([token.string isEqualToString:@"foobar"]);
}

@end
