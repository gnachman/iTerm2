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

@class CapturedOutput;
@protocol CapturedOutputReading;
@protocol VT100ScreenMarkReading;

@protocol iTermMarkDelegate <NSObject>
- (void)markDidBecomeCommandMark:(id<VT100ScreenMarkReading>)mark;
@end

@protocol VT100ScreenMarkReading<NSObject, IntervalTreeImmutableObject, iTermMark>
@property(nonatomic, readonly) BOOL isPrompt;
@property(nonatomic, copy, readonly) NSString *guid;
@property(nonatomic, readonly) NSInteger clearCount;

// Array of CapturedOutput objects.
@property(nonatomic, readonly) NSArray<id<CapturedOutputReading>> *capturedOutput;

// Return code of command on the line for this mark.
@property(nonatomic, readonly) int code;
@property(nonatomic, readonly) BOOL hasCode;

// Command for this mark.
#warning TODO: readonlyments to command must happen on the mutation thread safely!
@property(nonatomic, copy, readonly) NSString *command;

// Time the command was set at (and presumably began running).
@property(nonatomic, strong, readonly) NSDate *startDate;

// Time the command finished running. nil if no command or if it hasn't finished.
@property(nonatomic, strong, readonly) NSDate *endDate;

// The session this mark belongs to.
@property(nonatomic, strong, readonly) NSString *sessionGuid;

@property(nonatomic, readonly) VT100GridAbsCoordRange promptRange;
@property(nonatomic, readonly) VT100GridAbsCoordRange commandRange;
@property(nonatomic, readonly) VT100GridAbsCoord outputStart;

- (id<VT100ScreenMarkReading>)progenitor;
- (id<VT100ScreenMarkReading>)doppelganger;

@end

// Visible marks that can be navigated.
@interface VT100ScreenMark : iTermMark<VT100ScreenMarkReading, IntervalTreeObject>

@property(nonatomic, readwrite) BOOL isPrompt;
@property(nonatomic, copy, readwrite) NSString *guid;

@property(nonatomic, weak, readwrite) id<iTermMarkDelegate> delegate;

// Return code of command on the line for this mark.
@property(nonatomic, readwrite) int code;

// Command for this mark.
#warning TODO: Assignments to command must happen on the mutation thread safely!
@property(nonatomic, copy, readwrite) NSString *command;

// Time the command was set at (and presumably began running).
@property(nonatomic, strong, readwrite) NSDate *startDate;

// Time the command finished running. nil if no command or if it hasn't finished.
@property(nonatomic, strong, readwrite) NSDate *endDate;

// The session this mark belongs to.
@property(nonatomic, strong, readwrite) NSString *sessionGuid;

@property(nonatomic, readwrite) VT100GridAbsCoordRange promptRange;
@property(nonatomic, readwrite) VT100GridAbsCoordRange commandRange;
@property(nonatomic, readwrite) VT100GridAbsCoord outputStart;

// Returns a reference to an existing mark with the given GUID.
+ (id<VT100ScreenMarkReading>)markWithGuid:(NSString *)guid;

// Add an object to self.capturedOutput.
- (void)addCapturedOutput:(CapturedOutput *)capturedOutput;
- (void)incrementClearCount;

- (id<VT100ScreenMarkReading>)doppelganger;

@end
