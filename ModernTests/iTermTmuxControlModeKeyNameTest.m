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

#pragma mark - All keys (tmux that encodes every key)

// The names were validated against tmux's own encoder: each one, sent with
// send-keys, comes out as the expected sequence in legacy, modifyOtherKeys and
// Kitty panes.
// The pane is in VT10x (or Kitty) mode as far as we know.
static NSString *AllKeys(UTF32Char c, NSEventModifierFlags m) {
    return iTermTmuxControlModeKeyName(c, m, NO, NO, NO);
}
static NSString *AllKeysMeta(UTF32Char c, NSEventModifierFlags m) {
    return iTermTmuxControlModeKeyName(c, m, YES, NO, NO);
}
static NSString *Keypad(UTF32Char c, NSEventModifierFlags m) {
    return iTermTmuxControlModeKeyName(c, m, NO, YES, NO);
}
// The pane has asked for modifyOtherKeys 1 or 2.
static NSString *AllKeysMOK(UTF32Char c, NSEventModifierFlags m) {
    return iTermTmuxControlModeKeyName(c, m, NO, NO, YES);
}

- (void)testAllKeysNamesUnmodifiedSpecialKeys {
    // The byte path sends these verbatim, which is wrong for a Kitty pane
    // (Escape is CSI 27u under disambiguate; all four are CSI u under report-all).
    XCTAssertEqualObjects(AllKeys('\r', 0), @"Enter");
    XCTAssertEqualObjects(AllKeys('\t', 0), @"Tab");
    XCTAssertEqualObjects(AllKeys(0x1b, 0), @"Escape");
    XCTAssertEqualObjects(AllKeys(0x7f, 0), @"BSpace");
}

- (void)testAllKeysNamesModifiedSpecialKeys {
    XCTAssertEqualObjects(AllKeys('\r', NSEventModifierFlagShift), @"S-Enter");
    XCTAssertEqualObjects(AllKeys('\r', NSEventModifierFlagControl), @"C-Enter");
    XCTAssertEqualObjects(AllKeys('\r', NSEventModifierFlagControl | NSEventModifierFlagShift), @"C-S-Enter");
    XCTAssertEqualObjects(AllKeys(0x1b, NSEventModifierFlagShift), @"S-Escape");
    // Option is a modifier on these keys whatever the option key setting.
    XCTAssertEqualObjects(AllKeys('\r', NSEventModifierFlagOption), @"M-Enter");
    XCTAssertEqualObjects(AllKeys(0x7f, NSEventModifierFlagOption), @"M-BSpace");
}

- (void)testAllKeysShiftTabIsBTab {
    // S-Tab loses the shift in a legacy pane; BTab comes out as CSI Z there and in
    // modifyOtherKeys 1, as in xterm, and as Shift+Tab elsewhere.
    XCTAssertEqualObjects(AllKeys('\t', NSEventModifierFlagShift), @"BTab");
    XCTAssertEqualObjects(AllKeys('\t', NSEventModifierFlagShift | NSEventModifierFlagControl), @"C-BTab");
    XCTAssertEqualObjects(AllKeys('\t', NSEventModifierFlagControl), @"C-Tab");
}

- (void)testAllKeysNamesArrowNavigationAndFunctionKeys {
    XCTAssertEqualObjects(AllKeys(NSUpArrowFunctionKey, 0), @"Up");
    XCTAssertEqualObjects(AllKeys(NSDownArrowFunctionKey, NSEventModifierFlagShift), @"S-Down");
    XCTAssertEqualObjects(AllKeys(NSLeftArrowFunctionKey, NSEventModifierFlagControl), @"C-Left");
    XCTAssertEqualObjects(AllKeys(NSRightArrowFunctionKey, NSEventModifierFlagOption), @"M-Right");
    XCTAssertEqualObjects(AllKeys(NSHomeFunctionKey, 0), @"Home");
    XCTAssertEqualObjects(AllKeys(NSEndFunctionKey, 0), @"End");
    XCTAssertEqualObjects(AllKeys(NSPageUpFunctionKey, 0), @"PPage");
    XCTAssertEqualObjects(AllKeys(NSPageDownFunctionKey, 0), @"NPage");
    XCTAssertEqualObjects(AllKeys(NSInsertFunctionKey, 0), @"IC");
    XCTAssertEqualObjects(AllKeys(NSDeleteFunctionKey, NSEventModifierFlagControl), @"C-DC");
    XCTAssertEqualObjects(AllKeys(NSF1FunctionKey, 0), @"F1");
    XCTAssertEqualObjects(AllKeys(NSF12FunctionKey, 0), @"F12");
    XCTAssertEqualObjects(AllKeys(NSF1FunctionKey, NSEventModifierFlagShift | NSEventModifierFlagOption), @"M-S-F1");
    // The Function modifier that macOS sets on these keys is not a modifier to tmux.
    XCTAssertEqualObjects(AllKeys(NSF5FunctionKey, NSEventModifierFlagFunction), @"F5");
}

