/*
* Copyright (c) 2009, 2010 <andrew iain mcdermott via gmail>
*
* Source can be cloned from:
*
*  git://github.com/aim-stuff/cmd-key-happy.git
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to
* deal in the Software without restriction, including without limitation the
* rights to use, copy, modify, merge, publish, distribute, sublicense,
* and/or sell copies of the Software, and to permit persons to whom the
* Software is furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
* DEALINGS IN THE SOFTWARE.
*/

#import <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>

#import "iTermModifierRemapper.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplicationDelegate.h"
#import "iTermEventTap.h"
#import "iTermHotKeyController.h"
#import "iTermKeyMappings.h"
#import "iTermKeystroke.h"
#import "iTermShortcutInputView.h"
#import "iTermSystemVersion.h"
#import "NSEvent+iTerm.h"

@interface iTermModifierRemapper()<iTermEventTapRemappingDelegate>
@end

@implementation iTermModifierRemapper {
    iTermEventTap *_keyDown;
    iTermEventTap *_keyUp;
    BOOL _remapped;
    CGEventFlags _flags;
}

+ (NSInteger)_cgMaskForMod:(int)mod {
    switch (mod) {
        case kPreferencesModifierTagLegacyRightControl:
        case kPreferencesModifierTagLeftControl:
        case kPreferencesModifierTagRightControl:
            return kCGEventFlagMaskControl;

        case kPreferencesModifierTagLeftOption:
        case kPreferencesModifierTagRightOption:
        case kPreferencesModifierTagEitherOption:
            return kCGEventFlagMaskAlternate;

        case kPreferencesModifierTagEitherCommand:
        case kPreferencesModifierTagLeftCommand:
        case kPreferencesModifierTagRightCommand:
            return kCGEventFlagMaskCommand;

        case kPreferencesModifierTagCommandAndOption:
            return kCGEventFlagMaskCommand | kCGEventFlagMaskAlternate;

        case kPreferenceModifierTagFunction:
            return kCGEventFlagMaskSecondaryFn;

        default:
            return 0;
    }
}

+ (NSInteger)_nxMaskForLeftMod:(int)mod {
    switch (mod) {
        case kPreferencesModifierTagLegacyRightControl:
            return NX_DEVICELCTLKEYMASK;

        case kPreferencesModifierTagLeftControl:
            return NX_DEVICELCTLKEYMASK;

        case kPreferencesModifierTagRightControl:
            return NX_DEVICERCTLKEYMASK;

        case kPreferencesModifierTagLeftOption:
            return NX_DEVICELALTKEYMASK;

        case kPreferencesModifierTagRightOption:
            return NX_DEVICERALTKEYMASK;

        case kPreferencesModifierTagEitherOption:
            return NX_DEVICELALTKEYMASK;

        case kPreferencesModifierTagRightCommand:
            return NX_DEVICERCMDKEYMASK;

        case kPreferencesModifierTagLeftCommand:
        case kPreferencesModifierTagEitherCommand:
            return NX_DEVICELCMDKEYMASK;

        case kPreferencesModifierTagCommandAndOption:
            return NX_DEVICELCMDKEYMASK | NX_DEVICELALTKEYMASK;

        case kPreferenceModifierTagFunction:
            return NX_SECONDARYFNMASK;

        default:
            return 0;
    }
}

+ (NSInteger)_nxMaskForRightMod:(int)mod {
    switch (mod) {
        case kPreferencesModifierTagLegacyRightControl:
            return NX_DEVICERCTLKEYMASK;

        case kPreferencesModifierTagLeftControl:
            return NX_DEVICELCTLKEYMASK;

        case kPreferencesModifierTagRightControl:
            return NX_DEVICERCTLKEYMASK;

        case kPreferencesModifierTagLeftOption:
            return NX_DEVICELALTKEYMASK;

        case kPreferencesModifierTagRightOption:
            return NX_DEVICERALTKEYMASK;

        case kPreferencesModifierTagEitherOption:
            return NX_DEVICERALTKEYMASK;

        case kPreferencesModifierTagLeftCommand:
            return NX_DEVICELCMDKEYMASK;

        case kPreferencesModifierTagRightCommand:
        case kPreferencesModifierTagEitherCommand:
            return NX_DEVICERCMDKEYMASK;

        case kPreferencesModifierTagCommandAndOption:
            return NX_DEVICERCMDKEYMASK | NX_DEVICERALTKEYMASK;

        case kPreferenceModifierTagFunction:
            return NX_SECONDARYFNMASK;

        default:
            return 0;
    }
}

