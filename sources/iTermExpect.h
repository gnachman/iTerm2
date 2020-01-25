//
//  iTermExpect.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/21/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermExpectation: NSObject
@property (nonatomic, readonly) NSString *regex;
@property (nonatomic, readonly) BOOL hasCompleted;
@property (nullable, nonatomic, strong, readonly) iTermExpectation *successor;
@property (nonatomic, readonly) iTermExpectation *lastExpectation;  // self or successor

- (void)didMatchWithCaptureGroups:(NSArray<NSString *> *)captureGroups;

@end

@interface iTermExpect : NSObject
@property (nonatomic, readonly) NSArray<iTermExpectation *> *expectations;

- (iTermExpectation *)expectRegularExpression:(NSString *)regex
                                        after:(nullable iTermExpectation *)precedecessor
                                   willExpect:(void (^ _Nullable)(void))willExpect
                                   completion:(void (^ _Nullable)(NSArray<NSString *> *captureGroups))completion;

- (iTermExpectation *)expectRegularExpression:(NSString *)regex
                                   completion:(void (^)(NSArray<NSString *> *captureGroups))completion;

- (void)cancelExpectation:(iTermExpectation *)expectation;
- (void)setTimeout:(NSTimeInterval)timeout forExpectation:(iTermExpectation *)expectation;

@end

NS_ASSUME_NONNULL_END
