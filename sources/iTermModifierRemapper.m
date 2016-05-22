#import <Cocoa/Cocoa.h>

#import "iTermModifierRemapper.h"

#import "iTermApplicationDelegate.h"
#import "iTermHotKeyController.h"
#import "iTermKeyBindingMgr.h"
#import "iTermEventTap.h"
#import "iTermShortcutInputView.h"
#import "iTermSystemVersion.h"

@interface iTermModifierRemapper()<iTermEventTapDelegate>
@end

@implementation iTermModifierRemapper

+ (instancetype)sharedInstance {
  static dispatch_once_t onceToken;
  static id instance;
  dispatch_once(&onceToken, ^{
      instance = [[self alloc] init];
  });
  return instance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
      [[iTermEventTap sharedInstance] setDelegate:self];
  }
  return self;
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
  return [[iTermEventTap sharedInstance] isEnabled];
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

- (void)beginRemappingModifiers {
  [[iTermEventTap sharedInstance] setEnabled:YES];

  if (![[iTermEventTap sharedInstance] isEnabled]) {
      if (IsMavericksOrLater()) {
          [self requestAccessibilityPermissionMavericks];
          return;
      }
      switch (NSRunAlertPanel(@"Could not remap modifiers",
                              @"%@",
                              @"OK",
                              [self accessibilityActionMessage],
                              nil,
                              [self accessibilityMessageForModifier])) {
          case NSAlertAlternateReturn:
              [self navigateToAccessibilityPreferencesPanePreMavericks];
              break;
      }
  }
}

- (void)stopRemappingModifiers {
  [[iTermEventTap sharedInstance] setEnabled:NO];
}

- (void)navigateToAccessibilityPreferencesPanePreMavericks {
  // NOTE: Pre-Mavericks only.
  [[NSWorkspace sharedWorkspace] openFile:@"/System/Library/PreferencePanes/UniversalAccessPref.prefPane"];
}

- (void)requestAccessibilityPermissionMavericks {
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

#pragma mark - iTermEventTapDelegate

- (CGEventRef)eventTappedWithType:(CGEventType)type event:(CGEventRef)event {
  if (![[[iTermApplication sharedApplication] delegate] workspaceSessionActive]) {
      return event;
  }

  if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
      NSLog(@"Event tap disabled (type is %@)", @(type));
      if ([[iTermEventTap sharedInstance] isEnabled]) {
          NSLog(@"Re-enabling event tap");
          [[iTermEventTap sharedInstance] reEnable];
      }
      return NULL;
  }

  if (![self userIsActive]) {
      // Fast user switching has switched to another user, don't do any remapping.
      DLog(@"** not doing any remapping for event %@", [NSEvent eventWithCGEvent:event]);
      return event;
  }

  if ([NSApp isActive]) {
      // Remap modifier keys only while iTerm2 is active; otherwise you could just use the
      // OS's remap feature.
      return [self eventByRemappingEvent:event];
  } else {
      return event;
  }
}

// Indicates if the user at the keyboard is the same user that owns this process. Used to avoid
// remapping keys when the user has switched users with fast user switching.
- (BOOL)userIsActive {
  CFDictionaryRef sessionInfoDict;

  sessionInfoDict = CGSessionCopyCurrentDictionary();
  if (sessionInfoDict) {
      NSNumber *userIsActiveNumber = CFDictionaryGetValue(sessionInfoDict,
                                                          kCGSessionOnConsoleKey);
      if (!userIsActiveNumber) {
          CFRelease(sessionInfoDict);
          return YES;
      } else {
          BOOL value = [userIsActiveNumber boolValue];
          CFRelease(sessionInfoDict);
          return value;
      }
  }
  return YES;
}

// Only called when the app is active.
- (CGEventRef)eventByRemappingEvent:(CGEventRef)event {
  NSEvent *cocoaEvent = [NSEvent eventWithCGEvent:event];
  iTermShortcutInputView *shortcutView = [iTermShortcutInputView firstResponder];

  if (shortcutView.disableKeyRemapping) {
      // Send keystroke directly to preference panel when setting do-not-remap for a key; for
      // system keys, NSApp sendEvent: is never called so this is the last chance.
      [shortcutView handleShortcutEvent:cocoaEvent];
      return nil;
  }

  switch ([self boundActionForEvent:cocoaEvent]) {
      case KEY_ACTION_REMAP_LOCALLY:
          [iTermKeyBindingMgr remapModifiersInCGEvent:event];
          [NSApp sendEvent:[NSEvent eventWithCGEvent:event]];
          return nil;

      case KEY_ACTION_DO_NOT_REMAP_MODIFIERS:
          return event;

      default:
          [iTermKeyBindingMgr remapModifiersInCGEvent:event];
          return event;
  }
}

- (int)boundActionForEvent:(NSEvent *)cocoaEvent {
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
