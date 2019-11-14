//
//  NSTableView+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/14/19.
//

#import "NSTableView+iTerm.h"

#import <AppKit/AppKit.h>


@implementation NSTableView (iTerm)

- (void)it_performUpdateBlock:(void (^NS_NOESCAPE)(void))block {
    [self beginUpdates];
    block();
    [self endUpdates];
}

@end
