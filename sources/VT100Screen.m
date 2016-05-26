
#import "VT100Screen.h"

#import "CapturedOutput.h"
#import "DebugLogging.h"
#import "DVR.h"
#import "IntervalTree.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermCapturedOutputMark.h"
#import "iTermColorMap.h"
#import "iTermExpose.h"
#import "iTermGrowlDelegate.h"
#import "iTermImageMark.h"
#import "iTermPreferences.h"
#import "iTermSelection.h"
#import "iTermShellHistoryController.h"
#import "iTermTemporaryDoubleBufferedGridController.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSData+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import "PTYNoteViewController.h"
#import "PTYTextView.h"
#import "RegexKitLite.h"
#import "SearchResult.h"
#import "TmuxStateParser.h"
#import "VT100RemoteHost.h"
#import "VT100ScreenMark.h"
#import "VT100WorkingDirectory.h"
#import "VT100DCSParser.h"
#import "VT100Token.h"

#import <apr-1/apr_base64.h>
#include <string.h>

NSString *const kScreenStateKey = @"Screen State";

NSString *const kScreenStateTabStopsKey = @"Tab Stops";
NSString *const kScreenStateTerminalKey = @"Terminal State";
NSString *const kScreenStateLineDrawingModeKey = @"Line Drawing Modes";
NSString *const kScreenStateNonCurrentGridKey = @"Non-current Grid";
NSString *const kScreenStateCurrentGridIsPrimaryKey = @"Showing Primary Grid";
NSString *const kScreenStateIntervalTreeKey = @"Interval Tree";
NSString *const kScreenStateSavedIntervalTreeKey = @"Saved Interval Tree";
NSString *const kScreenStateCommandStartXKey = @"Command Start X";
NSString *const kScreenStateCommandStartYKey = @"Command Start Y";
NSString *const kScreenStateNextCommandOutputStartKey = @"Output Start";
NSString *const kScreenStateCursorVisibleKey = @"Cursor Visible";
NSString *const kScreenStateTrackCursorLineMovementKey = @"Track Cursor Line";
NSString *const kScreenStateLastCommandOutputRangeKey = @"Last Command Output Range";
NSString *const kScreenStateShellIntegrationInstalledKey = @"Shell Integration Installed";
NSString *const kScreenStateLastCommandMarkKey = @"Last Command Mark";
NSString *const kScreenStatePrimaryGridStateKey = @"Primary Grid State";
NSString *const kScreenStateAlternateGridStateKey = @"Alternate Grid State";
NSString *const kScreenStateNumberOfLinesDroppedKey = @"Number of Lines Dropped";

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

@interface VT100Screen () <iTermTemporaryDoubleBufferedGridControllerDelegate, iTermMarkDelegate>
@property(nonatomic, retain) VT100ScreenMark *lastCommandMark;
@property(nonatomic, retain) iTermTemporaryDoubleBufferedGridController *temporaryDoubleBuffer;
@end

@implementation VT100Screen {
    NSMutableSet* tabStops_;
    VT100Terminal *terminal_;
    id<VT100ScreenDelegate> delegate_;  // PTYSession implements this

    // BOOLs indicating, for each of the characters sets, which ones are in line-drawing mode.
    BOOL charsetUsesLineDrawingMode_[4];
    BOOL audibleBell_;
    BOOL showBellIndicator_;
    BOOL flashBell_;
    BOOL postGrowlNotifications_;
    BOOL cursorBlinks_;
    VT100Grid *primaryGrid_;
    VT100Grid *altGrid_;  // may be nil
    VT100Grid *currentGrid_;  // Weak reference. Points to either primaryGrid or altGrid.
    VT100Grid *realCurrentGrid_;  // When a saved grid is swapped in, this is the live current grid.

    // Max size of scrollback buffer
    unsigned int maxScrollbackLines_;
    // This flag overrides maxScrollbackLines_:
    BOOL unlimitedScrollback_;

    // How many scrollback lines have been lost due to overflow. Periodically reset with
    // -resetScrollbackOverflow.
    int scrollbackOverflow_;

    // A rarely reset count of the number of lines lost to scrollback overflow. Adding this to a
    // line number gives a unique line number that won't be reused when the linebuffer overflows.
    long long cumulativeScrollbackOverflow_;

    // When set, strings, newlines, and linefeeds are appened to printBuffer_. When ANSICSI_PRINT
    // with code 4 is received, it's sent for printing.
    BOOL collectInputForPrinting_;
    NSMutableString *printBuffer_;

    // Current find context.
    FindContext *findContext_;

    // Where we left off searching.
    long long savedFindContextAbsPos_;

    // Used for recording instant replay.
    DVR* dvr_;
    BOOL saveToScrollbackInAlternateScreen_;

    // OK to report window title?
    BOOL allowTitleReporting_;

    // Holds notes on alt/primary grid (the one we're not in). The origin is the top-left of the
    // grid.
    IntervalTree *savedIntervalTree_;

    // All currently visible marks and notes. Maps an interval of
    //   (startx + absstarty * (width+1)) to (endx + absendy * (width+1))
    // to an id<IntervalTreeObject>, which is either PTYNoteViewController or VT100ScreenMark.
    IntervalTree *intervalTree_;

    NSMutableDictionary *markCache_;  // Maps an absolute line number to a VT100ScreenMark.
    VT100GridCoordRange markCacheRange_;

    // Location of the start of the current command, or -1 for none. Y is absolute.
    int commandStartX_;
    long long commandStartY_;

    // Cached copies of terminal attributes
    BOOL _wraparoundMode;
    BOOL _ansi;
    BOOL _insert;
    
    BOOL _shellIntegrationInstalled;

    NSDictionary *inlineFileInfo_;  // Keys are kInlineFileXXX
    VT100GridAbsCoord nextCommandOutputStart_;
    NSTimeInterval lastBell_;
    BOOL _cursorVisible;
    // Line numbers containing animated GIFs that need to be redrawn for the next frame.
    NSMutableIndexSet *_animatedLines;
}

static NSString *const kInlineFileName = @"name";  // NSString
static NSString *const kInlineFileWidth = @"width";  // NSNumber
static NSString *const kInlineFileWidthUnits = @"width units";  // NSNumber of VT100TerminalUnits
static NSString *const kInlineFileHeight = @"height";  // NSNumber
static NSString *const kInlineFileHeightUnits = @"height units"; // NSNumber of VT100TerminalUnits
static NSString *const kInlineFilePreserveAspectRatio = @"preserve aspect ratio";  // NSNumber bool
static NSString *const kInlineFileBase64String = @"base64 string";  // NSMutableString
static NSString *const kInilineFileInset = @"inset";  // NSValue of NSEdgeInsets

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

- (instancetype)initWithTerminal:(VT100Terminal *)terminal {
    self = [super init];
    if (self) {
        assert(terminal);
        [self setTerminal:terminal];
        primaryGrid_ = [[VT100Grid alloc] initWithSize:VT100GridSizeMake(kDefaultScreenColumns,
                                                                         kDefaultScreenRows)
                                              delegate:self];
        currentGrid_ = primaryGrid_;
        _temporaryDoubleBuffer = [[iTermTemporaryDoubleBufferedGridController alloc] init];
        _temporaryDoubleBuffer.delegate = self;

        maxScrollbackLines_ = kDefaultMaxScrollbackLines;
        tabStops_ = [[NSMutableSet alloc] init];
        [self setInitialTabStops];
        linebuffer_ = [[LineBuffer alloc] init];

        [iTermGrowlDelegate sharedInstance];

        dvr_ = [DVR alloc];
        [dvr_ initWithBufferCapacity:[iTermPreferences intForKey:kPreferenceKeyInstantReplayMemoryMegabytes] * 1024 * 1024];

        for (int i = 0; i < NUM_CHARSETS; i++) {
            charsetUsesLineDrawingMode_[i] = NO;
        }

        findContext_ = [[FindContext alloc] init];
        savedIntervalTree_ = [[IntervalTree alloc] init];
        intervalTree_ = [[IntervalTree alloc] init];
        markCache_ = [[NSMutableDictionary alloc] init];
        commandStartX_ = commandStartY_ = -1;

        nextCommandOutputStart_ = VT100GridAbsCoordMake(-1, -1);
        _lastCommandOutputRange = VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
        _animatedLines = [[NSMutableIndexSet alloc] init];
    }
    return self;
}

