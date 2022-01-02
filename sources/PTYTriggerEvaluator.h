//
//  PTYTriggerEvaluator.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/27/21.
//

#import <Foundation/Foundation.h>
#import "iTermExpect.h"
#import "iTermSlownessDetector.h"
#import "PTYTextViewDataSource.h"
#import "Trigger.h"
#import "VT100Token.h"

NS_ASSUME_NONNULL_BEGIN

@class PTYTriggerEvaluator;
@class iTermStringLine;

extern NSString *const PTYSessionSlownessEventExecute;

@protocol PTYTriggerEvaluatorDataSource<PTYTextViewDataSource>
- (iTermStringLine *)stringLineAsStringAtAbsoluteLineNumber:(long long)absoluteLineNumber
                                                   startPtr:(long long *)startAbsLineNumber;
@end

@protocol PTYTriggerEvaluatorDelegate<NSObject, iTermTriggerSession>

- (BOOL)triggerEvaluatorShouldUseTriggers:(PTYTriggerEvaluator *)evaluator;
// Call naggingController.offerToDisableTriggersInInteractiveApps()
- (void)triggerEvaluatorOfferToDisableTriggersInInteractiveApps:(PTYTriggerEvaluator *)evaluator;

@end

@interface PTYTriggerEvaluator : NSObject

// The current set of triggers.
@property (nonatomic, readonly) NSArray<Trigger *> *triggers;

// The last time at which a partial-line trigger check occurred. This keeps us from wasting CPU
// checking long lines over and over.
@property (nonatomic, readonly) NSTimeInterval lastPartialLineTriggerCheck;

// The absolute line number of the next line to apply triggers to.
@property (nonatomic, readonly) long long triggerLineNumber;

@property (nonatomic, readonly) BOOL shouldUpdateIdempotentTriggers;

@property (nonatomic, strong, readonly) iTermExpect *expect;


// Measures time spent in triggers and executing tokens while in interactive apps.
// nil when not in soft alternate screen mode.
@property (nonatomic, strong, readonly) iTermSlownessDetector *triggersSlownessDetector;

@property (nonatomic) BOOL triggerParametersUseInterpolatedStrings;

@property (nonatomic, weak) id<PTYTriggerEvaluatorDataSource> dataSource;
@property (nonatomic, weak) id<PTYTriggerEvaluatorDelegate> delegate;
@property (nonatomic) BOOL sessionExited;

- (instancetype)initWithDelegate:(id<PTYTriggerEvaluatorDelegate>)delegate
                      dataSource:(id<PTYTriggerEvaluatorDataSource>)dataSource NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)loadFromProfileArray:(NSArray *)array;
- (void)checkPartialLineTriggers;
- (void)checkIdempotentTriggersIfAllowed;
- (void)invalidateIdempotentTriggers;
- (void)appendStringToTriggerLine:(NSString *)s;
- (void)appendAsciiDataToCurrentLine:(AsciiData *)asciiData;
- (void)forceCheck;
- (NSIndexSet *)enabledTriggerIndexes;
- (void)clearTriggerLine;

@end

NS_ASSUME_NONNULL_END
