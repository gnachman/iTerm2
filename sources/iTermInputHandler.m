//
//  iTermInputHandler.m
//  iTerm2
//
//  Created by George Nachman on 7/11/15.
//
//

#import "iTermInputHandler.h"
#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermApplicationDelegate.h"
#import "iTermNSKeyBindingEmulator.h"
#import "PreferencePanel.h"
#import "VT100Output.h"

// In case I ever need it:
// static const LeftAlternateKeyMask = (0x000020 | NSAlternateKeyMask);
static const NSEventModifierFlags RightAlternateKeyMask = (0x000040 | NSAlternateKeyMask);

@interface iTermInputHandler()
@property(nonatomic, assign) BOOL lastKeyPressWasRepeating;
@end

@implementation iTermInputHandler

- (void)handleKeyDownEvent:(NSEvent *)event {
   DLog(@"handleKeyDownEvent: %@", event);

    [self logDebugInfoForEvent:event];

    // discard repeated key events if auto repeat mode (DECARM) is disabled
    if ([event isARepeat] && !_delegate.inputHandlerShouldAutoRepeat) {
        return;
    }

    self.lastKeyPressWasRepeating = [event isARepeat];

    // First try to execute a bound action. This will happen rarely because
    // bound actions are normally run directly from -[iTermApplication
    // sendEvent:] before any other processing happens. There are a handful of
    // oddball conditions where that might not be true. For example, if you add a
    // key binding while a key action is queued up during pasting.
    if ([_delegate inputHandlerExecuteBoundActionForEvent:event]) {
        DLog(@"Executed bound action. Returning.");
        return;
    }

    // Dead sessions can't handle keypresses that send text, and everything past this
    // point sends text (the only exception being events going to the IME which
    // could get canceled).
    if (_delegate.inputHandlerSessionHasExited) {
        DLog(@"Session has exited.");
        return;
    }

    const BOOL hadMarkedText = _delegate.inputHandlerHasMarkedText;

    if ([self eventShouldBeInterpreted:event]) {
        [_delegate inputHandlerInterpretEvents:@[ event ]];

        if (hadMarkedText ||                        // IME handled it
            _delegate.inputHandlerHasMarkedText ||  // IME started marked text
            _delegate.inputHandlerDidInsertText) {  // Something was inserted
            [NSCursor setHiddenUntilMouseMoves:YES];
            return;
        }
    }

    if (event.modifierFlags & NSCommandKeyMask) {
        DLog(@"Aborting because command key is pressed and there is no bound action.");
        return;
    }

    // Try to send data for the keypress ourselves.
    NSData *data = [self dataForKeyEvent:event];
    if (data) {
        DLog(@"Write data: %@", data);
        [NSCursor setHiddenUntilMouseMoves:YES];
        [_delegate inputHandlerWriteData:data];
    }
}

// Returns YES if the key event should be sent to interpretKeyEvents. There are
// three reasons it would be a good idea:
//   1. DefaultKeyBinding.dict has something for it to do, we're pretty sure
//   2. The input method editor might want to start
//   3. The input method editor is in effect nad can handle it
- (BOOL)eventShouldBeInterpreted:(NSEvent *)event {
    // See if DefaultKeyBinding.dict has anything defined that inserts text.
    if ([[iTermNSKeyBindingEmulator sharedInstance] handlesEvent:event]) {
      return YES;
    }

    if (event.modifierFlags & NSCommandKeyMask) {
        // This would cause cmd+key to insert the key, so we must not handle it
        // unless there's a DefaultKeyBinding for it.
        return NO;
    }

    if (_delegate.inputHandlerHasMarkedText) {
        // IME already going. Let it handle anything that comes.
        return YES;
    }

    // The IME won't start on function keys, opt+key, or ctrl+key.
    // This is an undocumented assumption but it has held up OK over time.
    if (event.modifierFlags & (NSNumericPadKeyMask | NSFunctionKeyMask)) {
        return NO;
    }

    if ([self dataForOptionKeyPress:event].length > 0) {
        return NO;
    }

    if ([self dataForControlKeyEvent:event].length > 0) {
        // It's important not to send control keys to interpretKeyEvents in this case because it
        // will break with custom keyboard layouts, as described in issue 1097.
        return NO;
    }

    return YES;
}

- (NSData *)dataForKeyEvent:(NSEvent *)event {
    // Arrow keys, etc.
    NSData *data = [self dataForFunctionKeyPress:event];
    if (!data) {
        // Add esc to the pressed key's string (or set the high bits for Meta).
        data = [self dataForOptionKeyPress:event];
    }
    if (!data) {
        // Try to handle control keys.
        data = [self dataForControlKeyEvent:event];
    }
    if (!data) {
        // Try to handle everything else (normal case)
        data = [self dataForRegularKeyPress:event];
    }

    return data;
}