+ (NSInteger)_cgMaskForLeftCommandKey {
    return [self _cgMaskForMod:[[iTermModifierRemapper sharedInstance] leftCommandRemapping]];
}

+ (NSInteger)_cgMaskForRightCommandKey {
    return [self _cgMaskForMod:[[iTermModifierRemapper sharedInstance] rightCommandRemapping]];
}

+ (NSInteger)_nxMaskForLeftCommandKey {
    return [self _nxMaskForLeftMod:[[iTermModifierRemapper sharedInstance] leftCommandRemapping]];
}

+ (NSInteger)_nxMaskForRightCommandKey {
    return [self _nxMaskForRightMod:[[iTermModifierRemapper sharedInstance] rightCommandRemapping]];
}

+ (NSInteger)_cgMaskForLeftAlternateKey {
    return [self _cgMaskForMod:[[iTermModifierRemapper sharedInstance] leftOptionRemapping]];
}

+ (NSInteger)_cgMaskForRightAlternateKey {
    return [self _cgMaskForMod:[[iTermModifierRemapper sharedInstance] rightOptionRemapping]];
}

+ (NSInteger)_nxMaskForLeftAlternateKey {
    return [self _nxMaskForLeftMod:[[iTermModifierRemapper sharedInstance] leftOptionRemapping]];
}

+ (NSInteger)_nxMaskForRightAlternateKey {
    return [self _nxMaskForRightMod:[[iTermModifierRemapper sharedInstance] rightOptionRemapping]];
}

+ (NSInteger)_cgMaskForLeftControlKey {
    return [self _cgMaskForMod:[[iTermModifierRemapper sharedInstance] leftControlRemapping]];
}

+ (NSInteger)_cgMaskForRightControlKey {
    return [self _cgMaskForMod:[[iTermModifierRemapper sharedInstance] rightControlRemapping]];
}

+ (NSInteger)_nxMaskForLeftControlKey {
    return [self _nxMaskForLeftMod:[[iTermModifierRemapper sharedInstance] leftControlRemapping]];
}

+ (NSInteger)_nxMaskForRightControlKey {
    return [self _nxMaskForRightMod:[[iTermModifierRemapper sharedInstance] rightControlRemapping]];
}

+ (NSInteger)_cgMaskForFunctionKey {
    return [self _cgMaskForMod:[[iTermModifierRemapper sharedInstance] functionRemapping]];
}

+ (NSInteger) _nxMaskForFunctionKey {
    return [self _nxMaskForLeftMod:[[iTermModifierRemapper sharedInstance] functionRemapping]];
}

