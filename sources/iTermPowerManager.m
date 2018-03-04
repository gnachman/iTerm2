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

@implementation iTermPowerManager {
    CFRunLoopRef _runLoop;
    CFRunLoopSourceRef _runLoopSource;
}

static BOOL iTermPowerManagerIsConnectedToPower(void) {
    CFStringRef source = IOPSGetProvidingPowerSourceType(NULL);
    return [@kIOPMACPowerKey isEqualToString:(__bridge NSString *)(source)];
}

static void iTermPowerManagerSourceDidChange(void *context) {
    iTermPowerManager* pm = (__bridge iTermPowerManager *)(context);
    [pm setConnected:iTermPowerManagerIsConnectedToPower()];
}

+ (instancetype)sharedInstance {
    static iTermPowerManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] initPrivate];
    });
    return sharedInstance;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _runLoop = CFRunLoopGetMain();
        _runLoopSource = IOPSCreateLimitedPowerNotification(iTermPowerManagerSourceDidChange,
                                                            (__bridge void *)(self));
        _connectedToPower = iTermPowerManagerIsConnectedToPower();
        if (_runLoop && _runLoopSource){
            CFRunLoopAddSource(_runLoop, _runLoopSource, kCFRunLoopDefaultMode);
        }
    }
    return self;
}

- (void)setConnected:(BOOL)connected {
    if (_connectedToPower != connected) {
        _connectedToPower = connected;
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermPowerManagerStateDidChange object:nil];
    }
}

@end
