//
//  VT100Grid.m
//  iTerm
//
//  Created by George Nachman on 10/9/13.
//
//

#import "VT100Grid.h"

#import "DebugLogging.h"
#import "iTermEncoderAdapter.h"
#import "iTermMetadata.h"
#import "LineBuffer.h"
#import "NSArray+iTerm.h"
#import "NSData+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import "VT100GridTypes.h"
#import "VT100LineInfo.h"
#import "VT100Terminal.h"

static NSString *const kGridCursorKey = @"Cursor";
static NSString *const kGridScrollRegionRowsKey = @"Scroll Region Rows";
static NSString *const kGridScrollRegionColumnsKey = @"Scroll Region Columns";
static NSString *const kGridUseScrollRegionColumnsKey = @"Use Scroll Region Columns";
static NSString *const kGridSizeKey = @"Size";

#define MEDIAN(min_, mid_, max_) MAX(MIN(mid_, max_), min_)

@interface VT100Grid ()
@property(nonatomic, readonly) NSArray *lines;  // Warning: not in order found on screen!
@end

@implementation VT100Grid {
    VT100GridSize size_;
    int screenTop_;  // Index into lines_ and dirty_ of first line visible in the grid.
    NSMutableArray<NSMutableData *> *lines_;  // Array of NSMutableData. Each data has size_.width+1 screen_char_t's.
    NSMutableArray<VT100LineInfo *> *lineInfos_;  // Array of VT100LineInfo.
    __weak id<VT100GridDelegate> delegate_;
    VT100GridCoord cursor_;
    VT100GridRange scrollRegionRows_;
    VT100GridRange scrollRegionCols_;
    BOOL useScrollRegionCols_;

    NSMutableData *cachedDefaultLine_;
    NSMutableData *resultLine_;
    screen_char_t savedDefaultChar_;
    NSTimeInterval _allDirtyTimestamp;
}

@synthesize size = size_;
@synthesize scrollRegionRows = scrollRegionRows_;
@synthesize scrollRegionCols = scrollRegionCols_;
@synthesize useScrollRegionCols = useScrollRegionCols_;
@synthesize allDirty = allDirty_;
@synthesize lines = lines_;
@synthesize savedDefaultChar = savedDefaultChar_;
@synthesize cursor = cursor_;
@synthesize delegate = delegate_;

- (instancetype)initWithSize:(VT100GridSize)size delegate:(id<VT100GridDelegate>)delegate {
    self = [super init];
    if (self) {
        delegate_ = delegate;
        [self setSize:size withSideEffects:NO];
        scrollRegionRows_ = VT100GridRangeMake(0, size_.height);
        scrollRegionCols_ = VT100GridRangeMake(0, size_.width);
        _preferredCursorPosition = VT100GridCoordMake(-1, -1);
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary
                          delegate:(id<VT100GridDelegate>)delegate {
    self = [super init];
    if (self) {
        delegate_ = delegate;
        NSArray<NSString *> *requiredKeys = @[ @"size", @"cursor" ];
        for (NSString *requiredKey in requiredKeys) {
            if (!dictionary[requiredKey]) {
                return nil;
            }
        }
        [self setSize:[NSDictionary castFrom:dictionary[@"size"]].gridSize];
        assert(size_.width > 0 && size_.height > 0);
        
        NSMutableDictionary<NSNumber *, iTermExternalAttributeIndex *> *migrationIndexes = nil;
        if (dictionary[@"lines v3"]) {
            // 3.5.0beta6+ path
            lines_ = [[NSArray castFrom:dictionary[@"lines v3"]] mutableCopy];
        } else if (dictionary[@"lines v2"]) {
            // 3.5.0beta3+ path
            lines_ = [[[NSArray castFrom:dictionary[@"lines v2"]] mapWithBlock:^id _Nonnull(NSData *data) {
                return [data migrateV2ToV3];
            }] mutableCopy];
        } else if (dictionary[@"lines"]) {
            // Migration code path for v1 -> v3 - upgrade legacy_screen_char_t.
            NSArray<NSData *> *legacyLines = [NSArray castFrom:dictionary[@"lines"]];
            if (!legacyLines) {
                return nil;
            }
            lines_ = [[NSMutableArray alloc] init];
            migrationIndexes = [NSMutableDictionary dictionary];
            [legacyLines enumerateObjectsUsingBlock:^(NSData * _Nonnull legacyData, NSUInteger idx, BOOL * _Nonnull stop) {
                iTermExternalAttributeIndex *migrationIndex = nil;
                [lines_ addObject:[[legacyData migrateV1ToV3:&migrationIndex] mutableCopy]];
                if (migrationIndex) {
                    migrationIndexes[@(idx)] = migrationIndex;
                }
            }];
        }
        if (!lines_) {
            return nil;
        }

        // Deprecated: migration code path. Modern dicts have `metadata` instead.
        [[NSArray castFrom:dictionary[@"timestamps"]] enumerateObjectsUsingBlock:^(NSNumber *timestamp,
                                                                                   NSUInteger idx,
                                                                                   BOOL * _Nonnull stop) {
            if (idx >= lineInfos_.count) {
                DLog(@"Too many lineInfos");
                *stop = YES;
                return;
            }
            lineInfos_[idx].timestamp = timestamp.doubleValue;
        }];
        [[NSArray castFrom:dictionary[@"metadata"]] enumerateObjectsUsingBlock:^(NSArray *entry,
                                                                                 NSUInteger idx,
                                                                                 BOOL * _Nonnull stop) {
            if (idx >= lineInfos_.count) {
                DLog(@"Too many lineInfos");
                *stop = YES;
                return;
            }
            [lineInfos_[idx] decodeMetadataArray:entry];
        }];
        [migrationIndexes enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull idx, iTermExternalAttributeIndex * _Nonnull ea, BOOL * _Nonnull stop) {
            [lineInfos_[idx.integerValue] setExternalAttributeIndex:ea];
        }];
        cursor_ = [NSDictionary castFrom:dictionary[@"cursor"]].gridCoord;
        scrollRegionRows_ = [NSDictionary castFrom:dictionary[@"scrollRegionRows"]].gridRange;
        scrollRegionCols_ = [NSDictionary castFrom:dictionary[@"scrollRegionCols"]].gridRange;
        useScrollRegionCols_ = [NSNumber castFrom:dictionary[@"useScrollRegionCols"]].boolValue;
        NSData *data = [NSData castFrom:dictionary[@"savedDefaultCharData"]];
        if (data.length == sizeof(savedDefaultChar_)) {
            memmove(&savedDefaultChar_, data.bytes, sizeof(savedDefaultChar_));
        }
        _preferredCursorPosition = cursor_;
        [self markAllCharsDirty:YES updateTimestamps:NO];
    }
    return self;
}

- (NSMutableData *)lineDataAtLineNumber:(int)lineNumber {
    if (lineNumber >= 0 && lineNumber < size_.height) {
        return [lines_ objectAtIndex:(screenTop_ + lineNumber) % size_.height];
    } else {
        return nil;
    }
}

- (iTermImmutableMetadata)immutableMetadataAtLineNumber:(int)lineNumber {
    return iTermMetadataMakeImmutable([self metadataAtLineNumber:lineNumber]);
}

- (iTermMetadata)metadataAtLineNumber:(int)lineNumber {
    return [self lineInfoAtLineNumber:lineNumber].metadata;
}

- (iTermExternalAttributeIndex *)externalAttributesOnLine:(int)line
                                           createIfNeeded:(BOOL)createIfNeeded {
    return [[self lineInfoAtLineNumber:line] externalAttributesCreatingIfNeeded:createIfNeeded];
}

- (void)setMetadata:(iTermMetadata)metadata forLineNumber:(int)lineNumber {
    VT100LineInfo *info = [self lineInfoAtLineNumber:lineNumber];
    info.metadata = metadata;
}

- (screen_char_t *)screenCharsAtLineNumber:(int)lineNumber {
    assert(lineNumber >= 0);
    return [[lines_ objectAtIndex:(screenTop_ + lineNumber) % size_.height] mutableBytes];
}

static int VT100GridIndex(int screenTop, int lineNumber, int height) {
    if (lineNumber >= 0 && lineNumber < height) {
        return (screenTop + lineNumber) % height;
    } else {
        return -1;
    }
}

- (VT100LineInfo *)lineInfoAtLineNumber:(int)lineNumber {
    const int index = VT100GridIndex(screenTop_, lineNumber, size_.height);
    if (index < 0) {
        return nil;
    }
    return lineInfos_[index];
}

- (NSArray<VT100LineInfo *> *)metadataArray {
    NSMutableArray<VT100LineInfo *> *result = [NSMutableArray array];
    for (int i = 0; i < self.size.height; i++) {
        [result addObject:[self lineInfoAtLineNumber:i]];
    }
    return result;
}

- (void)markCharDirty:(BOOL)dirty at:(VT100GridCoord)coord updateTimestamp:(BOOL)updateTimestamp {
    DLog(@"Mark %@ dirty=%@ delegate=%@", VT100GridCoordDescription(coord), @(dirty), delegate_);

    if (!dirty) {
        allDirty_ = NO;
    }
    VT100LineInfo *lineInfo = [self lineInfoAtLineNumber:coord.y];
    [lineInfo setDirty:dirty
               inRange:VT100GridRangeMake(coord.x, 1)
     updateTimestampTo:updateTimestamp ? self.currentDate : 0];
}

- (void)markCharsDirty:(BOOL)dirty inRectFrom:(VT100GridCoord)from to:(VT100GridCoord)to {
    DLog(@"Mark rect from %@ to %@ dirty=%@ delegate=%@", VT100GridCoordDescription(from), VT100GridCoordDescription(to), @(dirty), delegate_);
    assert(from.x <= to.x);
    if (!dirty) {
        allDirty_ = NO;
    }
    const VT100GridRange xrange = VT100GridRangeMake(from.x, to.x - from.x + 1);
    const NSTimeInterval timestamp = self.currentDate;
    for (int y = from.y; y <= to.y; y++) {
        const int index = VT100GridIndex(screenTop_, y, size_.height);
        if (index < 0) {
            continue;
        }
        [lineInfos_[index] setDirty:dirty
                            inRange:xrange
                  updateTimestampTo:dirty ? timestamp : 0];
    }
}

- (void)markAllCharsDirty:(BOOL)dirty updateTimestamps:(BOOL)updateTimestamps {
    DLog(@"Mark all chars dirty=%@ delegate=%@", @(dirty), delegate_);

    if (dirty) {
        // Fast path
        const VT100GridRange horizontalRange = VT100GridRangeMake(0, size_.width);
        const NSTimeInterval timestamp = self.currentDate;
        if (allDirty_ && (!updateTimestamps || _allDirtyTimestamp == timestamp)) {
            // Nothing changed.
            return;
        }
        allDirty_ = YES;
        if (updateTimestamps) {
            _allDirtyTimestamp = timestamp;
        }
        [lineInfos_ enumerateObjectsUsingBlock:^(VT100LineInfo * _Nonnull lineInfo, NSUInteger idx, BOOL * _Nonnull stop) {
            [lineInfo setDirty:YES inRange:horizontalRange updateTimestampTo:updateTimestamps ? timestamp : 0];
        }];
        return;
    }
    allDirty_ = dirty;
    [self markCharsDirty:dirty
              inRectFrom:VT100GridCoordMake(0, 0)
                      to:VT100GridCoordMake(size_.width - 1, size_.height - 1)];
}

- (void)markCharsDirty:(BOOL)dirty inRun:(VT100GridRun)run {
    DLog(@"Mark chars in run (origin=%@, length=%@) dirty=%@ delegate=%@", VT100GridCoordDescription(run.origin), @(run.length), @(dirty), delegate_);

    if (!dirty) {
        allDirty_ = NO;
    }
    for (NSValue *value in [self rectsForRun:run]) {
        VT100GridRect rect = [value gridRectValue];
        [self markCharsDirty:dirty inRectFrom:rect.origin to:VT100GridRectMax(rect)];
    }
}

- (BOOL)isCharDirtyAt:(VT100GridCoord)coord {
    if (allDirty_) {
        return YES;
    }
    VT100LineInfo *lineInfo = [self lineInfoAtLineNumber:coord.y];
    return [lineInfo isDirtyAtOffset:coord.x];
}

- (NSIndexSet *)dirtyIndexesOnLine:(int)line {
    if (allDirty_) {
        return [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.size.width)];
    }
    VT100LineInfo *lineInfo = [self lineInfoAtLineNumber:line];
    return [lineInfo dirtyIndexes];
}