// Fn key remapping and reverse keycode translation
//
// There are two paths for key events:
//
// 1. Event tap path (ET=Y): The event tap at kCGTailAppendEventTap intercepts CGEvents.
//    On modern macOS (Sequoia+), the event tap sees events AFTER macOS applies Fn
//    keycode translation (e.g., Up is already PageUp when Fn is held).
//    remapModifiersInCGEvent: strips SecondaryFn and adds the remapped modifier, then
//    reverseFnKeyTranslationIfNeeded: reverses the keycode translation when Fn is
//    remapped (e.g., PageUp back to Up).
//
// 2. Application path (ET=N): When the event tap is not running (e.g., secure keyboard
//    entry is on), events arrive at -[NSApp sendEvent:] with Fn translation already
//    applied (e.g., keycode is PageUp, not Up). remapModifiersInCGEvent: handles
//    the flags, and reverseFnKeyTranslationIfNeeded: reverses the keycode translation
//    the same way as in the event tap path.
//
// In both paths, reverseFnKeyTranslationIfNeeded: is called unconditionally after
// remapModifiersInCGEvent:. It is a no-op when physicalFnKeyDown is NO or when Fn
// is not remapped (kPreferenceModifierTagFunction).
//
// physicalFnKeyDown tracks whether the physical Fn key is held, via kCGEventFlagsChanged
// events with keycode kVK_Function. It is set by the flagsChanged event tap (which
// runs even with secure keyboard entry). When the flagsChanged event tap is running,
// handleFlagsChangedEvent: in iTermApplication defers to it and does not overwrite
// the value. External keyboards lack a Fn key, so physicalFnKeyDown is always NO
// for them.
//
// The following table enumerates all 2^5 = 32 combinations of:
//   ET:  Event tap runs (Y) or not (N)
//   KB:  Internal laptop keyboard (I) or External keyboard (E)
//   Fn:  Physical Fn key is held (Y) or not (N)
//   Key: Pressed key is in the function area and sets SecondaryFn, e.g., arrow (F)
//        or is a normal key, e.g., a letter (L)
//   Rmp: Fn is remapped to another modifier like Control (Y) or not (N)
//
// Columns show the keycode and flags at each stage. Example fn-area key: Up Arrow
// (Fn-translated form: PageUp). Example normal key: 'a'.
//   Tap: CGEvent arriving at the key-down event tap (kCGTailAppendEventTap).
//        On modern macOS, Fn translation has already been applied.
//   SE:  NSEvent arriving at -[NSApp sendEvent:]
//   Out: CGEvent returned by -[iTermModifierRemapper eventByRemappingEvent:eventTap:]
//        when called from -[iTermApplication eventByRemappingEvent:]
//
// Flags: SF = kCGEventFlagMaskSecondaryFn, C = remapped modifier (e.g., Control)
// "—" means this stage is not reached for the given path.
// "n/a" means the combination is impossible (external keyboards have no Fn key).
//
// For each configuration the result (SE when ET=Y, Out when ET=N) should be
// identical, ensuring consistent behavior regardless of whether the event tap runs.
//
//  #  ET KB Fn Key Rmp   Tap         SE          Out         Result
// --  -- -- -- --- ---   ----------  ----------  ----------  ----------
//  1  Y  I  N  F   N    Up+SF       Up+SF       —           Up+SF
//  2  Y  I  N  F   Y    Up+SF       Up+SF       —           Up+SF
//  3  Y  I  N  L   N    'a'         'a'         —           'a'
//  4  Y  I  N  L   Y    'a'         'a'         —           'a'
//  5  Y  I  Y  F   N    PgUp+SF     PgUp+SF     —           PgUp+SF
//  6  Y  I  Y  F   Y    PgUp+SF     Up+C        —           Up+C
//  7  Y  I  Y  L   N    'a'+SF      'a'+SF      —           'a'+SF
//  8  Y  I  Y  L   Y    'a'+SF      'a'+C       —           'a'+C
//  9  Y  E  N  F   N    Up+SF       Up+SF       —           Up+SF
// 10  Y  E  N  F   Y    Up+SF       Up+SF       —           Up+SF
// 11  Y  E  N  L   N    'a'         'a'         —           'a'
// 12  Y  E  N  L   Y    'a'         'a'         —           'a'
// 13  Y  E  Y  F   N    n/a         n/a         n/a         n/a
// 14  Y  E  Y  F   Y    n/a         n/a         n/a         n/a
// 15  Y  E  Y  L   N    n/a         n/a         n/a         n/a
// 16  Y  E  Y  L   Y    n/a         n/a         n/a         n/a
// 17  N  I  N  F   N    —           Up+SF       Up+SF       Up+SF
// 18  N  I  N  F   Y    —           Up+SF       Up+SF       Up+SF
// 19  N  I  N  L   N    —           'a'         'a'         'a'
// 20  N  I  N  L   Y    —           'a'         'a'         'a'
// 21  N  I  Y  F   N    —           PgUp+SF     PgUp+SF     PgUp+SF
// 22  N  I  Y  F   Y    —           PgUp+SF     Up+C        Up+C
// 23  N  I  Y  L   N    —           'a'+SF      'a'+SF      'a'+SF
// 24  N  I  Y  L   Y    —           'a'+SF      'a'+C       'a'+C
// 25  N  E  N  F   N    —           Up+SF       Up+SF       Up+SF
// 26  N  E  N  F   Y    —           Up+SF       Up+SF       Up+SF
// 27  N  E  N  L   N    —           'a'         'a'         'a'
// 28  N  E  N  L   Y    —           'a'         'a'         'a'
// 29  N  E  Y  F   N    n/a         n/a         n/a         n/a
// 30  N  E  Y  F   Y    n/a         n/a         n/a         n/a
// 31  N  E  Y  L   N    n/a         n/a         n/a         n/a
// 32  N  E  Y  L   Y    n/a         n/a         n/a         n/a
//
// Key rows: #6 vs #22 (Fn+Arrow with Fn remapped) — both produce Up+C.
//           #5 vs #21 (Fn+Arrow, Fn not remapped) — both produce PgUp+SF.
//
// reverseFnKeyTranslationIfNeeded: is responsible for rows 6, 8, 22, and 24: it
// reverses the Fn keycode translation (PgUp->Up, etc.) only when physicalFnKeyDown=YES
// AND Fn is remapped. Row 5/21 shows why both conditions are needed: Fn+Arrow with
// Fn NOT remapped must produce PageUp.
//
// Note on Fn+letter (rows 7, 8, 23, 24): Starting in macOS Sequoia, the system
// intercepts Fn+letter combinations for Globe key shortcuts (e.g., Fn+A opens the
// Finder in the Dock) before any event tap or application receives the keyDown.
// As a result, Fn+letter events may never reach iTerm2 at all, making rows 7/8/23/24
// impossible to fulfill for letters that have Globe shortcuts. Fn+arrow and other
// function-area keys are not affected by this.

