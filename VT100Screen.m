#import "VT100Screen.h"

#import "DVRBuffer.h"
#import "ITAddressBookMgr.h"
#import "ITAddressBookMgr.h"
#import "LineBuffer.h"
#import "NSStringITerm.h"
#import "PTYScrollView.h"
#import "PTYTab.h"
#import "PTYTask.h"
#import "PTYTextView.h"
#import "PreferencePanel.h"
#import "RegexKitLite.h"
#import "SearchResult.h"
#import "TmuxStateParser.h"
#import "VT100Grid.h"
#import "WindowControllerInterface.h"
#import "charmaps.h"
#import "iTerm.h"
#import "iTermApplicationDelegate.h"
#import "iTermExpose.h"
#import "iTermGrowlDelegate.h"

#import <apr-1/apr_base64.h>  // for xterm's base64 decoding (paste64)
#include <string.h>
#include <unistd.h>

static const int kMaxLinesToScrollAtOneTime = 1024;  // Prevents DOS by XTERMCC_SU/XTERMCC_SD

// Prevents runaway memory usage
static const int kMaxScreenColumns = 4096;
static const int kMaxScreenRows = 4096;

static const int kDefaultScreenColumns = 80;
static const int kDefaultScreenRows = 25;
static const int kDefaultMaxScrollbackLines = 1000;
static const int kDefaultTabstopWidth = 8;

NSString * const kHighlightForegroundColor = @"kHighlightForegroundColor";
NSString * const kHighlightBackgroundColor = @"kHighlightBackgroundColor";

// Wait this long between calls to NSBeep().
static const double kInterBellQuietPeriod = 0.1;

// Max time for -continueFindResultAtStartX: to run for.
static const NSTimeInterval kMaxTimeToSearch = 0.1;

@implementation VT100Screen

@synthesize terminal = terminal_;
@synthesize shell = shell_;
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

- (id)initWithTerminal:(VT100Terminal *)terminal
{
    self = [super init];
    if (self) {
        terminal_ = [terminal retain];
        primaryGrid_ = [[VT100Grid alloc] initWithSize:VT100GridSizeMake(kDefaultScreenColumns,
                                                                         kDefaultScreenRows)
                                              delegate:terminal];
        currentGrid_ = primaryGrid_;

        maxScrollbackLines_ = kDefaultMaxScrollbackLines;
        tabStops = [[NSMutableSet alloc] init];
        [self setInitialTabStops];
        linebuffer_ = [[LineBuffer alloc] init];

        [iTermGrowlDelegate sharedInstance];

        dvr = [DVR alloc];
        [dvr initWithBufferCapacity:[[PreferencePanel sharedInstance] irMemory] * 1024 * 1024];
    }
    return self;
}

- (void)dealloc
{
    [primaryGrid_ release];
    [altGrid_ release];
    [tabStops release];
    [printBuffer_ release];
    [linebuffer_ release];
    [dvr release];
    [terminal_ release];
    [shell_ release];
    [super dealloc];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p grid:%@>", [self class], self, currentGrid_];
}

#pragma mark - APIs

- (void)setUpScreenWithWidth:(int)width height:(int)height
{
    int i;
    screen_char_t *aDefaultLine;

    width = MAX(width, MIN_SESSION_COLUMNS);
    height = MAX(height, MIN_SESSION_ROWS);

    primaryGrid_.size = VT100GridSizeMake(width, height);
    altGrid_.size = VT100GridSizeMake(width, height);
    primaryGrid_.cursor = VT100GridCoordMake(0, 0);
    altGrid_.cursor = VT100GridCoordMake(0, 0);
    primaryGrid_.savedCursor = VT100GridCoordMake(0, 0);
    altGrid_.savedCursor = VT100GridCoordMake(0, 0);
    [primaryGrid_ resetScrollRegions];
    [altGrid_ resetScrollRegions];

    findContext_.substring = nil;

    scrollbackOverflow_ = 0;
    [delegate_ screenRemoveSelection];

    [primaryGrid_ markAllCharsDirty:YES];
    [altGrid_ markAllCharsDirty:YES];
}

- (void)resizeWidth:(int)new_width height:(int)new_height
{
#ifdef DEBUG_RESIZEDWIDTH
    NSLog(@"Size before resizing is %dx%d", currentGrid_.size.width, currentGrid_.size.height);
    [self dumpScreen];
#endif
    DLog(@"Resize session to %d height", new_height);
    int i;

#ifdef DEBUG_RESIZEDWIDTH
    NSLog(@"Resize from %dx%d to %dx%d\n", currentGrid_.size.width, currentGrid_.size.height, new_width, new_height);
    [self dumpScreen];
#endif

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

    VT100Grid *originalPrimaryGrid = primaryGrid_;
    VT100Grid *originalAltGrid = altGrid_;
    VT100Grid *copyOfAltGrid = [[altGrid_ copy] autorelease];
    LineBuffer *realLineBuffer = linebuffer_;

    int originalLastPos = [linebuffer_ lastPos];
    int originalStartPos = 0;
    int originalEndPos = 0;
    BOOL originalIsFullLine;
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
        [self getNullCorrectedSelectionStartPosition:&originalStartPos
                                         endPosition:&originalEndPos
                                 isFullLineSelection:&originalIsFullLine
                       selectionStartPositionIsValid:&ok1
                          selectionEndPostionIsValid:&ok2];
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
    [self appendScreen:primaryGrid_
          toScrollback:linebuffer_
        withUsedHeight:[primaryGrid_ numberOfLinesUsed]
             newHeight:new_height];

    int newSelStartX = -1;
    int newSelStartY = -1;
    int newSelEndX = -1;
    int newSelEndY = -1;
    BOOL isFullLineSelection = NO;
    if (!wasShowingAltScreen && hasSelection) {
        hasSelection = [self convertCurrentSelectionToWidth:new_width
                                                toNewStartX:&newSelStartX
                                                toNewStartY:&newSelStartY
                                                  toNewEndX:&newSelEndX
                                                  toNewEndY:&newSelEndY
                                      toIsFullLineSelection:&isFullLineSelection];
    }

    VT100GridSize newSize = VT100GridSizeMake(new_width, new_height);
    currentGrid_.size = newSize;

    // Restore the screen contents that were pushed onto the linebuffer.
    [currentGrid_ restoreScreenFromLineBuffer:wasShowingAltScreen ? altScreenLineBuffer : linebuffer_
                              withDefaultChar:[currentGrid_ defaultChar]
                            maxLinesToRestore:[linebuffer_ numLinesWithWidth:currentGrid_.size.width]];

    // In alternate screen mode, the screen contents move up when a line wraps.
    int linesMovedUp = [linebuffer_ numLinesWithWidth:currentGrid_.size.width];

    // If we're in the alternate screen, restore its contents from the temporary
    // linebuffer.
    if (wasShowingAltScreen) {
        VT100Grid *savedCurrentGrid = currentGrid_;
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
            [currentGrid_ restoreScreenFromLineBuffer:realLineBuffer
                                      withDefaultChar:[primaryGrid_ defaultChar]
                                    maxLinesToRestore:new_height];
        }

        int newLastPos = [realLineBuffer lastPos];
        primaryGrid_.savedCursor = primaryGrid_.cursor;

        ///////////////////////////////////////
        // Create a cheap append-only copy of the line buffer and add the
        // screen to it. This sets up the current state so that if there is a
        // selection, linebuffer has the configuration that the user actually
        // sees (history + the alt screen contents). That'll make
        // convertCurrentSelectionToWidth:... happy (the selection's Y values
        // will be able to be looked up) and then after that's done we can swap
        // back to the tempLineBuffer.
        LineBuffer *appendOnlyLineBuffer = [[realLineBuffer newAppendOnlyCopy] autorelease];

        [self appendScreen:copyOfAltGrid
              toScrollback:appendOnlyLineBuffer
            withUsedHeight:usedHeight
                 newHeight:new_height];

        if (hasSelection) {
            // Compute selection positions relative to the end of the line buffer, which may have
            // grown or shrunk.

            int growth = newLastPos - originalLastPos;
            int startPos = originalStartPos;
            int endPos = originalEndPos;
            if (growth > 0) {
                if (startPos >= originalLastPos) {
                    startPos += growth;
                }
                if (endPos >= originalLastPos) {
                    endPos += growth;
                }
            } else if (growth < 0) {
                if (startPos >= newLastPos && startPos < originalLastPos) {
                    // Started in deleted region
                    startPos = newLastPos;
                } else if (startPos >= originalLastPos) {
                    startPos += growth;
                }
                if (endPos >= newLastPos && endPos < originalLastPos) {
                    // Ended in deleted region
                    endPos = newLastPos;
                } else if (endPos >= originalLastPos) {
                    endPos += growth;
                }
            }
            if (startPos == endPos) {
                hasSelection = NO;
            }
            [appendOnlyLineBuffer convertPosition:startPos
                                        withWidth:new_width
                                              toX:&newSelStartX
                                              toY:&newSelStartY];
            int numScrollbackLines = [realLineBuffer numLinesWithWidth:new_width];
            if (newSelStartY >= numScrollbackLines) {
                newSelStartY -= linesMovedUp;
            }
            [appendOnlyLineBuffer convertPosition:endPos
                                        withWidth:new_width
                                              toX:&newSelEndX
                                              toY:&newSelEndY];
            if (newSelEndY >= numScrollbackLines) {
                newSelEndY -= linesMovedUp;
            }
        }
    } else {
        [altGrid_ release];
        altGrid_ = nil;
    }

    [primaryGrid_ resetScrollRegions];
    [altGrid_ resetScrollRegions];
    [primaryGrid_ clampCursorPositionToValid];
    [altGrid_ clampCursorPositionToValid];

    // The linebuffer may have grown. Ensure it doesn't have too many lines.
    int linesDropped = 0;
    if (!unlimitedScrollback_) {
        linesDropped = [linebuffer_ dropExcessLinesWithWidth:currentGrid_.size.width];
        [self incrementOverflowBy:linesDropped];  // TODO test this!
    }
    int lines = [linebuffer_ numLinesWithWidth:currentGrid_.size.width];
    NSAssert(lines >= 0, @"Negative lines");

    // An immediate refresh is needed so that the size of TEXTVIEW can be
    // adjusted to fit the new size
    DebugLog(@"resizeWidth setDirty");
    [delegate_ screenNeedsRedraw];
    if (hasSelection &&
        newSelStartY >= linesDropped &&
        newSelEndY >= linesDropped) {
        [delegate_ screenSetSelectionFromX:newSelStartX
                                     fromY:newSelStartY - linesDropped
                                       toX:newSelEndX
                                       toY:newSelEndY - linesDropped];
    } else {
        [delegate_ screenRemoveSelection];
    }
    
    [delegate_ screenSizeDidChange];
}