- (BOOL)isAnyCharDirty {
    if (allDirty_) {
        return YES;
    }
    for (int y = 0; y < size_.height; y++) {
        VT100LineInfo *lineInfo = [self lineInfoAtLineNumber:y];
        if ([lineInfo anyCharIsDirty]) {
            return YES;
        }
    }
    return NO;
}

- (VT100GridRange)dirtyRangeForLine:(int)y {
    if (allDirty_) {
        return VT100GridRangeMake(0, self.size.width);
    }
    VT100LineInfo *lineInfo = [self lineInfoAtLineNumber:y];
    return [lineInfo dirtyRange];
}

- (int)cursorX {
    return cursor_.x;
}

- (int)cursorY {
    return cursor_.y;
}

- (void)setCursorX:(int)cursorX {
    int newX = MIN(size_.width, MAX(0, cursorX));
    if (newX != cursor_.x) {
        DLog(@"Move cursor x to %d (requested %d)", newX, cursorX);
        cursor_.x = newX;
        [delegate_ gridCursorDidMove];
    }
}

- (void)setCursorY:(int)cursorY {
    int prev = cursor_.y;
    cursor_.y = MIN(size_.height - 1, MAX(0, cursorY));
    if (cursorY != prev) {
        DLog(@"Move cursor y to %d (requested %d)", cursor_.y, cursorY);
        [delegate_ gridCursorDidChangeLine];
        [delegate_ gridCursorDidMove];
    }
}

- (void)setCursor:(VT100GridCoord)coord {
    cursor_.x = MIN(size_.width, MAX(0, coord.x));
    self.cursorY = MIN(size_.height - 1, MAX(0, coord.y));
}

- (int)numberOfNonEmptyLinesIncludingWhitespaceAsEmpty:(BOOL)includeWhitespace {
    int numberOfLinesUsed = size_.height;
    NSMutableCharacterSet *allowedCharacters = [[NSMutableCharacterSet alloc] init];
    [allowedCharacters addCharactersInRange:NSMakeRange(0, 1)];
    if (includeWhitespace) {
        [allowedCharacters addCharactersInString:@" \t"];
        [allowedCharacters addCharactersInRange:NSMakeRange(TAB_FILLER, 1)];
        [allowedCharacters addCharactersInRange:NSMakeRange(DWC_RIGHT, 1)];
        [allowedCharacters addCharactersInRange:NSMakeRange(DWC_SKIP, 1)];
    }
    for(; numberOfLinesUsed > 0; numberOfLinesUsed--) {
        screen_char_t *line = [self screenCharsAtLineNumber:numberOfLinesUsed - 1];
        int i;
        for (i = 0; i < size_.width; i++) {
            if (line[i].complexChar ||
                line[i].image ||
                ![allowedCharacters characterIsMember:line[i].code]) {
                break;
            }
        }
        if (i < size_.width) {
            break;
        }
    }

    return numberOfLinesUsed;
}

- (int)numberOfLinesUsed {
    return MAX(MIN(size_.height, cursor_.y + 1), [self numberOfNonEmptyLinesIncludingWhitespaceAsEmpty:NO]);
}

- (int)appendLines:(int)numLines
      toLineBuffer:(LineBuffer *)lineBuffer {
    assert(numLines <= size_.height);

    // Set numLines to the number of lines on the screen that are in use.
    int i;

    // Push the current screen contents into the scrollback buffer.
    // The maximum number of lines of scrollback are temporarily ignored because this
    // loop doesn't call dropExcessLinesWithWidth.
    int lengthOfNextLine = 0;
    if (numLines > 0) {
        lengthOfNextLine = [self lengthOfLineNumber:0];
    }
    for (i = 0; i < numLines; ++i) {
        const screen_char_t *line = [self screenCharsAtLineNumber:i];
        int currentLineLength = lengthOfNextLine;
        if (i + 1 < size_.height) {
            lengthOfNextLine = [self lengthOfLine:[self screenCharsAtLineNumber:i+1]];
        } else {
            lengthOfNextLine = -1;
        }

        int continuation = line[size_.width].code;
        if (i == cursor_.y) {
            [lineBuffer setCursor:cursor_.x];
        } else if ((cursor_.x == 0) &&
                   (i == cursor_.y - 1) &&
                   (lengthOfNextLine == 0) &&
                   line[size_.width].code != EOL_HARD) {
            // This line is continued, the next line is empty, and the cursor is
            // on the first column of the next line. Pull it up.
            // NOTE: This was cursor_.x + 1, but I'm pretty sure that's wrong as it would always be 1.
            [lineBuffer setCursor:currentLineLength];
        }

        // NOTE: When I initially wrote the session restoration code, there was
        // an '|| (i == size.height)' conjunction. It caused issue 3788 so I
        // removed it. Unfortunately, I can't recall why it was added in the
        // first place.
        const BOOL isPartial = ((continuation != EOL_HARD) ||
                                (i + 1 == numLines &&
                                 self.cursor.y == i &&
                                 self.cursor.x == [self lengthOfLineNumber:i]));
        [lineBuffer appendLine:line
                        length:currentLineLength
                       partial:isPartial
                         width:size_.width
                      metadata:[[self lineInfoAtLineNumber:i] immutableMetadata]
                  continuation:line[size_.width]];
#ifdef DEBUG_RESIZEDWIDTH
        NSLog(@"Appended a line. now have %d lines for width %d\n",
              [lineBuffer numLinesWithWidth:size_.width], size_.width);
#endif
    }

    return numLines;
}

- (NSTimeInterval)timestampForLine:(int)y {
    return [[self lineInfoAtLineNumber:y] metadata].timestamp;
}

- (int)lengthOfLineNumber:(int)lineNumber {
    screen_char_t *line = [self screenCharsAtLineNumber:lineNumber];
    return [self lengthOfLine:line];
}

- (int)lengthOfLine:(screen_char_t *)line {
    int lineLength = 0;
    // Figure out the line length.
    if (line[size_.width].code == EOL_SOFT) {
        lineLength = size_.width;
    } else if (line[size_.width].code == EOL_DWC) {
        lineLength = size_.width - 1;
    } else {
        for (lineLength = size_.width - 1; lineLength >= 0; --lineLength) {
            if (line[lineLength].code && !ScreenCharIsDWC_SKIP(line[lineLength])) {
                break;
            }
        }
        ++lineLength;
    }
    return lineLength;
}

- (int)continuationMarkForLineNumber:(int)lineNumber {
    screen_char_t *line = [self screenCharsAtLineNumber:lineNumber];
    return line[size_.width].code;
}

- (int)indexOfLineNumber:(int)lineNumber {
    while (lineNumber < 0) {
        lineNumber += size_.height;
    }
    return (screenTop_ + lineNumber) % size_.height;
}

- (int)scrollWholeScreenUpIntoLineBuffer:(LineBuffer *)lineBuffer
                     unlimitedScrollback:(BOOL)unlimitedScrollback {
    // Mark the cursor's previous location dirty. This fixes a rare race condition where
    // the cursor is not erased.
    // TODO: I'm not sure this still exists post-refactoring.
    if (cursor_.x < size_.width) {
      [self markCharDirty:YES at:cursor_ updateTimestamp:YES];
    }

    // Add the top line to the scrollback
    int numLinesDropped = [self appendLineToLineBuffer:lineBuffer
                                   unlimitedScrollback:unlimitedScrollback];

    // Increment screenTop_, effectively scrolling the lines & dirty up by one line.
    screenTop_ = (screenTop_ + 1) % size_.height;
    _haveScrolled = YES;
    // Empty contents of last line on screen.
    NSMutableData *lastLineData = [self lineDataAtLineNumber:(size_.height - 1)];
    if (lastLineData) {  // This if statement is just to quiet the analyzer.
        [self clearLineData:lastLineData];
        [[self lineInfoAtLineNumber:(size_.height - 1)] resetMetadata];
    }

    [self markAllCharsDirty:YES updateTimestamps:NO];

    DLog(@"scrolled screen up by 1 line");
    return numLinesDropped;
}

- (int)scrollUpIntoLineBuffer:(LineBuffer *)lineBuffer
          unlimitedScrollback:(BOOL)unlimitedScrollback
      useScrollbackWithRegion:(BOOL)useScrollbackWithRegion
                    softBreak:(BOOL)softBreak {
    const int scrollTop = self.topMargin;
    const int scrollBottom = self.bottomMargin;
    const int scrollLeft = self.leftMargin;
    const int scrollRight = self.rightMargin;

    assert(scrollTop >= 0 && scrollTop < size_.height);
    assert(scrollBottom >= 0 && scrollBottom < size_.height);
    assert(scrollTop <= scrollBottom );

    if (![self haveScrollRegion]) {
        // Scroll the whole screen. This is the fast path.
        return [self scrollWholeScreenUpIntoLineBuffer:lineBuffer
                                   unlimitedScrollback:unlimitedScrollback];
    } else {
        int numLinesDropped = 0;
        // Not scrolling the whole screen.
        if (scrollTop == 0 && useScrollbackWithRegion && ![self haveColumnScrollRegion]) {
            // A line is being scrolled off the top of the screen so add it to
            // the scrollback buffer.
            numLinesDropped = [self appendLineToLineBuffer:lineBuffer
                                       unlimitedScrollback:unlimitedScrollback];
        }
        // TODO: formerly, scrollTop==scrollBottom was a no-op but I think that's wrong. See what other terms do.
        [self scrollRect:VT100GridRectMake(scrollLeft,
                                           scrollTop,
                                           scrollRight - scrollLeft + 1,
                                           scrollBottom - scrollTop + 1)
                    downBy:-1
               softBreak:softBreak];

        return numLinesDropped;
    }
}

- (int)resetWithLineBuffer:(LineBuffer *)lineBuffer
        unlimitedScrollback:(BOOL)unlimitedScrollback
        preserveCursorLine:(BOOL)preserveCursorLine
     additionalLinesToSave:(int)additionalLinesToSave {
    self.scrollRegionRows = VT100GridRangeMake(0, size_.height);
    self.scrollRegionCols = VT100GridRangeMake(0, size_.width);
    int numLinesToScroll;
    if (preserveCursorLine) {
        numLinesToScroll = MAX(0, cursor_.y - additionalLinesToSave);
    } else {
        numLinesToScroll = [self lineNumberOfLastNonEmptyLine] + 1;
    }
    int numLinesDropped = 0;
    for (int i = 0; i < numLinesToScroll; i++) {
        numLinesDropped += [self scrollUpIntoLineBuffer:lineBuffer
                                    unlimitedScrollback:unlimitedScrollback
                                useScrollbackWithRegion:NO
                                              softBreak:NO];
    }
    self.cursor = VT100GridCoordMake(0, 0);

    const VT100GridCoord topLeft = VT100GridCoordMake(0, preserveCursorLine ? 1 + additionalLinesToSave : 0);
    const VT100GridCoord bottomRight = VT100GridCoordMake(size_.width - 1, size_.height - 1);
    [self setCharsFrom:topLeft
                    to:bottomRight
                toChar:[self defaultChar]
    externalAttributes:nil];

    return numLinesDropped;
}

- (void)moveWrappedCursorLineToTopOfGrid {
    if (cursor_.y < 0) {
        return;  // Not sure how this would happen, but the old code in -[VT100Screen clearScreen] had this check.
    }
    int sourceLineNumber = [self cursorLineNumberIncludingPrecedingWrappedLines];
    for (int i = 0; i < sourceLineNumber; i++) {
        [self scrollWholeScreenUpIntoLineBuffer:nil unlimitedScrollback:NO];
    }
    self.cursorY = cursor_.y - sourceLineNumber;
}

- (int)moveCursorDownOneLineScrollingIntoLineBuffer:(LineBuffer *)lineBuffer
                                unlimitedScrollback:(BOOL)unlimitedScrollback
                            useScrollbackWithRegion:(BOOL)useScrollbackWithRegion
                                         willScroll:(void (^)(void))willScroll {
    // This doesn't call -bottomMargin because it was a hotspot in profiling.
    const int scrollBottom = VT100GridRangeMax(scrollRegionRows_);

    if (cursor_.y != scrollBottom) {
        // Do not scroll the screen; just move the cursor.
        self.cursorY = cursor_.y + 1;
        DLog(@"moved cursor down by 1 line");
        return 0;
    } else {
        // We are scrolling within a subset of the screen.
        DebugLog(@"scrolled a subset or whole screen up by 1 line");
        if (willScroll) {
            willScroll();
        }
        return [self scrollUpIntoLineBuffer:lineBuffer
                        unlimitedScrollback:unlimitedScrollback
                    useScrollbackWithRegion:useScrollbackWithRegion
                                  softBreak:YES];
    }
}

