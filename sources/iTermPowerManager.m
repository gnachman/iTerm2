//
//  iTermPowerManager.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/21/18.
//

#import "iTermPowerManager.h"

#import "iTermPreferences.h"
#import "iTermPublisher.h"
#import "NSArray+iTerm.h"
#import "NSTimer+iTerm.h"

#import <IOKit/ps/IOPowerSources.h>

NSString *const iTermPowerManagerStateDidChange = @"iTermPowerManagerStateDidChange";
NSString *const iTermPowerManagerMetalAllowedDidChangeNotification = @"iTermPowerManagerMetalAllowedDidChangeNotification";

@interface iTermPowerState()
@property (nonatomic, copy, readwrite) NSString *powerStatus;
@property (nonatomic, strong, readwrite) NSNumber *percentage;
@property (nonatomic, strong, readwrite) NSNumber *time;
@property (nonatomic, readwrite) BOOL charging;
@end

//#define ENABLE_FAKE_BATTERY 1
#if ENABLE_FAKE_BATTERY
#warning do not submit
#endif

@implementation iTermPowerState
@end

@interface iTermPowerManager()<iTermPublisherDelegate>
@end

@implementation iTermPowerManager {
    CFRunLoopRef _runLoop;
    CFRunLoopSourceRef _runLoopSource;
    BOOL _metalAllowed;
    iTermPublisher<iTermPowerState *> *_publisher;
    NSTimer *_timer;
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
        _publisher = [[iTermPublisher alloc] initWithCapacity:120];
        _publisher.delegate = self;
        [self metalAllowed];
    }
    return self;
}

- (void)setConnected:(BOOL)connected {
    if (_connectedToPower != connected) {
        _connectedToPower = connected;
        const BOOL metalWasAllowed = _metalAllowed;
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermPowerManagerStateDidChange object:nil];
        if (metalWasAllowed && !self.metalAllowed) {
            // metal allowed just became false
            [[NSNotificationCenter defaultCenter] postNotificationName:iTermPowerManagerMetalAllowedDidChangeNotification object:@(_metalAllowed)];
        }
    }
}

- (BOOL)metalAllowed {
    const BOOL connectedToPower = [self connectedToPower];
    const BOOL connectionToPowerRequired = [iTermPreferences boolForKey:kPreferenceKeyDisableMetalWhenUnplugged];
    _metalAllowed = (!connectionToPowerRequired || connectedToPower);
    return _metalAllowed;
}

#if ENABLE_FAKE_BATTERY
- (iTermPowerState *)computedPowerState {
    static int level;
    int d;
    if (level < 2) {
        d = 2;
        level = 0;
    } else if (level == 100) {
        level = 101;
        d = -2;
    } else if (level % 2) {  // odd
        d = -2;
    } else {  // event
        d = 2;
    }
    level += d;

    iTermPowerState *state = [[iTermPowerState alloc] init];
    state.powerStatus = @"Fake";
    state.percentage = @(level);
    state.time = @60;

    return state;
}
#else
- (iTermPowerState *)computedPowerState {
    CFTypeRef powerSourcesInfo = IOPSCopyPowerSourcesInfo();
    CFArrayRef powerSourcesList = IOPSCopyPowerSourcesList(powerSourcesInfo);

    iTermPowerState *result = [self computedPowerStateWithList:powerSourcesList
                                                          info:powerSourcesInfo];

    if (powerSourcesList) {
        CFRelease(powerSourcesList);
    }
    if (powerSourcesInfo) {
        CFRelease(powerSourcesInfo);
    }

    return result;
}

- (iTermPowerState *)computedPowerStateWithList:(CFArrayRef)powerSourcesList
                                           info:(CFTypeRef)powerSourcesInfo {
    CFDictionaryRef info;
    if (powerSourcesList && CFArrayGetCount(powerSourcesList)) {
        info = IOPSGetPowerSourceDescription(powerSourcesInfo, CFArrayGetValueAtIndex(powerSourcesList, 0));
    } else {
        return nil;
    }
    CFNumberRef number;

    number = (CFNumberRef)CFDictionaryGetValue(info, CFSTR(kIOPSCurrentCapacityKey));
    int percentage = -1;
    CFNumberGetValue(number, kCFNumberIntType, &percentage);

    iTermPowerState *state = [[iTermPowerState alloc] init];
    if ((CFBooleanRef)CFDictionaryGetValue(info, CFSTR(kIOPSIsChargingKey)) == kCFBooleanTrue) {
        state.charging = YES;
        number = (CFNumberRef)CFDictionaryGetValue(info, CFSTR(kIOPSTimeToFullChargeKey));
    } else {
        state.charging = NO;
        number = (CFNumberRef)CFDictionaryGetValue(info, CFSTR(kIOPSTimeToEmptyKey));
    }
    int time = -1;
    CFNumberGetValue(number, kCFNumberIntType, &time);

    state.powerStatus = (__bridge NSString *)CFDictionaryGetValue(info, CFSTR(kIOPSPowerSourceStateKey));
    state.percentage = @(percentage);
    state.time = @(time >= 0 ? time * 60 : -1);

    return state;
}
#endif

- (void)updateBatteryState {
    iTermPowerState *state = [self computedPowerState];
    if (state) {
        [_publisher publish:state];
    } else {
        _hasBattery = NO;
    }
}

- (void)addPowerStateSubscriber:(id)subscriber block:(void (^)(iTermPowerState *))block {
    [_publisher addSubscriber:subscriber block:^(iTermPowerState * _Nonnull payload) {
        block(payload);
    }];
    iTermPowerState *state = _publisher.historicalValues.lastObject;
    if (state != nil) {
        block(state);
    } else {
        [self updateBatteryState];
    }
}

- (NSArray<NSNumber *> *)percentageSamples {
    return [_publisher.historicalValues mapWithBlock:^id(iTermPowerState *state) {
        return state.percentage;
    }];
}

- (iTermPowerState *)currentState {
    return _publisher.historicalValues.lastObject;
}

#pragma mark - iTermPublisherDelegate

- (void)publisherDidChangeNumberOfSubscribers:(iTermPublisher *)publisher {
    if (!_publisher.hasAnySubscribers) {
        [_timer invalidate];
        _timer = nil;
    } else if (!_timer) {
        [self updateBatteryState];
#if ENABLE_FAKE_BATTERY
        NSTimeInterval interval = 1;
#else
        NSTimeInterval interval = 60;
#endif
        _timer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                  target:self
                                                selector:@selector(updateBatteryState)
                                                userInfo:nil
                                                 repeats:YES];
    }
}

@end