+ (void)reverseFnKeyTranslationIfNeeded:(CGEventRef)event {
    const BOOL fnDown = [[iTermModifierRemapper sharedInstance] physicalFnKeyDown];
    iTermPreferencesModifierTag remap = [[iTermModifierRemapper sharedInstance] functionRemapping];
    DLog(@"reverseFnKeyTranslationIfNeeded: physicalFnKeyDown=%d functionRemapping=%d keycode=0x%llx",
         fnDown, (int)remap,
         CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode));
    if (!fnDown) {
        return;
    }
    if (remap == kPreferenceModifierTagFunction) {
        // Fn is not remapped, so preserve macOS's Fn translation (e.g., Fn+Up = PageUp).
        return;
    }
    CGKeyCode keyCode = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    CGKeyCode newKeyCode;
    UniChar newChar;
    switch (keyCode) {
        case kVK_PageUp:
            newKeyCode = kVK_UpArrow;
            newChar = NSUpArrowFunctionKey;
            break;
        case kVK_PageDown:
            newKeyCode = kVK_DownArrow;
            newChar = NSDownArrowFunctionKey;
            break;
        case kVK_Home:
            newKeyCode = kVK_LeftArrow;
            newChar = NSLeftArrowFunctionKey;
            break;
        case kVK_End:
            newKeyCode = kVK_RightArrow;
            newChar = NSRightArrowFunctionKey;
            break;
        case kVK_ForwardDelete:
            newKeyCode = kVK_Delete;
            newChar = 0x7F;
            break;
        default:
            return;
    }
    DLog(@"Reversing Fn key translation: keycode 0x%x -> 0x%x", (int)keyCode, (int)newKeyCode);
    CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode, newKeyCode);
    CGEventKeyboardSetUnicodeString(event, 1, &newChar);
}

