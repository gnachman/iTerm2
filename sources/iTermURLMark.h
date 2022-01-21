//
//  iTermURLMark.h
//  iTerm2
//
//  Created by George Nachman on 4/1/17.
//
//

#import "iTermMark.h"

@protocol iTermURLMarkReading<IntervalTreeImmutableObject>
@property (nonatomic, readonly) unsigned int code;
@end

// Invisible marks used to record where URL links are located so they can be freed.
@interface iTermURLMark : iTermMark<iTermURLMarkReading>
- (instancetype)initWithCode:(unsigned int)code NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) unsigned int code;
@end
