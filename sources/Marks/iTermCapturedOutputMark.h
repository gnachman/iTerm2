//
//  iTermCapturedOutputMark.h
//  iTerm2
//
//  Created by George Nachman on 10/18/15.
//
//

#import "iTermMark.h"

@protocol iTermCapturedOutputMarkReading<NSObject, iTermMark>
@end

// Invisible marks used to keep track of the location of captured output.
@interface iTermCapturedOutputMark : iTermMark<iTermCapturedOutputMarkReading>
@end
