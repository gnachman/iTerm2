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
        _desired = iTermUserDefaults.secureKeyboardEntry;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidResignActive:)
                                                     name:NSApplicationDidResignActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
    }
    return self;
}

#pragma mark - API

- (void)toggle {
    // Set _desired to the opposite of the current state.
    _desired = !_desired;
    DLog(@"toggle called. Setting desired to %@", @(_desired));

    // Try to set the system's state of secure input to the desired state.
    [self update];

    // Save the preference, independent of whether it succeeded or not.
    iTermUserDefaults.secureKeyboardEntry = _desired;
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

#pragma mark - Notifications

- (void)applicationDidResignActive:(NSNotification *)notification {
    if (_desired) {
        DLog(@"Application resigning active.");
        [self update];
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    if (_desired) {
        DLog(@"Application became active.");
        [self update];
    }
}

#pragma mark - Private

- (BOOL)allowed {
    if ([NSApp isActive]) {
        return YES;
    }
    return _focusStolen;
}

- (void)update {
    DLog(@"Update secure keyboard entry. desired=%@ active=%@ focusStolen=%@",
         @(_desired), @([NSApp isActive]), @(_focusStolen));
    const BOOL secure = _desired && [self allowed];

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
