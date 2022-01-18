//
//  VT100Screen+Mutation.m
//  iTerm2Shared
//
//  Created by George Nachman on 12/9/21.
//

#import "VT100Screen+Mutation.h"
#import "VT100Screen+Private.h"

#import "VT100ScreenMutableState.h"

@implementation VT100Screen (Mutation)

// This can be deleted after I make a copy of the state in -sync
- (void)mutResetDirty {
    [_mutableState.currentGrid markAllCharsDirty:NO];
}

@end

