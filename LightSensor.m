//
//  LightSensor.m
//  iTerm
//
//  Created by George Nachman on 4/10/13.
//
//

#import "LightSensor.h"
#import <mach/mach.h>
#import <CoreFoundation/CoreFoundation.h>

static NSString * const kLightSensorServiceName = @"AppleLMUController";

@implementation LightSensor

+ (io_service_t)ioServiceWithName:(NSString *)serviceName {
    return IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching([serviceName UTF8String]));
}

- (id)init {
    self = [super init];
    if (self) {
        io_service_t ioService;

        BOOL ok = NO;
        ioService = [[self class] ioServiceWithName:kLightSensorServiceName];
        if (ioService) {
            kern_return_t status = IOServiceOpen(ioService, mach_task_self(), 0, &connection_);
            if (status == KERN_SUCCESS) {
                ok = YES;
            }
            IOObjectRelease(ioService);
        }
        if (!ok) {
            [self autorelease];
            return nil;
        }
    }
    return self;
}

- (void)notifyTargetOfChange {
    switch (state_) {
        case LightSensorStateLight:
            [target_ lightSensorMeasuredLightness:self];
            break;
            
        case LightSensorStateDark:
            [target_ lightSensorMeasuredDarkness:self];
            break;
    }
}

- (void)_update:(NSTimer *)timer {
    int64_t brightness = [self brightness];
    NSLog(@"Brightness is %lld", brightness);
    if (brightness > lightTriggerLevel_ && state_ == LightSensorStateDark) {
        state_ = LightSensorStateLight;
        [self notifyTargetOfChange];
    } else if (brightness < darkTriggerLevel_ && state_ == LightSensorStateLight) {
        state_ = LightSensorStateDark;
        [self notifyTargetOfChange];
    }
}


- (void)startMonitoringWithDarkTriggerLevel:(int64_t)darkTriggerLevel
                          lightTriggerLevel:(int64_t)lightTriggerLevel
                                     target:(id<LightSensorTarget>)target {
    darkTriggerLevel_ = darkTriggerLevel;
    lightTriggerLevel_ = lightTriggerLevel;
    if ([self brightness] > (darkTriggerLevel_ + lightTriggerLevel_) / 2) {
        state_ = LightSensorStateLight;
    } else {
        state_ = LightSensorStateDark;
    }
    target_ = target;
    
    [timer_ invalidate];
    timer_ = [NSTimer scheduledTimerWithTimeInterval:2
                                              target:self
                                            selector:@selector(_update:)
                                            userInfo:nil
                                             repeats:YES];
    [self notifyTargetOfChange];
}

- (void)stopMonitoring {
    [timer_ invalidate];
    timer_ = nil;
    target_ = nil;
}

- (int64_t)brightness {
    uint32_t outputs = 2;
    uint64_t values[outputs];
    
    kern_return_t status = IOConnectCallMethod(connection_, 0, nil, 0, nil, 0, values, &outputs, nil, 0);
    if (status == KERN_SUCCESS) {
        return values[0] / 2 + values[1] / 2;
    } else {
        return -1;
    }
}

@end
