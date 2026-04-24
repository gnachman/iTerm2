//
//  PTYTriggerEvaluator.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/27/21.
//

#import <Foundation/Foundation.h>
#import "iTermExpect.h"
#import "PTYTextViewDataSource.h"
#import "Trigger.h"
#import "VT100Token.h"

NS_ASSUME_NONNULL_BEGIN

@class PTYTriggerEvaluator;
@class iTermStringLine;
@class iTermSlownessDetector;

extern NSString *const PTYSessionSlownessEventExecute;

@protocol PTYTriggerEvaluatorDataSource<iTermTextDataSource>
- (iTermStringLine * _Nullable)stringLineAsStringAtAbsoluteLineNumber:(long long)absoluteLineNumber
                                                             startPtr:(long long *)startAbsLineNumber;
- (int)numberOfScrollbackLines;
- (int)cursorY;
- (long long)totalScrollbackOverflow;
- (int)height;
@end

@protocol PTYTriggerEvaluatorDelegate<NSObject, iTermTriggerSession>
- (BOOL)triggerEvaluatorShouldUseTriggers:(PTYTriggerEvaluator *)evaluator;
// Call naggingController.offerToDisableTriggersInInteractiveApps()
- (void)triggerEvaluatorOfferToDisableTriggersInInteractiveApps:(PTYTriggerEvaluator *)evaluator;
- (void)triggerEvaluatorScheduleSideEffect:(PTYTriggerEvaluator *)evaluator
                                     block:(void (^)(void))block;
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

@property (nonatomic, strong) iTermExpect *expect;


// Measures time spent in triggers and executing tokens while in interactive apps.
// nil when not in soft alternate screen mode.
@property (nonatomic, strong, readonly) iTermSlownessDetector *triggersSlownessDetector;

@property (nonatomic) BOOL triggerParametersUseInterpolatedStrings;

@property (nonatomic, weak) id<PTYTriggerEvaluatorDataSource> dataSource;
@property (nonatomic, weak) id<PTYTriggerEvaluatorDelegate> delegate;
@property (nonatomic) BOOL sessionExited;
@property (atomic, readonly) BOOL evaluating;
@property (nonatomic, readonly) BOOL haveTriggersOrExpectations;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic) BOOL disableExecution;
// Set from the main thread by PTYSession when the foreground job changes.
// Read from the mutation thread during trigger evaluation.
// Contains lowercased argv0 values for the foreground process and its ancestors
// (deepest first) up to (but not including) the login shell.
@property (atomic, copy, nullable) NSArray<NSString *> *foregroundJobAncestors;
@property (nonatomic, readonly) BOOL havePromptDetectingTrigger;
@property (nonatomic, readonly) NSString *stats;
@property (nonatomic, copy, nullable) NSString *sessionID;

- (instancetype)initWithQueue:(dispatch_queue_t)queue NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)loadFromProfileArray:(NSArray *)array;
- (void)checkPartialLineTriggers;
- (void)checkIdempotentTriggersIfAllowed;
- (void)invalidateIdempotentTriggers;
- (void)appendStringToTriggerLine:(NSString *)s;
- (NSString * _Nullable)appendAsciiDataToCurrentLine:(AsciiData *)asciiData;
- (void)forceCheck;
- (NSIndexSet *)enabledTriggerIndexes;
- (void)clearTriggerLine;
- (void)resetRateLimit;

@end

NS_ASSUME_NONNULL_END
