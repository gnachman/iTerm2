//
//  iTermTmuxControlModeKeyNameTest.m
//  ModernTests
//
//  Spec for the single source of truth that maps a keystroke to the tmux
//  send-keys key name a -CC pane should be handed (or nil to keep the byte
//  path). Expected names were validated end-to-end against tmux 3.7b: each name,
//  injected via `send-keys`, is re-encoded by tmux's input_key per the pane's
//  mode + extended-keys-format (e.g. C-j -> ESC[106;5u under csi-u, C-Escape ->
//  ESC[27;5u, C-BSpace -> ESC[127;5u).
//
//  The function's contract is to mirror the byte path (stringForEvent /
//  keyMapperStringForPreCocoaEvent in iTermModifyOtherKeysMapper.m): it names a
//  keystroke exactly when the byte path would encode it as ESC[27;m;k~, and
//  returns nil otherwise.
//

#import <XCTest/XCTest.h>

#import "iTermTmuxControlModeKeyName.h"

@interface iTermTmuxControlModeKeyNameTest : XCTestCase
@end

@implementation iTermTmuxControlModeKeyNameTest

// Convenience wrappers over the 4-arg function for the common cases.
static NSString *Name(UTF32Char c, NSEventModifierFlags m) {
    return iTermTmuxControlModeOtherKeyName(c, m, NO, NO);
}
static NSString *NameMeta(UTF32Char c, NSEventModifierFlags m) {
    return iTermTmuxControlModeOtherKeyName(c, m, YES, NO);
}

#pragma mark - Keys that are delegated (named)

- (void)testControlLetter {
    XCTAssertEqualObjects(Name('j', NSEventModifierFlagControl), @"C-j");
    XCTAssertEqualObjects(Name('m', NSEventModifierFlagControl), @"C-m");
}

- (void)testShiftEnterAndTab {
    XCTAssertEqualObjects(Name(13, NSEventModifierFlagShift), @"S-Enter");
    XCTAssertEqualObjects(Name(9, NSEventModifierFlagShift), @"S-Tab");
}

- (void)testControlShiftLetterPassesThroughGivenBase {
    // Backward compatibility: iTerm2 feeds charactersIgnoringModifiers, which for
    // ctrl-shift-j is 'J', matching what native tmux re-encodes (ESC[74;6u under
    // csi-u; identical ESC[27;6;74~ under xterm). C-S-j would change the byte.
    XCTAssertEqualObjects(Name('J', NSEventModifierFlagControl | NSEventModifierFlagShift), @"C-S-J");
    XCTAssertEqualObjects(Name('j', NSEventModifierFlagControl | NSEventModifierFlagShift), @"C-S-j");
}

- (void)testMetaLetterOnlyWhenOptionActsAsMeta {
    XCTAssertEqualObjects(NameMeta('x', NSEventModifierFlagOption), @"M-x");
    // Option composing a character (option-as-normal) is text, not delegated.
    XCTAssertNil(Name('x', NSEventModifierFlagOption));
}

- (void)testModifierOrderIsCtrlMetaShift {
    const NSEventModifierFlags all = (NSEventModifierFlagControl |
                                      NSEventModifierFlagOption |
                                      NSEventModifierFlagShift);
    XCTAssertEqualObjects(NameMeta('a', all), @"C-M-S-a");
}

- (void)testShiftSpaceRequiresSoleShiftModifier {
    // Shift+Space is delegated only when Shift is the sole modifier.
    XCTAssertEqualObjects(Name(' ', NSEventModifierFlagControl), @"C-Space");
    XCTAssertEqualObjects(Name(' ', NSEventModifierFlagShift), @"S-Space");
    // Regression: Opt+Shift+Space with option-as-normal must NOT be delegated;
    // it composes a no-break space as text (the byte path's exact-equality check
    // fails once another modifier is present).
    XCTAssertNil(Name(' ', NSEventModifierFlagOption | NSEventModifierFlagShift));
    // With option acting as meta it is a real modified key.
    XCTAssertEqualObjects(NameMeta(' ', NSEventModifierFlagOption | NSEventModifierFlagShift), @"M-S-Space");
}

