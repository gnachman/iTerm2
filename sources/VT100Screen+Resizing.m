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
        newSubSelections = [self subSelectionsAfterRestoringPrimaryGridWithCopyOfAltGrid:copyOfAltGrid
                                                                            linesMovedUp:[altScreenLineBuffer numLinesWithWidth:mutableState.currentGrid.size.width]
                                                                            toLineBuffer:realLineBuffer
                                                                      subSelectionTuples:altScreenSubSelectionTuples
                                                                    originalLastPosition:originalLastPos
                                                                                 oldSize:oldSize
                                                                                 newSize:newSize
                                                                              usedHeight:usedHeight
                                                                     intervalTreeObjects:altScreenNotes
                                                                            mutableState:mutableState];
    } else {
        // Was showing primary grid. Fix up notes in the alt screen.
        [self updateAlternateScreenIntervalTreeForNewSize:newSize
                                             mutableState:mutableState];
    }

    const int newTop = rangeOfVisibleLinesConvertedCorrectly ? convertedRangeOfVisibleLines.start.y : -1;

    [self didResizeToSize:newSize
                selection:selection
       couldHaveSelection:couldHaveSelection
            subSelections:newSubSelections
                   newTop:newTop];
    [altScreenLineBuffer endResizing];
    [mutableState sanityCheckIntervalsFrom:oldSize note:@"post-hoc"];
    DLog(@"After:\n%@", [mutableState.currentGrid compactLineDumpWithContinuationMarks]);
    DLog(@"Cursor at %d,%d", mutableState.currentGrid.cursorX, mutableState.currentGrid.cursorY);
}

- (void)updateAlternateScreenIntervalTreeForNewSize:(VT100GridSize)newSize
                                       mutableState:(VT100ScreenMutableState *)mutableState {
    // Append alt screen to empty line buffer
    LineBuffer *altScreenLineBuffer = [[[LineBuffer alloc] init] autorelease];
    [altScreenLineBuffer beginResizing];
    [mutableState appendScreen:mutableState.altGrid
                  toScrollback:altScreenLineBuffer
                withUsedHeight:[mutableState.altGrid numberOfLinesUsed]
                     newHeight:newSize.height];
    int numLinesThatWillBeRestored = MIN([altScreenLineBuffer numLinesWithWidth:newSize.width],
                                         newSize.height);
    int numLinesDroppedFromTop = [altScreenLineBuffer numLinesWithWidth:newSize.width] - numLinesThatWillBeRestored;

    // Convert note ranges to new coords, dropping or truncating as needed
    mutableState.currentGrid = mutableState.altGrid;  // Swap to alt grid temporarily for convertRange:toWidth:to:inLineBuffer:
    IntervalTree *replacementTree = [[[IntervalTree alloc] init] autorelease];
    for (id<IntervalTreeObject> object in [_state.savedIntervalTree allObjects]) {
        VT100GridCoordRange objectRange = [mutableState coordRangeForInterval:object.entry.interval];
        DLog(@"Found object at %@", VT100GridCoordRangeDescription(objectRange));
        VT100GridCoordRange newRange;
        if ([mutableState convertRange:objectRange
                               toWidth:newSize.width
                                    to:&newRange
                          inLineBuffer:altScreenLineBuffer
                         tolerateEmpty:[mutableState intervalTreeObjectMayBeEmpty:object]]) {
            assert(objectRange.start.y >= 0);
            assert(objectRange.end.y >= 0);
            // Anticipate the lines that will be dropped when the alt grid is restored.
            newRange.start.y += mutableState.cumulativeScrollbackOverflow - numLinesDroppedFromTop;
            newRange.end.y += mutableState.cumulativeScrollbackOverflow - numLinesDroppedFromTop;
            if (newRange.start.y < 0) {
                newRange.start.y = 0;
                newRange.start.x = 0;
            }
            DLog(@"  Its new range is %@ including %d lines dropped from top", VT100GridCoordRangeDescription(objectRange), numLinesDroppedFromTop);
            [mutableState.savedIntervalTree removeObject:object];
            if (newRange.end.y > 0 || (newRange.end.y == 0 && newRange.end.x > 0)) {
                Interval *newInterval = [mutableState intervalForGridCoordRange:newRange
                                                                          width:newSize.width
                                                                    linesOffset:0];
                [replacementTree addObject:object withInterval:newInterval];
            } else {
                DLog(@"Failed to convert");
            }
        }
    }
    mutableState.savedIntervalTree = replacementTree;
    mutableState.currentGrid = _state.primaryGrid;  // Swap back to primary grid

    // Restore alt screen with new width
    self.mutableAltGrid.size = VT100GridSizeMake(newSize.width, newSize.height);
    [self.mutableAltGrid restoreScreenFromLineBuffer:altScreenLineBuffer
                                     withDefaultChar:[_state.altGrid defaultChar]
                                   maxLinesToRestore:[altScreenLineBuffer numLinesWithWidth:_state.currentGrid.size.width]];
    [altScreenLineBuffer endResizing];
}

