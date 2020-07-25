//
//  iTermSecureKeyboardEntryController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 02/05/19.
//

#import "iTermSecureKeyboardEntryController.h"

#import "DebugLogging.h"
#import "iTermUserDefaults.h"

#import <Carbon/Carbon.h>

NSString *const iTermDidToggleSecureInputNotification = @"iTermDidToggleSecureInputNotification";

@implementation iTermSecureKeyboardEntryController {
    int _count;
    BOOL _focusStolen;
    BOOL _enabledByUserDefault;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _enabledByUserDefault = iTermUserDefaults.secureKeyboardEntry;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidResignActive:)
                                                     name:NSApplicationDidResignActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
        if ([NSApp isActive]) {
            [self update];
        }
    }
    return self;
}

#pragma mark - API

- (void)toggle {
    // Set _desired to the opposite of the current state.
    _enabledByUserDefault = !_enabledByUserDefault;
    DLog(@"toggle called. Setting desired to %@", @(_enabledByUserDefault));

    // Try to set the system's state of secure input to the desired state.
    [self update];

    // Save the preference, independent of whether it succeeded or not.
    iTermUserDefaults.secureKeyboardEntry = _enabledByUserDefault;
}

- (void)didStealFocus {
    _focusStolen = YES;
    [self update];
}

- (void)didReleaseFocus {
    _focusStolen = NO;
    [self update];
}

- (BOOL)isEnabled {
    return !!IsSecureEventInputEnabled();
}

- (void)setDesired:(BOOL)desired {
    _enabledByUserDefault = desired;
}

- (BOOL)isDesired {
    return _enabledByUserDefault || [self currentSessionAtPasswordPrompt];
}

#pragma mark - Notifications

- (void)applicationDidResignActive:(NSNotification *)notification {
    if (_count > 0) {
        DLog(@"Application resigning active.");
        [self update];
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    if (self.isDesired) {
        DLog(@"Application became active.");
        [self update];
    }
}

#pragma mark - Private

- (BOOL)currentSessionAtPasswordPrompt {
    NSResponder *firstResponder = [[NSApp keyWindow] firstResponder];
    if (![firstResponder conformsToProtocol:@protocol(iTermSecureInputRequesting)]) {
        return NO;
    }
    id<iTermSecureInputRequesting> requesting = (id<iTermSecureInputRequesting>)firstResponder;
    const BOOL result = [requesting isRequestingSecureInput];
    DLog(@"Current session at password prompt=%@", @(result));
    return result;
}

- (BOOL)allowed {
    if ([NSApp isActive]) {
        return YES;
    }
    return _focusStolen;
}

- (void)update {
    DLog(@"Update secure keyboard entry. desired=%@ active=%@ focusStolen=%@",
         @(self.isDesired), @([NSApp isActive]), @(_focusStolen));
    const BOOL secure = self.isDesired && [self allowed];

    if (secure && _count > 0) {
        DLog(@"Want to turn on secure input but it's already on");
        return;
    }

    if (!secure && _count == 0) {
        DLog(@"Want to turn off secure input but it's already off");
        return;
    }

    DLog(@"Before: IsSecureEventInputEnabled returns %d", (int)self.isEnabled);
    if (secure) {
        OSErr err = EnableSecureEventInput();
        DLog(@"EnableSecureEventInput err=%d", (int)err);
        if (err) {
            XLog(@"EnableSecureEventInput failed with error %d", (int)err);
        } else {
            _count += 1;
        }
    } else {
        OSErr err = DisableSecureEventInput();
        DLog(@"DisableSecureEventInput err=%d", (int)err);
        if (err) {
            XLog(@"DisableSecureEventInput failed with error %d", (int)err);
        } else {
            _count -= 1;
        }
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermDidToggleSecureInputNotification object:nil];
    DLog(@"After: IsSecureEventInputEnabled returns %d", (int)self.isEnabled);
}

@end