- (void)moveCursorLeft:(int)n {
    if ([self haveColumnScrollRegion]) {
        // Don't allow cursor to wrap around the left margin when there is a
        // column scroll region. If the cursor begins at/right of the left margin, it stops at the
        // left margin. If the cursor begins left of the left margin, it stops at the left edge.
        int x = cursor_.x - n;
        const int leftMargin = [self leftMargin];

        int limit;
        if (cursor_.x < leftMargin) {
            limit = 0;
        } else {
            limit = leftMargin;
        }

        x = MAX(limit, x);
        self.cursorX = x;
        return;
    }

    while (n > 0) {
        if (self.cursorX == 0 && self.cursorY == 0) {
            // Can't move any farther left.
            return;
        } else if (self.cursorX == 0) {
            // Wrap around?
            switch ([self continuationMarkForLineNumber:self.cursorY - 1]) {
                case EOL_SOFT:
                case EOL_DWC:
                    // Wrap around to the end of the previous line, even if this leaves the cursor
                    // on a DWC_RIGHT.
                    n--;
                    self.cursorX = [self rightMargin];
                    self.cursorY = self.cursorY - 1;
                    break;

                case EOL_HARD:
                    // Can't wrap across EOL_HARD.
                    return;
            }
        } else {
            // Move as far as the left margin
            int x = MAX(0, cursor_.x - n);
            int moved = self.cursorX - x;
            n -= moved;
            self.cursorX = x;
        }
    }
}

- (void)moveCursorRight:(int)n {
    int x = cursor_.x + n;
    int rightMargin = [self rightMargin];
    if (cursor_.x > rightMargin) {
        rightMargin = size_.width - 1;
    }

    x = MIN(x, rightMargin);
    self.cursorX = x;
}

- (void)moveCursorUp:(int)n {
    const int scrollTop = self.topMargin;
    int y = MAX(0, MIN(size_.height - 1, cursor_.y - n));
    int x = MIN(cursor_.x, size_.width - 1);
    if (cursor_.y >= scrollTop) {
        [self setCursor:VT100GridCoordMake(x,
                                           y < scrollTop ? scrollTop : y)];
    } else {
        [self setCursor:VT100GridCoordMake(x, y)];
    }
}

- (void)moveCursorDown:(int)n {
    const int scrollBottom = self.bottomMargin;
    int y = MAX(0, MIN(size_.height - 1, cursor_.y + n));
    int x = MIN(cursor_.x, size_.width - 1);
    if (cursor_.y <= scrollBottom) {
        [self setCursor:VT100GridCoordMake(x,
                                           y > scrollBottom ? scrollBottom : y)];
    } else {
        [self setCursor:VT100GridCoordMake(x, y)];
    }
}

- (void)mutateCharactersInRange:(VT100GridCoordRange)range
                          block:(void (^)(screen_char_t *sct,
                                          iTermExternalAttribute **eaOut,
                                          VT100GridCoord coord,
                                          BOOL *stop))block {
    int left = MAX(0, range.start.x);
    for (int y = MAX(0, range.start.y); y <= MIN(range.end.y, size_.height - 1); y++) {
        const int right = MAX(left, y == range.end.y ? range.end.x : size_.width);
        screen_char_t *line = [self lineDataAtLineNumber:y].mutableBytes;
        iTermExternalAttributeIndex *eaIndex = [self externalAttributesOnLine:y createIfNeeded:NO];
        [self markCharsDirty:YES inRun:VT100GridRunMake(left, y, right - left)];
        for (int x = left; x < right; x++) {
            BOOL stop = NO;
            iTermExternalAttribute *ea = eaIndex[x];
            iTermExternalAttribute *originalEa = ea;
            block(&line[x], &ea, VT100GridCoordMake(x, y), &stop);
            if (ea != originalEa) {
                if (!eaIndex) {
                    eaIndex = [self externalAttributesOnLine:y createIfNeeded:YES];
                }
                [eaIndex setAttributes:ea at:x count:1];
            }
            if (stop) {
                return;
            }
        }
        left = 0;
    }
}

- (void)setCharsFrom:(VT100GridCoord)unsafeFrom
                  to:(VT100GridCoord)unsafeTo
              toChar:(screen_char_t)c
  externalAttributes:(iTermExternalAttribute *)attrs {
    if (unsafeFrom.x > unsafeTo.x || unsafeFrom.y > unsafeTo.y) {
        return;
    }
    const VT100GridCoord from = [self clamp:unsafeFrom];
    const VT100GridCoord to = [self clamp:unsafeTo];
    for (int y = MAX(0, from.y); y <= MIN(to.y, size_.height - 1); y++) {
        screen_char_t *line = [self screenCharsAtLineNumber:y];
        [self erasePossibleDoubleWidthCharInLineNumber:y startingAtOffset:from.x - 1 withChar:c];
        [self erasePossibleDoubleWidthCharInLineNumber:y startingAtOffset:to.x withChar:c];
        const int minX = MAX(0, from.x);
        const int maxX = MIN(to.x, size_.width - 1);
        for (int x = minX; x <= maxX; x++) {
            line[x] = c;
        }
        if (c.code == 0 && to.x == size_.width - 1) {
            line[size_.width] = c;
            line[size_.width].code = EOL_HARD;
        }
        iTermExternalAttributeIndex *eaIndex = [self externalAttributesOnLine:y
                                                               createIfNeeded:attrs != nil];
        [eaIndex setAttributes:attrs
                            at:minX
                         count:maxX - minX + 1];
    }
    [self markCharsDirty:YES inRectFrom:from to:to];
}

- (void)eraseExternalAttributesFrom:(VT100GridCoord)from to:(VT100GridCoord)to {
    if (from.x > to.x || from.y > to.y) {
        return;
    }
    const int minX = MAX(0, from.x);
    const int maxX = MIN(to.x, size_.width - 1);
    for (int y = MAX(0, from.y); y <= MIN(to.y, size_.height - 1); y++) {
        [self eraseExternalAttributesAt:VT100GridCoordMake(minX, y) count:maxX - minX + 1];
    }
}

- (void)setMetadata:(iTermMetadata)metadata forLine:(int)lineNumber {
    [[self lineInfoAtLineNumber:lineNumber] setMetadata:metadata];
}

- (void)setCharsInRun:(VT100GridRun)run toChar:(unichar)code externalAttributes:(iTermExternalAttribute *)ea {
    screen_char_t c = [self defaultChar];
    c.code = code;
    c.complexChar = NO;

    VT100GridCoord max = VT100GridRunMax(run, size_.width);
    int y = run.origin.y;

    if (y == max.y) {
        // Whole run is on one line.
        [self setCharsFrom:run.origin to:max toChar:c externalAttributes:ea];
    } else {
        // Fill partial first line
        [self setCharsFrom:run.origin
                        to:VT100GridCoordMake(size_.width - 1, y)
                    toChar:c
        externalAttributes:ea];
        y++;

        if (y < max.y) {
            // Fill a bunch of full lines
            [self setCharsFrom:VT100GridCoordMake(0, y)
                            to:VT100GridCoordMake(size_.width - 1, max.y - 1)
                        toChar:c
            externalAttributes:ea];
        }

        // Fill possibly-partial last line
        [self setCharsFrom:VT100GridCoordMake(0, max.y)
                        to:VT100GridCoordMake(max.x, max.y)
                    toChar:c
        externalAttributes:ea];
    }
}

- (void)setBackgroundColor:(screen_char_t)bg
           foregroundColor:(screen_char_t)fg
                inRectFrom:(VT100GridCoord)from
                        to:(VT100GridCoord)to {
    for (int y = from.y; y <= to.y; y++) {
        screen_char_t *line = [self screenCharsAtLineNumber:y];
        for (int x = from.x; x <= to.x; x++) {
            if (fg.foregroundColorMode != ColorModeInvalid) {
                CopyForegroundColor(&line[x], fg);
            }
            if (bg.backgroundColorMode != ColorModeInvalid) {
                CopyBackgroundColor(&line[x], bg);
            }
        }
        [self markCharsDirty:YES
                  inRectFrom:VT100GridCoordMake(from.x, y)
                          to:VT100GridCoordMake(to.x, y)];
    }
}

- (void)setURLCode:(unsigned int)code
        inRectFrom:(VT100GridCoord)from
                to:(VT100GridCoord)to {
    for (int y = from.y; y <= to.y; y++) {
        VT100LineInfo *info = [self lineInfoAtLineNumber:y];
        iTermExternalAttributeIndex *eaIndex = [info externalAttributesCreatingIfNeeded:code != 0];
        [eaIndex mutateAttributesFrom:from.x to:to.x block:^iTermExternalAttribute * _Nullable(iTermExternalAttribute * _Nullable old) {
            return [iTermExternalAttribute attributeHavingUnderlineColor:old.hasUnderlineColor
                                                          underlineColor:old.underlineColor
                                                                 urlCode:code];
        }];
        [self markCharsDirty:YES
                  inRectFrom:VT100GridCoordMake(from.x, y)
                          to:VT100GridCoordMake(to.x, y)];
    }
}

- (void)copyDirtyFromGrid:(VT100Grid *)otherGrid {
    if (otherGrid == self) {
        return;
    }
    const BOOL sizeChanged = !VT100GridSizeEquals(self.size, otherGrid.size);
    [self setSize:otherGrid.size];
    for (int i = 0; i < size_.height; i++) {
        const VT100GridRange dirtyRange = [otherGrid dirtyRangeForLine:i];
        if (!sizeChanged && dirtyRange.length <= 0) {
            continue;
        }
        screen_char_t *dest = [self screenCharsAtLineNumber:i];
        screen_char_t *source = [otherGrid screenCharsAtLineNumber:i];
        memmove(dest,
                source,
                sizeof(screen_char_t) * (size_.width + 1));
        iTermMetadata metadata = iTermMetadataCopy([otherGrid metadataAtLineNumber:i]);
        [self setMetadata:metadata forLineNumber:i];
        iTermMetadataRelease(metadata);
        if (dirtyRange.length > 0) {
            [[self lineInfoAtLineNumber:i] setDirty:YES inRange:dirtyRange updateTimestampTo:0];
        }
    }
    [otherGrid copyMiscellaneousStateTo:self];
}

- (int)scrollLeft {
    return scrollRegionCols_.location;
}

- (int)scrollRight {
    return VT100GridRangeMax(scrollRegionCols_);
}

