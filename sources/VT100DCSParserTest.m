//
//  VT100DCSParserTest.m
//  iTerm2
//
//  Created by George Nachman on 2/24/15.
//
//

#import "VT100DCSParserTest.h"
#import "VT100DCSParser.h"
#import "VT100Parser.h"

// Macros don't play nice with objective c, throwing bogus syntax errors. This
// works around that issue.
static void Assert(BOOL condition) {
    assert(condition);
}

@implementation VT100DCSParserTest {
    iTermParserContext _context;
    VT100DCSParser *_parser;
    NSMutableDictionary *_savedState;
}

- (void)setup {
    _parser = [[VT100DCSParser alloc] init];
    _savedState = [[NSMutableDictionary alloc] init];
}

- (void)teardown {
    [_parser release];
    [_savedState release];
}

- (VT100Token *)tokenForDataWithFormat:(NSString *)formatString, ... {
    va_list args;
    va_start(args, formatString);
    NSString *string = [[[NSString alloc] initWithFormat:formatString arguments:args] autorelease];
    va_end(args);

    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    VT100Token *token = [[[VT100Token alloc] init] autorelease];
    _context = iTermParserContextMake((unsigned char *)data.bytes, data.length);
    [_parser decodeFromContext:&_context
                         token:token
                      encoding:NSUTF8StringEncoding
                    savedState:_savedState];
    return token;
}

- (void)testDCS {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP", VT100CC_ESC];
    assert(token->type == VT100_WAIT);
    assert(_parser.state == kVT100DCSStateEntry);
}

- (void)testDCSControl {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP%c", VT100CC_ESC, VT100CC_LF];
    assert(token->type == VT100_WAIT);
    assert(_parser.state == kVT100DCSStateEntry);
}

- (void)testDCSBackspace {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP%c", VT100CC_ESC, VT100CC_DEL];
    assert(token->type == VT100_WAIT);
    assert(_parser.state == kVT100DCSStateEntry);
}

- (void)testDCSIntermediate {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP ", VT100CC_ESC];
    assert(token->type == VT100_WAIT);
    assert(_parser.state == kVT100DCSStateIntermediate);
}

- (void)testDCSMultipleIntermediates {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP !", VT100CC_ESC];
    assert(token->type == VT100_WAIT);
    assert(_parser.state == kVT100DCSStateIntermediate);
}

- (void)testDCSIntermediateIgnore {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP 0", VT100CC_ESC];
    assert(token->type == VT100_WAIT);
    assert(_parser.state == kVT100DCSStateIgnore);
}

- (void)testDCSIntermediateIgnoreIgnore {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP 01", VT100CC_ESC];
    assert(token->type == VT100_WAIT);
    assert(_parser.state == kVT100DCSStateIgnore);
}

- (void)testDCSIntermediateIgnoreMany {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP 0%c%c%c0",
                         VT100CC_ESC, VT100CC_LF, VT100CC_EM, VT100CC_FS];
    assert(token->type == VT100_WAIT);
    assert(_parser.state == kVT100DCSStateIgnore);
}

- (void)testDCSIntermediateIgnoreIgnoreEsc {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP 01%c", VT100CC_ESC, VT100CC_ESC];
    assert(token->type == VT100_WAIT);
    assert(_parser.state == kVT100DCSStateDCSEscape);
}

- (void)testDCSIntermediateIgnoreIgnoreST {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP 01%c\\", VT100CC_ESC, VT100CC_ESC];
    assert(token->type == VT100_INVALID_SEQUENCE);
    assert(_parser.state == kVT100DCSStateGround);
}

- (void)testDCSIntermediateIgnoreIgnoreEscAsciiST {
    // Enter ignore, then dcs escape, then passthrough, then ground; should still be invalid.
    VT100Token *token = [self tokenForDataWithFormat:@"%cP 01%cabc%c\\",
                             VT100CC_ESC, VT100CC_ESC, VT100CC_ESC];
    assert(token->type == VT100_INVALID_SEQUENCE);
    assert(_parser.state == kVT100DCSStateGround);
}

- (void)testDCSIntermediatePassthrough {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP x", VT100CC_ESC];
    assert(token->type == VT100_WAIT);
    assert(_parser.state == kVT100DCSStatePassthrough);
}

- (void)testDCSIntermediatePassthroughEsc {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP x%c", VT100CC_ESC, VT100CC_ESC];
    assert(token->type == VT100_WAIT);
    assert(_parser.state == kVT100DCSStateDCSEscape);
}

- (void)testDCSIntermediatePassthroughST {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP x%c\\", VT100CC_ESC, VT100CC_ESC];
    assert(token->type == VT100_NOTSUPPORT);
    assert(_parser.state == kVT100DCSStateGround);
}

- (void)testDCSIgnore {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP:", VT100CC_ESC];
    assert(token->type == VT100_WAIT);
    assert(_parser.state == kVT100DCSStateIgnore);
}

