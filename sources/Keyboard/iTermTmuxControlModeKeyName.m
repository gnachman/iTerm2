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
