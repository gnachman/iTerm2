#import <Foundation/Foundation.h>

#import "iTermPreferences.h"

@class iTermEventTap;

// A simple interface to modifier remapping-related stuff.
@interface iTermModifierRemapper : NSObject

// These are convenience methods for looking up the preferences setting for
// what each modifier ought to do.
@property(nonatomic, readonly) iTermPreferencesModifierTag leftControlRemapping;
@property(nonatomic, readonly) iTermPreferencesModifierTag rightControlRemapping;
@property(nonatomic, readonly) iTermPreferencesModifierTag leftOptionRemapping;
@property(nonatomic, readonly) iTermPreferencesModifierTag rightOptionRemapping;
@property(nonatomic, readonly) iTermPreferencesModifierTag leftCommandRemapping;
@property(nonatomic, readonly) iTermPreferencesModifierTag rightCommandRemapping;
@property(nonatomic, readonly) iTermPreferencesModifierTag functionRemapping;

// Is any modifier set in prefs to do something other than its un-remapped behavior?
@property(nonatomic, readonly) BOOL isAnyModifierRemapped;

// Whether the physical Fn key is currently held down. Updated by the event tap,
// or by iTermApplication for the application-level remapping path.
// Atomic because it is written from the event tap thread and read from the main thread.
@property(atomic) BOOL physicalFnKeyDown;

// Assign to start or stop remapping. The event taps are only installed while iTerm2 is active,
// since remapping only applies then and a filtering tap delays keystrokes in every app. The getter
// indicates if the event tap is on (even if self.isAnyModifierRemapped is NO).
@property(nonatomic, getter=isRemappingModifiers) BOOL remapModifiers;

// Exposed for testing.
+ (BOOL)shouldInstallEventTapsWhenWantingRemapping:(BOOL)wantsRemapping appActive:(BOOL)appActive;

// Exposed for testing. The new install time after a begin or stop.
+ (NSTimeInterval)tapsInstalledTimeAfterPreviousTime:(NSTimeInterval)previous
                                        wasRemapping:(BOOL)wasRemapping
                                         isRemapping:(BOOL)isRemapping
                                                 now:(NSTimeInterval)now;

// Exposed for testing. See -eventTapMissedEvent:.
+ (BOOL)eventTapMissedEventWithTimestamp:(NSTimeInterval)timestamp
                       tapsInstalledTime:(NSTimeInterval)tapsInstalledTime
                            handledByTap:(BOOL)handledByTap;

// Whether the event got to the app without passing through the remapping taps because it reached
// the system before they were installed (they're installed on activation). The app must remap it
// itself. Events after installation that skipped the taps were synthesized past them and are not
// remapped, as before the taps depended on activation.
- (BOOL)eventTapMissedEvent:(NSEvent *)event;

+ (NSEvent *)remapModifiers:(NSEvent *)event;

+ (instancetype)sharedInstance;
- (instancetype)init NS_UNAVAILABLE;

- (CGEventRef)eventByRemappingEvent:(CGEventRef)event
                           eventTap:(iTermEventTap *)eventTap;

@end
