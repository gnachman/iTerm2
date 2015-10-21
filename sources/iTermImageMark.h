//
//  iTermImageMark.h
//  iTerm2
//
//  Created by George Nachman on 10/18/15.
//
//

#import "iTermMark.h"

// Invisible marks used to record where images are located so they can be freed.
@interface iTermImageMark : iTermMark
@property(nonatomic, retain) NSNumber *imageCode;
@end