+ (CGEventRef)remapModifiersInCGEvent:(CGEventRef)cgEvent {
    // This function copied from cmd-key happy. See copyright notice at top.
    CGEventFlags flags = CGEventGetFlags(cgEvent);
    DLog(@"Performing remapping. On input CGEventFlags=%@", @(flags));
    CGEventFlags andMask = -1;
    CGEventFlags orMask = 0;

    // flags contains both device-dependent flags and device-independent flags.
    // The device-independent flags are named kCGEventFlagMaskXXX or NX_xxxMASK
    // The device-dependent flags are named NX_DEVICExxxKEYMASK
    // Device-independent flags do not indicate leftness or rightness.
    // Device-dependent flags do.
    // Generally, you get both sets of flags. But this does not have to be the case if an event
    // is synthesized, as seen in issue 5207 where Flycut does not set the device-dependent flags.
    // If the event lacks device-specific flags we'll add them when synergyModifierRemappingEnabled
    // is on. Otherwise, we don't remap them.
    if (flags & kCGEventFlagMaskCommand) {
        BOOL hasDeviceIndependentFlagsForCommandKey = ((flags & (NX_DEVICELCMDKEYMASK | NX_DEVICERCMDKEYMASK)) != 0);
        if (!hasDeviceIndependentFlagsForCommandKey) {
            if ([iTermAdvancedSettingsModel synergyModifierRemappingEnabled]) {
                flags |= NX_DEVICELCMDKEYMASK;
                hasDeviceIndependentFlagsForCommandKey = YES;
            }
        }
        if (hasDeviceIndependentFlagsForCommandKey) {
            andMask &= ~kCGEventFlagMaskCommand;
            if (flags & NX_DEVICELCMDKEYMASK) {
                andMask &= ~NX_DEVICELCMDKEYMASK;
                orMask |= [self _cgMaskForLeftCommandKey];
                orMask |= [self _nxMaskForLeftCommandKey];
            }
            if (flags & NX_DEVICERCMDKEYMASK) {
                andMask &= ~NX_DEVICERCMDKEYMASK;
                orMask |= [self _cgMaskForRightCommandKey];
                orMask |= [self _nxMaskForRightCommandKey];
            }
        }
    }
    if (flags & kCGEventFlagMaskAlternate) {
        BOOL hasDeviceIndependentFlagsForOptionKey = ((flags & (NX_DEVICELALTKEYMASK | NX_DEVICERALTKEYMASK)) != 0);
        if (!hasDeviceIndependentFlagsForOptionKey) {
            if ([iTermAdvancedSettingsModel synergyModifierRemappingEnabled]) {
                flags |= NX_DEVICELALTKEYMASK;
                hasDeviceIndependentFlagsForOptionKey = YES;
            }
        }
        if (hasDeviceIndependentFlagsForOptionKey) {
            andMask &= ~kCGEventFlagMaskAlternate;
            if (flags & NX_DEVICELALTKEYMASK) {
                andMask &= ~NX_DEVICELALTKEYMASK;
                orMask |= [self _cgMaskForLeftAlternateKey];
                orMask |= [self _nxMaskForLeftAlternateKey];
            }
            if (flags & NX_DEVICERALTKEYMASK) {
                andMask &= ~NX_DEVICERALTKEYMASK;
                orMask |= [self _cgMaskForRightAlternateKey];
                orMask |= [self _nxMaskForRightAlternateKey];
            }
        }
    }
    if (flags & kCGEventFlagMaskControl) {
        BOOL hasDeviceIndependentFlagsForControlKey = ((flags & (NX_DEVICELCTLKEYMASK | NX_DEVICERCTLKEYMASK)) != 0);
        if (!hasDeviceIndependentFlagsForControlKey) {
            if ([iTermAdvancedSettingsModel synergyModifierRemappingEnabled]) {
                flags |= NX_DEVICELCTLKEYMASK;
                hasDeviceIndependentFlagsForControlKey = YES;
            }
        }
        if (hasDeviceIndependentFlagsForControlKey) {
            andMask &= ~kCGEventFlagMaskControl;
            if (flags & NX_DEVICELCTLKEYMASK) {
                andMask &= ~NX_DEVICELCTLKEYMASK;
                orMask |= [self _cgMaskForLeftControlKey];
                orMask |= [self _nxMaskForLeftControlKey];
            }
            if (flags & NX_DEVICERCTLKEYMASK) {
                andMask &= ~NX_DEVICERCTLKEYMASK;
                orMask |= [self _cgMaskForRightControlKey];
                orMask |= [self _nxMaskForRightControlKey];
            }
        }
    }
    {
        BOOL hasFnFlag = (flags & kCGEventFlagMaskSecondaryFn) != 0;
        BOOL fnDown = [[iTermModifierRemapper sharedInstance] physicalFnKeyDown];
        DLog(@"remapModifiersInCGEvent: Fn check: hasFnFlag=%d physicalFnKeyDown=%d keycode=0x%llx",
             hasFnFlag, fnDown,
             CGEventGetIntegerValueField(cgEvent, kCGKeyboardEventKeycode));
        if (hasFnFlag && fnDown) {
            andMask &= ~kCGEventFlagMaskSecondaryFn;
            orMask |= [self _cgMaskForFunctionKey];
            orMask |= [self _nxMaskForFunctionKey];
        }
    }
    DLog(@"On output CGEventFlags=%@", @((flags & andMask) | orMask));

    CGEventSetFlags(cgEvent, (flags & andMask) | orMask);
    return cgEvent;
}

