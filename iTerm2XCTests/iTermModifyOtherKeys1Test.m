//
//  iTermModifyOtherKeys1Test.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/4/21.
//

#import <XCTest/XCTest.h>

#import "VT100Output.h"
#import "iTermModifyOtherKeysMapper1.h"

#import <Carbon/Carbon.h>

@interface iTermModifyOtherKeys1Test : XCTestCase<iTermStandardKeyMapperDelegate, iTermModifyOtherKeysMapperDelegate>

@end

#define C_ NSEventModifierFlagControl
#define O_ NSEventModifierFlagOption
#define S_ NSEventModifierFlagShift
#define F_ NSEventModifierFlagFunction

@implementation iTermModifyOtherKeys1Test {
    iTermModifyOtherKeysMapper1 *_mapper;
    VT100Output *_output;
}

- (void)setUp {
    _mapper = [[iTermModifyOtherKeysMapper1 alloc] init];
    _mapper.delegate = self;
    _output = [[VT100Output alloc] init];
    _output.termType = @"xterm";
}

- (void)verifyCharacters:(NSString *)characters
charactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers
               modifiers:(NSEventModifierFlags)modifiers
                 keycode:(int)keycode
                expected:(NSString *)expected {
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                      location:NSZeroPoint
                                 modifierFlags:modifiers
                                     timestamp:[NSDate timeIntervalSinceReferenceDate]
                                  windowNumber:0
                                       context:nil
                                    characters:characters
                   charactersIgnoringModifiers:charactersIgnoringModifiers
                                     isARepeat:NO
                                       keyCode:keycode];
    NSString *actual = [_mapper keyMapperStringForPreCocoaEvent:event];
    if (!actual) {
        NSData *data = [_mapper keyMapperDataForPostCocoaEvent:event];
        if (data) {
            actual = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
    }
    XCTAssertEqualObjects(actual, expected);
}

- (NSString *)regular:(NSString *)string {
    return string;
}

- (NSString *)csi:(NSString *)suffix {
    return [NSString stringWithFormat:@"\e[%@", suffix];
}

- (NSString *)esc:(NSString *)suffix {
    return [NSString stringWithFormat:@"\e%@", suffix];
}

- (NSString *)ctrl:(unichar)c {
    if (c == '?') {
        const unichar temp = 0x7f;
        return [NSString stringWithCharacters:&temp length:1];
    }
    assert(c >= '@');
    const unichar cc = c - '@';
    return [NSString stringWithCharacters:&cc length:1];
}

#pragma mark - iTermStandardKeyMapperDelegate

- (void)standardKeyMapperWillMapKey:(iTermStandardKeyMapper *)standardKeyMapper {
    iTermStandardKeyMapperConfiguration *configuration = [[[iTermStandardKeyMapperConfiguration alloc] init] autorelease];
    configuration.outputFactory = _output;
    configuration.encoding = NSUTF8StringEncoding;
    configuration.leftOptionKey = OPT_ESC;
    configuration.rightOptionKey = OPT_ESC;
    configuration.screenlike = NO;
    standardKeyMapper.configuration = configuration;
}

#pragma mark - iTermModifyOtherKeysMapperDelegate

- (NSStringEncoding)modifiyOtherKeysDelegateEncoding:(iTermModifyOtherKeysMapper *)sender {
    return NSUTF8StringEncoding;
}

- (void)modifyOtherKeys:(iTermModifyOtherKeysMapper *)sender
getOptionKeyBehaviorLeft:(iTermOptionKeyBehavior *)left
                  right:(iTermOptionKeyBehavior *)right {
    *left = OPT_ESC;
    *right = OPT_ESC;
}

- (VT100Output *)modifyOtherKeysOutputFactory:(iTermModifyOtherKeysMapper *)sender {
    return _output;
}

- (BOOL)modifyOtherKeysTerminalIsScreenlike:(iTermModifyOtherKeysMapper *)sender {
    return NO;
}

