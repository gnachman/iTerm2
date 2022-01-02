//
//  iTermExpect.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/21/19.
//

#import <Foundation/Foundation.h>

// Usage;
//
// /* Main thread */
// iTermExpect *e = [[iTermExpect alloc] init];
// iTermExpectation *x1 = [e expectRegularExpression:@"…" after:nil deadline:nil willExpect:…  completion:…];
// iTermExpectation *x2 = [e expectRegularExpression:@"…" after:x1 deadline:nil willExpect:… completion:…];
//
// /* Time to sync with mutation thread. This happens in a mutex so neither `e` nor a pre-existing
//    `_mutableState.expect` gets modified during -copy. */
// _mutableState.expect = [e copy];
//
// /* Mutation thread */
// [_mutableState.expect.expectations.firstObject didMatchWithCaptureGroups:…];
//
// /* This is allowed concurrently on the main thread */
// [e cancelExpectation:x1];
// iTermExpectation *x3 = [e expectRegularExpression:@"…" after:nil deadline:nil willExpect:… completion:…];


NS_ASSUME_NONNULL_BEGIN

@interface iTermExpectation: NSObject
@property (nonatomic, readonly) NSString *regex;
@property (nonatomic, readonly) BOOL hasCompleted;
@property (nullable, nonatomic, strong, readonly) iTermExpectation *successor;
@property (nonatomic, readonly) iTermExpectation *lastExpectation;  // self or successor
@property (nullable, nonatomic, readonly) NSDate *deadline;

// This is to be called on the mutation thread.
- (void)didMatchWithCaptureGroups:(NSArray<NSString *> *)captureGroups;

@end

@interface iTermExpect : NSObject<NSCopying>
@property (nonatomic, readonly) NSArray<iTermExpectation *> *expectations;

- (iTermExpectation *)expectRegularExpression:(NSString *)regex
                                        after:(nullable iTermExpectation *)precedecessor
                                     deadline:(nullable NSDate *)deadline
                                   willExpect:(void (^ _Nullable)(void))willExpect
                                   completion:(void (^ _Nullable)(NSArray<NSString *> *captureGroups))completion;

// This may only be called on the main thread. The mutation thread cannot cancel expectations without creating races.
- (void)cancelExpectation:(iTermExpectation *)expectation;

@end

NS_ASSUME_NONNULL_END
