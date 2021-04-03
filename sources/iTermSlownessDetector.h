//
//  iTermSlownessDetector.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/3/21.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Measures the amount of time spent handling different events, as well as the time outside
// event processing.
@interface iTermSlownessDetector : NSObject
@property (nonatomic, readonly) NSTimeInterval timeSinceReset;
@property (nonatomic) BOOL enabled;

- (void)measureEvent:(NSString *)event block:(void (^ NS_NOESCAPE)(void))block;
- (NSDictionary<NSString *, NSNumber *> *)timeDistribution;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