#pragma mark - Unmodified

- (void)testUnmodifiedLetter {
    [self verifyCharacters:@"a" charactersIgnoringModifiers:@"a" modifiers:0 keycode:kVK_ANSI_A expected:[self regular:@"a"]];
}

- (void)testUnmodifiedNumber {
    [self verifyCharacters:@"1" charactersIgnoringModifiers:@"1" modifiers:0 keycode:kVK_ANSI_1 expected:[self regular:@"1"]];
}

- (void)testUnmodifiedSymbol {
    [self verifyCharacters:@"[" charactersIgnoringModifiers:@"[" modifiers:0 keycode:kVK_ANSI_LeftBracket expected:[self regular:@"["]];
}

- (void)testUnmodifiedArrow {
    [self verifyCharacters:@"\uf700" charactersIgnoringModifiers:@"\uf700" modifiers:F_ keycode:kVK_UpArrow expected:[self csi:@"A"]];
}

- (void)testUnmodifiedFunctionKey {
    [self verifyCharacters:@"\uf704" charactersIgnoringModifiers:@"\uf704" modifiers:F_ keycode:kVK_F1 expected:[self esc:@"OP"]];
}

- (void)testUnmodifiedDelete {
    [self verifyCharacters:@"\uf728" charactersIgnoringModifiers:@"\uf728" modifiers:F_ keycode:kVK_ForwardDelete expected:[self csi:@"3~"]];
}

- (void)testUnmodifiedTab {
    [self verifyCharacters:@"\t" charactersIgnoringModifiers:@"\t" modifiers:0 keycode:kVK_Tab expected:[self regular:@"\t"]];
}

- (void)testUnmodifiedEsc {
    [self verifyCharacters:@"\e" charactersIgnoringModifiers:@"\e" modifiers:0 keycode:kVK_Escape expected:[self regular:@"\e"]];
}

- (void)testUnmodifiedBackspace {
    [self verifyCharacters:@"\x7f" charactersIgnoringModifiers:@"\x7f" modifiers:0 keycode:kVK_Delete expected:[self regular:@"\x7f"]];
}

#pragma mark - Control

- (void)testControlLetter {
    [self verifyCharacters:@"\x01" charactersIgnoringModifiers:@"a" modifiers:C_ keycode:kVK_ANSI_A expected:[self regular:@"\x01"]];
}

- (void)testControlNumber {
    [self verifyCharacters:@"1" charactersIgnoringModifiers:@"1" modifiers:C_ keycode:kVK_ANSI_1 expected:[self csi:@"27;5;49~"]];
    [self verifyCharacters:@"2" charactersIgnoringModifiers:@"2" modifiers:C_ keycode:kVK_ANSI_2 expected:[self ctrl:'@']];
    [self verifyCharacters:@"3" charactersIgnoringModifiers:@"3" modifiers:C_ keycode:kVK_ANSI_3 expected:[self ctrl:'[']];
    [self verifyCharacters:@"4" charactersIgnoringModifiers:@"4" modifiers:C_ keycode:kVK_ANSI_4 expected:[self ctrl:'\\']];
    [self verifyCharacters:@"5" charactersIgnoringModifiers:@"5" modifiers:C_ keycode:kVK_ANSI_5 expected:[self ctrl:']']];
    [self verifyCharacters:@"6" charactersIgnoringModifiers:@"6" modifiers:C_ keycode:kVK_ANSI_6 expected:[self ctrl:'^']];
    [self verifyCharacters:@"7" charactersIgnoringModifiers:@"7" modifiers:C_ keycode:kVK_ANSI_7 expected:[self ctrl:'_']];
    [self verifyCharacters:@"8" charactersIgnoringModifiers:@"8" modifiers:C_ keycode:kVK_ANSI_8 expected:[self ctrl:'?']];
    [self verifyCharacters:@"9" charactersIgnoringModifiers:@"9" modifiers:C_ keycode:kVK_ANSI_9 expected:[self csi:@"27;5;57~"]];
    [self verifyCharacters:@"0" charactersIgnoringModifiers:@"0" modifiers:C_ keycode:kVK_ANSI_0 expected:[self csi:@"27;5;48~"]];
}

