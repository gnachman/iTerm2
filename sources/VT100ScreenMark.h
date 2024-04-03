//
//  VT100ScreenMark.h
//  iTerm
//
//  Created by George Nachman on 12/5/13.
//
//

#import <Foundation/Foundation.h>
#import "iTermMark.h"
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class CapturedOutput;
@protocol CapturedOutputReading;
@class ScreenCharArray;
@protocol VT100ScreenMarkReading;
@class iTermPromise<T>;

@protocol iTermMarkDelegate <NSObject>
- (void)markDidBecomeCommandMark:(id<VT100ScreenMarkReading>)mark;
@end

@protocol VT100ScreenMarkReading<NSObject, IntervalTreeImmutableObject, iTermMark>
@property(nonatomic, readonly) BOOL isPrompt;
@property(nonatomic, copy, readonly) NSString *guid;
@property(nonatomic, readonly) NSInteger clearCount;

// Array of CapturedOutput objects.
@property(nonatomic, readonly, nullable) NSArray<id<CapturedOutputReading>> *capturedOutput;

// Return code of command on the line for this mark.
@property(nonatomic, readonly) int code;
@property(nonatomic, readonly) BOOL hasCode;

// Command for this mark.
@property(nonatomic, copy, readonly) NSString *command;

// Time the command was set at (and presumably began running).
@property(nonatomic, strong, readonly, nullable) NSDate *startDate;

// Time the command finished running. nil if no command or if it hasn't finished.
@property(nonatomic, strong, readonly, nullable) NSDate *endDate;

// The session this mark belongs to.
@property(nonatomic, strong, readonly, nullable) NSString *sessionGuid;

@property(nonatomic, readonly) VT100GridAbsCoordRange promptRange;
@property(nonatomic, copy, readonly, nullable) NSArray<ScreenCharArray *> *promptText;
@property(nonatomic, readonly) VT100GridAbsCoordRange commandRange;
@property(nonatomic, readonly) VT100GridAbsCoord outputStart;
@property(nonatomic, readonly) iTermPromise<NSNumber *> *returnCodePromise;
@property(nonatomic, readonly) BOOL promptDetectedByTrigger;
@property(nonatomic, readonly) BOOL lineStyle;
@property(nonatomic, readonly, copy, nullable) NSString *name;

@property(nonatomic, readonly) BOOL isRunning;

- (id<VT100ScreenMarkReading>)progenitor;
- (id<VT100ScreenMarkReading>)doppelganger;

@end

// Visible marks that can be navigated.
@interface VT100ScreenMark : iTermMark<VT100ScreenMarkReading, IntervalTreeObject>

@property(nonatomic, readwrite) BOOL isPrompt;
@property(nonatomic, copy, readwrite) NSString *guid;

@property(nonatomic, weak, readwrite, nullable) id<iTermMarkDelegate> delegate;

// Return code of command on the line for this mark.
@property(nonatomic, readwrite) int code;

// Command for this mark.
@property(nonatomic, copy, readwrite, nullable) NSString *command;

// Time the command was set at (and presumably began running).
@property(nonatomic, strong, readwrite, nullable) NSDate *startDate;

// Time the command finished running. nil if no command or if it hasn't finished.
@property(nonatomic, strong, readwrite, nullable) NSDate *endDate;

// The session this mark belongs to.
@property(nonatomic, strong, readwrite) NSString *sessionGuid;

@property(nonatomic, copy, readwrite, nullable) NSString *name;

@property(nonatomic, readwrite) VT100GridAbsCoordRange promptRange;
@property(nonatomic, copy, nullable) NSArray<ScreenCharArray *> *promptText;
@property(nonatomic, readwrite) VT100GridAbsCoordRange commandRange;
@property(nonatomic, readwrite) VT100GridAbsCoord outputStart;
@property(nonatomic) BOOL promptDetectedByTrigger;
@property(nonatomic) BOOL lineStyle;

// Returns a reference to an existing mark with the given GUID.
+ (id<VT100ScreenMarkReading>)markWithGuid:(NSString *)guid
                         forMutationThread:(BOOL)forMutationThread;

// Add an object to self.capturedOutput.
- (void)addCapturedOutput:(CapturedOutput *)capturedOutput;
- (void)incrementClearCount;

- (id<VT100ScreenMarkReading>)doppelganger;

@end

NS_ASSUME_NONNULL_END
