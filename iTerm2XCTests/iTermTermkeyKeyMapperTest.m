//
//  iTermTermkeyKeyMapperTest.m
//  iTerm2XCTests
//
//  Created by George Nachman on 12/31/18.
//

#import <XCTest/XCTest.h>

#import "iTermTermkeyKeyMapper.h"

@interface iTermTermkeyKeyMapperTest : XCTestCase<iTermTermkeyKeyMapperDelegate>

@end

@implementation iTermTermkeyKeyMapperTest {
    iTermTermkeyKeyMapper *_mapper;
    iTermOptionKeyBehavior _optionKeyBehavior;
}

- (void)setUp {
    _mapper = [[iTermTermkeyKeyMapper alloc] init];
    _mapper.delegate = self;
    _optionKeyBehavior = OPT_NORMAL;
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

- (NSString *)escPlus:(NSString *)string {
    return [NSString stringWithFormat:@"%c%@", 27, string];
}

- (NSString *)meta:(NSString *)string {
    NSMutableData *data = [[string dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    unsigned char *ptr = data.mutableBytes;
    ptr[0] |= 0x80;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (NSString *)character:(unichar)unicode {
    return [NSString stringWithCharacters:&unicode length:1];
}

- (NSString *)csiUWithCodepoint:(unichar)codepoint
                        control:(BOOL)control
                          shift:(BOOL)shift
                         option:(BOOL)option {
    int mod = 1;
    if (shift) {
        mod += 1;
    }
    if (option) {
        mod += 2;
    }
    if (control) {
        mod += 4;
    }
    return [NSString stringWithFormat:@"%c[%d;%du", 27, (int)codepoint, mod];
}

- (NSString *)csiUWithCodepoint:(unichar)codepoint modifier:(int)mod {
    return [NSString stringWithFormat:@"%c[%d;%du", 27, (int)codepoint, mod];
}

- (NSString *)csiZ:(NSArray<NSString *> *)optargs {
    return [NSString stringWithFormat:@"%c[%@Z", 27, [optargs componentsJoinedByString:@";"]];
}

- (NSString *)csiTildeCode:(int)number modifier:(int)modifier {
    if (modifier == 1) {
        return [NSString stringWithFormat:@"%c[%d~", 27, number];
    } else {
        return [NSString stringWithFormat:@"%c[%d;%d~", 27, number, modifier];
    }
}

- (NSString *)reallySpecial:(unichar)code modifier:(int)modifier {
    if (modifier == 1) {
        // CSI 1;[non-1 modifier] {ABCDFHPQRS}
        return [NSString stringWithFormat:@"%c[%C", 27, code];
    } else {
        // CSI {ABCDFHPQRS}
        return [NSString stringWithFormat:@"%c[1;%d%C", 27, modifier, code];
    }
}
#pragma mark - Modified Unicode

- (void)testUnmodifiedUnicode {
    [self verifyCharacters:@"x" charactersIgnoringModifiers:@"x" modifiers:0x100 keycode:7 expected:@"x"];
    [self verifyCharacters:@"\u00c4" charactersIgnoringModifiers:@"\u00c4" modifiers:0x20002 keycode:39 expected:@"\u00c4"];

}

- (void)testEscPlusAscii {
    _optionKeyBehavior = OPT_ESC;
    [self verifyCharacters:@"\u00e5" charactersIgnoringModifiers:@"a" modifiers:0x80140 keycode:0 expected:[self escPlus:@"a"]];
}

- (void)testEscPlusNonAscii {
    _optionKeyBehavior = OPT_ESC;
    [self verifyCharacters:@"\u00e6" charactersIgnoringModifiers:@"\u00e4" modifiers:0x80040 keycode:39 expected:[self escPlus:@"\u00e4"]];
}

- (void)testMetaAscii {
    _optionKeyBehavior = OPT_META;
    [self verifyCharacters:@"\u222b" charactersIgnoringModifiers:@"b" modifiers:0x80140 keycode:11 expected:[self meta:@"b"]];
}

- (void)testBang {
    [self verifyCharacters:@"!" charactersIgnoringModifiers:@"!" modifiers:0x20102 keycode:18 expected:@"!"];
}

- (void)testCtrlI {
    [self verifyCharacters:[self character:9] charactersIgnoringModifiers:@"i" modifiers:0x42100 keycode:34 expected:[self csiUWithCodepoint:105 modifier:5]];
}

- (void)testCtrlM {
    [self verifyCharacters:[self character:0xd] charactersIgnoringModifiers:@"m" modifiers:0x42100 keycode:46 expected:[self csiUWithCodepoint:109 modifier:5]];
}

- (void)testCtrlOpenBracket {
    // This is an intentional deviation because the touch bar makes pressing esc hard.
    [self verifyCharacters:[self character:0x1b] charactersIgnoringModifiers:@"[" modifiers:0x42100 keycode:33 expected:[self character:27]];
}

- (void)testCtrlAtSign {
    // This is an intentional deviation from the spec because control-2 changes desktops.
    [self verifyCharacters:[self character:0] charactersIgnoringModifiers:@"@" modifiers:0x62104 keycode:19 expected:[self character:0]];
}

- (void)testControlCaret {
    [self verifyCharacters:[self character:0x1e] charactersIgnoringModifiers:@"^" modifiers:0x62104 keycode:22 expected:[self character:0x1e]];
}

- (void)testControlHyphen {
    [self verifyCharacters:[self character:0x1f] charactersIgnoringModifiers:@"-" modifiers:0x42100 keycode:27 expected:[self character:0x1f]];
}

- (void)testControlUnderscore {
    [self verifyCharacters:[self character:0x1f] charactersIgnoringModifiers:@"_" modifiers:0x62102 keycode:27 expected:[self character:0x1f]];
}

- (void)testCtrl2 {
    [self verifyCharacters:[self character:'2'] charactersIgnoringModifiers:@"2" modifiers:0x42100 keycode:19 expected:[self character:0]];
}

- (void)testControlOpenBracket {
    [self verifyCharacters:[self character:0x1b] charactersIgnoringModifiers:@"[" modifiers:0x42100 keycode:33 expected:[self character:27]];
}

- (void)testControlShiftOpenBracket {
    [self verifyCharacters:[self character:0x1b] charactersIgnoringModifiers:@"{" modifiers:0x62102 keycode:33 expected:[self csiUWithCodepoint:'{' modifier:5]];
}

- (void)testControlSlash {
    [self verifyCharacters:[self character:'/'] charactersIgnoringModifiers:@"/" modifiers:0x42100 keycode:44 expected:[self character:0x7f]];
}

- (void)testControlQuestionMark {
    [self verifyCharacters:[self character:'?'] charactersIgnoringModifiers:@"/" modifiers:0x60103 keycode:44 expected:[self csiUWithCodepoint:'/' modifier:5]];
}

- (void)testControlCloseBracket {
    [self verifyCharacters:[self character:0x1d] charactersIgnoringModifiers:@"]" modifiers:0x42100 keycode:30 expected:[self character:0x1d]];
}

- (void)testControlShiftCloseBracket {
    [self verifyCharacters:[self character:0x1d] charactersIgnoringModifiers:@"}" modifiers:0x62102 keycode:30 expected:[self csiUWithCodepoint:'}' modifier:5]];
}

- (void)testCtrlShiftI {
    [self verifyCharacters:[self character:9] charactersIgnoringModifiers:@"I" modifiers:0x62102 keycode:34 expected:[self csiUWithCodepoint:73 modifier:5]];
}

- (void)testCtrlShiftM {
    [self verifyCharacters:[self character:0xd] charactersIgnoringModifiers:@"M" modifiers:0x62102 keycode:46 expected:[self csiUWithCodepoint:77 modifier:5]];
}

- (void)testCtrlOpenBrace {
    [self verifyCharacters:[self character:0x1b] charactersIgnoringModifiers:@"{" modifiers:0x42100 keycode:33 expected:[self csiUWithCodepoint:123 modifier:5]];
}

- (void)testTab {
    [self verifyCharacters:[self character:9] charactersIgnoringModifiers:[self character:9] modifiers:0x100 keycode:48 expected:[self character:9]];
}

- (void)testEnter {
    [self verifyCharacters:[self character:0xd] charactersIgnoringModifiers:[self character:0xd] modifiers:0x100 keycode:36 expected:[self character:0xd]];
}

- (void)testEscape {
    [self verifyCharacters:[self character:0x1b] charactersIgnoringModifiers:[self character:0x1b] modifiers:0x100 keycode:53 expected:[self character:0x1b]];
}

- (void)testSpace {
    [self verifyCharacters:@" " charactersIgnoringModifiers:@" " modifiers:0x100 keycode:49 expected:[self character:' ']];
}

- (void)testCtrlA {
    [self verifyCharacters:[self character:1] charactersIgnoringModifiers:@"a" modifiers:0x42100 keycode:0 expected:[self character:1]];
}

- (void)testCtrlB {
    [self verifyCharacters:[self character:2] charactersIgnoringModifiers:@"b" modifiers:0x42100 keycode:11 expected:[self character:2]];
}

- (void)testCtrlShiftA {
    [self verifyCharacters:[self character:1] charactersIgnoringModifiers:@"A" modifiers:0x62102 keycode:0 expected:[self csiUWithCodepoint:65 modifier:5]];
}

- (void)testCtrlShiftB {
    [self verifyCharacters:[self character:2] charactersIgnoringModifiers:@"B" modifiers:0x62102 keycode:11 expected:[self csiUWithCodepoint:66 modifier:5]];
}

- (void)testCtrlAltC {
    [self verifyCharacters:[self character:0xe7] charactersIgnoringModifiers:@"c" modifiers:0xc2140 keycode:8 expected:[self csiUWithCodepoint:'c' modifier:7]];
}

- (void)testAltBackspace {
    _optionKeyBehavior = OPT_ESC;
    [self verifyCharacters:[self character:0x7f] charactersIgnoringModifiers:[self character:0x7f] modifiers:0x80140 keycode:51 expected:[self escPlus:[self character:0x7f]]];
}

#pragma mark - Modified C0 Controls

- (void)testAltShiftBackspace {
    _optionKeyBehavior = OPT_ESC;
    [self verifyCharacters:[self character:0x7f] charactersIgnoringModifiers:[self character:0x7f] modifiers:0xa0142 keycode:51 expected:[self csiUWithCodepoint:0x7f modifier:4]];
}

- (void)testShiftEnter {
    [self verifyCharacters:[self character:0xd] charactersIgnoringModifiers:[self character:0xd] modifiers:0x20102 keycode:36 expected:[self csiUWithCodepoint:13 modifier:2]];
}

- (void)testShiftEscape {
    [self verifyCharacters:[self character:0x1b] charactersIgnoringModifiers:[self character:0x1b] modifiers:0x20104 keycode:53 expected:[self csiUWithCodepoint:27 modifier:2]];
}

- (void)testShiftBackspace {
    [self verifyCharacters:[self character:0x7f] charactersIgnoringModifiers:[self character:0x7f] modifiers:0x20102 keycode:51 expected:[self csiUWithCodepoint:127 modifier:2]];
}

- (void)testCtrlEnter {
    [self verifyCharacters:[self character:0xd] charactersIgnoringModifiers:[self character:0xd] modifiers:0x42100 keycode:36 expected:[self csiUWithCodepoint:13 modifier:5]];
}

- (void)testCtrlEscape {
    [self verifyCharacters:[self character:0x1b] charactersIgnoringModifiers:[self character:0x1b] modifiers:0x42100 keycode:53 expected:[self csiUWithCodepoint:27 modifier:5]];
}

- (void)testCtrlBackspace {
    [self verifyCharacters:[self character:0x7f] charactersIgnoringModifiers:[self character:0x7f] modifiers:0x42100 keycode:51 expected:[self csiUWithCodepoint:127 modifier:5]];
}

- (void)testShiftSpace {
    [self verifyCharacters:@" " charactersIgnoringModifiers:@" " modifiers:0x20102 keycode:49 expected:[self csiUWithCodepoint:32 modifier:2]];
}

- (void)testCtrlSpace {
    [self verifyCharacters:[self character:0] charactersIgnoringModifiers:@" " modifiers:0x42100 keycode:49 expected:[self character:0]];
}

- (void)testShiftCtrlSpace {
    [self verifyCharacters:[self character:0] charactersIgnoringModifiers:@" " modifiers:0x62102 keycode:49 expected:[self csiUWithCodepoint:32 modifier:6]];
}

- (void)testShiftTab {
    [self verifyCharacters:[self character:0x19] charactersIgnoringModifiers:[self character:0x19] modifiers:0x20102 keycode:48 expected:[self csiZ:@[]]];
}

- (void)testCtrlTab {
    [self verifyCharacters:[self character:9] charactersIgnoringModifiers:[self character:9] modifiers:0x42100 keycode:48 expected:[self csiUWithCodepoint:9 modifier:5]];
}

- (void)testShiftCtrlTab {
    [self verifyCharacters:[self character:0x19] charactersIgnoringModifiers:[self character:0x19] modifiers:0x62102 keycode:48 expected:[self csiZ:@[ @"1", @"5" ]]];
}

#pragma mark - Special Keys

- (void)testInsert {
    [self verifyCharacters:@"\uf746" charactersIgnoringModifiers:@"\uf746" modifiers:0x800100 keycode:114 expected:[self csiTildeCode:2 modifier:1]];
}

- (void)testDelete {
    [self verifyCharacters:@"\uf728" charactersIgnoringModifiers:@"\uf728" modifiers:0x800000 keycode:117 expected:[self csiTildeCode:3 modifier:1]];
}

- (void)testPageUp {
    [self verifyCharacters:@"\uf72c" charactersIgnoringModifiers:@"\uf72c" modifiers:0x800100 keycode:116 expected:[self csiTildeCode:5 modifier:1]];
}

- (void)testPageDown {
    [self verifyCharacters:@"\uf72d" charactersIgnoringModifiers:@"\uf72d" modifiers:0x800100 keycode:121 expected:[self csiTildeCode:6 modifier:1]];
}

- (void)testF5 {
    [self verifyCharacters:@"\uf708" charactersIgnoringModifiers:@"\uf708" modifiers:0x800000 keycode:96 expected:[self csiTildeCode:15 modifier:1]];
}

- (void)testF12 {
    [self verifyCharacters:@"\uf70f" charactersIgnoringModifiers:@"\uf70f" modifiers:0x800000 keycode:111 expected:[self csiTildeCode:24 modifier:1]];
}

#pragma mark - Really Special Keypresses

- (void)testUp {
    [self verifyCharacters:@"\uf700" charactersIgnoringModifiers:@"\uf700" modifiers:0xa00100 keycode:126 expected:[self reallySpecial:'A' modifier:1]];
}

- (void)testDown {
    [self verifyCharacters:@"\uf701" charactersIgnoringModifiers:@"\uf701" modifiers:0xa00100 keycode:125 expected:[self reallySpecial:'B' modifier:1]];
}

- (void)testRight {
    [self verifyCharacters:@"\uf703" charactersIgnoringModifiers:@"\uf703" modifiers:0xa00100 keycode:124 expected:[self reallySpecial:'C' modifier:1]];
}

- (void)testLeft {
    [self verifyCharacters:@"\uf702" charactersIgnoringModifiers:@"\uf702" modifiers:0xa00100 keycode:123 expected:[self reallySpecial:'D' modifier:1]];
}

- (void)testEnd {
    [self verifyCharacters:@"\uf72b" charactersIgnoringModifiers:@"\uf72b" modifiers:0x800100 keycode:119 expected:[self reallySpecial:'F' modifier:1]];
}

- (void)testHome {
    [self verifyCharacters:@"\uf729" charactersIgnoringModifiers:@"\uf729" modifiers:0x800100 keycode:115 expected:[self reallySpecial:'H' modifier:1]];
}

- (void)testF1 {
    [self verifyCharacters:@"\uf704" charactersIgnoringModifiers:@"\uf704" modifiers:0x800000 keycode:122 expected:[self reallySpecial:'P' modifier:1]];
}

#pragma mark - iTermTermkeyKeyMapperDelegate

- (void)termkeyKeyMapperWillMapKey:(iTermTermkeyKeyMapper *)termkeyKeyMapper {
    iTermTermkeyKeyMapperConfiguration configuration = {
        .encoding = NSUTF8StringEncoding,
        .leftOptionKey = _optionKeyBehavior,
        .rightOptionKey = _optionKeyBehavior,
        .applicationCursorMode = NO,
        .applicationKeypadMode = NO
    };
    termkeyKeyMapper.configuration = configuration;
}

@end