- (void)testControlSymbol {
    [self verifyCharacters:@"\x001b" charactersIgnoringModifiers:@"[" modifiers:C_ keycode:33 expected:[self ctrl:'[']];
    [self verifyCharacters:@"\x001d" charactersIgnoringModifiers:@"]" modifiers:C_ keycode:30 expected:[self ctrl:']']];
}

- (void)testControlArrow {
    [self verifyCharacters:@"\uf700" charactersIgnoringModifiers:@"\uf700" modifiers:F_ | C_ keycode:126 expected:[self csi:@"1;5A"]];
}

- (void)testControlFunctionKey {
    [self verifyCharacters:@"\uf705" charactersIgnoringModifiers:@"\uf705" modifiers:F_ | C_ keycode:120 expected:[self csi:@"1;5Q"]];
}

- (void)testControlDelete {
    [self verifyCharacters:@"\uf728" charactersIgnoringModifiers:@"\uf728" modifiers:F_ | C_ keycode:kVK_ForwardDelete expected:[self csi:@"3;5~"]];
}

- (void)testControlTab {
    [self verifyCharacters:@"\x0009" charactersIgnoringModifiers:@"\x0009" modifiers:C_ keycode:48 expected:[self csi:@"27;5;9~"]];
}

- (void)testControlEsc {
    [self verifyCharacters:@"\x001b" charactersIgnoringModifiers:@"\x001b" modifiers:C_ keycode:53 expected:@"\e"];
}

- (void)testControlBackspace {
    [self verifyCharacters:@"\x007f" charactersIgnoringModifiers:@"\x007f" modifiers:C_ keycode:51 expected:[self ctrl:'H']];
}

#pragma mark - Meta

- (void)testMetaLetter {
    [self verifyCharacters:@"a" charactersIgnoringModifiers:@"a" modifiers:O_ keycode:kVK_ANSI_A expected:[self esc:@"a"]];
}

- (void)testMetaNumber {
    [self verifyCharacters:@"1" charactersIgnoringModifiers:@"1" modifiers:O_ keycode:kVK_ANSI_1 expected:[self esc:@"1"]];
}

- (void)testMetaSymbol {
    [self verifyCharacters:@"[" charactersIgnoringModifiers:@"[" modifiers:O_ keycode:kVK_ANSI_LeftBracket expected:[self esc:@"["]];
}

- (void)testMetaArrow {
    [self verifyCharacters:@"\uf700" charactersIgnoringModifiers:@"\uf700" modifiers:O_ | F_ keycode:kVK_UpArrow expected:[self csi:@"1;9A"]];  // 1;3A if option is alt, not meta
}

- (void)testMetaFunctionKey {
    [self verifyCharacters:@"\uf704" charactersIgnoringModifiers:@"\uf704" modifiers:O_ | F_ keycode:kVK_F1 expected:[self csi:@"1;9P"]];  // 1;3P if option is alt, not meta
}

- (void)testMetaDelete {
    [self verifyCharacters:@"\uf728" charactersIgnoringModifiers:@"\uf728" modifiers:O_ | F_ keycode:kVK_ForwardDelete expected:[self csi:@"3;9~"]];  // 3;9~ if option is alt, not meta
}

- (void)testMetaTab {
    [self verifyCharacters:@"\t" charactersIgnoringModifiers:@"\t" modifiers:O_ keycode:kVK_Tab expected:[self esc:@"\t"]];
}

