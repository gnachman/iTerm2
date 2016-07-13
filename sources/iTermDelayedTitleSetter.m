//
//  iTermDelayedTitleSetter.m
//  iTerm2
//
//  Created by George Nachman on 11/15/15.
//
//

#import "iTermDelayedTitleSetter.h"
#import "DebugLogging.h"

NSString *const kDelayedTitleSetterSetTitle = @"kDelayedTitleSetterSetTitle";
NSString *const kDelayedTitleSetterTitleKey = @"title";

static NSString * const kDelayedTitleSetterCustomDelayKey = @"DelayedTitleCustomDelayTimeInterval";

static const NSTimeInterval kDelay = 0.1;

static const char * kDelayedTitleSetterNSTimeIntervalObjCType = @encode(NSTimeInterval);

static const char * kDelayedTitleSetterFloatObjCType = @encode(float);

@interface iTermDelayedTitleSetter()
@property(nonatomic, assign) NSTimer *timer;
@property(nonatomic, copy) NSString *pendingTitle;
@end

@implementation iTermDelayedTitleSetter

+ (void) initialize {
    [super initialize];
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{ kDelayedTitleSetterCustomDelayKey : @(kDelay) }];
}

- (void)dealloc {
    [_pendingTitle release];
    [super dealloc];
}

- (NSTimeInterval) titleDelayDuration {
    NSNumber *titleDelayDurationNumber = [[NSUserDefaults standardUserDefaults] objectForKey:kDelayedTitleSetterCustomDelayKey];

    if (![titleDelayDurationNumber isKindOfClass:[NSNumber class]]) {
        // Validate the duration, if it's not a number remove it.

        DLog(@"duration isn't a number! (%@) %@", NSStringFromClass([titleDelayDurationNumber class]), titleDelayDurationNumber);

        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDelayedTitleSetterCustomDelayKey];

        [[NSUserDefaults standardUserDefaults] synchronize];

        titleDelayDurationNumber = @(kDelay);
    } else {
        const char *titleDelayDurationObjCType = [titleDelayDurationNumber objCType];

        if (strcmp(titleDelayDurationObjCType, kDelayedTitleSetterNSTimeIntervalObjCType) != 0) {
            if (strcmp(titleDelayDurationObjCType, kDelayedTitleSetterFloatObjCType) != 0) {
                DLog(@"types not equal: ori: %s saved: %s", kDelayedTitleSetterNSTimeIntervalObjCType, titleDelayDurationObjCType);

                titleDelayDurationNumber = @(kDelay);
            }
        }
    }

    NSTimeInterval titleDelayDuration = [titleDelayDurationNumber doubleValue];

    if (titleDelayDuration < 0) {
        titleDelayDuration = kDelay;

        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDelayedTitleSetterCustomDelayKey];

        [[NSUserDefaults standardUserDefaults] synchronize];
    }

    return titleDelayDuration;
}

- (void)setTitle:(NSString *)title {
    self.pendingTitle = title;

    NSTimeInterval timerDelay = [self titleDelayDuration];

    if (timerDelay > 0) {
        if (!self.timer) {
            self.timer = [NSTimer scheduledTimerWithTimeInterval:[self titleDelayDuration]
                                                          target:self
                                                        selector:@selector(timerDidFire:)
                                                        userInfo:nil
                                                         repeats:NO];
        }
    } else {
        [self timerDidFire:nil];
    }
}

- (void)timerDidFire:(NSTimer *)timer {
    self.timer = nil;
    NSString *newTitle = [[self.pendingTitle retain] autorelease];
    self.pendingTitle = nil;
    if (newTitle) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kDelayedTitleSetterSetTitle
                                                            object:self.window
                                                          userInfo:@{ kDelayedTitleSetterTitleKey: newTitle }];
    }
}

@end
