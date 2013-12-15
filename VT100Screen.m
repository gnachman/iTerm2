/* Bugs found during testing
 - Cmd-I>terminal>put cursor in "scrollback lines", close window. It goes from 100000 to 100.
 - Attach to tmux that's running vimdiff. Open a new tmux tab, grow the window, and close the tab. vimdiff's display is messed up.
 - Save/restore alt screen in tmux is broken. Test that it's restored correctly, and that cursor position is also loaded properly on connecting.
 */

#import "VT100Screen.h"

#import "DebugLogging.h"
#import "DVR.h"
#import "IntervalTree.h"
#import "PTYNoteViewController.h"
#import "PTYTextView.h"
#import "RegexKitLite.h"
#import "SearchResult.h"
#import "TmuxStateParser.h"
#import "VT100ScreenMark.h"
#import "iTermExpose.h"
#import "iTermGrowlDelegate.h"

#include <string.h>
#include <unistd.h>

int kVT100ScreenMinColumns = 2;
int kVT100ScreenMinRows = 2;

static const int kDefaultScreenColumns = 80;
static const int kDefaultScreenRows = 25;
static const int kDefaultMaxScrollbackLines = 1000;
static const int kDefaultTabstopWidth = 8;

NSString * const kHighlightForegroundColor = @"kHighlightForegroundColor";
NSString * const kHighlightBackgroundColor = @"kHighlightBackgroundColor";

// Wait this long between calls to NSBeep().
static const double kInterBellQuietPeriod = 0.1;

@implementation VT100Screen

@synthesize terminal = terminal_;
@synthesize audibleBell = audibleBell_;
@synthesize showBellIndicator = showBellIndicator_;
@synthesize flashBell = flashBell_;
@synthesize postGrowlNotifications = postGrowlNotifications_;
@synthesize cursorBlinks = cursorBlinks_;
@synthesize allowTitleReporting = allowTitleReporting_;
@synthesize maxScrollbackLines = maxScrollbackLines_;
@synthesize unlimitedScrollback = unlimitedScrollback_;
@synthesize saveToScrollbackInAlternateScreen = saveToScrollbackInAlternateScreen_;
@synthesize dvr = dvr_;
@synthesize delegate = delegate_;
@synthesize savedCursor = savedCursor_;

