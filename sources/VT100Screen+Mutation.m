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

- (void)mutUpdateConfig {
    _mutableState.config = _nextConfig;
}

#pragma mark - Accessors

- (void)mutSetAppendToScrollbackWithStatusBar:(BOOL)value {
    _mutableState.appendToScrollbackWithStatusBar = value;
}

- (void)mutSetTrackCursorLineMovement:(BOOL)trackCursorLineMovement {
    _mutableState.trackCursorLineMovement = trackCursorLineMovement;
}

- (void)mutSetSaveToScrollbackInAlternateScreen:(BOOL)value {
    _mutableState.saveToScrollbackInAlternateScreen = value;
}

- (void)mutInvalidateCommandStartCoord {
    [self mutSetCommandStartCoord:VT100GridAbsCoordMake(-1, -1)];
}

- (void)mutSetCommandStartCoord:(VT100GridAbsCoord)coord {
    [_mutableState setCoordinateOfCommandStart:coord];
}

- (void)mutResetScrollbackOverflow {
    [_mutableState resetScrollbackOverflow];
}

- (void)mutSetUnlimitedScrollback:(BOOL)newValue {
    _mutableState.unlimitedScrollback = newValue;
}

// Gets a line on the screen (0 = top of screen)
- (screen_char_t *)mutGetLineAtScreenIndex:(int)theIndex {
    return [_mutableState.currentGrid screenCharsAtLineNumber:theIndex];
}

#pragma mark - Dirty

- (void)mutResetAllDirty {
    _mutableState.currentGrid.allDirty = NO;
}

- (void)mutSetLineDirtyAtY:(int)y {
    if (y >= 0) {
        [_mutableState.currentGrid markCharsDirty:YES
                                       inRectFrom:VT100GridCoordMake(0, y)
                                               to:VT100GridCoordMake(_mutableState.width - 1, y)];
    }
}

- (void)mutSetCharDirtyAtCursorX:(int)x Y:(int)y {
    if (y < 0) {
        DLog(@"Warning: cannot set character dirty at y=%d", y);
        return;
    }
    int xToMark = x;
    int yToMark = y;
    if (xToMark == _state.currentGrid.size.width && yToMark < _state.currentGrid.size.height - 1) {
        xToMark = 0;
        yToMark++;
    }
    if (xToMark < _state.currentGrid.size.width && yToMark < _state.currentGrid.size.height) {
        [_mutableState.currentGrid markCharDirty:YES
                                              at:VT100GridCoordMake(xToMark, yToMark)
                                 updateTimestamp:NO];
        if (xToMark < _state.currentGrid.size.width - 1) {
            // Just in case the cursor was over a double width character
            [_mutableState.currentGrid markCharDirty:YES
                                                  at:VT100GridCoordMake(xToMark + 1, yToMark)
                                     updateTimestamp:NO];
        }
    }
}

- (void)mutResetDirty {
    [_mutableState.currentGrid markAllCharsDirty:NO];
}

- (void)mutRedrawGrid {
    [_mutableState.currentGrid setAllDirty:YES];
    // Force the screen to redraw right away. Some users reported lag and this seems to fix it.
    // I think the update timer was hitting a worst case scenario which made the lag visible.
    // See issue 3537.
    [delegate_ screenUpdateDisplay:YES];
}

#pragma mark - URLs

- (void)mutLinkTextInRange:(NSRange)range
basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                  URLCode:(unsigned int)code {
    [_mutableState linkTextInRange:range basedAtAbsoluteLineNumber:absoluteLineNumber URLCode:code];
}

#pragma mark - Highlighting

- (void)mutHighlightRun:(VT100GridRun)run
    withForegroundColor:(NSColor *)fgColor
        backgroundColor:(NSColor *)bgColor {
    [_mutableState highlightRun:run withForegroundColor:fgColor backgroundColor:bgColor];
}

- (void)mutHighlightTextInRange:(NSRange)range
      basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                         colors:(NSDictionary *)colors {
    [_mutableState highlightTextInRange:range
              basedAtAbsoluteLineNumber:absoluteLineNumber
                                 colors:colors];
}


#pragma mark - Scrollback

// sets scrollback lines.
- (void)mutSetMaxScrollbackLines:(unsigned int)lines {
    _mutableState.maxScrollbackLines = lines;
    [self.mutableLineBuffer setMaxLines: lines];
    if (!_state.unlimitedScrollback) {
        [_mutableState incrementOverflowBy:[self.mutableLineBuffer dropExcessLinesWithWidth:_state.currentGrid.size.width]];
    }
    [delegate_ screenDidChangeNumberOfScrollbackLines];
}

#pragma mark - Miscellaneous State

- (BOOL)mutGetAndResetHasScrolled {
    const BOOL result = _state.currentGrid.haveScrolled;
    _mutableState.currentGrid.haveScrolled = NO;
    return result;
}

#pragma mark - Synchronized Drawing

- (iTermTemporaryDoubleBufferedGridController *)mutableTemporaryDoubleBuffer {
    if ([delegate_ screenShouldReduceFlicker] || _mutableState.temporaryDoubleBuffer.explicit) {
        return _mutableState.temporaryDoubleBuffer;
    } else {
        return nil;
    }
}

- (PTYTextViewSynchronousUpdateState *)mutSetUseSavedGridIfAvailable:(BOOL)useSavedGrid {
    if (useSavedGrid && !_state.realCurrentGrid && self.mutableTemporaryDoubleBuffer.savedState) {
        _mutableState.realCurrentGrid = _state.currentGrid;
        _mutableState.currentGrid = self.mutableTemporaryDoubleBuffer.savedState.grid;
        self.mutableTemporaryDoubleBuffer.drewSavedGrid = YES;
        return self.mutableTemporaryDoubleBuffer.savedState;
    } else if (!useSavedGrid && _state.realCurrentGrid) {
        _mutableState.currentGrid = _state.realCurrentGrid;
        _mutableState.realCurrentGrid = nil;
    }
    return nil;
}

#pragma mark - Injection

- (void)mutInjectData:(NSData *)data {
    [_mutableState injectData:data];
}

#pragma mark - Triggers

- (void)mutForceCheckTriggers {
    [_mutableState forceCheckTriggers];
}

- (void)mutPerformPeriodicTriggerCheck {
    [_mutableState performPeriodicTriggerCheck];
}

@end

@implementation VT100Screen (Testing)

- (void)setMayHaveDoubleWidthCharacters:(BOOL)value {
    self.mutableLineBuffer.mayHaveDoubleWidthCharacter = value;
}

- (void)destructivelySetScreenWidth:(int)width height:(int)height {
    width = MAX(width, kVT100ScreenMinColumns);
    height = MAX(height, kVT100ScreenMinRows);

    self.mutablePrimaryGrid.size = VT100GridSizeMake(width, height);
    self.mutableAltGrid.size = VT100GridSizeMake(width, height);
    self.mutablePrimaryGrid.cursor = VT100GridCoordMake(0, 0);
    self.mutableAltGrid.cursor = VT100GridCoordMake(0, 0);
    [self.mutablePrimaryGrid resetScrollRegions];
    [self.mutableAltGrid resetScrollRegions];
    [_mutableState.terminal resetSavedCursorPositions];

    self.findContext.substring = nil;

    _mutableState.scrollbackOverflow = 0;
    [delegate_ screenRemoveSelection];

    [self.mutablePrimaryGrid markAllCharsDirty:YES];
    [self.mutableAltGrid markAllCharsDirty:YES];
}

@end
