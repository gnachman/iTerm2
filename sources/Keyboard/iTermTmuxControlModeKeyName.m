//
//  iTermTmuxControlModeKeyName.m
//  iTerm2SharedARC
//

#import "iTermTmuxControlModeKeyName.h"

#import "NSStringITerm.h"

// The tmux send-keys name for the base key, or nil if the key is not nameable
// (and so must keep the byte path). Enter/Tab/Space/Escape/Backspace use their
// tmux names; function/navigation keys and non-named control codes return nil.
static NSString *iTermTmuxOtherKeyBaseName(UTF32Char c) {
    switch (c) {
        case '\r':    // 13
            return @"Enter";
        case '\t':    // 9
            return @"Tab";
        case ' ':     // 32
            return @"Space";
        case 0x1b:    // Escape
            return @"Escape";
        case 0x7f:    // Backspace/Delete
            return @"BSpace";
        default:
            break;
    }
    // Apple's function-key unicode range holds the arrows, Home, End, PageUp,
    // PageDown, Insert, Delete and F-keys. Those have standard, format-
    // independent CSI encodings and are not modifyOtherKeys "other keys", so
    // they keep the byte path.
    if (c >= 0xF700 && c <= 0xF8FF) {
        return nil;
    }
    // Only printable base keys are nameable; C0 control codes (other than the
    // named keys above) keep the byte path.
    if (c < 0x20) {
        return nil;
    }
    return [NSString stringWithLongCharacter:c];
}

NSString *iTermTmuxControlModeOtherKeyName(UTF32Char codePoint,
                                           NSEventModifierFlags modifiers,
                                           BOOL optionActsAsMeta,
                                           BOOL isNumericKeypad) {
    // Application-keypad keys have their own format-independent SS3/CSI keypad
    // encoding (keypadDataForString); keep them on the byte path.
    if (isNumericKeypad) {
        return nil;
    }
    // Command is not a modifyOtherKeys modifier: ignore it for the decision and
    // the emitted name.
    const NSEventModifierFlags encodable = (NSEventModifierFlagControl |
                                            NSEventModifierFlagOption |
                                            NSEventModifierFlagShift);
    if ((modifiers & encodable) == 0) {
        // Unmodified keys go out as raw bytes; there is nothing to delegate.
        return nil;
    }
    // A non-nameable base (function/navigation key or bare control code) keeps
    // the byte path regardless of modifiers.
    NSString *base = iTermTmuxOtherKeyBaseName(codePoint);
    if (base == nil) {
        return nil;
    }
    // Delegate only keystrokes the byte path actually encodes as modifyOtherKeys
    // and sends to the pty (rather than inserting as text):
    //   - Control + anything (keyMapperStringForPreCocoaEvent),
    //   - option acting as meta,
    //   - the command keys Return/Tab/Escape/Backspace, which Cocoa never inserts
    //     as text, or
    //   - Shift+Space, but only when Shift is the sole modifier (the byte path's
    //     Shift+Space special case tests exact equality against the full mask,
    //     which counts Command; so e.g. Opt+Shift+Space composes text instead).
    const BOOL control = (modifiers & NSEventModifierFlagControl) != 0;
    const BOOL optionMeta = (modifiers & NSEventModifierFlagOption) && optionActsAsMeta;
    const BOOL commandKey = (codePoint == '\r' || codePoint == '\t' ||
                             codePoint == 0x1b || codePoint == 0x7f);
    const NSEventModifierFlags allMask = (encodable | NSEventModifierFlagCommand);
    const BOOL shiftSpace = (codePoint == ' ' &&
                             (modifiers & allMask) == NSEventModifierFlagShift);
    if (!control && !optionMeta && !commandKey && !shiftSpace) {
        return nil;
    }

    NSMutableString *name = [NSMutableString string];
    if (control) {
        [name appendString:@"C-"];
    }
    if (modifiers & NSEventModifierFlagOption) {
        [name appendString:@"M-"];
    }
    if (modifiers & NSEventModifierFlagShift) {
        [name appendString:@"S-"];
    }
    [name appendString:base];
    return name;
}

#pragma mark - All keys