- (void)testMetaEsc {
    [self verifyCharacters:@"\e" charactersIgnoringModifiers:@"\e" modifiers:O_ keycode:kVK_Escape expected:[self esc:@"\e"]];
}

- (void)testMetaBackspace {
    [self verifyCharacters:@"\x7f" charactersIgnoringModifiers:@"\x7f" modifiers:O_ keycode:kVK_Delete expected:[self esc:@"\x7f"]];
}

#pragma mark - Shift

- (void)testShiftLetter {
    [self verifyCharacters:@"A" charactersIgnoringModifiers:@"A" modifiers:S_ keycode:0 expected:[self regular:@"A"]];
}

- (void)testShiftNumber {
    [self verifyCharacters:@"!" charactersIgnoringModifiers:@"!" modifiers:S_ keycode:kVK_ANSI_1 expected:[self regular:@"!"]];
    [self verifyCharacters:@"@" charactersIgnoringModifiers:@"@" modifiers:S_ keycode:kVK_ANSI_2 expected:[self regular:@"@"]];
    [self verifyCharacters:@"#" charactersIgnoringModifiers:@"#" modifiers:S_ keycode:kVK_ANSI_3 expected:[self regular:@"#"]];
    [self verifyCharacters:@"$" charactersIgnoringModifiers:@"$" modifiers:S_ keycode:kVK_ANSI_4 expected:[self regular:@"$"]];
    [self verifyCharacters:@"%" charactersIgnoringModifiers:@"%" modifiers:S_ keycode:kVK_ANSI_5 expected:[self regular:@"%"]];
    [self verifyCharacters:@"^" charactersIgnoringModifiers:@"^" modifiers:S_ keycode:kVK_ANSI_6 expected:[self regular:@"^"]];
    [self verifyCharacters:@"&" charactersIgnoringModifiers:@"&" modifiers:S_ keycode:kVK_ANSI_7 expected:[self regular:@"&"]];
    [self verifyCharacters:@"*" charactersIgnoringModifiers:@"*" modifiers:S_ keycode:kVK_ANSI_8 expected:[self regular:@"*"]];
    [self verifyCharacters:@"(" charactersIgnoringModifiers:@"(" modifiers:S_ keycode:kVK_ANSI_9 expected:[self regular:@"("]];
    [self verifyCharacters:@")" charactersIgnoringModifiers:@")" modifiers:S_ keycode:kVK_ANSI_0 expected:[self regular:@")"]];
}

- (void)testShiftSymbol {
    [self verifyCharacters:@"{" charactersIgnoringModifiers:@"{" modifiers:S_ keycode:33 expected:[self regular:@"{"]];
    [self verifyCharacters:@"}" charactersIgnoringModifiers:@"}" modifiers:S_ keycode:30 expected:[self regular:@"}"]];
}

- (void)testShiftArrow {
    [self verifyCharacters:@"\uf700" charactersIgnoringModifiers:@"\uf700" modifiers:F_ | S_ keycode:126 expected:[self csi:@"1;2A"]];
}

- (void)testShiftFunctionKey {
    [self verifyCharacters:@"\uf704" charactersIgnoringModifiers:@"\uf704" modifiers:F_ | S_ keycode:122 expected:[self csi:@"1;2P"]];
}

- (void)testShiftDelete {
    [self verifyCharacters:@"\uf728" charactersIgnoringModifiers:@"\uf728" modifiers:F_ | S_ keycode:117 expected:[self csi:@"3;2~"]];
}

- (void)testShiftTab {
    [self verifyCharacters:@"\x0019" charactersIgnoringModifiers:@"\x0019" modifiers:S_ keycode:48 expected:[self csi:@"Z"]];
}

- (void)testShiftEsc {
    [self verifyCharacters:@"\x001b" charactersIgnoringModifiers:@"\x001b" modifiers:S_ keycode:53 expected:@"\e"];
}