- (void)dealloc {
    [primaryGrid_ release];
    [altGrid_ release];
    [tabStops_ release];
    [printBuffer_ release];
    [linebuffer_ release];
    [dvr_ release];
    [terminal_ release];
    [findContext_ release];
    [savedIntervalTree_ release];
    [intervalTree_ release];
    [markCache_ release];
    [inlineFileInfo_ release];
    [_lastCommandMark release];
    _temporaryDoubleBuffer.delegate = nil;
    [_temporaryDoubleBuffer reset];
    [_temporaryDoubleBuffer release];
    [_animatedLines release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p grid:%@>", [self class], self, currentGrid_];
}

#pragma mark - APIs

- (void)setTerminal:(VT100Terminal *)terminal {
    [terminal_ autorelease];
    terminal_ = [terminal retain];
    _ansi = [terminal_ isAnsi];
    _wraparoundMode = [terminal_ wraparoundMode];
    _insert = [terminal_ insertMode];
}

- (void)destructivelySetScreenWidth:(int)width height:(int)height {
    width = MAX(width, kVT100ScreenMinColumns);
    height = MAX(height, kVT100ScreenMinRows);

    primaryGrid_.size = VT100GridSizeMake(width, height);
    altGrid_.size = VT100GridSizeMake(width, height);
    primaryGrid_.cursor = VT100GridCoordMake(0, 0);
    altGrid_.cursor = VT100GridCoordMake(0, 0);
    [primaryGrid_ resetScrollRegions];
    [altGrid_ resetScrollRegions];
    [terminal_ resetSavedCursorPositions];

    findContext_.substring = nil;

    scrollbackOverflow_ = 0;
    [delegate_ screenRemoveSelection];

    [primaryGrid_ markAllCharsDirty:YES];
    [altGrid_ markAllCharsDirty:YES];
}

- (BOOL)intervalTreeObjectMayBeEmpty:(id)note {
    // These kinds of ranges are allowed to be empty because
    // although they nominally refer to an entire line, sometimes
    // that line is blank such as just before the prompt is
    // printed. See issue 4261.
    return ([note isKindOfClass:[VT100RemoteHost class]] ||
            [note isKindOfClass:[VT100WorkingDirectory class]] ||
            [note isKindOfClass:[iTermImageMark class]]);
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

- (VT100GridSize)size {
    return currentGrid_.size;
}

- (void)setSize:(VT100GridSize)newSize {
    [self.temporaryDoubleBuffer reset];

    DLog(@"Resize session to %@", VT100GridSizeDescription(newSize));
    DLog(@"Before:\n%@", [currentGrid_ compactLineDumpWithContinuationMarks]);
    DLog(@"Cursor at %d,%d", currentGrid_.cursorX, currentGrid_.cursorY);
    if (commandStartX_ != -1) {
        [delegate_ screenCommandDidEndWithRange:[self commandRange]];
        commandStartX_ = commandStartY_ = -1;
    }
    self.lastCommandMark = nil;

    newSize.width = MAX(newSize.width, 1);
    newSize.height = MAX(newSize.height, 1);
    if (currentGrid_.size.width == 0 ||
        currentGrid_.size.height == 0 ||
        (newSize.width == currentGrid_.size.width &&
         newSize.height == currentGrid_.size.height)) {
            return;
    }
    VT100GridSize oldSize = currentGrid_.size;

    iTermSelection *selection = [delegate_ screenSelection];
    if (selection.live) {
        [selection endLiveSelection];
    }
    [selection removeWindowsWithWidth:self.width];
    BOOL couldHaveSelection = [delegate_ screenHasView] && selection.hasSelection;

    int usedHeight = [currentGrid_ numberOfLinesUsed];

    VT100Grid *copyOfAltGrid = [[altGrid_ copy] autorelease];
    LineBuffer *realLineBuffer = linebuffer_;

    // This is an array of tuples:
    // [LineBufferPositionRange, iTermSubSelection]
    NSMutableArray *altScreenSubSelectionTuples = nil;
    LineBufferPosition *originalLastPos = [linebuffer_ lastPosition];
    BOOL wasShowingAltScreen = (currentGrid_ == altGrid_);

    // If we're in the alternate screen, create a temporary linebuffer and append
    // the base screen's contents to it.
    LineBuffer *altScreenLineBuffer = nil;

    // If non-nil, contains 3-tuples NSArray*s of
    // [ PTYNoteViewController*,
    //   LineBufferPosition* for start of range,
    //   LineBufferPosition* for end of range ]
    // These will be re-added to intervalTree_ later on.
    NSMutableArray *altScreenNotes = nil;

    if (wasShowingAltScreen) {
        if (couldHaveSelection) {
            // In alternate screen mode, get the original positions of the
            // selection. Later this will be used to set the selection positions
            // relative to the end of the updated linebuffer (which could change as
            // lines from the base screen are pushed onto it).
            LineBuffer *lineBufferWithAltScreen = [[linebuffer_ newAppendOnlyCopy] autorelease];
            [self appendScreen:currentGrid_
                  toScrollback:lineBufferWithAltScreen
                withUsedHeight:usedHeight
                     newHeight:newSize.height];
            altScreenSubSelectionTuples = [NSMutableArray array];
            for (iTermSubSelection *sub in selection.allSubSelections) {
                VT100GridCoordRange range = sub.range.coordRange;
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
            }
        }

        altScreenLineBuffer = [[[LineBuffer alloc] init] autorelease];
        [self appendScreen:altGrid_
              toScrollback:altScreenLineBuffer
            withUsedHeight:usedHeight
                 newHeight:newSize.height];

        if ([intervalTree_ count]) {
            // Add notes that were on the alt grid to altScreenNotes, leaving notes in history alone.
            VT100GridCoordRange screenCoordRange =
            VT100GridCoordRangeMake(0,
                                    [self numberOfScrollbackLines],
                                    0,
                                    [self numberOfScrollbackLines] + self.height);
            NSArray *notesAtLeastPartiallyOnScreen =
                [intervalTree_ objectsInInterval:[self intervalForGridCoordRange:screenCoordRange]];

            LineBuffer *appendOnlyLineBuffer = [[realLineBuffer newAppendOnlyCopy] autorelease];
            [self appendScreen:altGrid_
                  toScrollback:appendOnlyLineBuffer
                withUsedHeight:usedHeight
                     newHeight:newSize.height];
            altScreenNotes = [NSMutableArray array];

            for (id<IntervalTreeObject> note in notesAtLeastPartiallyOnScreen) {
                VT100GridCoordRange range = [self coordRangeForInterval:note.entry.interval];
                [[note retain] autorelease];
                [intervalTree_ removeObject:note];
                LineBufferPositionRange *positionRange =
                  [self positionRangeForCoordRange:range inLineBuffer:appendOnlyLineBuffer tolerateEmpty:[self intervalTreeObjectMayBeEmpty:note]];
                if (positionRange) {
                    DLog(@"Add note on alt screen at %@ (position %@ to %@) to altScreenNotes",
                         VT100GridCoordRangeDescription(range),
                         positionRange.start,
                         positionRange.end);
                    [altScreenNotes addObject:@[ note, positionRange.start, positionRange.end ]];
                } else {
                    DLog(@"Failed to get position range while in alt screen for note %@ with range %@",
                         note, VT100GridCoordRangeDescription(range));
                }
            }
        }

        currentGrid_ = primaryGrid_;
        // Move savedIntervalTree_ into intervalTree_. This should leave savedIntervalTree_ empty.
        [self swapNotes];
        currentGrid_ = altGrid_;
    }

    // Append primary grid to line buffer.
    [self appendScreen:primaryGrid_
          toScrollback:linebuffer_
        withUsedHeight:[primaryGrid_ numberOfLinesUsed]
             newHeight:newSize.height];
    DLog(@"History after appending screen to scrollback:\n%@", [linebuffer_ debugString]);

    // Contains iTermSubSelection*s updated for the new screen size. Used
    // regardless of whether we were in the alt screen, as it's simply the set
    // of new sub-selections.
    NSMutableArray *newSubSelections = [NSMutableArray array];
    if (!wasShowingAltScreen && couldHaveSelection) {
        for (iTermSubSelection *sub in selection.allSubSelections) {
            VT100GridCoordRange newSelection;
            DLog(@"convert sub %@", sub);
            BOOL ok = [self convertRange:sub.range.coordRange
                                 toWidth:newSize.width
                                      to:&newSelection
                            inLineBuffer:linebuffer_
                           tolerateEmpty:NO];
            if (ok) {
                assert(sub.range.coordRange.start.y >= 0);
                assert(sub.range.coordRange.end.y >= 0);
                VT100GridWindowedRange theRange = VT100GridWindowedRangeMake(newSelection, 0, 0);
                iTermSubSelection *theSub =
                    [iTermSubSelection subSelectionWithRange:theRange mode:sub.selectionMode];
                theSub.connected = sub.connected;
                [newSubSelections addObject:theSub];
            }
        }
    }

    if ([intervalTree_ count]) {
        // Fix up the intervals for the primary grid.
        if (wasShowingAltScreen) {
            // Temporarily swap in primary grid so convertRange: will do the right thing.
            currentGrid_ = primaryGrid_;
        }

        // Convert ranges of notes to their new coordinates and replace the interval tree.
        IntervalTree *replacementTree = [[IntervalTree alloc] init];
        for (id<IntervalTreeObject> note in [intervalTree_ allObjects]) {
            VT100GridCoordRange noteRange = [self coordRangeForInterval:note.entry.interval];
            VT100GridCoordRange newRange;
            if (noteRange.end.x < 0 && noteRange.start.y == 0 && noteRange.end.y < 0) {
                // note has scrolled off top
                [intervalTree_ removeObject:note];
            } else {
                if ([self convertRange:noteRange
                               toWidth:newSize.width
                                    to:&newRange
                          inLineBuffer:linebuffer_
                         tolerateEmpty:[self intervalTreeObjectMayBeEmpty:note]]) {
                    assert(noteRange.start.y >= 0);
                    assert(noteRange.end.y >= 0);
                    Interval *newInterval = [self intervalForGridCoordRange:newRange
                                                                      width:newSize.width
                                                                linesOffset:[self totalScrollbackOverflow]];
                    [[note retain] autorelease];
                    [intervalTree_ removeObject:note];
                    [replacementTree addObject:note withInterval:newInterval];
                }
            }
        }
        [intervalTree_ release];
        intervalTree_ = replacementTree;

        if (wasShowingAltScreen) {
            // Return to alt grid.
            currentGrid_ = altGrid_;
        }
    }
    currentGrid_.size = newSize;

    // Restore the screen contents that were pushed onto the linebuffer.
    [currentGrid_ restoreScreenFromLineBuffer:wasShowingAltScreen ? altScreenLineBuffer : linebuffer_
                              withDefaultChar:[currentGrid_ defaultChar]
                            maxLinesToRestore:[linebuffer_ numLinesWithWidth:currentGrid_.size.width]];
    DLog(@"After restoring screen from line buffer:\n%@", [self compactLineDumpWithHistoryAndContinuationMarksAndLineNumbers]);
    
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
        if (oldSize.height < newSize.height) {
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
                                    maxLinesToRestore:newSize.height];
        }

        // Any onscreen notes in primary grid get moved to savedIntervalTree_.
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
                 newHeight:newSize.height];

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
                VT100GridWindowedRange theRange =
                    VT100GridWindowedRangeMake(newSelection, 0, 0);
                iTermSubSelection *theSub = [iTermSubSelection subSelectionWithRange:theRange
                                                                                mode:originalSub.selectionMode];
                theSub.connected = originalSub.connected;
                [newSubSelections addObject:theSub];
            }
        }
        DLog(@"Original limit=%@", originalLastPos);
        DLog(@"New limit=%@", newLastPos);
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
                [intervalTree_ addObject:note withInterval:interval];
            } else {
                DLog(@"  *FAILED TO CONVERT*");
            }
        }
    } else {
        // Was showing primary grid. Fix up notes in the alt screen.

        // Append alt screen to empty line buffer
        altScreenLineBuffer = [[[LineBuffer alloc] init] autorelease];
        [self appendScreen:altGrid_
              toScrollback:altScreenLineBuffer
            withUsedHeight:[altGrid_ numberOfLinesUsed]
                 newHeight:newSize.height];
        int numLinesThatWillBeRestored = MIN([altScreenLineBuffer numLinesWithWidth:newSize.width],
                                             newSize.height);
        int numLinesDroppedFromTop = [altScreenLineBuffer numLinesWithWidth:newSize.width] - numLinesThatWillBeRestored;

        // Convert note ranges to new coords, dropping or truncating as needed
        currentGrid_ = altGrid_;  // Swap to alt grid temporarily for convertRange:toWidth:to:inLineBuffer:
        IntervalTree *replacementTree = [[IntervalTree alloc] init];
        for (PTYNoteViewController *note in [savedIntervalTree_ allObjects]) {
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
                [savedIntervalTree_ removeObject:note];
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
        [savedIntervalTree_ release];
        savedIntervalTree_ = replacementTree;
        currentGrid_ = primaryGrid_;  // Swap back to primary grid

        // Restore alt screen with new width
        altGrid_.size = VT100GridSizeMake(newSize.width, newSize.height);
        [altGrid_ restoreScreenFromLineBuffer:altScreenLineBuffer
                              withDefaultChar:[altGrid_ defaultChar]
                            maxLinesToRestore:[altScreenLineBuffer numLinesWithWidth:currentGrid_.size.width]];
    }

    [terminal_ clampSavedCursorToScreenSize:VT100GridSizeMake(newSize.width, newSize.height)];

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
    int lines __attribute__((unused)) = [linebuffer_ numLinesWithWidth:currentGrid_.size.width];
    NSAssert(lines >= 0, @"Negative lines");

    // An immediate refresh is needed so that the size of textview can be
    // adjusted to fit the new size
    DebugLog(@"setSize setDirty");
    [delegate_ screenNeedsRedraw];
    [selection clearSelection];
    if (couldHaveSelection) {
        NSMutableArray *subSelectionsToAdd = [NSMutableArray array];
        for (iTermSubSelection* sub in newSubSelections) {
            VT100GridCoordRange newSelection = sub.range.coordRange;
            if (newSelection.start.y >= linesDropped &&
                newSelection.end.y >= linesDropped) {
                newSelection.start.y -= linesDropped;
                newSelection.end.y -= linesDropped;
                [subSelectionsToAdd addObject:sub];
            }
        }
        [selection addSubSelections:subSelectionsToAdd];
    }

    [self reloadMarkCache];
    [delegate_ screenSizeDidChange];
    DLog(@"After:\n%@", [currentGrid_ compactLineDumpWithContinuationMarks]);
    DLog(@"Cursor at %d,%d", currentGrid_.cursorX, currentGrid_.cursorY);
}

- (void)reloadMarkCache {
    long long totalScrollbackOverflow = [self totalScrollbackOverflow];
    [markCache_ removeAllObjects];
    for (id<IntervalTreeObject> obj in [intervalTree_ allObjects]) {
        if ([obj isKindOfClass:[VT100ScreenMark class]]) {
            VT100GridCoordRange range = [self coordRangeForInterval:obj.entry.interval];
            VT100ScreenMark *mark = (VT100ScreenMark *)obj;
            markCache_[@(totalScrollbackOverflow + range.end.y)] = mark;
        }
    }
}

