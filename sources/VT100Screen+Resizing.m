//
//  VT100Screen+Resizing.m
//  iTerm2Shared
//
//  Created by George Nachman on 12/21/21.
//

#import "VT100Screen+Resizing.h"
#import "VT100Screen+Mutation.h"
#import "VT100Screen+Private.h"
#import "VT100ScreenMutableState+Resizing.h"

#import "DebugLogging.h"
#import "VT100RemoteHost.h"
#import "VT100WorkingDirectory.h"
#import "iTermImageMark.h"
#import "iTermSelection.h"
#import "iTermURLMark.h"

@implementation VT100Screen (Resizing)

- (void)mutSetSize:(VT100GridSize)proposedSize
      visibleLines:(VT100GridRange)previouslyVisibleLineRange
         selection:(iTermSelection *)selection
           hasView:(BOOL)hasView {
    assert([NSThread isMainThread]);

    [_mutableState performBlockWithJoinedThreads:^(VT100Terminal * _Nonnull terminal,
                                                   VT100ScreenMutableState *mutableState,
                                                   id<VT100ScreenDelegate>  _Nonnull delegate) {
        assert(mutableState);
        const VT100GridSize newSize = [mutableState safeSizeForSize:proposedSize];
        if (![mutableState shouldSetSizeTo:newSize]) {
            return;
        }
        [mutableState.linebuffer beginResizing];
        [self reallySetSize:newSize
               visibleLines:previouslyVisibleLineRange
                  selection:selection
               mutableState:mutableState
                   delegate:delegate
                    hasView:hasView];
        [mutableState.linebuffer endResizing];

        if (gDebugLogging) {
            DLog(@"Notes after resizing to width=%@", @(_mutableState.width));
            for (id<IntervalTreeObject> object in _mutableState.intervalTree.allObjects) {
                if (![object isKindOfClass:[PTYAnnotation class]]) {
                    continue;
                }
                DLog(@"Note has coord range %@", VT100GridCoordRangeDescription([_mutableState coordRangeForInterval:object.entry.interval]));
            }
            DLog(@"------------ end -----------");
        }
    }];
}