- (void)testShiftBackspace {
    [self verifyCharacters:@"\x007f" charactersIgnoringModifiers:@"\x007f" modifiers:S_ keycode:51 expected:@"\x7f"];
}

#pragma mark - Control-Shift

- (void)testControlShiftLetter {
    [self verifyCharacters:@"\x01" charactersIgnoringModifiers:@"A" modifiers:C_ | S_ keycode:kVK_ANSI_A expected:[self regular:@"\x01"]];
}

- (void)testControlShiftNumber {
    [self verifyCharacters:@"1" charactersIgnoringModifiers:@"!" modifiers:C_ | S_ keycode:kVK_ANSI_1 expected:[self csi:@"27;6;33~"]];
    [self verifyCharacters:@"2" charactersIgnoringModifiers:@"@" modifiers:C_ | S_ keycode:kVK_ANSI_2 expected:[self ctrl:'@']];
    [self verifyCharacters:@"3" charactersIgnoringModifiers:@"#" modifiers:C_ | S_ keycode:kVK_ANSI_3 expected:[self csi:@"27;6;35~"]];
    [self verifyCharacters:@"4" charactersIgnoringModifiers:@"$" modifiers:C_ | S_ keycode:kVK_ANSI_4 expected:[self csi:@"27;6;36~"]];
    [self verifyCharacters:@"5" charactersIgnoringModifiers:@"%" modifiers:C_ | S_ keycode:kVK_ANSI_5 expected:[self csi:@"27;6;37~"]];
    [self verifyCharacters:@"6" charactersIgnoringModifiers:@"^" modifiers:C_ | S_ keycode:kVK_ANSI_6 expected:[self ctrl:'^']];
    [self verifyCharacters:@"7" charactersIgnoringModifiers:@"&" modifiers:C_ | S_ keycode:kVK_ANSI_7 expected:[self csi:@"27;6;38~"]];
    [self verifyCharacters:@"8" charactersIgnoringModifiers:@"*" modifiers:C_ | S_ keycode:kVK_ANSI_8 expected:[self csi:@"27;6;42~"]];
    [self verifyCharacters:@"9" charactersIgnoringModifiers:@"(" modifiers:C_ | S_ keycode:kVK_ANSI_9 expected:[self csi:@"27;6;40~"]];
    [self verifyCharacters:@"0" charactersIgnoringModifiers:@")" modifiers:C_ | S_ keycode:kVK_ANSI_0 expected:[self csi:@"27;6;41~"]];
}

- (void)testControlShiftSymbol {
    [self verifyCharacters:@"\x001b" charactersIgnoringModifiers:@"{" modifiers:C_ | S_ keycode:33 expected:[self ctrl:'[']];
    [self verifyCharacters:@"\x001d" charactersIgnoringModifiers:@"}" modifiers:C_ | S_ keycode:30 expected:[self ctrl:']']];
}

- (void)testControlShiftArrow {
    [self verifyCharacters:@"\uf700" charactersIgnoringModifiers:@"\uf700" modifiers:F_ | C_ | S_ keycode:126 expected:[self csi:@"1;6A"]];
}

- (void)testControlShiftFunctionKey {
    [self verifyCharacters:@"\uf704" charactersIgnoringModifiers:@"\uf704" modifiers:F_ | C_ | S_ keycode:122 expected:[self csi:@"1;6P"]];
}

- (void)testControlShiftDelete {
    [self verifyCharacters:@"\uf728" charactersIgnoringModifiers:@"\uf728" modifiers:F_ | C_ | S_ keycode:117 expected:[self csi:@"3;6~"]];
}

- (void)testControlShiftTab {
    [self verifyCharacters:@"\x0019" charactersIgnoringModifiers:@"\x0019" modifiers:C_ | S_ keycode:48 expected:[self csi:@"Z"]];
}

- (void)testControlShiftEsc {
    [self verifyCharacters:@"\x001b" charactersIgnoringModifiers:@"\x001b" modifiers:C_ | S_ keycode:53 expected:@"\e"];
}

