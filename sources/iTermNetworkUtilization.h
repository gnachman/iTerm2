//
//  iTermNetworkUtilization.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/21/18.
//

#import <Foundation/Foundation.h>

@interface iTermNetworkUtilization : NSObject

@property (nonatomic) NSTimeInterval cadence;

+ (instancetype)sharedInstance;
- (void)addSubscriber:(id)subscriber
                block:(void (^)(double bytesPerSecondRead, double bytesPerSecondWrite))block;

@end