- (void)testEscapeAndBackspaceAreCommandKeys {
    // Ctrl-Escape and Ctrl-Backspace reach the byte path's modifyOtherKeys
    // encoding; tmux names them Escape / BSpace (validated: C-Escape -> ESC[27;5u,
    // C-BSpace -> ESC[127;5u).
    XCTAssertEqualObjects(Name(0x1b, NSEventModifierFlagControl), @"C-Escape");
    XCTAssertEqualObjects(Name(0x7f, NSEventModifierFlagControl), @"C-BSpace");
    XCTAssertEqualObjects(Name(0x7f, NSEventModifierFlagShift), @"S-BSpace");
    // Unmodified Escape/Backspace keep the raw byte path.
    XCTAssertNil(Name(0x1b, 0));
    XCTAssertNil(Name(0x7f, 0));
}

- (void)testControlPunctuation {
    XCTAssertEqualObjects(Name(']', NSEventModifierFlagControl), @"C-]");
    XCTAssertEqualObjects(Name('[', NSEventModifierFlagControl), @"C-[");
    XCTAssertEqualObjects(Name('/', NSEventModifierFlagControl), @"C-/");
    XCTAssertEqualObjects(Name('.', NSEventModifierFlagControl), @"C-.");
    XCTAssertEqualObjects(Name('-', NSEventModifierFlagControl), @"C--");
    XCTAssertEqualObjects(Name('\\', NSEventModifierFlagControl), @"C-\\");
    // Names are unquoted here; quoting for the tmux command parser (semicolon,
    // apostrophe, backslash) is the gateway's job.
    XCTAssertEqualObjects(Name(';', NSEventModifierFlagControl), @"C-;");
    XCTAssertEqualObjects(Name('\'', NSEventModifierFlagControl), @"C-'");
}

- (void)testCommandModifierIsIgnored {
    XCTAssertEqualObjects(Name('j', NSEventModifierFlagCommand | NSEventModifierFlagControl), @"C-j");
    XCTAssertNil(Name('j', NSEventModifierFlagCommand));
}

#pragma mark - Keys that are NOT delegated (nil, keep the byte path)

- (void)testUnmodifiedReturnsNil {
    XCTAssertNil(Name('a', 0));
    XCTAssertNil(Name(13, 0));
    XCTAssertNil(Name(9, 0));
}

- (void)testPlainShiftedPrintablesReturnNil {
    XCTAssertNil(Name('!', NSEventModifierFlagShift));
    XCTAssertNil(Name(':', NSEventModifierFlagShift));
    XCTAssertNil(Name('+', NSEventModifierFlagShift));
    XCTAssertNil(Name('A', NSEventModifierFlagShift));
}

- (void)testFunctionAndNavKeysReturnNilEvenWhenModified {
    const NSEventModifierFlags ctrl = NSEventModifierFlagControl;
    XCTAssertNil(Name(NSUpArrowFunctionKey, ctrl));
    XCTAssertNil(Name(NSDownArrowFunctionKey, ctrl));
    XCTAssertNil(Name(NSLeftArrowFunctionKey, ctrl));
    XCTAssertNil(Name(NSRightArrowFunctionKey, ctrl));
    XCTAssertNil(Name(NSHomeFunctionKey, ctrl));
    XCTAssertNil(Name(NSEndFunctionKey, ctrl));
    XCTAssertNil(Name(NSPageUpFunctionKey, NSEventModifierFlagShift));
    XCTAssertNil(Name(NSPageDownFunctionKey, ctrl));
    XCTAssertNil(Name(NSInsertFunctionKey, ctrl));
    XCTAssertNil(Name(NSDeleteFunctionKey, ctrl));
    XCTAssertNil(Name(NSF1FunctionKey, ctrl));
    XCTAssertNil(Name(NSF5FunctionKey, ctrl));
    XCTAssertNil(Name(NSF12FunctionKey, ctrl));
}

- (void)testNumericKeypadReturnsNil {
    // Application-keypad keys keep their format-independent SS3/CSI encoding.
    XCTAssertNil(iTermTmuxControlModeOtherKeyName('5', NSEventModifierFlagControl, NO, YES));
    XCTAssertNil(iTermTmuxControlModeOtherKeyName('7', NSEventModifierFlagOption, YES, YES));
    XCTAssertNil(iTermTmuxControlModeOtherKeyName('+', NSEventModifierFlagShift, NO, YES));
    // The same key off the keypad still delegates.
    XCTAssertEqualObjects(iTermTmuxControlModeOtherKeyName('5', NSEventModifierFlagControl, NO, NO), @"C-5");
}

@end
