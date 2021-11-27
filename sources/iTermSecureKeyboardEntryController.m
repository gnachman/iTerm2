//
//  iTermSecureKeyboardEntryController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 02/05/19.
//

#import "iTermSecureKeyboardEntryController.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermUserDefaults.h"

#import <Carbon/Carbon.h>

NSString *const iTermDidToggleSecureInputNotification = @"iTermDidToggleSecureInputNotification";

@interface iTermSecureKeyboardEntryController()
@property (nonatomic) BOOL temporarilyDisabled;
@end

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

- (void)disableTemporarily {
    if (_temporarilyDisabled) {
        DLog(@"already temporarily disabled");
        return;
    }
    if (!self.isDesired) {
        DLog(@"not desired");
        return;
    }
    DLog(@"set timer");
    self.temporarilyDisabled = YES;
    const NSTimeInterval duration = 0.1;
    __weak __typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf reenable];
    });
}

- (void)keyDown {
    DLog(@"keyDown");
    [self reenable];
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

- (void)reenable {
    DLog(@"reenable");
    self.temporarilyDisabled = NO;
}

- (void)setTemporarilyDisabled:(BOOL)temporarilyDisabled {
    DLog(@"%@", @(temporarilyDisabled));
    if (temporarilyDisabled == _temporarilyDisabled) {
        DLog(@"Not changing");
        return;
    }
    if (temporarilyDisabled && ![iTermAdvancedSettingsModel temporarilyDisableSecureKeyboardEntry]) {
        DLog(@"Advanced setting off");
        return;
    }
    _temporarilyDisabled = temporarilyDisabled;
    [self update];
}

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
    if (_temporarilyDisabled && [self currentSessionAtPasswordPrompt]) {
        DLog(@"At password prompt: remove temporary disablement");
        _temporarilyDisabled = NO;
    }
    const BOOL secure = self.isDesired && [self allowed] && !_temporarilyDisabled;

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
        NSLog(@"EnableSecureEventInput err=%d", (int)err);
        if (err) {
            XLog(@"EnableSecureEventInput failed with error %d", (int)err);
        } else {
            _count += 1;
        }
    } else {
        OSErr err = DisableSecureEventInput();
        NSLog(@"DisableSecureEventInput err=%d", (int)err);
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
