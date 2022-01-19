//
//  iTermCapturedOutputMark.h
//  iTerm2
//
//  Created by George Nachman on 10/18/15.
//
//

#import "iTermMark.h"

@protocol iTermCapturedOutputMarkReading<NSObject, IntervalTreeImmutableEntry, iTermMark>
@property (nonatomic, copy, readonly) NSString *guid;
@end

// Invisible marks used to keep track of the location of captured output.
@interface iTermCapturedOutputMark : iTermMark<iTermCapturedOutputMarkReading>
@property(nonatomic, copy, readwrite) NSString *guid;
@end