- (NSData *)dataForFunctionKeyPress:(NSEvent *)event {
    if (!(event.modifierFlags & NSFunctionKeyMask)) {
        return nil;
    }
    DLog(@"PTYSession keyDown is a function key");
    // Handle all "special" keys (arrows, etc.)
    NSData *data = nil;
    const unichar unicode = [event.characters length] > 0 ? [event.characters characterAtIndex:0] : 0;

    VT100Output *output = [_delegate inputHandlerOutputGenerator];
    switch (unicode) {
        case NSUpArrowFunctionKey:
            data = [output keyArrowUp:event.modifierFlags];
            break;
        case NSDownArrowFunctionKey:
            data = [output keyArrowDown:event.modifierFlags];
            break;
        case NSLeftArrowFunctionKey:
            data = [output keyArrowLeft:event.modifierFlags];
            break;
        case NSRightArrowFunctionKey:
            data = [output keyArrowRight:event.modifierFlags];
            break;
        case NSInsertFunctionKey:
            data = [output keyInsert];
            break;
        case NSDeleteFunctionKey:
            // This is forward delete, not backspace.
            data = [output keyDelete];
            break;
        case NSHomeFunctionKey:
            data = [output keyHome:event.modifierFlags];
            break;
        case NSEndFunctionKey:
            data = [output keyEnd:event.modifierFlags];
            break;
        case NSPageUpFunctionKey:
            data = [output keyPageUp:event.modifierFlags];
            break;
        case NSPageDownFunctionKey:
            data = [output keyPageDown:event.modifierFlags];
            break;
        case NSClearLineFunctionKey:
            data = [@"\e" dataUsingEncoding:NSUTF8StringEncoding];
            break;
    }

    if (NSF1FunctionKey <= unicode && unicode <= NSF35FunctionKey) {
        data = [output keyFunction:unicode - NSF1FunctionKey + 1];
    }

    if (data != nil) {
        return data;
    } else if (event.characters != nil) {
        // I'm pretty sure this never happens, but it was added in the original
        // iTerm in response to a specific bug (though that issue report is gone).
        return ((event.modifierFlags & NSControlKeyMask) && unicode > 0) ?
            [event.characters dataUsingEncoding:_delegate.inputHandlerEncoding] :
            [event.charactersIgnoringModifiers dataUsingEncoding:_delegate.inputHandlerEncoding];
    } else {
        return nil;
    }
}

// WARNING: This assumes that one of the option keys is pressed.
- (iTermOptionKeyAction)optionModeForFlags:(NSEventModifierFlags)modifierFlags {
    const BOOL rightAltPressed = (modifierFlags & RightAlternateKeyMask) == RightAlternateKeyMask;
    const BOOL leftAltPressed = (modifierFlags & NSAlternateKeyMask) == NSAlternateKeyMask && !rightAltPressed;
    if (leftAltPressed) {
        return [_delegate inputHandlerLeftOptionKeyBehavior];
    } else if (rightAltPressed) {
        return [_delegate inputHandlerRightOptionKeyBehavior];
    }
    return OPT_NORMAL;
}

- (NSData *)dataForOptionKeyPress:(NSEvent *)event {
    if ([self optionModeForFlags:event.modifierFlags] == OPT_NORMAL) {
        return nil;
    }
    DLog(@"PTYSession keyDown opt + key -> modkey");
    // A key was pressed while holding down option and the option key
    // is not behaving normally. Apply the modified behavior.

    NSData *data = ((event.modifierFlags & NSControlKeyMask) && event.characters.length > 0)
        ? [event.characters dataUsingEncoding:_delegate.inputHandlerEncoding]
        : [event.charactersIgnoringModifiers dataUsingEncoding:_delegate.inputHandlerEncoding];
    return [self dataByApplyingMetaOrEsc:data modifierFlags:event.modifierFlags];
}

- (NSData *)dataForRegularKeyPress:(NSEvent *)event {
    DLog(@"PTYSession keyDown regular path");
    // Regular path for inserting a character from a keypress.
    NSString *keystr = event.characters;
    NSData *data = [keystr dataUsingEncoding:_delegate.inputHandlerEncoding];
    unichar unicode = event.characters.length > 0 ? [event.characters characterAtIndex:0] : 0;
    unichar unmodunicode = [event.charactersIgnoringModifiers characterAtIndex:0];
    NSEventModifierFlags modifierFlags = event.modifierFlags;

    // Enter key is on numeric keypad, but not marked as such
    if (unicode == NSEnterCharacter && unmodunicode == NSEnterCharacter) {
        modifierFlags |= NSNumericPadKeyMask;
        DLog(@"Enter key on numeric keypad pressed");
        keystr = @"\015";  // Enter key -> 0x0d
    }

    if (modifierFlags & NSNumericPadKeyMask) {
        // Handle numeric keypad keys, which get different output depending on the terminal's mode.
        DLog(@"Numeric keypad mask is set");
        data = [[_delegate inputHandlerOutputGenerator] keypadData:unicode keystr:keystr];
    }

    DLog(@"data=%@", data);

    if ((modifierFlags & NSShiftKeyMask) &&
        data.length == 1 &&
        ((const char *)data.bytes)[0] == '\031') {
        DLog(@"shift-tab -> esc[Z");
        // Shift-tab is sent as Esc-[Z (or "backtab")
        return [@"\033[Z" dataUsingEncoding:[_delegate inputHandlerEncoding]];
    }

    return data;
}

