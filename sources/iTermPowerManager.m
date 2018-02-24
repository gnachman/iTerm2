//
//  iTermPowerManager.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/21/18.
//

#import "iTermPowerManager.h"
#import "NSTimer+iTerm.h"
#import <IOKit/ps/IOPowerSources.h>

NSString *const iTermPowerManagerStateDidChange = @"iTermPowerManagerStateDidChange";

@implementation iTermPowerManager

+ (instancetype)sharedInstance {
    return [[self alloc] initPrivate];
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        [self updateCharging];
        [NSTimer it_scheduledTimerWithTimeInterval:5 repeats:YES block:^(NSTimer * _Nonnull timer) {
            BOOL before = _connectedToPower;
            [self updateCharging];
            if (_connectedToPower != before) {
                [[NSNotificationCenter defaultCenter] postNotificationName:iTermPowerManagerStateDidChange object:nil];
            }
        }];
    }
    return self;
}

- (void)updateCharging {
    _connectedToPower = (IOPSGetTimeRemainingEstimate() == kIOPSTimeRemainingUnlimited);
}

@end
