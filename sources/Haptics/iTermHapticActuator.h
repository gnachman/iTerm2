//
//  iTermHapticActuator.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/6/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, iTermHapticFeedbackType) {
    iTermHapticFeedbackTypeNone,
    iTermHapticFeedbackTypeWeak,
    iTermHapticFeedbackTypeMedium,
    iTermHapticFeedbackTypeStrong
};

@interface iTermHapticActuator : NSObject

@property (nonatomic) iTermHapticFeedbackType feedbackType;

+ (instancetype)sharedActuator;

- (void)actuateTouchDownFeedback;
- (void)actuateTouchUpFeedback;


@end

NS_ASSUME_NONNULL_END
