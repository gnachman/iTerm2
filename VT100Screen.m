#import "VT100Screen.h"

#import "DebugLogging.h"
#import "DVR.h"
#import "PTYTextView.h"
#import "RegexKitLite.h"
#import "SearchResult.h"
#import "TmuxStateParser.h"
#import "iTermExpose.h"
#import "iTermGrowlDelegate.h"

#include <string.h>
#include <unistd.h>

int kVT100ScreenMinColumns = 2;
int kVT100ScreenMinRows = 2;

static const int kMaxLinesToScrollAtOneTime = 1024;  // Prevents DOS by XTERMCC_SU/XTERMCC_SD

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
        tabStops_ = [[NSMutableSet alloc] init];
        [self setInitialTabStops];
        linebuffer_ = [[LineBuffer alloc] init];

        [iTermGrowlDelegate sharedInstance];

        dvr_ = [DVR alloc];
        [dvr_ initWithBufferCapacity:[[PreferencePanel sharedInstance] irMemory] * 1024 * 1024];
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
    width = MAX(width, kVT100ScreenMinColumns);
    height = MAX(height, kVT100ScreenMinRows);

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
    [charsetUsesLineDrawingMode_ removeAllObjects];
    for (int i = 0; i < NUM_CHARSETS; i++) {
        [charsetUsesLineDrawingMode_ addObject:[NSNumber numberWithBool:NO]];
    }
}

- (BOOL)usingDefaultCharset {
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

    // TODO: The way that tmux and iterm2 handle saving the cursor position is different and incompatible and only one of us is right.
    // tmux saves the cursor position for DECSC in one location and for the non-alt screen in a separate location.
    // iterm2 saves the cursor position for the base screen in one location and for the alternate screen in another location.
    // At a minimum, we differ in how we handle DECSC.
    // After resolving this confusion, do the right thing with these state fields:
    // kStateDictDECSCCursorX;
    // kStateDictDECSCCursorY;
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
    if (!dvr_ || ![[PreferencePanel sharedInstance] instantReplay]) {
        return;
    }

    DVRFrameInfo info;
    info.cursorX = currentGrid_.cursorX;
    info.cursorY = currentGrid_.cursorY;
    info.height = currentGrid_.size.height;
    info.width = currentGrid_.size.width;

    [dvr_ appendFrame:currentGrid_.lines
               length:sizeof(screen_char_t) * (currentGrid_.size.width + 1) * (currentGrid_.size.height)
                 info:&info];
}

- (BOOL)shouldSendContentsChangedNotification
{
    return [[iTermExpose sharedInstance] isVisible] ||
    [delegate_ screenShouldSendContentsChangedNotification];
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

- (void)terminalAppendTabAtCursor
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
    return shell_ != nil;
}

- (void)terminalSendReport:(NSData *)report
{
    if (shell_ && report) {
        [delegate_ screenWriteDataToTask:report];
    }
}

- (void)terminalShowTestPattern
{
    screen_char_t ch = [currentGrid_ defaultChar];
    ch.code = 'E';
    [currentGrid_ setCharsFrom:VT100GridCoordMake(0, 0)
                            to:VT100GridCoordMake(currentGrid_.size.width - 1, currentGrid_.size.height - 1)
                        toChar:ch];
    [currentGrid_ resetScrollRegions];
    currentGrid_.cursor = VT100GridCoordMake(0, 0);
}

