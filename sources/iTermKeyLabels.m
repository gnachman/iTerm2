//
//  iTermKeyLabels.m
//  iTerm2
//
//  Created by George Nachman on 12/30/16.
//
//

#import "iTermKeyLabels.h"

@implementation iTermKeyLabels

- (void)dealloc {
    [_map release];
    [_name release];
    [super dealloc];
}

@end