- (void)testAllKeysLeavesUnnameableFunctionKeysOnBytePath {
    XCTAssertNil(AllKeys(NSHelpFunctionKey, 0));
    XCTAssertNil(AllKeys(NSClearLineFunctionKey, 0));
    // tmux drops F13 and up in any mode but Kitty.
    XCTAssertNil(AllKeys(NSF13FunctionKey, 0));
    XCTAssertNil(AllKeys(NSF19FunctionKey, NSEventModifierFlagShift));
}

- (void)testAllKeysLeavesKeypadOnBytePath {
    // In any mode but Kitty, tmux drops modified keypad keys and sends LF for
    // keypad Enter.
    XCTAssertNil(Keypad('5', 0));
    XCTAssertNil(Keypad('5', NSEventModifierFlagControl));
    XCTAssertNil(Keypad(NSEnterCharacter, 0));
    XCTAssertNil(Keypad('=', 0));
}

- (void)testAllKeysLeavesTextOnBytePath {
    // Text goes through Cocoa (so input methods and dead keys work) and then the
    // byte path, which hands printable characters to tmux's key encoder too.
    XCTAssertNil(AllKeys('a', 0));
    XCTAssertNil(AllKeys('A', NSEventModifierFlagShift));
    XCTAssertNil(AllKeys('!', NSEventModifierFlagShift));
    XCTAssertNil(AllKeys(' ', 0));
    XCTAssertNil(AllKeys(0xe9, 0));
    // Option composing a character.
    XCTAssertNil(AllKeys('a', NSEventModifierFlagOption));
}

- (void)testAllKeysNamesPrintableKeyCombinations {
    XCTAssertEqualObjects(AllKeys('c', NSEventModifierFlagControl), @"C-c");
    XCTAssertEqualObjects(AllKeysMeta('a', NSEventModifierFlagOption), @"M-a");
    XCTAssertEqualObjects(AllKeys('A', NSEventModifierFlagControl | NSEventModifierFlagShift), @"C-S-A");
    XCTAssertEqualObjects(AllKeys(' ', NSEventModifierFlagControl), @"C-Space");
    XCTAssertEqualObjects(AllKeys(';', NSEventModifierFlagControl), @"C-;");
}

- (void)testAllKeysNamesVT10xUnencodableControlKeysOnlyInModifyOtherKeysMode {
    // tmux's VT10x encoder has no control code for these bases, and send-keys
    // types a name the pane's mode cannot encode as literal text. They encode in
    // modifyOtherKeys 1 and 2, so they are named only once the pane asks for it.
    const UTF32Char bases[] = { 0x1b, 0x7f, '#', '$', '%', '&', '*' };
    NSArray<NSString *> *names = @[ @"C-Escape", @"C-BSpace", @"C-#", @"C-$", @"C-%", @"C-&", @"C-*" ];
    for (NSUInteger i = 0; i < sizeof(bases) / sizeof(*bases); i++) {
        XCTAssertNil(AllKeys(bases[i], NSEventModifierFlagControl), @"%@", names[i]);
        XCTAssertNil(AllKeys(bases[i], NSEventModifierFlagControl | NSEventModifierFlagShift), @"%@", names[i]);
        // Meta doesn't help: tmux writes ESC and then fails the same way.
        XCTAssertNil(AllKeysMeta(bases[i], NSEventModifierFlagControl | NSEventModifierFlagOption), @"%@", names[i]);
        XCTAssertEqualObjects(AllKeysMOK(bases[i], NSEventModifierFlagControl), names[i]);
    }
    XCTAssertEqualObjects(AllKeysMOK('%', NSEventModifierFlagControl | NSEventModifierFlagShift), @"C-S-%");
    XCTAssertEqualObjects(AllKeysMOK(0x1b, NSEventModifierFlagControl | NSEventModifierFlagOption), @"C-M-Escape");

    // Without Control the same bases encode in every mode.
    XCTAssertEqualObjects(AllKeys(0x1b, NSEventModifierFlagShift), @"S-Escape");
    XCTAssertEqualObjects(AllKeys(0x7f, NSEventModifierFlagOption), @"M-BSpace");
    XCTAssertNil(AllKeys('%', NSEventModifierFlagShift), @"Shifted printable is text");
    XCTAssertEqualObjects(AllKeysMeta('%', NSEventModifierFlagOption), @"M-%");

    // Control combinations tmux can encode in VT10x mode stay named regardless.
    XCTAssertEqualObjects(AllKeys('\r', NSEventModifierFlagControl), @"C-Enter");
    XCTAssertEqualObjects(AllKeys('\t', NSEventModifierFlagControl), @"C-Tab");
    XCTAssertEqualObjects(AllKeys('[', NSEventModifierFlagControl), @"C-[");
    XCTAssertEqualObjects(AllKeys('1', NSEventModifierFlagControl), @"C-1");
    XCTAssertEqualObjects(AllKeys('!', NSEventModifierFlagControl | NSEventModifierFlagShift), @"C-S-!");
    XCTAssertEqualObjects(AllKeys(NSDeleteFunctionKey, NSEventModifierFlagControl), @"C-DC");
}

- (void)testAllKeysIgnoresCommand {
    XCTAssertEqualObjects(AllKeys(NSUpArrowFunctionKey, NSEventModifierFlagCommand), @"Up");
    XCTAssertEqualObjects(AllKeys('\r', NSEventModifierFlagCommand), @"Enter");
}

@end