- (id)initWithTerminal:(VT100Terminal *)terminal
{
    self = [super init];
    if (self) {
        assert(terminal);
        terminal_ = [terminal retain];
        primaryGrid_ = [[VT100Grid alloc] initWithSize:VT100GridSizeMake(kDefaultScreenColumns,
                                                                         kDefaultScreenRows)
                                              delegate:terminal];
        currentGrid_ = primaryGrid_;

        maxScrollbackLines_ = kDefaultMaxScrollbackLines;
        tabStops_ = [[NSMutableSet alloc] init];
        [self setInitialTabStops];
        linebuffer_ = [[LineBuffer alloc] init];

        [iTermGrowlDelegate sharedInstance];

        dvr_ = [DVR alloc];
        [dvr_ initWithBufferCapacity:[[PreferencePanel sharedInstance] irMemory] * 1024 * 1024];

        charsetUsesLineDrawingMode_ = [[NSMutableArray alloc] init];
        savedCharsetUsesLineDrawingMode_ = [[NSMutableArray alloc] init];
        for (int i = 0; i < NUM_CHARSETS; i++) {
            [charsetUsesLineDrawingMode_ addObject:[NSNumber numberWithBool:NO]];
            [savedCharsetUsesLineDrawingMode_ addObject:[NSNumber numberWithBool:NO]];
        }

        findContext_ = [[FindContext alloc] init];
        savedMarksAndNotes_ = [[IntervalTree alloc] init];
        marksAndNotes_ = [[IntervalTree alloc] init];
        markCache_ = [[NSMutableSet alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [primaryGrid_ release];
    [altGrid_ release];
    [tabStops_ release];
    [printBuffer_ release];
    [linebuffer_ release];
    [dvr_ release];
    [terminal_ release];
    [charsetUsesLineDrawingMode_ release];
    [findContext_ release];
    [marksAndNotes_ release];
    [markCache_ release];
    [super dealloc];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p grid:%@>", [self class], self, currentGrid_];
}

#pragma mark - APIs

- (void)setTerminal:(VT100Terminal *)terminal {
    [terminal_ autorelease];
    terminal_ = [terminal retain];
    primaryGrid_.delegate = terminal;
    altGrid_.delegate = terminal;
}

- (void)destructivelySetScreenWidth:(int)width height:(int)height
{
    width = MAX(width, kVT100ScreenMinColumns);
    height = MAX(height, kVT100ScreenMinRows);

    primaryGrid_.size = VT100GridSizeMake(width, height);
    altGrid_.size = VT100GridSizeMake(width, height);
    primaryGrid_.cursor = VT100GridCoordMake(0, 0);
    altGrid_.cursor = VT100GridCoordMake(0, 0);
    savedCursor_ = VT100GridCoordMake(0, 0);
    [primaryGrid_ resetScrollRegions];
    [altGrid_ resetScrollRegions];

    findContext_.substring = nil;

    scrollbackOverflow_ = 0;
    [delegate_ screenRemoveSelection];

    [primaryGrid_ markAllCharsDirty:YES];
    [altGrid_ markAllCharsDirty:YES];
}

- (VT100GridCoordRange)coordRangeForCurrentSelection {
    return VT100GridCoordRangeMake([delegate_ screenSelectionStartX],
                                   [delegate_ screenSelectionStartY],
                                   [delegate_ screenSelectionEndX],
                                   [delegate_ screenSelectionEndY]);
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

- (void)resizeWidth:(int)new_width height:(int)new_height
{
    DLog(@"Resize session to %d height", new_height);

    if (currentGrid_.size.width == 0 ||
        currentGrid_.size.height == 0 ||
        (new_width == currentGrid_.size.width &&
         new_height == currentGrid_.size.height)) {
            return;
    }
    VT100GridSize oldSize = currentGrid_.size;
    new_width = MAX(new_width, 1);
    new_height = MAX(new_height, 1);

    BOOL hasSelection = ([delegate_ screenHasView] &&
                         [delegate_ screenSelectionStartX] >= 0 &&
                         [delegate_ screenSelectionEndX] >= 0 &&
                         [delegate_ screenSelectionStartY] >= 0 &&
                         [delegate_ screenSelectionEndY] >= 0);

    int usedHeight = [currentGrid_ numberOfLinesUsed];

    VT100Grid *copyOfAltGrid = [[altGrid_ copy] autorelease];
    LineBuffer *realLineBuffer = linebuffer_;

    LineBufferPosition *originalLastPos = [linebuffer_ lastPosition];
    LineBufferPosition *originalStartPos = nil;
    LineBufferPosition *originalEndPos = nil;
    BOOL wasShowingAltScreen = (currentGrid_ == altGrid_);

    if (hasSelection && wasShowingAltScreen) {
        // In alternate screen mode, get the original positions of the
        // selection. Later this will be used to set the selection positions
        // relative to the end of the udpated linebuffer (which could change as
        // lines from the base screen are pushed onto it).
        BOOL ok1, ok2;
        LineBuffer *lineBufferWithAltScreen = [[linebuffer_ newAppendOnlyCopy] autorelease];
        [self appendScreen:currentGrid_
              toScrollback:lineBufferWithAltScreen
            withUsedHeight:usedHeight
                 newHeight:new_height];
        VT100GridCoordRange selection = [self coordRangeForCurrentSelection];

        [self getNullCorrectedSelectionStartPosition:&originalStartPos
                                         endPosition:&originalEndPos
                       selectionStartPositionIsValid:&ok1
                          selectionEndPostionIsValid:&ok2
                                        inLineBuffer:lineBufferWithAltScreen
                                            forRange:selection];
        hasSelection = ok1 && ok2;
    }

    // If we're in the alternate screen, create a temporary linebuffer and append
    // the base screen's contents to it.
    LineBuffer *altScreenLineBuffer = nil;
    if (wasShowingAltScreen) {
        altScreenLineBuffer = [[[LineBuffer alloc] init] autorelease];
        [self appendScreen:altGrid_
              toScrollback:altScreenLineBuffer
            withUsedHeight:usedHeight
                 newHeight:new_height];
    }

    // If non-nil, contains 3-tuples NSArray*s of
    // [ PTYNoteViewController*,
    //   LineBufferPosition* for start of range,
    //   LineBufferPosition* for end of range ]
    // These will be re-added to marksAndNotes_ later on.
    NSMutableArray *altScreenNotes = nil;

    if (wasShowingAltScreen && [marksAndNotes_ count]) {
        // Add notes that were on the alt grid to altScreenNotes, leaving notes in history alone.
        VT100GridCoordRange screenCoordRange =
        VT100GridCoordRangeMake(0,
                                [self numberOfScrollbackLines],
                                0,
                                [self numberOfScrollbackLines] + self.height);
        NSArray *notesAtLeastPartiallyOnScreen =
            [marksAndNotes_ objectsInInterval:[self intervalForGridCoordRange:screenCoordRange]];
        
        LineBuffer *appendOnlyLineBuffer = [[realLineBuffer newAppendOnlyCopy] autorelease];
        [self appendScreen:altGrid_
              toScrollback:appendOnlyLineBuffer
            withUsedHeight:usedHeight
                 newHeight:new_height];
        altScreenNotes = [NSMutableArray array];
        
        for (id<IntervalTreeObject> note in notesAtLeastPartiallyOnScreen) {
            VT100GridCoordRange range = [self coordRangeForInterval:note.entry.interval];
            [[note retain] autorelease];
            [marksAndNotes_ removeObject:note];
            
            BOOL ok1, ok2;
            LineBufferPosition *startPosition = nil;
            LineBufferPosition *endPosition = nil;
            
            [self getNullCorrectedSelectionStartPosition:&startPosition
                                             endPosition:&endPosition
                           selectionStartPositionIsValid:&ok1
                              selectionEndPostionIsValid:&ok2
                                            inLineBuffer:appendOnlyLineBuffer
                                                forRange:range];
            NSLog(@"Add note on alt screen at %@ (position %@ to %@) to altScreenNotes",
                  VT100GridCoordRangeDescription(range),
                  startPosition,
                  endPosition);
            [altScreenNotes addObject:@[ note, startPosition, endPosition ]];
        }
    }
    
    if (wasShowingAltScreen) {
      currentGrid_ = primaryGrid_;
      // Move savedMarksAndNotes_ into marksAndNotes_. This should leave savedMarksAndNotes_ empty.
      [self swapNotes];
      currentGrid_ = altGrid_;
    }

    // Append primary grid to line buffer.
    [self appendScreen:primaryGrid_
          toScrollback:linebuffer_
        withUsedHeight:[primaryGrid_ numberOfLinesUsed]
             newHeight:new_height];

    VT100GridCoordRange newSelection;
    if (!wasShowingAltScreen && hasSelection) {
        hasSelection = [self convertRange:[self coordRangeForCurrentSelection]
                                  toWidth:new_width
                                       to:&newSelection
                             inLineBuffer:linebuffer_];
    }
    
    if ([marksAndNotes_ count]) {
        // Fix up the intervals for the primary grid.
        if (wasShowingAltScreen) {
            // Temporarily swap in primary grid so convertRange: will do the right thing.
            currentGrid_ = primaryGrid_;
        }

        // Convert ranges of notes to their new coordinates and replace the interval tree.
        IntervalTree *replacementTree = [[IntervalTree alloc] init];
        for (id<IntervalTreeObject> note in [marksAndNotes_ allObjects]) {
            VT100GridCoordRange noteRange = [self coordRangeForInterval:note.entry.interval];
            VT100GridCoordRange newRange;
            if ([self convertRange:noteRange toWidth:new_width to:&newRange inLineBuffer:linebuffer_]) {
                Interval *newInterval = [self intervalForGridCoordRange:newRange
                                                                  width:new_width
                                                            linesOffset:[self totalScrollbackOverflow]];
                [[note retain] autorelease];
                [marksAndNotes_ removeObject:note];
                [replacementTree addObject:note withInterval:newInterval];
            }
        }
        [marksAndNotes_ release];
        marksAndNotes_ = replacementTree;
        
        if (wasShowingAltScreen) {
            // Return to alt grid.
            currentGrid_ = altGrid_;
        }
    }
    VT100GridSize newSize = VT100GridSizeMake(new_width, new_height);
    currentGrid_.size = newSize;

    // Restore the screen contents that were pushed onto the linebuffer.
    [currentGrid_ restoreScreenFromLineBuffer:wasShowingAltScreen ? altScreenLineBuffer : linebuffer_
                              withDefaultChar:[currentGrid_ defaultChar]
                            maxLinesToRestore:[linebuffer_ numLinesWithWidth:currentGrid_.size.width]];

    // If we're in the alternate screen, restore its contents from the temporary
    // linebuffer.
    if (wasShowingAltScreen) {
        // In alternate screen mode, the screen contents move up when the screen gets smaller.
        // For example, if your alt screen looks like this before:
        //   abcd
        //   ef..
        // And then gets shrunk to 3 wide, it becomes
        //   d..
        //   ef.
        // The "abc" line was lost, so "linesMovedUp" is 1. That's the number of lines at the top
        // of the alt screen that were lost.
        int linesMovedUp = [altScreenLineBuffer numLinesWithWidth:currentGrid_.size.width];
        
        primaryGrid_.size = newSize;
        [primaryGrid_ setCharsFrom:VT100GridCoordMake(0, 0)
                                to:VT100GridCoordMake(newSize.width - 1, newSize.height - 1)
                            toChar:primaryGrid_.savedDefaultChar];
        if (oldSize.height < new_height) {
            // Growing (avoid pulling in stuff from scrollback. Add blank lines
            // at bottom instead). Note there's a little hack here: we use saved_primary_buffer as the default
            // line because it was just initialized with default lines.
            [primaryGrid_ restoreScreenFromLineBuffer:realLineBuffer
                                      withDefaultChar:[primaryGrid_ defaultChar]
                                    maxLinesToRestore:oldSize.height];
        } else {
            // Shrinking (avoid pulling in stuff from scrollback, pull in no more
            // than might have been pushed, even if more is available). Note there's a little hack
            // here: we use saved_primary_buffer as the default line because it was just initialized with
            // default lines.
            [primaryGrid_ restoreScreenFromLineBuffer:realLineBuffer
                                      withDefaultChar:[primaryGrid_ defaultChar]
                                    maxLinesToRestore:new_height];
        }

        // Any onscreen notes in primary grid get moved to savedMarksAndNotes_.
        currentGrid_ = primaryGrid_;
        [self swapNotes];
        currentGrid_ = altGrid_;

        LineBufferPosition *newLastPos = [realLineBuffer lastPosition];

        ///////////////////////////////////////
        // Create a cheap append-only copy of the line buffer and add the
        // screen to it. This sets up the current state so that if there is a
        // selection, linebuffer has the configuration that the user actually
        // sees (history + the alt screen contents). That'll make
        // convertRange:toWidth:... happy (the selection's Y values
        // will be able to be looked up) and then after that's done we can swap
        // back to the tempLineBuffer.
        LineBuffer *appendOnlyLineBuffer = [[realLineBuffer newAppendOnlyCopy] autorelease];

        [self appendScreen:copyOfAltGrid
              toScrollback:appendOnlyLineBuffer
            withUsedHeight:usedHeight
                 newHeight:new_height];

        if (hasSelection) {
            hasSelection = [self computeRangeFromOriginalLimit:originalLastPos
                                                 limitPosition:newLastPos
                                                 startPosition:originalStartPos
                                                   endPosition:originalEndPos
                                                      newWidth:new_width
                                                    lineBuffer:appendOnlyLineBuffer
                                                         range:&newSelection
                                                  linesMovedUp:linesMovedUp];
        }
        NSLog(@"Original limit=%@", originalLastPos);
        NSLog(@"New limit=%@", newLastPos);
        for (NSArray *tuple in altScreenNotes) {
            id<IntervalTreeObject> note = tuple[0];
            LineBufferPosition *start = tuple[1];
            LineBufferPosition *end = tuple[2];
            VT100GridCoordRange newRange;
            NSLog(@"  Note positions=%@ to %@", start, end);
            BOOL ok = [self computeRangeFromOriginalLimit:originalLastPos
                                            limitPosition:newLastPos
                                            startPosition:start
                                              endPosition:end
                                                 newWidth:new_width
                                               lineBuffer:appendOnlyLineBuffer
                                                    range:&newRange
                                             linesMovedUp:linesMovedUp];
            if (ok) {
                NSLog(@"  New range=%@", VT100GridCoordRangeDescription(newRange));
                Interval *interval = [self intervalForGridCoordRange:newRange
                                                               width:new_width
                                                         linesOffset:[self totalScrollbackOverflow]];
                [marksAndNotes_ addObject:note withInterval:interval];
            } else {
                NSLog(@"  *FAILED TO CONVERT*");
            }
        }
    } else {
        // Was showing primary grid. Fix up notes in the alt screen.

        // Append alt screen to empty line buffer
        altScreenLineBuffer = [[[LineBuffer alloc] init] autorelease];
        [self appendScreen:altGrid_
              toScrollback:altScreenLineBuffer
            withUsedHeight:[altGrid_ numberOfLinesUsed]
                 newHeight:new_height];
        int numLinesThatWillBeRestored = MIN([altScreenLineBuffer numLinesWithWidth:new_width],
                                             new_height);
        int numLinesDroppedFromTop = [altScreenLineBuffer numLinesWithWidth:new_width] - numLinesThatWillBeRestored;
        
        // Convert note ranges to new coords, dropping or truncating as needed
        currentGrid_ = altGrid_;  // Swap to alt grid temporarily for convertRange:toWidth:to:inLineBuffer:
        IntervalTree *replacementTree = [[IntervalTree alloc] init];
        for (PTYNoteViewController *note in [savedMarksAndNotes_ allObjects]) {
            VT100GridCoordRange noteRange = [self coordRangeForInterval:note.entry.interval];
            NSLog(@"Found note at %@", VT100GridCoordRangeDescription(noteRange));
            VT100GridCoordRange newRange;
            if ([self convertRange:noteRange toWidth:new_width to:&newRange inLineBuffer:altScreenLineBuffer]) {
                // Anticipate the lines that will be dropped when the alt grid is restored.
                newRange.start.y += [self totalScrollbackOverflow] - numLinesDroppedFromTop;
                newRange.end.y += [self totalScrollbackOverflow] - numLinesDroppedFromTop;
                if (newRange.start.y < 0) {
                    newRange.start.y = 0;
                    newRange.start.x = 0;
                }
                NSLog(@"  Its new range is %@ including %d lines dropped from top", VT100GridCoordRangeDescription(noteRange), numLinesDroppedFromTop);
                [savedMarksAndNotes_ removeObject:note];
                if (newRange.end.y > 0 || (newRange.end.y == 0 && newRange.end.x > 0)) {
                    Interval *newInterval = [self intervalForGridCoordRange:newRange
                                                                      width:new_width
                                                                linesOffset:0];
                    [replacementTree addObject:note withInterval:newInterval];
                } else {
                    NSLog(@"Failed to convert");
                }
            }
        }
        [savedMarksAndNotes_ release];
        savedMarksAndNotes_ = replacementTree;
        currentGrid_ = primaryGrid_;  // Swap back to primary grid
        
        // Restore alt screen with new width
        altGrid_.size = VT100GridSizeMake(new_width, new_height);
        [altGrid_ restoreScreenFromLineBuffer:altScreenLineBuffer
                              withDefaultChar:[altGrid_ defaultChar]
                            maxLinesToRestore:[altScreenLineBuffer numLinesWithWidth:currentGrid_.size.width]];
    }

    savedCursor_.x = MIN(new_width - 1, savedCursor_.x);
    savedCursor_.y = MIN(new_height - 1, savedCursor_.y);

    [primaryGrid_ resetScrollRegions];
    [altGrid_ resetScrollRegions];
    [primaryGrid_ clampCursorPositionToValid];
    [altGrid_ clampCursorPositionToValid];

    // The linebuffer may have grown. Ensure it doesn't have too many lines.
    int linesDropped = 0;
    if (!unlimitedScrollback_) {
        linesDropped = [linebuffer_ dropExcessLinesWithWidth:currentGrid_.size.width];
        [self incrementOverflowBy:linesDropped];
    }
    int lines = [linebuffer_ numLinesWithWidth:currentGrid_.size.width];
    NSAssert(lines >= 0, @"Negative lines");

    // An immediate refresh is needed so that the size of TEXTVIEW can be
    // adjusted to fit the new size
    DebugLog(@"resizeWidth setDirty");
    [delegate_ screenNeedsRedraw];
    if (hasSelection &&
        newSelection.start.y >= linesDropped &&
        newSelection.end.y >= linesDropped) {
        [delegate_ screenSetSelectionFromX:newSelection.start.x
                                     fromY:newSelection.start.y - linesDropped
                                       toX:newSelection.end.x
                                       toY:newSelection.end.y - linesDropped];
    } else {
        [delegate_ screenRemoveSelection];
    }

    [self reloadMarkCache];
    [delegate_ screenSizeDidChange];
}

- (void)reloadMarkCache {
    [markCache_ removeAllObjects];
    for (id<IntervalTreeObject> obj in [marksAndNotes_ allObjects]) {
        if ([obj isKindOfClass:[VT100ScreenMark class]]) {
            VT100GridCoordRange range = [self coordRangeForInterval:obj.entry.interval];
            [markCache_ addObject:@(range.end.y)];
        }
    }
}

- (BOOL)allCharacterSetPropertiesHaveDefaultValues {
    for (int i = 0; i < NUM_CHARSETS; i++) {
        if ([[charsetUsesLineDrawingMode_ objectAtIndex:i] boolValue]) {
            return NO;
        }
    }
    if ([terminal_ charset]) {
        return NO;
    }
    return YES;
}

- (void)showCursor:(BOOL)show
{
    [delegate_ screenSetCursorVisible:show];
}

- (void)clearBuffer
{
    [self clearAndResetScreenPreservingCursorLine];
    [self clearScrollbackBuffer];
    [delegate_ screenUpdateDisplay];
}

// This clears the screen, leaving the cursor's line at the top and preserves the cursor's x
// coordinate. Scroll regions and the saved cursor position are reset.
- (void)clearAndResetScreenPreservingCursorLine {
    [delegate_ screenTriggerableChangeDidOccur];
    // This clears the screen.
    int x = currentGrid_.cursorX;
    [self incrementOverflowBy:[currentGrid_ resetWithLineBuffer:linebuffer_
                                            unlimitedScrollback:unlimitedScrollback_
                                             preserveCursorLine:YES]];
    currentGrid_.cursorX = x;
}

- (void)clearScrollbackBuffer
{
    [linebuffer_ release];
    linebuffer_ = [[LineBuffer alloc] init];
    [linebuffer_ setMaxLines:maxScrollbackLines_];
    [delegate_ screenClearHighlights];
    [currentGrid_ markAllCharsDirty:YES];

    savedFindContextAbsPos_ = 0;

    [self resetScrollbackOverflow];
    [delegate_ screenRemoveSelection];
    [currentGrid_ markAllCharsDirty:YES];
    [marksAndNotes_ release];
    marksAndNotes_ = [[IntervalTree alloc] init];
    [self reloadMarkCache];
}

- (void)appendStringAtCursor:(NSString *)string ascii:(BOOL)ascii
{
    DLog(@"setString: %ld chars starting with %c at x=%d, y=%d, line=%d",
         (unsigned long)[string length],
         [string characterAtIndex:0],
         currentGrid_.cursorX,
         currentGrid_.cursorY,
         currentGrid_.cursorY + [linebuffer_ numLinesWithWidth:currentGrid_.size.width]);

    int len = [string length];
    if (len < 1 || !string) {
        return;
    }

    // Allocate a buffer of screen_char_t and place the new string in it.
    const int kStaticBufferElements = 1024;
    screen_char_t staticBuffer[kStaticBufferElements];
    screen_char_t *dynamicBuffer = 0;
    screen_char_t *buffer;
    if (ascii) {
        // Only Unicode code points 0 through 127 occur in the string.
        const int kStaticTempElements = kStaticBufferElements;
        unichar staticTemp[kStaticTempElements];
        unichar* dynamicTemp = 0;
        unichar *sc;
        if ([string length] > kStaticTempElements) {
            dynamicTemp = sc = (unichar *) calloc(len, sizeof(unichar));
            assert(dynamicTemp);
        } else {
            sc = staticTemp;
        }
        assert(terminal_);
        screen_char_t fg = [terminal_ foregroundColorCode];
        screen_char_t bg = [terminal_ backgroundColorCode];

        if ([string length] > kStaticBufferElements) {
            buffer = dynamicBuffer = (screen_char_t *) calloc([string length],
                                                              sizeof(screen_char_t));
            assert(dynamicBuffer);
            if (!buffer) {
                NSLog(@"%s: Out of memory", __PRETTY_FUNCTION__);
                return;
            }
        } else {
            buffer = staticBuffer;
        }

        [string getCharacters:sc];
        for (int i = 0; i < len; i++) {
            buffer[i].code = sc[i];
            buffer[i].complexChar = NO;
            CopyForegroundColor(&buffer[i], fg);
            CopyBackgroundColor(&buffer[i], bg);
            buffer[i].unused = 0;
        }

        // If a graphics character set was selected then translate buffer
        // characters into graphics charaters.
        if ([[charsetUsesLineDrawingMode_ objectAtIndex:[terminal_ charset]] boolValue]) {
            ConvertCharsToGraphicsCharset(buffer, len);
        }
        if (dynamicTemp) {
            free(dynamicTemp);
        }
    } else {
        string = [string precomposedStringWithCanonicalMapping];
        len = [string length];
        if (2 * len > kStaticBufferElements) {
            buffer = dynamicBuffer = (screen_char_t *) calloc(2 * len,
                                                              sizeof(screen_char_t));
            assert(buffer);
            if (!buffer) {
                NSLog(@"%s: Out of memory", __PRETTY_FUNCTION__);
                return;
            }
        } else {
            buffer = staticBuffer;
        }

        // Pick off leading combining marks and low surrogates and modify the
        // character at the cursor position with them.
        unichar firstChar = [string characterAtIndex:0];
        while ([string length] > 0 &&
               (IsCombiningMark(firstChar) || IsLowSurrogate(firstChar))) {
            VT100GridCoord pred = [currentGrid_ coordinateBefore:currentGrid_.cursor];
            if (pred.x < 0 ||
                ![currentGrid_ addCombiningChar:firstChar toCoord:pred]) {
                // Combining mark will need to stand alone rather than combine
                // because nothing precedes it.
                if (IsCombiningMark(firstChar)) {
                    // Prepend a space to it so the combining mark has something
                    // to combine with.
                    string = [NSString stringWithFormat:@" %@", string];
                } else {
                    // Got a low surrogate but can't find the matching high
                    // surrogate. Turn the low surrogate into a replacement
                    // char. This should never happen because decode_string
                    // ought to detect the broken unicode and substitute a
                    // replacement char.
                    string = [NSString stringWithFormat:@"%@%@",
                              ReplacementString(),
                              [string substringFromIndex:1]];
                }
                len = [string length];
                break;
            }
            string = [string substringFromIndex:1];
            if ([string length] > 0) {
                firstChar = [string characterAtIndex:0];
            }
        }

        assert(terminal_);
        // Add DWC_RIGHT after each double-byte character, build complex characters out of surrogates
        // and combining marks, replace private codes with replacement characters, swallow zero-
        // width spaces, and set fg/bg colors and attributes.
        StringToScreenChars(string,
                            buffer,
                            [terminal_ foregroundColorCode],
                            [terminal_ backgroundColorCode],
                            &len,
                            [delegate_ screenShouldTreatAmbiguousCharsAsDoubleWidth],
                            NULL);
    }

    if (len < 1) {
        // The string is empty so do nothing.
        if (dynamicBuffer) {
            free(dynamicBuffer);
        }
        return;
    }

    [self incrementOverflowBy:[currentGrid_ appendCharsAtCursor:buffer
                                                         length:len
                                        scrollingIntoLineBuffer:linebuffer_
                                            unlimitedScrollback:unlimitedScrollback_
                                        useScrollbackWithRegion:[self useScrollbackWithRegion]]];


    if (dynamicBuffer) {
        free(dynamicBuffer);
    }
}

- (void)crlf
{
    [self linefeed];
    currentGrid_.cursorX = 0;
}

- (void)linefeed
{
    LineBuffer *lineBufferToUse = linebuffer_;
    if (currentGrid_ == altGrid_ && !saveToScrollbackInAlternateScreen_) {
        // In alt grid but saving to scrollback in alt-screen is off, so pass in a nil linebuffer.
        lineBufferToUse = nil;
        // This is a temporary hack. In this case, keeping the selection in the right place requires
        // more cooperation between VT100Screen and PTYTextView than is currently in place because
        // the selection could become truncated, and regardless, will need to move up a line in terms
        // of absolute Y position (normally when the screen scrolls the absolute Y position of the
        // selection stays the same and the viewport moves down, or else there is soem scrollback
        // overflow and PTYTextView -refresh bumps the selection's Y position, but because in this
        // case we don't append to the line buffer, scrollback overflow will not increment).
        [delegate_ screenRemoveSelection];
    }
    [self incrementOverflowBy:[currentGrid_ moveCursorDownOneLineScrollingIntoLineBuffer:lineBufferToUse
                                                                     unlimitedScrollback:unlimitedScrollback_
                                                                 useScrollbackWithRegion:[self useScrollbackWithRegion]]];
}

- (void)cursorToX:(int)x
{
    int xPos;
    int leftMargin = [currentGrid_ leftMargin];
    int rightMargin = [currentGrid_ rightMargin];

    xPos = x - 1;

    if ([terminal_ originMode]) {
        xPos += leftMargin;
        xPos = MAX(leftMargin, MIN(rightMargin, xPos));
    }

    currentGrid_.cursorX = xPos;

    DebugLog(@"cursorToX");
    
}

- (void)activateBell
{
    if (audibleBell_) {
        // Some bells or systems block on NSBeep so it's important to rate-limit it to prevent
        // bells from blocking the terminal indefinitely. The small delay we insert between
        // bells allows us to swallow up the vast majority of ^G characters when you cat a
        // binary file.
        static NSDate *lastBell;
        double interval = lastBell ? [[NSDate date] timeIntervalSinceDate:lastBell] : INFINITY;
        if (interval > kInterBellQuietPeriod) {
            NSBeep();
            [lastBell release];
            lastBell = [[NSDate date] retain];
        }
    }
    if (showBellIndicator_) {
        [delegate_ screenShowBellIndicator];
    }
    if (flashBell_) {
        [delegate_ screenFlashImage:FlashBell];
    }
}

- (void)setHistory:(NSArray *)history
{
    // This is way more complicated than it should be to work around something dumb in tmux.
    // It pads lines in its history with trailing spaces, which we'd like to trim. More importantly,
    // we need to trim empty lines at the end of the history because that breaks how we move the
    // screen contents around on resize. So we take the history from tmux, append it to a temporary
    // line buffer, grab each wrapped line and trim spaces from it, and then append those modified
    // line (excluding empty ones at the end) to the real line buffer.
    [self clearBuffer];
    LineBuffer *temp = [[[LineBuffer alloc] init] autorelease];
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    for (NSData *chars in history) {
        screen_char_t *line = (screen_char_t *) [chars bytes];
        const int len = [chars length] / sizeof(screen_char_t);
        [temp appendLine:line
                  length:len
                 partial:NO
                   width:currentGrid_.size.width
               timestamp:now];
    }
    NSMutableArray *wrappedLines = [NSMutableArray array];
    int n = [temp numLinesWithWidth:currentGrid_.size.width];
    int numberOfConsecutiveEmptyLines = 0;
    for (int i = 0; i < n; i++) {
        ScreenCharArray *line = [temp wrappedLineAtIndex:i width:currentGrid_.size.width];
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
        [linebuffer_ appendLine:line.line
                         length:line.length
                        partial:(line.eol != EOL_HARD)
                          width:currentGrid_.size.width
                      timestamp:now];
    }
    if (!unlimitedScrollback_) {
        [linebuffer_ dropExcessLinesWithWidth:currentGrid_.size.width];
    }

    // We don't know the cursor position yet but give the linebuffer something
    // so it doesn't get confused in restoreScreenFromScrollback.
    [linebuffer_ setCursor:0];
    [currentGrid_ restoreScreenFromLineBuffer:linebuffer_
                              withDefaultChar:[currentGrid_ defaultChar]
                            maxLinesToRestore:MIN([linebuffer_ numLinesWithWidth:currentGrid_.size.width],
                                                  currentGrid_.size.height - numberOfConsecutiveEmptyLines)];
}

- (void)setAltScreen:(NSArray *)lines
{
    if (!altGrid_) {
        altGrid_ = [primaryGrid_ copy];
    }

    // Initialize alternate screen to be empty
    [altGrid_ setCharsFrom:VT100GridCoordMake(0, 0)
                        to:VT100GridCoordMake(altGrid_.size.width - 1, altGrid_.size.height - 1)
                    toChar:[altGrid_ defaultChar]];
    // Copy the lines back over it
    int o = 0;
    for (int i = 0; o < altGrid_.size.height && i < MIN(lines.count, altGrid_.size.height); i++) {
        NSData *chars = [lines objectAtIndex:i];
        screen_char_t *line = (screen_char_t *) [chars bytes];
        int length = [chars length] / sizeof(screen_char_t);

        do {
            // Add up to altGrid_.size.width characters at a time until they're all used.
            screen_char_t *dest = [altGrid_ screenCharsAtLineNumber:o];
            memcpy(dest, line, MIN(altGrid_.size.width, length) * sizeof(screen_char_t));
            const BOOL isPartial = (length > altGrid_.size.width);
            dest[altGrid_.size.width].code = (isPartial ? EOL_SOFT : EOL_HARD);
            length -= altGrid_.size.width;
            line += altGrid_.size.width;
            o++;
        } while (o < altGrid_.size.height && length > 0);
    }
}

- (void)setTmuxState:(NSDictionary *)state
{
    BOOL inAltScreen = [[self objectInDictionary:state
                                withFirstKeyFrom:[NSArray arrayWithObjects:kStateDictSavedGrid,
                                                  kStateDictSavedGrid,
                                                  nil]] intValue];
    if (inAltScreen) {
        // Alt and primary have been populated with each other's content.
        VT100Grid *temp = altGrid_;
        altGrid_ = primaryGrid_;
        primaryGrid_ = temp;
    }

    NSNumber *altSavedX = [state objectForKey:kStateDictAltSavedCX];
    NSNumber *altSavedY = [state objectForKey:kStateDictAltSavedCY];
    if (altSavedX && altSavedY && inAltScreen) {
        primaryGrid_.cursor = VT100GridCoordMake([altSavedX intValue], [altSavedY intValue]);
    }

    NSNumber *savedX = [state objectForKey:kStateDictSavedCX];
    NSNumber *savedY = [state objectForKey:kStateDictSavedCY];
    if (savedX && savedY) {
        savedCursor_ = VT100GridCoordMake([savedX intValue], [savedY intValue]);
    }

    currentGrid_.cursorX = [[state objectForKey:kStateDictCursorX] intValue];
    currentGrid_.cursorY = [[state objectForKey:kStateDictCursorY] intValue];
    int top = [[state objectForKey:kStateDictScrollRegionUpper] intValue];
    int bottom = [[state objectForKey:kStateDictScrollRegionLower] intValue];
    currentGrid_.scrollRegionRows = VT100GridRangeMake(top, bottom - top + 1);
    [self showCursor:[[state objectForKey:kStateDictCursorMode] boolValue]];

    [tabStops_ removeAllObjects];
    int maxTab = 0;
    for (NSNumber *n in [state objectForKey:kStateDictTabstops]) {
        [tabStops_ addObject:n];
        maxTab = MAX(maxTab, [n intValue]);
    }
    for (int i = 0; i < 1000; i += 8) {
        if (i > maxTab) {
            [tabStops_ addObject:[NSNumber numberWithInt:i]];
        }
    }

    NSNumber *cursorMode = [state objectForKey:kStateDictCursorMode];
    if (cursorMode) {
        [self terminalSetCursorVisible:!![cursorMode intValue]];
    }

    // Everything below this line needs testing
    NSNumber *insertMode = [state objectForKey:kStateDictInsertMode];
    if (insertMode) {
        [terminal_ setInsertMode:!![insertMode intValue]];
    }

    NSNumber *applicationCursorKeys = [state objectForKey:kStateDictKCursorMode];
    if (applicationCursorKeys) {
        [terminal_ setCursorMode:!![applicationCursorKeys intValue]];
    }

    NSNumber *keypad = [state objectForKey:kStateDictKKeypadMode];
    if (keypad) {
        [terminal_ setKeypadMode:!![keypad boolValue]];
    }

    NSNumber *mouse = [state objectForKey:kStateDictMouseStandardMode];
    if (mouse && [mouse intValue]) {
        [terminal_ setMouseMode:MOUSE_REPORTING_NORMAL];
    }
    mouse = [state objectForKey:kStateDictMouseButtonMode];
    if (mouse && [mouse intValue]) {
        [terminal_ setMouseMode:MOUSE_REPORTING_BUTTON_MOTION];
    }
    mouse = [state objectForKey:kStateDictMouseButtonMode];
    if (mouse && [mouse intValue]) {
        [terminal_ setMouseMode:MOUSE_REPORTING_ALL_MOTION];
    }
    mouse = [state objectForKey:kStateDictMouseUTF8Mode];
    if (mouse && [mouse intValue]) {
        [terminal_ setMouseFormat:MOUSE_FORMAT_XTERM_EXT];
    }

    NSNumber *wrap = [state objectForKey:kStateDictWrapMode];
    if (wrap) {
        [terminal_ setWraparoundMode:!![wrap intValue]];
    }
}

// Change color of text on screen that matches regex to the color of prototypechar.
- (void)highlightTextMatchingRegex:(NSString *)regex
                            colors:(NSDictionary *)colors
{
    NSArray *runs = [currentGrid_ runsMatchingRegex:regex];
    for (NSValue *run in runs) {
        [self highlightRun:[run gridRunValue]
       withForegroundColor:[colors objectForKey:kHighlightForegroundColor]
           backgroundColor:[colors objectForKey:kHighlightBackgroundColor]];
    }
}

- (void)setFromFrame:(screen_char_t*)s len:(int)len info:(DVRFrameInfo)info
{
    assert(len == (info.width + 1) * info.height * sizeof(screen_char_t));
    [currentGrid_ setContentsFromDVRFrame:s info:info];
    [self resetScrollbackOverflow];
    savedFindContextAbsPos_ = 0;
    [delegate_ screenRemoveSelection];
    [delegate_ screenNeedsRedraw];
    [currentGrid_ markAllCharsDirty:YES];
}

- (void)storeLastPositionInLineBufferAsFindContextSavedPosition
{
    savedFindContextAbsPos_ = [linebuffer_ absPositionForPosition:[linebuffer_ lastPos]];
}

- (void)restoreSavedPositionToFindContext:(FindContext *)context
{
    int linesPushed;
    linesPushed = [currentGrid_ appendLines:[currentGrid_ numberOfLinesUsed]
                               toLineBuffer:linebuffer_];

    [linebuffer_ storeLocationOfAbsPos:savedFindContextAbsPos_
                             inContext:context];

    [self popScrollbackLines:linesPushed];
}

- (void)resetCharset {
    [charsetUsesLineDrawingMode_ removeAllObjects];
    for (int i = 0; i < NUM_CHARSETS; i++) {
        [charsetUsesLineDrawingMode_ addObject:[NSNumber numberWithBool:NO]];
    }
}

#pragma mark - PTYTextViewDataSource

// This is a wee hack until PTYTextView breaks its direct dependence on PTYSession
- (PTYSession *)session {
    return (PTYSession *)delegate_;
}

// Returns the number of lines in scrollback plus screen height.
- (int)numberOfLines
{
    return [linebuffer_ numLinesWithWidth:currentGrid_.size.width] + currentGrid_.size.height;
}

- (int)width
{
    return currentGrid_.size.width;
}

- (int)height
{
    return currentGrid_.size.height;
}

- (int)cursorX
{
    return currentGrid_.cursorX + 1;
}

- (int)cursorY
{
    return currentGrid_.cursorY + 1;
}

// Like getLineAtIndex:withBuffer:, but uses dedicated storage for the result.
// This function is dangerous! It writes to an internal buffer and returns a
// pointer to it. Better to use getLineAtIndex:withBuffer:.
- (screen_char_t *)getLineAtIndex:(int)theIndex
{
    return [self getLineAtIndex:theIndex withBuffer:[currentGrid_ resultLine]];
}

// theIndex = 0 for first line in history; for sufficiently large values, it pulls from the current
// grid.
- (screen_char_t *)getLineAtIndex:(int)theIndex withBuffer:(screen_char_t*)buffer
{
    int numLinesInLineBuffer = [linebuffer_ numLinesWithWidth:currentGrid_.size.width];
    if (theIndex >= numLinesInLineBuffer) {
        // Get a line from the circular screen buffer
        return [currentGrid_ screenCharsAtLineNumber:(theIndex - numLinesInLineBuffer)];
    } else {
        // Get a line from the scrollback buffer.
        screen_char_t *defaultLine = [[currentGrid_ defaultLineOfWidth:currentGrid_.size.width] mutableBytes];
        memcpy(buffer, defaultLine, sizeof(screen_char_t) * currentGrid_.size.width);
        int cont = [linebuffer_ copyLineToBuffer:buffer
                                           width:currentGrid_.size.width
                                         lineNum:theIndex];
        if (cont == EOL_SOFT &&
            theIndex == numLinesInLineBuffer - 1 &&
            [currentGrid_ screenCharsAtLineNumber:0][1].code == DWC_RIGHT &&
            buffer[currentGrid_.size.width - 1].code == 0) {
            // The last line in the scrollback buffer is actually a split DWC
            // if the first char on the screen is double-width and the buffer is soft-wrapped without
            // a last char.
            cont = EOL_DWC;
        }
        if (cont == EOL_DWC) {
            buffer[currentGrid_.size.width - 1].code = DWC_SKIP;
            buffer[currentGrid_.size.width - 1].complexChar = NO;
        }
        buffer[currentGrid_.size.width].code = cont;

        return buffer;
    }
}

// Gets a line on the screen (0 = top of screen)
- (screen_char_t *)getLineAtScreenIndex:(int)theIndex
{
    return [currentGrid_ screenCharsAtLineNumber:theIndex];
}

- (int)numberOfScrollbackLines
{
    return [linebuffer_ numLinesWithWidth:currentGrid_.size.width];
}

- (int)scrollbackOverflow
{
    return scrollbackOverflow_;
}

- (void)resetScrollbackOverflow
{
    scrollbackOverflow_ = 0;
}

- (long long)totalScrollbackOverflow
{
    return cumulativeScrollbackOverflow_;
}

- (long long)absoluteLineNumberOfCursor
{
    return [self totalScrollbackOverflow] + [self numberOfLines] - [self height] + currentGrid_.cursorY;
}

- (BOOL)continueFindAllResults:(NSMutableArray*)results
                     inContext:(FindContext*)context
{
    context.hasWrapped = YES;
    NSDate* start = [NSDate date];
    BOOL keepSearching;
    do {
        keepSearching = [self continueFindResultsInContext:context
                                                   toArray:results];
    } while (keepSearching &&
             [[NSDate date] timeIntervalSinceDate:start] < context.maxTime);

    return keepSearching;
}

- (FindContext*)findContext
{
    return findContext_;
}

- (void)setFindString:(NSString*)aString
     forwardDirection:(BOOL)direction
         ignoringCase:(BOOL)ignoreCase
                regex:(BOOL)regex
          startingAtX:(int)x
          startingAtY:(int)y
           withOffset:(int)offset
            inContext:(FindContext*)context
      multipleResults:(BOOL)multipleResults
{
    // Append the screen contents to the scrollback buffer so they are included in the search.
    int linesPushed = [currentGrid_ appendLines:[currentGrid_ numberOfLinesUsed]
                                   toLineBuffer:linebuffer_];

    // Get the start position of (x,y)
    LineBufferPosition *startPos;
    startPos = [linebuffer_ positionForCoordinate:VT100GridCoordMake(x, y)
                                            width:currentGrid_.size.width
                                           offset:offset * (direction ? 1 : -1)];
    if (!startPos) {
        // x,y wasn't a real position in the line buffer, probably a null after the end.
        if (direction) {
            startPos = [linebuffer_ firstPosition];
        } else {
            startPos = [[linebuffer_ lastPosition] predecessor];
        }
    } else {
        // Make sure startPos is not at or after the last cell in the line buffer.
        BOOL ok;
        VT100GridCoord startPosCoord = [linebuffer_ coordinateForPosition:startPos
                                                                    width:currentGrid_.size.width
                                                                       ok:&ok];
        LineBufferPosition *lastValidPosition = [[linebuffer_ lastPosition] predecessor];
        if (!ok) {
            startPos = lastValidPosition;
        } else {
            VT100GridCoord lastPositionCoord = [linebuffer_ coordinateForPosition:lastValidPosition
                                                                            width:currentGrid_.size.width
                                                                               ok:&ok];
            assert(ok);
            long long s = startPosCoord.y;
            s *= currentGrid_.size.width;
            s += startPosCoord.x;
            
            long long l = lastPositionCoord.y;
            l *= currentGrid_.size.width;
            l += lastPositionCoord.x;
            
            if (s >= l) {
                startPos = lastValidPosition;
            }
        }
    }

    // Set up the options bitmask and call findSubstring.
    int opts = 0;
    if (!direction) {
        opts |= FindOptBackwards;
    }
    if (ignoreCase) {
        opts |= FindOptCaseInsensitive;
    }
    if (regex) {
        opts |= FindOptRegex;
    }
    if (multipleResults) {
        opts |= FindMultipleResults;
    }
    [linebuffer_ prepareToSearchFor:aString startingAt:startPos options:opts withContext:context];
    context.hasWrapped = NO;
    [self popScrollbackLines:linesPushed];
}

- (void)saveFindContextAbsPos
{
    int linesPushed;
    linesPushed = [currentGrid_ appendLines:[currentGrid_ numberOfLinesUsed]
                               toLineBuffer:linebuffer_];

    savedFindContextAbsPos_ = [self findContextAbsPosition];
    [self popScrollbackLines:linesPushed];
}

- (NSString *)debugString {
    return [currentGrid_ debugString];
}

- (NSString *)compactLineDumpWithHistory {
    NSMutableString *string = [NSMutableString stringWithString:[linebuffer_ compactLineDumpWithWidth:[self width]]];
    if ([string length]) {
        [string appendString:@"\n"];
    }
    [string appendString:[currentGrid_ compactLineDump]];
    return string;
}

- (NSString *)compactLineDumpWithHistoryAndContinuationMarks {
    NSMutableString *string = [NSMutableString stringWithString:[linebuffer_ compactLineDumpWithWidth:[self width]]];
    if ([string length]) {
        [string appendString:@"\n"];
    }
    [string appendString:[currentGrid_ compactLineDumpWithContinuationMarks]];
    return string;
}

- (NSString *)compactLineDump {
    return [currentGrid_ compactLineDump];
}

- (VT100Grid *)currentGrid {
    return currentGrid_;
}

- (BOOL)isAllDirty
{
    return currentGrid_.isAllDirty;
}

- (void)resetAllDirty
{
    currentGrid_.allDirty = NO;
}

- (void)setCharDirtyAtCursorX:(int)x Y:(int)y
{
    int xToMark = x;
    int yToMark = y;
    if (xToMark == currentGrid_.size.width && yToMark < currentGrid_.size.height - 1) {
        xToMark = 0;
        yToMark++;
    }
    if (xToMark < currentGrid_.size.width && yToMark < currentGrid_.size.height) {
        [currentGrid_ markCharDirty:YES
                                 at:VT100GridCoordMake(xToMark, yToMark)
                    updateTimestamp:NO];
        if (xToMark < currentGrid_.size.width - 1) {
            // Just in case the cursor was over a double width character
            [currentGrid_ markCharDirty:YES
                                     at:VT100GridCoordMake(xToMark + 1, yToMark)
                        updateTimestamp:NO];
        }
    }
}

- (BOOL)isDirtyAtX:(int)x Y:(int)y
{
    return [currentGrid_ isCharDirtyAt:VT100GridCoordMake(x, y)];
}

- (void)resetDirty
{
    [currentGrid_ markAllCharsDirty:NO];
}

- (void)saveToDvr
{
    if (!dvr_ || ![[PreferencePanel sharedInstance] instantReplay]) {
        return;
    }

    DVRFrameInfo info;
    info.cursorX = currentGrid_.cursorX;
    info.cursorY = currentGrid_.cursorY;
    info.height = currentGrid_.size.height;
    info.width = currentGrid_.size.width;

    [dvr_ appendFrame:[currentGrid_ orderedLines]
               length:sizeof(screen_char_t) * (currentGrid_.size.width + 1) * (currentGrid_.size.height)
                 info:&info];
}

- (BOOL)shouldSendContentsChangedNotification
{
    return ([[iTermExpose sharedInstance] isVisible] ||
            [delegate_ screenShouldSendContentsChangedNotification]);
}

- (VT100GridRange)dirtyRangeForLine:(int)y {
    return [currentGrid_ dirtyRangeForLine:y];
}

- (NSDate *)timestampForLine:(int)y {
    int numLinesInLineBuffer = [linebuffer_ numLinesWithWidth:currentGrid_.size.width];
    NSTimeInterval interval;
    if (y >= numLinesInLineBuffer) {
        interval = [currentGrid_ timestampForLine:y - numLinesInLineBuffer];
    } else {
        interval = [linebuffer_ timestampForLineNumber:y width:currentGrid_.size.width];
    }
    return [NSDate dateWithTimeIntervalSinceReferenceDate:interval];
}

- (Interval *)intervalForGridCoordRange:(VT100GridCoordRange)range
                                  width:(int)width
                            linesOffset:(long long)linesOffset
{
    VT100GridCoord start = range.start;
    VT100GridCoord end = range.end;
    long long si = start.y;
    si += linesOffset;
    si *= (width + 1);
    si += start.x;
    long long ei = end.y;
    ei += linesOffset;
    ei *= (width + 1);
    ei += end.x;
    if (ei < si) {
        long long temp = ei;
        ei = si;
        si = temp;
    }
    return [Interval intervalWithLocation:si length:ei - si];
}

- (Interval *)intervalForGridCoordRange:(VT100GridCoordRange)range {
    return [self intervalForGridCoordRange:range
                                     width:self.width
                               linesOffset:[self totalScrollbackOverflow]];
}

- (VT100GridCoordRange)coordRangeForInterval:(Interval *)interval {
    VT100GridCoordRange result;
    const int w = self.width + 1;
    result.start.y = interval.location / w - [self totalScrollbackOverflow];
    result.start.x = interval.location % w;
    result.end.y = interval.limit / w - [self totalScrollbackOverflow];
    result.end.x = interval.limit % w;
    
    if (result.start.y < 0) {
        result.start.y = 0;
        result.start.x = 0;
    }
    return result;
}

- (VT100GridCoord)predecessorOfCoord:(VT100GridCoord)coord {
    coord.x--;
    while (coord.x < 0) {
        coord.x += self.width;
        coord.y--;
        if (coord.y < 0) {
            coord.y = 0;
            return coord;
        }
    }
    return coord;
}

- (void)addNote:(PTYNoteViewController *)note
        inRange:(VT100GridCoordRange)range {
    [marksAndNotes_ addObject:note withInterval:[self intervalForGridCoordRange:range]];
    [currentGrid_ markCharsDirty:YES inRectFrom:range.start to:[self predecessorOfCoord:range.end]];
    note.delegate = self;
    [delegate_ screenDidAddNote:note];
}

- (void)removeInaccessibleNotes {
    long long lastDeadLocation = [self totalScrollbackOverflow] * (self.width + 1);
    if (lastDeadLocation > 0) {
        Interval *deadInterval = [Interval intervalWithLocation:0 length:lastDeadLocation + 1];
        for (id<IntervalTreeObject> obj in [marksAndNotes_ objectsInInterval:deadInterval]) {
            if ([obj.entry.interval limit] <= lastDeadLocation) {
                if ([obj isKindOfClass:[VT100ScreenMark class]]) {
                    [markCache_ removeObject:@([self coordRangeForInterval:obj.entry.interval].end.y)];
                }
                [marksAndNotes_ removeObject:obj];
            }
        }
    }
}

- (BOOL)markIsValid:(VT100ScreenMark *)mark {
    return [marksAndNotes_ containsObject:mark];
}

- (VT100ScreenMark *)addMarkStartingAtAbsoluteLine:(long long)line oneLine:(BOOL)oneLine {
    VT100ScreenMark *mark = [[[VT100ScreenMark alloc] init] autorelease];
    int nonAbsoluteLine = line - [self totalScrollbackOverflow];
    VT100GridCoordRange range;
    if (oneLine) {
        range = VT100GridCoordRangeMake(0, nonAbsoluteLine, self.width, nonAbsoluteLine);
    } else {
        // Interval is whole screen
        int limit = nonAbsoluteLine + self.height - 1;
        if (limit >= [self numberOfScrollbackLines] + [currentGrid_ numberOfLinesUsed]) {
            limit = [self numberOfScrollbackLines] + [currentGrid_ numberOfLinesUsed] - 1;
        }
        range = VT100GridCoordRangeMake(0,
                                        nonAbsoluteLine,
                                        self.width,
                                        limit);
    }
    [markCache_ addObject:@(range.end.y)];
    [marksAndNotes_ addObject:mark withInterval:[self intervalForGridCoordRange:range]];
    [delegate_ screenNeedsRedraw];
    return mark;
}

- (VT100GridCoordRange)coordRangeOfNote:(PTYNoteViewController *)note {
    return [self coordRangeForInterval:note.entry.interval];
}

- (NSArray *)charactersWithNotesOnLine:(int)line {
    NSMutableArray *result = [NSMutableArray array];
    Interval *interval = [self intervalForGridCoordRange:VT100GridCoordRangeMake(0,
                                                                                 line,
                                                                                 0,
                                                                                 line + 1)];
    NSArray *objects = [marksAndNotes_ objectsInInterval:interval];
    for (id<IntervalTreeObject> note in objects) {
        if ([note isKindOfClass:[PTYNoteViewController class]]) {
            VT100GridCoordRange range = [self coordRangeForInterval:note.entry.interval];
            VT100GridRange gridRange;
            if (range.start.y < line) {
                gridRange.location = 0;
            } else {
                gridRange.location = range.start.x;
            }
            if (range.end.y > line) {
                gridRange.length = self.width + 1 - gridRange.location;
            } else {
                gridRange.length = range.end.x - gridRange.location;
            }
            [result addObject:[NSValue valueWithGridRange:gridRange]];
        }
    }
    return result;
}

- (NSArray *)notesInRange:(VT100GridCoordRange)range {
    Interval *interval = [self intervalForGridCoordRange:range];
    NSArray *objects = [marksAndNotes_ objectsInInterval:interval];
    NSMutableArray *notes = [NSMutableArray array];
    for (id<IntervalTreeObject> o in objects) {
        if ([o isKindOfClass:[PTYNoteViewController class]]) {
            [notes addObject:o];
        }
    }
    return notes;
}

- (VT100ScreenMark *)lastMark {
    NSEnumerator *enumerator = [marksAndNotes_ reverseLimitEnumerator];
    NSArray *objects = [enumerator nextObject];
    while (objects) {
        for (id<IntervalTreeObject> obj in objects) {
            if ([obj isKindOfClass:[VT100ScreenMark class]]) {
                return obj;
            }
        }
        objects = [enumerator nextObject];
    }
    return nil;
}

- (BOOL)hasMarkOnLine:(int)line {
    return [markCache_ containsObject:@(line)];
}

- (NSArray *)lastMarksOrNotes {
    return [marksAndNotes_ objectsWithLargestLimit];
}

- (NSArray *)firstMarksOrNotes {
    return [marksAndNotes_ objectsWithSmallestLimit];
}

- (NSArray *)marksOrNotesBefore:(Interval *)location {
    NSEnumerator *enumerator = [marksAndNotes_ reverseLimitEnumeratorAt:location.limit];
    NSArray *objects = [enumerator nextObject];
    return objects;
}

- (NSArray *)marksOrNotesAfter:(Interval *)location {
    NSEnumerator *enumerator = [marksAndNotes_ forwardLimitEnumeratorAt:location.limit];
    NSArray *objects = [enumerator nextObject];
    return objects;
}

- (VT100GridRange)lineNumberRangeOfInterval:(Interval *)interval {
    VT100GridCoordRange range = [self coordRangeForInterval:interval];
    return VT100GridRangeMake(range.start.y, range.end.y - range.start.y + 1);
}

#pragma mark - VT100TerminalDelegate

- (void)terminalAppendString:(NSString *)string isAscii:(BOOL)isAscii
{
    if (collectInputForPrinting_) {
        [printBuffer_ appendString:string];
    } else {
        // else display string on screen
        [self appendStringAtCursor:string ascii:isAscii];
    }
    [delegate_ screenDidAppendStringToCurrentLine:string];
}

- (void)terminalRingBell {
    [delegate_ screenDidAppendStringToCurrentLine:@"\a"];
    [self activateBell];
}

- (void)terminalBackspace {
    int leftMargin = currentGrid_.leftMargin;
    int cursorX = currentGrid_.cursorX;
    int cursorY = currentGrid_.cursorY;

    if (cursorX > leftMargin) {
        // Cursor can move back without hitting the left margin; easy and normal case.
        if (cursorX >= currentGrid_.size.width) {
            currentGrid_.cursorX = cursorX - 2;
        } else {
            currentGrid_.cursorX = cursorX - 1;
        }
    } else if (cursorX == 0 && cursorY > 0 && !currentGrid_.useScrollRegionCols) {
        // Cursor is at the left margin and can wrap around.
        screen_char_t* aLine = [self getLineAtScreenIndex:cursorY - 1];
        if (aLine[currentGrid_.size.width].code == EOL_SOFT) {
            currentGrid_.cursor = VT100GridCoordMake(currentGrid_.size.width - 1, cursorY - 1);
        } else if (aLine[currentGrid_.size.width].code == EOL_DWC) {
            currentGrid_.cursor = VT100GridCoordMake(currentGrid_.size.width - 2, cursorY - 1);
        }
    }
}

- (void)terminalAppendTabAtCursor
{
    // TODO: respect left-right margins
    BOOL simulateTabStopAtMargins = NO;
    if (![self haveTabStopBefore:currentGrid_.size.width + 1]) {
        // No legal tabstop so pretend there's one on first and last column.
        simulateTabStopAtMargins = YES;
        if (currentGrid_.cursor.x == currentGrid_.size.width) {
            // Cursor in right margin, wrap it around and we're done.
            [self linefeed];
            currentGrid_.cursorX = 0;
            return;
        } else if (currentGrid_.cursor.x == currentGrid_.size.width - 1) {
            // Cursor in last column. If there's already a tab there, do nothing.
            screen_char_t *line = [currentGrid_ screenCharsAtLineNumber:currentGrid_.cursorY];
            if (currentGrid_.cursorX > 0 &&
                line[currentGrid_.cursorX].code == 0 &&
                line[currentGrid_.cursorX - 1].code == '\t') {
                return;
            }
        }
    }
    screen_char_t* aLine = [currentGrid_ screenCharsAtLineNumber:currentGrid_.cursorY];
    int positions = 0;
    BOOL allNulls = YES;

    // Advance cursor to next tab stop. Count the number of positions advanced
    // and record whether they were all nulls.
    if (aLine[currentGrid_.cursorX].code != 0) {
        allNulls = NO;
    }

    ++positions;
    // ensure we go to the next tab in case we are already on one
    [self advanceCursor:YES];
    aLine = [currentGrid_ screenCharsAtLineNumber:currentGrid_.cursorY];
    while (1) {
        if (currentGrid_.cursorX == currentGrid_.size.width) {
            // Wrap around to the next line.
            if (aLine[currentGrid_.cursorX].code == EOL_HARD) {
                aLine[currentGrid_.cursorX].code = EOL_SOFT;
            }
            [self linefeed];
            currentGrid_.cursorX = 0;
            aLine = [currentGrid_ screenCharsAtLineNumber:currentGrid_.cursorY];
        }
        BOOL isFirstOrLastColumn = (currentGrid_.cursorX == 0 ||
                                    currentGrid_.cursorX == currentGrid_.size.width - 1);
        if ((simulateTabStopAtMargins && isFirstOrLastColumn) ||
            [self haveTabStopAt:currentGrid_.cursorX]) {
            break;
        }
        if (aLine[currentGrid_.cursorX].code != 0) {
            allNulls = NO;
        }
        [self advanceCursor:YES];
        ++positions;
    }
    if (allNulls) {
        // If only nulls were advanced over, convert them to tab fillers
        // and place a tab character at the end of the run.
        int x = currentGrid_.cursorX;
        int y = currentGrid_.cursorY;
        --x;
        if (x < 0) {
            x = currentGrid_.size.width - 1;
            --y;
        }
        unichar replacement = '\t';
        while (positions--) {
            aLine = [currentGrid_ screenCharsAtLineNumber:y];
            aLine[x].code = replacement;
            replacement = TAB_FILLER;
            --x;
            if (x < 0) {
                x = currentGrid_.size.width - 1;
                --y;
            }
        }
    }
}

- (void)terminalLineFeed
{
    if (collectInputForPrinting_) {
        [printBuffer_ appendString:@"\n"];
    } else {
        [self linefeed];
    }
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalCursorLeft:(int)n
{
    [currentGrid_ moveCursorLeft:n];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalCursorDown:(int)n
{
    [currentGrid_ moveCursorDown:n];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalCursorRight:(int)n
{
    [currentGrid_ moveCursorRight:n];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalCursorUp:(int)n
{
    [currentGrid_ moveCursorUp:n];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalMoveCursorToX:(int)x y:(int)y
{
    [self cursorToX:x Y:y];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (BOOL)terminalShouldSendReport
{
    return [delegate_ screenShouldSendReport];
}

- (void)terminalSendReport:(NSData *)report
{
    if ([delegate_ screenShouldSendReport] && report) {
        [delegate_ screenWriteDataToTask:report];
    }
}

- (void)terminalShowTestPattern
{
    screen_char_t ch = [currentGrid_ defaultChar];
    ch.code = 'E';
    [currentGrid_ setCharsFrom:VT100GridCoordMake(0, 0)
                            to:VT100GridCoordMake(currentGrid_.size.width - 1,
                                                  currentGrid_.size.height - 1)
                        toChar:ch];
    [currentGrid_ resetScrollRegions];
    currentGrid_.cursor = VT100GridCoordMake(0, 0);
}

- (void)terminalRestoreCursor
{
    currentGrid_.cursor = savedCursor_;
}

- (void)terminalRestoreCharsetFlags
{
    assert(savedCharsetUsesLineDrawingMode_.count == charsetUsesLineDrawingMode_.count);
    [charsetUsesLineDrawingMode_ removeAllObjects];
    [charsetUsesLineDrawingMode_ addObjectsFromArray:savedCharsetUsesLineDrawingMode_];

    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalSaveCursor
{
    [currentGrid_ clampCursorPositionToValid];
    savedCursor_ = currentGrid_.cursor;
}

- (void)terminalSaveCharsetFlags
{
    [savedCharsetUsesLineDrawingMode_ removeAllObjects];
    [savedCharsetUsesLineDrawingMode_ addObjectsFromArray:charsetUsesLineDrawingMode_];
}

- (int)terminalRelativeCursorX {
    return currentGrid_.cursorX - currentGrid_.leftMargin + 1;
}

- (int)terminalRelativeCursorY {
    return currentGrid_.cursorY - currentGrid_.topMargin + 1;
}

- (void)terminalSetScrollRegionTop:(int)top bottom:(int)bottom
{
    if (top >= 0 &&
        top < currentGrid_.size.height &&
        bottom >= 0 &&
        bottom < currentGrid_.size.height &&
        bottom >= top) {
        currentGrid_.scrollRegionRows = VT100GridRangeMake(top, bottom - top + 1);

        if ([terminal_ originMode]) {
            currentGrid_.cursor = VT100GridCoordMake(currentGrid_.leftMargin,
                                                     currentGrid_.topMargin);
        } else {
           currentGrid_.cursor = VT100GridCoordMake(0, 0);
        }
    }
}

- (void)terminalEraseInDisplayBeforeCursor:(BOOL)before afterCursor:(BOOL)after
{
    int x1, yStart, x2, y2;

    if (before && after) {
        // Scroll the top lines of the screen into history, up to and including the last non-
        // empty line.
        const int n = [currentGrid_ numberOfLinesUsed];
        for (int i = 0; i < n; i++) {
            [self incrementOverflowBy:[currentGrid_ scrollWholeScreenUpIntoLineBuffer:linebuffer_
                                                                  unlimitedScrollback:unlimitedScrollback_]];
        }
        x1 = 0;
        yStart = 0;
        x2 = currentGrid_.size.width - 1;
        y2 = currentGrid_.size.height - 1;
    } else if (before) {
        x1 = 0;
        yStart = 0;
        x2 = MIN(currentGrid_.cursor.x, currentGrid_.size.width - 1);
        y2 = currentGrid_.cursor.y;
    } else if (after) {
        x1 = MIN(currentGrid_.cursor.x, currentGrid_.size.width - 1);
        yStart = currentGrid_.cursor.y;
        x2 = currentGrid_.size.width - 1;
        y2 = currentGrid_.size.height - 1;
    } else {
        return;
    }

    VT100GridRun theRun = VT100GridRunFromCoords(VT100GridCoordMake(x1, yStart),
                                                 VT100GridCoordMake(x2, y2),
                                                 currentGrid_.size.width);
    [currentGrid_ setCharsInRun:theRun
                         toChar:0];
    [delegate_ screenTriggerableChangeDidOccur];
    
}

- (void)terminalEraseLineBeforeCursor:(BOOL)before afterCursor:(BOOL)after {
    int x1 = 0;
    int x2 = 0;

    if (before && after) {
        x1 = 0;
        x2 = currentGrid_.size.width - 1;
    } else if (before) {
        x1 = 0;
        x2 = MIN(currentGrid_.cursor.x, currentGrid_.size.width - 1);
    } else if (after) {
        x1 = currentGrid_.cursor.x;
        x2 = currentGrid_.size.width - 1;
    } else {
        return;
    }

    VT100GridRun theRun = VT100GridRunFromCoords(VT100GridCoordMake(x1, currentGrid_.cursor.y),
                                                 VT100GridCoordMake(x2, currentGrid_.cursor.y),
                                                 currentGrid_.size.width);
    [currentGrid_ setCharsInRun:theRun
                         toChar:0];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalSetTabStopAtCursor {
    if (currentGrid_.cursorX < currentGrid_.size.width) {
        [tabStops_ addObject:[NSNumber numberWithInt:currentGrid_.cursorX]];
    }
}

- (void)terminalCarriageReturn {
    if (currentGrid_.useScrollRegionCols && currentGrid_.cursorX == currentGrid_.leftMargin) {
        // I observed that xterm will move the cursor to the first column when it gets a CR
        // while the cursor is at the left margin of a vsplit. Not sure why.
        currentGrid_.cursorX = 0;
    } else {
        [currentGrid_ moveCursorToLeftMargin];
    }
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalReverseIndex {
    if (currentGrid_.cursorY == currentGrid_.topMargin) {
        [currentGrid_ scrollDown];
    } else {
        currentGrid_.cursorY = MAX(0, currentGrid_.cursorY - 1);
    }
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalResetPreservingPrompt:(BOOL)preservePrompt {
    [delegate_ screenTriggerableChangeDidOccur];
    if (preservePrompt) {
        [self clearAndResetScreenPreservingCursorLine];
    } else {
        [self incrementOverflowBy:[currentGrid_ resetWithLineBuffer:linebuffer_
                                                unlimitedScrollback:unlimitedScrollback_
                                                 preserveCursorLine:NO]];
    }
    savedCursor_ = VT100GridCoordMake(0, 0);

    [self setInitialTabStops];

    [savedCharsetUsesLineDrawingMode_ removeAllObjects];
    [charsetUsesLineDrawingMode_ removeAllObjects];
    for (int i = 0; i < NUM_CHARSETS; i++) {
        [savedCharsetUsesLineDrawingMode_ addObject:[NSNumber numberWithBool:NO]];
        [charsetUsesLineDrawingMode_ addObject:[NSNumber numberWithBool:NO]];
    }

    [self showCursor:YES];
}

- (void)terminalSoftReset {
    // See note in xterm-terminfo.txt (search for DECSTR).

    // save cursor (fixes origin-mode side-effect)
    [self terminalSaveCursor];
    [self terminalSaveCharsetFlags];

    // reset scrolling margins
    [currentGrid_ resetScrollRegions];

    // reset SGR (done in VT100Terminal)
    // reset wraparound mode (done in VT100Terminal)
    // reset application cursor keys (done in VT100Terminal)
    // reset origin mode (done in VT100Terminal)
    // restore cursor
    [self terminalRestoreCursor];
    [self terminalRestoreCharsetFlags];
}

- (void)terminalSetCursorType:(ITermCursorType)cursorType {
    [delegate_ screenSetCursorType:cursorType];
}

- (void)terminalSetCursorBlinking:(BOOL)blinking {
    [delegate_ screenSetCursorBlinking:blinking];
}

- (void)terminalSetLeftMargin:(int)scrollLeft rightMargin:(int)scrollRight {
    if (currentGrid_.useScrollRegionCols) {
        currentGrid_.scrollRegionCols = VT100GridRangeMake(scrollLeft,
                                                           scrollRight - scrollLeft + 1);
        // set cursor to the home position
        [self cursorToX:1 Y:1];
    }
}

- (void)terminalSetCharset:(int)charset toLineDrawingMode:(BOOL)lineDrawingMode {
    [charsetUsesLineDrawingMode_ replaceObjectAtIndex:charset
                                           withObject:[NSNumber numberWithBool:lineDrawingMode]];
}

- (void)terminalRemoveTabStops {
    [tabStops_ removeAllObjects];
}

- (void)terminalRemoveTabStopAtCursor {
    if (currentGrid_.cursorX < currentGrid_.size.width) {
        [tabStops_ removeObject:[NSNumber numberWithInt:currentGrid_.cursorX]];
    }
}

- (void)terminalSetWidth:(int)width {
    if ([delegate_ screenShouldInitiateWindowResize] &&
        ![delegate_ screenWindowIsFullscreen]) {
        // set the column
        [delegate_ screenResizeToWidth:width
                                height:currentGrid_.size.height];
        [self terminalEraseInDisplayBeforeCursor:YES afterCursor:YES];  // erase the screen
        currentGrid_.cursorX = 0;
        currentGrid_.cursorY = 0;
    }
}

- (void)terminalBackTab:(int)n
{
    for (int i = 0; i < n; i++) {
        // TODO: respect left-right margins
        if (currentGrid_.cursorX > 0) {
            currentGrid_.cursorX = currentGrid_.cursorX - 1;
            while (![self haveTabStopAt:currentGrid_.cursorX] && currentGrid_.cursorX > 0) {
                currentGrid_.cursorX = currentGrid_.cursorX - 1;
            }
            [delegate_ screenTriggerableChangeDidOccur];
        }
    }
}

- (void)terminalSetCursorX:(int)x {
    [self cursorToX:x];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalSetCursorY:(int)y {
    [self cursorToY:y];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalEraseCharactersAfterCursor:(int)j {
    if (currentGrid_.cursorX < currentGrid_.size.width) {
        if (j <= 0) {
            return;
        }

        int limit = MIN(currentGrid_.cursorX + j, currentGrid_.size.width);
        [currentGrid_ setCharsFrom:VT100GridCoordMake(currentGrid_.cursorX, currentGrid_.cursorY)
                                to:VT100GridCoordMake(limit - 1, currentGrid_.cursorY)
                            toChar:[currentGrid_ defaultChar]];
        // TODO: This used to always set the continuation mark to hard, but I think it should only do that if the last char in the line is erased.
        [delegate_ screenTriggerableChangeDidOccur];
    }
}

- (void)terminalPrintBuffer {
    if ([delegate_ screenShouldBeginPrinting] && [printBuffer_ length] > 0) {
        [self doPrint];
    }
}

- (void)terminalBeginRedirectingToPrintBuffer {
    if ([delegate_ screenShouldBeginPrinting]) {
        // allocate a string for the stuff to be printed
        if (printBuffer_ != nil) {
            [printBuffer_ release];
        }
        printBuffer_ = [[NSMutableString alloc] init];
        collectInputForPrinting_ = YES;
    }
}

- (void)terminalPrintScreen {
    if ([delegate_ screenShouldBeginPrinting]) {
        // Print out the whole screen
        if (printBuffer_ != nil) {
            [printBuffer_ release];
            printBuffer_ = nil;
        }
        collectInputForPrinting_ = NO;
        [self doPrint];
    }
}

- (void)terminalSetWindowTitle:(NSString *)title {
    NSString *newTitle = [[title copy] autorelease];
    if ([delegate_ screenShouldSyncTitle]) {
        newTitle = [NSString stringWithFormat:@"%@: %@", [delegate_ screenNameExcludingJob], newTitle];
    }
    [delegate_ screenSetWindowTitle:newTitle];
    long long lineNumber = [self absoluteLineNumberOfCursor];
    [delegate_ screenLogWorkingDirectoryAtLine:lineNumber withDirectory:nil];
}

- (void)terminalSetIconTitle:(NSString *)title {
    NSString *newTitle = [[title copy] autorelease];
    if ([delegate_ screenShouldSyncTitle]) {
        newTitle = [NSString stringWithFormat:@"%@: %@", [delegate_ screenNameExcludingJob], newTitle];
    }
    [delegate_ screenSetName:newTitle];
}

- (void)terminalPasteString:(NSString *)string {
    // check the configuration
    if (![[PreferencePanel sharedInstance] allowClipboardAccess]) {
        return;
    }

    // set the result to paste board.
    NSPasteboard* thePasteboard = [NSPasteboard generalPasteboard];
    [thePasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [thePasteboard setString:string forType:NSStringPboardType];
}

- (void)terminalInsertEmptyCharsAtCursor:(int)n {
    [currentGrid_ insertChar:[currentGrid_ defaultChar]
                          at:currentGrid_.cursor
                       times:n];
}

- (void)terminalInsertBlankLinesAfterCursor:(int)n {
    VT100GridRect scrollRegionRect = [currentGrid_ scrollRegionRect];
    if (scrollRegionRect.origin.x + scrollRegionRect.size.width == currentGrid_.size.width) {
        // Cursor can be in right margin and still be considered in the scroll region if the
        // scroll region abuts the right margin.
        scrollRegionRect.size.width++;
    }
    BOOL cursorInScrollRegion = VT100GridCoordInRect(currentGrid_.cursor, scrollRegionRect);
    if (cursorInScrollRegion) {
        // xterm appears to ignore INSLN if the cursor is outside the scroll region.
        // See insln-* files in tests/.
        int top = currentGrid_.cursorY;
        int left = currentGrid_.leftMargin;
        int width = currentGrid_.rightMargin - currentGrid_.leftMargin + 1;
        int height = currentGrid_.bottomMargin - top + 1;
        [currentGrid_ scrollRect:VT100GridRectMake(left, top, width, height)
                          downBy:n];
        [delegate_ screenTriggerableChangeDidOccur];
    }
}

- (void)terminalDeleteCharactersAtCursor:(int)n {
    [currentGrid_ deleteChars:n startingAt:currentGrid_.cursor];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalDeleteLinesAtCursor:(int)n {
    if (n <= 0) {
        return;
    }
    VT100GridRect scrollRegionRect = [currentGrid_ scrollRegionRect];
    if (scrollRegionRect.origin.x + scrollRegionRect.size.width == currentGrid_.size.width) {
        // Cursor can be in right margin and still be considered in the scroll region if the
        // scroll region abuts the right margin.
        scrollRegionRect.size.width++;
    }
    BOOL cursorInScrollRegion = VT100GridCoordInRect(currentGrid_.cursor, scrollRegionRect);
    if (cursorInScrollRegion) {
        [currentGrid_ scrollRect:VT100GridRectMake(currentGrid_.leftMargin,
                                                   currentGrid_.cursorY,
                                                   currentGrid_.rightMargin - currentGrid_.leftMargin + 1,
                                                   currentGrid_.bottomMargin - currentGrid_.cursorY + 1)
                          downBy:-n];
        [delegate_ screenTriggerableChangeDidOccur];
    }
}

- (void)terminalSetRows:(int)rows andColumns:(int)columns {
    if ([delegate_ screenShouldInitiateWindowResize] &&
        ![delegate_ screenWindowIsFullscreen]) {
        [delegate_ screenResizeToWidth:columns
                                height:rows];

    }
}

- (void)terminalSetPixelWidth:(int)width height:(int)height {
    if ([delegate_ screenShouldInitiateWindowResize] &&
        ![delegate_ screenWindowIsFullscreen]) {
        // TODO: Only allow this if there is a single session in the tab.
        NSRect frame = [delegate_ screenWindowFrame];
        NSRect screenFrame = [delegate_ screenWindowScreenFrame];
        if (width < 0) {
            width = frame.size.width;
        } else if (width == 0) {
            width = screenFrame.size.width;
        }
        if (height < 0) {
            height = frame.size.height;
        } else if (height == 0) {
            height = screenFrame.size.height;
        }
        [delegate_ screenResizeToPixelWidth:width height:height];
    }
}

- (void)terminalMoveWindowTopLeftPointTo:(NSPoint)point {
    if ([delegate_ screenShouldInitiateWindowResize] &&
        ![delegate_ screenWindowIsFullscreen]) {
        // TODO: Only allow this if there is a single session in the tab.
        [delegate_ screenMoveWindowTopLeftPointTo:point];
    }
}

- (void)terminalMiniaturize:(BOOL)mini {
    // TODO: Only allow this if there is a single session in the tab.
    if ([delegate_ screenShouldInitiateWindowResize] &&
        ![delegate_ screenWindowIsFullscreen]) {
        [delegate_ screenMiniaturizeWindow:mini];
    }
}

- (void)terminalRaise:(BOOL)raise {
    if ([delegate_ screenShouldInitiateWindowResize]) {
        [delegate_ screenRaise:raise];
    }
}

- (void)terminalScrollUp:(int)n {
    for (int i = 0;
         i < MIN(currentGrid_.size.height, n);
         i++) {
        [self incrementOverflowBy:[currentGrid_ scrollUpIntoLineBuffer:linebuffer_
                                                   unlimitedScrollback:unlimitedScrollback_
                                               useScrollbackWithRegion:[self useScrollbackWithRegion]]];
    }
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalScrollDown:(int)n {
    [currentGrid_ scrollRect:[currentGrid_ scrollRegionRect]
                      downBy:MIN(currentGrid_.size.height, n)];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (BOOL)terminalWindowIsMiniaturized {
    return [delegate_ screenWindowIsMiniaturized];
}

- (NSPoint)terminalWindowTopLeftPixelCoordinate {
    return [delegate_ screenWindowTopLeftPixelCoordinate];
}

- (int)terminalWindowWidthInPixels {
    NSRect frame = [delegate_ screenWindowFrame];
    return frame.size.width;
}

- (int)terminalWindowHeightInPixels {
    NSRect frame = [delegate_ screenWindowFrame];
    return frame.size.height;
}

- (int)terminalScreenHeightInCells {
    //  TODO: WTF do we do with panes here?
    NSRect screenFrame = [delegate_ screenWindowScreenFrame];
    NSRect windowFrame = [delegate_ screenWindowFrame];
    float roomToGrow = screenFrame.size.height - windowFrame.size.height;
    NSSize cellSize = [delegate_ screenCellSize];
    return [self height] + roomToGrow / cellSize.height;
}

- (int)terminalScreenWidthInCells {
    //  TODO: WTF do we do with panes here?
    NSRect screenFrame = [delegate_ screenWindowScreenFrame];
    NSRect windowFrame = [delegate_ screenWindowFrame];
    float roomToGrow = screenFrame.size.width - windowFrame.size.width;
    NSSize cellSize = [delegate_ screenCellSize];
    return [self width] + roomToGrow / cellSize.width;
}

- (NSString *)terminalIconTitle {
    if (allowTitleReporting_) {
        return [delegate_ screenWindowTitle] ? [delegate_ screenWindowTitle] : [delegate_ screenDefaultName];
    } else {
        return @"";
    }
}

- (NSString *)terminalWindowTitle {
    if (allowTitleReporting_) {
        return [delegate_ screenWindowTitle] ? [delegate_ screenWindowTitle] : @"";
    } else {
        return @"";
    }
}

- (void)terminalPushCurrentTitleForWindow:(BOOL)isWindow {
    [delegate_ screenPushCurrentTitleForWindow:isWindow];
}

- (void)terminalPopCurrentTitleForWindow:(BOOL)isWindow {
    [delegate_ screenPopCurrentTitleForWindow:isWindow];
}

- (void)terminalPostGrowlNotification:(NSString *)message {
    if (postGrowlNotifications_) {
        // Use a non-printable control character (RECORD SEPARATOR)
        // to allow the user to specify both the alert title and text,
        // if it's not present treat the whole message as the message
        // as in previous versions. Ignore more than two "records" for
        // future use.
        NSArray *split = [message componentsSeparatedByString:@"\036"];
        NSString *description = message;
        NSString *title = nil;
        if ([split count] > 1) {
            title = [split objectAtIndex:0];
            description = [split objectAtIndex:1];
        } else {
            title = NSLocalizedStringFromTableInBundle(@"Alert",
                                                       @"iTerm",
                                                       [NSBundle bundleForClass:[self class]],
                                                       @"Growl Alerts");
        }
        [[iTermGrowlDelegate sharedInstance]
         growlNotify:title
         withDescription:[NSString stringWithFormat:@"Session %@ #%d: %@",
                          [delegate_ screenName],
                          [delegate_ screenNumber],
                          description]
         andNotification:@"Customized Message"
         windowIndex:[delegate_ screenWindowIndex]
         tabIndex:[delegate_ screenTabIndex]
         viewIndex:[delegate_ screenViewIndex]];
    }
}

- (void)terminalStartTmuxMode {
    [delegate_ screenStartTmuxMode];
}

- (int)terminalWidth {
    return [self width];
}

- (int)terminalHeight {
    return [self height];
}

- (void)terminalMouseModeDidChangeTo:(MouseMode)mouseMode
{
    [delegate_ screenMouseModeDidChange];
}

- (void)terminalNeedsRedraw {
    [currentGrid_ markAllCharsDirty:YES];
}

- (void)terminalSetUseColumnScrollRegion:(BOOL)use {
    self.useColumnScrollRegion = use;
}

- (BOOL)terminalUseColumnScrollRegion {
    return self.useColumnScrollRegion;
}

// offset is added to intervals before inserting into interval tree.
- (void)moveNotesOnScreenFrom:(IntervalTree *)source
                           to:(IntervalTree *)dest
                       offset:(long long)offset
                 screenOrigin:(int)screenOrigin
{
    VT100GridCoordRange screenRange =
        VT100GridCoordRangeMake(0,
                                screenOrigin,
                                [self width],
                                screenOrigin + self.height);
    NSLog(@"  moveNotes: looking in range %@", VT100GridCoordRangeDescription(screenRange));
    Interval *interval = [self intervalForGridCoordRange:screenRange];
    for (id<IntervalTreeObject> obj in [source objectsInInterval:interval]) {
        Interval *interval = [[obj.entry.interval retain] autorelease];
        [[obj retain] autorelease];
        NSLog(@"  found note with interval %@", interval);
        [source removeObject:obj];
        interval.location = interval.location + offset;
        NSLog(@"  new interval is %@", interval);
        [dest addObject:obj withInterval:interval];
    }
}

// Swap onscreen notes between marksAndNotes_ and savedMarksAndNotes_.
// IMPORTANT: Call -reloadMarkCache after this.
- (void)swapNotes
{
    int historyLines = [self numberOfScrollbackLines];
    Interval *origin = [self intervalForGridCoordRange:VT100GridCoordRangeMake(0,
                                                                               historyLines,
                                                                               1,
                                                                               historyLines)];
    IntervalTree *temp = [[IntervalTree alloc] init];
    NSLog(@"swapNotes: moving onscreen notes into savedNotes");
    [self moveNotesOnScreenFrom:marksAndNotes_
                             to:temp
                         offset:-origin.location
                   screenOrigin:[self numberOfScrollbackLines]];
    NSLog(@"swapNotes: moving onscreen savedNotes into notes");
    [self moveNotesOnScreenFrom:savedMarksAndNotes_
                             to:marksAndNotes_
                         offset:origin.location
                   screenOrigin:0];
    [savedMarksAndNotes_ release];
    savedMarksAndNotes_ = temp;
}

- (void)terminalShowAltBuffer
{
    if (currentGrid_ == altGrid_) {
        return;
    }
    if (!altGrid_) {
        altGrid_ = [[VT100Grid alloc] initWithSize:primaryGrid_.size delegate:terminal_];
    }

    primaryGrid_.savedDefaultChar = [primaryGrid_ defaultChar];
    [self hideOnScreenNotesAndTruncateSpanners];
    currentGrid_ = altGrid_;
    currentGrid_.cursor = primaryGrid_.cursor;

    [self swapNotes];
    [self reloadMarkCache];

    [currentGrid_ markAllCharsDirty:YES];
    [delegate_ screenNeedsRedraw];
}

- (void)hideOnScreenNotesAndTruncateSpanners
{
    int screenOrigin = [self numberOfScrollbackLines];
    VT100GridCoordRange screenRange =
        VT100GridCoordRangeMake(0,
                                screenOrigin,
                                [self width],
                                screenOrigin + self.height);
    Interval *screenInterval = [self intervalForGridCoordRange:screenRange];
    for (id<IntervalTreeObject> note in [marksAndNotes_ objectsInInterval:screenInterval]) {
        if (note.entry.interval.location < screenInterval.location) {
            // Truncate note so that it ends just before screen.
            note.entry.interval.length = screenInterval.location - note.entry.interval.location;
        }
        if ([note isKindOfClass:[PTYNoteViewController class]]) {
            [(PTYNoteViewController *)note setNoteHidden:YES];
        }
    }
}
- (void)terminalShowPrimaryBufferRestoringCursor:(BOOL)restore
{
    if (currentGrid_ == altGrid_) {
        [self hideOnScreenNotesAndTruncateSpanners];
        currentGrid_ = primaryGrid_;
        [self swapNotes];
        [self reloadMarkCache];

        [currentGrid_ markAllCharsDirty:YES];
        if (!restore) {
            // Don't restore the cursor; instead, continue using the cursor position of the alt grid.
            currentGrid_.cursor = altGrid_.cursor;
        }
        [delegate_ screenNeedsRedraw];
    }
}

- (void)terminalClearScreen {
    // Unconditionally clear the whole screen, regardless of cursor position.
    // This behavior changed in the Great VT100Grid Refactoring of 2013. Before, clearScreen
    // used to move the cursor's wrapped line to the top of the screen. It's only used from
    // DECSET 1049, and neither xterm nor terminal have this behavior, and I'm not sure why it
    // would be desirable anyway. Like xterm (and unlike Terminal) we leave the cursor put.
    [currentGrid_ setCharsFrom:VT100GridCoordMake(0, 0)
                            to:VT100GridCoordMake(currentGrid_.size.width - 1,
                                                  currentGrid_.size.height - 1)
                        toChar:[currentGrid_ defaultChar]];
}

- (void)terminalSendModifiersDidChangeTo:(int *)modifiers
                               numValues:(int)numValues {
    NSMutableArray *array = [NSMutableArray array];
    for (int i = 0; i < numValues; i++) {
        [array addObject:[NSNumber numberWithInt:modifiers[i]]];
    }
    [delegate_ screenModifiersDidChangeTo:array];
}

- (void)terminalColorTableEntryAtIndex:(int)theIndex didChangeToColor:(NSColor *)theColor {
    [delegate_ screenSetColorTableEntryAtIndex:theIndex color:theColor];
}

- (void)terminalSaveScrollPositionWithArgument:(NSString *)argument {
    // The difference between an argument of saveScrollPosition and saveCursorLine (the default) is
    // subtle. When saving the scroll position, the entire region of visible lines is recorded and
    // will be restored exactly. When saving only the line the cursor is on, when restored, that
    // line will be made visible but no other aspect of the scroll position must be restored. This
    // is often preferable because when setting a mark as part of the prompt, we wouldn't want the
    // prompt to be the last line on the screen (such lines are scrolled to the center of
    // the screen).
    if ([argument isEqualToString:@"saveScrollPosition"]) {
        [delegate_ screenSaveScrollPosition];
    } else {  // implicitly "saveCursorLine"
        [delegate_ screenAddMarkOnLine:[self numberOfScrollbackLines] + self.cursorY - 1];
    }
}

- (void)terminalStealFocus {
    [delegate_ screenActivateWindow];
    [delegate_ screenRaise:YES];
}

- (void)terminalClearBuffer {
    [self clearBuffer];
}

- (void)terminalCurrentDirectoryDidChangeTo:(NSString *)value {
    long long lineNumber = [self absoluteLineNumberOfCursor];
    [delegate_ screenLogWorkingDirectoryAtLine:lineNumber withDirectory:value];
}

- (void)terminalProfileShouldChangeTo:(NSString *)value {
    [delegate_ screenSetProfileToProfileNamed:value];
}

- (void)terminalAddNote:(NSString *)value show:(BOOL)show {
    NSArray *parts = [value componentsSeparatedByString:@"|"];
    VT100GridCoord location = currentGrid_.cursor;
    NSString *message = nil;
    int length = currentGrid_.size.width - currentGrid_.cursorX - 1;
    if (parts.count == 1) {
        message = parts[0];
    } else if (parts.count == 2) {
        message = parts[1];
        length = [parts[0] intValue];
    } else if (parts.count >= 4) {
        location.x = MIN(MAX(0, [parts[0] intValue]), location.x);
        location.y = MIN(MAX(0, [parts[1] intValue]), location.y);
        length = [parts[2] intValue];
        message = parts[3];
    }
    VT100GridCoord end = location;
    end.x += length;
    end.y += end.x / self.width;
    end.x %= self.width;
    
    int endVal = end.x + end.y * self.width;
    int maxVal = self.width - 1 + (self.height - 1) * self.width;
    if (length > 0 &&
        message.length > 0 &&
        endVal <= maxVal) {
        PTYNoteViewController *note = [[[PTYNoteViewController alloc] init] autorelease];
        [note setString:message];
        [note sizeToFit];
        [self addNote:note
              inRange:VT100GridCoordRangeMake(location.x,
                                              location.y + [self numberOfScrollbackLines],
                                              end.x,
                                              end.y + [self numberOfScrollbackLines])];
        if (!show) {
            [note setNoteHidden:YES];
        }
    }
}

- (void)terminalSetPasteboard:(NSString *)value {
    [delegate_ screenSetPasteboard:value];
}

- (void)terminalCopyBufferToPasteboard {
    [delegate_ screenCopyBufferToPasteboard];
}

- (BOOL)terminalIsAppendingToPasteboard {
    return [delegate_ screenIsAppendingToPasteboard];
}

- (void)terminalAppendDataToPasteboard:(NSData *)data {
    return [delegate_ screenAppendDataToPasteboard:data];
}

- (void)terminalRequestAttention:(BOOL)request {
    [delegate_ screenRequestAttention:request];
}

- (void)terminalSetForegroundColor:(NSColor *)color {
    [delegate_ screenSetForegroundColor:color];
}

- (void)terminalSetBackgroundGColor:(NSColor *)color {
    [delegate_ screenSetBackgroundColor:color];
}

- (void)terminalSetBoldColor:(NSColor *)color {
    [delegate_ screenSetBoldColor:color];
}

- (void)terminalSetSelectionColor:(NSColor *)color {
    [delegate_ screenSetSelectionColor:color];
}

- (void)terminalSetSelectedTextColor:(NSColor *)color {
    [delegate_ screenSetSelectedTextColor:color];
}

- (void)terminalSetCursorColor:(NSColor *)color {
    [delegate_ screenSetCursorColor:color];
}

- (void)terminalSetCursorTextColor:(NSColor *)color {
    [delegate_ screenSetCursorTextColor:color];
}

- (void)terminalSetColorTableEntryAtIndex:(int)n color:(NSColor *)color {
    [delegate_ screenSetColorTableEntryAtIndex:n color:color];
}

- (void)terminalSetCurrentTabColor:(NSColor *)color {
    [delegate_ screenSetCurrentTabColor:color];
}

- (void)terminalSetTabColorRedComponentTo:(CGFloat)color {
    [delegate_ screenSetTabColorRedComponentTo:color];
}

- (void)terminalSetTabColorGreenComponentTo:(CGFloat)color {
    [delegate_ screenSetTabColorGreenComponentTo:color];
}

- (void)terminalSetTabColorBlueComponentTo:(CGFloat)color {
    [delegate_ screenSetTabColorBlueComponentTo:color];
}

- (int)terminalCursorX {
    return [self cursorX];
}

- (int)terminalCursorY {
    return [self cursorY];
}

- (void)terminalSetCursorVisible:(BOOL)visible {
    [delegate_ screenSetCursorVisible:visible];
}

#pragma mark - Private

- (void)setInitialTabStops
{
    [tabStops_ removeAllObjects];
    const int kInitialTabWindow = 1000;
    for (int i = 0; i < kInitialTabWindow; i += kDefaultTabstopWidth) {
        [tabStops_ addObject:[NSNumber numberWithInt:i]];
    }
}

- (BOOL)isAnyCharDirty
{
    return [currentGrid_ isAnyCharDirty];
}

- (void)setCursorX:(int)x Y:(int)y
{
    DLog(@"Move cursor to %d,%d", x, y);
    currentGrid_.cursor = VT100GridCoordMake(x, y);
}

// NSLog the screen contents for debugging.
- (void)dumpScreen
{
    NSLog(@"%@", [self debugString]);
}

- (int)colorCodeForColor:(NSColor *)theColor
{
    if (theColor) {
        theColor = [theColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        int r = 5 * [theColor redComponent];
        int g = 5 * [theColor greenComponent];
        int b = 5 * [theColor blueComponent];
        return 16 + b + g*6 + r*36;
    } else {
        return 0;
    }
}

// Set the color of prototypechar to all chars between startPoint and endPoint on the screen.
- (void)highlightRun:(VT100GridRun)run
    withForegroundColor:(NSColor *)fgColor
        backgroundColor:(NSColor *)bgColor
{
    int fgColorCode = [self colorCodeForColor:fgColor];
    int bgColorCode = [self colorCodeForColor:bgColor];

    screen_char_t fg = { 0 };
    screen_char_t bg = { 0 };

    fg.foregroundColor = fgColorCode;
    fg.foregroundColorMode = fgColor ? ColorModeNormal : ColorModeInvalid;
    bg.backgroundColor = bgColorCode;
    bg.backgroundColorMode = bgColor ? ColorModeNormal : ColorModeInvalid;

    for (NSValue *value in [currentGrid_ rectsForRun:run]) {
        VT100GridRect rect = [value gridRectValue];
        [currentGrid_ setBackgroundColor:bg
                         foregroundColor:fg
                              inRectFrom:rect.origin
                                      to:VT100GridRectMax(rect)];
    }
}

// This assumes the window's height is going to change to newHeight but currentGrid_.size.height
// is still the "old" height. Returns the number of lines appended.
- (int)appendScreen:(VT100Grid *)grid
        toScrollback:(LineBuffer *)lineBufferToUse
      withUsedHeight:(int)usedHeight
           newHeight:(int)newHeight
{
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
    [grid appendLines:n
         toLineBuffer:lineBufferToUse];

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

// It's kind of wrong to use VT100GridRun here, but I think it's harmless enough.
- (VT100GridRun)runByTrimmingNullsFromRun:(VT100GridRun)run {
    VT100GridRun result = run;
    int x = result.origin.x;
    int y = result.origin.y;
    screen_char_t *line = [self getLineAtIndex:y];
    int numberOfLines = [self numberOfLines];
    int width = [self width];
    while (result.length > 0 && line[x].code == 0 && y < numberOfLines) {
        x++;
        result.length--;
        if (x == width) {
            x = 0;
            y++;
            if (y == numberOfLines) {
                // Run is all nulls
                result.length = 0;
                return result;
            }
            line = [self getLineAtIndex:y];
        }
    }
    result.origin = VT100GridCoordMake(x, y);

    VT100GridCoord end = VT100GridRunMax(run, width);
    x = end.x;
    y = end.y;
    line = [self getLineAtIndex:y];
    while (result.length > 0 && line[x].code == 0 && y < numberOfLines) {
        x--;
        result.length--;
        if (x == -1) {
            x = width - 1;
            y--;
            assert(y >= 0);
            line = [self getLineAtIndex:y];
        }
    }

    return result;
}

- (void)trimSelectionFromStart:(VT100GridCoord)start
                           end:(VT100GridCoord)end
                      toStartX:(VT100GridCoord *)startPtr
                        toEndX:(VT100GridCoord *)endPtr
{
    assert(start.x >= 0);
    assert(end.x >= 0);
    assert(start.y >= 0);
    assert(end.y >= 0);

    if (!XYIsBeforeXY(start.x, start.y, end.x, end.y)) {
        SwapInt(&start.x, &end.x);
        SwapInt(&start.y, &end.y);
    }

    // Advance start position until it hits a non-null or equals the end position.
    int startX = start.x;
    int startY = start.y;
    if (startX == currentGrid_.size.width) {
        startX = 0;
        startY++;
    }

    int endX = end.x;
    int endY = end.y;
    if (endX == currentGrid_.size.width) {
        endX = 0;
        endY++;
    }
    
    VT100GridRun run = VT100GridRunFromCoords(VT100GridCoordMake(startX, startY),
                                              VT100GridCoordMake(endX, endY),
                                              currentGrid_.size.width);
    assert(run.length >= 0);
    run = [self runByTrimmingNullsFromRun:run];
    assert(run.length >= 0);
    VT100GridCoord max = VT100GridRunMax(run, currentGrid_.size.width);

    *startPtr = run.origin;
    *endPtr = max;
}

- (BOOL)getNullCorrectedSelectionStartPosition:(LineBufferPosition **)startPos
                                   endPosition:(LineBufferPosition **)endPos
                 selectionStartPositionIsValid:(BOOL *)selectionStartPositionIsValid
                    selectionEndPostionIsValid:(BOOL *)selectionEndPostionIsValid
                                  inLineBuffer:(LineBuffer *)lineBuffer
                                      forRange:(VT100GridCoordRange)range
{
    int actualStartX = range.start.x;
    int actualStartY = range.start.y;
    int actualEndX = range.end.x;
    int actualEndY = range.end.y;

    BOOL endExtends = NO;
    // Use the predecessor of endx,endy so it will have a legal position in the line buffer.
    if (actualEndX == [self width]) {
        screen_char_t *line = [self getLineAtIndex:actualEndY];
        if (line[actualEndX - 1].code == 0 && line[actualEndX].code == EOL_HARD) {
            // The selection goes all the way to the end of the line and there is a null at the
            // end of the line, so it extends to the end of the line. The linebuffer can't recover
            // this from its position because the trailing null in the line wouldn't be in the
            // linebuffer.
            endExtends = YES;
        }
    }
    actualEndX--;
    if (actualEndX < 0) {
        actualEndY--;
        actualEndX = [self width] - 1;
        if (actualEndY < 0) {
            return NO;
        }
    }

    VT100GridCoord trimmedStart;
    VT100GridCoord trimmedEnd;
    [self trimSelectionFromStart:VT100GridCoordMake(actualStartX, actualStartY)
                             end:VT100GridCoordMake(actualEndX, actualEndY)
                        toStartX:&trimmedStart
                          toEndX:&trimmedEnd];
    BOOL endsAfterStart = XYIsBeforeXY(trimmedStart.x, trimmedStart.y, trimmedEnd.x, trimmedEnd.y);
    if (!endsAfterStart) {
        return NO;
    }

    *startPos = [lineBuffer positionForCoordinate:trimmedStart
                                            width:currentGrid_.size.width
                                           offset:0];
    if (selectionStartPositionIsValid) {
        *selectionStartPositionIsValid = (*startPos != nil);
    }
    *endPos = [lineBuffer positionForCoordinate:trimmedEnd
                                          width:currentGrid_.size.width
                                         offset:0];
    (*endPos).extendsToEndOfLine = endExtends;

    if (selectionEndPostionIsValid) {
        *selectionEndPostionIsValid = (*endPos != nil);
    }
    return YES;
}

- (BOOL)convertRange:(VT100GridCoordRange)range
             toWidth:(int)newWidth
                  to:(VT100GridCoordRange *)resultPtr
        inLineBuffer:(LineBuffer *)lineBuffer
{
    LineBufferPosition *selectionStartPosition;
    LineBufferPosition *selectionEndPosition;
    BOOL selectionStartPositionIsValid;
    BOOL selectionEndPostionIsValid;
    
    // Temporarily swap in the passed-in linebuffer so the call below can access lines in the right line buffer.
    LineBuffer *savedLineBuffer = linebuffer_;
    linebuffer_ = lineBuffer;
    BOOL hasSelection = [self getNullCorrectedSelectionStartPosition:&selectionStartPosition
                                                         endPosition:&selectionEndPosition
                                       selectionStartPositionIsValid:&selectionStartPositionIsValid
                                          selectionEndPostionIsValid:&selectionEndPostionIsValid
                                                        inLineBuffer:lineBuffer
                                                            forRange:range];
    linebuffer_ = savedLineBuffer;
    if (!hasSelection) {
        return NO;
    }
    if (selectionStartPositionIsValid) {
        resultPtr->start = [lineBuffer coordinateForPosition:selectionStartPosition width:newWidth ok:NULL];
        if (selectionEndPostionIsValid) {
            VT100GridCoord newEnd = [lineBuffer coordinateForPosition:selectionEndPosition width:newWidth ok:NULL];
            newEnd.x++;
            if (newEnd.x > newWidth) {
                newEnd.y++;
                newEnd.x -= newWidth;
            }
            resultPtr->end = newEnd;
        } else {
            resultPtr->end.x = currentGrid_.size.width;
            resultPtr->end.y = [lineBuffer numLinesWithWidth:newWidth] + currentGrid_.size.height - 1;
        }
    }
    if (selectionEndPostionIsValid && selectionEndPosition.extendsToEndOfLine) {
        resultPtr->end.x = newWidth;
    }
    return YES;
}

- (void)incrementOverflowBy:(int)overflowCount {
    scrollbackOverflow_ += overflowCount;
    cumulativeScrollbackOverflow_ += overflowCount;
}

// sets scrollback lines.
- (void)setMaxScrollbackLines:(unsigned int)lines;
{
    maxScrollbackLines_ = lines;
    [linebuffer_ setMaxLines: lines];
    if (!unlimitedScrollback_) {
        [self incrementOverflowBy:[linebuffer_ dropExcessLinesWithWidth:currentGrid_.size.width]];
    }
    [delegate_ screenDidChangeNumberOfScrollbackLines];
}

- (BOOL)useScrollbackWithRegion
{
    return [delegate_ screenShouldAppendToScrollbackWithStatusBar];
}

- (void)advanceCursor:(BOOL)canOccupyLastSpace
{
    // TODO: respect left-right margins
    int cursorX = currentGrid_.cursorX + 1;
    if (canOccupyLastSpace) {
        if (cursorX > currentGrid_.size.width) {
            screen_char_t* aLine = [currentGrid_ screenCharsAtLineNumber:currentGrid_.cursorY];
            aLine[currentGrid_.size.width].code = EOL_SOFT;
            [self linefeed];
            cursorX = 0;
        }
    } else if (cursorX >= currentGrid_.size.width) {
        [self linefeed];
        cursorX = 0;
    }
    currentGrid_.cursorX = cursorX;
}

- (BOOL)haveTabStopBefore:(int)limit {
    for (NSNumber *number in tabStops_) {
        if ([number intValue] < limit) {
            return YES;
        }
    }
    return NO;
}

- (void)cursorToY:(int)y
{
    int yPos;
    int topMargin = currentGrid_.topMargin;
    int bottomMargin = currentGrid_.bottomMargin;

    yPos = y - 1;

    if ([terminal_ originMode]) {
        yPos += topMargin;
        yPos = MAX(topMargin, MIN(bottomMargin, yPos));
    }
    currentGrid_.cursorY = yPos;

    DebugLog(@"cursorToY");

}

- (void)cursorToX:(int)x Y:(int)y
{
    [self cursorToX:x];
    [self cursorToY:y];
    DebugLog(@"cursorToX:Y");
}

- (void)setUseColumnScrollRegion:(BOOL)mode;
{
    currentGrid_.useScrollRegionCols = mode;
    altGrid_.useScrollRegionCols = mode;
    if (!mode) {
        currentGrid_.scrollRegionCols = VT100GridRangeMake(0, currentGrid_.size.width);
    }
}

- (BOOL)useColumnScrollRegion
{
    return currentGrid_.useScrollRegionCols;
}

- (void)blink
{
    if ([currentGrid_ isAnyCharDirty]) {
        [delegate_ screenNeedsRedraw];
    }
}

- (BOOL)haveTabStopAt:(int)x
{
    return [tabStops_ containsObject:[NSNumber numberWithInt:x]];
}

- (void)doPrint
{
    if ([printBuffer_ length] > 0) {
        [delegate_ screenPrintString:printBuffer_];
    } else {
        [delegate_ screenPrintVisibleArea];
    }
    [printBuffer_ release];
    printBuffer_ = nil;
    collectInputForPrinting_ = NO;
}

- (BOOL)isDoubleWidthCharacter:(unichar)c
{
    return [NSString isDoubleWidthCharacter:c
                     ambiguousIsDoubleWidth:[delegate_ screenShouldTreatAmbiguousCharsAsDoubleWidth]];
}

- (void)popScrollbackLines:(int)linesPushed
{
    // Undo the appending of the screen to scrollback
    int i;
    screen_char_t* dummy = calloc(currentGrid_.size.width, sizeof(screen_char_t));
    for (i = 0; i < linesPushed; ++i) {
        int cont;
        BOOL isOk = [linebuffer_ popAndCopyLastLineInto:dummy
                                                  width:currentGrid_.size.width
                                      includesEndOfLine:&cont
                                              timestamp:NULL];
        NSAssert(isOk, @"Pop shouldn't fail");
    }
    free(dummy);
}

- (void)stripTrailingSpaceFromLine:(ScreenCharArray *)line
{
    screen_char_t *p = line.line;
    int len = line.length;
    for (int i = len - 1; i >= 0; i--) {
        if (p[i].code == ' ' && ScreenCharHasDefaultAttributesAndColors(p[i])) {
            len--;
        } else {
            break;
        }
    }
    line.length = len;
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

- (long long)findContextAbsPosition
{
    return [linebuffer_ absPositionOfFindContext:findContext_];
}

- (BOOL)continueFindResultsInContext:(FindContext*)context
                             toArray:(NSMutableArray*)results
{
    // Append the screen contents to the scrollback buffer so they are included in the search.
    int linesPushed;
    linesPushed = [currentGrid_ appendLines:[currentGrid_ numberOfLinesUsed]
                               toLineBuffer:linebuffer_];

    // Search one block.
    int stopAt;
    if (context.dir > 0) {
        stopAt = [linebuffer_ lastPos];
    } else {
        stopAt = [linebuffer_ firstPos];
    }

    struct timeval begintime;
    gettimeofday(&begintime, NULL);
    BOOL keepSearching = NO;
    int iterations = 0;
    int ms_diff = 0;
    do {
        if (context.status == Searching) {
            [linebuffer_ findSubstring:context stopAt:stopAt];
        }

        // Handle the current state
        switch (context.status) {
            case Matched: {
                // NSLog(@"matched");
                // Found a match in the text.
                NSArray *allPositions = [linebuffer_ convertPositions:context.results
                                                            withWidth:currentGrid_.size.width];
                int k = 0;
                for (ResultRange* currentResultRange in context.results) {
                    SearchResult* result = [[SearchResult alloc] init];

                    XYRange* xyrange = [allPositions objectAtIndex:k++];

                    result->startX = xyrange->xStart;
                    result->endX = xyrange->xEnd;
                    result->absStartY = xyrange->yStart + [self totalScrollbackOverflow];
                    result->absEndY = xyrange->yEnd + [self totalScrollbackOverflow];

                    [results addObject:result];
                    [result release];
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
                    [linebuffer_ prepareToSearchFor:findContext_.substring
                                         startingAt:(findContext_.dir > 0 ? [linebuffer_ firstPosition] : [[linebuffer_ lastPosition] predecessor])
                                            options:findContext_.options
                                        withContext:tempFindContext];
                    [findContext_ reset];
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
    // NSLog(@"Did %d iterations in %dms. Average time per block was %dms", iterations, ms_diff, ms_diff/iterations);

    [self popScrollbackLines:linesPushed];
    return keepSearching;
}

#pragma mark - PTYNoteViewControllerDelegate

- (void)noteDidRequestRemoval:(PTYNoteViewController *)note {
    if ([marksAndNotes_ containsObject:note]) {
        [marksAndNotes_ removeObject:note];
    } else if ([savedMarksAndNotes_ containsObject:note]) {
        [savedMarksAndNotes_ removeObject:note];
    }
    [delegate_ screenNeedsRedraw];
    [delegate_ screenDidEndEditingNote];
}

- (void)noteDidEndEditing:(PTYNoteViewController *)note {
    [delegate_ screenDidEndEditingNote];
}

@end