- (void)terminalRestoreCursorAndCharsetFlags
{
    currentGrid_.cursor = currentGrid_.savedCursor;
    [charsetUsesLineDrawingMode_ removeAllObjects];
    [charsetUsesLineDrawingMode_ addObjectsFromArray:savedCharsetUsesLineDrawingMode_];

    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalSaveCursorAndCharsetFlags
{
    [currentGrid_ clampCursorPositionToValid];
    currentGrid_.savedCursor = currentGrid_.cursor;
    [savedCharsetUsesLineDrawingMode_ removeAllObjects];
    [savedCharsetUsesLineDrawingMode_ addObjectsFromArray:charsetUsesLineDrawingMode_];
}

- (int)terminalRelativeCursorX {
    return currentGrid_.cursorX - currentGrid_.leftMargin + 1;
}

- (int)terminalRelativeCursorY {
    return currentGrid_.cursorY - currentGrid_.topMargin + 1;
}

- (void)terminalResetTopBottomScrollRegion
{
    [self terminalSetScrollRegionTop:0 bottom:[self height] - 1];
}

- (void)terminalSetScrollRegionTop:(int)top bottom:(int)bottom
{
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

- (void)terminalEraseInDisplayBeforeCursor:(BOOL)before afterCursor:(BOOL)after
{
    int x1, yStart, x2, y2;

    if (before && after) {
        [currentGrid_ scrollWholeScreenUpIntoLineBuffer:linebuffer_
                                    unlimitedScrollback:unlimitedScrollback_];
        x1 = 0;
        yStart = 0;
        x2 = 0;
        y2 = currentGrid_.size.height;
    } else if (before) {
        x1 = 0;
        yStart = 0;
        x2 = currentGrid_.cursor.x < currentGrid_.size.width ? currentGrid_.cursor.x + 1 : currentGrid_.size.width;
        y2 = currentGrid_.cursor.y;
    } else if (after) {
        x1 = currentGrid_.cursor.x;
        yStart = currentGrid_.cursor.y;
        x2 = 0;
        y2 = currentGrid_.size.height;
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
        x2 = currentGrid_.size.width;
    } else if (before) {
        x1 = 0;
        x2 = MIN(currentGrid_.cursor.x + 1, currentGrid_.size.width);  // TODO: Why x+1?
    } else if (after) {
        x1 = currentGrid_.cursor.x;
        x2 = currentGrid_.size.width;
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
    [currentGrid_ moveCursorToLeftMargin];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalIndex {
    if (currentGrid_.cursorY == currentGrid_.bottomMargin) {
        [self incrementOverflowBy:[currentGrid_ scrollUpIntoLineBuffer:linebuffer_
                                                   unlimitedScrollback:unlimitedScrollback_
                                               useScrollbackWithRegion:[self useScrollbackWithRegion]]];
    } else {
        currentGrid_.cursorY = currentGrid_.cursorY + 1;
    }
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalReverseIndex {
    if (currentGrid_.cursorY == currentGrid_.topMargin) {
        [currentGrid_ scrollDown];
    } else {
        currentGrid_.cursorY = currentGrid_.cursorY - 1;
    }
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalResetPreservingPrompt:(BOOL)preservePrompt {
    [self resetPreservingPrompt:preservePrompt];
}

- (void)terminalSoftReset {
    // See note in xterm-terminfo.txt (search for DECSTR).

    // save cursor (fixes origin-mode side-effect)
    [self terminalSaveCursorAndCharsetFlags];

    // reset scrolling margins
    [self terminalResetTopBottomScrollRegion];

    // reset SGR (done in VT100Terminal)
    // reset wraparound mode (done in VT100Terminal)
    // reset application cursor keys (done in VT100Terminal)
    // reset origin mode (done in VT100Terminal)
    // restore cursor
    [self terminalRestoreCursorAndCharsetFlags];
}

- (void)terminalSetCursorType:(ITermCursorType)cursorType {
    [delegate_ screenSetCursorType:cursorType];
}

- (void)terminalSetCursorBlinking:(BOOL)blinking {
    [delegate_ screenSetCursorBlinking:blinking];
}

- (void)terminalSetLeftMargin:(int)scrollLeft rightMargin:(int)scrollRight {
    currentGrid_.scrollRegionCols = VT100GridRangeMake(scrollLeft,
                                                       scrollRight - scrollLeft + 1);
    // set cursor to the home position
    [self cursorToX:1 Y:1];
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
    if (![delegate_ screenShouldInitiateWindowResize]) {
        // set the column
        [delegate_ screenResizeToWidth:width
                                height:currentGrid_.size.height];
        [self terminalEraseInDisplayBeforeCursor:NO afterCursor:YES];  // erase the screen
        [self terminalResetTopBottomScrollRegion];
        [self setUseColumnScrollRegion:NO];
    }
}

- (void)terminalBackTab
{
    // TODO: take a number argument
    // TODO: respect left-right margins
    while (![self haveTabStopAt:currentGrid_.cursorX] && currentGrid_.cursorX > 0) {
        currentGrid_.cursorX = currentGrid_.cursorX - 1;
    }
    [delegate_ screenTriggerableChangeDidOccur];
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
    if ([delegate_ screenShouldBeginPrinting]) {
        [self doPrint];  // TODO: I think this does the wrong thing if the buffer is empty (it prints the screen)
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
    if ([self syncTitle]) {
        newTitle = [NSString stringWithFormat:@"%@: %@", [delegate_ screenNameExcludingJob], newTitle];
    }
    [delegate_ screenSetWindowTitle:newTitle];
    long long lineNumber = [self absoluteLineNumberOfCursor];
    [delegate_ screenLogWorkingDirectoryAtLine:lineNumber withDirectory:nil];
}

- (void)terminalSetIconTitle:(NSString *)title {
    NSString *newTitle = [[title copy] autorelease];
    if ([self syncTitle]) {
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

- (void)terminalInsertEmptyCharAtCursor:(int)n {
    [currentGrid_ insertChar:[currentGrid_ defaultChar]
                          at:currentGrid_.cursor
                       times:n];
}

- (void)terminalInsertBlankLinesAfterCursor:(int)n {
    // TODO: I think the original code was buggy when the cursor was outside the scroll region.
    [currentGrid_ scrollRect:[currentGrid_ scrollRegionRect]
                      downBy:n];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalDeleteCharactersAtCursor:(int)n {
    [currentGrid_ deleteChars:n startingAt:currentGrid_.cursor];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalDeleteLinesAtCursor:(int)n {
    int num_lines_moved;

    if (n + currentGrid_.cursorY <= currentGrid_.bottomMargin) {
        // number of lines we can move down by n before we hit SCROLL_BOTTOM
        num_lines_moved = currentGrid_.bottomMargin - (currentGrid_.cursorY + n);
        [currentGrid_ scrollRect:VT100GridRectMake(currentGrid_.leftMargin,
                                                   currentGrid_.cursorY,
                                                   currentGrid_.rightMargin - currentGrid_.leftMargin + 1,
                                                   currentGrid_.cursorY + num_lines_moved + n)
                          downBy:-n];
    }
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalSetRows:(int)rows andColumns:(int)columns {
    if ([delegate_ screenShouldInitiateWindowResize] &&
        ![delegate_ screenWindowIsFullscreen]) {
        // set the column
        [delegate_ screenResizeToWidth:columns
                                height:rows];

    }
}

- (void)terminalSetPixelWidth:(int)width height:(int)height {
    if ([delegate_ screenShouldInitiateWindowResize] &&
        ![delegate_ screenWindowIsFullscreen]) {
        // TODO: Only allow this if there is a single session in the tab.
        NSSize cellSize = [delegate_ screenCellSize];
        [delegate_ screenResizeToWidth:width / cellSize.width
                                height:height / cellSize.height];
    }
}

- (void)terminalMoveWindowTopLeftPointTo:(NSPoint)point {
    if ([delegate_ screenShouldInitiateWindowResize] &&
        ![delegate_ screenWindowIsFullscreen]) {
        // TODO: Only allow this if there is a single session in the tab.
        point.y = [[delegate_ screenWindowScreen] frame].size.height - point.y;
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
         i < MIN(MAX(currentGrid_.size.height, kMaxLinesToScrollAtOneTime), n);
         i++) {
        [self incrementOverflowBy:[currentGrid_ scrollUpIntoLineBuffer:linebuffer_
                                                   unlimitedScrollback:unlimitedScrollback_
                                               useScrollbackWithRegion:[self useScrollbackWithRegion]]];
    }
    [delegate_ screenTriggerableChangeDidOccur];
}

- (void)terminalScrollDown:(int)n {
    [currentGrid_ scrollRect:[currentGrid_ scrollRegionRect]
                      downBy:MIN(MAX(currentGrid_.size.height, kMaxLinesToScrollAtOneTime), n)];
    [delegate_ screenTriggerableChangeDidOccur];
}

- (BOOL)terminalWindowIsMiniaturized {
    return [delegate_ screenWindowIsMiniaturized];
}

- (NSPoint)terminalWindowTopLeftPixelCoordinate {
    NSRect frame = [delegate_ screenWindowFrame];
    NSScreen *screen = [delegate_ screenWindowScreen];
    return NSMakePoint(frame.origin.x,
                       [screen frame].size.height - frame.origin.y - frame.size.height);
}

- (int)terminalWindowWidth {
    NSRect frame = [delegate_ screenWindowFrame];
    return frame.size.width;
}

- (int)terminalWindowHeight {
    NSRect frame = [delegate_ screenWindowFrame];
    return frame.size.height;
}

- (int)terminalScreenHeightInCells {
    // TODO: This isn't really right since a window couldn't be made this large given the
    // window decorations.
    NSRect screenSize = [[delegate_ screenWindowScreen] frame];
    //  TODO: WTF do we do with panes here?
    float nch = [delegate_ screenWindowFrame].size.height - [delegate_ screenSize].height;
    NSSize cellSize = [delegate_ screenCellSize];
    return (screenSize.size.height - nch) / cellSize.height;
}

- (int)terminalScreenWidthInCells {
    // TODO: This isn't really right since a window couldn't be made this large given the
    // window decorations.
    NSRect screenSize = [[delegate_ screenWindowScreen] frame];
    //  TODO: WTF do we do with panes here?
    float wch = [delegate_ screenWindowFrame].size.width - [delegate_ screenSize].width;
    NSSize cellSize = [delegate_ screenCellSize];
    return (screenSize.size.width - wch - MARGIN * 2) / cellSize.width;
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
        return [delegate_ screenWindowName];
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
        [[iTermGrowlDelegate sharedInstance]
         growlNotify:NSLocalizedStringFromTableInBundle(@"Alert",
                                                        @"iTerm",
                                                        [NSBundle bundleForClass:[self class]],
                                                        @"Growl Alerts")
         withDescription:[NSString stringWithFormat:@"Session %@ #%d: %@",
                          [delegate_ screenName],
                          [delegate_ screenNumber],
                          message]
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

- (void)terminalShowAltBuffer
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

- (void)terminalShowPrimaryBuffer
{
    currentGrid_ = primaryGrid_;
    [currentGrid_ markAllCharsDirty:YES];
    [delegate_ screenNeedsRedraw];
}

- (void)terminalClearScreen {
    [self clearScreen];
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

- (void)terminalSaveScrollPosition {
    [delegate_ screenSaveScrollPosition];
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

- (void)terminalSetPasteboard:(NSString *)value {
    [delegate_ screenSetPasteboard:value];
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

    [savedCharsetUsesLineDrawingMode_ removeAllObjects];
    [charsetUsesLineDrawingMode_ removeAllObjects];
    for (int i = 0; i < NUM_CHARSETS; i++) {
        [savedCharsetUsesLineDrawingMode_ addObject:[NSNumber numberWithBool:NO]];
        [charsetUsesLineDrawingMode_ addObject:[NSNumber numberWithBool:NO]];
    }

    [self showCursor:YES];
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

