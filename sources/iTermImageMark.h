//
//  iTermImageMark.h
//  iTerm2
//
//  Created by George Nachman on 10/18/15.
//
//

#import "iTermMark.h"

@protocol iTermImageMarkReading<NSObject>
@property(nonatomic, strong, readonly) NSNumber *imageCode;

- (id<iTermImageMarkReading>)doppelganger;
@end

// Invisible marks used to record where images are located so they can be freed.
@interface iTermImageMark : iTermMark
- (instancetype)initWithImageCode:(NSNumber *)imageCode NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, strong, readonly) NSNumber *imageCode;
@end
