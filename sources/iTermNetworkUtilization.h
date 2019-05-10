//
//  iTermNetworkUtilization.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/21/18.
//

#import <Foundation/Foundation.h>

@interface iTermNetworkUtilizationSample : NSObject
@property (nonatomic, readonly) double bytesPerSecondRead;
@property (nonatomic, readonly) double bytesPerSecondWrite;
@end

@interface iTermNetworkUtilization : NSObject

@property (nonatomic) NSTimeInterval cadence;
@property (nonatomic, readonly) NSArray<iTermNetworkUtilizationSample *> *samples;

+ (instancetype)sharedInstance;
- (void)addSubscriber:(id)subscriber
                block:(void (^)(double bytesPerSecondRead, double bytesPerSecondWrite))block;

@end