+ (NSEvent *)remapModifiers:(NSEvent *)event {
    return [NSEvent eventWithCGEvent:[self remapModifiersInCGEvent:[event CGEvent]]];
}

+ (instancetype)sharedInstance {
  static dispatch_once_t onceToken;
  static id instance;
  dispatch_once(&onceToken, ^{
      instance = [[self alloc] init];
  });
  return instance;
}

- (void)dealloc {
    [_keyDown release];
    [_keyUp release];
    [super dealloc];
}

#pragma mark - APIs

- (void)setRemapModifiers:(BOOL)remapModifiers {
  if (remapModifiers) {
      [self beginRemappingModifiers];
  } else {
      [self stopRemappingModifiers];
  }
}

- (BOOL)isRemappingModifiers {
    return [_keyDown isEnabled] && [iTermPreferences boolForKey:kPreferenceKeyRemapModifiersGlobally];
}

- (iTermPreferencesModifierTag)leftControlRemapping {
    return [iTermPreferences intForKey:kPreferenceKeyLeftControlRemapping];
}

- (iTermPreferencesModifierTag)rightControlRemapping {
    return [iTermPreferences intForKey:kPreferenceKeyRightControlRemapping];
}

- (iTermPreferencesModifierTag)leftOptionRemapping {
  return [iTermPreferences intForKey:kPreferenceKeyLeftOptionRemapping];
}

- (iTermPreferencesModifierTag)rightOptionRemapping {
  return [iTermPreferences intForKey:kPreferenceKeyRightOptionRemapping];
}

- (iTermPreferencesModifierTag)leftCommandRemapping {
  return [iTermPreferences intForKey:kPreferenceKeyLeftCommandRemapping];
}

- (iTermPreferencesModifierTag)rightCommandRemapping {
  return [iTermPreferences intForKey:kPreferenceKeyRightCommandRemapping];
}

- (iTermPreferencesModifierTag)functionRemapping {
    return [iTermPreferences intForKey:kPreferenceKeyFunctionRemapping];
}