- (void)testControlShiftBackspace {
    [self verifyCharacters:@"\x007f" charactersIgnoringModifiers:@"\x007f" modifiers:C_ | S_ keycode:51 expected:[self ctrl:'H']];
}

#pragma mark - Control-Meta

- (void)testControlMetaLetter {
    [self verifyCharacters:@"\x01" charactersIgnoringModifiers:@"a" modifiers:C_ | O_ keycode:kVK_ANSI_A expected:[self esc:[self regular:@"\x01"]]];
}

- (void)testControlMetaNumber {
    // In xterm, control+number and control+meta+number do the same thing. This is a departure because that seems like a bug to me.
    // Here 7 is used because that's how iTermMotifyOtherKeysMapper has always worked. See `csiModifiersForEventModifiers`.
    [self verifyCharacters:@"1" charactersIgnoringModifiers:@"1" modifiers:C_ | O_ keycode:kVK_ANSI_1 expected:[self csi:@"27;7;49~"]];
    [self verifyCharacters:@"2" charactersIgnoringModifiers:@"2" modifiers:C_ | O_ keycode:kVK_ANSI_2 expected:[self esc:[self ctrl:'@']]];
    [self verifyCharacters:@"3" charactersIgnoringModifiers:@"3" modifiers:C_ | O_ keycode:kVK_ANSI_3 expected:[self esc:[self ctrl:'[']]];
    [self verifyCharacters:@"4" charactersIgnoringModifiers:@"4" modifiers:C_ | O_ keycode:kVK_ANSI_4 expected:[self esc:[self ctrl:'\\']]];
    [self verifyCharacters:@"5" charactersIgnoringModifiers:@"5" modifiers:C_ | O_ keycode:kVK_ANSI_5 expected:[self esc:[self ctrl:']']]];
    [self verifyCharacters:@"6" charactersIgnoringModifiers:@"6" modifiers:C_ | O_ keycode:kVK_ANSI_6 expected:[self esc:[self ctrl:'^']]];
    [self verifyCharacters:@"7" charactersIgnoringModifiers:@"7" modifiers:C_ | O_ keycode:kVK_ANSI_7 expected:[self esc:[self ctrl:'_']]];
    [self verifyCharacters:@"8" charactersIgnoringModifiers:@"8" modifiers:C_ | O_ keycode:kVK_ANSI_8 expected:[self esc:[self ctrl:'?']]];
    [self verifyCharacters:@"9" charactersIgnoringModifiers:@"9" modifiers:C_ | O_ keycode:kVK_ANSI_9 expected:[self csi:@"27;7;57~"]];
    [self verifyCharacters:@"0" charactersIgnoringModifiers:@"0" modifiers:C_ | O_ keycode:kVK_ANSI_0 expected:[self csi:@"27;7;48~"]];
}

- (void)testControlMetaSymbol {
    [self verifyCharacters:@"\x001b" charactersIgnoringModifiers:@"[" modifiers:C_ | O_ keycode:33 expected:[self esc:[self ctrl:'[']]];
    [self verifyCharacters:@"\x001d" charactersIgnoringModifiers:@"]" modifiers:C_ | O_ keycode:30 expected:[self esc:[self ctrl:']']]];
}

- (void)testControlMetaArrow {
    [self verifyCharacters:@"\uf700" charactersIgnoringModifiers:@"\uf700" modifiers:F_ | C_ | O_ keycode:126 expected:[self csi:@"1;13A"]];
}

- (void)testControlMetaFunctionKey {
    [self verifyCharacters:@"\uf705" charactersIgnoringModifiers:@"\uf705" modifiers:F_ | C_ | O_ keycode:120 expected:[self csi:@"1;13Q"]];
}