- (NSArray *)subSelectionsAfterRestoringPrimaryGridWithCopyOfAltGrid:(VT100Grid *)copyOfAltGrid
                                                        linesMovedUp:(int)linesMovedUp
                                                        toLineBuffer:(LineBuffer *)realLineBuffer
                                                  subSelectionTuples:(NSArray *)altScreenSubSelectionTuples
                                                originalLastPosition:(LineBufferPosition *)originalLastPos
                                                             oldSize:(VT100GridSize)oldSize
                                                             newSize:(VT100GridSize)newSize
                                                          usedHeight:(int)usedHeight
                                                 intervalTreeObjects:(NSArray *)altScreenNotes
                                                        mutableState:(VT100ScreenMutableState *)mutableState {
    [mutableState restorePrimaryGridWithLineBuffer:realLineBuffer
                                           oldSize:oldSize
                                           newSize:newSize];

    // Any onscreen notes in primary grid get moved to savedIntervalTree_.
    mutableState.currentGrid = _state.primaryGrid;
    [mutableState swapOnscreenIntervalTreeObjects];
    mutableState.currentGrid = _state.altGrid;

    ///////////////////////////////////////
    // Create a cheap append-only copy of the line buffer and add the
    // screen to it. This sets up the current state so that if there is a
    // selection, linebuffer has the configuration that the user actually
    // sees (history + the alt screen contents). That'll make
    // convertRange:toWidth:... happy (the selection's Y values
    // will be able to be looked up) and then after that's done we can swap
    // back to the tempLineBuffer.
    LineBuffer *appendOnlyLineBuffer = [[realLineBuffer copy] autorelease];
    LineBufferPosition *newLastPos = [realLineBuffer lastPosition];
    NSArray *newSubSelections = [self subSelectionsForNewSize:newSize
                                                   lineBuffer:realLineBuffer
                                                         grid:copyOfAltGrid
                                                   usedHeight:usedHeight
                                           subSelectionTuples:altScreenSubSelectionTuples
                                         originalLastPosition:originalLastPos
                                              newLastPosition:newLastPos
                                                 linesMovedUp:linesMovedUp
                                         appendOnlyLineBuffer:appendOnlyLineBuffer
                                                 mutableState:mutableState];
    DLog(@"Original limit=%@", originalLastPos);
    DLog(@"New limit=%@", newLastPos);
    [mutableState addObjectsToIntervalTreeFromTuples:altScreenNotes
                                             newSize:newSize
                                originalLastPosition:originalLastPos
                                     newLastPosition:newLastPos
                                        linesMovedUp:linesMovedUp
                                appendOnlyLineBuffer:appendOnlyLineBuffer];
    return newSubSelections;
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

- (void)didResizeToSize:(VT100GridSize)newSize
              selection:(iTermSelection *)selection
     couldHaveSelection:(BOOL)couldHaveSelection
          subSelections:(NSArray *)newSubSelections
                 newTop:(int)newTop {
    [_mutableState.terminal clampSavedCursorToScreenSize:VT100GridSizeMake(newSize.width, newSize.height)];

    [self.mutablePrimaryGrid resetScrollRegions];
    [self.mutableAltGrid resetScrollRegions];
    [self.mutablePrimaryGrid clampCursorPositionToValid];
    [self.mutableAltGrid clampCursorPositionToValid];

    // The linebuffer may have grown. Ensure it doesn't have too many lines.
    int linesDropped = 0;
    if (!_state.unlimitedScrollback) {
        linesDropped = [self.mutableLineBuffer dropExcessLinesWithWidth:_state.currentGrid.size.width];
        [_mutableState incrementOverflowBy:linesDropped];
    }
    int lines __attribute__((unused)) = [_mutableState.linebuffer numLinesWithWidth:_state.currentGrid.size.width];
    ITAssertWithMessage(lines >= 0, @"Negative lines");

    [selection clearSelection];
    // An immediate refresh is needed so that the size of textview can be
    // adjusted to fit the new size
    DebugLog(@"setSize setDirty");
    [delegate_ screenNeedsRedraw];
    if (couldHaveSelection) {
        NSMutableArray *subSelectionsToAdd = [NSMutableArray array];
        for (iTermSubSelection *sub in newSubSelections) {
            VT100GridAbsCoordRangeTryMakeRelative(sub.absRange.coordRange,
                                                  _mutableState.cumulativeScrollbackOverflow,
                                                  ^(VT100GridCoordRange range) {
                [subSelectionsToAdd addObject:sub];
            });
        }
        [selection addSubSelections:subSelectionsToAdd];
    }

    [self mutReloadMarkCache];
    [delegate_ screenSizeDidChangeWithNewTopLineAt:newTop];
}

- (NSArray *)subSelectionsForNewSize:(VT100GridSize)newSize
                          lineBuffer:(LineBuffer *)realLineBuffer
                                grid:(VT100Grid *)copyOfAltGrid
                          usedHeight:(int)usedHeight
                  subSelectionTuples:(NSArray *)altScreenSubSelectionTuples
                originalLastPosition:(LineBufferPosition *)originalLastPos
                     newLastPosition:(LineBufferPosition *)newLastPos
                        linesMovedUp:(int)linesMovedUp
                appendOnlyLineBuffer:(LineBuffer *)appendOnlyLineBuffer
                        mutableState:(VT100ScreenMutableState *)mutableState {
    [mutableState appendScreen:copyOfAltGrid
                  toScrollback:appendOnlyLineBuffer
                withUsedHeight:usedHeight
                     newHeight:newSize.height];

    NSMutableArray *newSubSelections = [NSMutableArray array];
    for (int i = 0; i < altScreenSubSelectionTuples.count; i++) {
        LineBufferPositionRange *positionRange = altScreenSubSelectionTuples[i][0];
        iTermSubSelection *originalSub = altScreenSubSelectionTuples[i][1];
        VT100GridCoordRange newSelection;
        BOOL ok = [mutableState computeRangeFromOriginalLimit:originalLastPos
                                                limitPosition:newLastPos
                                                startPosition:positionRange.start
                                                  endPosition:positionRange.end
                                                     newWidth:newSize.width
                                                   lineBuffer:appendOnlyLineBuffer
                                                        range:&newSelection
                                                 linesMovedUp:linesMovedUp];
        if (ok) {
            const VT100GridAbsWindowedRange theRange =
            VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeFromCoordRange(newSelection, mutableState.cumulativeScrollbackOverflow),
                                          0, 0);
            iTermSubSelection *theSub = [iTermSubSelection subSelectionWithAbsRange:theRange
                                                                               mode:originalSub.selectionMode
                                                                              width:mutableState.width];
            theSub.connected = originalSub.connected;
            [newSubSelections addObject:theSub];
        }
    }
    return newSubSelections;
}


@end
