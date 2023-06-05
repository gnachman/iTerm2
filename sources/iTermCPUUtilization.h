//
//  iTermCPUUtilization.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/19/18.
//

#import <Foundation/Foundation.h>
#import "iTermPublisher.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^iTermCPUUtilizationObserver)(double);

@interface iTermCPUUtilization : NSObject
@property (nonatomic) NSTimeInterval cadence;
@property (nullable, nonatomic, readonly) NSArray<NSNumber *> *samples;
@property (nonatomic, strong) iTermPublisher<NSNumber *> *publisher;

+ (instancetype)instanceForSessionID:(NSString *)sessionID;
+ (void)setInstance:(nullable iTermCPUUtilization *)instance
       forSessionID:(NSString *)sessionID;
- (instancetype)initWithPublisher:(iTermPublisher<NSNumber *> *)publisher;
- (void)addSubscriber:(id)subscriber block:(iTermCPUUtilizationObserver)block;
@end

@interface iTermLocalCPUUtilizationPublisher: iTermPublisher<NSNumber *>
+ (instancetype)sharedInstance;
@end

NS_ASSUME_NONNULL_END
