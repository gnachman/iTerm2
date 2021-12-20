//
//  VT100Screen+Mutation.m
//  iTerm2Shared
//
//  Created by George Nachman on 12/9/21.
//

// For mysterious reasons this needs to be in the iTerm2XCTests to avoid runtime failures to call
// its methods in tests. If I ever have an appetite for risk try https://stackoverflow.com/a/17581430/321984
#import "VT100Screen+Mutation.h"

#import "DebugLogging.h"
#import "VT100Screen+Private.h"
#import "iTermSelection.h"
#import "iTermTextExtractor.h"
#import "VT100RemoteHost.h"
#import "VT100WorkingDirectory.h"
#import "iTermImageMark.h"
#import "iTermURLMark.h"
#import "iTermAdvancedSettingsModel.h"
#import "NSDictionary+iTerm.h"
#import "CapturedOutput.h"
#import "iTermCapturedOutputMark.h"
#import "iTermCommandHistoryCommandUseMO.h"
#import "iTermShellHistoryController.h"
#import "SearchResult.h"
#import "TmuxStateParser.h"

#include <sys/time.h>

@implementation VT100Screen (Mutation)

- (VT100Grid *)mutableCurrentGrid {
    return (VT100Grid *)_state.currentGrid;
}

- (VT100Grid *)mutableAltGrid {
    return (VT100Grid *)_state.altGrid;
}

- (VT100Grid *)mutablePrimaryGrid {
    return (VT100Grid *)_state.primaryGrid;
}

- (LineBuffer *)mutableLineBuffer {
    return (LineBuffer *)linebuffer_;
}

#pragma mark - Resizing

- (void)mutSetSize:(VT100GridSize)proposedSize {
    VT100GridSize newSize = [self safeSizeForSize:proposedSize];
    if (![self shouldSetSizeTo:newSize]) {
        return;
    }
    [self.mutableLineBuffer beginResizing];
    [self reallySetSize:newSize];
    [self.mutableLineBuffer endResizing];

    if (gDebugLogging) {
        DLog(@"Notes after resizing to width=%@", @(self.width));
        for (PTYNoteViewController *note in _mutableState.intervalTree.allObjects) {
            if (![note isKindOfClass:[PTYNoteViewController class]]) {
                continue;
            }
            DLog(@"Note has coord range %@", VT100GridCoordRangeDescription([self coordRangeForInterval:note.entry.interval]));
        }
        DLog(@"------------ end -----------");
    }
}

- (void)reallySetSize:(VT100GridSize)newSize {
    DLog(@"------------ reallySetSize");
    DLog(@"Set size to %@", VT100GridSizeDescription(newSize));

    const VT100GridRange previouslyVisibleLineRange = [self.delegate screenRangeOfVisibleLines];
    const VT100GridCoordRange previouslyVisibleLines =
        VT100GridCoordRangeMake(0,
                                previouslyVisibleLineRange.location,
                                0,
                                previouslyVisibleLineRange.location + 1);

    [self sanityCheckIntervalsFrom:_state.currentGrid.size note:@"pre-hoc"];
    [self.temporaryDoubleBuffer resetExplicitly];
    const VT100GridSize oldSize = _state.currentGrid.size;
    iTermSelection *selection = [delegate_ screenSelection];
    [self willSetSizeWithSelection:selection];

    const BOOL couldHaveSelection = [delegate_ screenHasView] && selection.hasSelection;
    const int usedHeight = [_state.currentGrid numberOfLinesUsed];

    VT100Grid *copyOfAltGrid = [[self.mutableAltGrid copy] autorelease];
    LineBuffer *realLineBuffer = linebuffer_;

    // This is an array of tuples:
    // [LineBufferPositionRange, iTermSubSelection]
    NSArray *altScreenSubSelectionTuples = nil;
    LineBufferPosition *originalLastPos = [linebuffer_ lastPosition];
    BOOL wasShowingAltScreen = (_state.currentGrid == _state.altGrid);


    // If non-nil, contains 3-tuples NSArray*s of
    // [ PTYNoteViewController*,
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
                                                                 newSize:newSize];
    }

    // Append primary grid to line buffer.
    [self appendScreen:_state.primaryGrid
          toScrollback:linebuffer_
        withUsedHeight:[_state.primaryGrid numberOfLinesUsed]
             newHeight:newSize.height];
    DLog(@"History after appending screen to scrollback:\n%@", [linebuffer_ debugString]);

    VT100GridCoordRange convertedRangeOfVisibleLines;
    const BOOL rangeOfVisibleLinesConvertedCorrectly = [self convertRange:previouslyVisibleLines
                                                                  toWidth:newSize.width
                                                                       to:&convertedRangeOfVisibleLines
                                                             inLineBuffer:linebuffer_
                                                            tolerateEmpty:YES];

    // Contains iTermSubSelection*s updated for the new screen size. Used
    // regardless of whether we were in the alt screen, as it's simply the set
    // of new sub-selections.
    NSArray *newSubSelections = @[];
    if (!wasShowingAltScreen && couldHaveSelection) {
        newSubSelections = [self subSelectionsWithConvertedRangesFromSelection:selection
                                                                      newWidth:newSize.width];
    }

    [self fixUpPrimaryGridIntervalTreeForNewSize:newSize
                             wasShowingAltScreen:wasShowingAltScreen];
    self.mutableCurrentGrid.size = newSize;

    // Restore the screen contents that were pushed onto the linebuffer.
    [self.mutableCurrentGrid restoreScreenFromLineBuffer:wasShowingAltScreen ? altScreenLineBuffer : linebuffer_
                                         withDefaultChar:[_state.currentGrid defaultChar]
                                       maxLinesToRestore:[wasShowingAltScreen ? altScreenLineBuffer : linebuffer_ numLinesWithWidth:_state.currentGrid.size.width]];
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
                                                                            linesMovedUp:[altScreenLineBuffer numLinesWithWidth:_state.currentGrid.size.width]
                                                                            toLineBuffer:realLineBuffer
                                                                      subSelectionTuples:altScreenSubSelectionTuples
                                                                    originalLastPosition:originalLastPos
                                                                                 oldSize:oldSize
                                                                                 newSize:newSize
                                                                              usedHeight:usedHeight
                                                                     intervalTreeObjects:altScreenNotes];
    } else {
        // Was showing primary grid. Fix up notes in the alt screen.
        [self updateAlternateScreenIntervalTreeForNewSize:newSize];
    }

    const int newTop = rangeOfVisibleLinesConvertedCorrectly ? convertedRangeOfVisibleLines.start.y : -1;

    [self didResizeToSize:newSize
                selection:selection
       couldHaveSelection:couldHaveSelection
            subSelections:newSubSelections
                   newTop:newTop];
    [altScreenLineBuffer endResizing];
    [self sanityCheckIntervalsFrom:oldSize note:@"post-hoc"];
    DLog(@"After:\n%@", [_state.currentGrid compactLineDumpWithContinuationMarks]);
    DLog(@"Cursor at %d,%d", _state.currentGrid.cursorX, _state.currentGrid.cursorY);
}

- (void)updateAlternateScreenIntervalTreeForNewSize:(VT100GridSize)newSize {
    // Append alt screen to empty line buffer
    LineBuffer *altScreenLineBuffer = [[[LineBuffer alloc] init] autorelease];
    [altScreenLineBuffer beginResizing];
    [self appendScreen:_state.altGrid
          toScrollback:altScreenLineBuffer
        withUsedHeight:[_state.altGrid numberOfLinesUsed]
             newHeight:newSize.height];
    int numLinesThatWillBeRestored = MIN([altScreenLineBuffer numLinesWithWidth:newSize.width],
                                         newSize.height);
    int numLinesDroppedFromTop = [altScreenLineBuffer numLinesWithWidth:newSize.width] - numLinesThatWillBeRestored;

    // Convert note ranges to new coords, dropping or truncating as needed
    _mutableState.currentGrid = _mutableState.altGrid;  // Swap to alt grid temporarily for convertRange:toWidth:to:inLineBuffer:
    IntervalTree *replacementTree = [[IntervalTree alloc] init];
    for (PTYNoteViewController *note in [_state.savedIntervalTree allObjects]) {
        VT100GridCoordRange noteRange = [self coordRangeForInterval:note.entry.interval];
        DLog(@"Found note at %@", VT100GridCoordRangeDescription(noteRange));
        VT100GridCoordRange newRange;
        if ([self convertRange:noteRange toWidth:newSize.width to:&newRange inLineBuffer:altScreenLineBuffer tolerateEmpty:[self intervalTreeObjectMayBeEmpty:note]]) {
            assert(noteRange.start.y >= 0);
            assert(noteRange.end.y >= 0);
            // Anticipate the lines that will be dropped when the alt grid is restored.
            newRange.start.y += [self totalScrollbackOverflow] - numLinesDroppedFromTop;
            newRange.end.y += [self totalScrollbackOverflow] - numLinesDroppedFromTop;
            if (newRange.start.y < 0) {
                newRange.start.y = 0;
                newRange.start.x = 0;
            }
            DLog(@"  Its new range is %@ including %d lines dropped from top", VT100GridCoordRangeDescription(noteRange), numLinesDroppedFromTop);
            [_mutableState.savedIntervalTree removeObject:note];
            if (newRange.end.y > 0 || (newRange.end.y == 0 && newRange.end.x > 0)) {
                Interval *newInterval = [self intervalForGridCoordRange:newRange
                                                                  width:newSize.width
                                                            linesOffset:0];
                [replacementTree addObject:note withInterval:newInterval];
            } else {
                DLog(@"Failed to convert");
            }
        }
    }
    _mutableState.savedIntervalTree = replacementTree;
    _mutableState.currentGrid = _state.primaryGrid;  // Swap back to primary grid

    // Restore alt screen with new width
    self.mutableAltGrid.size = VT100GridSizeMake(newSize.width, newSize.height);
    [self.mutableAltGrid restoreScreenFromLineBuffer:altScreenLineBuffer
                                     withDefaultChar:[_state.altGrid defaultChar]
                                   maxLinesToRestore:[altScreenLineBuffer numLinesWithWidth:_state.currentGrid.size.width]];
    [altScreenLineBuffer endResizing];
}

- (BOOL)intervalTreeObjectMayBeEmpty:(id)note {
    // These kinds of ranges are allowed to be empty because
    // although they nominally refer to an entire line, sometimes
    // that line is blank such as just before the prompt is
    // printed. See issue 4261.
    return ([note isKindOfClass:[VT100RemoteHost class]] ||
            [note isKindOfClass:[VT100WorkingDirectory class]] ||
            [note isKindOfClass:[iTermImageMark class]] ||
            [note isKindOfClass:[iTermURLMark class]] ||
            [note isKindOfClass:[PTYNoteViewController class]]);
}

- (NSArray *)subSelectionsAfterRestoringPrimaryGridWithCopyOfAltGrid:(VT100Grid *)copyOfAltGrid
                                                        linesMovedUp:(int)linesMovedUp
                                                        toLineBuffer:(LineBuffer *)realLineBuffer
                                                  subSelectionTuples:(NSArray *)altScreenSubSelectionTuples
                                                originalLastPosition:(LineBufferPosition *)originalLastPos
                                                             oldSize:(VT100GridSize)oldSize
                                                             newSize:(VT100GridSize)newSize
                                                          usedHeight:(int)usedHeight
                                                 intervalTreeObjects:(NSArray *)altScreenNotes {
    [self restorePrimaryGridWithLineBuffer:realLineBuffer
                                   oldSize:oldSize
                                   newSize:newSize];

    // Any onscreen notes in primary grid get moved to savedIntervalTree_.
    _mutableState.currentGrid = _state.primaryGrid;
    [self swapNotes];
    _mutableState.currentGrid = _state.altGrid;

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
                                         appendOnlyLineBuffer:appendOnlyLineBuffer];
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

// Swap onscreen notes between intervalTree_ and savedIntervalTree_.
// IMPORTANT: Call -reloadMarkCache after this.
- (void)swapNotes {
    int historyLines = [self numberOfScrollbackLines];
    Interval *origin = [self intervalForGridCoordRange:VT100GridCoordRangeMake(0,
                                                                               historyLines,
                                                                               1,
                                                                               historyLines)];
    IntervalTree *temp = [[[IntervalTree alloc] init] autorelease];
    DLog(@"swapNotes: moving onscreen notes into savedNotes");
    [self moveNotesOnScreenFrom:_mutableState.intervalTree
                             to:temp
                         offset:-origin.location
                   screenOrigin:[self numberOfScrollbackLines]];
    DLog(@"swapNotes: moving onscreen savedNotes into notes");
    [self moveNotesOnScreenFrom:_mutableState.savedIntervalTree
                             to:_mutableState.intervalTree
                         offset:origin.location
                   screenOrigin:0];
    _mutableState.savedIntervalTree = temp;
}

// offset is added to intervals before inserting into interval tree.
- (void)moveNotesOnScreenFrom:(IntervalTree *)source
                           to:(IntervalTree *)dest
                       offset:(long long)offset
                 screenOrigin:(int)screenOrigin {
    VT100GridCoordRange screenRange =
        VT100GridCoordRangeMake(0,
                                screenOrigin,
                                [self width],
                                screenOrigin + self.height);
    DLog(@"  moveNotes: looking in range %@", VT100GridCoordRangeDescription(screenRange));
    Interval *sourceInterval = [self intervalForGridCoordRange:screenRange];
    self.lastCommandMark = nil;
    for (id<IntervalTreeObject> obj in [source objectsInInterval:sourceInterval]) {
        Interval *interval = [[obj.entry.interval retain] autorelease];
        [[obj retain] autorelease];
        DLog(@"  found note with interval %@", interval);
        [source removeObject:obj];
        interval.location = interval.location + offset;
        DLog(@"  new interval is %@", interval);
        [dest addObject:obj withInterval:interval];
    }
}

- (LineBuffer *)prepareToResizeInAlternateScreenMode:(NSArray **)altScreenSubSelectionTuplesPtr
                                 intervalTreeObjects:(NSArray **)altScreenNotesPtr
                                        hasSelection:(BOOL)couldHaveSelection
                                           selection:(iTermSelection *)selection
                                          lineBuffer:(LineBuffer *)realLineBuffer
                                          usedHeight:(int)usedHeight
                                             newSize:(VT100GridSize)newSize {
    if (couldHaveSelection) {
        *altScreenSubSelectionTuplesPtr = [self subSelectionTuplesWithUsedHeight:usedHeight
                                                                       newHeight:newSize.height
                                                                    selection:selection];
    }

    LineBuffer *altScreenLineBuffer = [[[LineBuffer alloc] init] autorelease];
    [altScreenLineBuffer beginResizing];
    [self appendScreen:_state.altGrid
          toScrollback:altScreenLineBuffer
        withUsedHeight:usedHeight
             newHeight:newSize.height];

    if ([_mutableState.intervalTree count]) {
        *altScreenNotesPtr = [self intervalTreeObjectsWithUsedHeight:usedHeight
                                                           newHeight:newSize.height
                                                                grid:_state.altGrid
                                                          lineBuffer:realLineBuffer];
    }

    _mutableState.currentGrid = _state.primaryGrid;
    // Move savedIntervalTree_ into intervalTree_. This should leave savedIntervalTree_ empty.
    [self swapNotes];
    _mutableState.currentGrid = _state.altGrid;

    return altScreenLineBuffer;
}

- (void)fixUpPrimaryGridIntervalTreeForNewSize:(VT100GridSize)newSize
                           wasShowingAltScreen:(BOOL)wasShowingAltScreen {
    if ([_mutableState.intervalTree count]) {
        // Fix up the intervals for the primary grid.
        if (wasShowingAltScreen) {
            // Temporarily swap in primary grid so convertRange: will do the right thing.
            _mutableState.currentGrid = _state.primaryGrid;
        }

        _mutableState.intervalTree = [self replacementIntervalTreeForNewWidth:newSize.width];

        if (wasShowingAltScreen) {
            // Return to alt grid.
            _mutableState.currentGrid = _state.altGrid;
        }
    }
}

- (void)sanityCheckIntervalsFrom:(VT100GridSize)oldSize note:(NSString *)note {
#if BETA
    for (id<IntervalTreeObject> obj in [_mutableState.intervalTree allObjects]) {
        IntervalTreeEntry *entry = obj.entry;
        Interval *interval = entry.interval;
        ITBetaAssert(interval.limit >= 0, @"Bogus interval %@ after resizing from %@ to %@. Note: %@",
                     interval, VT100GridSizeDescription(oldSize), VT100GridSizeDescription(_state.currentGrid.size),
                     note);
    }
#endif
}

- (void)mutSetWidth:(int)width preserveScreen:(BOOL)preserveScreen {
    if ([delegate_ screenShouldInitiateWindowResize] &&
        ![delegate_ screenWindowIsFullscreen]) {
        // set the column
        [delegate_ screenResizeToWidth:width
                                height:_state.currentGrid.size.height];
        if (!preserveScreen) {
            [self mutEraseInDisplayBeforeCursor:YES afterCursor:YES decProtect:NO];  // erase the screen
            self.mutableCurrentGrid.cursorX = 0;
            self.mutableCurrentGrid.cursorY = 0;
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
        [self incrementOverflowBy:linesDropped];
    }
    int lines __attribute__((unused)) = [linebuffer_ numLinesWithWidth:_state.currentGrid.size.width];
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
                                                  self.totalScrollbackOverflow,
                                                  ^(VT100GridCoordRange range) {
                [subSelectionsToAdd addObject:sub];
            });
        }
        [selection addSubSelections:subSelectionsToAdd];
    }

    [self reloadMarkCache];
    [delegate_ screenSizeDidChangeWithNewTopLineAt:newTop];
}

- (BOOL)shouldSetSizeTo:(VT100GridSize)size {
    [self.temporaryDoubleBuffer reset];

    DLog(@"Resize session to %@", VT100GridSizeDescription(size));
    DLog(@"Before:\n%@", [_state.currentGrid compactLineDumpWithContinuationMarks]);
    DLog(@"Cursor at %d,%d", _state.currentGrid.cursorX, _state.currentGrid.cursorY);
    if (_state.commandStartCoord.x != -1) {
        [delegate_ screenCommandDidEndWithRange:[self commandRange]];
        [self mutInvalidateCommandStartCoordWithoutSideEffects];
    }
    self.lastCommandMark = nil;

    if (_state.currentGrid.size.width == 0 ||
        _state.currentGrid.size.height == 0 ||
        (size.width == _state.currentGrid.size.width &&
         size.height == _state.currentGrid.size.height)) {
        return NO;
    }
    return YES;
}