- (BOOL)isAnyModifierRemapped {
  return ([self leftControlRemapping] != kPreferencesModifierTagLeftControl ||
          [self rightControlRemapping] != kPreferencesModifierTagRightControl ||
          [self leftOptionRemapping] != kPreferencesModifierTagLeftOption ||
          [self rightOptionRemapping] != kPreferencesModifierTagRightOption ||
          [self leftCommandRemapping] != kPreferencesModifierTagLeftCommand ||
          [self rightCommandRemapping] != kPreferencesModifierTagRightCommand ||
          [self functionRemapping] != kPreferenceModifierTagFunction);
}


#pragma mark - Private

- (iTermEventTap *)keyDown {
    if ([iTermAdvancedSettingsModel remapModifiersWithoutEventTap]) {
        return nil;
    }
    if (!_keyDown) {
        _keyDown = [[iTermEventTap alloc] initWithEventTypes:CGEventMaskBit(kCGEventKeyDown)];
    }
    return _keyDown;
}

- (iTermEventTap *)keyUp {
    if ([iTermAdvancedSettingsModel remapModifiersWithoutEventTap]) {
        return nil;
    }
    if (!_keyUp) {
        _keyUp = [[iTermEventTap alloc] initWithEventTypes:CGEventMaskBit(kCGEventKeyUp)];
    }
    return _keyUp;
}

- (void)beginRemappingModifiers {
    DLog(@"Begin remapping modifiers");
    [self.keyDown setRemappingDelegate:self];
    [self.keyUp setRemappingDelegate:self];
    if ([iTermAdvancedSettingsModel remapModifiersWithoutEventTap]) {
        return;
    }

    [[iTermFlagsChangedEventTap sharedInstance] setRemappingDelegate:self];

    if (![_keyDown isEnabled]) {
        DLog(@"The event tap is NOT enabled");
        [self requestAccessibilityPermission];
    }
}

- (void)stopRemappingModifiers {
    [_keyDown setRemappingDelegate:nil];
    [_keyUp setRemappingDelegate:nil];
    [[iTermFlagsChangedEventTap sharedInstanceCreatingIfNeeded:NO] setRemappingDelegate:nil];
}

- (void)requestAccessibilityPermission {
    if ([iTermAdvancedSettingsModel remapModifiersWithoutEventTap]) {
        return;
    }

    DLog(@"Requesting accessibility permission");
    [[iTermPermissionsHelper accessibility] request];
}

#pragma mark - iTermEventTapRemappingDelegate

- (CGEventRef)remappedEventFromEventTap:(iTermEventTap *)eventTap
                               withType:(CGEventType)type
                                  event:(CGEventRef)event {
    DLog(@"Modifier remapper event tap got an event: %@", [NSEvent eventWithCGEvent:event]);
    if (![iTermPreferences boolForKey:kPreferenceKeyRemapModifiersGlobally]) {
        DLog(@"Flags changed remapping disabled by advanced setting");
        return event;
    }
    if (type == kCGEventFlagsChanged) {
        int64_t keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        CGEventFlags tapFlags = CGEventGetFlags(event);
        if (keycode == kVK_Function) {
            self.physicalFnKeyDown = (tapFlags & kCGEventFlagMaskSecondaryFn) != 0;
            DLog(@"eventTap: set physicalFnKeyDown=%d", self.physicalFnKeyDown);
        }
    }
    if ([NSApp isActive]) {
        DLog(@"App is active, performing remapping");
        // Remap modifier keys only while iTerm2 is active; otherwise you could just use the
        // OS's remap feature.
        const BOOL hadRemapped = _remapped;
        const NSEventModifierFlags before = [NSEvent eventWithCGEvent:event].modifierFlags;
        CGEventRef remappedEvent = [self eventByRemappingEvent:event eventTap:eventTap];
        DLog(@"Remapped modifiers from %x to %x in event tap", (int)before, (int)[NSEvent eventWithCGEvent:remappedEvent].modifierFlags);
        if (remappedEvent) {
            if ([iTermAdvancedSettingsModel postFakeFlagsChangedEvents]) {
                if (hadRemapped != _remapped &&
                    CGEventGetFlags(event) != _flags &&
                    (CGEventGetType(event) == kCGEventKeyDown || CGEventGetType(event) == kCGEventKeyUp)) {
                    CGEventRef fakeEvent = [self createFakeFlagsChangedEvent:CGEventGetFlags(event)];
                    DLog(@"remapped %@ -> %@, flags %@ -> %@, event type is %@. Post fake flags-changed event: %@",
                          @(hadRemapped), @(_remapped),
                          @(_flags), @(CGEventGetFlags(event)),
                          @(CGEventGetType(event)),
                          [NSEvent eventWithCGEvent:fakeEvent]);
                    CGEventPost(kCGHIDEventTap, fakeEvent);
                    CFRelease(fakeEvent);
                }
                _flags = CGEventGetFlags(remappedEvent);
            }
        }
        DLog(@"Return remapped event: %@", [NSEvent eventWithCGEvent:remappedEvent]);
        return remappedEvent;
    } else {
        DLog(@"iTerm2 not active. The active app is %@", [[NSWorkspace sharedWorkspace] frontmostApplication]);
        return event;
    }
}

