//
//  iTermCapturedOutputMark.h
//  iTerm2
//
//  Created by George Nachman on 10/18/15.
//
//

#import "iTermMark.h"

// Invisible marks used to keep track of the location of captured output.
@interface iTermCapturedOutputMark : iTermMark
@property(nonatomic, copy) NSString *guid;
@end