// The tmux name for an arrow, navigation or function key, or nil to keep the
// byte path. That includes keys tmux has no name for (e.g., Help or Clear) and
// F13 and up, which tmux can only encode for a pane using the Kitty protocol. It
// drops them in any other mode, where the byte path sends xterm's encoding.
static NSString *iTermTmuxFunctionKeyName(UTF32Char c) {
    switch (c) {
        case NSUpArrowFunctionKey:
            return @"Up";
        case NSDownArrowFunctionKey:
            return @"Down";
        case NSLeftArrowFunctionKey:
            return @"Left";
        case NSRightArrowFunctionKey:
            return @"Right";
        case NSHomeFunctionKey:
            return @"Home";
        case NSEndFunctionKey:
            return @"End";
        case NSPageUpFunctionKey:
            return @"PPage";
        case NSPageDownFunctionKey:
            return @"NPage";
        case NSInsertFunctionKey:
            return @"IC";
        case NSDeleteFunctionKey:
            // Forward delete. Backspace is 0x7f.
            return @"DC";
        default:
            break;
    }
    if (c >= NSF1FunctionKey && c <= NSF12FunctionKey) {
        return [NSString stringWithFormat:@"F%d", (int)(c - NSF1FunctionKey + 1)];
    }
    return nil;
}

// Prefixes a non-text key's base name with its modifiers. Option is always M-
// here: it cannot compose a character on these keys.
static NSString *iTermTmuxNonTextKeyName(NSString *base, NSEventModifierFlags modifiers, BOOL shift) {
    NSMutableString *name = [NSMutableString string];
    if (modifiers & NSEventModifierFlagControl) {
        [name appendString:@"C-"];
    }
    if (modifiers & NSEventModifierFlagOption) {
        [name appendString:@"M-"];
    }
    if (shift) {
        [name appendString:@"S-"];
    }
    [name appendString:base];
    return name;
}

// YES for the Control combinations tmux can encode only as modifyOtherKeys. In a
// VT10x pane its encoder (input_key_vt10x) has no control code for these bases
// and fails, and send-keys then types the name as text (see the header). It also
// fails on C-BSpace in a Kitty pane that has not asked for report-all, because
// tmux hands modified Backspace back to the VT10x path there. Meta on top changes
// nothing: the VT10x path writes ESC and then fails the same way.
static BOOL iTermTmuxKeyNeedsModifyOtherKeys(UTF32Char c, NSEventModifierFlags modifiers) {
    if (!(modifiers & NSEventModifierFlagControl)) {
        return NO;
    }
    switch (c) {
        case 0x1b:  // Escape
        case 0x7f:  // Backspace
        case '#':
        case '$':
        case '%':
        case '&':
        case '*':
            return YES;
        default:
            return NO;
    }
}

NSString *iTermTmuxControlModeKeyName(UTF32Char codePoint,
                                      NSEventModifierFlags modifiers,
                                      BOOL optionActsAsMeta,
                                      BOOL isNumericKeypad,
                                      BOOL modifyOtherKeys) {
    const BOOL shift = (modifiers & NSEventModifierFlagShift) != 0;
    if (isNumericKeypad) {
        // Keypad keys keep the byte path. In any mode but Kitty, tmux drops a
        // modified keypad key and encodes Enter as LF rather than CR, and the byte
        // path already follows the application keypad mode.
        return nil;
    }
    if (!modifyOtherKeys && iTermTmuxKeyNeedsModifyOtherKeys(codePoint, modifiers)) {
        // The pane has not asked for a mode that can encode this, so tmux would
        // type its name. The byte path sends what it sends today.
        return nil;
    }
    if (codePoint >= 0xF700 && codePoint <= 0xF8FF) {
        NSString *base = iTermTmuxFunctionKeyName(codePoint);
        return base ? iTermTmuxNonTextKeyName(base, modifiers, shift) : nil;
    }
    switch (codePoint) {
        case '\r':
            return iTermTmuxNonTextKeyName(@"Enter", modifiers, shift);
        case '\t':
            // BTab rather than S-Tab: tmux encodes BTab as CSI Z in legacy and
            // modifyOtherKeys 1 mode, as xterm does, and as Shift+Tab in the
            // others, whereas S-Tab loses the shift in legacy mode.
            return iTermTmuxNonTextKeyName(shift ? @"BTab" : @"Tab", modifiers, NO);
        case 0x1b:
            return iTermTmuxNonTextKeyName(@"Escape", modifiers, shift);
        case 0x7f:
            return iTermTmuxNonTextKeyName(@"BSpace", modifiers, shift);
        default:
            break;
    }
    // A printable key. It is text unless a modifier makes it a key combination,
    // which is exactly the modifyOtherKeys "other key" rule.
    return iTermTmuxControlModeOtherKeyName(codePoint, modifiers, optionActsAsMeta, NO);
}
