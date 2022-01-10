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
        altScreenLineBuffer = [self prepareToResizeInAlternateScreenMode:&altScreenSubSelectionTuples
                                                     intervalTreeObjects:&altScreenNotes
                                                            hasSelection:couldHaveSelection
                                                               selection:selection
                                                              lineBuffer:realLineBuffer
                                                              usedHeight:usedHeight
                                                                 newSize:newSize
                                                            mutableState:mutableState];
    }

    // Append primary grid to line buffer.
    [mutableState appendScreen:mutableState.primaryGrid
                  toScrollback:mutableState.linebuffer
                withUsedHeight:[mutableState.primaryGrid numberOfLinesUsed]
                     newHeight:newSize.height];
    DLog(@"History after appending screen to scrollback:\n%@", [mutableState.linebuffer debugString]);

    VT100GridCoordRange convertedRangeOfVisibleLines;
    const BOOL rangeOfVisibleLinesConvertedCorrectly = [self convertRange:previouslyVisibleLines
                                                                  toWidth:newSize.width
                                                                       to:&convertedRangeOfVisibleLines
                                                             inLineBuffer:mutableState.linebuffer
                                                             mutableState:mutableState
                                                            tolerateEmpty:YES];

    // Contains iTermSubSelection*s updated for the new screen size. Used
    // regardless of whether we were in the alt screen, as it's simply the set
    // of new sub-selections.
    NSArray *newSubSelections = @[];
    if (!wasShowingAltScreen && couldHaveSelection) {
        newSubSelections = [self subSelectionsWithConvertedRangesFromSelection:selection
                                                                  mutableState:mutableState
                                                                      newWidth:newSize.width];
    }

    [self fixUpPrimaryGridIntervalTreeForNewSize:newSize
                             wasShowingAltScreen:wasShowingAltScreen
                                    mutableState:mutableState];
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
        if ([self convertRange:objectRange toWidth:newSize.width to:&newRange inLineBuffer:altScreenLineBuffer mutableState:mutableState tolerateEmpty:[mutableState intervalTreeObjectMayBeEmpty:object]]) {
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
    [self restorePrimaryGridWithLineBuffer:realLineBuffer
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
    [self addObjectsToIntervalTreeFromTuples:altScreenNotes
                                     newSize:newSize
                        originalLastPosition:originalLastPos
                             newLastPosition:newLastPos
                                linesMovedUp:linesMovedUp
                        appendOnlyLineBuffer:appendOnlyLineBuffer];
    return newSubSelections;
}

- (LineBuffer *)prepareToResizeInAlternateScreenMode:(NSArray **)altScreenSubSelectionTuplesPtr
                                 intervalTreeObjects:(NSArray **)altScreenNotesPtr
                                        hasSelection:(BOOL)couldHaveSelection
                                           selection:(iTermSelection *)selection
                                          lineBuffer:(LineBuffer *)realLineBuffer
                                          usedHeight:(int)usedHeight
                                             newSize:(VT100GridSize)newSize
                                        mutableState:(VT100ScreenMutableState *)mutableState {
    if (couldHaveSelection) {
        *altScreenSubSelectionTuplesPtr = [mutableState subSelectionTuplesWithUsedHeight:usedHeight
                                                                               newHeight:newSize.height
                                                                               selection:selection];
    }

    LineBuffer *altScreenLineBuffer = [[[LineBuffer alloc] init] autorelease];
    [altScreenLineBuffer beginResizing];
    [mutableState appendScreen:mutableState.altGrid
                  toScrollback:altScreenLineBuffer
                withUsedHeight:usedHeight
                     newHeight:newSize.height];

    if ([mutableState.intervalTree count]) {
        *altScreenNotesPtr = [mutableState intervalTreeObjectsWithUsedHeight:usedHeight
                                                                   newHeight:newSize.height
                                                                        grid:_state.altGrid
                                                                  lineBuffer:realLineBuffer];
    }

    mutableState.currentGrid = _state.primaryGrid;
    // Move savedIntervalTree_ into intervalTree_. This should leave savedIntervalTree_ empty.
    [mutableState swapOnscreenIntervalTreeObjects];
    mutableState.currentGrid = _state.altGrid;

    return altScreenLineBuffer;
}

- (void)fixUpPrimaryGridIntervalTreeForNewSize:(VT100GridSize)newSize
                           wasShowingAltScreen:(BOOL)wasShowingAltScreen
                                  mutableState:(VT100ScreenMutableState *)mutableState {
    if ([mutableState.intervalTree count]) {
        // Fix up the intervals for the primary grid.
        if (wasShowingAltScreen) {
            // Temporarily swap in primary grid so convertRange: will do the right thing.
            mutableState.currentGrid = _state.primaryGrid;
        }

        mutableState.intervalTree = [self replacementIntervalTreeForNewWidth:newSize.width
                                                                mutableState:mutableState];

        if (wasShowingAltScreen) {
            // Return to alt grid.
            mutableState.currentGrid = mutableState.altGrid;
        }
    }
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

- (NSArray *)subSelectionsWithConvertedRangesFromSelection:(iTermSelection *)selection
                                              mutableState:(VT100ScreenMutableState *)mutableState
                                                  newWidth:(int)newWidth {
    NSMutableArray *newSubSelections = [NSMutableArray array];
    const long long overflow = mutableState.cumulativeScrollbackOverflow;
    for (iTermSubSelection *sub in selection.allSubSelections) {
        DLog(@"convert sub %@", sub);
        VT100GridAbsCoordRangeTryMakeRelative(sub.absRange.coordRange,
                                              overflow,
                                              ^(VT100GridCoordRange range) {
            VT100GridCoordRange newSelection;
            const BOOL ok = [self convertRange:range
                                       toWidth:newWidth
                                            to:&newSelection
                                  inLineBuffer:mutableState.linebuffer
                                  mutableState:mutableState
                                 tolerateEmpty:NO];
            if (ok) {
                assert(range.start.y >= 0);
                assert(range.end.y >= 0);
                const VT100GridWindowedRange relativeRange = VT100GridWindowedRangeMake(newSelection, 0, 0);
                const VT100GridAbsWindowedRange absRange =
                VT100GridAbsWindowedRangeFromWindowedRange(relativeRange, overflow);
                iTermSubSelection *theSub =
                [iTermSubSelection subSelectionWithAbsRange:absRange
                                                       mode:sub.selectionMode
                                                      width:newWidth];
                theSub.connected = sub.connected;
                [newSubSelections addObject:theSub];
            }
        });
    }
    return newSubSelections;
}

- (IntervalTree *)replacementIntervalTreeForNewWidth:(int)newWidth
                                        mutableState:(VT100ScreenMutableState *)mutableState {
    // Convert ranges of notes to their new coordinates and replace the interval tree.
    IntervalTree *replacementTree = [[[IntervalTree alloc] init] autorelease];
    for (id<IntervalTreeObject> note in [mutableState.intervalTree allObjects]) {
        VT100GridCoordRange noteRange = [mutableState coordRangeForInterval:note.entry.interval];
        VT100GridCoordRange newRange;
        if (noteRange.end.x < 0 && noteRange.start.y == 0 && noteRange.end.y < 0) {
            // note has scrolled off top
            [mutableState.intervalTree removeObject:note];
        } else {
            if ([self convertRange:noteRange
                           toWidth:newWidth
                                to:&newRange
                      inLineBuffer:mutableState.linebuffer
                      mutableState:mutableState
                     tolerateEmpty:[mutableState intervalTreeObjectMayBeEmpty:note]]) {
                assert(noteRange.start.y >= 0);
                assert(noteRange.end.y >= 0);
                Interval *newInterval = [mutableState intervalForGridCoordRange:newRange
                                                                          width:newWidth
                                                                    linesOffset:mutableState.cumulativeScrollbackOverflow];
                [[note retain] autorelease];
                [mutableState.intervalTree removeObject:note];
                [replacementTree addObject:note withInterval:newInterval];
            }
        }
    }
    return replacementTree;
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
                        mutableState:(VT100ScreenMutableState *)mutableState{
    [mutableState appendScreen:copyOfAltGrid
                  toScrollback:appendOnlyLineBuffer
                withUsedHeight:usedHeight
                     newHeight:newSize.height];

    NSMutableArray *newSubSelections = [NSMutableArray array];
    for (int i = 0; i < altScreenSubSelectionTuples.count; i++) {
        LineBufferPositionRange *positionRange = altScreenSubSelectionTuples[i][0];
        iTermSubSelection *originalSub = altScreenSubSelectionTuples[i][1];
        VT100GridCoordRange newSelection;
        BOOL ok = [self computeRangeFromOriginalLimit:originalLastPos
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

- (void)addObjectsToIntervalTreeFromTuples:(NSArray *)altScreenNotes
                                   newSize:(VT100GridSize)newSize
                      originalLastPosition:(LineBufferPosition *)originalLastPos
                           newLastPosition:(LineBufferPosition *)newLastPos
                              linesMovedUp:(int)linesMovedUp
                      appendOnlyLineBuffer:(LineBuffer *)appendOnlyLineBuffer
{
    for (NSArray *tuple in altScreenNotes) {
        id<IntervalTreeObject> note = tuple[0];
        LineBufferPosition *start = tuple[1];
        LineBufferPosition *end = tuple[2];
        VT100GridCoordRange newRange;
        DLog(@"  Note positions=%@ to %@", start, end);
        BOOL ok = [self computeRangeFromOriginalLimit:originalLastPos
                                        limitPosition:newLastPos
                                        startPosition:start
                                          endPosition:end
                                             newWidth:newSize.width
                                           lineBuffer:appendOnlyLineBuffer
                                                range:&newRange
                                         linesMovedUp:linesMovedUp];
        if (ok) {
            DLog(@"  New range=%@", VT100GridCoordRangeDescription(newRange));
            Interval *interval = [_mutableState intervalForGridCoordRange:newRange
                                                                    width:newSize.width
                                                              linesOffset:_mutableState.cumulativeScrollbackOverflow];
            [_mutableState.intervalTree addObject:note withInterval:interval];
        } else {
            DLog(@"  *FAILED TO CONVERT*");
        }
    }
}


- (BOOL)convertRange:(VT100GridCoordRange)range
             toWidth:(int)newWidth
                  to:(VT100GridCoordRange *)resultPtr
        inLineBuffer:(LineBuffer *)lineBuffer
        mutableState:(VT100ScreenMutableState *)mutableState
       tolerateEmpty:(BOOL)tolerateEmpty {
    if (range.start.y < 0 || range.end.y < 0) {
        return NO;
    }
    LineBufferPositionRange *selectionRange;

    // Temporarily swap in the passed-in linebuffer so the call below can access lines in the right line buffer.
    LineBuffer *savedLineBuffer = mutableState.linebuffer;
    mutableState.linebuffer = lineBuffer;
    selectionRange = [mutableState positionRangeForCoordRange:range
                                                 inLineBuffer:lineBuffer
                                                tolerateEmpty:tolerateEmpty];
    DLog(@"%@ -> %@", VT100GridCoordRangeDescription(range), selectionRange);
    mutableState.linebuffer = savedLineBuffer;
    if (!selectionRange) {
        // One case where this happens is when the start and end of the range are past the last
        // character in the line buffer (e.g., all nulls). It could occur when a note exists on a
        // null line.
        return NO;
    }

    resultPtr->start = [lineBuffer coordinateForPosition:selectionRange.start
                                                   width:newWidth
                                            extendsRight:NO
                                                      ok:NULL];
    BOOL ok = NO;
    VT100GridCoord newEnd = [lineBuffer coordinateForPosition:selectionRange.end
                                                        width:newWidth
                                                 extendsRight:YES
                                                           ok:&ok];
    if (ok) {
        newEnd.x++;
        if (newEnd.x > newWidth) {
            newEnd.y++;
            newEnd.x -= newWidth;
        }
        resultPtr->end = newEnd;
    } else {
        // I'm not sure how to get here. It would happen if the endpoint of the selection could
        // be converted into a LineBufferPosition with the original width but that LineBufferPosition
        // could not be converted back into a VT100GridCoord with the new width.
        resultPtr->end.x = _state.currentGrid.size.width;
        resultPtr->end.y = [lineBuffer numLinesWithWidth:newWidth] + _state.currentGrid.size.height - 1;
    }
    if (selectionRange.end.extendsToEndOfLine) {
        resultPtr->end.x = newWidth;
    }
    return YES;
}

// This is used for a very specific case. It's used when you have some history, optionally followed
// by lines pulled from the primary grid, followed by the alternate grid, all stuffed into a line
// buffer. Given a pair of positions, it converts them to a range. If a position is between
// originalLastPos and newLastPos, it's invalid. Likewise, if a position is in the first
// |linesMovedUp| lines of the screen, it's invalid.
// NOTE: This assumes that _mutableState.linebuffer contains the history plus lines from the primary grid.
// Returns YES if the range is valid, NO if it could not be converted (e.g., because it was entirely
// in the area of dropped lines).
/*
 * 0 History      }                                                                     }
 * 1 History      } These lines were in history before resizing began                   }
 * 2 History      }                    <- originalLimit                                 } equal to _mutableState.linebuffer
 * 3 Line from primary grid            <- limit (pushed into history due to resize)     }
 * 4 Line to be lost from alt grid     <- linesMovedUp = 1 because this one line will be lost
 * 5 Line from alt grid                }
 * 6 Line from alt grid                } These lines will be restored to the alt grid later
 */
- (BOOL)computeRangeFromOriginalLimit:(LineBufferPosition *)originalLimit
                        limitPosition:(LineBufferPosition *)limit
                        startPosition:(LineBufferPosition *)startPos
                          endPosition:(LineBufferPosition *)endPos
                             newWidth:(int)newWidth
                           lineBuffer:(LineBuffer *)lineBuffer  // NOTE: May be append-only
                                range:(VT100GridCoordRange *)resultRangePtr
                         linesMovedUp:(int)linesMovedUp
{
    BOOL result = YES;
    // Compute selection positions relative to the end of the line buffer, which may have
    // grown or shrunk.
    int growth = limit.absolutePosition - originalLimit.absolutePosition;
    LineBufferPosition *savedEndPos = endPos;
    LineBufferPosition *predecessorOfLimit = [limit predecessor];
    if (growth > 0) {
        /*
         +--------------------+
         |                    |
         |  Original History  |
         |                    |
         +....................+ <------- originalLimit
         | Lines pushed from  | ^
         | primary into       | |- growth = number of lines in this section
         | history            | V
         +--------------------+ <------- limit
         |                    |
         | Alt screen         |
         |                    |
         +--------------------+
         */
        if (startPos.absolutePosition >= originalLimit.absolutePosition) {
            // Start position was on alt screen originally. Move it down by the number of lines
            // pulled in from the primary screen.
            startPos.absolutePosition += growth;
        }
        if (endPos.absolutePosition >= originalLimit.absolutePosition) {
            // End position was on alt screen originally. Move it down by the number of lines
            // pulled in from the primary screen.
            endPos.absolutePosition += growth;
        }
    } else if (growth < 0) {
        /*
         +--------------------+
         |                    |
         | Original history   |
         |                    |
         +--------------------+ +....................+ <------- limit
         | Current alt screen | | Lines pulled back  | ^
         |                    | | into primary from  | |- growth = -(number of lines in this section)
         +--------------------+ | history            | V
         +--------------------+ <------- originalLimit
         | Original           |
         | Alt screen         |
         +--------------------+
         */
        if (startPos.absolutePosition >= limit.absolutePosition &&
            startPos.absolutePosition < originalLimit.absolutePosition) {
            // Started in history in the region pulled into primary screen. Advance start to
            // new beginning of alt screen
            startPos = limit;
        } else if (startPos.absolutePosition >= originalLimit.absolutePosition) {
            // Starts after deleted region. Move start position up by number of deleted lines so
            // it refers to the same cell.
            startPos.absolutePosition += growth;
        }
        if (endPos.absolutePosition >= predecessorOfLimit.absolutePosition &&
            endPos.absolutePosition < originalLimit.absolutePosition) {
            // Ended in deleted region. Move end point to just before current alt screen.
            endPos = predecessorOfLimit;
        } else if (endPos.absolutePosition >= originalLimit.absolutePosition) {
            // Ends in alt screen. Move it up to refer to the same cell.
            endPos.absolutePosition += growth;
        }
    }
    if (startPos.absolutePosition >= endPos.absolutePosition + 1) {
        result = NO;
    }
    resultRangePtr->start = [lineBuffer coordinateForPosition:startPos
                                                        width:newWidth
                                                 extendsRight:NO
                                                           ok:NULL];
    int numScrollbackLines = [_mutableState.linebuffer numLinesWithWidth:newWidth];

    // |linesMovedUp| wrapped lines will not be restored into the alt grid later on starting at |limit|
    if (resultRangePtr->start.y >= numScrollbackLines) {
        if (resultRangePtr->start.y < numScrollbackLines + linesMovedUp) {
            // The selection started in one of the lines that was lost. Move it to the
            // first cell of the screen.
            resultRangePtr->start.y = numScrollbackLines;
            resultRangePtr->start.x = 0;
        } else {
            // The selection starts on screen, so move it up by the number of lines by which
            // the alt screen shifted up.
            resultRangePtr->start.y -= linesMovedUp;
        }
    }

    resultRangePtr->end = [lineBuffer coordinateForPosition:endPos
                                                      width:newWidth
                                               extendsRight:YES
                                                         ok:NULL];
    if (resultRangePtr->end.y >= numScrollbackLines) {
        if (resultRangePtr->end.y < numScrollbackLines + linesMovedUp) {
            // The selection ends in one of the lines that was lost. The whole selection is
            // gone.
            result = NO;
        } else {
            // The selection ends on screen, so move it up by the number of lines by which
            // the alt screen shifted up.
            resultRangePtr->end.y -= linesMovedUp;
        }
    }
    if (savedEndPos.extendsToEndOfLine) {
        resultRangePtr->end.x = newWidth;
    } else {
        // Move to the successor of newSelection.end.x, newSelection.end.y.
        resultRangePtr->end.x++;
        if (resultRangePtr->end.x > newWidth) {
            resultRangePtr->end.x -= newWidth;
            resultRangePtr->end.y++;
        }
    }

    return result;
}

- (void)restorePrimaryGridWithLineBuffer:(LineBuffer *)realLineBuffer
                                 oldSize:(VT100GridSize)oldSize
                                 newSize:(VT100GridSize)newSize {
    self.mutablePrimaryGrid.size = newSize;
    [self.mutablePrimaryGrid setCharsFrom:VT100GridCoordMake(0, 0)
                                       to:VT100GridCoordMake(newSize.width - 1, newSize.height - 1)
                                   toChar:_state.primaryGrid.savedDefaultChar
                       externalAttributes:nil];
    // If the height increased:
    // Growing (avoid pulling in stuff from scrollback. Add blank lines
    // at bottom instead). Note there's a little hack here: we use saved_primary_buffer as the default
    // line because it was just initialized with default lines.
    //
    // If the height decreased or stayed the same:
    // Shrinking (avoid pulling in stuff from scrollback, pull in no more
    // than might have been pushed, even if more is available). Note there's a little hack
    // here: we use saved_primary_buffer as the default line because it was just initialized with
    // default lines.
    [self.mutablePrimaryGrid restoreScreenFromLineBuffer:realLineBuffer
                                         withDefaultChar:[_state.primaryGrid defaultChar]
                                       maxLinesToRestore:MIN(oldSize.height, newSize.height)];
}

@end
