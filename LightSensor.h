//
//  LightSensor.h
//  iTerm
//
//  Created by George Nachman on 4/10/13.
//
//

#import <Foundation/Foundation.h>
#include <IOKit/IOKitLib.h>
#import <Foundation/Foundation.h>

@class LightSensor;

@protocol LightSensorTarget <NSObject>
- (void)lightSensorMeasuredDarkness:(LightSensor *)lightSensor;
- (void)lightSensorMeasuredLightness:(LightSensor *)lightSensor;
@end

@interface LightSensor : NSObject {
    io_connect_t connection_;
    NSTimer *timer_;  // weak
    int64_t darkTriggerLevel_;
    int64_t lightTriggerLevel_;
    id<LightSensorTarget> target_;  // weak
    enum {
        LightSensorStateLight,
        LightSensorStateDark
    } state_;
}

- (void)startMonitoringWithDarkTriggerLevel:(int64_t)darkTriggerLevel
                          lightTriggerLevel:(int64_t)lightTriggerLevel
                                     target:(id<LightSensorTarget>)target;

- (void)stopMonitoring;

- (int64_t)brightness;

@end