- (NSData *)dataByApplyingMetaOrEsc:(NSData *)dataToSend
                      modifierFlags:(NSEventModifierFlags)modifierFlags {
    int mode = [self optionModeForFlags:modifierFlags];  // The modified behavior based on which modifier is pressed.
    if (mode == OPT_ESC) {
        // Prepend an escape.
        NSMutableData *temp = [[dataToSend mutableCopy] autorelease];
        [temp replaceBytesInRange:NSMakeRange(0, 0) withBytes:"\e" length:1];
        return temp;
    } else if (mode == OPT_META) {
        // Set the high bit in all characters. This is obviously insane with anything
        // but a 7-bit encoding like ASCII.
        NSMutableData *temp = [[dataToSend mutableCopy] autorelease];
        char *tempBytes = temp.mutableBytes;
        for (int i = 0; i < temp.length; ++i) {
            tempBytes[i] |= 0x80;
        }
        return temp;
    }
    return dataToSend;
}

- (void)logDebugInfoForEvent:(NSEvent *)event {
    const BOOL rightAltPressed =
        (event.modifierFlags & RightAlternateKeyMask) == RightAlternateKeyMask;
    const BOOL leftAltPressed =
        (event.modifierFlags & NSAlternateKeyMask) == NSAlternateKeyMask && !rightAltPressed;
    DLog(@"textViewKeyDown:");
    DLog(@"  modifierFlags=%d keycode=%d", (int)event.modifierFlags, (int)[event keyCode]);
    DLog(@"  hadMarkedText=%d", (int)[_delegate inputHandlerHasMarkedText]);
    DLog(@"  hasActionableKeyMappingForEvent=%d",
         (int)[_delegate inputHandlerHasActionableKeyMappingForEvent:event]);
    DLog(@"  modFlag & (NSNumericPadKeyMask | NSFUnctionKeyMask)=%lu",
         (event.modifierFlags & (NSNumericPadKeyMask | NSFunctionKeyMask)));
    DLog(@"  charactersIgnoringModififiers length=%d",
         (int)[[event charactersIgnoringModifiers] length]);
    DLog(@"  optionkey=%d, delegate rightOptionKey=%d",
         (int)[_delegate inputHandlerLeftOptionKeyBehavior],
         (int)[_delegate inputHandlerRightOptionKeyBehavior]);
    DLog(@"  leftAltPressed && optionKey != NORMAL = %d",
         (int)(leftAltPressed && [_delegate inputHandlerLeftOptionKeyBehavior] != OPT_NORMAL));
    DLog(@"  rightAltPressed && rightOptionKey != NORMAL = %d",
         (int)(rightAltPressed && [_delegate inputHandlerRightOptionKeyBehavior] != OPT_NORMAL));
    DLog(@"  isControl=%d", (int)(event.modifierFlags & NSControlKeyMask));
    DLog(@"  event is repeated=%d", event.isARepeat);
}

- (NSData *)dataForControlKeyEvent:(NSEvent *)event {
    NSUInteger flagMask = (NSControlKeyMask | NSCommandKeyMask | NSAlternateKeyMask);
    if ((event.modifierFlags & flagMask) != NSControlKeyMask) {
        return nil;
    }
    DLog(@"Special ctrl+key handler running");

    NSString *unmodkeystr = [event charactersIgnoringModifiers];
    if ([unmodkeystr length] != 0) {
        unichar unmodunicode = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
        unichar code = 0xffff;
        if (unmodunicode >= 'a' && unmodunicode <= 'z') {
            code = unmodunicode - 'a' + 1;
        } else if (unmodunicode == ' ' || unmodunicode == '2' || unmodunicode == '@') {
            code = 0;
        } else if (unmodunicode == '[') {  // esc
            code = 27;
        } else if (unmodunicode == '\\' || unmodunicode == '|') {
            code = 28;
        } else if (unmodunicode == ']') {
            code = 29;
        } else if (unmodunicode == '^' || unmodunicode == '6') {
            code = 30;
        } else if (unmodunicode == '-' || unmodunicode == '_') {
            code = 31;
        } else if (unmodunicode == '/') {
            if (event.modifierFlags & NSShiftKeyMask) {
                // Control-shift-/ is sent as Control-?, which is delete.
                code = 127;
            } else {
                // Control-/ is treated like Ctrl-_ (TODO: Why?)
                code = 31;
            }
        }
        if (code != 0xffff) {
            DLog(@"Send control code %d", (int)code);
            return [[NSString stringWithCharacters:&code length:1] dataUsingEncoding:[_delegate inputHandlerEncoding]];
        }
    }

    return nil;
}

@end
