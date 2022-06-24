#import <Foundation/Foundation.h>

#import "iTermPreferences.h"

@class iTermEventTap;

// A simple interface to modifier remapping-related stuff.
@interface iTermModifierRemapper : NSObject

// These are convenience methods for looking up the preferences setting for
// what each modifier ought to do.
@property(nonatomic, readonly) iTermPreferencesModifierTag controlRemapping;
@property(nonatomic, readonly) iTermPreferencesModifierTag leftOptionRemapping;
@property(nonatomic, readonly) iTermPreferencesModifierTag rightOptionRemapping;
@property(nonatomic, readonly) iTermPreferencesModifierTag leftCommandRemapping;
@property(nonatomic, readonly) iTermPreferencesModifierTag rightCommandRemapping;

// Is any modifier set in prefs to do something other than its un-remapped behavior?
@property(nonatomic, readonly) BOOL isAnyModifierRemapped;

// Assign to start or stop remapping. The getter indicates if the event tap is
// on (even if self.isAnyModifierRemapped is NO).
@property(nonatomic, getter=isRemappingModifiers) BOOL remapModifiers;

+ (NSEvent *)remapModifiers:(NSEvent *)event;

+ (instancetype)sharedInstance;
- (instancetype)init NS_UNAVAILABLE;

- (CGEventRef)eventByRemappingEvent:(CGEventRef)event
                           eventTap:(iTermEventTap *)eventTap;

@end