- (void)reallySetSize:(VT100GridSize)newSize
         visibleLines:(VT100GridRange)previouslyVisibleLineRange
            selection:(iTermSelection *)selection
         mutableState:(VT100ScreenMutableState *)mutableState
             delegate:(id<VT100ScreenDelegate>)delegate
              hasView:(BOOL)hasView {
    assert([NSThread isMainThread]);

    DLog(@"------------ reallySetSize");
    DLog(@"Set size to %@", VT100GridSizeDescription(newSize));

    const VT100GridCoordRange previouslyVisibleLines =
    VT100GridCoordRangeMake(0,
                            previouslyVisibleLineRange.location,
                            0,
                            previouslyVisibleLineRange.location + 1);

    [mutableState sanityCheckIntervalsFrom:mutableState.currentGrid.size note:@"pre-hoc"];
    [mutableState.temporaryDoubleBuffer resetExplicitly];
    const VT100GridSize oldSize = mutableState.currentGrid.size;
    [mutableState willSetSizeWithSelection:selection];

    const BOOL couldHaveSelection = hasView && selection.hasSelection;
    const int usedHeight = [mutableState.currentGrid numberOfLinesUsed];

    VT100Grid *copyOfAltGrid = [[mutableState.altGrid copy] autorelease];
    LineBuffer *realLineBuffer = mutableState.linebuffer;

    // This is an array of tuples:
    // [LineBufferPositionRange, iTermSubSelection]
    NSArray *altScreenSubSelectionTuples = nil;
    LineBufferPosition *originalLastPos = [mutableState.linebuffer lastPosition];
    BOOL wasShowingAltScreen = (mutableState.currentGrid == mutableState.altGrid);


    // If non-nil, contains 3-tuples NSArray*s of
    // [ PTYAnnotation*,
    //   LineBufferPosition* for start of range,
    //   LineBufferPosition* for end of range ]
    // These will be re-added to intervalTree_ later on.
    NSArray *altScreenNotes = nil;

    // If we're in the alternate screen, create a temporary linebuffer and append
    // the base screen's contents to it.
    LineBuffer *altScreenLineBuffer = nil;
    if (wasShowingAltScreen) {
        altScreenLineBuffer = [mutableState prepareToResizeInAlternateScreenMode:&altScreenSubSelectionTuples
                                                     intervalTreeObjects:&altScreenNotes
                                                            hasSelection:couldHaveSelection
                                                               selection:selection
                                                              lineBuffer:realLineBuffer
                                                              usedHeight:usedHeight
                                                                 newSize:newSize];
    }

    // Append primary grid to line buffer.
    [mutableState appendScreen:mutableState.primaryGrid
                  toScrollback:mutableState.linebuffer
                withUsedHeight:[mutableState.primaryGrid numberOfLinesUsed]
                     newHeight:newSize.height];
    DLog(@"History after appending screen to scrollback:\n%@", [mutableState.linebuffer debugString]);

    VT100GridCoordRange convertedRangeOfVisibleLines;
    const BOOL rangeOfVisibleLinesConvertedCorrectly = [mutableState convertRange:previouslyVisibleLines
                                                                          toWidth:newSize.width
                                                                               to:&convertedRangeOfVisibleLines
                                                                     inLineBuffer:mutableState.linebuffer
                                                                    tolerateEmpty:YES];

    // Contains iTermSubSelection*s updated for the new screen size. Used
    // regardless of whether we were in the alt screen, as it's simply the set
    // of new sub-selections.
    NSArray *newSubSelections = @[];
    if (!wasShowingAltScreen && couldHaveSelection) {
        newSubSelections = [mutableState subSelectionsWithConvertedRangesFromSelection:selection
                                                                              newWidth:newSize.width];
    }

    [mutableState fixUpPrimaryGridIntervalTreeForNewSize:newSize
                                     wasShowingAltScreen:wasShowingAltScreen];
    mutableState.currentGrid.size = newSize;

    // Restore the screen contents that were pushed onto the linebuffer.
    [mutableState.currentGrid restoreScreenFromLineBuffer:wasShowingAltScreen ? altScreenLineBuffer : mutableState.linebuffer
                                          withDefaultChar:[mutableState.currentGrid defaultChar]
                                        maxLinesToRestore:[wasShowingAltScreen ? altScreenLineBuffer : mutableState.linebuffer numLinesWithWidth:mutableState.currentGrid.size.width]];
    DLog(@"After restoring screen from line buffer:\n%@", [self compactLineDumpWithHistoryAndContinuationMarksAndLineNumbers]);

    if (wasShowingAltScreen) {
        // If we're in the alternate screen, restore its contents from the temporary
        // linebuffer.
        // In alternate screen mode, the screen contents move up when the screen gets smaller.
        // For example, if your alt screen looks like this before:
        //   abcd
        //   ef..
        // And then gets shrunk to 3 wide, it becomes
        //   d..
        //   ef.
        // The "abc" line was lost, so "linesMovedUp" is 1. That's the number of lines at the top
        // of the alt screen that were lost.
        newSubSelections = [mutableState subSelectionsAfterRestoringPrimaryGridWithCopyOfAltGrid:copyOfAltGrid
                                                                                    linesMovedUp:[altScreenLineBuffer numLinesWithWidth:mutableState.currentGrid.size.width]
                                                                                    toLineBuffer:realLineBuffer
                                                                              subSelectionTuples:altScreenSubSelectionTuples
                                                                            originalLastPosition:originalLastPos
                                                                                         oldSize:oldSize
                                                                                         newSize:newSize
                                                                                      usedHeight:usedHeight
                                                                             intervalTreeObjects:altScreenNotes];
    } else {
        // Was showing primary grid. Fix up notes in the alt screen.
        [mutableState updateAlternateScreenIntervalTreeForNewSize:newSize];
    }

    const int newTop = rangeOfVisibleLinesConvertedCorrectly ? convertedRangeOfVisibleLines.start.y : -1;

    [mutableState didResizeToSize:newSize
                        selection:selection
               couldHaveSelection:couldHaveSelection
                    subSelections:newSubSelections
                           newTop:newTop
                         delegate:delegate];
    [altScreenLineBuffer endResizing];
    [mutableState sanityCheckIntervalsFrom:oldSize note:@"post-hoc"];
    DLog(@"After:\n%@", [mutableState.currentGrid compactLineDumpWithContinuationMarks]);
    DLog(@"Cursor at %d,%d", mutableState.currentGrid.cursorX, mutableState.currentGrid.cursorY);
}

- (void)mutSetWidth:(int)width preserveScreen:(BOOL)preserveScreen {
    if ([delegate_ screenShouldInitiateWindowResize] &&
        ![delegate_ screenWindowIsFullscreen]) {
        // set the column
        [delegate_ screenResizeToWidth:width
                                height:_state.currentGrid.size.height];
        if (!preserveScreen) {
            [_mutableState eraseInDisplayBeforeCursor:YES afterCursor:YES decProtect:NO];  // erase the screen
            _mutableState.currentGrid.cursorX = 0;
            _mutableState.currentGrid.cursorY = 0;
        }
    }
}



@end