- (void)testControlMetaDelete {
    [self verifyCharacters:@"\uf728" charactersIgnoringModifiers:@"\uf728" modifiers:F_ | C_ | O_  keycode:kVK_ForwardDelete expected:[self csi:@"3;13~"]];
}

- (void)testControlMetaTab {
    [self verifyCharacters:@"\x0009" charactersIgnoringModifiers:@"\x0009" modifiers:C_ | O_ keycode:48 expected:[self esc:@"\t"]];
}

- (void)testControlMetaEsc {
    [self verifyCharacters:@"\x001b" charactersIgnoringModifiers:@"\x001b" modifiers:C_ | O_ keycode:53 expected:[self csi:@"27;7;27~"]];
}

- (void)testControlMetaBackspace {
    [self verifyCharacters:@"\x007f" charactersIgnoringModifiers:@"\x007f" modifiers:C_ | O_ keycode:51 expected:[self csi:@"3;7~"]];
}

#pragma mark - Control-Meta-Shift

- (void)testControlMetaShiftLetter {
    [self verifyCharacters:@"\x01" charactersIgnoringModifiers:@"a" modifiers:C_ | O_ | S_ keycode:kVK_ANSI_A expected:[self esc:[self regular:@"\x01"]]];
}

- (void)testControlMetaShiftNumber {
    // In xterm, control+number and control+meta+number do the same thing. This is a departure because that seems like a bug to me.
    // Here 7 is used because that's how iTermMotifyOtherKeysMapper has always worked. See `csiModifiersForEventModifiers`.
    [self verifyCharacters:@"1" charactersIgnoringModifiers:@"!" modifiers:C_ | O_ | S_ keycode:kVK_ANSI_1 expected:[self csi:@"27;8;33~"]];
    [self verifyCharacters:@"2" charactersIgnoringModifiers:@"@" modifiers:C_ | O_ | S_ keycode:kVK_ANSI_2 expected:[self esc:[self ctrl:'@']]];
    [self verifyCharacters:@"3" charactersIgnoringModifiers:@"#" modifiers:C_ | O_ | S_ keycode:kVK_ANSI_3 expected:[self csi:@"27;8;35~"]];
    [self verifyCharacters:@"4" charactersIgnoringModifiers:@"$" modifiers:C_ | O_ | S_ keycode:kVK_ANSI_4 expected:[self csi:@"27;8;36~"]];
    [self verifyCharacters:@"5" charactersIgnoringModifiers:@"%" modifiers:C_ | O_ | S_ keycode:kVK_ANSI_5 expected:[self csi:@"27;8;37~"]];
    [self verifyCharacters:@"6" charactersIgnoringModifiers:@"^" modifiers:C_ | O_ | S_ keycode:kVK_ANSI_6 expected:[self esc:[self ctrl:'^']]];
    [self verifyCharacters:@"7" charactersIgnoringModifiers:@"&" modifiers:C_ | O_ | S_ keycode:kVK_ANSI_7 expected:[self csi:@"27;8;38~"]];
    [self verifyCharacters:@"8" charactersIgnoringModifiers:@"*" modifiers:C_ | O_ | S_ keycode:kVK_ANSI_8 expected:[self csi:@"27;8;42~"]];
    [self verifyCharacters:@"9" charactersIgnoringModifiers:@"(" modifiers:C_ | O_ | S_ keycode:kVK_ANSI_9 expected:[self csi:@"27;8;40~"]];
    [self verifyCharacters:@"0" charactersIgnoringModifiers:@")" modifiers:C_ | O_ | S_ keycode:kVK_ANSI_0 expected:[self csi:@"27;8;41~"]];
}

- (void)testControlMetaShiftSymbol {
    [self verifyCharacters:@"\x001b" charactersIgnoringModifiers:@"[" modifiers:C_ | O_ | S_ keycode:33 expected:[self esc:[self ctrl:'[']]];
    [self verifyCharacters:@"\x001d" charactersIgnoringModifiers:@"]" modifiers:C_ | O_ | S_ keycode:30 expected:[self esc:[self ctrl:']']]];
}