- (void)testDCSParam {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP1", VT100CC_ESC];
    assert(token->type == VT100_WAIT);
    assert(_parser.state == kVT100DCSStateParam);
}

- (void)testDCSMultipleParameters {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP12%c3;45%c6;;0",
                            VT100CC_ESC, VT100CC_LF, VT100CC_DEL];
    assert(token->type == VT100_WAIT);
    assert(_parser.state == kVT100DCSStateParam);
    Assert([_parser.parameters isEqual:@[ @"123", @"456", @"", @"0" ]]);
}

- (void)testDCSParamIgnoreColon {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP1:", VT100CC_ESC];
    assert(token->type == VT100_WAIT);
    assert(_parser.state == kVT100DCSStateIgnore);
}

- (void)testDCSParamIgnoreLT {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP1<", VT100CC_ESC];
    assert(token->type == VT100_WAIT);
    assert(_parser.state == kVT100DCSStateIgnore);
}

- (void)testDCSPrivate {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP<1;2", VT100CC_ESC];
    assert(token->type == VT100_WAIT);
    assert(_parser.state == kVT100DCSStateParam);
    assert([_parser.privateMarkers isEqualToString:@"<"]);
    Assert([_parser.parameters isEqual:@[ @"1", @"2" ]]);
}

- (void)testDCSParamIntermediate {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP1;2 ", VT100CC_ESC];
    assert(token->type == VT100_WAIT);
    assert(_parser.state == kVT100DCSStateIntermediate);
    Assert([_parser.parameters isEqual:@[ @"1", @"2" ]]);
    assert([_parser.intermediateString isEqualToString:@" "]);
}

- (void)testDCSParamPassthrough {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP1;2Abc~", VT100CC_ESC];
    assert(token->type == VT100_WAIT);
    assert(_parser.state == kVT100DCSStatePassthrough);
    Assert([_parser.parameters isEqual:@[ @"1", @"2" ]]);
    assert([_parser.data isEqualToString:@"Abc~"]);
}

- (void)testDCSPassthrough {
    VT100Token *token = [self tokenForDataWithFormat:@"%cPAbc%c%c%c%c~",
                            VT100CC_ESC, VT100CC_LF, VT100CC_EM, VT100CC_FS, VT100CC_DEL];
    assert(token->type == VT100_WAIT);
    assert(_parser.state == kVT100DCSStatePassthrough);
    assert([_parser.parameters isEqual:@[ ]]);
    Assert([_parser.data isEqualToString:[NSString stringWithFormat:@"Abc%c%c%c~",
                                          VT100CC_LF, VT100CC_EM, VT100CC_FS]]);
}

- (void)testDCSPassthroughEsc {
    VT100Token *token = [self tokenForDataWithFormat:@"%cPAbcd%c", VT100CC_ESC, VT100CC_ESC];
    assert(token->type == VT100_WAIT);
    assert(_parser.state == kVT100DCSStateDCSEscape);
    assert([_parser.data isEqualToString:@"Abcd"]);
}

- (void)testDCSPassthroughST {
    VT100Token *token = [self tokenForDataWithFormat:@"%cPAbcd%c%\\", VT100CC_ESC, VT100CC_ESC];
    assert(token->type == VT100_NOTSUPPORT);
    assert(_parser.state == kVT100DCSStateGround);
    assert([_parser.data isEqualToString:@"Abcd"]);
}

- (void)testDCSEverything {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP<0;1;!\"abc%c\\",
                            VT100CC_ESC, VT100CC_ESC];
    assert(token->type == VT100_NOTSUPPORT);
    assert(_parser.state == kVT100DCSStateGround);
    Assert([_parser.privateMarkers isEqualToString:@"<"]);
    Assert([_parser.parameters isEqual:@[ @"0", @"1", @"" ]]);
    assert([_parser.intermediateString isEqualToString:@"!\""]);
    assert([_parser.data isEqualToString:@"abc"]);
}

- (NSString *)hexEncodedString:(NSString *)s {
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < s.length; i++) {
        [hex appendFormat:@"%02x", (int)[s characterAtIndex:i]];
    }
    return hex;
}

- (void)testDCSRequestTermcapTerminfo {
    VT100Token *token = [self tokenForDataWithFormat:@"%cP+q%@%c\\",
                            VT100CC_ESC, [self hexEncodedString:@"TN"], VT100CC_ESC];
    assert(token->type == DCS_REQUEST_TERMCAP_TERMINFO);
}

- (void)testDCSEnterTmuxIntegration {
    assert(!_parser.isHooked);
    VT100Token *token = [self tokenForDataWithFormat:@"%cP1000p%c\\", VT100CC_ESC, VT100CC_ESC];
    assert(token->type == DCS_TMUX_HOOK);
    assert(_parser.isHooked);
    assert(_context.datalen == 2);
    [_savedState removeAllObjects];

    token = [self tokenForDataWithFormat:@"%%exit\n"];
    assert(token->type == TMUX_EXIT);
    assert(_parser.isHooked);
    assert(_context.datalen == 0);
    assert(_parser.state == kVT100DCSStatePassthrough);

    token = [self tokenForDataWithFormat:@"\e\\"];
    assert(token->type == VT100_SKIP);
    assert(!_parser.isHooked);
    assert(_parser.state == kVT100DCSStateGround);
}

