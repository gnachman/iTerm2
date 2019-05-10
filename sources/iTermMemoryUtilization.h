//
//  iTermMemoryUtilization.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/21/18.
//

#import <Foundation/Foundation.h>

@interface iTermMemoryUtilization : NSObject

@property (nonatomic) NSTimeInterval cadence;
@property (nonatomic, readonly) long long availableMemory;
@property (nonatomic, readonly) NSArray<NSNumber *> *samples;

+ (instancetype)sharedInstance;
- (void)addSubscriber:(id)subscriber
                block:(void (^)(double))block;

@end
