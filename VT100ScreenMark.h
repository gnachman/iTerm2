//
//  VT100ScreenMark.h
//  iTerm
//
//  Created by George Nachman on 12/5/13.
//
//

#import <Foundation/Foundation.h>
#import "IntervalTree.h"

@interface VT100ScreenMark : NSObject <IntervalTreeObject>

// Return code of command on the line for this mark.
@property(nonatomic, assign) int code;

// Command for this mark.
@property(nonatomic, copy) NSString *command;

// The session this mark belongs to.
@property(nonatomic, assign) int sessionID;

// Time the command was set at (and presumably began running).
@property(nonatomic, retain) NSDate *startDate;

// Time the command finished running. nil if no command or if it hasn't finished.
@property(nonatomic, retain) NSDate *endDate;

@end
