//
//  VT100Screen+Mutation.m
//  iTerm2Shared
//
//  Created by George Nachman on 12/9/21.
//

// For mysterious reasons this needs to be in the iTerm2XCTests to avoid runtime failures to call
// its methods in tests. If I ever have an appetite for risk try https://stackoverflow.com/a/17581430/321984
#import "VT100Screen+Mutation.h"
#import "VT100Screen+Resizing.h"

#import "CapturedOutput.h"
#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSData+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "SearchResult.h"
#import "TmuxStateParser.h"
#import "VT100RemoteHost.h"
#import "VT100ScreenMutableState+Resizing.h"
#import "VT100ScreenMutableState+TerminalDelegate.h"
#import "VT100Screen+Private.h"
#import "VT100Token.h"
#import "VT100WorkingDirectory.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermCapturedOutputMark.h"
#import "iTermCommandHistoryCommandUseMO.h"
#import "iTermImageMark.h"
#import "iTermNotificationController.h"
#import "iTermOrderEnforcer.h"
#import "iTermPreferences.h"
#import "iTermSelection.h"
#import "iTermShellHistoryController.h"
#import "iTermTemporaryDoubleBufferedGridController.h"
#import "iTermTextExtractor.h"
#import "iTermURLMark.h"

#include <sys/time.h>

#warning TODO: I can't call regular VT100Screen methods from here because they'll use _state instead of _mutableState! I think this should eventually be its own class, not a category, to enfore the shared-nothing regime.

@implementation VT100Screen (Mutation)

- (VT100Grid *)mutableAltGrid {
    return (VT100Grid *)_state.altGrid;
}

- (VT100Grid *)mutablePrimaryGrid {
    return (VT100Grid *)_state.primaryGrid;
}

- (LineBuffer *)mutableLineBuffer {
    return (LineBuffer *)_mutableState.linebuffer;
}

#pragma mark - Dirty

// This can be deleted after I make a copy of the state in -sync
- (void)mutResetDirty {
    [_mutableState.currentGrid markAllCharsDirty:NO];
}

@end