- (void)testDCSTmuxHook {
    assert(!_parser.isHooked);
    VT100Token *token = [self tokenForDataWithFormat:@"%cP1000", VT100CC_ESC];
    assert(token->type == VT100_WAIT);
    assert(!_parser.isHooked);
    assert(_context.datalen == 6);

    token = [self tokenForDataWithFormat:@"%cP1000p", VT100CC_ESC];
    assert(token->type == DCS_TMUX_HOOK);
    assert(_parser.isHooked);
    assert(_context.datalen == 0);
    [_savedState removeAllObjects];

    token = [self tokenForDataWithFormat:@"abc"];
    assert(token->type == VT100_WAIT);
    assert(_parser.isHooked);
    assert(_context.datalen == 0);

    token = [self tokenForDataWithFormat:@"def\r\n"];
    assert(token->type == TMUX_LINE);
    Assert([token.string isEqualToString:@"abcdef"]);
    assert(_parser.isHooked);
    assert(_context.datalen == 0);
    [_savedState removeAllObjects];

    // Technically DCS should take ESC ESC as input to produce ESC as output, but that's not how
    // tmux works so we have a hack that in tmux mode only a single ESC is treated as an ESC.
    NSString *s = [NSString stringWithFormat:@"%c[1m", VT100CC_ESC];
    token = [self tokenForDataWithFormat:@"%@\n", s];
    assert(token->type == TMUX_LINE);
    Assert([token.string isEqualToString:s]);

    // Test an empty line.
    s = @"";
    token = [self tokenForDataWithFormat:@"%@\n", s];
    assert(token->type == TMUX_LINE);
    Assert([token.string isEqualToString:s]);

    // Test an empty line with CR's
    s = @"\r\r\r";
    token = [self tokenForDataWithFormat:@"%@\n", s];
    assert(token->type == TMUX_LINE);
    Assert([token.string isEqualToString:@""]);

    // Test an empty line split in two.
    token = [self tokenForDataWithFormat:@"\r"];
    assert(token->type == VT100_WAIT);
    token = [self tokenForDataWithFormat:@"\n", s];
    assert(token->type == TMUX_LINE);
    Assert([token.string isEqualToString:@""]);

    token = [self tokenForDataWithFormat:@"%%exit\r\n"];
    assert(token->type == TMUX_EXIT);
    assert(_parser.isHooked);
    assert(_context.datalen == 0);
    [_savedState removeAllObjects];

    token = [self tokenForDataWithFormat:@"%c\\", VT100CC_ESC];
    assert(token->type == VT100_SKIP);
    assert(!_parser.isHooked);
    assert(_context.datalen == 0);
}

-  (void)testDCSTmuxWrap {
    VT100Token *token = [self tokenForDataWithFormat:@"%cPtmux;%c%c[1m%c\\",
                            VT100CC_ESC, VT100CC_ESC, VT100CC_ESC, VT100CC_ESC];
    assert(token->type == DCS_TMUX_CODE_WRAP);
    Assert([token.string isEqualToString:[NSString stringWithFormat:@"%c[1m", VT100CC_ESC]]);
}

- (void)testDCSSavedState {
    NSString *wholeSequence = [NSString stringWithFormat:@"%cP<0;1;!\"abc%c\\",
                                  VT100CC_ESC, VT100CC_ESC];

    for (int i = 2; i < wholeSequence.length; i++) {
        [self teardown];
        [self setup];
        VT100Token *token = [self tokenForDataWithFormat:@"%@", [wholeSequence substringToIndex:i]];
        assert(token->type == VT100_WAIT);

        token = [self tokenForDataWithFormat:@"%@%@",
                    [@"-" stringRepeatedTimes:i], [wholeSequence substringFromIndex:i]];
        assert(_parser.state == kVT100DCSStateGround);
        assert([_parser.privateMarkers isEqualToString:@"<"]);
        Assert([_parser.parameters isEqual:@[ @"0", @"1", @"" ]]);
        assert([_parser.intermediateString isEqualToString:@"!\""]);
        assert([_parser.data isEqualToString:@"abc"]);
    }
}

- (void)testParserWithDSCTmuxWrap {
    VT100Parser *parser = [[[VT100Parser alloc] init] autorelease];
    parser.encoding = NSUTF8StringEncoding;
    char *s = "\ePtmux;\e\e[1m\e\\";
    [parser putStreamData:s length:strlen(s)];
    CVector v;
    CVectorCreate(&v, 10);
    [parser addParsedTokensToVector:&v];
    assert(CVectorCount(&v) == 1);
    VT100Token *token = CVectorGetObject(&v, 0);
    assert(token->type == VT100CSI_SGR);
}

@end