- (int)appendCharsAtCursor:(const screen_char_t *)buffer
                    length:(int)len
   scrollingIntoLineBuffer:(LineBuffer *)lineBuffer
       unlimitedScrollback:(BOOL)unlimitedScrollback
   useScrollbackWithRegion:(BOOL)useScrollbackWithRegion
                wraparound:(BOOL)wraparound
                      ansi:(BOOL)ansi
                    insert:(BOOL)insert
    externalAttributeIndex:(id<iTermExternalAttributeIndexReading>)attributes {
    int numDropped = 0;
    assert(buffer);
    int idx;  // Index into buffer
    int charsToInsert;
    int newx;
    int leftMargin, rightMargin;
    screen_char_t *aLine;
    const int scrollLeft = self.scrollLeft;
    const int scrollRight = self.scrollRight;

    // Iterate over each character in the buffer and copy/insert into screen.
    // Grab a block of consecutive characters up to the remaining length in the
    // line and append them at once.
    for (idx = 0; idx < len; )  {
        int startIdx = idx;
#ifdef VERBOSE_STRING
        NSLog(@"Begin inserting line. cursor_.x=%d, WIDTH=%d", cursor_.x, WIDTH);
#endif

        int widthOffset;
        if (idx + 1 < len && ScreenCharIsDWC_RIGHT(buffer[idx + 1])) {
            // If we're about to insert a double width character then reduce the
            // line width for the purposes of testing if the cursor is in the
            // rightmost position.
            widthOffset = 1;
#ifdef VERBOSE_STRING
            NSLog(@"The first char we're going to insert is a DWC");
#endif
        } else {
            widthOffset = 0;
        }

        if (useScrollRegionCols_ && cursor_.x <= scrollRight + 1) {
            // If the cursor is left of the right margin,
            // the text run stops (or wraps) at right margin.
            // And if a text run wraps at the right margin,
            // the next line starts from left margin.
            //
            // NOTE:
            //    Above behavior is compatible with xterm, but incompatible with VT525.
            //    VT525 has curious glitch:
            //        If a text run which starts from left of the left margin
            //        wraps or returns by CR, the next line starts from column 1, but not left margin.
            //        (see Mr. IWAMOTO's gist https://gist.github.com/ttdoda/5902671)
            //    We're going for xterm compatibility, not VT525 compatibility.
            leftMargin = scrollLeft;
            rightMargin = scrollRight + 1;
        } else {
            leftMargin = 0;
            rightMargin = size_.width;
        }
        if (cursor_.x >= rightMargin - widthOffset) {
            if (wraparound) {
                if (leftMargin == 0 && rightMargin == size_.width) {
                    // Set the continuation marker
                    screen_char_t* prevLine = [self screenCharsAtLineNumber:cursor_.y];
                    BOOL splitDwc = (cursor_.x == size_.width - 1);
                    prevLine[size_.width] = [self defaultChar];
                    prevLine[size_.width].code = (splitDwc ? EOL_DWC : EOL_SOFT);
                    if (splitDwc) {
                        ScreenCharSetDWC_SKIP(&prevLine[size_.width - 1]);
                    }
                }
                self.cursorX = leftMargin;
                // Advance to the next line
                numDropped += [self moveCursorDownOneLineScrollingIntoLineBuffer:lineBuffer
                                                             unlimitedScrollback:unlimitedScrollback
                                                         useScrollbackWithRegion:useScrollbackWithRegion
                                                                      willScroll:nil];

#ifdef VERBOSE_STRING
                NSLog(@"Advance cursor to next line");
#endif
            } else {
                // Wraparound is off.
                // That means all the characters are effectively inserted at the
                // rightmost position. Move the cursor to the end of the line
                // and insert the last character there.

                // Cause the loop to end after this character.
                int newCursorX = rightMargin - 1;

                idx = len - 1;
                if (ScreenCharIsDWC_RIGHT(buffer[idx]) && idx > startIdx) {
                    // The last character to insert is double width. Back up one
                    // byte in buffer and move the cursor left one position.
                    idx--;
                    newCursorX--;
                }

                screen_char_t *line = [self screenCharsAtLineNumber:cursor_.y];
                if (rightMargin == size_.width) {
                    // Clear the continuation marker
                    line[size_.width].code = EOL_HARD;
                }

                if (newCursorX < 0) {
                    newCursorX = 0;
                }
                self.cursorX = newCursorX;
                if (ScreenCharIsDWC_RIGHT(line[cursor_.x])) {
                    // This would cause us to overwrite the second part of a
                    // double-width character. Convert it to a space.
                    line[cursor_.x - 1].code = 0;
                    line[cursor_.x - 1].complexChar = NO;
                }

#ifdef VERBOSE_STRING
                NSLog(@"Scribbling on last position");
#endif
            }
        }
        const int spaceRemainingInLine = rightMargin - cursor_.x;
        const int charsLeftToAppend = len - idx;

#ifdef VERBOSE_STRING
        DumpBuf(buffer + idx, charsLeftToAppend);
#endif
        BOOL wrapDwc = NO;
#ifdef VERBOSE_STRING
        NSLog(@"There is %d space left in the line and we are appending %d chars",
              spaceRemainingInLine, charsLeftToAppend);
#endif
        int effective_width;
        if (useScrollRegionCols_) {
            effective_width = size_.width;
        } else {
            effective_width = scrollRight + 1;
        }
        if (spaceRemainingInLine <= charsLeftToAppend) {
#ifdef VERBOSE_STRING
            NSLog(@"Not enough space in the line for everything we want to append.");
#endif
            // There is enough text to at least fill the line. Place the cursor
            // at the end of the line.
            int potentialCharsToInsert = spaceRemainingInLine;
            if (idx + potentialCharsToInsert < len &&
                ScreenCharIsDWC_RIGHT(buffer[idx + potentialCharsToInsert])) {
                // If we filled the line all the way out to WIDTH a DWC would be
                // split. Wrap the DWC around to the next line.
#ifdef VERBOSE_STRING
                NSLog(@"Dropping a char from the end to avoid splitting a DWC.");
#endif
                wrapDwc = YES;
                newx = rightMargin - 1;
                --effective_width;
            } else {
#ifdef VERBOSE_STRING
                NSLog(@"Inserting up to the end of the line only.");
#endif
                newx = rightMargin;
            }
        } else {
            // This is the last iteration through this loop and we will not
            // advance to another line. Place the cursor at the end of the line
            // where it should be after appending is complete.
            newx = cursor_.x + charsLeftToAppend;
#ifdef VERBOSE_STRING
            NSLog(@"All remaining chars fit.");
#endif
        }

        // Get the number of chars to insert this iteration (no more than fit
        // on the current line).
        charsToInsert = newx - cursor_.x;
#ifdef VERBOSE_STRING
        NSLog(@"Will insert %d chars", charsToInsert);
#endif
        if (charsToInsert <= 0) {
            //NSLog(@"setASCIIString: output length=0?(%d+%d)%d+%d",cursor_.x,charsToInsert,idx2,len);
            break;
        }

        const int lineNumber = cursor_.y;
        aLine = [self screenCharsAtLineNumber:lineNumber];
        iTermExternalAttributeIndex *eaIndex = [self externalAttributesOnLine:lineNumber createIfNeeded:attributes != nil];

        BOOL mayStompSplitDwc = NO;
        if (newx == size_.width) {
            // The cursor is ending at the right margin. See if there's a DWC_SKIP/EOL_DWC pair
            // there which may be affected.
            mayStompSplitDwc = (!useScrollRegionCols_ &&
                                aLine[size_.width].code == EOL_DWC &&
                                ScreenCharIsDWC_SKIP(aLine[size_.width - 1]));
        } else if (!wraparound &&
                   rightMargin < size_.width &&
                   useScrollRegionCols_ &&
                   newx >= rightMargin &&
                   cursor_.x < rightMargin) {
            // Prevent the cursor from going past the right margin when wraparound is off.
            newx = rightMargin - 1;
        }

        if (insert) {
            if (cursor_.x + charsToInsert < rightMargin) {
                [self shiftLine:lineNumber
                        rightBy:charsToInsert
                     startingAt:cursor_.x
                           upTo:rightMargin
         externalAttributeIndex:eaIndex];
            }
        }

        // Overwriting the second-half of a double-width character so turn the
        // DWC into a space.
        if (ScreenCharIsDWC_RIGHT(aLine[cursor_.x])) {
            [self eraseDWCRightOnLine:lineNumber x:cursor_.x externalAttributeIndex:eaIndex];
        }

        // This is an ugly little optimization--if we're inserting just one character, see if it would
        // change anything (because the memcmp is really cheap). In particular, this helps vim out because
        // it really likes redrawing pane separators when it doesn't need to.
        if (charsToInsert > 1 ||
            memcmp(aLine + cursor_.x, buffer + idx, charsToInsert * sizeof(screen_char_t))) {
            // copy charsToInsert characters into the line and set them dirty.
            memcpy(aLine + cursor_.x,
                   buffer + idx,
                   charsToInsert * sizeof(screen_char_t));
            [self markCharsDirty:YES
                      inRectFrom:VT100GridCoordMake(cursor_.x, lineNumber)
                              to:VT100GridCoordMake(cursor_.x + charsToInsert - 1, lineNumber)];
            [eaIndex copyFrom:attributes source:idx destination:cursor_.x count:charsToInsert];
        }
        if (wrapDwc) {
            [eaIndex eraseAt:cursor_.x + charsToInsert];
            if (cursor_.x + charsToInsert == size_.width - 1) {
                ScreenCharSetDWC_SKIP(&aLine[cursor_.x + charsToInsert]);
            } else {
                aLine[cursor_.x + charsToInsert].code = 0;
            }
            aLine[cursor_.x + charsToInsert].complexChar = NO;
        }
        self.cursorX = newx;
        idx += charsToInsert;

        // Overwrote some stuff that was already on the screen leaving behind the
        // second half of a DWC
        if (cursor_.x < size_.width - 1 && ScreenCharIsDWC_RIGHT(aLine[cursor_.x])) {
            [eaIndex eraseAt:cursor_.x];
            aLine[cursor_.x].code = 0;
            aLine[cursor_.x].complexChar = NO;
        }

        if (mayStompSplitDwc &&
            !ScreenCharIsDWC_SKIP(aLine[size_.width - 1]) &&
            aLine[size_.width].code == EOL_DWC) {
            // The line no longer ends in a DWC_SKIP, but the continuation mark is still EOL_DWC.
            // Change the continuation mark to EOL_SOFT since there's presumably still a DWC at the
            // start of the next line.
            aLine[size_.width].code = EOL_SOFT;
        }

        // The next char in the buffer shouldn't be DWC_RIGHT because we
        // wouldn't have inserted its first half due to a check at the top.
        assert(!(idx < len && ScreenCharIsDWC_RIGHT(buffer[idx]) ));

        // ANSI terminals will go to a new line after displaying a character at
        // the rightmost column.
        if (cursor_.x >= effective_width && ansi) {
            if (wraparound) {
                //set the wrapping flag
                aLine[size_.width] = [self defaultChar];
                aLine[size_.width].code = ((effective_width == size_.width) ? EOL_SOFT : EOL_DWC);
                self.cursorX = leftMargin;
                numDropped += [self moveCursorDownOneLineScrollingIntoLineBuffer:lineBuffer
                                                             unlimitedScrollback:unlimitedScrollback
                                                         useScrollbackWithRegion:useScrollbackWithRegion
                                                                      willScroll:nil];
            } else {
                self.cursorX = rightMargin - 1;
                if (idx < len - 1) {
                    // Iterate once more to draw the last character at the end
                    // of the line.
                    idx = len - 1;
                } else {
                    // Break out of the loop after the last character is drawn.
                    idx = len;
                }
            }
        }
    }

    assert(numDropped >= 0);
    return numDropped;
}

- (void)shiftLine:(int)lineNumber
          rightBy:(int)amount
       startingAt:(int)cursorX
             upTo:(int)rightMargin
externalAttributeIndex:(iTermExternalAttributeIndex *)ea {
#ifdef VERBOSE_STRING
                NSLog(@"Shifting old contents to the right");
#endif
    screen_char_t *aLine = [self screenCharsAtLineNumber:lineNumber];

    // Shift the old line contents to the right by 'amount' positions.
    screen_char_t *src = aLine + cursorX;
    screen_char_t *dst = aLine + cursorX + amount;
    const int elements = rightMargin - cursorX - amount;
    if (cursorX > 0 && ScreenCharIsDWC_RIGHT(src[0])) {
        // The insert occurred in the middle of a DWC.
        src[-1].code = 0;
        src[-1].complexChar = NO;
        src[0].code = 0;
        src[0].complexChar = NO;
    }
    if (ScreenCharIsDWC_RIGHT(src[elements])) {
        // Moving a DWC on top of its right half. Erase the DWC.
        src[elements - 1].code = 0;
        src[elements - 1].complexChar = NO;
    } else if (ScreenCharIsDWC_SKIP(src[elements]) &&
               aLine[size_.width].code == EOL_DWC) {
        // Stomping on a DWC_SKIP. Join the lines normally.
        aLine[size_.width] = [self defaultChar];
        aLine[size_.width].code = EOL_SOFT;
    }
    memmove(dst, src, elements * sizeof(screen_char_t));
    [self markCharsDirty:YES
              inRectFrom:VT100GridCoordMake(cursorX, lineNumber)
                      to:VT100GridCoordMake(rightMargin - 1, lineNumber)];
    [ea copyFrom:ea source:cursorX destination:cursorX + amount count:elements];
}

- (void)eraseDWCRightOnLine:(int)lineNumber x:(int)cursorX
     externalAttributeIndex:(iTermExternalAttributeIndex *)eaIndex {
#ifdef VERBOSE_STRING
    NSLog(@"Wiping out the right-half DWC at the cursor before writing to screen");
    ITAssertWithMessage(cursor_.x > 0, @"DWC split");  // there should never be the second half of a DWC at x=0
#endif
    screen_char_t *aLine = [self screenCharsAtLineNumber:lineNumber];
    aLine[cursorX].code = 0;
    aLine[cursorX].complexChar = NO;
    [eaIndex eraseAt:cursorX];
    if (cursorX > 0) {
        aLine[cursorX - 1].code = 0;
        aLine[cursorX - 1].complexChar = NO;
        [eaIndex eraseAt:cursorX - 1];
    }
    [self markCharDirty:YES
                     at:VT100GridCoordMake(cursorX, lineNumber)
        updateTimestamp:YES];
    if (cursorX > 0) {
        [self markCharDirty:YES
                         at:VT100GridCoordMake(cursorX - 1, lineNumber)
            updateTimestamp:YES];
    }
}

