//
//  iTermURLMark.h
//  iTerm2
//
//  Created by George Nachman on 4/1/17.
//
//

#import "iTermMark.h"

// Invisible marks used to record where URL links are located so they can be freed.
@interface iTermURLMark : iTermMark
@property (nonatomic) unsigned short code;
@end