- (VT100GridSize)safeSizeForSize:(VT100GridSize)proposedSize {
    VT100GridSize size;
    size.width = MAX(proposedSize.width, 1);
    size.height = MAX(proposedSize.height, 1);
    return size;
}

- (void)willSetSizeWithSelection:(iTermSelection *)selection {
    if (selection.live) {
        [selection endLiveSelection];
    }
    [selection removeWindowsWithWidth:self.width];
}

- (NSArray *)subSelectionTuplesWithUsedHeight:(int)usedHeight
                                    newHeight:(int)newHeight
                                    selection:(iTermSelection *)selection {
    // In alternate screen mode, get the original positions of the
    // selection. Later this will be used to set the selection positions
    // relative to the end of the updated linebuffer (which could change as
    // lines from the base screen are pushed onto it).
    LineBuffer *lineBufferWithAltScreen = [[linebuffer_ copy] autorelease];
    [self appendScreen:_state.currentGrid
          toScrollback:lineBufferWithAltScreen
        withUsedHeight:usedHeight
             newHeight:newHeight];
    NSMutableArray *altScreenSubSelectionTuples = [NSMutableArray array];
    for (iTermSubSelection *sub in selection.allSubSelections) {
        VT100GridAbsCoordRangeTryMakeRelative(sub.absRange.coordRange,
                                              self.totalScrollbackOverflow,
                                              ^(VT100GridCoordRange range) {
            LineBufferPositionRange *positionRange =
            [self positionRangeForCoordRange:range
                                inLineBuffer:lineBufferWithAltScreen
                               tolerateEmpty:NO];
            if (positionRange) {
                [altScreenSubSelectionTuples addObject:@[ positionRange, sub ]];
            } else {
                DLog(@"Failed to get position range for selection on alt screen %@",
                     VT100GridCoordRangeDescription(range));
            }
        });
    }
    return altScreenSubSelectionTuples;
}

- (NSArray *)intervalTreeObjectsWithUsedHeight:(int)usedHeight
                                     newHeight:(int)newHeight
                                          grid:(VT100Grid *)grid
                                    lineBuffer:(LineBuffer *)realLineBuffer {
    // Add notes that were on the alt grid to altScreenNotes, leaving notes in history alone.
    VT100GridCoordRange screenCoordRange =
    VT100GridCoordRangeMake(0,
                            [self numberOfScrollbackLines],
                            0,
                            [self numberOfScrollbackLines] + self.height);
    NSArray *notesAtLeastPartiallyOnScreen =
    [_mutableState.intervalTree objectsInInterval:[self intervalForGridCoordRange:screenCoordRange]];

    LineBuffer *appendOnlyLineBuffer = [[realLineBuffer copy] autorelease];
    [self appendScreen:grid
          toScrollback:appendOnlyLineBuffer
        withUsedHeight:usedHeight
             newHeight:newHeight];

    NSMutableArray *triples = [NSMutableArray array];

    for (id<IntervalTreeObject> note in notesAtLeastPartiallyOnScreen) {
        VT100GridCoordRange range = [self coordRangeForInterval:note.entry.interval];
        [[note retain] autorelease];
        [_mutableState.intervalTree removeObject:note];
        LineBufferPositionRange *positionRange =
        [self positionRangeForCoordRange:range inLineBuffer:appendOnlyLineBuffer tolerateEmpty:[self intervalTreeObjectMayBeEmpty:note]];
        if (positionRange) {
            DLog(@"Add note on alt screen at %@ (position %@ to %@) to triples",
                 VT100GridCoordRangeDescription(range),
                 positionRange.start,
                 positionRange.end);
            [triples addObject:@[ note, positionRange.start, positionRange.end ]];
        } else {
            DLog(@"Failed to get position range while in alt screen for note %@ with range %@",
                 note, VT100GridCoordRangeDescription(range));
        }
    }
    return triples;
}