- (void)deleteChars:(int)numberOfCharactersToDelete
         startingAt:(VT100GridCoord)startCoord {
    DLog(@"deleteChars:%d startingAt:%d,%d", numberOfCharactersToDelete, startCoord.x, startCoord.y);

    screen_char_t *aLine;
    const int leftMargin = [self leftMargin];
    // rightMargin is the index of last column within the margins.
    const int rightMargin = [self rightMargin];
    screen_char_t defaultChar = [self defaultChar];

    iTermExternalAttributeIndex *eaIndex = [self externalAttributesOnLine:startCoord.y
                                                           createIfNeeded:NO];
    if (startCoord.x >= leftMargin &&
        startCoord.x < rightMargin &&
        startCoord.y >= 0 &&
        startCoord.y < size_.height) {
        int lineNumber = startCoord.y;
        int n = numberOfCharactersToDelete;
        if (n + startCoord.x > rightMargin) {
            n = rightMargin - startCoord.x + 1;
        }

        // get the appropriate screen line
        aLine = [self screenCharsAtLineNumber:startCoord.y];

        if (n > 0 && startCoord.x + n <= rightMargin) {
            // Erase a section in the middle of a line. Shift the stuff to the right of the
            // deletion region left to the startCoord.

            // Deleting right half of DWC at startCoord?
            [self erasePossibleDoubleWidthCharInLineNumber:startCoord.y
                                          startingAtOffset:startCoord.x - 1
                                                  withChar:[self defaultChar]];

            // Deleting left half of DWC at end of run to be deleted?
            [self erasePossibleDoubleWidthCharInLineNumber:startCoord.y
                                          startingAtOffset:startCoord.x + n - 1
                                                  withChar:[self defaultChar]];

            // When there's a scroll region, are we moving the left half of a DWC w/o right half?
            [self erasePossibleDoubleWidthCharInLineNumber:startCoord.y
                                          startingAtOffset:self.rightMargin
                                                  withChar:[self defaultChar]];
            const int numCharsToMove = rightMargin - startCoord.x - n + 1;

            // Try to clean up DWC_SKIP+EOL_DWC pair, if needed.
            if (rightMargin == size_.width - 1 &&
                ScreenCharIsDWC_SKIP(aLine[rightMargin])) {
                // Moving DWC_SKIP left will break it.
                aLine[rightMargin] = aLine[rightMargin + 1];
                aLine[rightMargin].complexChar = NO;
                aLine[rightMargin].code = 0;
            }
            if (rightMargin == size_.width - 1 &&
                aLine[size_.width].code == EOL_DWC) {
                // When the previous if statement is true, this one should also always be true.
                aLine[size_.width].code = EOL_HARD;
            }

            memmove(aLine + startCoord.x,
                    aLine + startCoord.x + n,
                    numCharsToMove * sizeof(screen_char_t));
            [self markCharsDirty:YES
                      inRectFrom:VT100GridCoordMake(startCoord.x, lineNumber)
                              to:VT100GridCoordMake(startCoord.x + numCharsToMove - 1, lineNumber)];
            [eaIndex copyFrom:eaIndex source:startCoord.x + n destination:startCoord.x count:numCharsToMove];
        }
        // Erase chars on right side of line.
        [self setCharsFrom:VT100GridCoordMake(rightMargin - n + 1, lineNumber)
                        to:VT100GridCoordMake(rightMargin, lineNumber)
                    toChar:defaultChar
        externalAttributes:nil];
    }
}

- (void)scrollDown {
    [self scrollRect:[self scrollRegionRect] downBy:1 softBreak:NO];
}

- (void)moveContentLeft:(int)n {
    int x = 0;
    if (self.useScrollRegionCols && self.cursorX >= self.leftMargin && self.cursorX <= self.rightMargin) {
        // Cursor is within the scroll region so move the content within the scroll region.
        x = self.leftMargin;
    }
    for (int i = self.topMargin; i <= self.bottomMargin; i++) {
        [self deleteChars:n startingAt:VT100GridCoordMake(x, i)];
    }
}

- (void)moveContentRight:(int)n {
    int x = 0;
    if (self.useScrollRegionCols && self.cursorX >= self.leftMargin && self.cursorX <= self.rightMargin) {
        // Cursor is within the scroll region so move the content within the scroll region.
        x = self.leftMargin;
    }
    const screen_char_t c = [self defaultChar];
    for (int i = self.topMargin; i <= self.bottomMargin; i++) {
        [self insertChar:c externalAttributes:nil at:VT100GridCoordMake(x, i) times:n];
    }
}

- (void)scrollRect:(VT100GridRect)rect downBy:(int)distance softBreak:(BOOL)softBreak {
    DLog(@"scrollRect:%d,%d %dx%d downBy:%d",
             rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, distance);
    if (distance == 0) {
        return;
    }
    int direction = (distance > 0) ? 1 : -1;

    screen_char_t defaultChar = [self defaultChar];

    if (rect.size.width > 0 && rect.size.height > 0) {
        int rightIndex = rect.origin.x + rect.size.width - 1;
        int bottomIndex = rect.origin.y + rect.size.height - 1;
        int sourceHeight = rect.size.height - abs(distance);
        int sourceIndex = (direction > 0 ? bottomIndex - distance :
                           rect.origin.y - distance);
        int destIndex = direction > 0 ? bottomIndex : rect.origin.y;
        int continuation = (rightIndex == size_.width - 1) ? 1 : 0;

        // Fix up split DWCs that will be broken.
        if (continuation) {
            // The last line scrolled may have had a split-dwc. Replace its continuation mark with a hard
            // newline.
            [self erasePossibleSplitDwcAtLineNumber:bottomIndex];
            [self erasePossibleSplitDwcAtLineNumber:rect.origin.y - 1];
        }

        // clear DWC's that are about to get orphaned
        for (int iteration = 0; iteration < rect.size.height; iteration++) {
            const int lineNumber = iteration + rect.origin.y;
            [self erasePossibleDoubleWidthCharInLineNumber:lineNumber
                                          startingAtOffset:rect.origin.x - 1
                                                  withChar:defaultChar];
            [self erasePossibleDoubleWidthCharInLineNumber:lineNumber
                                          startingAtOffset:rightIndex
                                                  withChar:defaultChar];
        }

        // Move lines.
        for (int iteration = 0; (iteration < sourceHeight &&
                                 sourceIndex < size_.height &&
                                 destIndex < size_.height &&
                                 sourceIndex >= 0 &&
                                 destIndex >= 0);
             iteration++) {
            screen_char_t *sourceLine = [self screenCharsAtLineNumber:sourceIndex];
            screen_char_t *targetLine = [self screenCharsAtLineNumber:destIndex];

            const int length = rect.size.width + continuation;
            memmove(targetLine + rect.origin.x,
                    sourceLine + rect.origin.x,
                    length * sizeof(screen_char_t));
            [self copyExternalAttributesFrom:VT100GridCoordMake(rect.origin.x, sourceIndex)
                                          to:VT100GridCoordMake(rect.origin.x, destIndex)
                                      length:length];

            sourceIndex -= direction;
            destIndex -= direction;
        }

        [self markCharsDirty:YES
                  inRectFrom:rect.origin
                          to:VT100GridCoordMake(rightIndex, bottomIndex)];

        int lineNumberAboveScrollRegion = rect.origin.y - 1;
        // Fix up broken soft or dwc_skip continuation marks. It could occur on line just above
        // the scroll region.
        if (lineNumberAboveScrollRegion >= 0 &&
            lineNumberAboveScrollRegion < size_.height &&
            rect.origin.x == 0) {
            // Affecting continuation marks on line above/below rect.
            screen_char_t *pred =
                [self screenCharsAtLineNumber:lineNumberAboveScrollRegion];
            if (pred[size_.width].code == EOL_SOFT) {
                pred[size_.width].code = EOL_HARD;
            }
        }
        if (rect.origin.x + rect.size.width == size_.width && !softBreak) {
            // Clean up continuation mark on last line inside scroll region when scrolling down,
            // or last last preserved line when scrolling up, unless we were asked to preserve
            // soft breaks.
            int lastLineOfScrollRegion;
            if (direction > 0) {
                lastLineOfScrollRegion = rect.origin.y + rect.size.height - 1;
            } else {
                lastLineOfScrollRegion = rect.origin.y + rect.size.height - 1 + distance;
            }
            // Affecting continuation mark on first/last line in block
            if (lastLineOfScrollRegion >= 0 && lastLineOfScrollRegion < size_.height) {
                screen_char_t *lastLine =
                    [self screenCharsAtLineNumber:lastLineOfScrollRegion];
                if (lastLine[size_.width].code == EOL_SOFT) {
                    lastLine[size_.width].code = EOL_HARD;
                }
            }
        }

        // Clear region left over.
        if (direction > 0) {
            const VT100GridCoord extent = VT100GridCoordMake(rightIndex, MIN(bottomIndex, rect.origin.y + distance - 1));
            [self setCharsFrom:rect.origin
                            to:extent
                        toChar:defaultChar
            externalAttributes:nil];
        } else {
            const VT100GridCoord origin = VT100GridCoordMake(rect.origin.x, MAX(rect.origin.y, bottomIndex + distance + 1));
            const VT100GridCoord extent = VT100GridCoordMake(rightIndex, bottomIndex);
            [self setCharsFrom:origin
                            to:extent
                        toChar:defaultChar
            externalAttributes:nil];
        }

        if ((rect.origin.x == 0) ^ continuation) {
            // It's possible that either a continuation mark is being moved or a DWC was moved
            // (but not both!), causing a split-dwc continuation mark to become invalid.
            for (int iteration = 0; iteration < rect.size.height; iteration++) {
                [self erasePossibleSplitDwcAtLineNumber:iteration + rect.origin.y];
            }
        }

        // Clean up split-dwc continuation marker on last line if scrolling down, or line before
        // rectangle if scrolling up.
        if (continuation && rect.origin.x == 0) {
            // Moving whole lines
            if (direction > 0) {
                // scrolling down
                [self erasePossibleSplitDwcAtLineNumber:rect.origin.y + rect.size.height - 1];
            } else {
                // scrolling up
                [self erasePossibleSplitDwcAtLineNumber:rect.origin.y - 1];
            }
        }
    }
}

- (void)setContentsFromDVRFrame:(const screen_char_t *)s
                  metadataArray:(iTermMetadata *)sourceMetadataArray
                           info:(DVRFrameInfo)info {
    [self setCharsFrom:VT100GridCoordMake(0, 0)
                    to:VT100GridCoordMake(size_.width - 1, size_.height - 1)
                toChar:[self defaultChar]
    externalAttributes:nil];
    int charsToCopyPerLine = MIN(size_.width, info.width);
    if (size_.width == info.width) {
        // Ok to copy continuation mark.
        charsToCopyPerLine++;
    }
    int sourceLineOffset = 0;
    if (info.height > size_.height) {
        sourceLineOffset = info.height - size_.height;
    }
    if (info.height < size_.height || info.width < size_.width) {
        [self setCharsFrom:VT100GridCoordMake(0, 0)
                        to:VT100GridCoordMake(size_.width - 1, size_.height - 1)
                    toChar:[self defaultChar]
        externalAttributes:nil];
    }
    for (int y = 0; y < MIN(info.height, size_.height); y++) {
        screen_char_t *dest = [self screenCharsAtLineNumber:y];
        const screen_char_t *src = s + ((y + sourceLineOffset) * (info.width + 1));
        memmove(dest, src, sizeof(screen_char_t) * charsToCopyPerLine);
        if (size_.width != info.width) {
            // Not copying continuation marks, set them all to hard.
            dest[size_.width] = dest[size_.width - 1];
            dest[size_.width].code = EOL_HARD;
        }
        if (charsToCopyPerLine < info.width && ScreenCharIsDWC_RIGHT(src[charsToCopyPerLine])) {
            dest[charsToCopyPerLine - 1].code = 0;
            dest[charsToCopyPerLine - 1].complexChar = NO;
        }
        if (charsToCopyPerLine - 1 < info.width && ScreenCharIsTAB_FILLER(src[charsToCopyPerLine - 1])) {
            dest[charsToCopyPerLine - 1].code = '\t';
            dest[charsToCopyPerLine - 1].complexChar = NO;
        }
        [self setMetadata:sourceMetadataArray[y] forLine:y];
    }
    [self markAllCharsDirty:YES updateTimestamps:NO];

    const int yOffset = MAX(0, info.height - size_.height);
    self.cursorX = MIN(size_.width - 1, MAX(0, info.cursorX));
    self.cursorY = MIN(size_.height - 1, MAX(0, info.cursorY - yOffset));
}

