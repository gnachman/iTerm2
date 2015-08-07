//
//  iTermRestorableSession.m
//  iTerm
//
//  Created by George Nachman on 5/30/14.
//
//

#import "iTermRestorableSession.h"

@implementation iTermRestorableSession

- (void)dealloc {
    [_sessions release];
    [_terminalGuid release];
    [_arrangement release];
    [_predecessors release];
    [super dealloc];
}

@end
