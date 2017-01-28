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

@protocol iTermMarkDelegate <NSObject>
- (void)markDidBecomeCommandMark:(id<iTermMark>)mark;
@end

// Visible marks that can be navigated.
@interface VT100ScreenMark : iTermMark

@property(nonatomic, assign) BOOL isPrompt;
@property(nonatomic, copy) NSString *guid;

// Array of CapturedOutput objects.
@property(nonatomic, readonly) NSArray *capturedOutput;

@property(nonatomic, assign) id<iTermMarkDelegate> delegate;

// Return code of command on the line for this mark.
@property(nonatomic, assign) int code;

// Command for this mark.
@property(nonatomic, copy) NSString *command;

// Time the command was set at (and presumably began running).
@property(nonatomic, retain) NSDate *startDate;

// Time the command finished running. nil if no command or if it hasn't finished.
@property(nonatomic, retain) NSDate *endDate;

// The session this mark belongs to.
@property(nonatomic, retain) NSString *sessionGuid;

@property(nonatomic, assign) VT100GridAbsCoordRange promptRange;
@property(nonatomic, assign) VT100GridAbsCoordRange commandRange;
@property(nonatomic, assign) VT100GridAbsCoord outputStart;

// Returns a reference to an existing mark with the given GUID.
+ (VT100ScreenMark *)markWithGuid:(NSString *)guid;

// Add an object to self.capturedOutput.
- (void)addCapturedOutput:(CapturedOutput *)capturedOutput;

@end