- (NSString *)debugString {
    NSMutableString* result = [NSMutableString stringWithString:@""];
    int x, y;
    char line[1000];
    char dirtyline[1000];
    for (y = 0; y < size_.height; ++y) {
        int ox = 0;
        screen_char_t* p = [self screenCharsAtLineNumber:y];
        if (y == screenTop_) {
            [result appendString:@"--- top of buffer ---\n"];
        }
        for (x = 0; x < size_.width; ++x, ++ox) {
            if ([self isCharDirtyAt:VT100GridCoordMake(x, y)]) {
                dirtyline[ox] = '-';
            } else {
                dirtyline[ox] = '.';
            }
            if (y == cursor_.y && x == cursor_.x) {
                if (dirtyline[ox] == '-') {
                    dirtyline[ox] = '=';
                }
                if (dirtyline[ox] == '.') {
                    dirtyline[ox] = ':';
                }
            }
            if (p[x].image) {
                line[ox] = 'I';
            } else if (p[x].code && !p[x].complexChar) {
                if (p[x].code > 0 && p[x].code < 128) {
                    line[ox] = p[x].code;
                } else if (ScreenCharIsDWC_RIGHT(p[x])) {
                    line[ox] = '-';
                } else if (ScreenCharIsTAB_FILLER(p[x])) {
                    line[ox] = ' ';
                } else if (ScreenCharIsDWC_SKIP(p[x])) {
                    line[ox] = '>';
                } else {
                    line[ox] = '?';
                }
            } else {
                line[ox] = '.';
            }
        }
        line[x] = 0;
        dirtyline[x] = 0;
        [result appendFormat:@"%04d: %s %@\n", y, line, [self stringForContinuationMark:p[size_.width].code]];
        [result appendFormat:@"dirty %s%@\n", dirtyline, y == cursor_.y ? @" -cursor-" : @""];
    }
    return result;
}

- (VT100GridRun)gridRunFromRange:(NSRange)range relativeToRow:(int)row {
    const NSInteger longRow = row;
    const NSInteger location = (NSInteger)range.location + longRow * (NSInteger)size_.width;
    const NSInteger length = range.length;
    const NSInteger overage = MAX(0, -location);
    const NSInteger adjustedLocation = location + overage;
    const NSInteger adjustedLength = length - overage;

    if (adjustedLocation < 0 || adjustedLength < 0) {
        return VT100GridRunMake(0, 0, 0);
    }

    return VT100GridRunMake(adjustedLocation % size_.width,
                            adjustedLocation / size_.width,
                            adjustedLength);
}

- (BOOL)restoreScreenFromLineBuffer:(LineBuffer *)lineBuffer
                    withDefaultChar:(screen_char_t)defaultChar
                  maxLinesToRestore:(int)maxLines {
    // Move scrollback lines into screen
    int numLinesInLineBuffer = [lineBuffer numLinesWithWidth:size_.width];
    int destLineNumber;
    if (numLinesInLineBuffer >= size_.height) {
        destLineNumber = size_.height - 1;
    } else {
        destLineNumber = numLinesInLineBuffer - 1;
    }
    destLineNumber = MIN(destLineNumber, maxLines - 1);

    screen_char_t *defaultLine = [[self lineOfWidth:size_.width
                                     filledWithChar:defaultChar] mutableBytes];

    BOOL foundCursor = NO;
    BOOL prevLineStartsWithDoubleWidth = NO;
    int numPopped = 0;
    while (destLineNumber >= 0) {
        screen_char_t *dest = [self screenCharsAtLineNumber:destLineNumber];
        memcpy(dest, defaultLine, sizeof(screen_char_t) * size_.width);
        if (!foundCursor) {
            int tempCursor = cursor_.x;
            foundCursor = [lineBuffer getCursorInLastLineWithWidth:size_.width atX:&tempCursor];
            if (foundCursor) {
                VT100GridCoord newCursorCoord = VT100GridCoordMake(tempCursor % size_.width,
                                                                   destLineNumber + tempCursor / size_.width);
                if (tempCursor / size_.width > 0 && newCursorCoord.x == 0) {
                    // Allow the cursor to enter the right margin.
                    newCursorCoord.x = size_.width;
                    newCursorCoord.y -= 1;
                }
                [self setCursor:newCursorCoord];
            }
        }
        int cont;
        iTermImmutableMetadata metadata;
        screen_char_t continuation;
        ++numPopped;
        assert([lineBuffer popAndCopyLastLineInto:dest
                                            width:size_.width
                                includesEndOfLine:&cont
                                         metadata:&metadata
                                     continuation:&continuation]);
        [[self lineInfoAtLineNumber:destLineNumber] setMetadataFromImmutable:metadata];
        if (cont && dest[size_.width - 1].code == 0 && prevLineStartsWithDoubleWidth) {
            // If you pop a soft-wrapped line that's a character short and the
            // line below it starts with a DWC, it's safe to conclude that a DWC
            // was wrapped.
            ScreenCharSetDWC_SKIP(&dest[size_.width - 1]);
            cont = EOL_DWC;
        }
        if (ScreenCharIsDWC_RIGHT(dest[1])) {
            prevLineStartsWithDoubleWidth = YES;
        } else {
            prevLineStartsWithDoubleWidth = NO;
        }
        dest[size_.width] = continuation;
        dest[size_.width].code = cont;
        if (cont == EOL_DWC) {
            ScreenCharSetDWC_SKIP(&dest[size_.width - 1]);
        }
        --destLineNumber;
    }
    return foundCursor;
}

- (VT100GridCoord)clamp:(VT100GridCoord)coord {
    return VT100GridCoordMake(MEDIAN(0, coord.x, MAX(0, self.size.width - 1)),
                              MEDIAN(0, coord.y, MAX(0, self.size.height - 1)));
}

- (void)clampCursorPositionToValid
{
    if (cursor_.x >= size_.width) {
        // Allow the cursor to enter the right margin.
        self.cursorX = size_.width;
    }
    if (cursor_.y >= size_.height) {
        self.cursorY = size_.height - 1;
    }
}

- (screen_char_t *)resultLine {
    const int length = sizeof(screen_char_t) * (size_.width + 1);
    if (resultLine_.length != length) {
        resultLine_ = [[NSMutableData alloc] initWithLength:length];
    }
    return (screen_char_t *)[resultLine_ mutableBytes];
}

- (void)moveCursorToLeftMargin {
    const int leftMargin = [self leftMargin];
    self.cursorX = leftMargin;
}

- (NSArray *)rectsForRun:(VT100GridRun)run {
    NSMutableArray *rects = [NSMutableArray array];
    int length = run.length;
    int x = run.origin.x;
    for (int y = run.origin.y; length > 0; y++) {
        int endX = MIN(size_.width - 1, x + length - 1);
        [rects addObject:[NSValue valueWithGridRect:VT100GridRectMake(x, y, endX - x + 1, 1)]];
        length -= (endX - x + 1);
        x = 0;
    }
    assert(length >= 0);
    return rects;
}

- (int)leftMargin {
    return useScrollRegionCols_ ? scrollRegionCols_.location : 0;
}

- (int)rightMargin {
    return useScrollRegionCols_ ? VT100GridRangeMax(scrollRegionCols_) : size_.width - 1;
}

- (int)topMargin {
    return scrollRegionRows_.location;
}

- (int)bottomMargin {
    return VT100GridRangeMax(scrollRegionRows_);
}

- (VT100GridRect)scrollRegionRect {
    return VT100GridRectMake(self.leftMargin,
                             self.topMargin,
                             self.rightMargin - self.leftMargin + 1,
                             self.bottomMargin - self.topMargin + 1);
}

// . = null cell
// ? = non-ascii
// - = righthalf of dwc
// > = split-dwc (in rightmost column only)
// U = complex unicode char
// anything else = literal ascii char
- (NSString *)compactLineDump {
    NSMutableString *dump = [NSMutableString string];
    for (int y = 0; y < size_.height; y++) {
        screen_char_t *line = [self screenCharsAtLineNumber:y];
        for (int x = 0; x < size_.width; x++) {
            char c = line[x].code;
            if (line[x].code == 0) c = '.';
            if (line[x].code > 127) c = '?';
            if (ScreenCharIsDWC_RIGHT(line[x])) c = '-';
            if (ScreenCharIsDWC_SKIP(line[x])) {
                assert(x == size_.width - 1);
                c = '>';
            }
            if (line[x].complexChar) c = 'U';
            [dump appendFormat:@"%c", c];
        }
        if (y != size_.height - 1) {
            [dump appendString:@"\n"];
        }
    }
    return dump;
}

- (NSString *)compactLineDumpWithTimestamps {
    NSMutableString *dump = [NSMutableString string];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    [fmt setTimeStyle:NSDateFormatterLongStyle];

    for (int y = 0; y < size_.height; y++) {
        screen_char_t *line = [self screenCharsAtLineNumber:y];
        for (int x = 0; x < size_.width; x++) {
            char c = line[x].code;
            if (line[x].code == 0) c = '.';
            if (line[x].code > 127) c = '?';
            if (ScreenCharIsDWC_RIGHT(line[x])) c = '-';
            if (ScreenCharIsDWC_SKIP(line[x])) {
                assert(x == size_.width - 1);
                c = '>';
            }
            if (line[x].complexChar) c = 'U';
            [dump appendFormat:@"%c", c];
        }
        NSDate* date = [NSDate dateWithTimeIntervalSinceReferenceDate:[[self lineInfoAtLineNumber:y] metadata].timestamp];
        [dump appendFormat:@"  | %@", [fmt stringFromDate:date]];
        if (y != size_.height - 1) {
            [dump appendString:@"\n"];
        }
    }
    return dump;
}

- (NSString *)compactLineDumpWithContinuationMarks {
    NSMutableString *dump = [NSMutableString string];
    for (int y = 0; y < size_.height; y++) {
        screen_char_t *line = [self screenCharsAtLineNumber:y];
        for (int x = 0; x < size_.width; x++) {
            char c = line[x].code;
            if (line[x].code == 0) c = '.';
            if (line[x].code > 127) c = '?';
            if (ScreenCharIsDWC_RIGHT(line[x])) c = '-';
            if (ScreenCharIsDWC_SKIP(line[x])) {
                assert(x == size_.width - 1);
                c = '>';
            }
            if (line[x].complexChar) c = 'U';
            [dump appendFormat:@"%c", c];
        }
        switch (line[size_.width].code) {
            case EOL_HARD:
                [dump appendString:@"!"];
                break;
            case EOL_SOFT:
                [dump appendString:@"+"];
                break;
            case EOL_DWC:
                [dump appendString:@">"];
                break;
            default:
                [dump appendString:@"?"];
                break;
        }
        if (y != size_.height - 1) {
            [dump appendString:@"\n"];
        }
    }
    return dump;
}

- (NSString *)compactDirtyDump {
    NSMutableString *dump = [NSMutableString string];
    for (int y = 0; y < size_.height; y++) {
        for (int x = 0; x < size_.width; x++) {
            if ([self isCharDirtyAt:VT100GridCoordMake(x, y)]) {
                [dump appendString:@"d"];
            } else {
                [dump appendString:@"c"];
            }
        }
        if (y != size_.height - 1) {
            [dump appendString:@"\n"];
        }
    }
    return dump;
}