- (NSArray *)subSelectionsWithConvertedRangesFromSelection:(iTermSelection *)selection
                                                  newWidth:(int)newWidth {
    NSMutableArray *newSubSelections = [NSMutableArray array];
    const long long overflow = self.totalScrollbackOverflow;
    for (iTermSubSelection *sub in selection.allSubSelections) {
        DLog(@"convert sub %@", sub);
        VT100GridAbsCoordRangeTryMakeRelative(sub.absRange.coordRange,
                                              overflow,
                                              ^(VT100GridCoordRange range) {
            VT100GridCoordRange newSelection;
            const BOOL ok = [self convertRange:range
                                       toWidth:newWidth
                                            to:&newSelection
                                  inLineBuffer:linebuffer_
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

- (IntervalTree *)replacementIntervalTreeForNewWidth:(int)newWidth {
    // Convert ranges of notes to their new coordinates and replace the interval tree.
    IntervalTree *replacementTree = [[[IntervalTree alloc] init] autorelease];
    for (id<IntervalTreeObject> note in [_mutableState.intervalTree allObjects]) {
        VT100GridCoordRange noteRange = [self coordRangeForInterval:note.entry.interval];
        VT100GridCoordRange newRange;
        if (noteRange.end.x < 0 && noteRange.start.y == 0 && noteRange.end.y < 0) {
            // note has scrolled off top
            [_mutableState.intervalTree removeObject:note];
        } else {
            if ([self convertRange:noteRange
                           toWidth:newWidth
                                to:&newRange
                      inLineBuffer:linebuffer_
                     tolerateEmpty:[self intervalTreeObjectMayBeEmpty:note]]) {
                assert(noteRange.start.y >= 0);
                assert(noteRange.end.y >= 0);
                Interval *newInterval = [self intervalForGridCoordRange:newRange
                                                                  width:newWidth
                                                            linesOffset:[self totalScrollbackOverflow]];
                [[note retain] autorelease];
                [_mutableState.intervalTree removeObject:note];
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
                appendOnlyLineBuffer:(LineBuffer *)appendOnlyLineBuffer {
    [self appendScreen:copyOfAltGrid
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
            VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeFromCoordRange(newSelection, self.totalScrollbackOverflow),
                                          0, 0);
            iTermSubSelection *theSub = [iTermSubSelection subSelectionWithAbsRange:theRange
                                                                               mode:originalSub.selectionMode
                                                                              width:self.width];
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
            Interval *interval = [self intervalForGridCoordRange:newRange
                                                           width:newSize.width
                                                     linesOffset:[self totalScrollbackOverflow]];
            [_mutableState.intervalTree addObject:note withInterval:interval];
        } else {
            DLog(@"  *FAILED TO CONVERT*");
        }
    }
}

// This assumes the window's height is going to change to newHeight but _state.currentGrid.size.height
// is still the "old" height. Returns the number of lines appended.
- (int)appendScreen:(VT100Grid *)grid
        toScrollback:(LineBuffer *)lineBufferToUse
      withUsedHeight:(int)usedHeight
           newHeight:(int)newHeight {
    int n;
    if (grid.size.height - newHeight >= usedHeight) {
        // Height is decreasing but pushing HEIGHT lines into the buffer would scroll all the used
        // lines off the top, leaving the cursor floating without any text. Keep all used lines that
        // fit onscreen.
        n = MAX(usedHeight, newHeight);
    } else {
        if (newHeight < grid.size.height) {
            // Screen is shrinking.
            // If possible, keep the last used line a fixed distance from the top of
            // the screen. If not, at least save all the used lines.
            n = usedHeight;
        } else {
            // Screen is not shrinking in height. New content may be brought in on top.
            n = grid.size.height;
        }
    }
    [grid appendLines:n toLineBuffer:lineBufferToUse];

    return n;
}

static BOOL XYIsBeforeXY(int px1, int py1, int px2, int py2) {
    if (py1 == py2) {
        return px1 < px2;
    } else if (py1 < py2) {
        return YES;
    } else {
        return NO;
    }
}

static void SwapInt(int *a, int *b) {
    int temp = *a;
    *a = *b;
    *b = temp;
}

- (BOOL)trimSelectionFromStart:(VT100GridCoord)start
                           end:(VT100GridCoord)end
                      toStartX:(VT100GridCoord *)startPtr
                        toEndX:(VT100GridCoord *)endPtr {
    if (start.x < 0 || end.x < 0 ||
        start.y < 0 || end.y < 0) {
        *startPtr = start;
        *endPtr = end;
        return YES;
    }

    if (!XYIsBeforeXY(start.x, start.y, end.x, end.y)) {
        SwapInt(&start.x, &end.x);
        SwapInt(&start.y, &end.y);
    }

    // Advance start position until it hits a non-null or equals the end position.
    int startX = start.x;
    int startY = start.y;
    if (startX == _state.currentGrid.size.width) {
        startX = 0;
        startY++;
    }

    int endX = end.x;
    int endY = end.y;
    if (endX == _state.currentGrid.size.width) {
        endX = 0;
        endY++;
    }

    VT100GridRun run = VT100GridRunFromCoords(VT100GridCoordMake(startX, startY),
                                              VT100GridCoordMake(endX, endY),
                                              _state.currentGrid.size.width);
    if (run.length <= 0) {
        DLog(@"Run has length %@ given start and end of %@ and %@", @(run.length), VT100GridCoordDescription(start),
             VT100GridCoordDescription(end));
        return NO;
    }
    run = [self runByTrimmingNullsFromRun:run];
    if (run.length == 0) {
        DLog(@"After trimming, run has length 0 given start and end of %@ and %@", VT100GridCoordDescription(start),
             VT100GridCoordDescription(end));
        return NO;
    }
    VT100GridCoord max = VT100GridRunMax(run, _state.currentGrid.size.width);

    *startPtr = run.origin;
    *endPtr = max;
    return YES;
}

- (LineBufferPositionRange *)positionRangeForCoordRange:(VT100GridCoordRange)range
                                           inLineBuffer:(LineBuffer *)lineBuffer
                                          tolerateEmpty:(BOOL)tolerateEmpty {
    assert(range.end.y >= 0);
    assert(range.start.y >= 0);

    LineBufferPositionRange *positionRange = [[[LineBufferPositionRange alloc] init] autorelease];

    BOOL endExtends = NO;
    // Use the predecessor of endx,endy so it will have a legal position in the line buffer.
    if (range.end.x == [self width]) {
        const screen_char_t *line = [self getLineAtIndex:range.end.y];
        if (line[range.end.x - 1].code == 0 && line[range.end.x].code == EOL_HARD) {
            // The selection goes all the way to the end of the line and there is a null at the
            // end of the line, so it extends to the end of the line. The linebuffer can't recover
            // this from its position because the trailing null in the line wouldn't be in the
            // linebuffer.
            endExtends = YES;
        }
    }
    range.end.x--;
    if (range.end.x < 0) {
        range.end.y--;
        range.end.x = [self width] - 1;
        if (range.end.y < 0) {
            return nil;
        }
    }

    if (range.start.x < 0 || range.start.y < 0 ||
        range.end.x < 0 || range.end.y < 0) {
        return nil;
    }

    VT100GridCoord trimmedStart;
    VT100GridCoord trimmedEnd;
    BOOL ok = [self trimSelectionFromStart:VT100GridCoordMake(range.start.x, range.start.y)
                                       end:VT100GridCoordMake(range.end.x, range.end.y)
                                  toStartX:&trimmedStart
                                    toEndX:&trimmedEnd];
    if (!ok) {
        if (tolerateEmpty) {
            trimmedStart = trimmedEnd = range.start;
        } else {
            return nil;
        }
    }
    if (VT100GridCoordOrder(trimmedStart, trimmedEnd) == NSOrderedDescending) {
        if (tolerateEmpty) {
            trimmedStart = trimmedEnd = range.start;
        } else {
            return nil;
        }
    }

    positionRange.start = [lineBuffer positionForCoordinate:trimmedStart
                                                      width:_state.currentGrid.size.width
                                                     offset:0];
    positionRange.end = [lineBuffer positionForCoordinate:trimmedEnd
                                                    width:_state.currentGrid.size.width
                                                   offset:0];
    positionRange.end.extendsToEndOfLine = endExtends;

    if (positionRange.start && positionRange.end) {
        return positionRange;
    } else {
        return nil;
    }
}

- (BOOL)convertRange:(VT100GridCoordRange)range
             toWidth:(int)newWidth
                  to:(VT100GridCoordRange *)resultPtr
        inLineBuffer:(LineBuffer *)lineBuffer
       tolerateEmpty:(BOOL)tolerateEmpty {
    if (range.start.y < 0 || range.end.y < 0) {
        return NO;
    }
    LineBufferPositionRange *selectionRange;

    // Temporarily swap in the passed-in linebuffer so the call below can access lines in the right line buffer.
    LineBuffer *savedLineBuffer = linebuffer_;
    linebuffer_ = lineBuffer;
    selectionRange = [self positionRangeForCoordRange:range inLineBuffer:lineBuffer tolerateEmpty:tolerateEmpty];
    DLog(@"%@ -> %@", VT100GridCoordRangeDescription(range), selectionRange);
    linebuffer_ = savedLineBuffer;
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
// NOTE: This assumes that linebuffer_ contains the history plus lines from the primary grid.
// Returns YES if the range is valid, NO if it could not be converted (e.g., because it was entirely
// in the area of dropped lines).
/*
 * 0 History      }                                                                     }
 * 1 History      } These lines were in history before resizing began                   }
 * 2 History      }                    <- originalLimit                                 } equal to linebuffer_
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
    int numScrollbackLines = [linebuffer_ numLinesWithWidth:newWidth];

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

#pragma mark - FinalTerm

- (void)mutPromptDidStartAt:(VT100GridAbsCoord)coord {
    DLog(@"FinalTerm: mutPromptDidStartAt");
    if (coord.x > 0 && [delegate_ screenShouldPlacePromptAtFirstColumn]) {
        [self crlf];
    }
    _mutableState.shellIntegrationInstalled = YES;

    _mutableState.lastCommandOutputRange = VT100GridAbsCoordRangeMake(_state.startOfRunningCommandOutput.x,
                                                                      _state.startOfRunningCommandOutput.y,
                                                                      coord.x,
                                                                      coord.y);
    _mutableState.currentPromptRange = VT100GridAbsCoordRangeMake(coord.x,
                                                                  coord.y,
                                                                  coord.x,
                                                                  coord.y);

    // FinalTerm uses this to define the start of a collapsible region. That would be a nightmare
    // to add to iTerm, and our answer to this is marks, which already existed anyway.
    [delegate_ screenPromptDidStartAtLine:[self numberOfScrollbackLines] + self.cursorY - 1];
    if ([iTermAdvancedSettingsModel resetSGROnPrompt]) {
        [_mutableState.terminal resetGraphicRendition];
    }
}

- (void)mutSetLastCommandOutputRange:(VT100GridAbsCoordRange)lastCommandOutputRange {
    _mutableState.lastCommandOutputRange = lastCommandOutputRange;
}

- (void)mutCommandDidStart {
    DLog(@"FinalTerm: terminalCommandDidStart");
    _mutableState.currentPromptRange = VT100GridAbsCoordRangeMake(_state.currentPromptRange.start.x,
                                                                  _state.currentPromptRange.start.y,
                                                                  _state.currentGrid.cursor.x,
                                                                  _state.currentGrid.cursor.y + self.numberOfScrollbackLines + self.totalScrollbackOverflow);
    [self commandDidStartAtScreenCoord:_state.currentGrid.cursor];
    [delegate_ screenPromptDidEndAtLine:[self numberOfScrollbackLines] + self.cursorY - 1];
}

- (void)mutCommandDidEnd {
    DLog(@"FinalTerm: terminalCommandDidEnd");
    _mutableState.currentPromptRange = VT100GridAbsCoordRangeMake(0, 0, 0, 0);

    [self commandDidEndAtAbsCoord:VT100GridAbsCoordMake(_state.currentGrid.cursor.x, _state.currentGrid.cursor.y + [self numberOfScrollbackLines] + [self totalScrollbackOverflow])];
}

- (BOOL)mutCommandDidEndAtAbsCoord:(VT100GridAbsCoord)coord {
    if (_state.commandStartCoord.x != -1) {
        [delegate_ screenCommandDidEndWithRange:[self commandRange]];
        [self mutInvalidateCommandStartCoord];
        _mutableState.startOfRunningCommandOutput = coord;
        return YES;
    }
    return NO;
}

#pragma mark - Interval Tree

- (id<iTermMark>)mutAddMarkStartingAtAbsoluteLine:(long long)line
                                          oneLine:(BOOL)oneLine
                                          ofClass:(Class)markClass {
    id<iTermMark> mark = [[[markClass alloc] init] autorelease];
    if ([mark isKindOfClass:[VT100ScreenMark class]]) {
        VT100ScreenMark *screenMark = mark;
        screenMark.delegate = self;
        screenMark.sessionGuid = [delegate_ screenSessionGuid];
    }
    long long totalOverflow = [self totalScrollbackOverflow];
    if (line < totalOverflow || line > totalOverflow + self.numberOfLines) {
        return nil;
    }
    int nonAbsoluteLine = line - totalOverflow;
    VT100GridCoordRange range;
    if (oneLine) {
        range = VT100GridCoordRangeMake(0, nonAbsoluteLine, self.width, nonAbsoluteLine);
    } else {
        // Interval is whole screen
        int limit = nonAbsoluteLine + self.height - 1;
        if (limit >= [self numberOfScrollbackLines] + [_state.currentGrid numberOfLinesUsed]) {
            limit = [self numberOfScrollbackLines] + [_state.currentGrid numberOfLinesUsed] - 1;
        }
        range = VT100GridCoordRangeMake(0,
                                        nonAbsoluteLine,
                                        self.width,
                                        limit);
    }
    if ([mark isKindOfClass:[VT100ScreenMark class]]) {
        _mutableState.markCache[@([self totalScrollbackOverflow] + range.end.y)] = mark;
    }
    [_mutableState.intervalTree addObject:mark withInterval:[self intervalForGridCoordRange:range]];
    [self.intervalTreeObserver intervalTreeDidAddObjectOfType:[self intervalTreeObserverTypeForObject:mark]
                                                       onLine:range.start.y + self.totalScrollbackOverflow];
    [delegate_ screenNeedsRedraw];
    return mark;
}

- (void)reloadMarkCache {
    long long totalScrollbackOverflow = [self totalScrollbackOverflow];
    [_mutableState.markCache removeAllObjects];
    for (id<IntervalTreeObject> obj in [_mutableState.intervalTree allObjects]) {
        if ([obj isKindOfClass:[VT100ScreenMark class]]) {
            VT100GridCoordRange range = [self coordRangeForInterval:obj.entry.interval];
            VT100ScreenMark *mark = (VT100ScreenMark *)obj;
            _mutableState.markCache[@(totalScrollbackOverflow + range.end.y)] = mark;
        }
    }
    [self.intervalTreeObserver intervalTreeDidReset];
}

- (void)mutAddNote:(PTYNoteViewController *)note
           inRange:(VT100GridCoordRange)range {
    [_mutableState.intervalTree addObject:note withInterval:[self intervalForGridCoordRange:range]];
    [self.mutableCurrentGrid markAllCharsDirty:YES];
    note.delegate = self;
    [delegate_ screenDidAddNote:note];
    [self.intervalTreeObserver intervalTreeDidAddObjectOfType:iTermIntervalTreeObjectTypeAnnotation
                                                       onLine:range.start.y + self.totalScrollbackOverflow];
}

- (void)mutCommandWasAborted {
    VT100ScreenMark *screenMark = [self lastCommandMark];
    if (screenMark) {
        DLog(@"Removing last command mark %@", screenMark);
        [self.intervalTreeObserver intervalTreeDidRemoveObjectOfType:[self intervalTreeObserverTypeForObject:screenMark]
                                                              onLine:[self coordRangeForInterval:screenMark.entry.interval].start.y + self.totalScrollbackOverflow];
        [_mutableState.intervalTree removeObject:screenMark];
    }
    [self mutInvalidateCommandStartCoordWithoutSideEffects];
    [delegate_ screenCommandDidEndWithRange:VT100GridCoordRangeMake(-1, -1, -1, -1)];
}

- (void)mutRemoveObjectFromIntervalTree:(id<IntervalTreeObject>)obj {
    long long totalScrollbackOverflow = [self totalScrollbackOverflow];
    if ([obj isKindOfClass:[VT100ScreenMark class]]) {
        long long theKey = (totalScrollbackOverflow +
                            [self coordRangeForInterval:obj.entry.interval].end.y);
        [_mutableState.markCache removeObjectForKey:@(theKey)];
        self.lastCommandMark = nil;
    }
    [_mutableState.intervalTree removeObject:obj];
    iTermIntervalTreeObjectType type = [self intervalTreeObserverTypeForObject:obj];
    if (type != iTermIntervalTreeObjectTypeUnknown) {
        VT100GridCoordRange range = [self coordRangeForInterval:obj.entry.interval];
        [self.intervalTreeObserver intervalTreeDidRemoveObjectOfType:type
                                                              onLine:range.start.y + self.totalScrollbackOverflow];
    }
}

- (void)removePromptMarksBelowLine:(int)line {
    VT100ScreenMark *mark = [self lastPromptMark];
    if (!mark) {
        return;
    }

    VT100GridCoordRange range = [self coordRangeForInterval:mark.entry.interval];
    while (range.start.y >= line) {
        if (mark == self.lastCommandMark) {
            self.lastCommandMark = nil;
        }
        [self mutRemoveObjectFromIntervalTree:mark];
        mark = [self lastPromptMark];
        if (!mark) {
            return;
        }
        range = [self coordRangeForInterval:mark.entry.interval];
    }
}

- (void)mutRemoveNote:(PTYNoteViewController *)note {
    if ([_state.intervalTree containsObject:note]) {
        self.lastCommandMark = nil;
        [[note retain] autorelease];
        [_mutableState.intervalTree removeObject:note];
        [self.intervalTreeObserver intervalTreeDidRemoveObjectOfType:[self intervalTreeObserverTypeForObject:note]
                                                              onLine:[self coordRangeForInterval:note.entry.interval].start.y + self.totalScrollbackOverflow];
    } else if ([_state.savedIntervalTree containsObject:note]) {
        self.lastCommandMark = nil;
        [_mutableState.savedIntervalTree removeObject:note];
    }
    [delegate_ screenNeedsRedraw];
    [delegate_ screenDidEndEditingNote];
}

#pragma mark - Clearing

- (void)mutClearBuffer {
    [self mutClearBufferSavingPrompt:YES];
}

- (void)mutClearBufferSavingPrompt:(BOOL)savePrompt {
    // Cancel out the current command if shell integration is in use and we are
    // at the shell prompt.

    const int linesToSave = savePrompt ? [self numberOfLinesToPreserveWhenClearingScreen] : 0;
    // NOTE: This is in screen coords (y=0 is the top)
    VT100GridCoord newCommandStart = VT100GridCoordMake(-1, -1);
    if (_state.commandStartCoord.x >= 0) {
        // Compute the new location of the command's beginning, which is right
        // after the end of the prompt in its new location.
        int numberOfPromptLines = 1;
        if (!VT100GridAbsCoordEquals(_state.currentPromptRange.start, _state.currentPromptRange.end)) {
            numberOfPromptLines = MAX(1, _state.currentPromptRange.end.y - _state.currentPromptRange.start.y + 1);
        }
        newCommandStart = VT100GridCoordMake(_state.commandStartCoord.x, numberOfPromptLines - 1);

        // Abort the current command.
        [self mutCommandWasAborted];
    }
    // There is no last command after clearing the screen, so reset it.
    _mutableState.lastCommandOutputRange = VT100GridAbsCoordRangeMake(-1, -1, -1, -1);

    // Clear the grid by scrolling it up into history.
    [self clearAndResetScreenSavingLines:linesToSave];
    // Erase history.
    [self mutClearScrollbackBuffer];

    // Redraw soon.
    [delegate_ screenUpdateDisplay:NO];

    if (savePrompt && newCommandStart.x >= 0) {
        // Create a new mark and inform the delegate that there's new command start coord.
        [delegate_ screenPromptDidStartAtLine:[self numberOfScrollbackLines]];
        [self commandDidStartAtScreenCoord:newCommandStart];
    }
    [_mutableState.terminal resetSavedCursorPositions];
}

- (int)numberOfLinesToPreserveWhenClearingScreen {
    if (VT100GridAbsCoordEquals(_state.currentPromptRange.start, _state.currentPromptRange.end)) {
        // Prompt range not defined.
        return 1;
    }
    if (_state.commandStartCoord.x < 0) {
        // Prompt apparently hasn't ended.
        return 1;
    }
    VT100ScreenMark *lastCommandMark = [self lastPromptMark];
    if (!lastCommandMark) {
        // Never had a mark.
        return 1;
    }

    VT100GridCoordRange lastCommandMarkRange = [self coordRangeForInterval:lastCommandMark.entry.interval];
    int cursorLine = self.cursorY - 1 + self.numberOfScrollbackLines;
    int cursorMarkOffset = cursorLine - lastCommandMarkRange.start.y;
    return 1 + cursorMarkOffset;
}

// This clears the screen, leaving the cursor's line at the top and preserves the cursor's x
// coordinate. Scroll regions and the saved cursor position are reset.
- (void)clearAndResetScreenSavingLines:(int)linesToSave {
    [delegate_ screenTriggerableChangeDidOccur];
    // This clears the screen.
    int x = _state.currentGrid.cursorX;
    [self incrementOverflowBy:[self.mutableCurrentGrid resetWithLineBuffer:linebuffer_
                                                       unlimitedScrollback:_state.unlimitedScrollback
                                                        preserveCursorLine:linesToSave > 0
                                                     additionalLinesToSave:MAX(0, linesToSave - 1)]];
    self.mutableCurrentGrid.cursorX = x;
    self.mutableCurrentGrid.cursorY = linesToSave - 1;
}

- (void)mutClearScrollbackBuffer {
    [linebuffer_ release];
    linebuffer_ = [[LineBuffer alloc] init];
    [self.mutableLineBuffer setMaxLines:_state.maxScrollbackLines];
    [delegate_ screenClearHighlights];
    [self.mutableCurrentGrid markAllCharsDirty:YES];

    _mutableState.savedFindContextAbsPos = 0;

    [self resetScrollbackOverflow];
    [delegate_ screenRemoveSelection];
    [self.mutableCurrentGrid markAllCharsDirty:YES];
    _mutableState.intervalTree = [[[IntervalTree alloc] init] autorelease];
    [self reloadMarkCache];
    self.lastCommandMark = nil;
    [delegate_ screenDidClearScrollbackBuffer:self];
    [delegate_ screenRefreshFindOnPageView];
}

- (void)clearScrollbackBufferFromLine:(int)line {
    const int width = self.width;
    const int scrollbackLines = [linebuffer_ numberOfWrappedLinesWithWidth:width];
    if (scrollbackLines < line) {
        return;
    }
    [self.mutableLineBuffer removeLastWrappedLines:scrollbackLines - line
                                             width:width];
}

- (void)mutResetTimestamps {
    [self.mutablePrimaryGrid resetTimestamps];
    [self.mutableAltGrid resetTimestamps];
}

- (void)mutRemoveLastLine {
    DLog(@"BEGIN removeLastLine with cursor at %@", VT100GridCoordDescription(self.currentGrid.cursor));
    const int preHocNumberOfLines = [linebuffer_ numberOfWrappedLinesWithWidth:self.width];
    const int numberOfLinesAppended = [self.mutableCurrentGrid appendLines:self.currentGrid.numberOfLinesUsed
                                                              toLineBuffer:linebuffer_];
    if (numberOfLinesAppended <= 0) {
        return;
    }
    [self.mutableCurrentGrid setCharsFrom:VT100GridCoordMake(0, 0)
                                       to:VT100GridCoordMake(self.width - 1,
                                                             self.height - 1)
                                   toChar:self.currentGrid.defaultChar
                       externalAttributes:nil];
    [self.mutableLineBuffer removeLastRawLine];
    const int postHocNumberOfLines = [linebuffer_ numberOfWrappedLinesWithWidth:self.width];
    const int numberOfLinesToPop = MAX(0, postHocNumberOfLines - preHocNumberOfLines);

    [self.mutableCurrentGrid restoreScreenFromLineBuffer:linebuffer_
                                         withDefaultChar:[self.currentGrid defaultChar]
                                       maxLinesToRestore:numberOfLinesToPop];
    // One of the lines "removed" will be the one the cursor is on. Don't need to move it up for
    // that one.
    const int adjustment = self.currentGrid.cursorX > 0 ? 1 : 0;
    self.mutableCurrentGrid.cursorX = 0;
    const int numberOfLinesRemoved = MAX(0, numberOfLinesAppended - numberOfLinesToPop);
    const int y = MAX(0, self.currentGrid.cursorY - numberOfLinesRemoved + adjustment);
    DLog(@"numLinesAppended=%@ numLinesToPop=%@ numLinesRemoved=%@ adjustment=%@ y<-%@",
          @(numberOfLinesAppended), @(numberOfLinesToPop), @(numberOfLinesRemoved), @(adjustment), @(y));
    self.mutableCurrentGrid.cursorY = y;
    DLog(@"Cursor at %@", VT100GridCoordDescription(self.currentGrid.cursor));
}

- (void)mutClearFromAbsoluteLineToEnd:(long long)absLine {
    const VT100GridCoord cursorCoord = VT100GridCoordMake(_state.currentGrid.cursor.x,
                                                          _state.currentGrid.cursor.y + self.numberOfScrollbackLines);
    const long long totalScrollbackOverflow = self.totalScrollbackOverflow;
    const VT100GridAbsCoord absCursorCoord = VT100GridAbsCoordFromCoord(cursorCoord, totalScrollbackOverflow);
    iTermTextExtractor *extractor = [[[iTermTextExtractor alloc] initWithDataSource:self] autorelease];
    const VT100GridWindowedRange cursorLineRange = [extractor rangeForWrappedLineEncompassing:cursorCoord
                                                                         respectContinuations:YES
                                                                                     maxChars:100000];
    ScreenCharArray *savedLine = [extractor combinedLinesInRange:NSMakeRange(cursorLineRange.coordRange.start.y,
                                                                             cursorLineRange.coordRange.end.y - cursorLineRange.coordRange.start.y + 1)];
    savedLine = [savedLine screenCharArrayByRemovingTrailingNullsAndHardNewline];

    const long long firstScreenAbsLine = self.numberOfScrollbackLines + totalScrollbackOverflow;
    [self clearGridFromLineToEnd:MAX(0, absLine - firstScreenAbsLine)];

    [self clearScrollbackBufferFromLine:absLine - self.totalScrollbackOverflow];
    const VT100GridCoordRange coordRange = VT100GridCoordRangeMake(0,
                                                                   absLine - totalScrollbackOverflow,
                                                                   self.width,
                                                                   self.numberOfScrollbackLines + self.height);


    Interval *intervalToClear = [self intervalForGridCoordRange:coordRange];
    NSMutableArray<id<IntervalTreeObject>> *marksToMove = [NSMutableArray array];
    for (id<IntervalTreeObject> obj in [_mutableState.intervalTree objectsInInterval:intervalToClear]) {
        const VT100GridCoordRange markRange = [self coordRangeForInterval:obj.entry.interval];
        if (VT100GridCoordRangeContainsCoord(cursorLineRange.coordRange, markRange.start)) {
            [marksToMove addObject:obj];
        } else {
            [self mutRemoveObjectFromIntervalTree:obj];
        }
    }

    if (absCursorCoord.y >= absLine) {
        Interval *cursorLineInterval = [self intervalForGridCoordRange:cursorLineRange.coordRange];
        for (id<IntervalTreeObject> obj in [_mutableState.intervalTree objectsInInterval:cursorLineInterval]) {
            if ([marksToMove containsObject:obj]) {
                continue;
            }
            [marksToMove addObject:obj];
        }

        // Cursor was among the cleared lines. Restore the line content.
        self.mutableCurrentGrid.cursor = VT100GridCoordMake(0, absLine - totalScrollbackOverflow - self.numberOfScrollbackLines);
        [self mutAppendScreenChars:savedLine.line
                            length:savedLine.length
            externalAttributeIndex:savedLine.metadata.externalAttributes
                      continuation:savedLine.continuation];

        // Restore marks on that line.
        const long long numberOfLinesRemoved = absCursorCoord.y - absLine;
        if (numberOfLinesRemoved > 0) {
            [marksToMove enumerateObjectsUsingBlock:^(id<IntervalTreeObject>  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                // Make an interval shifted up by `numberOfLinesRemoved`
                VT100GridCoordRange range = [self coordRangeForInterval:obj.entry.interval];
                range.start.y -= numberOfLinesRemoved;
                range.end.y -= numberOfLinesRemoved;
                Interval *interval = [self intervalForGridCoordRange:range];

                // Remove and re-add the object with the new interval.
                [self mutRemoveObjectFromIntervalTree:obj];
                [_mutableState.intervalTree addObject:obj withInterval:interval];
                [self.intervalTreeObserver intervalTreeDidAddObjectOfType:[self intervalTreeObserverTypeForObject:obj]
                                                                   onLine:range.start.y + totalScrollbackOverflow];
            }];
        }
    } else {
        [marksToMove enumerateObjectsUsingBlock:^(id<IntervalTreeObject>  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [self mutRemoveObjectFromIntervalTree:obj];
        }];
    }
    [self reloadMarkCache];
    [delegate_ screenRemoveSelection];
    [delegate_ screenNeedsRedraw];
}

- (void)clearGridFromLineToEnd:(int)line {
    assert(line >= 0 && line < self.height);
    const VT100GridCoord savedCursor = self.currentGrid.cursor;
    self.mutableCurrentGrid.cursor = VT100GridCoordMake(0, line);
    [self removeSoftEOLBeforeCursor];
    const VT100GridRun run = VT100GridRunFromCoords(VT100GridCoordMake(0, line),
                                                    VT100GridCoordMake(self.width, self.height),
                                                    self.width);
    [self.mutableCurrentGrid setCharsInRun:run toChar:0 externalAttributes:nil];
    [delegate_ screenTriggerableChangeDidOccur];
    self.mutableCurrentGrid.cursor = savedCursor;
}

- (void)mutResetPreservingPrompt:(BOOL)preservePrompt modifyContent:(BOOL)modifyContent {
    if (modifyContent) {
        const int linesToSave = [self numberOfLinesToPreserveWhenClearingScreen];
        [delegate_ screenTriggerableChangeDidOccur];
        if (preservePrompt) {
            [self clearAndResetScreenSavingLines:linesToSave];
        } else {
            [self incrementOverflowBy:[self.mutableCurrentGrid resetWithLineBuffer:linebuffer_
                                                               unlimitedScrollback:_state.unlimitedScrollback
                                                                preserveCursorLine:NO
                                                             additionalLinesToSave:0]];
        }
    }

    [self mutSetInitialTabStops];

    for (int i = 0; i < NUM_CHARSETS; i++) {
        [self mutSetCharacterSet:i usesLineDrawingMode:NO];
    }
    [delegate_ screenDidResetAllowingContentModification:modifyContent];
    [self mutInvalidateCommandStartCoordWithoutSideEffects];
    [self showCursor:YES];
}

- (void)mutSetLeftMargin:(int)scrollLeft rightMargin:(int)scrollRight {
    if (_state.currentGrid.useScrollRegionCols) {
        self.mutableCurrentGrid.scrollRegionCols = VT100GridRangeMake(scrollLeft,
                                                                      scrollRight - scrollLeft + 1);
        // set cursor to the home position
        [self mutCursorToX:1 Y:1];
    }
}

- (void)mutEraseScreenAndRemoveSelection {
    // Unconditionally clear the whole screen, regardless of cursor position.
    // This behavior changed in the Great VT100Grid Refactoring of 2013. Before, clearScreen
    // used to move the cursor's wrapped line to the top of the screen. It's only used from
    // DECSET 1049, and neither xterm nor terminal have this behavior, and I'm not sure why it
    // would be desirable anyway. Like xterm (and unlike Terminal) we leave the cursor put.
    [delegate_ screenRemoveSelection];
    [self.mutableCurrentGrid setCharsFrom:VT100GridCoordMake(0, 0)
                                       to:VT100GridCoordMake(_state.currentGrid.size.width - 1,
                                                             _state.currentGrid.size.height - 1)
                                   toChar:[_state.currentGrid defaultChar]
                       externalAttributes:nil];
}


#pragma mark - Appending

- (void)mutAppendStringAtCursor:(NSString *)string {
    int len = [string length];
    if (len < 1 || !string) {
        return;
    }

    unichar firstChar =  [string characterAtIndex:0];

    DLog(@"appendStringAtCursor: %ld chars starting with %c at x=%d, y=%d, line=%d",
         (unsigned long)len,
         firstChar,
         _state.currentGrid.cursorX,
         _state.currentGrid.cursorY,
         _state.currentGrid.cursorY + [linebuffer_ numLinesWithWidth:_state.currentGrid.size.width]);

    // Allocate a buffer of screen_char_t and place the new string in it.
    const int kStaticBufferElements = 1024;
    screen_char_t staticBuffer[kStaticBufferElements];
    screen_char_t *dynamicBuffer = 0;
    screen_char_t *buffer;
    string = StringByNormalizingString(string, self.normalization);
    len = [string length];
    if (3 * len >= kStaticBufferElements) {
        buffer = dynamicBuffer = (screen_char_t *) iTermCalloc(3 * len,
                                                               sizeof(screen_char_t));
        assert(buffer);
        if (!buffer) {
            NSLog(@"%s: Out of memory", __PRETTY_FUNCTION__);
            return;
        }
    } else {
        buffer = staticBuffer;
    }

    // `predecessorIsDoubleWidth` will be true if the cursor is over a double-width character
    // but NOT if it's over a DWC_RIGHT.
    BOOL predecessorIsDoubleWidth = NO;
    VT100GridCoord pred = [_state.currentGrid coordinateBefore:_state.currentGrid.cursor
                                movedBackOverDoubleWidth:&predecessorIsDoubleWidth];
    NSString *augmentedString = string;
    NSString *predecessorString = pred.x >= 0 ? [_state.currentGrid stringForCharacterAt:pred] : nil;
    const BOOL augmented = predecessorString != nil;
    if (augmented) {
        augmentedString = [predecessorString stringByAppendingString:string];
    } else {
        // Prepend a space so we can detect if the first character is a combining mark.
        augmentedString = [@" " stringByAppendingString:string];
    }

    assert(_state.terminal);
    // Add DWC_RIGHT after each double-byte character, build complex characters out of surrogates
    // and combining marks, replace private codes with replacement characters, swallow zero-
    // width spaces, and set fg/bg colors and attributes.
    BOOL dwc = NO;
    StringToScreenChars(augmentedString,
                        buffer,
                        [_state.terminal foregroundColorCode],
                        [_state.terminal backgroundColorCode],
                        &len,
                        [delegate_ screenShouldTreatAmbiguousCharsAsDoubleWidth],
                        NULL,
                        &dwc,
                        self.normalization,
                        [delegate_ screenUnicodeVersion]);
    ssize_t bufferOffset = 0;
    if (augmented && len > 0) {
        screen_char_t *theLine = [self getLineAtScreenIndex:pred.y];
        theLine[pred.x].code = buffer[0].code;
        theLine[pred.x].complexChar = buffer[0].complexChar;
        bufferOffset++;

        // Does the augmented result begin with a double-width character? If so skip over the
        // DWC_RIGHT when appending. I *think* this is redundant with the `predecessorIsDoubleWidth`
        // test but I'm reluctant to remove it because it could break something.
        const BOOL augmentedResultBeginsWithDoubleWidthCharacter = (augmented &&
                                                                    len > 1 &&
                                                                    buffer[1].code == DWC_RIGHT &&
                                                                    !buffer[1].complexChar);
        if ((augmentedResultBeginsWithDoubleWidthCharacter || predecessorIsDoubleWidth) && len > 1 && buffer[1].code == DWC_RIGHT) {
            // Skip over a preexisting DWC_RIGHT in the predecessor.
            bufferOffset++;
        }
    } else if (!buffer[0].complexChar) {
        // We infer that the first character in |string| was not a combining mark. If it were, it
        // would have combined with the space we added to the start of |augmentedString|. Skip past
        // the space.
        bufferOffset++;
    }

    if (dwc) {
        self.mutableLineBuffer.mayHaveDoubleWidthCharacter = dwc;
    }
    [self mutAppendScreenCharArrayAtCursor:buffer + bufferOffset
                                    length:len - bufferOffset
                    externalAttributeIndex:[iTermUniformExternalAttributes withAttribute:_state.terminal.externalAttributes]];
    if (buffer == dynamicBuffer) {
        free(buffer);
    }
}

- (void)mutAppendScreenCharArrayAtCursor:(const screen_char_t *)buffer
                                  length:(int)len
                  externalAttributeIndex:(id<iTermExternalAttributeIndexReading>)externalAttributes {
    if (len >= 1) {
        screen_char_t lastCharacter = buffer[len - 1];
        if (lastCharacter.code == DWC_RIGHT && !lastCharacter.complexChar) {
            // Last character is the right half of a double-width character. Use the penultimate character instead.
            if (len >= 2) {
                _mutableState.lastCharacter = buffer[len - 2];
                _mutableState.lastCharacterIsDoubleWidth = YES;
                _mutableState.lastExternalAttribute = [externalAttributes[len - 2] retain];
            }
        } else {
            // Record the last character.
            _mutableState.lastCharacter = buffer[len - 1];
            _mutableState.lastCharacterIsDoubleWidth = NO;
            _mutableState.lastExternalAttribute = [externalAttributes[len] retain];
        }
        LineBuffer *lineBuffer = nil;
        if (_state.currentGrid != _state.altGrid || _state.saveToScrollbackInAlternateScreen) {
            // Not in alt screen or it's ok to scroll into line buffer while in alt screen.k
            lineBuffer = linebuffer_;
        }
        [self incrementOverflowBy:[self.mutableCurrentGrid appendCharsAtCursor:buffer
                                                                        length:len
                                                       scrollingIntoLineBuffer:lineBuffer
                                                           unlimitedScrollback:_state.unlimitedScrollback
                                                       useScrollbackWithRegion:self.appendToScrollbackWithStatusBar
                                                                    wraparound:_state.wraparoundMode
                                                                          ansi:_state.ansi
                                                                        insert:_state.insert
                                                        externalAttributeIndex:externalAttributes]];
        iTermImmutableMetadata temp;
        iTermImmutableMetadataInit(&temp, 0, externalAttributes);
        [delegate_ screenAppendScreenCharArray:buffer
                                      metadata:temp
                                        length:len];
        iTermImmutableMetadataRelease(temp);
    }

    if (_state.commandStartCoord.x != -1) {
        [delegate_ screenCommandDidChangeWithRange:[self commandRange]];
    }
}

- (void)appendSessionRestoredBanner {
    // Save graphic rendition. Set to system message color.
    const VT100GraphicRendition saved = _state.terminal.graphicRendition;

    VT100GraphicRendition temp = saved;
    temp.fgColorMode = ColorModeAlternate;
    temp.fgColorCode = ALTSEM_SYSTEM_MESSAGE;
    temp.bgColorMode = ColorModeAlternate;
    temp.bgColorCode = ALTSEM_SYSTEM_MESSAGE;
    _state.terminal.graphicRendition = temp;

    // Record the cursor position and append the message.
    const int yBefore = _state.currentGrid.cursor.y;
    if (_state.currentGrid.cursor.x > 0) {
        [self mutCrlf];
    }
    [self mutEraseLineBeforeCursor:YES afterCursor:YES decProtect:NO];
    NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
    dateFormatter.dateStyle = NSDateFormatterMediumStyle;
    dateFormatter.timeStyle = NSDateFormatterShortStyle;
    NSString *message = [NSString stringWithFormat:@"Session Contents Restored on %@", [dateFormatter stringFromDate:[NSDate date]]];
    [self mutAppendStringAtCursor:message];
    self.mutableCurrentGrid.cursorX = 0;
    self.mutableCurrentGrid.preferredCursorPosition = _state.currentGrid.cursor;

    // Restore the graphic rendition, add a newline, and calculate how far down the cursor moved.
    _state.terminal.graphicRendition = saved;
    [self mutCrlf];
    const int delta = _state.currentGrid.cursor.y - yBefore;

    // Update the preferred cursor position if needed.
    if (_state.currentGrid.preferredCursorPosition.y >= 0 && _state.currentGrid.preferredCursorPosition.y + 1 < _state.currentGrid.size.height) {
        VT100GridCoord coord = _state.currentGrid.preferredCursorPosition;
        coord.y = MAX(0, MIN(_state.currentGrid.size.height - 1, coord.y + delta));
        self.mutableCurrentGrid.preferredCursorPosition = coord;
    }
}

- (void)mutAppendScreenChars:(const screen_char_t *)line
                   length:(int)length
   externalAttributeIndex:(id<iTermExternalAttributeIndexReading>)externalAttributeIndex
             continuation:(screen_char_t)continuation {
    [self mutAppendScreenCharArrayAtCursor:line
                                    length:length
                    externalAttributeIndex:externalAttributeIndex];
    if (continuation.code == EOL_HARD) {
        [self mutCarriageReturn];
        [self mutLinefeed];
    }
}

- (void)mutAppendAsciiDataAtCursor:(AsciiData *)asciiData {
    int len = asciiData->length;
    if (len < 1 || !asciiData) {
        return;
    }
    STOPWATCH_START(appendAsciiDataAtCursor);
    char firstChar = asciiData->buffer[0];

    DLog(@"appendAsciiDataAtCursor: %ld chars starting with %c at x=%d, y=%d, line=%d",
         (unsigned long)len,
         firstChar,
         _state.currentGrid.cursorX,
         _state.currentGrid.cursorY,
         _state.currentGrid.cursorY + [linebuffer_ numLinesWithWidth:_state.currentGrid.size.width]);

    screen_char_t *buffer;
    buffer = asciiData->screenChars->buffer;

    screen_char_t fg = [_state.terminal foregroundColorCode];
    screen_char_t bg = [_state.terminal backgroundColorCode];
    iTermExternalAttribute *ea = [_state.terminal externalAttributes];

    screen_char_t zero = { 0 };
    if (memcmp(&fg, &zero, sizeof(fg)) || memcmp(&bg, &zero, sizeof(bg))) {
        STOPWATCH_START(setUpScreenCharArray);
        for (int i = 0; i < len; i++) {
            CopyForegroundColor(&buffer[i], fg);
            CopyBackgroundColor(&buffer[i], bg);
        }
        STOPWATCH_LAP(setUpScreenCharArray);
    }

    // If a graphics character set was selected then translate buffer
    // characters into graphics characters.
    if ([_state.charsetUsesLineDrawingMode containsObject:@(_state.terminal.charset)]) {
        ConvertCharsToGraphicsCharset(buffer, len);
    }

    [self mutAppendScreenCharArrayAtCursor:buffer
                                    length:len
                    externalAttributeIndex:[iTermUniformExternalAttributes withAttribute:ea]];
    STOPWATCH_LAP(appendAsciiDataAtCursor);
}

#pragma mark - Arrangements

- (void)mutSetContentsFromLineBuffer:(LineBuffer *)lineBuffer {
    [self mutClearBuffer];
    [self.mutableLineBuffer appendContentsOfLineBuffer:lineBuffer width:_state.currentGrid.size.width];
    const int numberOfLines = [self numberOfLines];
    [self.mutableCurrentGrid restoreScreenFromLineBuffer:linebuffer_
                                         withDefaultChar:[self.currentGrid defaultChar]
                                       maxLinesToRestore:MIN(numberOfLines, self.height)];
}

- (void)mutSetHistory:(NSArray *)history {
    // This is way more complicated than it should be to work around something dumb in tmux.
    // It pads lines in its history with trailing spaces, which we'd like to trim. More importantly,
    // we need to trim empty lines at the end of the history because that breaks how we move the
    // screen contents around on resize. So we take the history from tmux, append it to a temporary
    // line buffer, grab each wrapped line and trim spaces from it, and then append those modified
    // line (excluding empty ones at the end) to the real line buffer.
    [self mutClearBuffer];
    LineBuffer *temp = [[[LineBuffer alloc] init] autorelease];
    temp.mayHaveDoubleWidthCharacter = YES;
    self.mutableLineBuffer.mayHaveDoubleWidthCharacter = YES;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    // TODO(externalAttributes): Add support for external attributes here. This is only used by tmux at the moment.
    iTermMetadata metadata;
    iTermMetadataInit(&metadata, now, nil);
    for (NSData *chars in history) {
        screen_char_t *line = (screen_char_t *) [chars bytes];
        const int len = [chars length] / sizeof(screen_char_t);
        screen_char_t continuation;
        if (len) {
            continuation = line[len - 1];
            continuation.code = EOL_HARD;
        } else {
            memset(&continuation, 0, sizeof(continuation));
        }
        [temp appendLine:line
                  length:len
                 partial:NO
                   width:_state.currentGrid.size.width
                metadata:iTermMetadataMakeImmutable(metadata)
            continuation:continuation];
    }
    NSMutableArray *wrappedLines = [NSMutableArray array];
    int n = [temp numLinesWithWidth:_state.currentGrid.size.width];
    int numberOfConsecutiveEmptyLines = 0;
    for (int i = 0; i < n; i++) {
        ScreenCharArray *line = [temp wrappedLineAtIndex:i
                                                   width:_state.currentGrid.size.width
                                            continuation:NULL];
        if (line.eol == EOL_HARD) {
            [self stripTrailingSpaceFromLine:line];
            if (line.length == 0) {
                ++numberOfConsecutiveEmptyLines;
            } else {
                numberOfConsecutiveEmptyLines = 0;
            }
        } else {
            numberOfConsecutiveEmptyLines = 0;
        }
        [wrappedLines addObject:line];
    }
    for (int i = 0; i < n - numberOfConsecutiveEmptyLines; i++) {
        ScreenCharArray *line = [wrappedLines objectAtIndex:i];
        screen_char_t continuation = { 0 };
        if (line.length) {
            continuation = line.line[line.length - 1];
        }
        [self.mutableLineBuffer appendLine:line.line
                                    length:line.length
                                   partial:(line.eol != EOL_HARD)
                                     width:_state.currentGrid.size.width
                                  metadata:iTermMetadataMakeImmutable(metadata)
                              continuation:continuation];
    }
    if (!_state.unlimitedScrollback) {
        [self.mutableLineBuffer dropExcessLinesWithWidth:_state.currentGrid.size.width];
    }

    // We don't know the cursor position yet but give the linebuffer something
    // so it doesn't get confused in restoreScreenFromScrollback.
    [self.mutableLineBuffer setCursor:0];
    [self.mutableCurrentGrid restoreScreenFromLineBuffer:linebuffer_
                                         withDefaultChar:[_state.currentGrid defaultChar]
                                       maxLinesToRestore:MIN([linebuffer_ numLinesWithWidth:_state.currentGrid.size.width],
                                                             _state.currentGrid.size.height - numberOfConsecutiveEmptyLines)];
}

- (void)stripTrailingSpaceFromLine:(ScreenCharArray *)line {
    const screen_char_t *p = line.line;
    int len = line.length;
    for (int i = len - 1; i >= 0; i--) {
        // TODO: When I add support for URLs to tmux, don't pass 0 here - pass the URL code instead.
        if (p[i].code == ' ' && ScreenCharHasDefaultAttributesAndColors(p[i], 0)) {
            len--;
        } else {
            break;
        }
    }
    line.length = len;
}

- (void)mutSetAltScreen:(NSArray *)lines {
    self.mutableLineBuffer.mayHaveDoubleWidthCharacter = YES;
    if (!_state.altGrid) {
        _mutableState.altGrid = [[self.mutablePrimaryGrid copy] autorelease];
    }

    // Initialize alternate screen to be empty
    [self.mutableAltGrid setCharsFrom:VT100GridCoordMake(0, 0)
                                   to:VT100GridCoordMake(_state.altGrid.size.width - 1, _state.altGrid.size.height - 1)
                               toChar:[_state.altGrid defaultChar]
        externalAttributes:nil];
    // Copy the lines back over it
    int o = 0;
    for (int i = 0; o < _state.altGrid.size.height && i < MIN(lines.count, _state.altGrid.size.height); i++) {
        NSData *chars = [lines objectAtIndex:i];
        screen_char_t *line = (screen_char_t *) [chars bytes];
        int length = [chars length] / sizeof(screen_char_t);

        do {
            // Add up to _state.altGrid.size.width characters at a time until they're all used.
            screen_char_t *dest = [self.mutableAltGrid screenCharsAtLineNumber:o];
            memcpy(dest, line, MIN(_state.altGrid.size.width, length) * sizeof(screen_char_t));
            const BOOL isPartial = (length > _state.altGrid.size.width);
            dest[_state.altGrid.size.width] = dest[_state.altGrid.size.width - 1];  // TODO: This is probably wrong?
            dest[_state.altGrid.size.width].code = (isPartial ? EOL_SOFT : EOL_HARD);
            length -= _state.altGrid.size.width;
            line += _state.altGrid.size.width;
            o++;
        } while (o < _state.altGrid.size.height && length > 0);
    }
}

- (int)mutNumberOfLinesDroppedWhenEncodingContentsIncludingGrid:(BOOL)includeGrid
                                                        encoder:(id<iTermEncoderAdapter>)encoder
                                                 intervalOffset:(long long *)intervalOffsetPtr {
    // We want 10k lines of history at 80 cols, and fewer for small widths, to keep the size
    // reasonable.
    const int maxLines80 = [iTermAdvancedSettingsModel maxHistoryLinesToRestore];
    const int effectiveWidth = self.width ?: 80;
    const int maxArea = maxLines80 * (includeGrid ? 80 : effectiveWidth);
    const int maxLines = MAX(1000, maxArea / effectiveWidth);

    // Make a copy of the last blocks of the line buffer; enough to contain at least |maxLines|.
    LineBuffer *temp = [[linebuffer_ copyWithMinimumLines:maxLines
                                                  atWidth:effectiveWidth] autorelease];

    // Offset for intervals so 0 is the first char in the provided contents.
    int linesDroppedForBrevity = ([linebuffer_ numLinesWithWidth:effectiveWidth] -
                                  [temp numLinesWithWidth:effectiveWidth]);
    long long intervalOffset =
        -(linesDroppedForBrevity + [self totalScrollbackOverflow]) * (self.width + 1);

    if (includeGrid) {
        int numLines;
        if ([iTermAdvancedSettingsModel runJobsInServers]) {
            numLines = _state.currentGrid.size.height;
        } else {
            numLines = [_state.currentGrid numberOfLinesUsed];
        }
        [self.mutableCurrentGrid appendLines:numLines toLineBuffer:temp];
    }

    [temp encode:encoder maxLines:maxLines80];
    *intervalOffsetPtr = intervalOffset;
    return linesDroppedForBrevity;
}

#warning This method is an unusual mutator because it has to be on the main thread and it's probably always during initialization.

- (void)mutRestoreFromDictionary:(NSDictionary *)dictionary
        includeRestorationBanner:(BOOL)includeRestorationBanner
                   knownTriggers:(NSArray *)triggers
                      reattached:(BOOL)reattached {
    if (!_state.altGrid) {
        _mutableState.altGrid = [[_state.primaryGrid copy] autorelease];
    }
    NSDictionary *screenState = dictionary[kScreenStateKey];
    if (screenState) {
        if ([screenState[kScreenStateCurrentGridIsPrimaryKey] boolValue]) {
            _mutableState.currentGrid = _state.primaryGrid;
        } else {
            _mutableState.currentGrid = _state.altGrid;
        }
    }

    const BOOL newFormat = (dictionary[@"PrimaryGrid"] != nil);
    if (!newFormat) {
        LineBuffer *lineBuffer = [[LineBuffer alloc] initWithDictionary:dictionary];
        [lineBuffer setMaxLines:_state.maxScrollbackLines + self.height];
        if (!_state.unlimitedScrollback) {
            [lineBuffer dropExcessLinesWithWidth:self.width];
        }
        [linebuffer_ release];
        linebuffer_ = lineBuffer;
        int maxLinesToRestore;
        if ([iTermAdvancedSettingsModel runJobsInServers] && reattached) {
            maxLinesToRestore = _state.currentGrid.size.height;
        } else {
            maxLinesToRestore = _state.currentGrid.size.height - 1;
        }
        const int linesRestored = MIN(MAX(0, maxLinesToRestore),
                                [lineBuffer numLinesWithWidth:self.width]);
        BOOL setCursorPosition = [self.mutableCurrentGrid restoreScreenFromLineBuffer:linebuffer_
                                                                      withDefaultChar:[_state.currentGrid defaultChar]
                                                                    maxLinesToRestore:linesRestored];
        DLog(@"appendFromDictionary: Grid size is %dx%d", _state.currentGrid.size.width, _state.currentGrid.size.height);
        DLog(@"Restored %d wrapped lines from dictionary", [self numberOfScrollbackLines] + linesRestored);
        DLog(@"setCursorPosition=%@", @(setCursorPosition));
        if (!setCursorPosition) {
            VT100GridCoord coord;
            if (VT100GridCoordFromDictionary(screenState[kScreenStateCursorCoord], &coord)) {
                // The initial size of this session might be smaller than its eventual size.
                // Save the coord because after the window is set to its correct size it might be
                // possible to place the cursor in this position.
                self.mutableCurrentGrid.preferredCursorPosition = coord;
                DLog(@"Save preferred cursor position %@", VT100GridCoordDescription(coord));
                if (coord.x >= 0 &&
                    coord.y >= 0 &&
                    coord.x <= self.width &&
                    coord.y < self.height) {
                    DLog(@"Also set the cursor to this position");
                    self.mutableCurrentGrid.cursor = coord;
                    setCursorPosition = YES;
                }
            }
        }
        if (!setCursorPosition) {
            DLog(@"Place the cursor on the first column of the last line");
            self.mutableCurrentGrid.cursorY = linesRestored + 1;
            self.mutableCurrentGrid.cursorX = 0;
        }
        // Reduce line buffer's max size to not include the grid height. This is its final state.
        [lineBuffer setMaxLines:_state.maxScrollbackLines];
        if (!_state.unlimitedScrollback) {
            [lineBuffer dropExcessLinesWithWidth:self.width];
        }
    } else if (screenState) {
        // New format
        const BOOL onPrimary = (_state.currentGrid == _state.primaryGrid);
        self.mutablePrimaryGrid.delegate = nil;
        self.mutableAltGrid.delegate = nil;
        _mutableState.altGrid = nil;

        _mutableState.primaryGrid = [[[VT100Grid alloc] initWithDictionary:dictionary[@"PrimaryGrid"]
                                                                  delegate:self] autorelease];
        if (!_state.primaryGrid) {
            // This is to prevent a crash if the dictionary is bad (i.e., non-backward compatible change in a future version).
            _mutableState.primaryGrid = [[[VT100Grid alloc] initWithSize:VT100GridSizeMake(2, 2) delegate:self] autorelease];
        }
        if ([dictionary[@"AltGrid"] count]) {
            _mutableState.altGrid = [[[VT100Grid alloc] initWithDictionary:dictionary[@"AltGrid"]
                                                                  delegate:self] autorelease];
        }
        if (!_state.altGrid) {
            _mutableState.altGrid = [[[VT100Grid alloc] initWithSize:_state.primaryGrid.size delegate:self] autorelease];
        }
        if (onPrimary || includeRestorationBanner) {
            _mutableState.currentGrid = _state.primaryGrid;
        } else {
            _mutableState.currentGrid = _state.altGrid;
        }

        LineBuffer *lineBuffer = [[LineBuffer alloc] initWithDictionary:dictionary[@"LineBuffer"]];
        [lineBuffer setMaxLines:_state.maxScrollbackLines + self.height];
        if (!_state.unlimitedScrollback) {
            [lineBuffer dropExcessLinesWithWidth:self.width];
        }
        [linebuffer_ release];
        linebuffer_ = lineBuffer;
    }
    BOOL addedBanner = NO;
    if (includeRestorationBanner && [iTermAdvancedSettingsModel showSessionRestoredBanner]) {
        [self appendSessionRestoredBanner];
        addedBanner = YES;
    }

    if (screenState) {
        _mutableState.protectedMode = [screenState[kScreenStateProtectedMode] unsignedIntegerValue];
        [_mutableState.tabStops removeAllObjects];
        [_mutableState.tabStops addObjectsFromArray:screenState[kScreenStateTabStopsKey]];

        [_state.terminal setStateFromDictionary:screenState[kScreenStateTerminalKey]];
        NSArray<NSNumber *> *array = screenState[kScreenStateLineDrawingModeKey];
        for (int i = 0; i < NUM_CHARSETS && i < array.count; i++) {
            [self mutSetCharacterSet:i usesLineDrawingMode:array[i].boolValue];
        }

        if (!newFormat) {
            // Legacy content format restoration
            VT100Grid *otherGrid = (_state.currentGrid == _state.primaryGrid) ? _state.altGrid : _state.primaryGrid;
            LineBuffer *otherLineBuffer = [[[LineBuffer alloc] initWithDictionary:screenState[kScreenStateNonCurrentGridKey]] autorelease];
            [otherGrid restoreScreenFromLineBuffer:otherLineBuffer
                                   withDefaultChar:[_state.altGrid defaultChar]
                                 maxLinesToRestore:_state.altGrid.size.height];
            VT100GridCoord savedCursor = _state.primaryGrid.cursor;
            [self.mutablePrimaryGrid setStateFromDictionary:screenState[kScreenStatePrimaryGridStateKey]];
            if (addedBanner && _state.currentGrid.preferredCursorPosition.x < 0 && _state.currentGrid.preferredCursorPosition.y < 0) {
                self.mutablePrimaryGrid.cursor = savedCursor;
            }
            [self.mutableAltGrid setStateFromDictionary:screenState[kScreenStateAlternateGridStateKey]];
        }

        NSString *guidOfLastCommandMark = screenState[kScreenStateLastCommandMarkKey];
        if (reattached) {
            [self mutSetCommandStartCoordWithoutSideEffects:VT100GridAbsCoordMake([screenState[kScreenStateCommandStartXKey] intValue],
                                                                                  [screenState[kScreenStateCommandStartYKey] longLongValue])];
            _mutableState.startOfRunningCommandOutput = [screenState[kScreenStateNextCommandOutputStartKey] gridAbsCoord];
        }
        _mutableState.cursorVisible = [screenState[kScreenStateCursorVisibleKey] boolValue];
        self.trackCursorLineMovement = [screenState[kScreenStateTrackCursorLineMovementKey] boolValue];
        _mutableState.lastCommandOutputRange = [screenState[kScreenStateLastCommandOutputRangeKey] gridAbsCoordRange];
        _mutableState.shellIntegrationInstalled = [screenState[kScreenStateShellIntegrationInstalledKey] boolValue];


        if (!newFormat) {
            _initialSize = self.size;
            // Change the size to how big it was when state was saved so that
            // interval trees can be fixed up properly when it is set back later by
            // restoreInitialSize. Interval tree ranges cannot be interpreted
            // outside the context of the data they annotate because when an
            // annotation affects all the trailing nulls on a line, the length of
            // that annotation is dependent on the screen size and how text laid
            // out (maybe there are no nulls after reflow!).
            VT100GridSize savedSize = [VT100Grid sizeInStateDictionary:screenState[kScreenStatePrimaryGridStateKey]];
            [self mutSetSize:savedSize];
        }
        _mutableState.intervalTree = [[[IntervalTree alloc] initWithDictionary:screenState[kScreenStateIntervalTreeKey]] autorelease];
        [self fixUpDeserializedIntervalTree:_mutableState.intervalTree
                              knownTriggers:triggers
                                    visible:YES
                      guidOfLastCommandMark:guidOfLastCommandMark];

        _mutableState.savedIntervalTree = [[[IntervalTree alloc] initWithDictionary:screenState[kScreenStateSavedIntervalTreeKey]] autorelease];
        [self fixUpDeserializedIntervalTree:_mutableState.savedIntervalTree
                              knownTriggers:triggers
                                    visible:NO
                      guidOfLastCommandMark:guidOfLastCommandMark];

        [self reloadMarkCache];
        [self.delegate screenSendModifiersDidChange];

        if (gDebugLogging) {
            DLog(@"Notes after restoring with width=%@", @(self.width));
            for (PTYNoteViewController *note in _mutableState.intervalTree.allObjects) {
                if (![note isKindOfClass:[PTYNoteViewController class]]) {
                    continue;
                }
                DLog(@"Note has coord range %@", VT100GridCoordRangeDescription([self coordRangeForInterval:note.entry.interval]));
            }
            DLog(@"------------ end -----------");
        }
    }
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

// Link references to marks in CapturedOutput (for the lines where output was captured) to the deserialized mark.
// Link marks for commands to CommandUse objects in command history.
// Notify delegate of PTYNoteViewControllers so they get added as subviews, and set the delegate of not view controllers to self.
- (void)fixUpDeserializedIntervalTree:(IntervalTree *)intervalTree
                        knownTriggers:(NSArray *)triggers
                              visible:(BOOL)visible
                guidOfLastCommandMark:(NSString *)guidOfLastCommandMark {
    VT100RemoteHost *lastRemoteHost = nil;
    NSMutableDictionary *markGuidToCapturedOutput = [NSMutableDictionary dictionary];
    for (NSArray *objects in [intervalTree forwardLimitEnumerator]) {
        for (id<IntervalTreeObject> object in objects) {
            if ([object isKindOfClass:[VT100RemoteHost class]]) {
                lastRemoteHost = object;
            } else if ([object isKindOfClass:[VT100ScreenMark class]]) {
                VT100ScreenMark *screenMark = (VT100ScreenMark *)object;
                screenMark.delegate = self;
                // If |capturedOutput| is not empty then this mark is a command, some of whose output
                // was captured. The iTermCapturedOutputMarks will come later so save the GUIDs we need
                // in markGuidToCapturedOutput and they'll get backfilled when found.
                for (CapturedOutput *capturedOutput in screenMark.capturedOutput) {
                    [capturedOutput setKnownTriggers:triggers];
                    if (capturedOutput.markGuid) {
                        markGuidToCapturedOutput[capturedOutput.markGuid] = capturedOutput;
                    }
                }
                if (screenMark.command) {
                    // Find the matching object in command history and link it.
                    iTermCommandHistoryCommandUseMO *commandUse =
                        [[iTermShellHistoryController sharedInstance] commandUseWithMarkGuid:screenMark.guid
                                                                                      onHost:lastRemoteHost];
                    commandUse.mark = screenMark;
                }
                if ([screenMark.guid isEqualToString:guidOfLastCommandMark]) {
                    self.lastCommandMark = screenMark;
                }
            } else if ([object isKindOfClass:[iTermCapturedOutputMark class]]) {
                // This mark represents a line whose output was captured. Find the preceding command
                // mark that has a CapturedOutput corresponding to this mark and fill it in.
                iTermCapturedOutputMark *capturedOutputMark = (iTermCapturedOutputMark *)object;
                CapturedOutput *capturedOutput = markGuidToCapturedOutput[capturedOutputMark.guid];
                capturedOutput.mark = capturedOutputMark;
            } else if ([object isKindOfClass:[PTYNoteViewController class]]) {
                PTYNoteViewController *note = (PTYNoteViewController *)object;
                note.delegate = self;
                if (visible) {
                    [delegate_ screenDidAddNote:note];
                }
            } else if ([object isKindOfClass:[iTermImageMark class]]) {
                iTermImageMark *imageMark = (iTermImageMark *)object;
                ScreenCharClearProvisionalFlagForImageWithCode(imageMark.imageCode.intValue);
            }
        }
    }
}

#pragma mark - Tmux Integration

- (void)mutSetTmuxState:(NSDictionary *)state {
    BOOL inAltScreen = [[self objectInDictionary:state
                                withFirstKeyFrom:[NSArray arrayWithObjects:kStateDictSavedGrid,
                                                  kStateDictSavedGrid,
                                                  nil]] intValue];
    if (inAltScreen) {
        // Alt and primary have been populated with each other's content.
        id<VT100GridReading> temp = _state.altGrid;
        _mutableState.altGrid = _state.primaryGrid;
        _mutableState.primaryGrid = temp;
    }

    NSNumber *altSavedX = [state objectForKey:kStateDictAltSavedCX];
    NSNumber *altSavedY = [state objectForKey:kStateDictAltSavedCY];
    if (altSavedX && altSavedY && inAltScreen) {
        self.mutablePrimaryGrid.cursor = VT100GridCoordMake([altSavedX intValue], [altSavedY intValue]);
        [_state.terminal setSavedCursorPosition:_state.primaryGrid.cursor];
    }

    self.mutableCurrentGrid.cursorX = [[state objectForKey:kStateDictCursorX] intValue];
    self.mutableCurrentGrid.cursorY = [[state objectForKey:kStateDictCursorY] intValue];
    int top = [[state objectForKey:kStateDictScrollRegionUpper] intValue];
    int bottom = [[state objectForKey:kStateDictScrollRegionLower] intValue];
    self.mutableCurrentGrid.scrollRegionRows = VT100GridRangeMake(top, bottom - top + 1);
    [self showCursor:[[state objectForKey:kStateDictCursorMode] boolValue]];

    [_mutableState.tabStops removeAllObjects];
    int maxTab = 0;
    for (NSNumber *n in [state objectForKey:kStateDictTabstops]) {
        [_mutableState.tabStops addObject:n];
        maxTab = MAX(maxTab, [n intValue]);
    }
    for (int i = 0; i < 1000; i += 8) {
        if (i > maxTab) {
            [_mutableState.tabStops addObject:[NSNumber numberWithInt:i]];
        }
    }

    NSNumber *cursorMode = [state objectForKey:kStateDictCursorMode];
    if (cursorMode) {
        [self terminalSetCursorVisible:!![cursorMode intValue]];
    }

    // Everything below this line needs testing
    NSNumber *insertMode = [state objectForKey:kStateDictInsertMode];
    if (insertMode) {
        [_mutableState.terminal setInsertMode:!![insertMode intValue]];
    }

    NSNumber *applicationCursorKeys = [state objectForKey:kStateDictKCursorMode];
    if (applicationCursorKeys) {
        [_mutableState.terminal setCursorMode:!![applicationCursorKeys intValue]];
    }

    NSNumber *keypad = [state objectForKey:kStateDictKKeypadMode];
    if (keypad) {
        [_mutableState.terminal setKeypadMode:!![keypad boolValue]];
    }

    NSNumber *mouse = [state objectForKey:kStateDictMouseStandardMode];
    if (mouse && [mouse intValue]) {
        [_mutableState.terminal setMouseMode:MOUSE_REPORTING_NORMAL];
    }
    mouse = [state objectForKey:kStateDictMouseButtonMode];
    if (mouse && [mouse intValue]) {
        [_mutableState.terminal setMouseMode:MOUSE_REPORTING_BUTTON_MOTION];
    }
    mouse = [state objectForKey:kStateDictMouseButtonMode];
    if (mouse && [mouse intValue]) {
        [_mutableState.terminal setMouseMode:MOUSE_REPORTING_ALL_MOTION];
    }

    // NOTE: You can get both SGR and UTF8 set. In that case SGR takes priority. See comment in
    // tmux's input_key_get_mouse()
    mouse = [state objectForKey:kStateDictMouseSGRMode];
    if (mouse && [mouse intValue]) {
        [_mutableState.terminal setMouseFormat:MOUSE_FORMAT_SGR];
    } else {
        mouse = [state objectForKey:kStateDictMouseUTF8Mode];
        if (mouse && [mouse intValue]) {
            [_mutableState.terminal setMouseFormat:MOUSE_FORMAT_XTERM_EXT];
        }
    }

    NSNumber *wrap = [state objectForKey:kStateDictWrapMode];
    if (wrap) {
        [_mutableState.terminal setWraparoundMode:!![wrap intValue]];
    }
}

- (id)objectInDictionary:(NSDictionary *)dict withFirstKeyFrom:(NSArray *)keys {
    for (NSString *key in keys) {
        NSObject *object = [dict objectForKey:key];
        if (object) {
            return object;
        }
    }
    return nil;
}

#pragma mark - Terminal Fundamentals

- (void)mutSetProtectedMode:(VT100TerminalProtectedMode)mode {
    _mutableState.protectedMode = mode;
}

- (void)mutSetCursorVisible:(BOOL)visible {
    if (visible != _state.cursorVisible) {
        _mutableState.cursorVisible = visible;
        if (visible) {
            [self.temporaryDoubleBuffer reset];
        } else {
            [self.temporaryDoubleBuffer start];
        }
    }
    [delegate_ screenSetCursorVisible:visible];
}

- (void)mutSetCharacterSet:(int)charset usesLineDrawingMode:(BOOL)lineDrawingMode {
    if (lineDrawingMode) {
        [_mutableState.charsetUsesLineDrawingMode addObject:@(charset)];
    } else {
        [_mutableState.charsetUsesLineDrawingMode removeObject:@(charset)];
    }
}

- (void)mutSetInitialTabStops {
    [_mutableState.tabStops removeAllObjects];
    const int kInitialTabWindow = 1000;
    const int width = [iTermAdvancedSettingsModel defaultTabStopWidth];
    for (int i = 0; i < kInitialTabWindow; i += width) {
        [_mutableState.tabStops addObject:[NSNumber numberWithInt:i]];
    }
}

- (void)mutCrlf {
    [self mutLinefeed];
    self.mutableCurrentGrid.cursorX = 0;
}

- (void)mutLinefeed {
    LineBuffer *lineBufferToUse = linebuffer_;
    const BOOL noScrollback = (_state.currentGrid == _state.altGrid && !_state.saveToScrollbackInAlternateScreen);
    if (noScrollback) {
        // In alt grid but saving to scrollback in alt-screen is off, so pass in a nil linebuffer.
        lineBufferToUse = nil;
    }
    [self incrementOverflowBy:[self.mutableCurrentGrid moveCursorDownOneLineScrollingIntoLineBuffer:lineBufferToUse
                                                                                unlimitedScrollback:_state.unlimitedScrollback
                                                                            useScrollbackWithRegion:self.appendToScrollbackWithStatusBar
                                                                                         willScroll:^{
        if (noScrollback) {
            // This is a temporary hack. In this case, keeping the selection in the right place requires
            // more cooperation between VT100Screen and PTYTextView than is currently in place because
            // the selection could become truncated, and regardless, will need to move up a line in terms
            // of absolute Y position (normally when the screen scrolls the absolute Y position of the
            // selection stays the same and the viewport moves down, or else there is some scrollback
            // overflow and PTYTextView -refresh bumps the selection's Y position, but because in this
            // case we don't append to the line buffer, scrollback overflow will not increment).
            [delegate_ screenRemoveSelection];
        }
    }]];
}

- (BOOL)cursorOutsideTopBottomMargin {
    return (_state.currentGrid.cursorY < _state.currentGrid.topMargin ||
            _state.currentGrid.cursorY > _state.currentGrid.bottomMargin);
}

- (void)mutCursorToX:(int)x Y:(int)y {
    [self mutCursorToX:x];
    [self mutCursorToY:y];
    DebugLog(@"cursorToX:Y");
}

- (void)mutCursorToX:(int)x {
    const int leftMargin = [_state.currentGrid leftMargin];
    const int rightMargin = [_state.currentGrid rightMargin];

    int xPos = x - 1;

    if ([_state.terminal originMode]) {
        xPos += leftMargin;
        xPos = MAX(leftMargin, MIN(rightMargin, xPos));
    }

    self.mutableCurrentGrid.cursorX = xPos;

    DebugLog(@"cursorToX");
}

- (void)mutCursorToY:(int)y {
    int yPos;
    int topMargin = _state.currentGrid.topMargin;
    int bottomMargin = _state.currentGrid.bottomMargin;

    yPos = y - 1;

    if ([_state.terminal originMode]) {
        yPos += topMargin;
        yPos = MAX(topMargin, MIN(bottomMargin, yPos));
    }
    self.mutableCurrentGrid.cursorY = yPos;

    DebugLog(@"cursorToY");

}

- (void)mutDoBackspace {
    int leftMargin = _state.currentGrid.leftMargin;
    int rightMargin = _state.currentGrid.rightMargin;
    int cursorX = _state.currentGrid.cursorX;
    int cursorY = _state.currentGrid.cursorY;

    if (cursorX >= self.width && _state.terminal.reverseWraparoundMode && _state.terminal.wraparoundMode) {
        // Reverse-wrap when past the screen edge is a special case.
        self.mutableCurrentGrid.cursor = VT100GridCoordMake(rightMargin, cursorY);
    } else if ([self shouldReverseWrap]) {
        self.mutableCurrentGrid.cursor = VT100GridCoordMake(rightMargin, cursorY - 1);
    } else if (cursorX > leftMargin ||  // Cursor can move back without hitting the left margin: normal case
               (cursorX < leftMargin && cursorX > 0)) {  // Cursor left of left margin, right of left edge.
        if (cursorX >= _state.currentGrid.size.width) {
            // Cursor right of right edge, move back twice.
            self.mutableCurrentGrid.cursorX = cursorX - 2;
        } else {
            // Normal case.
            self.mutableCurrentGrid.cursorX = cursorX - 1;
        }
    }

    // It is OK to land on the right half of a double-width character (issue 3475).
}

// Reverse wrap is allowed when the cursor is on the left margin or left edge, wraparoundMode is
// set, the cursor is not at the top margin/edge, and:
// 1. reverseWraparoundMode is set (xterm's rule), or
// 2. there's no left-right margin and the preceding line has EOL_SOFT (Terminal.app's rule)
- (BOOL)shouldReverseWrap {
    if (!_state.terminal.wraparoundMode) {
        return NO;
    }

    // Cursor must be at left margin/edge.
    int leftMargin = _state.currentGrid.leftMargin;
    int cursorX = _state.currentGrid.cursorX;
    if (cursorX != leftMargin && cursorX != 0) {
        return NO;
    }

    // Cursor must not be at top margin/edge.
    int topMargin = _state.currentGrid.topMargin;
    int cursorY = _state.currentGrid.cursorY;
    if (cursorY == topMargin || cursorY == 0) {
        return NO;
    }

    // If reverseWraparoundMode is reset, then allow only if there's a soft newline on previous line
    if (!_state.terminal.reverseWraparoundMode) {
        if (_state.currentGrid.useScrollRegionCols) {
            return NO;
        }

        screen_char_t *line = [self getLineAtScreenIndex:cursorY - 1];
        unichar c = line[self.width].code;
        return (c == EOL_SOFT || c == EOL_DWC);
    }

    return YES;
}

- (void)convertHardNewlineToSoftOnGridLine:(int)line {
    screen_char_t *aLine = [self.mutableCurrentGrid screenCharsAtLineNumber:line];
    if (aLine[_state.currentGrid.size.width].code == EOL_HARD) {
        aLine[_state.currentGrid.size.width].code = EOL_SOFT;
    }
}

// Remove soft eol on previous line, provided the cursor is on the first column. This is useful
// because zsh likes to ED 0 after wrapping around before drawing the prompt. See issue 8938.
// For consistency, EL uses it, too.
- (void)removeSoftEOLBeforeCursor {
    if (_state.currentGrid.cursor.x != 0) {
        return;
    }
    if (_state.currentGrid.haveScrollRegion) {
        return;
    }
    if (_state.currentGrid.cursor.y > 0) {
        [self.mutableCurrentGrid setContinuationMarkOnLine:_state.currentGrid.cursor.y - 1 to:EOL_HARD];
    } else {
        [self.mutableLineBuffer setPartial:NO];
    }
}

- (void)softWrapCursorToNextLineScrollingIfNeeded {
    if (_state.currentGrid.rightMargin + 1 == _state.currentGrid.size.width) {
        [self convertHardNewlineToSoftOnGridLine:_state.currentGrid.cursorY];
    }
    if (_state.currentGrid.cursorY == _state.currentGrid.bottomMargin) {
        [self incrementOverflowBy:[self.mutableCurrentGrid scrollUpIntoLineBuffer:linebuffer_
                                                              unlimitedScrollback:_state.unlimitedScrollback
                                                          useScrollbackWithRegion:self.appendToScrollbackWithStatusBar
                                                                        softBreak:YES]];
    }
    self.mutableCurrentGrid.cursorX = _state.currentGrid.leftMargin;
    self.mutableCurrentGrid.cursorY++;
}

- (int)tabStopAfterColumn:(int)lowerBound {
    for (int i = lowerBound + 1; i < self.width - 1; i++) {
        if ([_state.tabStops containsObject:@(i)]) {
            return i;
        }
    }
    return self.width - 1;
}

// See issue 6592 for why `setBackgroundColors` exists. tl;dr ncurses makes weird assumptions.
- (void)mutAppendTabAtCursor:(BOOL)setBackgroundColors {
    int rightMargin;
    if (_state.currentGrid.useScrollRegionCols) {
        rightMargin = _state.currentGrid.rightMargin;
        if (_state.currentGrid.cursorX > rightMargin) {
            rightMargin = self.width - 1;
        }
    } else {
        rightMargin = self.width - 1;
    }

    if (_state.terminal.moreFix && self.cursorX > self.width && _state.terminal.wraparoundMode) {
        [self terminalLineFeed];
        [self mutCarriageReturn];
    }

    int nextTabStop = MIN(rightMargin, [self tabStopAfterColumn:_state.currentGrid.cursorX]);
    if (nextTabStop <= _state.currentGrid.cursorX) {
        // This happens when the cursor can't advance any farther.
        if ([iTermAdvancedSettingsModel tabsWrapAround]) {
            nextTabStop = [self tabStopAfterColumn:_state.currentGrid.leftMargin];
            [self softWrapCursorToNextLineScrollingIfNeeded];
        } else {
            return;
        }
    }
    const int y = _state.currentGrid.cursorY;
    screen_char_t *aLine = [self.mutableCurrentGrid screenCharsAtLineNumber:y];
    BOOL allNulls = YES;
    for (int i = _state.currentGrid.cursorX; i < nextTabStop; i++) {
        if (aLine[i].code) {
            allNulls = NO;
            break;
        }
    }
    if (allNulls) {
        screen_char_t filler;
        InitializeScreenChar(&filler, [_state.terminal foregroundColorCode], [_state.terminal backgroundColorCode]);
        filler.code = TAB_FILLER;
        const int startX = _state.currentGrid.cursorX;
        const int limit = nextTabStop - 1;
        iTermExternalAttribute *ea = [_state.terminal externalAttributes];
        [self.mutableCurrentGrid mutateCharactersInRange:VT100GridCoordRangeMake(startX, y, limit + 1, y)
                                                   block:^(screen_char_t *c,
                                                           iTermExternalAttribute **eaOut,
                                                           VT100GridCoord coord,
                                                           BOOL *stop) {
            if (coord.x < limit) {
                if (setBackgroundColors) {
                    *c = filler;
                    *eaOut = ea;
                } else {
                    c->image = NO;
                    c->complexChar = NO;
                    c->code = TAB_FILLER;
                }
            } else {
                if (setBackgroundColors) {
                    screen_char_t tab = filler;
                    tab.code = '\t';
                    *c = tab;
                    *eaOut = ea;
                } else {
                    c->image = NO;
                    c->complexChar = NO;
                    c->code = '\t';
                }
            }
        }];

        [delegate_ screenAppendScreenCharArray:aLine + _state.currentGrid.cursorX
                                      metadata:iTermImmutableMetadataDefault()
                                        length:nextTabStop - startX];
    }
    self.mutableCurrentGrid.cursorX = nextTabStop;
}

- (void)mutCursorLeft:(int)n {
    [self.mutableCurrentGrid moveCursorLeft:n];
    [delegate_ screenTriggerableChangeDidOccur];
    if (_state.commandStartCoord.x != -1) {
        [delegate_ screenCommandDidChangeWithRange:[self commandRange]];
    }
}

- (void)mutCursorDown:(int)n andToStartOfLine:(BOOL)toStart {
    [self.mutableCurrentGrid moveCursorDown:n];
    if (toStart) {
        [self.mutableCurrentGrid moveCursorToLeftMargin];
    }
    [delegate_ screenTriggerableChangeDidOccur];
    if (_state.commandStartCoord.x != -1) {
        [delegate_ screenCommandDidChangeWithRange:[self commandRange]];
    }
}

- (void)mutCursorRight:(int)n {
    [self.mutableCurrentGrid moveCursorRight:n];
    [delegate_ screenTriggerableChangeDidOccur];
    if (_state.commandStartCoord.x != -1) {
        [delegate_ screenCommandDidChangeWithRange:[self commandRange]];
    }
}

- (void)mutCursorUp:(int)n andToStartOfLine:(BOOL)toStart {
    [self.mutableCurrentGrid moveCursorUp:n];
    if (toStart) {
        [self.mutableCurrentGrid moveCursorToLeftMargin];
    }
    [delegate_ screenTriggerableChangeDidOccur];
    if (_state.commandStartCoord.x != -1) {
        [delegate_ screenCommandDidChangeWithRange:[self commandRange]];
    }
}

- (void)mutShowTestPattern {
    screen_char_t ch = [_state.currentGrid defaultChar];
    ch.code = 'E';
    [self.mutableCurrentGrid setCharsFrom:VT100GridCoordMake(0, 0)
                                       to:VT100GridCoordMake(_state.currentGrid.size.width - 1,
                                                             _state.currentGrid.size.height - 1)
                        toChar:ch
            externalAttributes:nil];
    [self.mutableCurrentGrid resetScrollRegions];
    self.mutableCurrentGrid.cursor = VT100GridCoordMake(0, 0);
}

- (void)mutSetScrollRegionTop:(int)top bottom:(int)bottom {
    if (top >= 0 &&
        top < _state.currentGrid.size.height &&
        bottom >= 0 &&
        bottom < _state.currentGrid.size.height &&
        bottom > top) {
        self.mutableCurrentGrid.scrollRegionRows = VT100GridRangeMake(top, bottom - top + 1);

        if ([_state.terminal originMode]) {
            self.mutableCurrentGrid.cursor = VT100GridCoordMake(_state.currentGrid.leftMargin,
                                                                _state.currentGrid.topMargin);
        } else {
            self.mutableCurrentGrid.cursor = VT100GridCoordMake(0, 0);
        }
    }
}

- (void)scrollScreenIntoHistory {
    // Scroll the top lines of the screen into history, up to and including the last non-
    // empty line.
    LineBuffer *lineBuffer;
    if (_state.currentGrid == _state.altGrid && !_state.saveToScrollbackInAlternateScreen) {
        lineBuffer = nil;
    } else {
        lineBuffer = linebuffer_;
    }
    const int n = [_state.currentGrid numberOfNonEmptyLinesIncludingWhitespaceAsEmpty:YES];
    for (int i = 0; i < n; i++) {
        [self incrementOverflowBy:
            [self.mutableCurrentGrid scrollWholeScreenUpIntoLineBuffer:lineBuffer
                                                   unlimitedScrollback:_state.unlimitedScrollback]];
    }
}

- (void)mutEraseInDisplayBeforeCursor:(BOOL)before afterCursor:(BOOL)after decProtect:(BOOL)dec {
    int x1, yStart, x2, y2;
    BOOL shouldHonorProtected = NO;
    switch (_state.protectedMode) {
        case VT100TerminalProtectedModeNone:
            shouldHonorProtected = NO;
            break;
        case VT100TerminalProtectedModeISO:
            shouldHonorProtected = YES;
            break;
        case VT100TerminalProtectedModeDEC:
            shouldHonorProtected = dec;
            break;
    }
    if (before && after) {
        [delegate_ screenRemoveSelection];
        if (!shouldHonorProtected) {
            [self scrollScreenIntoHistory];
        }
        x1 = 0;
        yStart = 0;
        x2 = _state.currentGrid.size.width - 1;
        y2 = _state.currentGrid.size.height - 1;
    } else if (before) {
        x1 = 0;
        yStart = 0;
        x2 = MIN(_state.currentGrid.cursor.x, _state.currentGrid.size.width - 1);
        y2 = _state.currentGrid.cursor.y;
    } else if (after) {
        x1 = MIN(_state.currentGrid.cursor.x, _state.currentGrid.size.width - 1);
        yStart = _state.currentGrid.cursor.y;
        x2 = _state.currentGrid.size.width - 1;
        y2 = _state.currentGrid.size.height - 1;
        if (x1 == 0 && yStart == 0 && [iTermAdvancedSettingsModel saveScrollBufferWhenClearing] && self.terminal.softAlternateScreenMode) {
            // Save the whole screen. This helps the "screen" terminal, where CSI H CSI J is used to
            // clear the screen.
            // Only do it in alternate screen mode to avoid doing this for zsh (issue 8822)
            // And don't do it if in a protection mode since that would defeat the purpose.
            [delegate_ screenRemoveSelection];
            if (!shouldHonorProtected) {
                [self scrollScreenIntoHistory];
            }
        } else if (self.cursorX == 1 && self.cursorY == 1 && _state.terminal.lastToken.type == VT100CSI_CUP) {
            // This is important for tmux integration with shell integration enabled. The screen
            // terminal uses ED 0 instead of ED 2 to clear the screen (e.g., when you do ^L at the shell).
            [self removePromptMarksBelowLine:yStart + self.numberOfScrollbackLines];
        }
    } else {
        return;
    }
    if (after) {
        [self removeSoftEOLBeforeCursor];
    }
    VT100GridRun theRun = VT100GridRunFromCoords(VT100GridCoordMake(x1, yStart),
                                                 VT100GridCoordMake(x2, y2),
                                                 _state.currentGrid.size.width);
    if (shouldHonorProtected) {
        const BOOL foundProtected = [self mutSelectiveEraseRange:VT100GridCoordRangeMake(x1, yStart, x2, y2)
                                                 eraseAttributes:YES];
        const BOOL eraseAll = (x1 == 0 && yStart == 0 && x2 == _state.currentGrid.size.width - 1 && y2 == _state.currentGrid.size.height - 1);
        if (!foundProtected && eraseAll) {  // xterm has this logic, so we do too. My guess is that it's an optimization.
            _mutableState.protectedMode = VT100TerminalProtectedModeNone;
        }
    } else {
        [self.mutableCurrentGrid setCharsInRun:theRun
                                        toChar:0
                            externalAttributes:nil];
    }
    [delegate_ screenTriggerableChangeDidOccur];

}

- (void)mutEraseLineBeforeCursor:(BOOL)before afterCursor:(BOOL)after decProtect:(BOOL)dec {
    BOOL shouldHonorProtected = NO;
    switch (_state.protectedMode) {
        case VT100TerminalProtectedModeNone:
            shouldHonorProtected = NO;
            break;
        case VT100TerminalProtectedModeISO:
            shouldHonorProtected = YES;
            break;
        case VT100TerminalProtectedModeDEC:
            shouldHonorProtected = dec;
            break;
    }
    int x1 = 0;
    int x2 = 0;

    if (before && after) {
        x1 = 0;
        x2 = _state.currentGrid.size.width - 1;
    } else if (before) {
        x1 = 0;
        x2 = MIN(_state.currentGrid.cursor.x, _state.currentGrid.size.width - 1);
    } else if (after) {
        x1 = _state.currentGrid.cursor.x;
        x2 = _state.currentGrid.size.width - 1;
    } else {
        return;
    }
    if (after) {
        [self removeSoftEOLBeforeCursor];
    }

    if (shouldHonorProtected) {
        [self mutSelectiveEraseRange:VT100GridCoordRangeMake(x1,
                                                             _state.currentGrid.cursor.y,
                                                             x2,
                                                             _state.currentGrid.cursor.y)
                     eraseAttributes:YES];
    } else {
        VT100GridRun theRun = VT100GridRunFromCoords(VT100GridCoordMake(x1, _state.currentGrid.cursor.y),
                                                     VT100GridCoordMake(x2, _state.currentGrid.cursor.y),
                                                     _state.currentGrid.size.width);
        [self.mutableCurrentGrid setCharsInRun:theRun
                                        toChar:0
                            externalAttributes:nil];
    }
}

- (void)mutCarriageReturn {
    if (_state.currentGrid.useScrollRegionCols && _state.currentGrid.cursorX < _state.currentGrid.leftMargin) {
        self.mutableCurrentGrid.cursorX = 0;
    } else {
        [self.mutableCurrentGrid moveCursorToLeftMargin];
    }
    [delegate_ screenTriggerableChangeDidOccur];
    if (_state.commandStartCoord.x != -1) {
        [delegate_ screenCommandDidChangeWithRange:[self commandRange]];
    }
}

- (void)mutReverseIndex {
    if (_state.currentGrid.cursorY == _state.currentGrid.topMargin) {
        if ([self cursorOutsideLeftRightMargin]) {
            return;
        } else {
            [self.mutableCurrentGrid scrollDown];
        }
    } else {
        self.mutableCurrentGrid.cursorY = MAX(0, _state.currentGrid.cursorY - 1);
    }
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)mutForwardIndex {
    if ((_state.currentGrid.cursorX == _state.currentGrid.rightMargin && ![self cursorOutsideLeftRightMargin] )||
         _state.currentGrid.cursorX == _state.currentGrid.size.width) {
        [self.mutableCurrentGrid moveContentLeft:1];
    } else {
        self.mutableCurrentGrid.cursorX += 1;
    }
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)mutBackIndex {
    if ((_state.currentGrid.cursorX == _state.currentGrid.leftMargin && ![self cursorOutsideLeftRightMargin] )||
         _state.currentGrid.cursorX == 0) {
        [self.mutableCurrentGrid moveContentRight:1];
    } else if (_state.currentGrid.cursorX > 0) {
        self.mutableCurrentGrid.cursorX -= 1;
    } else {
        return;
    }
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)mutBackTab:(int)n {
    for (int i = 0; i < n; i++) {
        // TODO: respect left-right margins
        if (_state.currentGrid.cursorX > 0) {
            self.mutableCurrentGrid.cursorX = _state.currentGrid.cursorX - 1;
            while (![self haveTabStopAt:_state.currentGrid.cursorX] && _state.currentGrid.cursorX > 0) {
                self.mutableCurrentGrid.cursorX = _state.currentGrid.cursorX - 1;
            }
            [delegate_ screenTriggerableChangeDidOccur];
        }
    }
}

- (BOOL)haveTabStopAt:(int)x {
    return [_state.tabStops containsObject:[NSNumber numberWithInt:x]];
}

- (void)mutAdvanceCursorPastLastColumn {
    if (_state.currentGrid.cursorX == self.width - 1) {
        self.mutableCurrentGrid.cursorX = self.width;
    }
}

- (void)mutEraseCharactersAfterCursor:(int)j {
    if (_state.currentGrid.cursorX < _state.currentGrid.size.width) {
        if (j <= 0) {
            return;
        }

        switch (_state.protectedMode) {
            case VT100TerminalProtectedModeNone:
            case VT100TerminalProtectedModeDEC: {
                // Do not honor protected mode.
                int limit = MIN(_state.currentGrid.cursorX + j, _state.currentGrid.size.width);
                [self.mutableCurrentGrid setCharsFrom:VT100GridCoordMake(_state.currentGrid.cursorX, _state.currentGrid.cursorY)
                                                   to:VT100GridCoordMake(limit - 1, _state.currentGrid.cursorY)
                                               toChar:[_state.currentGrid defaultChar]
                        externalAttributes:nil];
                // TODO: This used to always set the continuation mark to hard, but I think it should only do that if the last char in the line is erased.
                [delegate_ screenTriggerableChangeDidOccur];
                break;
            }
            case VT100TerminalProtectedModeISO:
                // honor protected mode.
                [self mutSelectiveEraseRange:VT100GridCoordRangeMake(_state.currentGrid.cursorX,
                                                                     _state.currentGrid.cursorY,
                                                                     MIN(_state.currentGrid.size.width, _state.currentGrid.cursorX + j),
                                                                     _state.currentGrid.cursorY)
                             eraseAttributes:YES];
                break;
        }
    }
}

- (void)mutInsertEmptyCharsAtCursor:(int)n {
    [self.mutableCurrentGrid insertChar:[_state.currentGrid defaultChar]
                     externalAttributes:nil
                                     at:_state.currentGrid.cursor
                                  times:n];
}

- (void)mutShiftLeft:(int)n {
    if (n < 1) {
        return;
    }
    if ([self cursorOutsideLeftRightMargin] || [self cursorOutsideTopBottomMargin]) {
        return;
    }
    [self.mutableCurrentGrid moveContentLeft:n];
}

- (void)mutShiftRight:(int)n {
    if (n < 1) {
        return;
    }
    if ([self cursorOutsideLeftRightMargin] || [self cursorOutsideTopBottomMargin]) {
        return;
    }
    [self.mutableCurrentGrid moveContentRight:n];
}

- (void)mutInsertBlankLinesAfterCursor:(int)n {
    VT100GridRect scrollRegionRect = [_state.currentGrid scrollRegionRect];
    if (scrollRegionRect.origin.x + scrollRegionRect.size.width == _state.currentGrid.size.width) {
        // Cursor can be in right margin and still be considered in the scroll region if the
        // scroll region abuts the right margin.
        scrollRegionRect.size.width++;
    }
    BOOL cursorInScrollRegion = VT100GridCoordInRect(_state.currentGrid.cursor, scrollRegionRect);
    if (cursorInScrollRegion) {
        // xterm appears to ignore INSLN if the cursor is outside the scroll region.
        // See insln-* files in tests/.
        int top = _state.currentGrid.cursorY;
        int left = _state.currentGrid.leftMargin;
        int width = _state.currentGrid.rightMargin - _state.currentGrid.leftMargin + 1;
        int height = _state.currentGrid.bottomMargin - top + 1;
        [self.mutableCurrentGrid scrollRect:VT100GridRectMake(left, top, width, height)
                                     downBy:n
                                  softBreak:NO];
        [delegate_ screenTriggerableChangeDidOccur];
    }
}

- (void)mutDeleteCharactersAtCursor:(int)n {
    [self.mutableCurrentGrid deleteChars:n startingAt:_state.currentGrid.cursor];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)mutDeleteLinesAtCursor:(int)n {
    if (n <= 0) {
        return;
    }
    VT100GridRect scrollRegionRect = [_state.currentGrid scrollRegionRect];
    if (scrollRegionRect.origin.x + scrollRegionRect.size.width == _state.currentGrid.size.width) {
        // Cursor can be in right margin and still be considered in the scroll region if the
        // scroll region abuts the right margin.
        scrollRegionRect.size.width++;
    }
    BOOL cursorInScrollRegion = VT100GridCoordInRect(_state.currentGrid.cursor, scrollRegionRect);
    if (cursorInScrollRegion) {
        [self.mutableCurrentGrid scrollRect:VT100GridRectMake(_state.currentGrid.leftMargin,
                                                              _state.currentGrid.cursorY,
                                                              _state.currentGrid.rightMargin - _state.currentGrid.leftMargin + 1,
                                                              _state.currentGrid.bottomMargin - _state.currentGrid.cursorY + 1)
                          downBy:-n
                       softBreak:NO];
        [delegate_ screenTriggerableChangeDidOccur];
    }
}

- (void)mutScrollUp:(int)n {
    [delegate_ screenRemoveSelection];
    for (int i = 0;
         i < MIN(_state.currentGrid.size.height, n);
         i++) {
        [self incrementOverflowBy:[self.mutableCurrentGrid scrollUpIntoLineBuffer:linebuffer_
                                                              unlimitedScrollback:_state.unlimitedScrollback
                                                          useScrollbackWithRegion:self.appendToScrollbackWithStatusBar
                                                                        softBreak:NO]];
    }
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)mutScrollDown:(int)n {
    [delegate_ screenRemoveSelection];
    [self.mutableCurrentGrid scrollRect:[_state.currentGrid scrollRegionRect]
                                 downBy:MIN(_state.currentGrid.size.height, n)
                              softBreak:NO];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)mutInsertColumns:(int)n {
    if ([self cursorOutsideLeftRightMargin] || [self cursorOutsideTopBottomMargin]) {
        return;
    }
    if (n <= 0) {
        return;
    }
    for (int y = _state.currentGrid.topMargin; y <= _state.currentGrid.bottomMargin; y++) {
        [self.mutableCurrentGrid insertChar:_state.currentGrid.defaultChar
                         externalAttributes:nil
                                         at:VT100GridCoordMake(_state.currentGrid.cursor.x, y)
                                      times:n];
    }
}

- (void)mutDeleteColumns:(int)n {
    if ([self cursorOutsideLeftRightMargin] || [self cursorOutsideTopBottomMargin]) {
        return;
    }
    if (n <= 0) {
        return;
    }
    for (int y = _state.currentGrid.topMargin; y <= _state.currentGrid.bottomMargin; y++) {
        [self.mutableCurrentGrid deleteChars:n
                                  startingAt:VT100GridCoordMake(_state.currentGrid.cursor.x, y)];
    }
}

- (void)mutSetAttribute:(int)sgrAttribute inRect:(VT100GridRect)rect {
    void (^block)(VT100GridCoord, screen_char_t *, iTermExternalAttribute *, BOOL *) =
    ^(VT100GridCoord coord,
      screen_char_t *sct,
      iTermExternalAttribute *ea,
      BOOL *stop) {
        switch (sgrAttribute) {
            case 0:
                sct->bold = NO;
                sct->blink = NO;
                sct->underline = NO;
                if (sct->inverse) {
                    ScreenCharInvert(sct);
                }
                break;

            case 1:
                sct->bold = YES;
                break;
            case 4:
                sct->underline = YES;
                break;
            case 5:
                sct->blink = YES;
                break;
            case 7:
                if (!sct->inverse) {
                    ScreenCharInvert(sct);
                }
                break;

            case 22:
                sct->bold = NO;
                break;
            case 24:
                sct->underline = NO;
                break;
            case 25:
                sct->blink = NO;
                break;
            case 27:
                if (sct->inverse) {
                    ScreenCharInvert(sct);
                }
                break;
        }
    };
    if (_state.terminal.decsaceRectangleMode) {
        [self.mutableCurrentGrid mutateCellsInRect:rect
                                             block:^(VT100GridCoord coord,
                                                     screen_char_t *sct,
                                                     iTermExternalAttribute **eaOut,
                                                     BOOL *stop) {
            block(coord, sct, *eaOut, stop);
        }];
    } else {
        [self.mutableCurrentGrid mutateCharactersInRange:VT100GridCoordRangeMake(rect.origin.x,
                                                                                 rect.origin.y,
                                                                                 rect.origin.x + rect.size.width,
                                                                                 rect.origin.y + rect.size.height - 1)
                                                   block:^(screen_char_t *sct,
                                                           iTermExternalAttribute **eaOut,
                                                           VT100GridCoord coord,
                                                           BOOL *stop) {
            block(coord, sct, *eaOut, stop);
        }];
    }
}

- (void)mutToggleAttribute:(int)sgrAttribute inRect:(VT100GridRect)rect {
    void (^block)(VT100GridCoord, screen_char_t *, iTermExternalAttribute *, BOOL *) =
    ^(VT100GridCoord coord,
      screen_char_t *sct,
      iTermExternalAttribute *ea,
      BOOL *stop) {
        switch (sgrAttribute) {
            case 1:
                sct->bold = !sct->bold;
                break;
            case 4:
                sct->underline = !sct->underline;
                break;
            case 5:
                sct->blink = !sct->blink;
                break;
            case 7:
                ScreenCharInvert(sct);
                break;
        }
    };
    if (_state.terminal.decsaceRectangleMode) {
        [self.mutableCurrentGrid mutateCellsInRect:rect
                                             block:^(VT100GridCoord coord,
                                                     screen_char_t *sct,
                                                     iTermExternalAttribute **eaOut,
                                                     BOOL *stop) {
            block(coord, sct, *eaOut, stop);
        }];
    } else {
        [self.mutableCurrentGrid mutateCharactersInRange:VT100GridCoordRangeMake(rect.origin.x,
                                                                                 rect.origin.y,
                                                                                 rect.origin.x + rect.size.width,
                                                                                 rect.origin.y + rect.size.height - 1)
                                                   block:^(screen_char_t *sct,
                                                           iTermExternalAttribute **eaOut,
                                                           VT100GridCoord coord,
                                                           BOOL *stop) {
            block(coord, sct, *eaOut, stop);
        }];
    }
}

- (void)mutFillRectangle:(VT100GridRect)rect with:(screen_char_t)c externalAttributes:(iTermExternalAttribute *)ea {
    [self.mutableCurrentGrid setCharsFrom:rect.origin
                                       to:VT100GridRectMax(rect)
                                   toChar:c
                       externalAttributes:ea];
}

static inline void VT100ScreenEraseCell(screen_char_t *sct, iTermExternalAttribute **eaOut, BOOL eraseAttributes, const screen_char_t *defaultChar) {
    if (eraseAttributes) {
        *sct = *defaultChar;
        sct->code = ' ';
        *eaOut = nil;
        return;
    }
    sct->code = ' ';
    sct->complexChar = NO;
    sct->image = NO;
    if ((*eaOut).urlCode) {
        *eaOut = [iTermExternalAttribute attributeHavingUnderlineColor:(*eaOut).hasUnderlineColor
                                                        underlineColor:(*eaOut).underlineColor
                                                               urlCode:0];
    }
}

// Note: this does not erase attributes! It just sets the character to space.
- (void)mutSelectiveEraseRectangle:(VT100GridRect)rect {
    const screen_char_t dc = _state.currentGrid.defaultChar;
    [self.mutableCurrentGrid mutateCellsInRect:rect
                                         block:^(VT100GridCoord coord,
                                                 screen_char_t *sct,
                                                 iTermExternalAttribute **eaOut,
                                                 BOOL *stop) {
        if (_state.protectedMode == VT100TerminalProtectedModeDEC && sct->guarded) {
            return;
        }
        VT100ScreenEraseCell(sct, eaOut, NO, &dc);
    }];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (BOOL)mutSelectiveEraseRange:(VT100GridCoordRange)range eraseAttributes:(BOOL)eraseAttributes {
    __block BOOL foundProtected = NO;
    const screen_char_t dc = _state.currentGrid.defaultChar;
    [self.mutableCurrentGrid mutateCharactersInRange:range
                                               block:^(screen_char_t *sct,
                                                       iTermExternalAttribute **eaOut,
                                                       VT100GridCoord coord,
                                                       BOOL *stop) {
        if (_state.protectedMode != VT100TerminalProtectedModeNone && sct->guarded) {
            foundProtected = YES;
            return;
        }
        VT100ScreenEraseCell(sct, eaOut, eraseAttributes, &dc);
    }];
    [delegate_ screenTriggerableChangeDidOccur];
    return foundProtected;
}

- (void)setCursorX:(int)x Y:(int)y {
    DLog(@"Move cursor to %d,%d", x, y);
    self.mutableCurrentGrid.cursor = VT100GridCoordMake(x, y);
}

- (void)mutSetUseColumnScrollRegion:(BOOL)mode {
    self.mutableCurrentGrid.useScrollRegionCols = mode;
    self.mutableAltGrid.useScrollRegionCols = mode;
    if (!mode) {
        self.mutableCurrentGrid.scrollRegionCols = VT100GridRangeMake(0, _state.currentGrid.size.width);
    }
}

- (void)mutCopyFrom:(VT100GridRect)source to:(VT100GridCoord)dest {
    id<VT100GridReading> copy = [[_state.currentGrid copy] autorelease];
    const VT100GridSize size = _state.currentGrid.size;
    [copy enumerateCellsInRect:source
                         block:^(VT100GridCoord sourceCoord,
                                 screen_char_t sct,
                                 iTermExternalAttribute *ea,
                                 BOOL *stop) {
        const VT100GridCoord destCoord = VT100GridCoordMake(sourceCoord.x - source.origin.x + dest.x,
                                                            sourceCoord.y - source.origin.y + dest.y);
        if (destCoord.x < 0 || destCoord.x >= size.width || destCoord.y < 0 || destCoord.y >= size.height) {
            return;
        }
        [self.mutableCurrentGrid setCharsFrom:destCoord
                                           to:destCoord
                                       toChar:sct
                           externalAttributes:ea];
    }];
}

- (void)mutSetTabStopAtCursor {
    if (_state.currentGrid.cursorX < _state.currentGrid.size.width) {
        [_mutableState.tabStops addObject:[NSNumber numberWithInt:_state.currentGrid.cursorX]];
    }
}

- (void)mutRemoveAllTabStops {
    [_mutableState.tabStops removeAllObjects];
}

- (void)mutRemoveTabStopAtCursor {
    if (_state.currentGrid.cursorX < _state.currentGrid.size.width) {
        [_mutableState.tabStops removeObject:[NSNumber numberWithInt:_state.currentGrid.cursorX]];
    }
}

- (void)mutSetTabStops:(NSArray<NSNumber *> *)tabStops {
    [_mutableState.tabStops removeAllObjects];
    [tabStops enumerateObjectsUsingBlock:^(NSNumber * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [_mutableState.tabStops addObject:@(obj.intValue - 1)];
    }];
}

#pragma mark - DVR

- (void)mutSetFromFrame:(screen_char_t*)s
                    len:(int)len
               metadata:(NSArray<NSArray *> *)metadataArrays
                   info:(DVRFrameInfo)info {
    assert(len == (info.width + 1) * info.height * sizeof(screen_char_t));
    NSMutableData *storage = [NSMutableData dataWithLength:sizeof(iTermMetadata) * info.height];
    iTermMetadata *md = (iTermMetadata *)storage.mutableBytes;
    [metadataArrays enumerateObjectsUsingBlock:^(NSArray * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (idx >= info.height) {
            *stop = YES;
            return;
        }
        iTermMetadataInitFromArray(&md[idx], obj);
    }];
    [self.mutableCurrentGrid setContentsFromDVRFrame:s metadataArray:md info:info];
    for (int i = 0; i < info.height; i++) {
        iTermMetadataRelease(md[i]);
    }
    [self resetScrollbackOverflow];
    _mutableState.savedFindContextAbsPos = 0;
    [delegate_ screenRemoveSelection];
    [delegate_ screenNeedsRedraw];
    [self.mutableCurrentGrid markAllCharsDirty:YES];
}

#pragma mark - Find on Page

- (void)mutRestoreSavedPositionToFindContext:(FindContext *)context {
    int linesPushed;
    linesPushed = [self.mutableCurrentGrid appendLines:[self.mutableCurrentGrid numberOfLinesUsed]
                                          toLineBuffer:linebuffer_];

    [linebuffer_ storeLocationOfAbsPos:_mutableState.savedFindContextAbsPos
                             inContext:context];

    [self mutPopScrollbackLines:linesPushed];
}

- (void)mutSetFindString:(NSString*)aString
     forwardDirection:(BOOL)direction
                 mode:(iTermFindMode)mode
          startingAtX:(int)x
          startingAtY:(int)y
           withOffset:(int)offset
            inContext:(FindContext*)context
      multipleResults:(BOOL)multipleResults {
    DLog(@"begin self=%@ aString=%@", self, aString);
    LineBuffer *tempLineBuffer = [[linebuffer_ copy] autorelease];
    [tempLineBuffer seal];

    // Append the screen contents to the scrollback buffer so they are included in the search.
    [self.mutableCurrentGrid appendLines:[_state.currentGrid numberOfLinesUsed]
                            toLineBuffer:tempLineBuffer];

    // Get the start position of (x,y)
    LineBufferPosition *startPos;
    startPos = [tempLineBuffer positionForCoordinate:VT100GridCoordMake(x, y)
                                               width:_state.currentGrid.size.width
                                              offset:offset * (direction ? 1 : -1)];
    if (!startPos) {
        // x,y wasn't a real position in the line buffer, probably a null after the end.
        if (direction) {
            DLog(@"Search from first position");
            startPos = [tempLineBuffer firstPosition];
        } else {
            DLog(@"Search from last position");
            startPos = [[tempLineBuffer lastPosition] predecessor];
        }
    } else {
        DLog(@"Search from %@", startPos);
        // Make sure startPos is not at or after the last cell in the line buffer.
        BOOL ok;
        VT100GridCoord startPosCoord = [tempLineBuffer coordinateForPosition:startPos
                                                                       width:_state.currentGrid.size.width
                                                                extendsRight:YES
                                                                          ok:&ok];
        LineBufferPosition *lastValidPosition = [[tempLineBuffer lastPosition] predecessor];
        if (!ok) {
            startPos = lastValidPosition;
        } else {
            VT100GridCoord lastPositionCoord = [tempLineBuffer coordinateForPosition:lastValidPosition
                                                                               width:_state.currentGrid.size.width
                                                                        extendsRight:YES
                                                                                  ok:&ok];
            assert(ok);
            long long s = startPosCoord.y;
            s *= _state.currentGrid.size.width;
            s += startPosCoord.x;

            long long l = lastPositionCoord.y;
            l *= _state.currentGrid.size.width;
            l += lastPositionCoord.x;

            if (s >= l) {
                startPos = lastValidPosition;
            }
        }
    }

    // Set up the options bitmask and call findSubstring.
    FindOptions opts = 0;
    if (!direction) {
        opts |= FindOptBackwards;
    }
    if (multipleResults) {
        opts |= FindMultipleResults;
    }
    [tempLineBuffer prepareToSearchFor:aString startingAt:startPos options:opts mode:mode withContext:context];
    context.hasWrapped = NO;
}

- (void)mutSaveFindContextPosition {
    _mutableState.savedFindContextAbsPos = [linebuffer_ absPositionOfFindContext:_mutableState.findContext];
}

- (void)mutStoreLastPositionInLineBufferAsFindContextSavedPosition {
    _mutableState.savedFindContextAbsPos = [[linebuffer_ lastPosition] absolutePosition];
}

- (BOOL)mutContinueFindResultsInContext:(FindContext *)context
                                toArray:(NSMutableArray *)results {
    // Append the screen contents to the scrollback buffer so they are included in the search.
    LineBuffer *temporaryLineBuffer = [[linebuffer_ copy] autorelease];
    [temporaryLineBuffer seal];

#warning TODO: This is an unusual use of mutation since it is only temporary. But probably Find should happen off-thread anyway.
    [self.mutableCurrentGrid appendLines:[_state.currentGrid numberOfLinesUsed]
                            toLineBuffer:temporaryLineBuffer];

    // Search one block.
    LineBufferPosition *stopAt;
    if (context.dir > 0) {
        stopAt = [temporaryLineBuffer lastPosition];
    } else {
        stopAt = [temporaryLineBuffer firstPosition];
    }

    struct timeval begintime;
    gettimeofday(&begintime, NULL);
    BOOL keepSearching = NO;
    int iterations = 0;
    int ms_diff = 0;
    do {
        if (context.status == Searching) {
            [temporaryLineBuffer findSubstring:context stopAt:stopAt];
        }

        // Handle the current state
        switch (context.status) {
            case Matched: {
                // NSLog(@"matched");
                // Found a match in the text.
                NSArray *allPositions = [temporaryLineBuffer convertPositions:context.results
                                                            withWidth:_state.currentGrid.size.width];
                for (XYRange *xyrange in allPositions) {
                    SearchResult *result = [[[SearchResult alloc] init] autorelease];

                    result.startX = xyrange->xStart;
                    result.endX = xyrange->xEnd;
                    result.absStartY = xyrange->yStart + [self totalScrollbackOverflow];
                    result.absEndY = xyrange->yEnd + [self totalScrollbackOverflow];

                    [results addObject:result];

                    if (!(context.options & FindMultipleResults)) {
                        assert([context.results count] == 1);
                        [context reset];
                        keepSearching = NO;
                    } else {
                        keepSearching = YES;
                    }
                }
                [context.results removeAllObjects];
                break;
            }

            case Searching:
                // NSLog(@"searching");
                // No result yet but keep looking
                keepSearching = YES;
                break;

            case NotFound:
                // NSLog(@"not found");
                // Reached stopAt point with no match.
                if (context.hasWrapped) {
                    [context reset];
                    keepSearching = NO;
                } else {
                    // NSLog(@"...wrapping");
                    // wrap around and resume search.
                    FindContext *tempFindContext = [[[FindContext alloc] init] autorelease];
                    [temporaryLineBuffer prepareToSearchFor:_mutableState.findContext.substring
                                                 startingAt:(_mutableState.findContext.dir > 0 ? [temporaryLineBuffer firstPosition] : [[temporaryLineBuffer lastPosition] predecessor])
                                                    options:_mutableState.findContext.options
                                                       mode:_mutableState.findContext.mode
                                                withContext:tempFindContext];
                    [_mutableState.findContext reset];
                    // TODO test this!
                    [context copyFromFindContext:tempFindContext];
                    context.hasWrapped = YES;
                    keepSearching = YES;
                }
                break;

            default:
                assert(false);  // Bogus status
        }

        struct timeval endtime;
        if (keepSearching) {
            gettimeofday(&endtime, NULL);
            ms_diff = (endtime.tv_sec - begintime.tv_sec) * 1000 +
            (endtime.tv_usec - begintime.tv_usec) / 1000;
            context.status = Searching;
        }
        ++iterations;
    } while (keepSearching && ms_diff < context.maxTime * 1000);

    switch (context.status) {
        case Searching: {
            int numDropped = [temporaryLineBuffer numberOfDroppedBlocks];
            double current = context.absBlockNum - numDropped;
            double max = [temporaryLineBuffer largestAbsoluteBlockNumber] - numDropped;
            double p = MAX(0, current / max);
            if (context.dir > 0) {
                context.progress = p;
            } else {
                context.progress = 1.0 - p;
            }
            break;
        }
        case Matched:
        case NotFound:
            context.progress = 1;
            break;
    }
    // NSLog(@"Did %d iterations in %dms. Average time per block was %dms", iterations, ms_diff, ms_diff/iterations);

    return keepSearching;
}

#pragma mark - Accessors

- (void)mutSetSaveToScrollbackInAlternateScreen:(BOOL)value {
    _mutableState.saveToScrollbackInAlternateScreen = value;
}

- (void)mutInvalidateCommandStartCoord {
    [self mutSetCommandStartCoord:VT100GridAbsCoordMake(-1, -1)];
}

- (void)mutInvalidateCommandStartCoordWithoutSideEffects {
    [self mutSetCommandStartCoordWithoutSideEffects:VT100GridAbsCoordMake(-1, -1)];
}

- (void)mutSetCommandStartCoord:(VT100GridAbsCoord)coord {
    _mutableState.commandStartCoord = coord;
    [delegate_ screenCommandDidChangeWithRange:[self commandRange]];
}

- (void)mutSetCommandStartCoordWithoutSideEffects:(VT100GridAbsCoord)coord {
    _mutableState.commandStartCoord = coord;
}

- (void)mutResetScrollbackOverflow {
    _mutableState.scrollbackOverflow = 0;
}

- (void)mutSetWraparoundMode:(BOOL)newValue {
    _mutableState.wraparoundMode = newValue;
}

- (void)mutUpdateTerminalType {
    _mutableState.ansi = [_state.terminal isAnsi];
}

- (void)mutSetInsert:(BOOL)newValue {
    _mutableState.insert = newValue;
}

- (void)mutSetUnlimitedScrollback:(BOOL)newValue {
    _mutableState.unlimitedScrollback = newValue;
}

// Gets a line on the screen (0 = top of screen)
- (screen_char_t *)mutGetLineAtScreenIndex:(int)theIndex {
    return [self.mutableCurrentGrid screenCharsAtLineNumber:theIndex];
}

- (void)mutSetTerminal:(VT100Terminal *)terminal {
    _mutableState.terminal = terminal;
    _mutableState.ansi = [terminal isAnsi];
    _mutableState.wraparoundMode = [terminal wraparoundMode];
    _mutableState.insert = [terminal insertMode];
}

#pragma mark - Dirty

- (void)mutResetAllDirty {
    self.mutableCurrentGrid.allDirty = NO;
}

- (void)mutSetLineDirtyAtY:(int)y {
    if (y >= 0) {
        [self.mutableCurrentGrid markCharsDirty:YES
                                     inRectFrom:VT100GridCoordMake(0, y)
                                             to:VT100GridCoordMake(self.width - 1, y)];
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
        [self.mutableCurrentGrid markCharDirty:YES
                                            at:VT100GridCoordMake(xToMark, yToMark)
                               updateTimestamp:NO];
        if (xToMark < _state.currentGrid.size.width - 1) {
            // Just in case the cursor was over a double width character
            [self.mutableCurrentGrid markCharDirty:YES
                                                at:VT100GridCoordMake(xToMark + 1, yToMark)
                                   updateTimestamp:NO];
        }
    }
}

- (void)mutResetDirty {
    [self.mutableCurrentGrid markAllCharsDirty:NO];
}

- (void)mutMarkWholeScreenDirty {
    [self.mutableCurrentGrid markAllCharsDirty:YES];
}

- (void)mutRedrawGrid {
    [self.mutableCurrentGrid setAllDirty:YES];
    // Force the screen to redraw right away. Some users reported lag and this seems to fix it.
    // I think the update timer was hitting a worst case scenario which made the lag visible.
    // See issue 3537.
    [delegate_ screenUpdateDisplay:YES];
}

#pragma mark - Alternate Screen

- (void)mutShowAltBuffer {
    if (_state.currentGrid == _state.altGrid) {
        return;
    }
    [delegate_ screenRemoveSelection];
    if (!_state.altGrid) {
        _mutableState.altGrid = [[[VT100Grid alloc] initWithSize:_state.primaryGrid.size delegate:self] autorelease];
    }

    [self.temporaryDoubleBuffer reset];
    self.mutablePrimaryGrid.savedDefaultChar = [_state.primaryGrid defaultChar];
    [self hideOnScreenNotesAndTruncateSpanners];
    _mutableState.currentGrid = _state.altGrid;
    self.mutableCurrentGrid.cursor = _state.primaryGrid.cursor;

    [self swapNotes];
    [self reloadMarkCache];

    [self.mutableCurrentGrid markAllCharsDirty:YES];
    [delegate_ screenScheduleRedrawSoon];
    [self mutInvalidateCommandStartCoordWithoutSideEffects];
}

- (void)mutShowPrimaryBuffer {
    if (_state.currentGrid == _state.altGrid) {
        [self.temporaryDoubleBuffer reset];
        [delegate_ screenRemoveSelection];
        [self hideOnScreenNotesAndTruncateSpanners];
        _mutableState.currentGrid = _state.primaryGrid;
        [self mutInvalidateCommandStartCoordWithoutSideEffects];
        [self swapNotes];
        [self reloadMarkCache];

        [self.mutableCurrentGrid markAllCharsDirty:YES];
        [delegate_ screenScheduleRedrawSoon];
    }
}

#pragma mark - URLs

- (void)mutLinkRun:(VT100GridRun)run
       withURLCode:(unsigned int)code {

    for (NSValue *value in [_state.currentGrid rectsForRun:run]) {
        VT100GridRect rect = [value gridRectValue];
        [self.mutableCurrentGrid setURLCode:code
                                 inRectFrom:rect.origin
                                         to:VT100GridRectMax(rect)];
    }
}

#pragma mark - Highlighting

// Set the color of prototypechar to all chars between startPoint and endPoint on the screen.
- (void)mutHighlightRun:(VT100GridRun)run
    withForegroundColor:(NSColor *)fgColor
        backgroundColor:(NSColor *)bgColor {
    DLog(@"Really highlight run %@ fg=%@ bg=%@", VT100GridRunDescription(run), fgColor, bgColor);

    screen_char_t fg = { 0 };
    screen_char_t bg = { 0 };

    NSColor *genericFgColor = [fgColor colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    NSColor *genericBgColor = [bgColor colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];

    if (fgColor) {
        fg.foregroundColor = genericFgColor.redComponent * 255;
        fg.fgBlue = genericFgColor.blueComponent * 255;
        fg.fgGreen = genericFgColor.greenComponent * 255;
        fg.foregroundColorMode = ColorMode24bit;
    } else {
        fg.foregroundColorMode = ColorModeInvalid;
    }

    if (bgColor) {
        bg.backgroundColor = genericBgColor.redComponent * 255;
        bg.bgBlue = genericBgColor.blueComponent * 255;
        bg.bgGreen = genericBgColor.greenComponent * 255;
        bg.backgroundColorMode = ColorMode24bit;
    } else {
        bg.backgroundColorMode = ColorModeInvalid;
    }

    for (NSValue *value in [_state.currentGrid rectsForRun:run]) {
        VT100GridRect rect = [value gridRectValue];
        [self.mutableCurrentGrid setBackgroundColor:bg
                                    foregroundColor:fg
                                         inRectFrom:rect.origin
                                                 to:VT100GridRectMax(rect)];
    }
}

#pragma mark - Scrollback

// sets scrollback lines.
- (void)mutSetMaxScrollbackLines:(unsigned int)lines {
    _mutableState.maxScrollbackLines = lines;
    [self.mutableLineBuffer setMaxLines: lines];
    if (!_state.unlimitedScrollback) {
        [self incrementOverflowBy:[self.mutableLineBuffer dropExcessLinesWithWidth:_state.currentGrid.size.width]];
    }
    [delegate_ screenDidChangeNumberOfScrollbackLines];
}

- (void)mutPopScrollbackLines:(int)linesPushed {
    // Undo the appending of the screen to scrollback
    int i;
    screen_char_t* dummy = iTermCalloc(_state.currentGrid.size.width, sizeof(screen_char_t));
    for (i = 0; i < linesPushed; ++i) {
        int cont;
        BOOL isOk __attribute__((unused)) =
        [self.mutableLineBuffer popAndCopyLastLineInto:dummy
                                                 width:_state.currentGrid.size.width
                                     includesEndOfLine:&cont
                                              metadata:NULL
                                          continuation:NULL];
        ITAssertWithMessage(isOk, @"Pop shouldn't fail");
    }
    free(dummy);
}

- (void)incrementOverflowBy:(int)overflowCount {
    _mutableState.scrollbackOverflow += overflowCount;
    cumulativeScrollbackOverflow_ += overflowCount;
    [self.intervalTreeObserver intervalTreeVisibleRangeDidChange];
}

#pragma mark - Miscellaneous State

- (BOOL)mutGetAndResetHasScrolled {
    const BOOL result = _state.currentGrid.haveScrolled;
    self.mutableCurrentGrid.haveScrolled = NO;
    return result;
}

#pragma mark - Synchronized Drawing

- (PTYTextViewSynchronousUpdateState *)mutSetUseSavedGridIfAvailable:(BOOL)useSavedGrid {
    if (useSavedGrid && !_state.realCurrentGrid && self.temporaryDoubleBuffer.savedState) {
        _mutableState.realCurrentGrid = _state.currentGrid;
        _mutableState.currentGrid = self.temporaryDoubleBuffer.savedState.grid;
        self.temporaryDoubleBuffer.drewSavedGrid = YES;
        return self.temporaryDoubleBuffer.savedState;
    } else if (!useSavedGrid && _state.realCurrentGrid) {
        _mutableState.currentGrid = _state.realCurrentGrid;
        _mutableState.realCurrentGrid = nil;
    }
    return nil;
}

#pragma mark - File Transfer

- (void)mutStopTerminalReceivingFile {
    [_mutableState.terminal stopReceivingFile];
    [self mutFileReceiptEndedUnexpectedly];
}

- (void)mutFileReceiptEndedUnexpectedly {
    _mutableState.inlineImageHelper = nil;
    [delegate_ screenFileReceiptEndedUnexpectedly];
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
    [_state.terminal resetSavedCursorPositions];

    _mutableState.findContext.substring = nil;

    _mutableState.scrollbackOverflow = 0;
    [delegate_ screenRemoveSelection];

    [self.mutablePrimaryGrid markAllCharsDirty:YES];
    [self.mutableAltGrid markAllCharsDirty:YES];
}

@end