- (void)resetPreservingPrompt:(BOOL)preservePrompt
{
    int savedCursorX = currentGrid_.cursorX;
    if (preservePrompt) {
        [self setCursorX:savedCursorX Y:currentGrid_.topMargin];
    }
    [self resetScreen];
    if (preservePrompt) {
        [self setCursorX:savedCursorX Y:0];
    }
}

- (void)resetCharset {
    for (int i = 0; i < 4; i++) {
        charsetUsesLineDrawingMode_[i] = NO;
    }
}

- (BOOL)usingDefaultCharset {
    for (int i = 0; i < 4; i++) {
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

- (void)putToken:(VT100TCC)token
{
    NSString *newTitle;

    int i,j,k;
    screen_char_t *aLine;

    switch (token.type) {
            // our special code
        case VT100_STRING:
        case VT100_ASCIISTRING:
            if (collectInputForPrinting_) {
                [printBuffer_ appendString:token.u.string];
            } else {
                // else display string on screen
                [self appendStringAtCursor:token.u.string ascii:(token.type == VT100_ASCIISTRING)];
            }
            [delegate_ screenDidAppendStringToCurrentLine:token.u.string];
            break;

        case VT100_UNKNOWNCHAR:
            break;
        case VT100_NOTSUPPORT:
            break;

            //  VT100 CC
        case VT100CC_ENQ:
            break;
        case VT100CC_BEL:
            [delegate_ screenDidAppendStringToCurrentLine:@"\a"];
            [self activateBell];
            break;
        case VT100CC_BS:
            [self backSpace];
            break;
        case VT100CC_HT:
            [self appendTabAtCursor];
            break;
        case VT100CC_LF:
        case VT100CC_VT:
        case VT100CC_FF:
            if (collectInputForPrinting_) {
                [printBuffer_ appendString:@"\n"];
            } else {
                [self linefeed];
            }
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case VT100CC_CR:
            [currentGrid_ moveCursorToLeftMargin];
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case VT100CC_SO:
            break;
        case VT100CC_SI:
            break;
        case VT100CC_DC1:
            break;
        case VT100CC_DC3:
            break;
        case VT100CC_CAN:
        case VT100CC_SUB:
            break;
        case VT100CC_DEL:
            [currentGrid_ deleteChars:1 startingAt:currentGrid_.cursor];
            [delegate_ screenTriggerableChangeDidOccur];
            break;

            // VT100 CSI
        case VT100CSI_CPR:
            break;
        case VT100CSI_CUB:
            [self cursorLeft:token.u.csi.p[0]];
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case VT100CSI_CUD:
            [self cursorDown:token.u.csi.p[0]];
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case VT100CSI_CUF:
            [self cursorRight:token.u.csi.p[0]];
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case VT100CSI_CUP:
            [self cursorToX:token.u.csi.p[1] Y:token.u.csi.p[0]];
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case VT100CSI_CUU:
            [self cursorUp:token.u.csi.p[0]];
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case VT100CSI_DA:
            [self deviceAttribute:token];
            break;
        case VT100CSI_DA2:
            [self secondaryDeviceAttribute:token];
            break;
        case VT100CSI_DECALN: {
            screen_char_t ch = [currentGrid_ defaultChar];
            ch.code = 'E';
            [currentGrid_ setCharsFrom:VT100GridCoordMake(0, 0)
                                    to:VT100GridCoordMake(currentGrid_.size.width - 1, currentGrid_.size.height - 1)
                                toChar:ch];
            [currentGrid_ resetScrollRegions];
            currentGrid_.cursor = VT100GridCoordMake(0, 0);
            DebugLog(@"putToken DECALN");
            break;
        }
        case VT100CSI_DECDHL:
            break;
        case VT100CSI_DECDWL:
            break;
        case VT100CSI_DECID:
            break;
        case VT100CSI_DECKPAM:
            break;
        case VT100CSI_DECKPNM:
            break;
        case VT100CSI_DECLL:
            break;
        case VT100CSI_DECRC:
            [self restoreCursorPosition];
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case VT100CSI_DECREPTPARM:
            break;
        case VT100CSI_DECREQTPARM:
            break;
        case VT100CSI_DECSC:
            [self saveCursorPosition];
            break;
        case VT100CSI_DECSTBM:
            [self setTopBottom:token];
            break;
        case VT100CSI_DECSWL:
            break;
        case VT100CSI_DECTST:
            break;
        case VT100CSI_DSR:
            [self deviceReport:token withQuestion:NO];
            break;
        case VT100CSI_DECDSR:
            [self deviceReport:token withQuestion:YES];
            break;
        case VT100CSI_ED:
            [self eraseInDisplay:token];
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case VT100CSI_EL:
            [self eraseInLine:token];
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case VT100CSI_HTS:
            if (currentGrid_.cursorX < currentGrid_.size.width) {
                [self setTabStopAt:currentGrid_.cursorX];
            }
            break;
        case VT100CSI_HVP:
            [self cursorToX:token.u.csi.p[1] Y:token.u.csi.p[0]];
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case VT100CSI_NEL:
            [currentGrid_ moveCursorToLeftMargin];
            // fall through
        case VT100CSI_IND:
            if (currentGrid_.cursorY == currentGrid_.bottomMargin) {
                [self incrementOverflowBy:[currentGrid_ scrollUpIntoLineBuffer:linebuffer_
                                                           unlimitedScrollback:unlimitedScrollback_
                                                       useScrollbackWithRegion:[self useScrollbackWithRegion]]];
            } else {
                currentGrid_.cursorY = currentGrid_.cursorY + 1;
            }
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case VT100CSI_RI:
            if (currentGrid_.cursorY == currentGrid_.topMargin) {
                [currentGrid_ scrollDown];
            } else {
                currentGrid_.cursorY = currentGrid_.cursorY - 1;
            }
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case VT100CSI_RIS:
            // As far as I can tell, this is not part of the standard and should not be
            // supported.  -- georgen 7/31/11
            break;

        case ANSI_RIS:
            [terminal_ reset];
            break;
        case VT100CSI_RM:
            break;
        case VT100CSI_DECSTR: {
            // VT100CSI_DECSC
            // See note in xterm-terminfo.txt (search for DECSTR).

            // save cursor (fixes origin-mode side-effect)
            [self saveCursorPosition];

            // reset scrolling margins
            VT100TCC wholeScreen = { 0 };
            wholeScreen.u.csi.p[0] = 0;
            wholeScreen.u.csi.p[1] = 0;
            [self setTopBottom:wholeScreen];

            // reset SGR (done in VT100Terminal)
            // reset wraparound mode (done in VT100Terminal)
            // reset application cursor keys (done in VT100Terminal)
            // reset origin mode (done in VT100Terminal)
            // restore cursor
            [self restoreCursorPosition];
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        }
        case VT100CSI_DECSCUSR:
            switch (token.u.csi.p[0]) {
                case 0:
                case 1:
                    [delegate_ screenSetCursorBlinking:true cursorType:CURSOR_BOX];
                    break;
                case 2:
                    [delegate_ screenSetCursorBlinking:false cursorType:CURSOR_BOX];
                    break;
                case 3:
                    [delegate_ screenSetCursorBlinking:true cursorType:CURSOR_UNDERLINE];
                    break;
                case 4:
                    [delegate_ screenSetCursorBlinking:false cursorType:CURSOR_UNDERLINE];
                    break;
                case 5:
                    [delegate_ screenSetCursorBlinking:true cursorType:CURSOR_VERTICAL];
                    break;
                case 6:
                    [delegate_ screenSetCursorBlinking:false cursorType:CURSOR_VERTICAL];
                    break;
                default:
                    //NSLog(@"DECSCUSR: Unrecognized parameter: %d", token.u.csi.p[0]);
                    break;
            }
            break;

        case VT100CSI_DECSLRM: {
            int scrollLeft = token.u.csi.p[0] - 1;
            int scrollRight = token.u.csi.p[1] - 1;
            int width = currentGrid_.size.width;
            if (scrollLeft < 0) {
                scrollLeft = 0;
            }
            if (scrollRight == 0) {
                scrollRight = width - 1;
            }
            // check wrong parameter
            if (scrollRight - scrollLeft < 1) {
                scrollLeft = 0;
                scrollRight = width - 1;
            }
            if (scrollRight > width - 1) {
                scrollRight = width - 1;
            }
            currentGrid_.scrollRegionCols = VT100GridRangeMake(scrollLeft,
                                                               scrollRight - scrollLeft + 1);
            // set cursor to the home position
            [self cursorToX:1 Y:1];
            break;
        }

            /* My interpretation of this:
             * http://www.cl.cam.ac.uk/~mgk25/unicode.html#term
             * is that UTF-8 terminals should ignore SCS because
             * it's either a no-op (in the case of iso-8859-1) or
             * insane. Also, mosh made fun of Terminal and I don't
             * want to be made fun of:
             * "Only Mosh will never get stuck in hieroglyphs when a nasty
             * program writes to the terminal. (See Markus Kuhn's discussion of
             * the relationship between ISO 2022 and UTF-8.)"
             * http://mosh.mit.edu/#techinfo
             *
             * I'm going to throw this out there (4/15/2012) and see if this breaks
             * anything for anyone.
             *
             * UPDATE: In bug 1997, we see that it breaks line-drawing chars, which
             * are in SCS0. Indeed, mosh fails to draw these as well.
             *
             * UPDATE: In bug 2358, we see that SCS1 is also legitimately used in
             * UTF-8.
             *
             * Here's my take on the way things work. There are four charsets: G0
             * (default), G1, G2, and G3. They are switched between with codes like SI
             * (^O), SO (^N), LS2 (ESC n), and LS3 (ESC o). You can get the current
             * character set from [terminal_ charset], and that gives you a number from
             * 0 to 3 inclusive. It is an index into Screen's charsetUsesLineDrawingMode_ array.
             * In iTerm2, it is an array of booleans where 0 means normal behavior and 1 means
             * line-drawing. There should be a bunch of other values too (like
             * locale-specific char sets). This is pretty far away from the spec,
             * but it works well enough for common behavior, and it seems the spec
             * doesn't work well with common behavior (esp line drawing).
             */
        case VT100CSI_SCS0:
            charsetUsesLineDrawingMode_[0] = (token.u.code=='0');
            break;
        case VT100CSI_SCS1:
            charsetUsesLineDrawingMode_[1] = (token.u.code=='0');
            break;
        case VT100CSI_SCS2:
            charsetUsesLineDrawingMode_[2] = (token.u.code=='0');
            break;
        case VT100CSI_SCS3:
            charsetUsesLineDrawingMode_[3] = (token.u.code=='0');
            break;
        case VT100CSI_SGR:
            [self selectGraphicRendition:token];
            break;
        case VT100CSI_SM:
            break;
        case VT100CSI_TBC:
            switch (token.u.csi.p[0]) {
                case 3:
                    [self clearTabStop];
                    break;

                case 0:
                    if (currentGrid_.cursorX < currentGrid_.size.width) {
                        [self removeTabStopAt:currentGrid_.cursorX];
                    }
            }
            break;

        case VT100CSI_DECSET:
        case VT100CSI_DECRST:
            if (token.u.csi.p[0] == 3 && // DECCOLM
                [terminal_ allowColumnMode] == YES &&
                ![delegate_ screenShouldInitiateWindowResize]) {
                // set the column
                [delegate_ screenResizeToWidth:([terminal_ columnMode] ? 132 : 80)
                                        height:currentGrid_.size.height];
                token.u.csi.p[0] = 2;
                [self eraseInDisplay:token];  // erase the screen
                token.u.csi.p[0] = token.u.csi.p[1] = 0;
                [self setTopBottom:token];  // reset horizontal scroll
                [self setVsplitMode: NO];   // reset vertical scroll
            }

            break;

            // ANSI CSI
        case ANSICSI_CBT:
            [self backTab];
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case ANSICSI_CHA:
            [self cursorToX:token.u.csi.p[0]];
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case ANSICSI_VPA:
            [self cursorToY:token.u.csi.p[0]];
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case ANSICSI_VPR:
            [self cursorDown:token.u.csi.p[0]];
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case ANSICSI_ECH:
            if (currentGrid_.cursorX < currentGrid_.size.width) {
                int dirtyX = currentGrid_.cursorX;
                int dirtyY = currentGrid_.cursorY;

                j = token.u.csi.p[0];
                if (j <= 0) {
                    break;
                }

                int limit = MIN(currentGrid_.cursorX + j, currentGrid_.size.width);
                [currentGrid_ setCharsFrom:VT100GridCoordMake(currentGrid_.cursorX, currentGrid_.cursorY)
                                        to:VT100GridCoordMake(limit - 1, currentGrid_.cursorY)
                                    toChar:[currentGrid_ defaultChar]];
                // TODO: This used to always set the continuation mark to hard, but I think it should only do that if the last char in the line is erased.
                DebugLog(@"putToken ECH");
            }
            [delegate_ screenTriggerableChangeDidOccur];
            break;

        case STRICT_ANSI_MODE:
            [terminal_ setStrictAnsiMode:![terminal_ strictAnsiMode]];
            break;

        case ANSICSI_PRINT:
            if ([delegate_ screenShouldBeginPrinting]) {
                switch (token.u.csi.p[0]) {
                    case 4:
                        // print our stuff!!
                        [self doPrint];
                        break;
                    case 5:
                        // allocate a string for the stuff to be printed
                        if (printBuffer_ != nil) {
                            [printBuffer_ release];
                        }
                        printBuffer_ = [[NSMutableString alloc] init];
                        collectInputForPrinting_ = YES;
                        break;
                    default:
                        //print out the whole screen
                        if (printBuffer_ != nil) {
                            [printBuffer_ release];
                            printBuffer_ = nil;
                        }
                        collectInputForPrinting_ = NO;
                        [self doPrint];
                }
            }
            break;
        case ANSICSI_SCP:
            [self saveCursorPosition];
            break;
        case ANSICSI_RCP:
            [self restoreCursorPosition];
            [delegate_ screenTriggerableChangeDidOccur];
            break;

            // XTERM extensions
        case XTERMCC_WIN_TITLE:
            newTitle = [[token.u.string copy] autorelease];
            if ([self syncTitle]) {
                newTitle = [NSString stringWithFormat:@"%@: %@", [delegate_ screenNameExcludingJob], newTitle];
            }
            [delegate_ screenSetWindowTitle:newTitle];
            long long lineNumber = [self absoluteLineNumberOfCursor];
            [delegate_ screenLogWorkingDirectoryAtLine:lineNumber];
            break;
        case XTERMCC_WINICON_TITLE:
            newTitle = [[token.u.string copy] autorelease];
            if ([self syncTitle]) {
                newTitle = [NSString stringWithFormat:@"%@: %@", [delegate_ screenNameExcludingJob], newTitle];
            }
            [delegate_ screenSetWindowTitle:newTitle];
            [delegate_ screenSetName:newTitle];
            break;
        case XTERMCC_PASTE64:
            [self processXtermPaste64: [[token.u.string copy] autorelease]];
            break;
        case XTERMCC_ICON_TITLE:
            newTitle = [[token.u.string copy] autorelease];
            if ([self syncTitle]) {
                newTitle = [NSString stringWithFormat:@"%@: %@", [delegate_ screenNameExcludingJob], newTitle];
            }
            [delegate_ screenSetName: newTitle];
            break;
        case XTERMCC_INSBLNK:
            [currentGrid_ insertChar:[currentGrid_ defaultChar]
                                  at:currentGrid_.cursor
                               times:token.u.csi.p[0]];
            break;
        case XTERMCC_INSLN:
            // TODO: I think the original code was buggy when the cursor was outside the scroll region.
            [currentGrid_ scrollRect:[currentGrid_ scrollRegionRect]
                              downBy:token.u.csi.p[0]];
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case XTERMCC_DELCH:
            [currentGrid_ deleteChars:token.u.csi.p[0] startingAt:currentGrid_.cursor];
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case XTERMCC_DELLN:
            [self deleteLines:token.u.csi.p[0]];
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case XTERMCC_WINDOWSIZE:
            //NSLog(@"setting window size from (%d, %d) to (%d, %d)", WIDTH, HEIGHT, token.u.csi.p[1], token.u.csi.p[2]);
            if ([delegate_ screenShouldInitiateWindowResize] &&
                ![delegate_ screenWindowIsFullscreen]) {
                // set the column
                [delegate_ screenResizeToWidth:MIN(token.u.csi.p[2], kMaxScreenColumns)
                                        height:MIN(token.u.csi.p[1], kMaxScreenRows)];

            }
            break;
        case XTERMCC_WINDOWSIZE_PIXEL:
            if ([delegate_ screenShouldInitiateWindowResize] &&
                ![delegate_ screenWindowIsFullscreen]) {
                // TODO: Only allow this if there is a single session in the tab.
                NSSize cellSize = [delegate_ screenCellSize];
                [delegate_ screenResizeToWidth:MIN(token.u.csi.p[2] / cellSize.width, kMaxScreenColumns)
                                        height:MIN(token.u.csi.p[1] / cellSize.height, kMaxScreenRows)];
            }
            break;
        case XTERMCC_WINDOWPOS:
            //NSLog(@"setting window position to Y=%d, X=%d", token.u.csi.p[1], token.u.csi.p[2]);
            if ([delegate_ screenShouldInitiateWindowResize] &&
                ![delegate_ screenWindowIsFullscreen]) {
                // TODO: Only allow this if there is a single session in the tab.
                [delegate_ screenMoveWindowTopLeftPointTo:NSMakePoint(token.u.csi.p[1],
                                                                      [[delegate_ screenWindowScreen] frame].size.height - token.u.csi.p[2])];
            }
            break;
        case XTERMCC_ICONIFY:
            // TODO: Only allow this if there is a single session in the tab.
            if (![delegate_ screenWindowIsFullscreen]) {
                [delegate_ screenMiniaturizeWindow:YES];
            }
            break;
        case XTERMCC_DEICONIFY:
            // TODO: Only allow this if there is a single session in the tab.
            [delegate_ screenMiniaturizeWindow:NO];
            break;
        case XTERMCC_RAISE:
            // TODO: Only allow this if there is a single session in the tab.
            [delegate_ screenRaise:YES];
            break;
        case XTERMCC_LOWER:
            // TODO: Only allow this if there is a single session in the tab.
            if (![delegate_ screenWindowIsFullscreen]) {
                [delegate_ screenRaise:NO];
            }
            break;
        case XTERMCC_SU:
            for (i = 0; i < MIN(MAX(currentGrid_.size.height, kMaxLinesToScrollAtOneTime), token.u.csi.p[0]); i++) {
                [self incrementOverflowBy:[currentGrid_ scrollUpIntoLineBuffer:linebuffer_
                                                           unlimitedScrollback:unlimitedScrollback_
                                                       useScrollbackWithRegion:[self useScrollbackWithRegion]]];
            }
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case XTERMCC_SD:
            [currentGrid_ scrollRect:[currentGrid_ scrollRegionRect]
                              downBy:MIN(MAX(currentGrid_.size.height, kMaxLinesToScrollAtOneTime), token.u.csi.p[0])];
            [delegate_ screenTriggerableChangeDidOccur];
            break;
        case XTERMCC_REPORT_WIN_STATE: {
            char buf[64];
            snprintf(buf, sizeof(buf), "\033[%dt", [delegate_ screenWindowIsMiniaturized] ? 2 : 1);
            [delegate_ screenWriteDataToTask:[NSData dataWithBytes:buf length:strlen(buf)]];
            break;
        }
        case XTERMCC_REPORT_WIN_POS: {
            char buf[64];
            NSRect frame = [delegate_ screenWindowFrame];
            NSScreen *screen = [delegate_ screenWindowScreen];
            // Report the Y coordinate in a non-Macish way; give the distance
            // from the top of the usable part of the display to the top of the
            // window frame.
            int y = [screen frame].size.height - frame.origin.y - frame.size.height;
            // TODO: Figure out wtf to do if there are multiple sessions in one tab.
            snprintf(buf, sizeof(buf), "\033[3;%d;%dt", (int) frame.origin.x, y);
            [delegate_ screenWriteDataToTask:[NSData dataWithBytes:buf length:strlen(buf)]];
            break;
        }
        case XTERMCC_REPORT_WIN_PIX_SIZE: {
            char buf[64];
            NSRect frame = [delegate_ screenWindowFrame];
            // TODO: Some kind of adjustment for panes?
            snprintf(buf, sizeof(buf), "\033[4;%d;%dt", (int) frame.size.height, (int) frame.size.width);
            [delegate_ screenWriteDataToTask:[NSData dataWithBytes:buf length:strlen(buf)]];
            break;
        }
        case XTERMCC_REPORT_WIN_SIZE: {
            char buf[64];
            // TODO: Some kind of adjustment for panes
            snprintf(buf, sizeof(buf), "\033[8;%d;%dt", currentGrid_.size.height, currentGrid_.size.width);
            [delegate_ screenWriteDataToTask:[NSData dataWithBytes:buf length:strlen(buf)]];
            break;
        }
        case XTERMCC_REPORT_SCREEN_SIZE: {
            char buf[64];
            // TODO: This isn't really right since a window couldn't be made this large given the
            // window decorations.
            NSRect screenSize = [[delegate_ screenWindowScreen] frame];
            //  TODO: WTF do we do with panes here?
            float nch = [delegate_ screenWindowFrame].size.height - [delegate_ screenSize].height;
            float wch = [delegate_ screenWindowFrame].size.width - [delegate_ screenSize].width;
            NSSize cellSize = [delegate_ screenCellSize];
            int h = (screenSize.size.height - nch) / cellSize.height;
            int w =  (screenSize.size.width - wch - MARGIN * 2) / cellSize.width;

            snprintf(buf, sizeof(buf), "\033[9;%d;%dt", h, w);
            [delegate_ screenWriteDataToTask:[NSData dataWithBytes:buf length:strlen(buf)]];
            break;
        }
        case XTERMCC_REPORT_ICON_TITLE: {
            NSString *theString;
            if (allowTitleReporting_) {
                theString = [NSString stringWithFormat:@"\033]L%@\033\\",
                             [delegate_ screenWindowTitle] ? [delegate_ screenWindowTitle] : [delegate_ screenDefaultName]];
            } else {
                NSLog(@"Not reporting icon title. You can enable this in prefs>profiles>terminal");
                theString = @"\033]L\033\\";
            }
            NSData *theData = [theString dataUsingEncoding:NSUTF8StringEncoding];
            [delegate_ screenWriteDataToTask:theData];
            break;
        }
        case XTERMCC_REPORT_WIN_TITLE: {
            NSString *theString;
            if (allowTitleReporting_) {
                theString = [NSString stringWithFormat:@"\033]l%@\033\\", [delegate_ screenWindowName]];
            } else {
                NSLog(@"Not reporting window title. You can enable this in prefs>profiles>terminal");
                theString = @"\033]l\033\\";
            }
            NSData *theData = [theString dataUsingEncoding:NSUTF8StringEncoding];
            [delegate_ screenWriteDataToTask:theData];
            break;
        }
        case XTERMCC_PUSH_TITLE: {
            switch (token.u.csi.p[1]) {
                case 0:
                    [delegate_ screenPushCurrentTitleForWindow:YES];
                    [delegate_ screenPushCurrentTitleForWindow:NO];
                    break;
                case 1:
                    [delegate_ screenPushCurrentTitleForWindow:NO];
                    break;
                case 2:
                    [delegate_ screenPushCurrentTitleForWindow:YES];
                    break;
                    break;
            }
            break;
        }
        case XTERMCC_POP_TITLE: {
            switch (token.u.csi.p[1]) {
                case 0:
                    [delegate_ screenPopCurrentTitleForWindow:YES];
                    [delegate_ screenPopCurrentTitleForWindow:NO];
                    break;
                case 1:
                    [delegate_ screenPopCurrentTitleForWindow:NO];
                    break;
                case 2:
                    [delegate_ screenPopCurrentTitleForWindow:YES];
                    break;
            }
            break;
        }
            // Our iTerm specific codes
        case ITERM_GROWL:
            if (postGrowlNotifications_) {
                [[iTermGrowlDelegate sharedInstance]
                 growlNotify:NSLocalizedStringFromTableInBundle(@"Alert",
                                                                @"iTerm",
                                                                [NSBundle bundleForClass:[self class]],
                                                                @"Growl Alerts")
                 withDescription:[NSString stringWithFormat:@"Session %@ #%d: %@",
                                  [delegate_ screenName],
                                  [delegate_ screenNumber],
                                  token.u.string]
                 andNotification:@"Customized Message"
                 windowIndex:[delegate_ screenWindowIndex]
                 tabIndex:[delegate_ screenTabIndex]
                 viewIndex:[delegate_ screenViewIndex]];
            }
            break;
            
        case DCS_TMUX:
            [delegate_ screenStartTmuxMode];
            break;
            
        default:
            NSLog(@"%s(%d): bug?? token.type = %d", __FILE__, __LINE__, token.type);
            break;
    }
}

- (void)clearBuffer
{
    [self clearScreen];
    [self clearScrollbackBuffer];
    [delegate_ screenUpdateDisplay];
}

- (void)clearScrollbackBuffer
{
    [linebuffer_ release];
    linebuffer_ = [[LineBuffer alloc] init];
    [linebuffer_ setMaxLines:maxScrollbackLines_];
    [delegate_ screenClearHighlights];

    savedFindContextAbsPos_ = 0;

    [self resetScrollbackOverflow];
    [delegate_ screenRemoveSelection];
    [currentGrid_ markAllCharsDirty:YES];
}

- (void)showPrimaryBuffer
{
    currentGrid_ = primaryGrid_;
}

- (void)showAltBuffer
{
    if (currentGrid_ == altGrid_) {
        return;
    }
    if (!altGrid_) {
        altGrid_ = [primaryGrid_ copy];
    }
    primaryGrid_.savedDefaultChar = [primaryGrid_ defaultChar];
    currentGrid_ = altGrid_;
}

- (void)setSendModifiers:(int *)modifiers
               numValues:(int)numValues {
    NSMutableArray *array = [NSMutableArray array];
    for (int i = 0; i < numValues; i++) {
        [array addObject:[NSNumber numberWithInt:modifiers[i]]];
    }
    [delegate_ screenModifiersDidChangeTo:array];
}

- (void)setMouseMode:(MouseMode)mouseMode
{
    [delegate_ screenMouseModeDidChange];
}

- (void)appendStringAtCursor:(NSString *)string ascii:(BOOL)ascii
{
    if (gDebugLogging) {
        DLog(@"setString: %ld chars starting with %c at x=%d, y=%d, line=%d",
             (unsigned long)[string length],
             [string characterAtIndex:0],
             currentGrid_.cursorX,
             currentGrid_.cursorY,
             currentGrid_.cursorY + [linebuffer_ numLinesWithWidth:currentGrid_.size.width]);
    }

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
        const int kStaticTempElements = 1024;
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
        if (charsetUsesLineDrawingMode_[[terminal_ charset]]) {
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

        // Add DWC_RIGHT after each double-byte character.
        assert(terminal_);
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
    [self incrementOverflowBy:[currentGrid_ moveCursorDownOneLineScrollingIntoLineBuffer:linebuffer_
                                                                     unlimitedScrollback:unlimitedScrollback_
                                                                 useScrollbackWithRegion:[self useScrollbackWithRegion]]];
}

- (void)deleteCharacters:(int)n
{
    [currentGrid_ deleteChars:n startingAt:currentGrid_.cursor];
}

- (void)backSpace
{
    int leftMargin = currentGrid_.leftMargin;
    int cursorX = currentGrid_.cursorX;
    int cursorY = currentGrid_.cursorY;

    if (cursorX > leftMargin) {
        if (cursorX >= currentGrid_.size.width) {
            currentGrid_.cursorX = cursorX - 2;
        } else {
            currentGrid_.cursorX = cursorX - 1;
        }
    } else if (cursorX == 0 && cursorY > 0 && !currentGrid_.useScrollRegionCols) {
        screen_char_t* aLine = [self getLineAtScreenIndex:cursorY - 1];
        if (aLine[currentGrid_.size.width].code == EOL_SOFT) {
            currentGrid_.cursor = VT100GridCoordMake(currentGrid_.size.width - 1, cursorY - 1);
        } else if (aLine[currentGrid_.size.width].code == EOL_DWC) {
            currentGrid_.cursor = VT100GridCoordMake(currentGrid_.size.width - 2, cursorY - 1);
        }
    }
}

- (void)appendTabAtCursor
{
    // TODO: respect left-right margins
    if (![self haveTabStopBefore:currentGrid_.size.width + 1]) {
        // No legal tabstop so stop; otherwise the for loop would never exit.
        return;
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
        if ([self haveTabStopAt:currentGrid_.cursorX]) {
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

- (void)clearScreen
{
    [currentGrid_ moveWrappedCursorLineToTopOfGrid];
    [currentGrid_ setCharsFrom:VT100GridCoordMake(0, currentGrid_.cursor.y + 1)
                            to:VT100GridCoordMake(currentGrid_.size.width - 1,
                                                  currentGrid_.size.height - 1)
                        toChar:[currentGrid_ defaultChar]];
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

- (void)carriageReturn
{
    [currentGrid_ moveCursorToLeftMargin];
}

- (void)saveCursorPosition
{
    [currentGrid_ clampCursorPositionToValid];
    currentGrid_.savedCursor = currentGrid_.cursor;

    for (int i = 0; i < 4; i++) {
        savedCharsetUsesLineDrawingMode_[i] = charsetUsesLineDrawingMode_[i];
    }
}

- (void)restoreCursorPosition
{
    currentGrid_.cursor = currentGrid_.savedCursor;

    for (int i = 0; i < 4; i++) {
        charsetUsesLineDrawingMode_[i] = savedCharsetUsesLineDrawingMode_[i];
    }

    NSParameterAssert(currentGrid_.cursorX >= 0 && currentGrid_.cursorX < currentGrid_.size.width);
    NSParameterAssert(currentGrid_.cursorY >= 0 && currentGrid_.cursorY < currentGrid_.size.height);
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
    for (NSData *chars in history) {
        screen_char_t *line = (screen_char_t *) [chars bytes];
        const int len = [chars length] / sizeof(screen_char_t);
        [temp appendLine:line
                  length:len
                 partial:NO
                   width:currentGrid_.size.width];
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
                          width:currentGrid_.size.width];
    }
    if (!unlimitedScrollback_) {
        [linebuffer_ dropExcessLinesWithWidth:currentGrid_.size.width];
    }

    // We don't know the cursor position yet but give the linebuffer something
    // so it doesn't get confused in restoreScreenFromScrollback.
    [linebuffer_ setCursor:0];
    [currentGrid_ restoreScreenFromLineBuffer:linebuffer_
                              withDefaultChar:[currentGrid_ defaultChar]
                            maxLinesToRestore:[linebuffer_ numLinesWithWidth:currentGrid_.size.width]];
}

- (void)setAltScreen:(NSArray *)lines
{
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
    int savedGrid = [[self objectInDictionary:state
                             withFirstKeyFrom:[NSArray arrayWithObjects:kStateDictSavedGrid,
                                               kStateDictInAlternateScreen,
                                               nil]] intValue];
    if (!savedGrid && altGrid_) {
        [altGrid_ release];
        altGrid_ = nil;
    }
    // TODO(georgen): Get the alt screen contents and fill altGrid.

    int scx = [[self objectInDictionary:state
                       withFirstKeyFrom:[NSArray arrayWithObjects:kStateDictSavedCX,
                                         kStateDictBaseCursorX,
                                         nil]] intValue];
    int scy = [[self objectInDictionary:state
                       withFirstKeyFrom:[NSArray arrayWithObjects:kStateDictSavedCY,
                                         kStateDictBaseCursorY,
                                         nil]] intValue];
    primaryGrid_.savedCursor = VT100GridCoordMake(scx, scy);

    primaryGrid_.cursorX = [[state objectForKey:kStateDictCursorX] intValue];
    primaryGrid_.cursorY = [[state objectForKey:kStateDictCursorY] intValue];
    int top = [[state objectForKey:kStateDictScrollRegionUpper] intValue];
    int bottom = [[state objectForKey:kStateDictScrollRegionLower] intValue];
    primaryGrid_.scrollRegionRows = VT100GridRangeMake(top, bottom - top + 1);
    [self showCursor:[[state objectForKey:kStateDictCursorMode] boolValue]];

    [tabStops removeAllObjects];
    int maxTab = 0;
    for (NSNumber *n in [state objectForKey:kStateDictTabstops]) {
        [tabStops addObject:n];
        maxTab = MAX(maxTab, [n intValue]);
    }
    for (int i = 0; i < 1000; i += 8) {
        if (i > maxTab) {
            [tabStops addObject:[NSNumber numberWithInt:i]];
        }
    }

    // TODO: The way that tmux and iterm2 handle saving the cursor position is different and incompatible and only one of us is right.
    // tmux saves the cursor position for DECSC in one location and for the non-alt screen in a separate location.
    // iterm2 saves the cursor position for the base screen in one location and for the alternate screen in another location.
    // At a minimum, we differ in how we handle DECSC.
    // After resolving this confusion, do the right thing with these state fields:
    // kStateDictDECSCCursorX;
    // kStateDictDECSCCursorY;
}

- (void)markAsNeedingCompleteRedraw {
    [currentGrid_ markAllCharsDirty:YES];
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

- (void)disableDvr
{
    [dvr release];
    dvr = nil;
}

- (void)setFromFrame:(screen_char_t*)s len:(int)len info:(DVRFrameInfo)info
{
    assert(len == info.width * info.height * sizeof(screen_char_t));
    [currentGrid_ setContentsFromDVRFrame:s info:info];
    [self resetScrollbackOverflow];
    savedFindContextAbsPos_ = 0;
    [delegate_ screenRemoveSelection];
    [currentGrid_ markAllCharsDirty:YES];
}

- (void)saveTerminalAbsPos
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
    context->hasWrapped = YES;

    float MAX_TIME = 0.1;
    NSDate* start = [NSDate date];
    BOOL keepSearching;
    context->hasWrapped = YES;
    do {
        keepSearching = [self continueFindResultsInContext:context
                                                   maxTime:0.1
                                                   toArray:results];
    } while (keepSearching &&
             [[NSDate date] timeIntervalSinceDate:start] < MAX_TIME);

    return keepSearching;
}

- (FindContext*)findContext
{
    return &findContext_;
}

- (void)cancelFindInContext:(FindContext*)context
{
    [linebuffer_ releaseFind:context];
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
    int startPos;
    BOOL isOk = [linebuffer_ convertCoordinatesAtX:x
                                               atY:y
                                         withWidth:currentGrid_.size.width
                                        toPosition:&startPos
                                            offset:offset * (direction ? 1 : -1)];
    if (!isOk) {
        // NSLog(@"Couldn't convert %d,%d to position", x, y);
        if (direction) {
            startPos = [linebuffer_ firstPos];
        } else {
            startPos = [linebuffer_ lastPos] - 1;
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
    [linebuffer_ initFind:aString startingAt:startPos options:opts withContext:context];
    context->hasWrapped = NO;
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
    [currentGrid_ markCharDirty:YES at:VT100GridCoordMake(xToMark, yToMark)];
    [self setCharDirtyAtX:xToMark Y:yToMark];
    if (xToMark < currentGrid_.size.width - 1) {
        // Just in case the cursor was over a double width character
        [currentGrid_ markCharDirty:YES at:VT100GridCoordMake(xToMark + 1, yToMark)];
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
    if (!dvr || ![[PreferencePanel sharedInstance] instantReplay]) {
        return;
    }

    DVRFrameInfo info;
    info.cursorX = currentGrid_.cursorX;
    info.cursorY = currentGrid_.cursorY;
    info.height = currentGrid_.size.height;
    info.width = currentGrid_.size.width;

    [dvr appendFrame:currentGrid_.lines
              length:sizeof(screen_char_t) * (currentGrid_.size.width + 1) * (currentGrid_.size.height)
                info:&info];
}

- (BOOL)shouldSendContentsChangedNotification
{
    return [[iTermExpose sharedInstance] isVisible] ||
    [delegate_ screenShouldSendContentsChangedNotification];
}

#pragma mark - Private

- (void)setInitialTabStops
{
    [self clearTabStop];
    const int kInitialTabWindow = 1000;
    for (int i = 0; i < kInitialTabWindow; i += kDefaultTabstopWidth) {
        [tabStops addObject:[NSNumber numberWithInt:i]];
    }
}

- (BOOL)isAnyCharDirty
{
    return [currentGrid_ isAnyCharDirty];
}

- (void)setCharDirtyAtX:(int)x Y:(int)y {
    [currentGrid_ markCharDirty:YES at:VT100GridCoordMake(x, y)];
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

    screen_char_t fg;
    screen_char_t bg;

    fg.foregroundColor = bgColorCode;
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
// is still the "old" height.
- (void)appendScreen:(VT100Grid *)grid
        toScrollback:(LineBuffer *)lineBufferToUse
      withUsedHeight:(int)usedHeight
           newHeight:(int)newHeight
{
    if (grid.size.height - newHeight >= usedHeight) {
        // Height is decreasing but pushing HEIGHT lines into the buffer would scroll all the used
        // lines off the top, leaving the cursor floating without any text. Keep all used lines that
        // fit onscreen.
        [grid appendLines:MAX(usedHeight, newHeight) toLineBuffer:lineBufferToUse];
    } else {
        if (newHeight < grid.size.height) {
            // Screen is shrinking.
            // If possible, keep the last used line a fixed distance from the top of
            // the screen. If not, at least save all the used lines.
            [grid appendLines:usedHeight toLineBuffer:lineBufferToUse];
        } else {
            // Screen is growing. New content may be brought in on top.
            [grid appendLines:currentGrid_.size.height toLineBuffer:lineBufferToUse];
        }
    }
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

- (void)convertSelectionStartX:(int)actualStartX
                        startY:(int)actualStartY
                          endX:(int)actualEndX
                          endY:(int)actualEndY
                    toNonNullX:(int *)nonNullStartX
                    toNonNullY:(int *)nonNullStartY
                    toNonNullX:(int *)nonNullEndX
                    toNonNullY:(int *)nonNullEndY
{
    assert(actualStartX >= 0);
    assert(actualEndX >= 0);
    assert(actualStartY >= 0);
    assert(actualEndY >= 0);

    if (!XYIsBeforeXY(actualStartX, actualStartY, actualEndX, actualEndY)) {
        SwapInt(&actualStartX, &actualEndX);
        SwapInt(&actualStartY, &actualEndY);
    }

    // Advance start position until it hits a non-null or equals the end position.
    int startX = actualStartX;
    int startY = actualStartY;
    if (startX == currentGrid_.size.width) {
        startX = 0;
        startY++;
    }

    int endX = actualEndX;
    int endY = actualEndY;
    if (endX == currentGrid_.size.width) {
        endX = 0;
        endY++;
    }

    VT100GridRun run = VT100GridRunFromCoords(VT100GridCoordMake(startX, startY),
                                              VT100GridCoordMake(endX, endY),
                                              currentGrid_.size.width);
    assert(run.length >= 0);
    run = [currentGrid_ runByTrimmingNullsFromRun:run];
    assert(run.length >= 0);
    VT100GridCoord max = VT100GridRunMax(run, currentGrid_.size.width);

    *nonNullStartX = run.origin.x;
    *nonNullStartY = run.origin.y;
    *nonNullEndX = max.x;
    *nonNullEndY = max.y;
}

- (BOOL)getNullCorrectedSelectionStartPosition:(int *)startPos
                                   endPosition:(int *)endPos
                           isFullLineSelection:(BOOL *)isFullLineSelection
                 selectionStartPositionIsValid:(BOOL *)selectionStartPositionIsValid
                    selectionEndPostionIsValid:(BOOL *)selectionEndPostionIsValid
{
    *startPos = -1;
    *endPos = -1;

    int actualStartX = [delegate_ screenSelectionStartX];
    int actualStartY = [delegate_ screenSelectionStartY];
    int actualEndX = [delegate_ screenSelectionEndX];
    int actualEndY = [delegate_ screenSelectionEndY];

    int nonNullStartX;
    int nonNullStartY;
    int nonNullEndX;
    int nonNullEndY;
    [self convertSelectionStartX:actualStartX
                          startY:actualStartY
                            endX:actualEndX
                            endY:actualEndY
                      toNonNullX:&nonNullStartX
                      toNonNullY:&nonNullStartY
                      toNonNullX:&nonNullEndX
                      toNonNullY:&nonNullEndY];
    BOOL endsAfterStart = XYIsBeforeXY(nonNullStartX, nonNullStartY, nonNullEndX, nonNullEndY);
    if (!endsAfterStart) {
        return NO;
    }
    if (isFullLineSelection) {
        if (actualStartX == 0 && actualEndX == currentGrid_.size.width) {
            *isFullLineSelection = YES;
        } else {
            *isFullLineSelection = NO;
        }
    }
    BOOL v;
    v = [linebuffer_ convertCoordinatesAtX:nonNullStartX
                                       atY:nonNullStartY
                                 withWidth:currentGrid_.size.width
                                toPosition:startPos
                                    offset:0];
    if (selectionStartPositionIsValid) {
        *selectionStartPositionIsValid = v;
    }
    v = [linebuffer_ convertCoordinatesAtX:nonNullEndX
                                       atY:nonNullEndY
                                 withWidth:currentGrid_.size.width
                                toPosition:endPos
                                    offset:0];
    if (selectionEndPostionIsValid) {
        *selectionEndPostionIsValid = v;
    }
    return YES;
}

- (BOOL)convertCurrentSelectionToWidth:(int)newWidth
                           toNewStartX:(int *)newStartXPtr
                           toNewStartY:(int *)newStartYPtr
                             toNewEndX:(int *)newEndXPtr
                             toNewEndY:(int *)newEndYPtr
                 toIsFullLineSelection:(BOOL *)isFullLineSelection
{
    int selectionStartPosition;
    int selectionEndPosition;
    BOOL selectionStartPositionIsValid;
    BOOL selectionEndPostionIsValid;
    BOOL hasSelection = [self getNullCorrectedSelectionStartPosition:&selectionStartPosition
                                                         endPosition:&selectionEndPosition
                                                 isFullLineSelection:isFullLineSelection
                                       selectionStartPositionIsValid:&selectionStartPositionIsValid
                                          selectionEndPostionIsValid:&selectionEndPostionIsValid];

    if (!hasSelection) {
        return NO;
    }
    if (selectionStartPositionIsValid) {
        [linebuffer_ convertPosition:selectionStartPosition
                           withWidth:newWidth
                                 toX:newStartXPtr
                                 toY:newStartYPtr];
        if (selectionEndPostionIsValid) {
            [linebuffer_ convertPosition:selectionEndPosition
                               withWidth:newWidth
                                     toX:newEndXPtr
                                     toY:newEndYPtr];
        } else {
            *newEndXPtr = currentGrid_.size.width;
            *newEndYPtr = [linebuffer_ numLinesWithWidth:newWidth] + currentGrid_.size.height - 1;
        }
    }
    return YES;
}

- (void)incrementOverflowBy:(int)overflowCount {
    scrollbackOverflow_ += overflowCount;
    cumulativeScrollbackOverflow_ += overflowCount;
}

- (void)resetScreen
{
    [delegate_ screenTriggerableChangeDidOccur];
    [self incrementOverflowBy:[currentGrid_ resetWithLineBuffer:linebuffer_
                                            unlimitedScrollback:unlimitedScrollback_]];
    [self clearScreen];
    [self setInitialTabStops];
    altGrid_.savedCursor = VT100GridCoordMake(0, 0);

    for (int i = 0; i < 4; i++) {
        savedCharsetUsesLineDrawingMode_[i] = charsetUsesLineDrawingMode_[i] = 0;
    }

    [self showCursor:YES];
}

- (void)reset
{
    [self resetPreservingPrompt:NO];
}

// sets scrollback lines.
- (void)setMaxScrollbackLines:(unsigned int)lines;
{
    maxScrollbackLines_ = lines;
    [linebuffer_ setMaxLines: lines];
    if (!unlimitedScrollback_) {
        [linebuffer_ dropExcessLinesWithWidth:currentGrid_.size.width];
    }
}

- (void)processXtermPaste64:(NSString *)commandString
{
    //
    // - write access
    //   ESC ] 5 2 ; Pc ; <base64 encoded string> ST
    //
    // - read access
    //   ESC ] 5 2 ; Pc ; ? ST
    //
    // Pc consists from:
    //   'p', 's', 'c', '0', '1', '2', '3', '4', '5', '6', '7'
    //
    // Note: Pc is ignored now.
    //
    const char *buffer = [commandString UTF8String];

    // ignore first parameter now
    while (strchr("psc01234567", *buffer)) {
        ++buffer;
    }
    if (*buffer != ';') {
        return; // fail to parse
    }
    ++buffer;    
    if (*buffer == '?') { // PASTE64(OSC 52) read access
        // Now read access is not implemented due to security issues.
    } else { // PASTE64(OSC 52) write access
        // check the configuration
        if (![[PreferencePanel sharedInstance] allowClipboardAccess]) {
            return;
        }
        // decode base64 string.
        int destLength = apr_base64_decode_len(buffer);
        if (destLength < 1) {
            return;
        }        
        NSMutableData *data = [NSMutableData dataWithLength:destLength];
        char *decodedBuffer = [data mutableBytes];
        int resultLength = apr_base64_decode(decodedBuffer, buffer);
        if (resultLength < 0) {
            return;
        }

        // sanitize buffer
        const char *inputIterator = decodedBuffer;
        char *outputIterator = decodedBuffer;
        int outputLength = 0;
        for (int i = 0; i < resultLength + 1; ++i) {
            char c = *inputIterator;
            if (c == 0x00) {
                *outputIterator = 0x00; // terminate string with NULL
                break;
            }
            if (c > 0x00 && c < 0x20) { // if c is control character
                // check if c is TAB/LF/CR
                if (c != 0x09 && c != 0x0a && c != 0x0d) {
                    // skip it
                    ++inputIterator;
                    continue;
                }
            }
            *outputIterator = c;
            ++inputIterator;
            ++outputIterator;
            ++outputLength;
        }
        [data setLength:outputLength];

        NSString *resultString = [[[NSString alloc] initWithData:data
                                                        encoding:[terminal_ encoding]] autorelease];
        // set the result to paste board.
        NSPasteboard* thePasteboard = [NSPasteboard generalPasteboard];
        [thePasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
        [thePasteboard setString:resultString forType:NSStringPboardType];
    }
}

// Should the profile name be inculded in the window/tab title? Requires both
// a per-profile option to be on as well as the global option.
- (BOOL)syncTitle
{
    if (![[PreferencePanel sharedInstance] showBookmarkName]) {
        return NO;
    }
    return [delegate_ screenShouldSyncTitle];
}

- (BOOL)useScrollbackWithRegion
{
    return [delegate_ screenShouldAppendToScrollbackWithStatusBar];
}

- (void)backTab
{
    // TODO: take a number argument
    // TODO: respect left-right margins
    while (![self haveTabStopAt:currentGrid_.cursorX] && currentGrid_.cursorX > 0) {
        currentGrid_.cursorX = currentGrid_.cursorX - 1;
    }
}

- (void)advanceCursor:(BOOL)canOccupyLastSpace
{
    // TODO: respect left-right margins
    int cursorX = currentGrid_.cursorX + 1;
    if (canOccupyLastSpace) {
        if (cursorX > currentGrid_.size.width) {
            cursorX = currentGrid_.size.width;
            screen_char_t* aLine = [currentGrid_ screenCharsAtLineNumber:currentGrid_.cursorY];
            aLine[currentGrid_.size.width].code = EOL_SOFT;
            [self linefeed];
            cursorX = 0;
        }
    } else if (cursorX >= currentGrid_.size.width) {
        cursorX = currentGrid_.size.width;
        [self linefeed];
        cursorX = 0;
    }
    currentGrid_.cursorX = cursorX;
}

- (BOOL)haveTabStopBefore:(int)limit {
    for (NSNumber *number in tabStops) {
        if ([number intValue] < limit) {
            return YES;
        }
    }
    return NO;
}

- (void)eraseInDisplay:(VT100TCC)token
{
    int x1, yStart, x2, y2;
    int i;

    switch (token.u.csi.p[0]) {
    case 1:
        x1 = 0;
        yStart = 0;
        x2 = currentGrid_.cursor.x < currentGrid_.size.width ? currentGrid_.cursor.x + 1 : currentGrid_.size.width;
        y2 = currentGrid_.cursor.y;
        break;

    case 2:
        [currentGrid_ scrollWholeScreenUpIntoLineBuffer:linebuffer_
                                    unlimitedScrollback:unlimitedScrollback_];
        x1 = 0;
        yStart = 0;
        x2 = 0;
        y2 = currentGrid_.size.height;
        break;

    case 0:
    default:
        x1 = currentGrid_.cursor.x;
        yStart = currentGrid_.cursor.y;
        x2 = 0;
        y2 = currentGrid_.size.height;
        break;
    }

    VT100GridRun theRun = VT100GridRunFromCoords(VT100GridCoordMake(x1, yStart),
                                                 VT100GridCoordMake(x2, y2),
                                                 currentGrid_.size.width);
    [currentGrid_ setCharsInRun:theRun
                        toChar:0];
    DebugLog(@"eraseInDisplay");
}

- (void)eraseInLine:(VT100TCC)token
{
    int x1 ,x2;

    x1 = x2 = 0;
    switch (token.u.csi.p[0]) {
        case 1:
            x1 = 0;
            x2 = currentGrid_.cursor.x < currentGrid_.size.width ? currentGrid_.cursor.x + 1 : currentGrid_.size.width;
            break;
        case 2:
            x1 = 0;
            x2 = currentGrid_.size.width;
            break;
        case 0:
            x1 = currentGrid_.cursor.x;
            x2 = currentGrid_.size.width;
            break;
    }

    VT100GridRun theRun = VT100GridRunFromCoords(VT100GridCoordMake(x1, currentGrid_.cursor.y),
                                                 VT100GridCoordMake(x2, currentGrid_.cursor.y),
                                                 currentGrid_.size.width);
    [currentGrid_ setCharsInRun:theRun
                         toChar:0];
    DebugLog(@"eraseInLine");
}

- (void)selectGraphicRendition:(VT100TCC)token
{
}

- (void)cursorLeft:(int)n
{
    [currentGrid_ moveCursorLeft:(n > 0 ? n : 1)];
    DebugLog(@"cursorLeft");
}

- (void)cursorRight:(int)n
{
    [currentGrid_ moveCursorRight:(n > 0 ? n : 1)];
    DebugLog(@"cursorRight");
}

- (void)cursorUp:(int)n
{
    [currentGrid_ moveCursorUp:(n > 0 ? n : 1)];
    DebugLog(@"cursorUp");
}

- (void)cursorDown:(int)n
{
    [currentGrid_ moveCursorDown:(n > 0 ? n : 1)];
    DebugLog(@"cursorDown");
}

- (void)cursorToY:(int)y
{
    int yPos;
    int topMargin = currentGrid_.topMargin;
    int bottomMargin = currentGrid_.bottomMargin;

    yPos = y - 1;

    if ([terminal_ originMode]) {
        yPos += topMargin;
        yPos = MIN(topMargin, MAX(bottomMargin, yPos));
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

- (void)setTopBottom:(VT100TCC)token
{
    int top;
    int bottom;

    top = token.u.csi.p[0] == 0 ? 0 : token.u.csi.p[0] - 1;
    bottom = token.u.csi.p[1] == 0 ? currentGrid_.size.height - 1 : token.u.csi.p[1] - 1;
    if (top >= 0 &&
        top < currentGrid_.size.height &&
        bottom >= 0 &&
        bottom < currentGrid_.size.height &&
        bottom >= top) {
        assert(bottom < currentGrid_.size.height);
        currentGrid_.scrollRegionRows = VT100GridRangeMake(top, bottom - top + 1);

        if ([terminal_ originMode]) {
            currentGrid_.cursor = VT100GridCoordMake(currentGrid_.leftMargin,
                                                     currentGrid_.topMargin);
        } else {
            currentGrid_.cursor = VT100GridCoordMake(0, 0);
        }
    }
}

- (void)deleteLines:(int)n
{
    int i, num_lines_moved;
    screen_char_t *sourceLine, *targetLine, *aDefaultLine;

    if (n + currentGrid_.cursorY <= currentGrid_.bottomMargin) {
        // number of lines we can move down by n before we hit SCROLL_BOTTOM
        num_lines_moved = currentGrid_.bottomMargin - (currentGrid_.cursorY + n);
        [currentGrid_ scrollRect:VT100GridRectMake(currentGrid_.leftMargin,
                                                   currentGrid_.cursorY,
                                                   currentGrid_.rightMargin - currentGrid_.leftMargin + 1,
                                                   currentGrid_.cursorY + num_lines_moved + n)
                          downBy:-n];
    }
    DebugLog(@"deleteLines");
    
}

- (void)deviceReport:(VT100TCC)token withQuestion:(BOOL)question
{
    NSData *report = nil;

    if (shell_ == nil) {
        return;
    }

    switch (token.u.csi.p[0]) {
        case 3: // response from VT100 -- Malfunction -- retry
            break;

        case 5: // Command from host -- Please report status
            report = [terminal_ reportStatus];
            break;

        case 6: // Command from host -- Please report active position
        {
            int x, y;

            if ([terminal_ originMode]) {
                x = currentGrid_.cursorX - currentGrid_.leftMargin + 1;
                y = currentGrid_.cursorY - currentGrid_.topMargin + 1;
            }
            else {
                x = currentGrid_.cursorX + 1;
                y = currentGrid_.cursorY + 1;
            }
            report = [terminal_ reportActivePositionWithX:x Y:y withQuestion:question];
        }
            break;

        case 0: // Response from VT100 -- Ready, No malfuctions detected
        default:
            break;
    }

    if (report != nil) {
        [delegate_ screenWriteDataToTask:report];
    }
}

- (void)deviceAttribute:(VT100TCC)token
{
    NSData *report = nil;

    if (shell_ == nil) {
        return;
    }

    report = [terminal_ reportDeviceAttribute];

    if (report != nil) {
        [delegate_ screenWriteDataToTask:report];
    }
}

- (void)secondaryDeviceAttribute:(VT100TCC)token
{
    NSData *report = nil;

    if (shell_ == nil) {
        return;
    }

    report = [terminal_ reportSecondaryDeviceAttribute];

    if (report != nil) {
        [delegate_ screenWriteDataToTask:report];
    }
}

- (void)setVsplitMode:(BOOL)mode;
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

- (void)clearTabStop
{
    [tabStops removeAllObjects];
}

- (BOOL)haveTabStopAt:(int)x
{
    return [tabStops containsObject:[NSNumber numberWithInt:x]];
}

- (void)setTabStopAt:(int)x
{
    [tabStops addObject:[NSNumber numberWithInt:x]];
}

- (void)removeTabStopAt:(int)x
{
    [tabStops removeObject:[NSNumber numberWithInt:x]];
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
                                      includesEndOfLine:&cont];
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
                             maxTime:(float)maxTime
                             toArray:(NSMutableArray*)results
{
    // Append the screen contents to the scrollback buffer so they are included in the search.
    int linesPushed;
    linesPushed = [currentGrid_ appendLines:[currentGrid_ numberOfLinesUsed]
                               toLineBuffer:linebuffer_];

    // Search one block.
    int stopAt;
    if (context->dir > 0) {
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
        if (context->status == Searching) {
            [linebuffer_ findSubstring:context stopAt:stopAt];
        }

        // Handle the current state
        switch (context->status) {
            case Matched: {
                // NSLog(@"matched");
                // Found a match in the text.
                NSArray *allPositions = [linebuffer_ convertPositions:context->results
                                                            withWidth:currentGrid_.size.width];
                int k = 0;
                for (ResultRange* currentResultRange in context->results) {
                    SearchResult* result = [[SearchResult alloc] init];

                    XYRange* xyrange = [allPositions objectAtIndex:k++];

                    result->startX = xyrange->xStart;
                    result->endX = xyrange->xEnd;
                    result->absStartY = xyrange->yStart + [self totalScrollbackOverflow];
                    result->absEndY = xyrange->yEnd + [self totalScrollbackOverflow];

                    [results addObject:result];
                    [result release];
                    if (!(context->options & FindMultipleResults)) {
                        assert([context->results count] == 1);
                        [linebuffer_ releaseFind:context];
                        keepSearching = NO;
                    } else {
                        keepSearching = YES;
                    }
                }
                [context->results removeAllObjects];
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
                if (context->hasWrapped) {
                    [linebuffer_ releaseFind:context];
                    keepSearching = NO;
                } else {
                    // NSLog(@"...wrapping");
                    // wrap around and resume search.
                    FindContext temp;
                    [linebuffer_ initFind:findContext_.substring
                               startingAt:(findContext_.dir > 0 ? [linebuffer_ firstPos] : [linebuffer_ lastPos]-1)
                                  options:findContext_.options
                              withContext:&temp];
                    [linebuffer_ releaseFind:&findContext_];
                    *context = temp;
                    context->hasWrapped = YES;
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
            context->status = Searching;
        }
        ++iterations;
    } while (keepSearching && ms_diff < maxTime*1000);
    // NSLog(@"Did %d iterations in %dms. Average time per block was %dms", iterations, ms_diff, ms_diff/iterations);

    [self popScrollbackLines:linesPushed];
    return keepSearching;
}

- (BOOL)continueFindResultAtStartX:(int*)startX
                          atStartY:(int*)startY
                            atEndX:(int*)endX
                            atEndY:(int*)endY
                             found:(BOOL*)found
                         inContext:(FindContext*)context
{
    NSMutableArray* myArray = [NSMutableArray arrayWithCapacity:1];
    BOOL rc = [self continueFindResultsInContext:context
                                         maxTime:kMaxTimeToSearch
                                         toArray:myArray];
    if ([myArray count] > 0) {
        SearchResult* result = [myArray objectAtIndex:0];
        *startX = result->startX;
        *startY = result->absStartY - [self totalScrollbackOverflow];
        *endX = result->endX;
        *endY = result->absEndY - [self totalScrollbackOverflow];
        *found = YES;
    } else {
        *found = NO;
    }
    return rc;
}

@end