- (void)testControlMetaShiftArrow {
    [self verifyCharacters:@"\uf700" charactersIgnoringModifiers:@"\uf700" modifiers:F_ | C_ | O_ | S_ keycode:126 expected:[self csi:@"1;14A"]];
}

- (void)testControlMetaShiftFunctionKey {
    [self verifyCharacters:@"\uf705" charactersIgnoringModifiers:@"\uf705" modifiers:F_ | C_ | O_ | S_ keycode:120 expected:[self csi:@"1;14Q"]];
}

- (void)testControlMetaShiftDelete {
    [self verifyCharacters:@"\uf728" charactersIgnoringModifiers:@"\uf728" modifiers:F_ | C_ | O_ | S_  keycode:kVK_ForwardDelete expected:[self csi:@"3;14~"]];
}

- (void)testControlMetaShiftTab {
    [self verifyCharacters:@"\x0019" charactersIgnoringModifiers:@"\x0019" modifiers:C_ | O_ | S_ keycode:48 expected:[self csi:@"Z"]];
}

- (void)testControlMetaShiftEsc {
    [self verifyCharacters:@"\x001b" charactersIgnoringModifiers:@"\x001b" modifiers:C_ | O_ | S_ keycode:53 expected:[self csi:@"27;8;27~"]];
}

- (void)testControlMetaShiftBackspace {
    [self verifyCharacters:@"\x007f" charactersIgnoringModifiers:@"\x007f" modifiers:C_ | O_ | S_ keycode:51 expected:[self esc:[self ctrl:'H']]];
}

#pragma mark - Meta-Shift

- (void)testMetaShiftLetter {
    [self verifyCharacters:@"\u00c5" charactersIgnoringModifiers:@"A" modifiers:O_ | S_ keycode:0 expected:[self esc:@"A"]];
}

- (void)testMetaShiftNumber {
    [self verifyCharacters:@"\u2044" charactersIgnoringModifiers:@"!" modifiers:O_ | S_ keycode:18 expected:[self esc:@"!"]];
}

- (void)testMetaShiftSymbol {
    [self verifyCharacters:@"\u201d" charactersIgnoringModifiers:@"{" modifiers:O_ | S_ keycode:33 expected:[self esc:@"{"]];
}

- (void)testMetaShiftArrow {
    [self verifyCharacters:@"\uf700" charactersIgnoringModifiers:@"\uf700" modifiers:F_ | O_ | S_ keycode:126 expected:[self csi:@"1;10A"]];  // 1;4A if option is alt, not meta
}

- (void)testMetaShiftFunctionKey {
    [self verifyCharacters:@"\uf704" charactersIgnoringModifiers:@"\uf704" modifiers:F_ | O_ | S_ keycode:122 expected:[self csi:@"1;10P"]];  // 1;4P if option is alt, not meta
}

- (void)testMetaShiftDelete {
    [self verifyCharacters:@"\uf728" charactersIgnoringModifiers:@"\uf728" modifiers:F_ | O_ | S_ keycode:117 expected:[self csi:@"3;10~"]];
}

- (void)testMetaShiftTab {
    [self verifyCharacters:@"\x0019" charactersIgnoringModifiers:@"\x0019" modifiers:O_ | S_ keycode:48 expected:[self csi:@"Z"]];
}

- (void)testMetaShiftEsc {
    [self verifyCharacters:@"\x001b" charactersIgnoringModifiers:@"\x001b" modifiers:O_ | S_ keycode:53 expected:[self csi:@"27;4;27~"]];
}

- (void)testMetaShiftBackspace {
    [self verifyCharacters:@"\x007f" charactersIgnoringModifiers:@"\x007f" modifiers:O_ | S_ keycode:51 expected:[self esc:@"\x7f"]];
}

@end
