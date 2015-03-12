//
//  iTermBackgroundColorRun.m
//  iTerm2
//
//  Created by George Nachman on 3/10/15.
//
//

#import "iTermBackgroundColorRun.h"

@implementation iTermBackgroundColorRunsInLine

- (void)dealloc {
    [_array release];
    [super dealloc];
}

@end

@implementation iTermBoxedBackgroundColorRun {
    iTermBackgroundColorRun _value;
}

- (void)dealloc {
    [_backgroundColor release];
    [super dealloc];
}

- (iTermBackgroundColorRun *)valuePointer {
    return &_value;
}

@end

