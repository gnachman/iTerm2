
#import <Cocoa/Cocoa.h>

#import "iTermModifierRemapper.h"
#import "DebugLogging.h"
#import "iTermApplicationDelegate.h"
#import "iTermHotKeyController.h"
#import "iTermKeyBindingMgr.h"
#import "iTermEventTap.h"
#import "iTermShortcutInputView.h"
#import "iTermSystemVersion.h"

@interface iTermModifierRemapper()<iTermEventTapRemappingDelegate>
@end

@implementation iTermModifierRemapper {
    iTermEventTap *_keyDown;
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
  return [_keyDown isEnabled];
}

- (iTermPreferencesModifierTag)controlRemapping {
  return [iTermPreferences intForKey:kPreferenceKeyControlRemapping];
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

- (BOOL)isAnyModifierRemapped {
  return ([self controlRemapping] != kPreferencesModifierTagControl ||
          [self leftOptionRemapping] != kPreferencesModifierTagLeftOption ||
          [self rightOptionRemapping] != kPreferencesModifierTagRightOption ||
          [self leftCommandRemapping] != kPreferencesModifierTagLeftCommand ||
          [self rightCommandRemapping] != kPreferencesModifierTagRightCommand);
}


#pragma mark - Private

- (iTermEventTap *)keyDown {
    if (!_keyDown) {
        _keyDown = [[iTermEventTap alloc] initWithEventTypes:CGEventMaskBit(kCGEventKeyDown)];
    }
    return _keyDown;
}

- (void)beginRemappingModifiers {
    DLog(@"Begin remapping modifiers");
    [self.keyDown setRemappingDelegate:self];
    [[iTermFlagsChangedEventTap sharedInstance] setRemappingDelegate:self];

    if (![_keyDown isEnabled]) {
        DLog(@"The event tap is NOT enabled");
        [self requestAccessibilityPermission];
    }
}

- (void)stopRemappingModifiers {
    [_keyDown setRemappingDelegate:nil];
    [[iTermFlagsChangedEventTap sharedInstance] setRemappingDelegate:nil];
}

- (void)requestAccessibilityPermission {
    DLog(@"Requesting accessibility permission");
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *options = @{ (NSString *)kAXTrustedCheckOptionPrompt: @YES };
        // Show a dialog prompting the user to open system prefs.
        if (!AXIsProcessTrustedWithOptions((CFDictionaryRef)options)) {
            return;
        }
    });
}

- (NSString *)accessibilityMessageForModifier {
  return @"You have chosen to remap certain modifier keys. For this to work for all key "
         @"combinations (such as cmd-tab), you must turn on \"access for assistive devices\" "
         @"in the Universal Access preferences panel in System Preferences and restart iTerm2.";
}

- (NSString *)accessibilityActionMessage {
  return @"Open System Preferences";
}

#pragma mark - iTermEventTapRemappingDelegate

- (CGEventRef)remappedEventFromEventTappedWithType:(CGEventType)type event:(CGEventRef)event {
    DLog(@"Modifier remapper got an event");
    if ([NSApp isActive]) {
        DLog(@"App is active, performing remapping");
        // Remap modifier keys only while iTerm2 is active; otherwise you could just use the
        // OS's remap feature.
        return [self eventByRemappingEvent:event];
    } else {
        DLog(@"iTerm2 not active. The active app is %@", [[NSWorkspace sharedWorkspace] activeApplication]);
        return event;
    }
}

// Only called when the app is active.
- (CGEventRef)eventByRemappingEvent:(CGEventRef)event {
    NSEvent *cocoaEvent = [NSEvent eventWithCGEvent:event];
    DLog(@"Remapping event %@", cocoaEvent);
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
        return nil;
    }

    switch ([self boundActionForEvent:cocoaEvent]) {
        case KEY_ACTION_REMAP_LOCALLY:
            DLog(@"Calling sendEvent:");
            [iTermKeyBindingMgr remapModifiersInCGEvent:event];
            [NSApp sendEvent:[NSEvent eventWithCGEvent:event]];
            return nil;

        case KEY_ACTION_DO_NOT_REMAP_MODIFIERS:
            DLog(@"Action is do not remap");
            return event;

        default:
            DLog(@"Remapping as usual");
            [iTermKeyBindingMgr remapModifiersInCGEvent:event];
            return event;
    }
}

- (int)boundActionForEvent:(NSEvent *)cocoaEvent {
    if (cocoaEvent.type == NSFlagsChanged) {
        return -1;
    }
    NSString* unmodkeystr = [cocoaEvent charactersIgnoringModifiers];
    unichar unmodunicode = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
    unsigned int modflag = [cocoaEvent modifierFlags];
    NSString *keyBindingText;

    const int boundAction = [iTermKeyBindingMgr actionForKeyCode:unmodunicode
                                                       modifiers:modflag
                                                            text:&keyBindingText
                                                     keyMappings:nil];
    return boundAction;
}

@end