- (CGEventRef)createFakeFlagsChangedEvent:(CGEventFlags)flags {
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventRef event = CGEventCreate(source);
    CGEventSetType(event, kCGEventFlagsChanged);
    CGEventSetFlags(event, flags);
    CFRelease(source);
    return event;
}

// Only called when the app is active.
- (CGEventRef)eventByRemappingEvent:(CGEventRef)event eventTap:(iTermEventTap *)eventTap {
    NSEvent *cocoaEvent = [NSEvent eventWithCGEvent:event];

    DLog(@"Remapping event %@ from keyboard of type %@", cocoaEvent, @(CGEventGetIntegerValueField(event, kCGKeyboardEventKeyboardType)));
    
    iTermShortcutInputView *shortcutView = nil;
    NSResponder *firstResponder = [[NSApp keyWindow] firstResponder];
    if ([firstResponder isKindOfClass:[iTermShortcutInputView class]]) {
        shortcutView = (iTermShortcutInputView *)firstResponder;
    }

    if (shortcutView.disableKeyRemapping) {
        DLog(@"Shortcut view is active so return nil");
        // Send keystroke directly to preference panel when setting do-not-remap for a key; for
        // system keys, NSApp sendEvent: is never called so this is the last chance.
        [shortcutView handleShortcutEvent:cocoaEvent];
        _remapped = NO;
        return nil;
    }

    switch ([self boundActionForEvent:cocoaEvent]) {
        case KEY_ACTION_REMAP_LOCALLY:
            DLog(@"Calling sendEvent:");
            [self.class remapModifiersInCGEvent:event];
            [self.class reverseFnKeyTranslationIfNeeded:event];
            if (eventTap != nil) {
                // Only re-send through sendEvent when coming from the event tap
                [NSApp sendEvent:[NSEvent eventWithCGEvent:event]];
                _remapped = NO;
                return nil;
            }
            // When called from application-level remapping (eventTap==nil), just return the remapped event
            _remapped = YES;
            return event;

        case KEY_ACTION_DO_NOT_REMAP_MODIFIERS:
            DLog(@"Action is do not remap");
            _remapped = NO;
            return event;

        default:
            DLog(@"Remapping as usual");
            [self.class remapModifiersInCGEvent:event];
            [self.class reverseFnKeyTranslationIfNeeded:event];
            _remapped = YES;
            return event;
    }
}

- (KEY_ACTION)boundActionForEvent:(NSEvent *)cocoaEvent {
    if (cocoaEvent.type != NSEventTypeKeyDown && cocoaEvent.type != NSEventTypeKeyUp) {
        DLog(@"Not keydown %@", cocoaEvent);
        return -1;
    }
    iTermKeystroke *keystroke = [iTermKeystroke withEvent:cocoaEvent];
    iTermKeyBindingAction *action = [iTermKeyMappings actionForKeystroke:keystroke
                                                             keyMappings:nil];
    return action ? action.keyAction : KEY_ACTION_INVALID;
}

@end
