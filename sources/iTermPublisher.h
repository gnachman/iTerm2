//
//  iTermPublisher.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/20/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermPublisher;

@protocol iTermPublisherDelegate<NSObject>

- (void)publisherDidChangeNumberOfSubscribers:(iTermPublisher *)publisher;

@end

@interface iTermPublisher<PayloadType> : NSObject

@property (nonatomic, weak) id<iTermPublisherDelegate> delegate;
@property (nonatomic, readonly) NSTimeInterval timeIntervalSinceLastUpdate;
@property (nonatomic, readonly) BOOL hasAnySubscribers;
@property (nonatomic, nullable, readonly) NSArray<PayloadType> *historicalValues;

- (instancetype)initWithCapacity:(NSInteger)capacity NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)publish:(PayloadType)payload;

- (void)addSubscriber:(id)subscriber
                block:(void (^)(PayloadType payload))block;

- (void)removeSubscriber:(id)subscriber;

@end

NS_ASSUME_NONNULL_END

