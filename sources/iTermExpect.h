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
// iTermExpect *e = [[iTermExpect alloc] initDry:YES];
// iTermExpectation *x1 = [e expectRegularExpression:@"…" after:nil deadline:nil willExpect:…  completion:…];
// iTermExpectation *x2 = [e expectRegularExpression:@"…" after:x1 deadline:nil willExpect:… completion:…];
//
// /* Time to sync with mutation thread. This happens in a mutex so neither `e` nor a pre-existing
//    `_mutableState.expect` gets modified during -copy. */
// _mutableState.expect = [e copy];
//
// /* Mutation thread */
// [_mutableState.expect.expectations.firstObject didMatchWithCaptureGroups:…];
// // The willExpect callback is dispatched to run later on the main thread.
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

// Becomes true when expectRegularExpression or cancelExpectation is called. Becomes false when resetDirty is called.
@property (nonatomic, readonly) BOOL dirty;

// The main thread instance is "dry" - you add and cancel expectations on it, but its expectations
// are never notified of matches directly. Instead it is copied from to a "wet" instance whose
// expectations get didMatchWithCaptureGroups called.
@property (nonatomic, readonly) BOOL dry;

// This might lie and say YES if all the expectations have been dealloced.
@property (nonatomic, readonly) BOOL maybeHasExpectations;
@property (nonatomic, readonly) BOOL expectationsIsEmpty;

// Dry means that it accepts mutations (add expectation, cancel expectation, reset dirty) but matching
// will never happen on this object - only on its copies. The main effect is that willExpect: calls
// are deferred until the next copy.
- (instancetype)initDry:(BOOL)dry NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Causes `dirty` to become YES.
- (iTermExpectation *)expectRegularExpression:(NSString *)regex
                                        after:(nullable iTermExpectation *)precedecessor
                                     deadline:(nullable NSDate *)deadline
                                   willExpect:(void (^ _Nullable)(void))willExpect
                                   completion:(void (^ _Nullable)(NSArray<NSString *> *captureGroups))completion;

// This may only be called on the main thread. The mutation thread cannot cancel expectations
// without creating races.
// Causes `dirty` to become YES.
- (void)cancelExpectation:(iTermExpectation *)expectation;

// Cause `dirty` to become NO.
- (void)resetDirty;

@end

NS_ASSUME_NONNULL_END