- (void)insertChar:(screen_char_t)c externalAttributes:(iTermExternalAttribute *)attrs at:(VT100GridCoord)pos times:(int)n {
    if (pos.x > self.rightMargin ||  // TODO: Test right-margin boundary case
        pos.x < self.leftMargin) {
        return;
    }
    if (n + pos.x > self.rightMargin) {
        n = self.rightMargin - pos.x + 1;
    }
    if (n < 1) {
        return;
    }

    screen_char_t *line = [self screenCharsAtLineNumber:pos.y];
    int charsToMove = self.rightMargin - pos.x - n + 1;

    // Splitting a dwc in half?
    [self erasePossibleDoubleWidthCharInLineNumber:pos.y
                                  startingAtOffset:pos.x - 1
                                          withChar:[self defaultChar]];

    // If the last char to be moved is the left half of a DWC, erase it.
    [self erasePossibleDoubleWidthCharInLineNumber:pos.y
                                  startingAtOffset:pos.x + charsToMove - 1
                                          withChar:[self defaultChar]];

    // When there's a scroll region, does the right margin overlap half a dwc?
    [self erasePossibleDoubleWidthCharInLineNumber:pos.y
                                  startingAtOffset:self.rightMargin
                                          withChar:[self defaultChar]];

    memmove(line + pos.x + n,
            line + pos.x,
            charsToMove * sizeof(screen_char_t));
    iTermExternalAttributeIndex *eaIndex = [self externalAttributesOnLine:pos.y
                                                           createIfNeeded:attrs != nil];
    [eaIndex copyFrom:eaIndex source:pos.x destination:pos.x + n count:charsToMove];

    // Try to clean up DWC_SKIP+EOL_DWC pair, if needed.
    if (self.rightMargin == size_.width - 1 &&
        line[size_.width].code == EOL_DWC) {
        // The line shifting means a split DWC is gone. The wrapping changes to hard if the last
        // code is 0 because soft wrapping doesn't make sense across a null code.
        line[size_.width].code = line[size_.width - 1].code ? EOL_SOFT : EOL_HARD;
    }

    if (size_.width > 0 &&
        self.rightMargin == size_.width - 1 &&
        line[size_.width].code == EOL_SOFT &&
        line[size_.width - 1].code == 0) {
        // If the last char becomes a null, convert to a hard line break.
        line[size_.width].code = EOL_HARD;
    }

    [self markCharsDirty:YES
              inRectFrom:VT100GridCoordMake(MIN(self.rightMargin - 1, pos.x), pos.y)
                      to:VT100GridCoordMake(self.rightMargin, pos.y)];
    [self setCharsFrom:pos to:VT100GridCoordMake(pos.x + n - 1, pos.y) toChar:c externalAttributes:attrs];
}

- (NSArray *)orderedLines {
    NSMutableArray *array = [NSMutableArray array];
    for (int i = 0; i < size_.height; i++) {
        [array addObject:[self lineDataAtLineNumber:i]];
    }
    return array;
}

- (NSArray<VT100LineInfo *> *)orderedLineInfos {
    NSMutableArray *array = [NSMutableArray array];
    for (int i = 0; i < size_.height; i++) {
        [array addObject:[self lineInfoAtLineNumber:i]];
    }
    return array;
}

- (NSDictionary *)dictionaryValue {
    return @{ kGridCursorKey: [NSDictionary dictionaryWithGridCoord:cursor_],
              kGridScrollRegionRowsKey: [NSDictionary dictionaryWithGridRange:scrollRegionRows_],
              kGridScrollRegionColumnsKey: [NSDictionary dictionaryWithGridRange:scrollRegionCols_],
              kGridUseScrollRegionColumnsKey: @(useScrollRegionCols_),
              kGridSizeKey: [NSDictionary dictionaryWithGridSize:size_] };
}

+ (VT100GridSize)sizeInStateDictionary:(NSDictionary *)dict {
    VT100GridSize size = [dict[kGridSizeKey] gridSize];
    return size;
}

- (void)setStateFromDictionary:(NSDictionary *)dict {
    if (!dict || [dict isKindOfClass:[NSNull class]]) {
        return;
    }
    VT100GridSize size = [dict[kGridSizeKey] gridSize];

    // Saved values only make sense if the size is at least as large as when the state was saved.
    // When restoring from a saved arrangement, the initial grid size is a guess which is a bit too
    // wide when legacy scrollbars are in use.
    if (size.width <= size_.width && size.height <= size_.height) {
        cursor_ = [dict[kGridCursorKey] gridCoord];
        scrollRegionRows_ = [dict[kGridScrollRegionRowsKey] gridRange];
        scrollRegionCols_ = [dict[kGridScrollRegionColumnsKey] gridRange];
        useScrollRegionCols_ = [dict[kGridUseScrollRegionColumnsKey] boolValue];
    }
}

- (void)resetTimestamps {
    for (VT100LineInfo *info in lineInfos_) {
        [info resetMetadata];
    }
}

- (void)restorePreferredCursorPositionIfPossible {
    if (_preferredCursorPosition.x >= 0 &&
        _preferredCursorPosition.y >= 0 &&
        _preferredCursorPosition.x <= size_.width &&
        _preferredCursorPosition.y < size_.height) {
        DLog(@"Restore preferred cursor position to %@", VT100GridCoordDescription(_preferredCursorPosition));
        self.cursor = _preferredCursorPosition;
        _preferredCursorPosition = VT100GridCoordMake(-1, -1);
    }
}

- (VT100GridSize)sizeRespectingRegionConditionally {
    if (self.cursor.x >= self.leftMargin &&
        self.cursor.x <= self.rightMargin &&
        self.cursor.y >= self.topMargin &&
        self.cursor.y <= self.bottomMargin) {
        return VT100GridSizeMake(self.rightMargin - self.leftMargin + 1,
                                 self.bottomMargin - self.topMargin + 1);
    }
    return self.size;
}

- (void)setContinuationMarkOnLine:(int)line to:(unichar)code {
    screen_char_t *chars = [self screenCharsAtLineNumber:line];
    assert(chars);
    chars[size_.width].code = code;
}

- (void)encode:(id<iTermEncoderAdapter>)encoder {
    NSArray<NSArray *> *metadata = [[self orderedLineInfos] mapWithBlock:^id(VT100LineInfo *anObject) {
        return anObject.encodedMetadata;
    }];
    NSArray<NSData *> *lines = [[NSArray sequenceWithRange:NSMakeRange(0, size_.height)] mapWithBlock:^id(NSNumber *i) {
        return [self lineDataAtLineNumber:i.intValue];
    }];
    NSArray<NSData *> *legacyLines = [lines mapEnumeratedWithBlock:^id(NSUInteger i, NSData *modernData, BOOL *stop) {
        return [modernData legacyScreenCharArrayWithExternalAttributes:[self externalAttributesOnLine:i createIfNeeded:NO]];
    }];
    [encoder mergeDictionary:@{
        @"size": [NSDictionary dictionaryWithGridSize:size_],
        @"lines v2": lines,
        @"lines": legacyLines,  // works around a crash pre-3.5 when downgrading with saved state
        @"metadata": metadata,
        @"cursor": [NSDictionary dictionaryWithGridCoord:cursor_],
        @"scrollRegionRows": [NSDictionary dictionaryWithGridRange:scrollRegionRows_],
        @"scrollRegionCols": [NSDictionary dictionaryWithGridRange:scrollRegionCols_],
        @"useScrollRegionCols": @(useScrollRegionCols_),
        @"savedDefaultCharData": [NSData dataWithBytes:&savedDefaultChar_ length:sizeof(savedDefaultChar_)]
    }];
}

- (void)mutateCellsInRect:(VT100GridRect)rect
                    block:(void (^NS_NOESCAPE)(VT100GridCoord, screen_char_t *, iTermExternalAttribute **, BOOL *))block {
    for (int y = MAX(0, rect.origin.y); y < MIN(size_.height, rect.origin.y + rect.size.height); y++) {
        NSMutableData *data = [self lineDataAtLineNumber:y];
        screen_char_t *line = (screen_char_t *)data.mutableBytes;
        iTermExternalAttributeIndex *eaIndex = [self externalAttributesOnLine:y
                                                               createIfNeeded:NO];
        const int left = MAX(0, rect.origin.x);
        const int right = MIN(size_.width, rect.origin.x + rect.size.width);
        [self markCharsDirty:YES inRun:VT100GridRunMake(left, y, right - left)];

        for (int x = left; x < right; x++) {
            BOOL stop = NO;
            iTermExternalAttribute *eaOrig = eaIndex[x];
            iTermExternalAttribute *ea = eaOrig;
            block(VT100GridCoordMake(x, y), &line[x], &ea, &stop);
            if (ea != eaOrig) {
                if (!eaIndex) {
                    eaIndex = [self externalAttributesOnLine:y createIfNeeded:YES];
                }
                eaIndex[x] = ea;
            }
            if (stop) {
                return;
            }
        }
    }
}

- (void)enumerateCellsInRect:(VT100GridRect)rect block:(void (^)(VT100GridCoord, screen_char_t, iTermExternalAttribute *, BOOL *))block {
    for (int y = MAX(0, rect.origin.y); y < MIN(size_.height, rect.origin.y + rect.size.height); y++) {
        NSMutableData *data = [self lineDataAtLineNumber:y];
        screen_char_t *line = (screen_char_t *)data.mutableBytes;
        iTermExternalAttributeIndex *eaIndex = [self externalAttributesOnLine:y
                                                               createIfNeeded:NO];
        const int left = MAX(0, rect.origin.x);
        const int right = MIN(size_.width, rect.origin.x + rect.size.width);
        [self markCharsDirty:YES inRun:VT100GridRunMake(left, y, right - left)];

        for (int x = left; x < right; x++) {
            BOOL stop = NO;
            block(VT100GridCoordMake(x, y), line[x], eaIndex[x], &stop);
            if (stop) {
                return;
            }
        }
    }
}

#pragma mark - Private

- (NSMutableArray *)linesWithSize:(VT100GridSize)size {
    NSMutableArray *lines = [[NSMutableArray alloc] init];
    for (int i = 0; i < size.height; i++) {
        [lines addObject:[[self defaultLineOfWidth:size.width] mutableCopy]];
    }
    return lines;
}

- (NSMutableArray *)lineInfosWithSize:(VT100GridSize)size {
    NSMutableArray *dirty = [NSMutableArray array];
    for (int i = 0; i < size.height; i++) {
        [dirty addObject:[[VT100LineInfo alloc] initWithWidth:size_.width]];
    }
    return dirty;
}

- (screen_char_t)defaultChar {
    assert(delegate_);
    screen_char_t c = { 0 };
    screen_char_t fg = [delegate_ gridForegroundColorCode];
    screen_char_t bg = [delegate_ gridBackgroundColorCode];

    c.code = 0;
    c.complexChar = NO;
    CopyForegroundColor(&c, fg);
    CopyBackgroundColor(&c, bg);

    c.underline = NO;
    c.strikethrough = NO;
    c.underlineStyle = VT100UnderlineStyleSingle;
    c.image = 0;

    return c;
}

- (NSMutableData *)lineOfWidth:(int)width filledWithChar:(screen_char_t)c {
    NSMutableData *data = [NSMutableData dataWithLength:sizeof(screen_char_t) * (width + 1)];
    screen_char_t *line = data.mutableBytes;
    for (int i = 0; i < width + 1; i++) {
        line[i] = c;
    }
    return data;
}

- (NSMutableData *)defaultLineOfWidth:(int)width {
    size_t length = (width + 1) * sizeof(screen_char_t);

    screen_char_t *existingCache = (screen_char_t *)[cachedDefaultLine_ mutableBytes];
    screen_char_t currentDefaultChar = [self defaultChar];
    if (cachedDefaultLine_ &&
        [cachedDefaultLine_ length] == length &&
        length > 0 &&
        !memcmp(existingCache, &currentDefaultChar, sizeof(screen_char_t))) {
        return cachedDefaultLine_;
    }

    NSMutableData *line = [NSMutableData dataWithLength:length];

    cachedDefaultLine_ = nil;
    [self clearLineData:line];
    cachedDefaultLine_ = line;

    return line;
}

// Not double-width char safe.
- (void)clearScreenChars:(screen_char_t *)chars inRange:(VT100GridRange)range {
    if (cachedDefaultLine_) {
        // Only do this if there is a cached line; otherwise there's an infinite recursion since
        // -defaultLineOfWidth indirectly calls this method.
        NSData *defaultLine = [self defaultLineOfWidth:size_.width];
        memcpy(chars + range.location,
               defaultLine.bytes,
               sizeof(screen_char_t) * MIN(size_.width, range.length));
        if (range.length > size_.width) {
            const screen_char_t c = chars[range.location];
            for (int i = range.location + MIN(size_.width, range.length);
                 i < range.location + range.length;
                 i++) {
                chars[i] = c;
            }
        }
    } else {
        // Rarely called slow path.
        screen_char_t c = [self defaultChar];
        for (int i = range.location; i < range.location + range.length; i++) {
            chars[i] = c;
        }
    }
}

- (void)clearLineData:(NSMutableData *)line {
    int length = (int)([line length] / sizeof(screen_char_t));
    // Clear length+1 so that continuation is set properly
    [self clearScreenChars:[line mutableBytes] inRange:VT100GridRangeMake(0, length)];
    screen_char_t *chars = (screen_char_t *)[line mutableBytes];
    int width = [line length] / sizeof(screen_char_t) - 1;
    chars[width].code = EOL_HARD;
}