- (BOOL)allCharacterSetPropertiesHaveDefaultValues {
    for (int i = 0; i < NUM_CHARSETS; i++) {
        if (charsetUsesLineDrawingMode_[i]) {
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

- (void)clearBuffer {
    [self clearAndResetScreenPreservingCursorLine];
    [self clearScrollbackBuffer];
    [delegate_ screenUpdateDisplay:NO];
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
    [intervalTree_ release];
    intervalTree_ = [[IntervalTree alloc] init];
    [self reloadMarkCache];
}

- (void)appendScreenChars:(screen_char_t *)line
                   length:(int)length
             continuation:(screen_char_t)continuation {
    [self appendScreenCharArrayAtCursor:line
                                 length:length
                             shouldFree:NO];
    if (continuation.code == EOL_HARD) {
        [self terminalCarriageReturn];
        [self linefeed];
    }
}

- (void)appendAsciiDataAtCursor:(AsciiData *)asciiData
{
    int len = asciiData->length;
    if (len < 1 || !asciiData) {
        return;
    }
    STOPWATCH_START(appendAsciiDataAtCursor);
    char firstChar = asciiData->buffer[0];

    DLog(@"appendAsciiDataAtCursor: %ld chars starting with %c at x=%d, y=%d, line=%d",
         (unsigned long)len,
         firstChar,
         currentGrid_.cursorX,
         currentGrid_.cursorY,
         currentGrid_.cursorY + [linebuffer_ numLinesWithWidth:currentGrid_.size.width]);

    screen_char_t *buffer;
    buffer = asciiData->screenChars->buffer;

    screen_char_t fg = [terminal_ foregroundColorCode];
    screen_char_t bg = [terminal_ backgroundColorCode];
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
    // characters into graphics charaters.
    if (charsetUsesLineDrawingMode_[[terminal_ charset]]) {
        ConvertCharsToGraphicsCharset(buffer, len);
    }

    [self appendScreenCharArrayAtCursor:buffer
                                 length:len
                             shouldFree:NO];
    STOPWATCH_LAP(appendAsciiDataAtCursor);
}

- (void)appendStringAtCursor:(NSString *)string
{
    int len = [string length];
    if (len < 1 || !string) {
        return;
    }

    unichar firstChar =  [string characterAtIndex:0];

    DLog(@"appendStringAtCursor: %ld chars starting with %c at x=%d, y=%d, line=%d",
         (unsigned long)len,
         firstChar,
         currentGrid_.cursorX,
         currentGrid_.cursorY,
         currentGrid_.cursorY + [linebuffer_ numLinesWithWidth:currentGrid_.size.width]);

    // Allocate a buffer of screen_char_t and place the new string in it.
    const int kStaticBufferElements = 1024;
    screen_char_t staticBuffer[kStaticBufferElements];
    screen_char_t *dynamicBuffer = 0;
    screen_char_t *buffer;
    string = _useHFSPlusMapping ? [string precomposedStringWithHFSPlusMapping]
                                : [string precomposedStringWithCanonicalMapping];
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

    BOOL predecessorIsDoubleWidth = NO;
    VT100GridCoord pred = [currentGrid_ coordinateBefore:currentGrid_.cursor
                                movedBackOverDoubleWidth:&predecessorIsDoubleWidth];
    NSString *augmentedString = string;
    NSString *predecessorString = pred.x >= 0 ? [currentGrid_ stringForCharacterAt:pred] : nil;
    BOOL augmented = predecessorString != nil;
    if (augmented) {
        augmentedString = [predecessorString stringByAppendingString:string];
    } else {
        // Prepend a space so we can detect if the first character is a combining mark.
        augmentedString = [@" " stringByAppendingString:string];
    }

    assert(terminal_);
    // Add DWC_RIGHT after each double-byte character, build complex characters out of surrogates
    // and combining marks, replace private codes with replacement characters, swallow zero-
    // width spaces, and set fg/bg colors and attributes.
    BOOL dwc = NO;
    StringToScreenChars(augmentedString,
                        buffer,
                        [terminal_ foregroundColorCode],
                        [terminal_ backgroundColorCode],
                        &len,
                        [delegate_ screenShouldTreatAmbiguousCharsAsDoubleWidth],
                        NULL,
                        &dwc,
                        _useHFSPlusMapping);
    ssize_t bufferOffset = 0;
    if (augmented && len > 0) {
        screen_char_t *theLine = [self getLineAtScreenIndex:pred.y];
        theLine[pred.x].code = buffer[0].code;
        theLine[pred.x].complexChar = buffer[0].complexChar;
        bufferOffset++;

        if (predecessorIsDoubleWidth && len > 1 && buffer[1].code == DWC_RIGHT) {
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
        linebuffer_.mayHaveDoubleWidthCharacter = dwc;
    }
    [self appendScreenCharArrayAtCursor:buffer + bufferOffset
                                 length:len - bufferOffset
                             shouldFree:NO];
    if (buffer == dynamicBuffer) {
        free(buffer);
    }
}

- (void)appendScreenCharArrayAtCursor:(screen_char_t *)buffer
                               length:(int)len
                           shouldFree:(BOOL)shouldFree {
    if (len >= 1) {
        LineBuffer *lineBuffer = nil;
        if (currentGrid_ != altGrid_ || saveToScrollbackInAlternateScreen_) {
            // Not in alt screen or it's ok to scroll into line buffer while in alt screen.k
            lineBuffer = linebuffer_;
        }
        [self incrementOverflowBy:[currentGrid_ appendCharsAtCursor:buffer
                                                             length:len
                                            scrollingIntoLineBuffer:lineBuffer
                                                unlimitedScrollback:unlimitedScrollback_
                                            useScrollbackWithRegion:_appendToScrollbackWithStatusBar
                                                         wraparound:_wraparoundMode
                                                               ansi:_ansi
                                                             insert:_insert]];
    }

    if (shouldFree) {
        free(buffer);
    }

    if (commandStartX_ != -1) {
        [delegate_ screenCommandDidChangeWithRange:[self commandRange]];
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
    const BOOL noScrollback = (currentGrid_ == altGrid_ && !saveToScrollbackInAlternateScreen_);
    if (noScrollback) {
        // In alt grid but saving to scrollback in alt-screen is off, so pass in a nil linebuffer.
        lineBufferToUse = nil;
    }
    [self incrementOverflowBy:[currentGrid_ moveCursorDownOneLineScrollingIntoLineBuffer:lineBufferToUse
                                                                     unlimitedScrollback:unlimitedScrollback_
                                                                 useScrollbackWithRegion:_appendToScrollbackWithStatusBar
                               willScroll:^{
                                   if (noScrollback) {
                                       // This is a temporary hack. In this case, keeping the selection in the right place requires
                                       // more cooperation between VT100Screen and PTYTextView than is currently in place because
                                       // the selection could become truncated, and regardless, will need to move up a line in terms
                                       // of absolute Y position (normally when the screen scrolls the absolute Y position of the
                                       // selection stays the same and the viewport moves down, or else there is soem scrollback
                                       // overflow and PTYTextView -refresh bumps the selection's Y position, but because in this
                                       // case we don't append to the line buffer, scrollback overflow will not increment).
                                       [delegate_ screenRemoveSelection];
                                   }
                               }]];
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

- (void)activateBell {
    if ([delegate_ screenShouldIgnoreBellWhichIsAudible:audibleBell_ visible:flashBell_]) {
        return;
    }
    if (audibleBell_) {
        // Some bells or systems block on NSBeep so it's important to rate-limit it to prevent
        // bells from blocking the terminal indefinitely. The small delay we insert between
        // bells allows us to swallow up the vast majority of ^G characters when you cat a
        // binary file.
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval interval = now - lastBell_;
        if (interval > kInterBellQuietPeriod) {
            NSBeep();
            lastBell_ = now;
        }
    }
    if (showBellIndicator_) {
        [delegate_ screenShowBellIndicator];
    }
    if (flashBell_) {
        [delegate_ screenFlashImage:kiTermIndicatorBell];
    }
    [delegate_ screenIncrementBadge];
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
    temp.mayHaveDoubleWidthCharacter = YES;
    linebuffer_.mayHaveDoubleWidthCharacter = YES;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
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
                   width:currentGrid_.size.width
               timestamp:now
            continuation:continuation];
    }
    NSMutableArray *wrappedLines = [NSMutableArray array];
    int n = [temp numLinesWithWidth:currentGrid_.size.width];
    int numberOfConsecutiveEmptyLines = 0;
    for (int i = 0; i < n; i++) {
        ScreenCharArray *line = [temp wrappedLineAtIndex:i
                                                   width:currentGrid_.size.width
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
        [linebuffer_ appendLine:line.line
                         length:line.length
                        partial:(line.eol != EOL_HARD)
                          width:currentGrid_.size.width
                      timestamp:now
                   continuation:continuation];
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
    linebuffer_.mayHaveDoubleWidthCharacter = YES;
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
            dest[altGrid_.size.width] = dest[altGrid_.size.width - 1];  // TODO: This is probably wrong?
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
        [terminal_ setSavedCursorPosition:VT100GridCoordMake([savedX intValue], [savedY intValue])];
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

- (void)highlightTextInRange:(NSRange)range
   basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                      colors:(NSDictionary *)colors {
    long long lineNumber = absoluteLineNumber - self.totalScrollbackOverflow - self.numberOfScrollbackLines;

    VT100GridRun gridRun = [currentGrid_ gridRunFromRange:range relativeToRow:lineNumber];
    if (gridRun.length > 0) {
        NSColor *foreground = colors[kHighlightForegroundColor];
        NSColor *background = colors[kHighlightBackgroundColor];
        [self highlightRun:gridRun withForegroundColor:foreground backgroundColor:background];
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

#pragma mark - PTYTextViewDataSource

// This is a wee hack until PTYTextView breaks its direct dependence on PTYSession
- (PTYSession *)session {
    return (PTYSession *)delegate_;
}

// Returns the number of lines in scrollback plus screen height.
- (int)numberOfLines {
    return [linebuffer_ numLinesWithWidth:currentGrid_.size.width] + currentGrid_.size.height;
}

- (int)width {
    return currentGrid_.size.width;
}

- (int)height {
    return currentGrid_.size.height;
}

- (int)cursorX {
    return currentGrid_.cursorX + 1;
}

- (int)cursorY {
    return currentGrid_.cursorY + 1;
}

- (void)setCursorPosition:(VT100GridCoord)coord {
    currentGrid_.cursor = coord;
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
        screen_char_t continuation;
        int cont = [linebuffer_ copyLineToBuffer:buffer
                                           width:currentGrid_.size.width
                                         lineNum:theIndex
                                    continuation:&continuation];
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
        buffer[currentGrid_.size.width] = continuation;
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

- (int)lineNumberOfCursor
{
    return [self numberOfLines] - [self height] + currentGrid_.cursorY;
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
    FindOptions opts = 0;
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
    NSMutableString *string = [NSMutableString stringWithString:[linebuffer_ compactLineDumpWithWidth:[self width]
                                                                                 andContinuationMarks:NO]];
    if ([string length]) {
        [string appendString:@"\n"];
    }
    [string appendString:[currentGrid_ compactLineDump]];
    return string;
}

- (NSString *)compactLineDumpWithHistoryAndContinuationMarks {
    NSMutableString *string = [NSMutableString stringWithString:[linebuffer_ compactLineDumpWithWidth:[self width]
                                                                                 andContinuationMarks:YES]];
    if ([string length]) {
        [string appendString:@"\n"];
    }
    [string appendString:[currentGrid_ compactLineDumpWithContinuationMarks]];
    return string;
}

- (NSString *)compactLineDumpWithHistoryAndContinuationMarksAndLineNumbers {
    NSMutableString *string =
        [NSMutableString stringWithString:[linebuffer_ compactLineDumpWithWidth:self.width andContinuationMarks:YES]];
    NSMutableArray *lines = [[[string componentsSeparatedByString:@"\n"] mutableCopy] autorelease];
    long long absoluteLineNumber = self.totalScrollbackOverflow;
    for (int i = 0; i < lines.count; i++) {
        lines[i] = [NSString stringWithFormat:@"%8lld:        %@", absoluteLineNumber++, lines[i]];
    }

    if ([string length]) {
        [lines addObject:@"- end of history -"];
    }
    NSString *gridDump = [currentGrid_ compactLineDumpWithContinuationMarks];
    NSArray *gridLines = [gridDump componentsSeparatedByString:@"\n"];
    for (int i = 0; i < gridLines.count; i++) {
        [lines addObject:[NSString stringWithFormat:@"%8lld (%04d): %@", absoluteLineNumber++, i, gridLines[i]]];
    }
    return [lines componentsJoinedByString:@"\n"];
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

- (void)setLineDirtyAtY:(int)y {
    if (y >= 0) {
        [currentGrid_ markCharsDirty:YES
                          inRectFrom:VT100GridCoordMake(0, y)
                                  to:VT100GridCoordMake(self.width - 1, y)];
    }
}

- (void)setRangeOfCharsAnimated:(NSRange)range onLine:(int)line {
    // TODO: Store range
    [_animatedLines addIndex:line];
}

- (void)resetAnimatedLines {
    [_animatedLines removeAllIndexes];
}

- (void)setCharDirtyAtCursorX:(int)x Y:(int)y {
    if (y < 0) {
        DLog(@"Warning: cannot set character dirty at y=%d", y);
        return;
    }
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

- (NSIndexSet *)dirtyIndexesOnLine:(int)line {
    return [currentGrid_ dirtyIndexesOnLine:line];
}

- (void)resetDirty
{
    [currentGrid_ markAllCharsDirty:NO];
}

- (void)saveToDvr
{
    if (!dvr_) {
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

- (void)setWorkingDirectory:(NSString *)workingDirectory onLine:(int)line {
    DLog(@"setWorkingDirectory:%@ onLine:%d", workingDirectory, line);
    VT100WorkingDirectory *workingDirectoryObj = [[[VT100WorkingDirectory alloc] init] autorelease];
    if (!workingDirectory) {
        workingDirectory = [delegate_ screenCurrentWorkingDirectory];
    }
    if (workingDirectory.length) {
        DLog(@"Changing working directory to %@", workingDirectory);
        workingDirectoryObj.workingDirectory = workingDirectory;

        VT100WorkingDirectory *previousWorkingDirectory = [[[self objectOnOrBeforeLine:line
                                                                               ofClass:[VT100WorkingDirectory class]] retain] autorelease];
        DLog(@"The previous directory was %@", previousWorkingDirectory);
        if ([previousWorkingDirectory.workingDirectory isEqualTo:workingDirectory]) {
            // Extend the previous working directory. We used to add a new VT100WorkingDirectory
            // every time but if the window title gets changed a lot then they can pile up really
            // quickly and you spend all your time searching through VT001WorkingDirectory marks
            // just to find VT100RemoteHost or VT100ScreenMark objects.
            //
            // It's a little weird that a VT100WorkingDirectory can now represent the same path on
            // two different hosts (e.g., you ssh from /Users/georgen to another host and you're in
            // /Users/georgen over there, but you can share the same VT100WorkingDirectory between
            // the two hosts because the path is the same). I can't see the harm in it besides being
            // odd.
            //
            // Intervals aren't removed while part of them is on screen, so this works fine.
            VT100GridCoordRange range = [self coordRangeForInterval:previousWorkingDirectory.entry.interval];
            [intervalTree_ removeObject:previousWorkingDirectory];
            range.end = VT100GridCoordMake(self.width, line);
            DLog(@"Extending the previous directory to %@", VT100GridCoordRangeDescription(range));
            Interval *interval = [self intervalForGridCoordRange:range];
            [intervalTree_ addObject:previousWorkingDirectory withInterval:interval];
        } else {
            VT100GridCoordRange range;
            range = VT100GridCoordRangeMake(currentGrid_.cursorX, line, self.width, line);
            DLog(@"Set range of %@ to %@", workingDirectory, VT100GridCoordRangeDescription(range));
            [intervalTree_ addObject:workingDirectoryObj
                        withInterval:[self intervalForGridCoordRange:range]];
        }
    }
    [delegate_ screenLogWorkingDirectoryAtLine:line withDirectory:workingDirectory];
}

- (VT100RemoteHost *)setRemoteHost:(NSString *)host user:(NSString *)user onLine:(int)line {
    VT100RemoteHost *remoteHostObj = [[[VT100RemoteHost alloc] init] autorelease];
    remoteHostObj.hostname = host;
    remoteHostObj.username = user;
    VT100GridCoordRange range = VT100GridCoordRangeMake(0, line, self.width, line);
    [intervalTree_ addObject:remoteHostObj
                withInterval:[self intervalForGridCoordRange:range]];
    return remoteHostObj;
}

- (id)objectOnOrBeforeLine:(int)line ofClass:(Class)cls {
    long long pos = [self intervalForGridCoordRange:VT100GridCoordRangeMake(0,
                                                                            line + 1,
                                                                            0,
                                                                            line + 1)].location;
    NSEnumerator *enumerator = [intervalTree_ reverseEnumeratorAt:pos];
    NSArray *objects;
    do {
        objects = [enumerator nextObject];
        objects = [objects objectsOfClasses:@[ cls ]];
    } while (objects && !objects.count);
    if (objects.count) {
        // We want the last object because they are sorted chronologically.
        return [objects lastObject];
    } else {
        return nil;
    }
}

- (VT100RemoteHost *)remoteHostOnLine:(int)line {
    return (VT100RemoteHost *)[self objectOnOrBeforeLine:line ofClass:[VT100RemoteHost class]];
}

- (SCPPath *)scpPathForFile:(NSString *)filename onLine:(int)line {
    DLog(@"Figuring out path for %@ on line %d", filename, line);
    VT100RemoteHost *remoteHost = [self remoteHostOnLine:line];
    if (!remoteHost.username || !remoteHost.hostname) {
        DLog(@"nil username or hostname; return nil");
        return nil;
    }
    if (remoteHost.isLocalhost) {
        DLog(@"Is localhost; return nil");
        return nil;
    }
    NSString *workingDirectory = [self workingDirectoryOnLine:line];
    if (!workingDirectory) {
        DLog(@"No working directory; return nil");
        return nil;
    }
    NSString *path;
    if ([filename hasPrefix:@"/"]) {
        DLog(@"Filename is absolute path, so that's easy");
        path = filename;
    } else {
        DLog(@"Use working directory of %@", workingDirectory);
        path = [workingDirectory stringByAppendingPathComponent:filename];
    }
    SCPPath *scpPath = [[[SCPPath alloc] init] autorelease];
    scpPath.path = path;
    scpPath.hostname = remoteHost.hostname;
    scpPath.username = remoteHost.username;
    return scpPath;
}

- (NSString *)workingDirectoryOnLine:(int)line {
    VT100WorkingDirectory *workingDirectory =
        [self objectOnOrBeforeLine:line ofClass:[VT100WorkingDirectory class]];
    return workingDirectory.workingDirectory;
}

- (void)addNote:(PTYNoteViewController *)note
        inRange:(VT100GridCoordRange)range {
    [intervalTree_ addObject:note withInterval:[self intervalForGridCoordRange:range]];
    [currentGrid_ markCharsDirty:YES inRectFrom:range.start to:[self predecessorOfCoord:range.end]];
    note.delegate = self;
    [delegate_ screenDidAddNote:note];
}

- (void)removeInaccessibleNotes {
    long long lastDeadLocation = [self totalScrollbackOverflow] * (self.width + 1);
    long long totalScrollbackOverflow = [self totalScrollbackOverflow];
    if (lastDeadLocation > 0) {
        Interval *deadInterval = [Interval intervalWithLocation:0 length:lastDeadLocation + 1];
        for (id<IntervalTreeObject> obj in [intervalTree_ objectsInInterval:deadInterval]) {
            if ([obj.entry.interval limit] <= lastDeadLocation) {
                if ([obj isKindOfClass:[VT100ScreenMark class]]) {
                    long long theKey = (totalScrollbackOverflow +
                                        [self coordRangeForInterval:obj.entry.interval].end.y);
                    [markCache_ removeObjectForKey:@(theKey)];
                    self.lastCommandMark = nil;
                }
                [intervalTree_ removeObject:obj];
            }
        }
    }
}

- (BOOL)markIsValid:(iTermMark *)mark {
    return [intervalTree_ containsObject:mark];
}

- (id<iTermMark>)addMarkStartingAtAbsoluteLine:(long long)line
                                       oneLine:(BOOL)oneLine
                                       ofClass:(Class)markClass {
    id<iTermMark> mark = [[[markClass alloc] init] autorelease];
    if ([mark isKindOfClass:[VT100ScreenMark class]]) {
        VT100ScreenMark *screenMark = mark;
        screenMark.delegate = self;
        screenMark.sessionGuid = [delegate_ screenSessionGuid];
    }
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
    if ([mark isKindOfClass:[VT100ScreenMark class]]) {
        markCache_[@([self totalScrollbackOverflow] + range.end.y)] = mark;
    }
    [intervalTree_ addObject:mark withInterval:[self intervalForGridCoordRange:range]];
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
    NSArray *objects = [intervalTree_ objectsInInterval:interval];
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
    NSArray *objects = [intervalTree_ objectsInInterval:interval];
    NSMutableArray *notes = [NSMutableArray array];
    for (id<IntervalTreeObject> o in objects) {
        if ([o isKindOfClass:[PTYNoteViewController class]]) {
            [notes addObject:o];
        }
    }
    return notes;
}

- (VT100ScreenMark *)lastPromptMark {
    return [self lastMarkMustBePrompt:YES class:[VT100ScreenMark class]];
}

- (VT100ScreenMark *)lastMark {
    return [self lastMarkMustBePrompt:NO class:[VT100ScreenMark class]];
}

- (VT100RemoteHost *)lastRemoteHost {
    return [self lastMarkMustBePrompt:NO class:[VT100RemoteHost class]];
}

- (id)lastMarkMustBePrompt:(BOOL)wantPrompt class:(Class)theClass {
    NSEnumerator *enumerator = [intervalTree_ reverseLimitEnumerator];
    NSArray *objects = [enumerator nextObject];
    while (objects) {
        for (id obj in objects) {
            if ([obj isKindOfClass:theClass]) {
                if (wantPrompt && [obj isPrompt]) {
                    return obj;
                } else if (!wantPrompt) {
                    return obj;
                }
            }
        }
        objects = [enumerator nextObject];
    }
    return nil;
}

- (VT100ScreenMark *)markOnLine:(int)line {
  return markCache_[@([self totalScrollbackOverflow] + line)];
}

- (NSArray *)lastMarksOrNotes {
    NSEnumerator *enumerator = [intervalTree_ reverseLimitEnumerator];
    NSArray *objects;
    do {
        objects = [enumerator nextObject];
        objects = [objects objectsOfClasses:@[ [PTYNoteViewController class],
                                               [VT100ScreenMark class] ]];
    } while (objects && !objects.count);
    return objects;
}

- (NSArray *)firstMarksOrNotes {
    NSEnumerator *enumerator = [intervalTree_ forwardLimitEnumerator];
    NSArray *objects;
    do {
        objects = [enumerator nextObject];
        objects = [objects objectsOfClasses:@[ [PTYNoteViewController class],
                                               [VT100ScreenMark class] ]];
    } while (objects && !objects.count);
    return objects;
}

- (int)lineNumberOfMarkBeforeLine:(int)line {
    Interval *interval = [self intervalForGridCoordRange:VT100GridCoordRangeMake(0, line, 0, line)];
    NSEnumerator *enumerator = [intervalTree_ reverseLimitEnumeratorAt:interval.limit];
    NSArray *objects = [enumerator nextObject];
    while (objects) {
        for (id object in objects) {
            if ([object isKindOfClass:[VT100ScreenMark class]]) {
                VT100ScreenMark *mark = object;
                return [self coordRangeForInterval:mark.entry.interval].start.y;
            }
        }
        objects = [enumerator nextObject];
    }
    return -1;
}

- (int)lineNumberOfMarkAfterLine:(int)line {
    Interval *interval = [self intervalForGridCoordRange:VT100GridCoordRangeMake(0, line + 1, 0, line + 1)];
    NSEnumerator *enumerator = [intervalTree_ forwardLimitEnumeratorAt:interval.limit];
    NSArray *objects = [enumerator nextObject];
    while (objects) {
        for (id object in objects) {
            if ([object isKindOfClass:[VT100ScreenMark class]]) {
                VT100ScreenMark *mark = object;
                return [self coordRangeForInterval:mark.entry.interval].end.y;
            }
        }
        objects = [enumerator nextObject];
    }
    return -1;
}

- (NSArray *)marksOrNotesBefore:(Interval *)location {
    NSEnumerator *enumerator = [intervalTree_ reverseLimitEnumeratorAt:location.limit];
    NSArray *objects;
    do {
        objects = [enumerator nextObject];
        objects = [objects objectsOfClasses:@[ [PTYNoteViewController class],
                                               [VT100ScreenMark class] ]];
    } while (objects && !objects.count);
    return objects;
}

- (NSArray *)marksOrNotesAfter:(Interval *)location {
    NSEnumerator *enumerator = [intervalTree_ forwardLimitEnumeratorAt:location.limit];
    NSArray *objects;
    do {
        objects = [enumerator nextObject];
        objects = [objects objectsOfClasses:@[ [PTYNoteViewController class],
                                               [VT100ScreenMark class] ]];
    } while (objects && !objects.count);
    return objects;
}

- (BOOL)containsMark:(id<iTermMark>)mark {
    for (id obj in [intervalTree_ objectsInInterval:mark.entry.interval]) {
        if (obj == mark) {
            return YES;
        }
    }
    return NO;
}

- (VT100GridRange)lineNumberRangeOfInterval:(Interval *)interval {
    VT100GridCoordRange range = [self coordRangeForInterval:interval];
    return VT100GridRangeMake(range.start.y, range.end.y - range.start.y + 1);
}

- (VT100GridCoordRange)textViewRangeOfOutputForCommandMark:(VT100ScreenMark *)mark {
    NSEnumerator *enumerator = [intervalTree_ forwardLimitEnumeratorAt:mark.entry.interval.limit];
    NSArray *objects;
    do {
        objects = [enumerator nextObject];
        objects = [objects objectsOfClasses:@[ [VT100ScreenMark class] ]];
        for (VT100ScreenMark *nextMark in objects) {
            if (nextMark.isPrompt) {
                VT100GridCoordRange range;
                range.start = [self coordRangeForInterval:mark.entry.interval].end;
                range.start.x = 0;
                range.start.y++;
                range.end = [self coordRangeForInterval:nextMark.entry.interval].start;
                return range;
            }
        }
    } while (objects && !objects.count);

    // Command must still be running with no subsequent prompt.
    VT100GridCoordRange range;
    range.start = [self coordRangeForInterval:mark.entry.interval].end;
    range.start.x = 0;
    range.start.y++;
    range.end.x = 0;
    range.end.y = self.numberOfLines - self.height + [currentGrid_ numberOfLinesUsed];
    return range;
}

- (BOOL)setUseSavedGridIfAvailable:(BOOL)useSavedGrid {
    if (useSavedGrid && !realCurrentGrid_ && self.temporaryDoubleBuffer.savedGrid) {
        realCurrentGrid_ = [currentGrid_ retain];
        [currentGrid_ release];
        currentGrid_ = [self.temporaryDoubleBuffer.savedGrid retain];
        self.temporaryDoubleBuffer.drewSavedGrid = YES;
        return YES;
    } else if (!useSavedGrid && realCurrentGrid_) {
        [currentGrid_ release];
        currentGrid_ = [realCurrentGrid_ retain];
        [realCurrentGrid_ release];
        realCurrentGrid_ = nil;
    }
    return NO;
}

- (iTermStringLine *)stringLineAsStringAtAbsoluteLineNumber:(long long)absoluteLineNumber
                                                   startPtr:(long long *)startAbsLineNumber {
    long long lineNumber = absoluteLineNumber - self.totalScrollbackOverflow;
    if (lineNumber < 0) {
        return nil;
    }
    if (lineNumber >= self.numberOfLines) {
        return nil;
    }
    // Search backward for start of line
    int i;
    NSMutableData *data = [NSMutableData data];
    *startAbsLineNumber = self.totalScrollbackOverflow;

    // Max radius of lines to search above and below absoluteLineNumber
    const int kMaxRadius = [iTermAdvancedSettingsModel triggerRadius];
    BOOL foundStart = NO;
    for (i = lineNumber - 1; i >= 0 && i >= lineNumber - kMaxRadius; i--) {
        screen_char_t *line = [self getLineAtIndex:i];
        if (line[self.width].code == EOL_HARD) {
            *startAbsLineNumber = i + self.totalScrollbackOverflow + 1;
            foundStart = YES;
            break;
        }
        [data replaceBytesInRange:NSMakeRange(0, 0)
                        withBytes:line
                           length:self.width * sizeof(screen_char_t)];
    }
    if (!foundStart) {
        *startAbsLineNumber = i + self.totalScrollbackOverflow + 1;
    }
    BOOL done = NO;
    for (i = lineNumber; !done && i < self.numberOfLines && i < lineNumber + kMaxRadius; i++) {
        screen_char_t *line = [self getLineAtIndex:i];
        int length = self.width;
        done = line[length].code == EOL_HARD;
        if (done) {
            // Remove trailing newlines
            while (length > 0 && line[length - 1].code == 0 && !line[length - 1].complexChar) {
                --length;
            }
        }
        [data appendBytes:line length:length * sizeof(screen_char_t)];
    }

    return [[[iTermStringLine alloc] initWithScreenChars:data.mutableBytes
                                                  length:data.length / sizeof(screen_char_t)] autorelease];
}

#pragma mark - VT100TerminalDelegate

- (void)terminalAppendString:(NSString *)string {
    if (collectInputForPrinting_) {
        [printBuffer_ appendString:string];
    } else {
        // else display string on screen
        [self appendStringAtCursor:string];
    }
    [delegate_ screenDidAppendStringToCurrentLine:string];
}

- (void)terminalAppendAsciiData:(AsciiData *)asciiData {
    if (collectInputForPrinting_) {
        NSString *string = [[[NSString alloc] initWithBytes:asciiData->buffer
                                                     length:asciiData->length
                                                   encoding:NSASCIIStringEncoding] autorelease];
        [self terminalAppendString:string];
        return;
    } else {
        // else display string on screen
        [self appendAsciiDataAtCursor:asciiData];
    }
    [delegate_ screenDidAppendAsciiDataToCurrentLine:asciiData];
}

- (void)terminalRingBell {
    [delegate_ screenDidAppendStringToCurrentLine:@"\a"];
    [self activateBell];
}

- (void)doBackspace {
    int leftMargin = currentGrid_.leftMargin;
    int rightMargin = currentGrid_.rightMargin;
    int cursorX = currentGrid_.cursorX;
    int cursorY = currentGrid_.cursorY;

    if (cursorX >= self.width && terminal_.reverseWraparoundMode && terminal_.wraparoundMode) {
        // Reverse-wrap when past the screen edge is a special case.
        currentGrid_.cursor = VT100GridCoordMake(rightMargin, cursorY);
    } else if ([self shouldReverseWrap]) {
        currentGrid_.cursor = VT100GridCoordMake(rightMargin, cursorY - 1);
    } else if (cursorX > leftMargin ||  // Cursor can move back without hitting the left margin: normal case
               (cursorX < leftMargin && cursorX > 0)) {  // Cursor left of left margin, right of left edge.
        if (cursorX >= currentGrid_.size.width) {
            // Cursor right of right edge, move back twice.
            currentGrid_.cursorX = cursorX - 2;
        } else {
            // Normal case.
            currentGrid_.cursorX = cursorX - 1;
        }
    }

    // It is OK to land on the right half of a double-width character (issue 3475).
}

// Reverse wrap is allowed when the cursor is on the left margin or left edge, wraparoundMode is
// set, the cursor is not at the top margin/edge, and:
// 1. reverseWraparoundMode is set (xterm's rule), or
// 2. there's no left-right margin and the preceding line has EOL_SOFT (Terminal.app's rule)
- (BOOL)shouldReverseWrap {
    if (!terminal_.wraparoundMode) {
        return NO;
    }

    // Cursor must be at left margin/edge.
    int leftMargin = currentGrid_.leftMargin;
    int cursorX = currentGrid_.cursorX;
    if (cursorX != leftMargin && cursorX != 0) {
        return NO;
    }

    // Cursor must not be at top margin/edge.
    int topMargin = currentGrid_.topMargin;
    int cursorY = currentGrid_.cursorY;
    if (cursorY == topMargin || cursorY == 0) {
        return NO;
    }

    // If reverseWraparoundMode is reset, then allow only if there's a soft newline on previous line
    if (!terminal_.reverseWraparoundMode) {
        if (currentGrid_.useScrollRegionCols) {
            return NO;
        }

        screen_char_t *line = [self getLineAtScreenIndex:cursorY - 1];
        unichar c = line[self.width].code;
        return (c == EOL_SOFT || c == EOL_DWC);
    }

    return YES;
}

- (void)terminalBackspace {
    int cursorX = currentGrid_.cursorX;
    int cursorY = currentGrid_.cursorY;

    [self doBackspace];

    if (commandStartX_ != -1 && (currentGrid_.cursorX != cursorX ||
                                 currentGrid_.cursorY != cursorY)) {
        [delegate_ screenCommandDidChangeWithRange:[self commandRange]];
    }
}

- (int)tabStopAfterColumn:(int)lowerBound {
    for (int i = lowerBound + 1; i < self.width - 1; i++) {
        if ([tabStops_ containsObject:@(i)]) {
            return i;
        }
    }
    return self.width - 1;
}

- (void)terminalAppendTabAtCursor {
    int rightMargin;
    if (currentGrid_.useScrollRegionCols) {
        rightMargin = currentGrid_.rightMargin;
        if (currentGrid_.cursorX > rightMargin) {
            rightMargin = self.width - 1;
        }
    } else {
        rightMargin = self.width - 1;
    }

    if (terminal_.moreFix && self.cursorX > self.width && terminal_.wraparoundMode) {
        [self terminalLineFeed];
        [self terminalCarriageReturn];
    }

    int nextTabStop = MIN(rightMargin, [self tabStopAfterColumn:currentGrid_.cursorX]);
    if (nextTabStop <= currentGrid_.cursorX) {
        // This would only happen if the cursor were at or past the right margin.
        return;
    }
    screen_char_t* aLine = [currentGrid_ screenCharsAtLineNumber:currentGrid_.cursorY];
    BOOL allNulls = YES;
    for (int i = currentGrid_.cursorX; i < nextTabStop; i++) {
        if (aLine[i].code) {
            allNulls = NO;
            break;
        }
    }
    if (allNulls) {
        int i;
        for (i = currentGrid_.cursorX; i < nextTabStop - 1; i++) {
            aLine[i].code = TAB_FILLER;
        }
        aLine[i].code = '\t';
    }
    currentGrid_.cursorX = nextTabStop;
}

- (BOOL)cursorOutsideLeftRightMargin {
    return (currentGrid_.useScrollRegionCols && (currentGrid_.cursorX < currentGrid_.leftMargin ||
                                                 currentGrid_.cursorX > currentGrid_.rightMargin));
}

- (void)terminalLineFeed {
    if (currentGrid_.cursor.y == VT100GridRangeMax(currentGrid_.scrollRegionRows) &&
        [self cursorOutsideLeftRightMargin]) {
        DLog(@"Ignore linefeed/formfeed/index because cursor outside left-right margin.");
        return;
    }

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

- (void)terminalCursorDown:(int)n andToStartOfLine:(BOOL)toStart {
    [currentGrid_ moveCursorDown:n];
    if (toStart) {
        [currentGrid_ moveCursorToLeftMargin];
    }
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalCursorRight:(int)n
{
    [currentGrid_ moveCursorRight:n];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalCursorUp:(int)n andToStartOfLine:(BOOL)toStart{
    [currentGrid_ moveCursorUp:n];
    if (toStart) {
        [currentGrid_ moveCursorToLeftMargin];
    }
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
        bottom > top) {
        currentGrid_.scrollRegionRows = VT100GridRangeMake(top, bottom - top + 1);

        if ([terminal_ originMode]) {
            currentGrid_.cursor = VT100GridCoordMake(currentGrid_.leftMargin,
                                                     currentGrid_.topMargin);
        } else {
           currentGrid_.cursor = VT100GridCoordMake(0, 0);
        }
    }
}

- (void)scrollScreenIntoHistory {
    // Scroll the top lines of the screen into history, up to and including the last non-
    // empty line.
    LineBuffer *lineBuffer;
    if (currentGrid_ == altGrid_ && !self.saveToScrollbackInAlternateScreen) {
        lineBuffer = nil;
    } else {
        lineBuffer = linebuffer_;
    }
    const int n = [currentGrid_ numberOfNonEmptyLines];
    for (int i = 0; i < n; i++) {
        [self incrementOverflowBy:
            [currentGrid_ scrollWholeScreenUpIntoLineBuffer:lineBuffer
                                        unlimitedScrollback:unlimitedScrollback_]];
    }
}

- (void)terminalEraseInDisplayBeforeCursor:(BOOL)before afterCursor:(BOOL)after
{
    int x1, yStart, x2, y2;

    if (before && after) {
        [delegate_ screenRemoveSelection];
        [self scrollScreenIntoHistory];
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
        if (x1 == 0 && yStart == 0) {
            // Save the whole screen. This helps the "screen" terminal, where CSI H CSI J is used to
            // clear the screen.
            [delegate_ screenRemoveSelection];
            [self scrollScreenIntoHistory];
        }
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
    if (currentGrid_.useScrollRegionCols && currentGrid_.cursorX < currentGrid_.leftMargin) {
        currentGrid_.cursorX = 0;
    } else {
        [currentGrid_ moveCursorToLeftMargin];
    }
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalReverseIndex {
    if (currentGrid_.cursorY == currentGrid_.topMargin) {
        if ([self cursorOutsideLeftRightMargin]) {
            return;
        } else {
            [currentGrid_ scrollDown];
        }
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

    [self setInitialTabStops];

    for (int i = 0; i < NUM_CHARSETS; i++) {
        charsetUsesLineDrawingMode_[i] = NO;
    }
    [delegate_ screenDidReset];
    commandStartX_ = commandStartY_ = -1;
    [self showCursor:YES];
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
    charsetUsesLineDrawingMode_[charset] = lineDrawingMode;
}

- (BOOL)terminalLineDrawingFlagForCharset:(int)charset {
    return charsetUsesLineDrawingMode_[charset];
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
    if ([delegate_ screenAllowTitleSetting]) {
        NSString *newTitle = [[title copy] autorelease];
        if ([delegate_ screenShouldSyncTitle]) {
            newTitle = [NSString stringWithFormat:@"%@: %@", [delegate_ screenNameExcludingJob], newTitle];
        }
        [delegate_ screenSetWindowTitle:newTitle];
    }

    // If you know to use RemoteHost then assume you also use CurrentDirectory. Innocent window title
    // changes shouldn't override CurrentDirectory.
    if (![self remoteHostOnLine:[self numberOfScrollbackLines] + self.height]) {
        DLog(@"Don't have a remote host, so changing working directory");
        // TODO: There's a bug here where remote host can scroll off the end of history, causing the
        // working directory to come from PTYTask (which is what happens when nil is passed here).
        [self setWorkingDirectory:nil onLine:[self lineNumberOfCursor]];
    } else {
        DLog(@"Already have a remote host so not updating working directory because of title change");
    }
}

- (void)terminalSetIconTitle:(NSString *)title {
    if ([delegate_ screenAllowTitleSetting]) {
        NSString *newTitle = [[title copy] autorelease];
        if ([delegate_ screenShouldSyncTitle]) {
            newTitle = [NSString stringWithFormat:@"%@: %@", [delegate_ screenNameExcludingJob], newTitle];
        }
        [delegate_ screenSetName:newTitle];
    }
}

- (void)terminalPasteString:(NSString *)string {
    // check the configuration
    if (![iTermPreferences boolForKey:kPreferenceKeyAllowClipboardAccessFromTerminal]) {
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
                          downBy:n
                       softBreak:NO];
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
                          downBy:-n
                       softBreak:NO];
        [delegate_ screenTriggerableChangeDidOccur];
    }
}

- (void)terminalSetRows:(int)rows andColumns:(int)columns {
    if (rows == -1) {
        rows = self.height;
    } else if (rows == 0) {
        rows = [self terminalScreenHeightInCells];
    }
    if (columns == -1) {
        columns = self.width;
    } else if (columns == 0) {
        columns = [self terminalScreenWidthInCells];
    }
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
    [delegate_ screenRemoveSelection];
    for (int i = 0;
         i < MIN(currentGrid_.size.height, n);
         i++) {
        [self incrementOverflowBy:[currentGrid_ scrollUpIntoLineBuffer:linebuffer_
                                                   unlimitedScrollback:unlimitedScrollback_
                                               useScrollbackWithRegion:_appendToScrollbackWithStatusBar
                                                             softBreak:NO]];
    }
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalScrollDown:(int)n {
    [delegate_ screenRemoveSelection];
    [currentGrid_ scrollRect:[currentGrid_ scrollRegionRect]
                      downBy:MIN(currentGrid_.size.height, n)
                   softBreak:NO];
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
    if (allowTitleReporting_ && [self terminalIsTrusted]) {
        // TODO: Should be something like screenRawName (which doesn't exist yet but would return
        // [self rawName]), not screenWindowTitle, right?
        return [delegate_ screenWindowTitle] ? [delegate_ screenWindowTitle] : [delegate_ screenDefaultName];
    } else {
        return @"";
    }
}

- (NSString *)terminalWindowTitle {
    if (allowTitleReporting_ && [self terminalIsTrusted]) {
        return [delegate_ screenWindowTitle] ? [delegate_ screenWindowTitle] : @"";
    } else {
        return @"";
    }
}

- (void)terminalPushCurrentTitleForWindow:(BOOL)isWindow {
    if ([delegate_ screenAllowTitleSetting]) {
        [delegate_ screenPushCurrentTitleForWindow:isWindow];
    }
}

- (void)terminalPopCurrentTitleForWindow:(BOOL)isWindow {
    if ([delegate_ screenAllowTitleSetting]) {
        [delegate_ screenPopCurrentTitleForWindow:isWindow];
    }
}

- (BOOL)terminalPostGrowlNotification:(NSString *)message {
    if (postGrowlNotifications_ && [delegate_ screenShouldPostTerminalGeneratedAlert]) {
        [delegate_ screenIncrementBadge];
        NSString *description = [NSString stringWithFormat:@"Session %@ #%d: %@",
                                    [delegate_ screenName],
                                    [delegate_ screenNumber],
                                    message];
        BOOL sent = [[iTermGrowlDelegate sharedInstance]
                        growlNotify:@"Alert"
                        withDescription:description
                        andNotification:@"Customized Message"
                            windowIndex:[delegate_ screenWindowIndex]
                               tabIndex:[delegate_ screenTabIndex]
                              viewIndex:[delegate_ screenViewIndex]];
        return sent;
    } else {
        return NO;
    }
}

- (void)terminalStartTmuxMode {
    [delegate_ screenStartTmuxMode];
}

- (void)terminalHandleTmuxInput:(VT100Token *)token {
    [delegate_ screenHandleTmuxInput:token];
}

- (BOOL)terminalInTmuxMode {
    return [delegate_ screenInTmuxMode];
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

// Swap onscreen notes between intervalTree_ and savedIntervalTree_.
// IMPORTANT: Call -reloadMarkCache after this.
- (void)swapNotes
{
    int historyLines = [self numberOfScrollbackLines];
    Interval *origin = [self intervalForGridCoordRange:VT100GridCoordRangeMake(0,
                                                                               historyLines,
                                                                               1,
                                                                               historyLines)];
    IntervalTree *temp = [[IntervalTree alloc] init];
    DLog(@"swapNotes: moving onscreen notes into savedNotes");
    [self moveNotesOnScreenFrom:intervalTree_
                             to:temp
                         offset:-origin.location
                   screenOrigin:[self numberOfScrollbackLines]];
    DLog(@"swapNotes: moving onscreen savedNotes into notes");
    [self moveNotesOnScreenFrom:savedIntervalTree_
                             to:intervalTree_
                         offset:origin.location
                   screenOrigin:0];
    [savedIntervalTree_ release];
    savedIntervalTree_ = temp;
}

- (void)terminalShowAltBuffer {
    if (currentGrid_ == altGrid_) {
        return;
    }
    [delegate_ screenRemoveSelection];
    if (!altGrid_) {
        altGrid_ = [[VT100Grid alloc] initWithSize:primaryGrid_.size delegate:self];
    }

    [self.temporaryDoubleBuffer reset];
    primaryGrid_.savedDefaultChar = [primaryGrid_ defaultChar];
    [self hideOnScreenNotesAndTruncateSpanners];
    currentGrid_ = altGrid_;
    currentGrid_.cursor = primaryGrid_.cursor;

    [self swapNotes];
    [self reloadMarkCache];

    [currentGrid_ markAllCharsDirty:YES];
    [delegate_ screenScheduleRedrawSoon];
    commandStartX_ = commandStartY_ = -1;
}

- (BOOL)terminalIsShowingAltBuffer {
    return [self showingAlternateScreen];
}

- (BOOL)showingAlternateScreen {
    return currentGrid_ == altGrid_;
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
    for (id<IntervalTreeObject> note in [intervalTree_ objectsInInterval:screenInterval]) {
        if (note.entry.interval.location < screenInterval.location) {
            // Truncate note so that it ends just before screen.
            note.entry.interval.length = screenInterval.location - note.entry.interval.location;
        }
        if ([note isKindOfClass:[PTYNoteViewController class]]) {
            [(PTYNoteViewController *)note setNoteHidden:YES];
        }
    }
}
- (void)terminalShowPrimaryBuffer {
    if (currentGrid_ == altGrid_) {
        [self.temporaryDoubleBuffer reset];
        [delegate_ screenRemoveSelection];
        [self hideOnScreenNotesAndTruncateSpanners];
        currentGrid_ = primaryGrid_;
        commandStartX_ = commandStartY_ = -1;
        [self swapNotes];
        [self reloadMarkCache];

        [currentGrid_ markAllCharsDirty:YES];
        [delegate_ screenScheduleRedrawSoon];
    }
}

- (void)terminalSetRemoteHost:(NSString *)remoteHost {
    NSRange atRange = [remoteHost rangeOfString:@"@"];
    VT100RemoteHost *currentHost = [self remoteHostOnLine:[self numberOfLines]];
    NSString *user = nil;
    NSString *host = nil;
    if (atRange.length == 1) {
        user = [remoteHost substringToIndex:atRange.location];
        host = [remoteHost substringFromIndex:atRange.location + 1];
        if (host.length == 0) {
            host = nil;
        }
    } else {
        host = remoteHost;
    }

    if (!host || !user) {
        // A trigger can set the host and user alone. If remoteHost looks like example.com or
        // user@, then preserve the previous host/user. Also ensure neither value is nil; the
        // empty string will stand in for a real value if necessary.
        VT100RemoteHost *lastRemoteHost = [self lastRemoteHost];
        if (!host) {
            host = [[lastRemoteHost.hostname copy] autorelease] ?: @"";
        }
        if (!user) {
            user = [[lastRemoteHost.username copy] autorelease] ?: @"";
        }
    }

    int cursorLine = [self numberOfLines] - [self height] + currentGrid_.cursorY;
    VT100RemoteHost *remoteHostObj = [self setRemoteHost:host user:user onLine:cursorLine];

    if (![remoteHostObj isEqualToRemoteHost:currentHost]) {
        [delegate_ screenCurrentHostDidChange:remoteHostObj];
    }
}

- (void)terminalClearScreen {
    // Unconditionally clear the whole screen, regardless of cursor position.
    // This behavior changed in the Great VT100Grid Refactoring of 2013. Before, clearScreen
    // used to move the cursor's wrapped line to the top of the screen. It's only used from
    // DECSET 1049, and neither xterm nor terminal have this behavior, and I'm not sure why it
    // would be desirable anyway. Like xterm (and unlike Terminal) we leave the cursor put.
    [delegate_ screenRemoveSelection];
    [currentGrid_ setCharsFrom:VT100GridCoordMake(0, 0)
                            to:VT100GridCoordMake(currentGrid_.size.width - 1,
                                                  currentGrid_.size.height - 1)
                        toChar:[currentGrid_ defaultChar]];
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

- (void)terminalClearScrollbackBuffer {
    [self clearScrollbackBuffer];
}

- (void)terminalClearBuffer {
    [self clearBuffer];
}

- (void)terminalCurrentDirectoryDidChangeTo:(NSString *)value {
    int cursorLine = [self numberOfLines] - [self height] + currentGrid_.cursorY;
    NSString *dir = value;
    if (!dir.length) {
        dir = [delegate_ screenCurrentWorkingDirectory];
    }
    if (dir.length) {
        BOOL willChange = ![dir isEqualToString:[self workingDirectoryOnLine:cursorLine]];
        [self setWorkingDirectory:dir onLine:cursorLine];
        if (willChange) {
            [delegate_ screenCurrentDirectoryDidChangeTo:dir];
        }
    }
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
        message = parts[0];
        length = [parts[1] intValue];
        location.x = MIN(MAX(0, [parts[2] intValue]), location.x);
        location.y = MIN(MAX(0, [parts[3] intValue]), location.y);
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

- (void)terminalWillReceiveFileNamed:(NSString *)name ofSize:(int)size {
    [delegate_ screenWillReceiveFileNamed:name ofSize:size];
}

- (void)terminalWillReceiveInlineFileNamed:(NSString *)name
                                    ofSize:(int)size
                                     width:(int)width
                                     units:(VT100TerminalUnits)widthUnits
                                    height:(int)height
                                     units:(VT100TerminalUnits)heightUnits
                       preserveAspectRatio:(BOOL)preserveAspectRatio
                                     inset:(NSEdgeInsets)inset {
    [inlineFileInfo_ release];
    inlineFileInfo_ = [@{ kInlineFileName: name,
                          kInlineFileWidth: @(width),
                          kInlineFileWidthUnits: @(widthUnits),
                          kInlineFileHeight: @(height),
                          kInlineFileHeightUnits: @(heightUnits),
                          kInlineFilePreserveAspectRatio: @(preserveAspectRatio),
                          kInlineFileBase64String: [NSMutableString string],
                          kInilineFileInset: [NSValue futureValueWithEdgeInsets:inset] } retain];
}

- (void)appendImageAtCursorWithName:(NSString *)name
                              width:(int)width
                              units:(VT100TerminalUnits)widthUnits
                             height:(int)height
                              units:(VT100TerminalUnits)heightUnits
                preserveAspectRatio:(BOOL)preserveAspectRatio
                              inset:(NSEdgeInsets)inset
                              image:(NSImage *)image
                               data:(NSData *)data {
    if (!image) {
        image = [NSImage imageNamed:@"broken_image"];
    }

    BOOL needsWidth = NO;
    NSSize cellSize = [delegate_ screenCellSize];
    switch (widthUnits) {
        case kVT100TerminalUnitsPixels:
            width = ceil((double)width / cellSize.width);
            break;

        case kVT100TerminalUnitsPercentage:
            width = ceil((double)[self width] * (double)MAX(MIN(100, width), 0) / 100.0);
            break;

        case kVT100TerminalUnitsCells:
            break;

        case kVT100TerminalUnitsAuto:
            if (heightUnits == kVT100TerminalUnitsAuto) {
                width = ceil((double)image.size.width / cellSize.width);
            } else {
                needsWidth = YES;
            }
            break;
    }
    switch (heightUnits) {
        case kVT100TerminalUnitsPixels:
            height = ceil((double)height / cellSize.height);
            break;

        case kVT100TerminalUnitsPercentage:
            height = ceil((double)[self height] * (double)MAX(MIN(100, height), 0) / 100.0);
            break;

        case kVT100TerminalUnitsCells:
            break;

        case kVT100TerminalUnitsAuto:
            if (widthUnits == kVT100TerminalUnitsAuto) {
                height = ceil((double)image.size.height / cellSize.height);
            } else {
                double aspectRatio = image.size.width / image.size.height;
                height = ((double)(width * cellSize.width) / aspectRatio) / cellSize.height;
            }
            break;
    }

    if (needsWidth) {
        double aspectRatio = image.size.width / image.size.height;
        width = ((double)(height * cellSize.height) * aspectRatio) / cellSize.width;
    }

    width = MAX(1, width);
    height = MAX(1, height);

    double maxWidth = self.width - currentGrid_.cursorX;
    // If the requested size is too large, scale it down to fit.
    if (width > maxWidth) {
        double scale = maxWidth / (double)width;
        width = self.width;
        height *= scale;
    }

    // Height is capped at 255 because only 8 bits are used to represent the line number of a cell
    // within the image.
    double maxHeight = 255;
    if (height > maxHeight) {
        double scale = (double)height / maxHeight;
        height = maxHeight;
        width *= scale;
    }

    // Allocate cells for the image.
    // TODO: Support scroll regions.
    int xOffset = self.cursorX - 1;
    int screenWidth = currentGrid_.size.width;
    NSEdgeInsets fractionalInset = {
        .left = MAX(inset.left / cellSize.width, 0),
        .top = MAX(inset.top / cellSize.height, 0),
        .right = MAX(inset.right / cellSize.width, 0),
        .bottom = MAX(inset.bottom / cellSize.height, 0)
    };
    screen_char_t c = ImageCharForNewImage(name,
                                           width,
                                           height,
                                           preserveAspectRatio,
                                           fractionalInset);
    for (int y = 0; y < height; y++) {
        if (y > 0) {
            [self linefeed];
        }
        for (int x = xOffset; x < xOffset + width && x < screenWidth; x++) {
            SetPositionInImageChar(&c, x - xOffset, y);
            [currentGrid_ setCharsFrom:VT100GridCoordMake(x, currentGrid_.cursorY)
                                    to:VT100GridCoordMake(x, currentGrid_.cursorY)
                                toChar:c];
        }
    }
    currentGrid_.cursorX = currentGrid_.cursorX + width + 1;

    // Add a mark after the image. When the mark gets freed, it will release the image's memory.
    SetDecodedImage(c.code, image, data);
    long long absLine = (self.totalScrollbackOverflow +
                         [self numberOfScrollbackLines] +
                         currentGrid_.cursor.y + 1);
    iTermImageMark *mark = [self addMarkStartingAtAbsoluteLine:absLine
                                                       oneLine:YES
                                                       ofClass:[iTermImageMark class]];
    mark.imageCode = @(c.code);
    [delegate_ screenNeedsRedraw];
}

- (void)terminalDidFinishReceivingFile {
    if (inlineFileInfo_) {
        // TODO: Handle objects other than images.
        NSData *data = [NSData dataWithBase64EncodedString:inlineFileInfo_[kInlineFileBase64String]];
        NSImage *image = [[[NSImage alloc] initWithData:data] autorelease];
        [self appendImageAtCursorWithName:inlineFileInfo_[kInlineFileName]
                                    width:[inlineFileInfo_[kInlineFileWidth] intValue]
                                    units:(VT100TerminalUnits)[inlineFileInfo_[kInlineFileWidthUnits] intValue]
                                   height:[inlineFileInfo_[kInlineFileHeight] intValue]
                                    units:(VT100TerminalUnits)[inlineFileInfo_[kInlineFileHeightUnits] intValue]
                      preserveAspectRatio:[inlineFileInfo_[kInlineFilePreserveAspectRatio] boolValue]
                                    inset:[inlineFileInfo_[kInilineFileInset] futureEdgeInsetsValue]
                                    image:image
                                     data:data];
        [inlineFileInfo_ release];
        inlineFileInfo_ = nil;
    } else {
        [delegate_ screenDidFinishReceivingFile];
    }
}

- (void)terminalDidReceiveBase64FileData:(NSString *)data {
    if (inlineFileInfo_) {
        [inlineFileInfo_[kInlineFileBase64String] appendString:data];
    } else {
        [delegate_ screenDidReceiveBase64FileData:data];
    }
}

- (void)terminalFileReceiptEndedUnexpectedly {
    [delegate_ screenFileReceiptEndedUnexpectedly];
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

- (BOOL)terminalIsTrusted {
    return ![iTermAdvancedSettingsModel disablePotentiallyInsecureEscapeSequences];
}

- (void)terminalRequestAttention:(BOOL)request {
    [delegate_ screenRequestAttention:request isCritical:YES];
}

- (void)terminalSetBackgroundImageFile:(NSString *)filename {
    [delegate_ screenSetBackgroundImageFile:filename];
}

- (void)terminalSetBadgeFormat:(NSString *)badge {
    [delegate_ screenSetBadgeFormat:badge];
}

- (void)terminalSetUserVar:(NSString *)kvp {
    [delegate_ screenSetUserVar:kvp];
}

- (void)terminalSetForegroundColor:(NSColor *)color {
    [delegate_ screenSetColor:color forKey:kColorMapForeground];
}

- (void)terminalSetBackgroundColor:(NSColor *)color {
    [delegate_ screenSetColor:color forKey:kColorMapBackground];
}

- (void)terminalSetBoldColor:(NSColor *)color {
    [delegate_ screenSetColor:color forKey:kColorMapBold];
}

- (void)terminalSetSelectionColor:(NSColor *)color {
    [delegate_ screenSetColor:color forKey:kColorMapSelection];
}

- (void)terminalSetSelectedTextColor:(NSColor *)color {
    [delegate_ screenSetColor:color forKey:kColorMapSelectedText];
}

- (void)terminalSetCursorColor:(NSColor *)color {
    [delegate_ screenSetColor:color forKey:kColorMapCursor];
}

- (void)terminalSetCursorTextColor:(NSColor *)color {
    [delegate_ screenSetColor:color forKey:kColorMapCursorText];
}

- (void)terminalSetColorTableEntryAtIndex:(int)n color:(NSColor *)color {
    [delegate_ screenSetColor:color forKey:kColorMap8bitBase + n];
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

- (BOOL)terminalFocusReportingEnabled {
    return [iTermAdvancedSettingsModel focusReportingEnabled];
}

- (NSColor *)terminalColorForIndex:(int)index {
    if (index < 0 || index > 255) {
        return nil;
    }
    return [[delegate_ screenColorMap] colorForKey:kColorMap8bitBase + index];
}

- (int)terminalCursorX {
    return MIN([self cursorX], [self width]);
}

- (int)terminalCursorY {
    return [self cursorY];
}

- (void)terminalSetCursorVisible:(BOOL)visible {
    if (visible != _cursorVisible) {
        _cursorVisible = visible;
        if (visible) {
            [self.temporaryDoubleBuffer reset];
        } else {
            [self.temporaryDoubleBuffer start];
        }
    }
    [delegate_ screenSetCursorVisible:visible];
}

- (void)terminalSetHighlightCursorLine:(BOOL)highlight {
    [delegate_ screenSetHighlightCursorLine:highlight];
}

- (void)terminalPromptDidStart {
    DLog(@"FinalTerm: terminalPromptDidStart");
    if (self.cursorX > 1 && [delegate_ screenShouldPlacePromptAtFirstColumn]) {
        [self crlf];
    }
    _shellIntegrationInstalled = YES;

    _lastCommandOutputRange.end.x = currentGrid_.cursor.x;
    _lastCommandOutputRange.end.y =
        currentGrid_.cursor.y + [self numberOfScrollbackLines] + [self totalScrollbackOverflow];
    _lastCommandOutputRange.start = nextCommandOutputStart_;

    // FinalTerm uses this to define the start of a collapsable region. That would be a nightmare
    // to add to iTerm, and our answer to this is marks, which already existed anyway.
    [delegate_ screenPromptDidStartAtLine:[self numberOfScrollbackLines] + self.cursorY - 1];
}

- (void)terminalCommandDidStart {
    DLog(@"FinalTerm: terminalCommandDidStart");
    commandStartX_ = currentGrid_.cursorX;
    commandStartY_ = currentGrid_.cursorY + [self numberOfScrollbackLines] + [self totalScrollbackOverflow];
    [delegate_ screenCommandDidChangeWithRange:[self commandRange]];
}

- (void)terminalCommandDidEnd {
    DLog(@"FinalTerm: terminalCommandDidEnd");
    if (commandStartX_ != -1) {
        [delegate_ screenCommandDidEndWithRange:[self commandRange]];
        commandStartX_ = commandStartY_ = -1;
        [delegate_ screenCommandDidChangeWithRange:[self commandRange]];
        nextCommandOutputStart_.x = currentGrid_.cursor.x;
        nextCommandOutputStart_.y =
            currentGrid_.cursor.y + [self numberOfScrollbackLines] + [self totalScrollbackOverflow];
    }
}

- (void)terminalAbortCommand {
    DLog(@"FinalTerm: terminalAbortCommand");
    VT100ScreenMark *screenMark = [self lastCommandMark];
    if (screenMark) {
        DLog(@"Removing last command mark %@", screenMark);
        [intervalTree_ removeObject:screenMark];
    }

    commandStartX_ = commandStartY_ = -1;
    [delegate_ screenCommandDidEndWithRange:VT100GridCoordRangeMake(-1, -1, -1, -1)];
}

- (void)terminalSemanticTextDidStartOfType:(VT100TerminalSemanticTextType)type {
    // TODO
}

- (void)terminalSemanticTextDidEndOfType:(VT100TerminalSemanticTextType)type {
    // TODO
}

- (void)terminalProgressAt:(double)fraction label:(NSString *)label {
     // TODO
}

- (void)terminalProgressDidFinish {
    // TODO
}

- (VT100ScreenMark *)lastCommandMark {
    DLog(@"Searching for last command mark...");
    if (_lastCommandMark) {
        DLog(@"Return cached mark %@", _lastCommandMark);
        return _lastCommandMark;
    }
    NSEnumerator *enumerator = [intervalTree_ reverseLimitEnumerator];
    NSArray *objects = [enumerator nextObject];
    int numChecked = 0;
    while (objects && numChecked < 500) {
        for (id<IntervalTreeObject> obj in objects) {
            if ([obj isKindOfClass:[VT100ScreenMark class]]) {
                VT100ScreenMark *mark = (VT100ScreenMark *)obj;
                if (mark.command) {
                    DLog(@"Found mark %@ in line number range %@", mark,
                         VT100GridRangeDescription([self lineNumberRangeOfInterval:obj.entry.interval]));
                    self.lastCommandMark = mark;
                    return mark;
                }
            }
            ++numChecked;
        }
        objects = [enumerator nextObject];
    }

    DLog(@"No last command mark found");
    return nil;
}

- (void)terminalReturnCodeOfLastCommandWas:(int)returnCode {
    DLog(@"FinalTerm: terminalReturnCodeOfLastCommandWas:%d", returnCode);
    VT100ScreenMark *mark = self.lastCommandMark;
    if (mark) {
        DLog(@"FinalTerm: setting code on mark %@", mark);
        mark.code = returnCode;
        VT100RemoteHost *remoteHost = [self remoteHostOnLine:[self numberOfLines]];
        [[iTermShellHistoryController sharedInstance] setStatusOfCommandAtMark:mark
                                                                        onHost:remoteHost
                                                                            to:returnCode];
        [delegate_ screenNeedsRedraw];
    } else {
        DLog(@"No last command mark found.");
    }
}

- (void)terminalFinalTermCommand:(NSArray *)argv {
    // TODO
    // Currently, FinalTerm supports these commands:
  /*
   QUIT_PROGRAM,
   SEND_TO_SHELL,
   CLEAR_SHELL_COMMAND,
   SET_SHELL_COMMAND,
   RUN_SHELL_COMMAND,
   TOGGLE_VISIBLE,
   TOGGLE_FULLSCREEN,
   TOGGLE_DROPDOWN,
   ADD_TAB,
   SPLIT,
   CLOSE,
   LOG,
   PRINT_METRICS,
   COPY_TO_CLIPBOARD,
   OPEN_URL
   */
}

// version is formatted as
// <version number>;<key>=<value>;<key>=<value>...
// Older scripts may have only a version number and no key-value pairs.
// The only defined key is "shell", and the value will be tcsh, bash, zsh, or fish.
- (void)terminalSetShellIntegrationVersion:(NSString *)version {
    NSArray *parts = [version componentsSeparatedByString:@";"];
    NSString *shell = nil;
    NSInteger versionNumber = [parts[0] integerValue];
    if (parts.count >= 2) {
        NSMutableDictionary *params = [NSMutableDictionary dictionary];
        for (NSString *kvp in [parts subarrayWithRange:NSMakeRange(1, parts.count - 1)]) {
            NSRange equalsRange = [kvp rangeOfString:@"="];
            if (equalsRange.location == NSNotFound) {
                continue;
            }
            NSString *key = [kvp substringToIndex:equalsRange.location];
            NSString *value = [kvp substringFromIndex:NSMaxRange(equalsRange)];
            params[key] = value;
        }
        shell = params[@"shell"];
    }
    
    NSDictionary<NSString *, NSNumber *> *lastVersionByShell =
        @{ @"tcsh": @2,
           @"bash": @2,
           @"zsh": @2,
           @"fish": @2 };
    NSInteger latestKnownVersion = [lastVersionByShell[shell ?: @""] integerValue];
    if (!shell || versionNumber < latestKnownVersion) {
        [delegate_ screenSuggestShellIntegrationUpgrade];
    }
}

- (void)terminalWraparoundModeDidChangeTo:(BOOL)newValue {
    _wraparoundMode = newValue;
}

- (void)terminalTypeDidChange {
    _ansi = [terminal_ isAnsi];
}

- (void)terminalInsertModeDidChangeTo:(BOOL)newValue {
    _insert = newValue;
}

- (NSString *)terminalProfileName {
    return [delegate_ screenProfileName];
}

- (VT100GridRect)terminalScrollRegion {
    return currentGrid_.scrollRegionRect;
}

- (int)terminalChecksumInRectangle:(VT100GridRect)rect {
    int result = 0;
    for (int y = rect.origin.y; y < rect.origin.y + rect.size.height; y++) {
        screen_char_t *theLine = [self getLineAtScreenIndex:y];
        for (int x = rect.origin.x; x < rect.origin.x + rect.size.width; x++) {
            unichar code = theLine[x].code;
            BOOL isPrivate = (code < ITERM2_PRIVATE_BEGIN &&
                              code > ITERM2_PRIVATE_END);
            if (code && !isPrivate) {
                NSString *s = ScreenCharToStr(&theLine[x]);
                for (int i = 0; i < s.length; i++) {
                    result += (int)[s characterAtIndex:i];
                }
            }
        }
    }
    return result;
}

- (NSSize)terminalCellSizeInPoints {
    return [delegate_ screenCellSize];
}

#pragma mark - Private

- (VT100GridCoordRange)commandRange {
    long long offset = [self totalScrollbackOverflow];
    if (commandStartX_ < 0) {
        return VT100GridCoordRangeMake(-1, -1, -1, -1);
    } else {
        return VT100GridCoordRangeMake(commandStartX_,
                                       MAX(0, commandStartY_ - offset),
                                       currentGrid_.cursorX,
                                       currentGrid_.cursorY + [self numberOfScrollbackLines]);
    }
}

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

// Set the color of prototypechar to all chars between startPoint and endPoint on the screen.
- (void)highlightRun:(VT100GridRun)run
    withForegroundColor:(NSColor *)fgColor
        backgroundColor:(NSColor *)bgColor {
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
    if (start.x < 0 || end.x < 0 ||
        start.y < 0 || end.y < 0) {
        *startPtr = start;
        *endPtr = end;
        return;
    }

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

- (LineBufferPositionRange *)positionRangeForCoordRange:(VT100GridCoordRange)range
                                           inLineBuffer:(LineBuffer *)lineBuffer
                                          tolerateEmpty:(BOOL)tolerateEmpty {
    assert(range.end.y >= 0);
    assert(range.start.y >= 0);

    LineBufferPositionRange *positionRange = [[[LineBufferPositionRange alloc] init] autorelease];

    BOOL endExtends = NO;
    // Use the predecessor of endx,endy so it will have a legal position in the line buffer.
    if (range.end.x == [self width]) {
        screen_char_t *line = [self getLineAtIndex:range.end.y];
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
    [self trimSelectionFromStart:VT100GridCoordMake(range.start.x, range.start.y)
                             end:VT100GridCoordMake(range.end.x, range.end.y)
                        toStartX:&trimmedStart
                          toEndX:&trimmedEnd];
    if (VT100GridCoordOrder(trimmedStart, trimmedEnd) == NSOrderedDescending) {
        if (tolerateEmpty) {
            trimmedStart = trimmedEnd = range.start;
        } else {
            return nil;
        }
    }

    positionRange.start = [lineBuffer positionForCoordinate:trimmedStart
                                                      width:currentGrid_.size.width
                                                     offset:0];
    positionRange.end = [lineBuffer positionForCoordinate:trimmedEnd
                                                    width:currentGrid_.size.width
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
                                                      ok:NULL];
    BOOL ok = NO;
    VT100GridCoord newEnd = [lineBuffer coordinateForPosition:selectionRange.end
                                                        width:newWidth
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
        resultPtr->end.x = currentGrid_.size.width;
        resultPtr->end.y = [lineBuffer numLinesWithWidth:newWidth] + currentGrid_.size.height - 1;
    }
    if (selectionRange.end.extendsToEndOfLine) {
        resultPtr->end.x = newWidth;
    }
    return YES;
}

- (void)incrementOverflowBy:(int)overflowCount {
    scrollbackOverflow_ += overflowCount;
    cumulativeScrollbackOverflow_ += overflowCount;
}

// sets scrollback lines.
- (void)setMaxScrollbackLines:(unsigned int)lines {
    maxScrollbackLines_ = lines;
    [linebuffer_ setMaxLines: lines];
    if (!unlimitedScrollback_) {
        [self incrementOverflowBy:[linebuffer_ dropExcessLinesWithWidth:currentGrid_.size.width]];
    }
    [delegate_ screenDidChangeNumberOfScrollbackLines];
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

- (void)setUseColumnScrollRegion:(BOOL)mode
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
        BOOL isOk __attribute__((unused)) =
            [linebuffer_ popAndCopyLastLineInto:dummy
                                          width:currentGrid_.size.width
                              includesEndOfLine:&cont
                                      timestamp:NULL
                                   continuation:NULL];
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
                const int numResults = context.results.count;
                for (int k = 0; k < numResults; k++) {
                    SearchResult* result = [[SearchResult alloc] init];

                    XYRange* xyrange = [allPositions objectAtIndex:k];

                    result.startX = xyrange->xStart;
                    result.endX = xyrange->xEnd;
                    result.absStartY = xyrange->yStart + [self totalScrollbackOverflow];
                    result.absEndY = xyrange->yEnd + [self totalScrollbackOverflow];

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

    switch (context.status) {
        case Searching: {
            int numDropped = [linebuffer_ numberOfDroppedBlocks];
            double current = context.absBlockNum - numDropped;
            double max = [linebuffer_ largestAbsoluteBlockNumber] - numDropped;
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

    [self popScrollbackLines:linesPushed];
    return keepSearching;
}

#pragma mark - PTYNoteViewControllerDelegate

- (void)noteDidRequestRemoval:(PTYNoteViewController *)note {
    if ([intervalTree_ containsObject:note]) {
        self.lastCommandMark = nil;
        [intervalTree_ removeObject:note];
    } else if ([savedIntervalTree_ containsObject:note]) {
        self.lastCommandMark = nil;
        [savedIntervalTree_ removeObject:note];
    }
    [delegate_ screenNeedsRedraw];
    [delegate_ screenDidEndEditingNote];
}

- (void)noteDidEndEditing:(PTYNoteViewController *)note {
    [delegate_ screenDidEndEditingNote];
}

#pragma mark - VT100GridDelegate

- (screen_char_t)gridForegroundColorCode {
    return [terminal_ foregroundColorCodeReal];
}

- (screen_char_t)gridBackgroundColorCode {
    return [terminal_ backgroundColorCodeReal];
}

- (void)gridCursorDidChangeLine {
    if (_trackCursorLineMovement) {
        [delegate_ screenCursorDidMoveToLine:currentGrid_.cursorY + [self numberOfScrollbackLines]];
    }
}

- (BOOL)gridUseHFSPlusMapping {
    return _useHFSPlusMapping;
}

- (void)gridCursorDidMove {
}

#pragma mark - iTermMarkDelegate

- (void)markDidBecomeCommandMark:(id<iTermMark>)mark {
    if (mark.entry.interval.location > self.lastCommandMark.entry.interval.location) {
        self.lastCommandMark = mark;
    }
}

- (NSDictionary *)contentsDictionary {
    // We want 10k lines of history at 80 cols, and fewer for small widths, to keep the size
    // reasonable.
    int maxArea = 10000 * 80;
    int effectiveWidth = self.width ?: 80;
    int maxLines = MAX(1000, maxArea / effectiveWidth);

    // Make a copy of the last blocks of the line buffer; enough to contain at least |maxLines|.
    LineBuffer *temp = [linebuffer_ appendOnlyCopyWithMinimumLines:maxLines
                                                           atWidth:effectiveWidth];

    // Offset for intervals so 0 is the first char in the provided contents.
    int linesDroppedForBrevity = ([linebuffer_ numLinesWithWidth:effectiveWidth] -
                                  [temp numLinesWithWidth:effectiveWidth]);
    long long intervalOffset =
        -(linesDroppedForBrevity + [self totalScrollbackOverflow]) * (self.width + 1);

    int numLines;
    if ([iTermAdvancedSettingsModel runJobsInServers]) {
        numLines = currentGrid_.size.height;
    } else {
        numLines = [currentGrid_ numberOfLinesUsed];
    }
    [currentGrid_ appendLines:numLines toLineBuffer:temp];
    NSMutableDictionary *dict = [[[temp dictionary] mutableCopy] autorelease];
    static NSString *const kScreenStateTabStopsKey = @"Tab Stops";
    dict[kScreenStateKey] =
        @{ kScreenStateTabStopsKey: [tabStops_ allObjects] ?: @[],
           kScreenStateTerminalKey: [terminal_ stateDictionary] ?: @{},
           kScreenStateLineDrawingModeKey: @[ @(charsetUsesLineDrawingMode_[0]),
                                              @(charsetUsesLineDrawingMode_[1]),
                                              @(charsetUsesLineDrawingMode_[2]),
                                              @(charsetUsesLineDrawingMode_[3]) ],
           kScreenStateNonCurrentGridKey: [self contentsOfNonCurrentGrid] ?: @{},
           kScreenStateCurrentGridIsPrimaryKey: @(primaryGrid_ == currentGrid_),
           kScreenStateIntervalTreeKey: [intervalTree_ dictionaryValueWithOffset:intervalOffset] ?: @{},
           kScreenStateSavedIntervalTreeKey: [savedIntervalTree_ dictionaryValueWithOffset:0] ?: [NSNull null],
           kScreenStateCommandStartXKey: @(commandStartX_),
           kScreenStateCommandStartYKey: @(commandStartY_),
           kScreenStateNextCommandOutputStartKey: [NSDictionary dictionaryWithGridAbsCoord:nextCommandOutputStart_],
           kScreenStateCursorVisibleKey: @(_cursorVisible),
           kScreenStateTrackCursorLineMovementKey: @(_trackCursorLineMovement),
           kScreenStateLastCommandOutputRangeKey: [NSDictionary dictionaryWithGridAbsCoordRange:_lastCommandOutputRange],
           kScreenStateShellIntegrationInstalledKey: @(_shellIntegrationInstalled),
           kScreenStateLastCommandMarkKey: _lastCommandMark.guid ?: [NSNull null],
           kScreenStatePrimaryGridStateKey: primaryGrid_.dictionaryValue ?: @{},
           kScreenStateAlternateGridStateKey: primaryGrid_.dictionaryValue ?: [NSNull null],
           kScreenStateNumberOfLinesDroppedKey: @(linesDroppedForBrevity)
           };
    return [dict dictionaryByRemovingNullValues];
}

- (NSDictionary *)contentsOfNonCurrentGrid {
    LineBuffer *temp = [[[LineBuffer alloc] initWithBlockSize:4096] autorelease];
    VT100Grid *grid;
    if (currentGrid_ == primaryGrid_) {
        grid = altGrid_;
    } else {
        grid = primaryGrid_;
    }
    if (!grid) {
        return @{};
    }
    [grid appendLines:grid.size.height toLineBuffer:temp];
    return [temp dictionary];
}

- (void)restoreFromDictionary:(NSDictionary *)dictionary
     includeRestorationBanner:(BOOL)includeRestorationBanner
                knownTriggers:(NSArray *)triggers
                   reattached:(BOOL)reattached {
    if (!altGrid_) {
        altGrid_ = [primaryGrid_ copy];
    }
    NSDictionary *screenState = reattached ? dictionary[kScreenStateKey] : nil;
    if (screenState) {
        if ([screenState[kScreenStateCurrentGridIsPrimaryKey] boolValue]) {
            currentGrid_ = primaryGrid_;
        } else {
            currentGrid_ = altGrid_;
        }
    }

    LineBuffer *lineBuffer = [[LineBuffer alloc] initWithDictionary:dictionary];
    if (includeRestorationBanner) {
        [lineBuffer appendMessage:@"Session Restored"];
    }
    [lineBuffer setMaxLines:maxScrollbackLines_];
    if (!unlimitedScrollback_) {
        [lineBuffer dropExcessLinesWithWidth:self.width];
    }
    [linebuffer_ release];
    linebuffer_ = lineBuffer;
    int maxLinesToRestore;
    if ([iTermAdvancedSettingsModel runJobsInServers] && reattached) {
        maxLinesToRestore = currentGrid_.size.height;
    } else {
        maxLinesToRestore = currentGrid_.size.height - 1;
    }
    int linesRestored = MIN(MAX(0, maxLinesToRestore),
                            [lineBuffer numLinesWithWidth:self.width]);
    [currentGrid_ restoreScreenFromLineBuffer:linebuffer_
                              withDefaultChar:[currentGrid_ defaultChar]
                            maxLinesToRestore:linesRestored];
    DLog(@"appendFromDictionary: Grid size is %dx%d", currentGrid_.size.width, currentGrid_.size.height);
    DLog(@"Restored %d wrapped lines from dictionary", [self numberOfScrollbackLines] + linesRestored);
    currentGrid_.cursorY = linesRestored + 1;
    currentGrid_.cursorX = 0;

    if (screenState) {
        [tabStops_ removeAllObjects];
        [tabStops_ addObjectsFromArray:screenState[kScreenStateTabStopsKey]];

        [terminal_ setStateFromDictionary:screenState[kScreenStateTerminalKey]];
        NSArray *array = screenState[kScreenStateLineDrawingModeKey];
        for (int i = 0; i < sizeof(charsetUsesLineDrawingMode_) / sizeof(charsetUsesLineDrawingMode_[0]) && i < array.count; i++) {
            charsetUsesLineDrawingMode_[i] = [array[i] boolValue];
        }

        VT100Grid *otherGrid = (currentGrid_ == primaryGrid_) ? altGrid_ : primaryGrid_;
        LineBuffer *otherLineBuffer = [[[LineBuffer alloc] initWithDictionary:screenState[kScreenStateNonCurrentGridKey]] autorelease];
        [otherGrid restoreScreenFromLineBuffer:otherLineBuffer
                               withDefaultChar:[altGrid_ defaultChar]
                             maxLinesToRestore:altGrid_.size.height];

        NSString *guidOfLastCommandMark = screenState[kScreenStateLastCommandMarkKey];

        [intervalTree_ release];
        intervalTree_ = [[IntervalTree alloc] initWithDictionary:screenState[kScreenStateIntervalTreeKey]];
        [self fixUpDeserializedIntervalTree:intervalTree_
                              knownTriggers:triggers
                                    visible:YES
                      guidOfLastCommandMark:guidOfLastCommandMark];

        [savedIntervalTree_ release];
        savedIntervalTree_ = [[IntervalTree alloc] initWithDictionary:screenState[kScreenStateSavedIntervalTreeKey]];
        [self fixUpDeserializedIntervalTree:savedIntervalTree_
                              knownTriggers:triggers
                                    visible:NO
                      guidOfLastCommandMark:guidOfLastCommandMark];

        [self reloadMarkCache];
        commandStartX_ = [screenState[kScreenStateCommandStartXKey] intValue];
        commandStartY_ = [screenState[kScreenStateCommandStartYKey] intValue];
        nextCommandOutputStart_ = [screenState[kScreenStateNextCommandOutputStartKey] gridAbsCoord];
        _cursorVisible = [screenState[kScreenStateCursorVisibleKey] boolValue];
        _trackCursorLineMovement = [screenState[kScreenStateTrackCursorLineMovementKey] boolValue];
        _lastCommandOutputRange = [screenState[kScreenStateLastCommandOutputRangeKey] gridAbsCoordRange];
        _shellIntegrationInstalled = [screenState[kScreenStateShellIntegrationInstalledKey] boolValue];

        [primaryGrid_ setStateFromDictionary:screenState[kScreenStatePrimaryGridStateKey]];
        [altGrid_ setStateFromDictionary:screenState[kScreenStateAlternateGridStateKey]];
    }
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
            }
        }
    }
}

- (iTermTemporaryDoubleBufferedGridController *)temporaryDoubleBuffer {
    if ([delegate_ screenShouldReduceFlicker]) {
        return _temporaryDoubleBuffer;
    } else {
        return nil;
    }
}

#pragma mark - iTermFullScreenUpdateDetectorDelegate

- (VT100Grid *)temporaryDoubleBufferedGridCopy {
    VT100Grid *copy = [[currentGrid_ copy] autorelease];
    copy.delegate = nil;
    return copy;
}

- (void)temporaryDoubleBufferedGridDidExpire {
    [currentGrid_ setAllDirty:YES];
    // Force the screen to redraw right away. Some users reported lag and this seems to fix it.
    // I think the update timer was hitting a worst case scenario which made the lag visible.
    // See issue 3537.
    [delegate_ screenUpdateDisplay:YES];
}

@end

@implementation VT100Screen (Testing)

- (void)setMayHaveDoubleWidthCharacters:(BOOL)value {
    linebuffer_.mayHaveDoubleWidthCharacter = value;
}

@end