// Returns number of lines dropped from line buffer because it exceeded its size (always 0 or 1).
- (int)appendLineToLineBuffer:(LineBuffer *)lineBuffer
          unlimitedScrollback:(BOOL)unlimitedScrollback {
    if (!lineBuffer) {
        return 0;
    }
    screen_char_t *line = [self screenCharsAtLineNumber:0];
    int len = [self lengthOfLine:line];
    int continuationMark = line[size_.width].code;
    if (continuationMark == EOL_DWC && len == size_.width) {
        --len;
    }
    [lineBuffer appendLine:line
                    length:len
                   partial:(continuationMark != EOL_HARD)
                     width:size_.width
                  metadata:[[self lineInfoAtLineNumber:0] immutableMetadata]
              continuation:line[size_.width]];
    int dropped;
    if (!unlimitedScrollback) {
        dropped = [lineBuffer dropExcessLinesWithWidth:size_.width];
    } else {
        dropped = 0;
    }

    return dropped;
}

- (BOOL)haveColumnScrollRegion {
    return (useScrollRegionCols_ &&
            (self.scrollLeft != 0 || self.scrollRight != size_.width - 1));
}

- (BOOL)haveRowScrollRegion {
    return !(self.topMargin == 0 && self.bottomMargin == size_.height - 1);;
}

- (BOOL)haveScrollRegion {
    return [self haveRowScrollRegion] || [self haveColumnScrollRegion];
}

- (int)cursorLineNumberIncludingPrecedingWrappedLines {
    for (int i = cursor_.y - 1; i >= 0; i--) {
        int mark = [self continuationMarkForLineNumber:i];
        if (mark == EOL_HARD) {
            return i + 1;
        }
    }
    return 0;
}

// NOTE: Returns -1 if there are no non-empty lines.
- (int)lineNumberOfLastNonEmptyLine {
    int y;
    for (y = size_.height - 1; y >= 0; --y) {
        if ([self lengthOfLineNumber:y] > 0) {
            return y;
        }
    }
    return -1;
}

// Warning: does not set dirty.
- (void)setSize:(VT100GridSize)newSize {
    [self setSize:newSize withSideEffects:YES];
}

- (void)setSize:(VT100GridSize)newSize withSideEffects:(BOOL)withSideEffects {
    if (newSize.width != size_.width || newSize.height != size_.height) {
        DLog(@"Grid for %@ resized to %@", self.delegate, VT100GridSizeDescription(newSize));
        size_ = newSize;
        lines_ = [self linesWithSize:newSize];
        lineInfos_ = [self lineInfosWithSize:newSize];

        scrollRegionRows_.location = MIN(scrollRegionRows_.location, size_.height - 1);
        scrollRegionRows_.length = MIN(scrollRegionRows_.length,
                                       size_.height - scrollRegionRows_.location);

        scrollRegionCols_.location = MIN(scrollRegionCols_.location, size_.width - 1);
        scrollRegionCols_.length = MIN(scrollRegionCols_.length,
                                       size_.width - scrollRegionCols_.location);

        cursor_.x = MIN(cursor_.x, size_.width - 1);
        self.cursorY = MIN(cursor_.y, size_.height - 1);
        if (withSideEffects) {
            [self.delegate gridDidResize];
        }
    }
}

- (VT100GridCoord)coordinateBefore:(VT100GridCoord)coord movedBackOverDoubleWidth:(BOOL *)dwc {
    // set cx, cy to the char before the given coordinate.
    VT100GridCoord invalid = VT100GridCoordMake(-1, -1);
    int cx = coord.x;
    int cy = coord.y;
    if (cx == self.leftMargin || cx == 0) {
        cx = self.rightMargin + 1;
        --cy;
        if (cy < 0) {
            return invalid;
        }
        if (![self haveColumnScrollRegion]) {
            switch ([self continuationMarkForLineNumber:cy]) {
                case EOL_HARD:
                    return invalid;
                case EOL_SOFT:
                    // Ok to wrap around
                    break;
                case EOL_DWC:
                    // Ok to wrap around, but move back over presumed DWC_SKIP at line[rightMargin-1].
                    cx--;
                    if (cx < 0) {
                        return invalid;
                    }
                    break;
            }
        }
    }
    --cx;
    if (cx < 0 || cy < 0) {
        // can't affect characters above screen so have it stand alone. cx really should never be
        // less than zero, but paranoia.
        return invalid;
    }

    screen_char_t *line = [self screenCharsAtLineNumber:cy];
    if (ScreenCharIsDWC_RIGHT(line[cx])) {
        if (cx > 0) {
            if (dwc) {
                *dwc = YES;
            }
            cx--;
        } else {
            // This should never happen.
            return invalid;
        }
    } else if (dwc) {
        *dwc = NO;
    }

    return VT100GridCoordMake(cx, cy);
}

- (screen_char_t)characterAt:(VT100GridCoord)coord {
    if (coord.y < 0 || coord.y >= self.size.height || coord.x < 0 || coord.x > self.size.width) {
        ITBetaAssert(NO, @"Asked for %@ in %@", VT100GridCoordDescription(coord), self);
        screen_char_t defaultChar = { 0 };
        return defaultChar;
    } else if (coord.x == self.size.width) {
        screen_char_t defaultChar = { 0 };
        return defaultChar;
    }
    screen_char_t *line = [self screenCharsAtLineNumber:coord.y];
    return line[coord.x];
}

- (NSString *)stringForCharacterAt:(VT100GridCoord)coord {
    screen_char_t *theLine = [self screenCharsAtLineNumber:coord.y];
    if (!theLine) {
        return nil;
    }
    screen_char_t theChar = theLine[coord.x];
    if (theChar.code == 0 && !theChar.complexChar) {
        return nil;
    }
    if (theChar.complexChar) {
        return ComplexCharToStr(theChar.code);
    } else {
        return [NSString stringWithFormat:@"%C", theChar.code];
    }
}

- (BOOL)haveDoubleWidthExtensionAt:(VT100GridCoord)coord {
    screen_char_t sct = [self characterAt:coord];
    return !sct.complexChar && (ScreenCharIsDWC_RIGHT(sct) || ScreenCharIsDWC_SKIP(sct));
}

- (VT100GridCoord)successorOf:(VT100GridCoord)origin {
    VT100GridCoord coord = origin;
    coord.x += 1;
    BOOL checkedForDWC = NO;
    if (coord.x < self.size.width && [self haveDoubleWidthExtensionAt:coord]) {
        coord.x += 1;
        checkedForDWC = YES;
    }
    if (coord.x >= self.size.width) {
        coord.x = 0;
        coord.y += 1;
        if (coord.y >= self.size.height) {
            return VT100GridCoordMake(-1, -1);
        }
        if (!checkedForDWC && [self haveDoubleWidthExtensionAt:coord]) {
            coord.x++;
        }
    }
    return coord;
}

#ifdef VERBOSE_STRING
static void DumpBuf(screen_char_t* p, int n) {
    for (int i = 0; i < n; ++i) {
        NSLog(@"%3d: \"%@\" (0x%04x)", i, ScreenCharToStr(&p[i]), (int)p[i].code);
    }
}
#endif

- (void)erasePossibleSplitDwcAtLineNumber:(int)lineNumber {
    if (lineNumber < 0) {
        return;
    }
    screen_char_t *line = [self screenCharsAtLineNumber:lineNumber];
    if (line[size_.width].code == EOL_DWC) {
        line[size_.width].code = EOL_HARD;
        if (ScreenCharIsDWC_SKIP(line[size_.width - 1])) {  // This really should always be the case.
            line[size_.width - 1].code = 0;
            [self eraseExternalAttributesAt:VT100GridCoordMake(size_.width - 1, lineNumber)
                                      count:1];
        } else {
            NSLog(@"Warning! EOL_DWC without DWC_SKIP at line %d", lineNumber);
        }
    }
}

- (void)eraseExternalAttributesAt:(VT100GridCoord)coord count:(int)count{
    iTermExternalAttributeIndex *eaIndex = [self externalAttributesOnLine:coord.y
                                                           createIfNeeded:NO];
    [eaIndex eraseInRange:VT100GridRangeMake(coord.x, count)];
}

- (void)copyExternalAttributesFrom:(VT100GridCoord)sourceCoord
                                to:(VT100GridCoord)destinationCoord
                            length:(int)length {
    iTermExternalAttributeIndex *source = [self externalAttributesOnLine:sourceCoord.y
                                                          createIfNeeded:NO];
    iTermExternalAttributeIndex *dest = [self externalAttributesOnLine:destinationCoord.y
                                         createIfNeeded:source != nil];
    if (!source && !dest) {
        return;
    }
    if (!dest) {
        dest = [self createExternalAttributesForLine:destinationCoord.y];
    }
    [dest copyFrom:source
            source:sourceCoord.x
       destination:destinationCoord.x
             count:length];
}

- (iTermExternalAttributeIndex *)createExternalAttributesForLine:(int)line {
    VT100LineInfo *info = [self lineInfoAtLineNumber:line];
    return [info externalAttributesCreatingIfNeeded:YES];
}

- (BOOL)erasePossibleDoubleWidthCharInLineNumber:(int)lineNumber
                                startingAtOffset:(int)offset
                                        withChar:(screen_char_t)c {
    screen_char_t *aLine = [self screenCharsAtLineNumber:lineNumber];
    if (offset >= 0 && offset < size_.width - 1 && ScreenCharIsDWC_RIGHT(aLine[offset + 1])) {
        aLine[offset] = c;
        aLine[offset + 1] = c;
        [self eraseExternalAttributesAt:VT100GridCoordMake(offset, lineNumber)
                                  count:2];
        [self markCharDirty:YES
                         at:VT100GridCoordMake(offset, lineNumber)
            updateTimestamp:YES];
        [self markCharDirty:YES
                         at:VT100GridCoordMake(offset + 1, lineNumber)
            updateTimestamp:YES];

        if (offset == 0 && lineNumber > 0) {
            [self erasePossibleSplitDwcAtLineNumber:lineNumber - 1];
        }

        return YES;
    } else {
        return NO;
    }
}

- (NSString *)stringForContinuationMark:(int)c {
    switch (c) {
        case EOL_HARD:
            return @"[hard]";
        case EOL_SOFT:
            return @"[soft]";
        case EOL_DWC:
            return @"[dwc]";
        default:
            return @"[?]";
    }
}

// Number of cells between two coords, including both endpoints For example, with a grid of
// xxyy
// yyxx
// The number of cells from (2,0) to (1,1) is 4 (the cells containing "y").
- (int)numCellsFrom:(VT100GridCoord)from to:(VT100GridCoord)to {
    VT100GridRun run = VT100GridRunFromCoords(from, to, size_.width);
    return run.length;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p size=%d x %d, cursor @ (%d,%d)>",
            [self class], self, size_.width, size_.height, cursor_.x, cursor_.y];
}

// Returns NSString representation of line. This exists to facilitate debugging only.
+ (NSString *)stringForScreenChars:(screen_char_t *)theLine length:(int)length
{
    NSMutableString* result = [NSMutableString stringWithCapacity:length];

    for (int i = 0; i < length; i++) {
        [result appendString:ScreenCharToStr(&theLine[i])];
    }

    if (theLine[length].code) {
        [result appendString:@"\n"];
    }

    return result;
}

- (void)resetScrollRegions {
    scrollRegionRows_ = VT100GridRangeMake(0, size_.height);
    scrollRegionCols_ = VT100GridRangeMake(0, size_.width);
}

#pragma mark - NSCopying

- (VT100Grid *)copy {
    return [self copyWithZone:nil];
}

- (void)copyMiscellaneousStateTo:(VT100Grid *)theCopy {
    theCopy->cursor_ = cursor_;  // Don't use property to avoid delegate call
    theCopy.scrollRegionRows = scrollRegionRows_;
    theCopy.scrollRegionCols = scrollRegionCols_;
    theCopy.useScrollRegionCols = useScrollRegionCols_;
    theCopy.savedDefaultChar = savedDefaultChar_;
}

- (id)copyWithZone:(NSZone *)zone {
    VT100Grid *theCopy = [[VT100Grid alloc] initWithSize:size_
                                                delegate:delegate_];
    theCopy->lines_ = [[NSMutableArray alloc] init];
    for (NSObject *line in lines_) {
        [theCopy->lines_ addObject:[line mutableCopy]];
    }
    theCopy->lineInfos_ = [[NSMutableArray alloc] init];
    for (VT100LineInfo *line in lineInfos_) {
        [theCopy->lineInfos_ addObject:[line copy]];
    }
    theCopy->screenTop_ = screenTop_;
    [self copyMiscellaneousStateTo:theCopy];

    return theCopy;
}

@end
