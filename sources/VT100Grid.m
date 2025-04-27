//
//  VT100Grid.m
//  iTerm
//
//  Created by George Nachman on 10/9/13.
//
//

#import "VT100Grid.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermEncoderAdapter.h"
#import "iTermExternalAttributeIndex.h"
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

    NSMutableArray<iTermMutableLineString *> *_lines;
    NSMutableIndexSet *_dirtyLines;

    __weak id<VT100GridDelegate> delegate_;
    VT100GridCoord cursor_;
    VT100GridRange scrollRegionRows_;
    VT100GridRange scrollRegionCols_;
    BOOL useScrollRegionCols_;

    NSMutableData *resultLine_;
    screen_char_t savedDefaultChar_;
    NSTimeInterval _allDirtyTimestamp;
#warning TODO: Move this into iTermLineString so it can generate proper ScreenCharArray's'
    NSMutableArray *_bidiInfo;  // iTermBidiDisplayInfo or NSNull
    BOOL _bidiDirty;  // Did _bidiInfo change?
}

@synthesize size = size_;
@synthesize scrollRegionRows = scrollRegionRows_;
@synthesize scrollRegionCols = scrollRegionCols_;
@synthesize useScrollRegionCols = useScrollRegionCols_;
@synthesize allDirty = allDirty_;
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
        NSArray<NSData *> *lines_ = nil;
        if (dictionary[@"lines v3"]) {
            // 3.5.0beta6+ path
            lines_ = [NSArray castFrom:dictionary[@"lines v3"]];
        } else if (dictionary[@"lines v2"]) {
            // 3.5.0beta3+ path
            lines_ = [[NSArray castFrom:dictionary[@"lines v2"]] mapWithBlock:^id _Nonnull(NSData *data) {
                return [data migrateV2ToV3];
            }];;
        } else if (dictionary[@"lines"]) {
            // Migration code path for v1 -> v3 - upgrade legacy_screen_char_t.
            NSArray<NSData *> *legacyLines = [NSArray castFrom:dictionary[@"lines"]];
            if (!legacyLines) {
                return nil;
            }
            NSMutableArray *temp = [[NSMutableArray alloc] init];
            migrationIndexes = [NSMutableDictionary dictionary];
            [legacyLines enumerateObjectsUsingBlock:^(NSData * _Nonnull legacyData, NSUInteger idx, BOOL * _Nonnull stop) {
                iTermExternalAttributeIndex *migrationIndex = nil;
                [temp addObject:[[legacyData migrateV1ToV3:&migrationIndex] mutableCopy]];
                if (migrationIndex) {
                    migrationIndexes[@(idx)] = migrationIndex;
                }
            }];
            lines_ = temp;
        }
        if (lines_) {
            _lines = [[lines_ mapWithBlock:^id(NSData *data) {
                const screen_char_t *chars = (const screen_char_t *)data.bytes;
                int count = data.length / sizeof(screen_char_t) - 1;
                iTermLegacyStyleString *legacyString = [[iTermLegacyStyleString alloc] initWithChars:chars
                                                                                               count:count
                                                                                             eaIndex:nil];
                iTermMutableLineString *mls = [[iTermMutableLineString alloc] initWithContent:[legacyString mutableClone]
                                                                                          eol:chars[count].code
                                                                                 continuation:chars[count]
                                                                                     metadata:(iTermLineStringMetadata){}];
                [mls setContentSize:size_.width];
                return mls;
            }] mutableCopy];
#if DEBUG
            [self sanityCheck];
#endif
        } else {
            return nil;
        }

        // Deprecated: migration code path. Modern dicts have `metadata` instead.
        [[NSArray castFrom:dictionary[@"timestamps"]] enumerateObjectsUsingBlock:^(NSNumber *timestamp,
                                                                                   NSUInteger idx,
                                                                                   BOOL * _Nonnull stop) {
            if (idx >= _lines.count) {
                DLog(@"Too many lineInfos");
                *stop = YES;
                return;
            }
            _lines[idx].timestamp = timestamp.doubleValue;
        }];
        [[NSArray castFrom:dictionary[@"metadata"]] enumerateObjectsUsingBlock:^(NSArray *entry,
                                                                                 NSUInteger idx,
                                                                                 BOOL * _Nonnull stop) {
            if (idx >= _lines.count) {
                DLog(@"Too many lineInfos");
                *stop = YES;
                return;
            }
            iTermMetadata metadata;
            iTermMetadataInitFromArray(&metadata, entry);
            _lines[idx].timestamp = metadata.timestamp;
            _lines[idx].rtlFound = metadata.rtlFound;
            if (metadata.externalAttributes) {
                iTermExternalAttributeIndex *eaIndex = iTermMetadataGetExternalAttributesIndex(metadata);
                [_lines[idx] setExternalAttributes:eaIndex];
            }
            iTermMetadataRelease(metadata);
        }];
        [migrationIndexes enumerateKeysAndObjectsUsingBlock:^(NSNumber *idx, iTermExternalAttributeIndex *ea, BOOL *stop) {
            [_lines[idx.integerValue] setExternalAttributes:ea];
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

#if DEBUG
- (void)sanityCheck {
    for (iTermMutableLineString *line in _lines) {
        assert(line.content.cellCount == size_.width);
    }
}
#endif

- (iTermMutableLineString *)mutableLineStringAtLineNumber:(int)lineNumber {
    if (lineNumber >= 0 && lineNumber < size_.height) {
        return [_lines objectAtIndex:(screenTop_ + lineNumber) % size_.height];
    } else {
        return nil;
    }
}

- (id<iTermLineStringReading>)lineStringAtLineNumber:(int)lineNumber {
    if (lineNumber >= 0 && lineNumber < size_.height) {
        return [_lines objectAtIndex:(screenTop_ + lineNumber) % size_.height];
    } else {
        return nil;
    }
}

- (iTermMetadata)metadataAtLineNumber:(int)lineNumber {
    iTermMutableLineString *ls = [self mutableLineStringAtLineNumber:lineNumber];
    return ls.externalMetadata;
}

- (iTermImmutableMetadata)immutableMetadataAtLineNumber:(int)lineNumber {
    return [self lineStringAtLineNumber:lineNumber].externalImmutableMetadata;
}

- (iTermLegacyMutableString *)legacyMutableStringForLine:(int)line {
    iTermMutableLineString *lineString = [self mutableLineStringAtLineNumber:line];
    iTermLegacyMutableString *lms = [lineString ensureLegacy];
    return lms;
}

- (id<iTermLegacyString>)legacyStringForLine:(int)line {
    id<iTermLineStringReading> lineString = [self lineStringAtLineNumber:line];
    return [lineString ensureImmutableLegacy];
}

NS_INLINE iTermExternalAttributeIndex *VT100GridGetExternalAttributes(VT100Grid *self, int line, BOOL create) {
    iTermLegacyMutableString *lms = [self legacyMutableStringForLine:line];
    return [lms eaIndexCreatingIfNeeded:create];
}

- (iTermExternalAttributeIndex *)externalAttributesOnLine:(int)line
                                           createIfNeeded:(BOOL)createIfNeeded {
    return VT100GridGetExternalAttributes(self, line, createIfNeeded);
}

- (void)setMetadata:(iTermMetadata)metadata forLineNumber:(int)lineNumber {
    iTermMutableLineString *mls = [self mutableLineStringAtLineNumber:lineNumber];
    mls.rtlFound = metadata.rtlFound;
    mls.timestamp = metadata.timestamp;
}

NS_INLINE screen_char_t *VT100GridMutableScreenCharsAtLine(VT100Grid *self, int lineNumber) {
#if DEBUG
    assert(lineNumber >= 0);
#endif
    return [[[self legacyMutableStringForLine:lineNumber] mutableScreenCharArray] mutableLine];
}

NS_INLINE const screen_char_t *VT100GridScreenCharsAtLine(VT100Grid *self, int lineNumber) {
#if DEBUG
    assert(lineNumber >= 0);
#endif
    return [[[self legacyStringForLine:lineNumber] screenCharArray] line];
}

- (ScreenCharArray *)screenCharArrayAtLine:(int)lineNumber {
    return [[self lineStringAtLineNumber:lineNumber] screenCharArrayWithBidi:[[self bidiInfoForLine:lineNumber] nilIfNull]];
}

- (const screen_char_t *)screenCharsAtLineNumber:(int)lineNumber {
    return VT100GridMutableScreenCharsAtLine(self, lineNumber);
}

- (screen_char_t)continuationForLine:(int)lineNumber {
    return [[self lineStringAtLineNumber:lineNumber] continuation];
}

- (screen_char_t *)mutableScreenCharsAtLineNumber:(int)lineNumber {
    return VT100GridMutableScreenCharsAtLine(self, lineNumber);
}

- (NSInteger)numberOfCellsUsedInRange:(VT100GridRange)range {
    __block NSInteger sum = 0;

    [self enumerateCellsInRect:VT100GridRectMake(0, range.location, self.size.width, range.length) block:^(VT100GridCoord coord, screen_char_t c, iTermExternalAttribute *ea, BOOL *stop) {
        if (c.complexChar || c.code || c.image) {
            sum += 1;
        }
    }];

    return sum;
}

static int VT100GridIndex(int screenTop, int lineNumber, int height) {
    if (lineNumber >= 0 && lineNumber < height) {
        return (screenTop + lineNumber) % height;
    } else {
        return -1;
    }
}

NS_INLINE int VT100GridLineInfoIndex(VT100Grid *self, int lineNumber) {
    return VT100GridIndex(self->screenTop_, lineNumber, self->size_.height);
}

#warning TODO: This is really slow. Make the DVR & serialization use something more modern.
- (NSArray<VT100Metadata *> *)metadataArray {
    NSMutableArray<VT100Metadata *> *result = [NSMutableArray array];
    for (int i = 0; i < self.size.height; i++) {
        id<iTermLineStringReading> mls = [self lineStringAtLineNumber:i];
        VT100Metadata *lineInfo =
            [[VT100Metadata alloc] initWithRTLFound:mls.rtlFound
                                          timestamp:mls.timestamp
                                            eaIndex:mls.immutableEAIndex];
        [result addObject:lineInfo];
    }
    return result;
}

- (void)markCharDirty:(BOOL)dirty at:(VT100GridCoord)coord updateTimestamp:(BOOL)updateTimestamp {
    DLog(@"Mark %@ dirty=%@ delegate=%@", VT100GridCoordDescription(coord), @(dirty), delegate_);

    if (!dirty) {
        allDirty_ = NO;
    }
    iTermMutableLineString *mls = [self mutableLineStringAtLineNumber:coord.y];
    mls.dirty = dirty;
    if (dirty && updateTimestamp > 0) {
        mls.timestamp = self.currentDate;
    }
    _hasChanged = YES;
}

- (void)markCharsDirty:(BOOL)dirty inRectFrom:(VT100GridCoord)from to:(VT100GridCoord)to {
    DLog(@"Mark rect from %@ to %@ dirty=%@ delegate=%@", VT100GridCoordDescription(from), VT100GridCoordDescription(to), @(dirty), delegate_);
    assert(from.x <= to.x);
    if (!dirty) {
        allDirty_ = NO;
    }
    const NSTimeInterval timestamp = self.currentDate;
    const int height = size_.height;
    for (int y = MAX(0, from.y); y <= to.y && y < height; y++) {
        iTermMutableLineString *mls = [self mutableLineStringAtLineNumber:y];
        mls.dirty = dirty;
        if (dirty && timestamp > 0) {
            mls.timestamp = timestamp;
        }
    }
    _hasChanged = YES;
}

- (void)markAllCharsDirty:(BOOL)dirty updateTimestamps:(BOOL)updateTimestamps {
    DLog(@"Mark all chars dirty=%@ delegate=%@", @(dirty), delegate_);

    if (dirty) {
        // Fast path
        const NSTimeInterval timestamp = self.currentDate;
        if (allDirty_ && (!updateTimestamps || _allDirtyTimestamp == timestamp)) {
            // Nothing changed.
            return;
        }
        allDirty_ = YES;
        if (updateTimestamps) {
            _allDirtyTimestamp = timestamp;
        }
        [_lines enumerateObjectsUsingBlock:^(iTermMutableLineString *mls, NSUInteger idx, BOOL *stop) {
            mls.dirty = YES;
            if (updateTimestamps && timestamp > 0) {
                mls.timestamp = timestamp;
            }
        }];
        return;
    }
    _hasChanged = YES;
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
    id<iTermLineStringReading> mls = [self lineStringAtLineNumber:coord.y];
    return mls.dirty;
}

- (NSIndexSet *)dirtyIndexesOnLine:(int)line {
    if (allDirty_) {
        return [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.size.width)];
    }
    id<iTermLineStringReading> mls = [self lineStringAtLineNumber:line];
    if (mls.dirty) {
        return [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, size_.width)];
    } else {
        return [NSIndexSet indexSet];
    }
}

- (BOOL)isAnyCharDirty {
    if (allDirty_) {
        return YES;
    }
    for (int y = 0; y < size_.height; y++) {
        id<iTermLineStringReading> mls = [self lineStringAtLineNumber:y];
        if (mls.dirty) {
            return YES;
        }
    }
    return NO;
}

- (VT100GridRange)dirtyRangeForLine:(int)y {
    if (allDirty_) {
        return VT100GridRangeMake(0, self.size.width);
    }
    id<iTermLineStringReading> mls = [self lineStringAtLineNumber:y];
    if (mls.dirty) {
        return VT100GridRangeMake(0, size_.width);
    } else {
        return VT100GridRangeMake(-1, -1);
    }
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
        [delegate_ gridCursorDidChangeLineFrom:prev];
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
        const screen_char_t *line = [self screenCharsAtLineNumber:numberOfLinesUsed - 1];
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

- (BOOL)lineIsEmpty:(int)n {
    return [[self lineStringAtLineNumber:n] isEmpty];
}

- (BOOL)anyLineDirtyInRange:(NSRange)range {
    for (NSInteger i = 0; i < range.length; i++) {
        if ([self dirtyRangeForLine:range.location + i].length > 0) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)mayContainRTL {
    const int height = size_.height;
    for (int i = 0; i < height; i++) {
        id<iTermLineStringReading> mls = [self lineStringAtLineNumber:i];
        if (mls.rtlFound) {
            return YES;
        }
    }
    if ([_bidiInfo anyWithBlock:^BOOL(id anObject) {
        return ![anObject isKindOfClass:[NSNull class]];
    }]) {
        return YES;
    }
    return NO;
}

- (int)numberOfLinesUsed {
    return MAX(MIN(size_.height, cursor_.y + 1), [self numberOfNonEmptyLinesIncludingWhitespaceAsEmpty:NO]);
}

- (int)appendLines:(int)numLines
      toLineBuffer:(LineBuffer *)lineBuffer {
    return [self appendLines:numLines toLineBuffer:lineBuffer makeCursorLineSoft:NO];
}

- (int)appendLines:(int)numLines
      toLineBuffer:(LineBuffer *)lineBuffer
makeCursorLineSoft:(BOOL)makeCursorLineSoft {
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
        iTermMutableLineString *mls = [self mutableLineStringAtLineNumber:i];
        iTermLegacyMutableString *lms = [mls ensureLegacy];
        const screen_char_t *line = lms.screenCharArray.line;

        int currentLineLength = lengthOfNextLine;
        if (i + 1 < size_.height) {
            lengthOfNextLine = [self lengthOfLineNumber:i+1];
        } else {
            lengthOfNextLine = -1;
        }

        int continuation = mls.eol;
        if (i == cursor_.y) {
            [lineBuffer setCursor:cursor_.x];
        } else if ((cursor_.x == 0) &&
                   (i == cursor_.y - 1) &&
                   (lengthOfNextLine == 0) &&
                   continuation != EOL_HARD) {
            // This line is continued, the next line is empty, and the cursor is
            // on the first column of the next line. Pull it up.
            // NOTE: This was cursor_.x + 1, but I'm pretty sure that's wrong as it would always be 1.
            [lineBuffer setCursor:currentLineLength];
        }

        // NOTE: When I initially wrote the session restoration code, there was
        // an '|| (i == size.height)' conjunction. It caused issue 3788 so I
        // removed it. Unfortunately, I can't recall why it was added in the
        // first place.
        BOOL isPartial = (continuation != EOL_HARD);
        if (makeCursorLineSoft && !isPartial) {
            isPartial = (i + 1 == numLines &&
                         self.cursor.y == i &&
                         self.cursor.x == [self lengthOfLineNumber:i]);
        }
        [lineBuffer appendLine:line
                        length:currentLineLength
                       partial:isPartial
                         width:size_.width
                      metadata:[self immutableMetadataAtLineNumber:i]
                  continuation:mls.continuation];
#ifdef DEBUG_RESIZEDWIDTH
        NSLog(@"Appended a line. now have %d lines for width %d\n",
              [lineBuffer numLinesWithWidth:size_.width], size_.width);
#endif
    }
    [lineBuffer commitLastBlock];

    return numLines;
}

- (NSTimeInterval)timestampForLine:(int)y {
    id<iTermLineStringReading> mls = [self lineStringAtLineNumber:y];
    return mls.timestamp;
}

- (int)lengthOfLineNumber:(int)lineNumber {
    return [[self lineStringAtLineNumber:lineNumber] usedLength];
}

- (int)lengthOfLine:(iTermMutableLineString *)mls {
    return mls.usedLength;
}

- (int)continuationMarkForLineNumber:(int)lineNumber {
    return [self lineStringAtLineNumber:lineNumber].eol;
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
    const int y = size_.height - 1;
    if (y >= 0 && y < _lines.count) {
        iTermMutableLineString *mls = [self mutableLineStringAtLineNumber:y];
        [mls eraseWithDefaultChar:_defaultChar];
    }

    // Mark new line at bottom of screen dirty and update its timestamp.
    [self markCharsDirty:YES
              inRectFrom:VT100GridCoordMake(0, size_.height - 1)
                      to:VT100GridCoordMake(size_.width - 1, size_.height - 1)];
    if (!lineBuffer) {
        // Mark everything dirty if we're not using the scrollback buffer.
        [self markAllCharsDirty:YES updateTimestamps:NO];
    }

    DLog(@"scrolled screen up by 1 line");
    return numLinesDropped;
}

- (int)scrollUpIntoLineBuffer:(LineBuffer *)lineBuffer
          unlimitedScrollback:(BOOL)unlimitedScrollback
      useScrollbackWithRegion:(BOOL)useScrollbackWithRegion
                    softBreak:(BOOL)softBreak
             sentToLineBuffer:(out BOOL *)sentToLineBuffer {
    const int scrollTop = self.topMargin;
    const int scrollBottom = self.bottomMargin;
    const int scrollLeft = self.leftMargin;
    const int scrollRight = self.rightMargin;

    assert(scrollTop >= 0 && scrollTop < size_.height);
    assert(scrollBottom >= 0 && scrollBottom < size_.height);
    assert(scrollTop <= scrollBottom );

    if (![self haveScrollRegion]) {
        // Scroll the whole screen. This is the fast path.
        if (sentToLineBuffer) {
            *sentToLineBuffer = YES;
        }
        return [self scrollWholeScreenUpIntoLineBuffer:lineBuffer
                                   unlimitedScrollback:unlimitedScrollback];
    } else {
        // Scroll a region

        int numLinesDropped = 0;
        // Not scrolling the whole screen.
        if (scrollTop == 0 && useScrollbackWithRegion && ![self haveColumnScrollRegion]) {
            // A line is being scrolled off the top of the screen so add it to
            // the scrollback buffer.
            if (sentToLineBuffer) {
                *sentToLineBuffer = YES;
            }
            numLinesDropped = [self appendLineToLineBuffer:lineBuffer
                                       unlimitedScrollback:unlimitedScrollback];
        } else {
            if (sentToLineBuffer) {
                *sentToLineBuffer = NO;
            }
        }
        // TODO: formerly, scrollTop==scrollBottom was a no-op but I think that's wrong. See what other terms do.
        [self scrollRect:VT100GridRectMake(scrollLeft,
                                           scrollTop,
                                           scrollRight - scrollLeft + 1,
                                           scrollBottom - scrollTop + 1)
                    downBy:-1
               softBreak:softBreak];
        // Absolute line numbers referring to positions in the grid are no longer meaningful.
        // Although the grid didn't change everywhere, this is the simplest way to ensure that
        // things like search results get updated.
        [self setAllDirty:YES];

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
                                              softBreak:NO
                                       sentToLineBuffer:nil];
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
                                         willScroll:(void (^)(void))willScroll
                                   sentToLineBuffer:(out BOOL *)sentToLineBuffer {
    // This doesn't call -bottomMargin because it was a hotspot in profiling.
    const int scrollBottom = VT100GridRangeMax(scrollRegionRows_);
    if (sentToLineBuffer) {
        *sentToLineBuffer = NO;
    }
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
                                  softBreak:YES
                           sentToLineBuffer:sentToLineBuffer];
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

- (void)performBlockWithoutScrollRegions:(void (^NS_NOESCAPE)(void))block {
    const VT100GridRange scrollRegionRows = scrollRegionRows_;
    const VT100GridRange scrollRegionCols = scrollRegionCols_;
    const BOOL useScrollRegionCols = useScrollRegionCols_;

    scrollRegionRows_ = VT100GridRangeMake(0, size_.height);
    scrollRegionCols_ = VT100GridRangeMake(0, size_.width);
    useScrollRegionCols_ = NO;

    block();

    scrollRegionRows_ = scrollRegionRows;
    scrollRegionCols_ = scrollRegionCols;
    useScrollRegionCols_ = useScrollRegionCols;
}

- (void)mutateCharactersInRange:(VT100GridCoordRange)range
                          block:(void (^)(screen_char_t *sct,
                                          iTermExternalAttribute **eaOut,
                                          VT100GridCoord coord,
                                          BOOL *stop))block {
    int left = MAX(0, range.start.x);
    for (int y = MAX(0, range.start.y); y <= MIN(range.end.y, size_.height - 1); y++) {
        const int right = MAX(left, y == range.end.y ? range.end.x : size_.width);
        screen_char_t *line = [self mutableScreenCharsAtLineNumber:y];
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
        iTermMutableLineString *mls = [self mutableLineStringAtLineNumber:y];
        iTermLegacyMutableString *lms = [mls ensureLegacy];

        [self erasePossibleDoubleWidthCharInLineNumber:y startingAtOffset:from.x - 1 withChar:c];
        [self erasePossibleDoubleWidthCharInLineNumber:y startingAtOffset:to.x withChar:c];
        const int minX = MAX(0, from.x);
        const int maxX = MIN(to.x, size_.width - 1);

        screen_char_t *line = lms.mutableScreenCharArray.mutableLine;
        for (int x = minX; x <= maxX; x++) {
            line[x] = c;
        }
        if (c.code == 0 && to.x == size_.width - 1) {
            mls.continuation = c;
            mls.eol = EOL_HARD;
        }
        iTermExternalAttributeIndex *eaIndex = [self externalAttributesOnLine:y
                                                               createIfNeeded:attrs != nil];
        [eaIndex setAttributes:attrs
                            at:minX
                         count:maxX - minX + 1];
    }
    [self markCharsDirty:YES inRectFrom:from to:to];
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
        screen_char_t *line = [self mutableScreenCharsAtLineNumber:y];
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

- (iTermExternalAttribute *)applySGR:(CSIParam)csi to:(screen_char_t *)cPtr externalAttribute:(iTermExternalAttribute *)attr {
    __block iTermExternalAttribute *updatedAttr = attr;
    VT100GraphicRendition rendition = VT100GraphicRenditionFromCharacter(cPtr, attr);
    for (int i = 0; i < csi.count; i++) {
        switch (VT100GraphicRenditionExecuteSGR(&rendition, &csi, i)) {
            case VT100GraphicRenditionSideEffectNone:
                break;
            case VT100GraphicRenditionSideEffectReset:
                updatedAttr = nil;
                memset(&rendition, 0, sizeof(rendition));
                break;
            case VT100GraphicRenditionSideEffectUpdateExternalAttributes:
                updatedAttr = [iTermExternalAttribute attributeHavingUnderlineColor:rendition.hasUnderlineColor
                                                                     underlineColor:rendition.underlineColor
                                                                                url:updatedAttr.url
                                                                        blockIDList:updatedAttr.blockIDList
                                                                        controlCode:updatedAttr.controlCodeNumber];
                break;
            case VT100GraphicRenditionSideEffectSkip2AndUpdateExternalAttributes:
                updatedAttr = [iTermExternalAttribute attributeHavingUnderlineColor:rendition.hasUnderlineColor
                                                                     underlineColor:rendition.underlineColor
                                                                                url:updatedAttr.url
                                                                        blockIDList:updatedAttr.blockIDList
                                                                        controlCode:updatedAttr.controlCodeNumber];
                i += 2;
                break;
            case VT100GraphicRenditionSideEffectSkip4AndUpdateExternalAttributes:
                updatedAttr = [iTermExternalAttribute attributeHavingUnderlineColor:rendition.hasUnderlineColor
                                                                     underlineColor:rendition.underlineColor
                                                                                url:updatedAttr.url
                                                                        blockIDList:updatedAttr.blockIDList
                                                                        controlCode:updatedAttr.controlCodeNumber];
                i += 4;
                break;
            case VT100GraphicRenditionSideEffectSkip2:
                i += 2;
                break;
            case VT100GraphicRenditionSideEffectSkip4:
                i += 4;
                break;
        }
    }
    VT100GraphicRenditionUpdateForeground(&rendition, YES, cPtr->guarded, cPtr);
    VT100GraphicRenditionUpdateBackground(&rendition, YES, cPtr);
    return updatedAttr;
}

- (void)setSGR:(CSIParam)csi
    inRectFrom:(VT100GridCoord)from
            to:(VT100GridCoord)to {
    for (int y = from.y; y <= to.y; y++) {
        iTermLegacyMutableString *lms = [self legacyMutableStringForLine:y];
        iTermExternalAttributeIndex *eaIndex = [lms eaIndexCreatingIfNeeded:NO];
        screen_char_t *line = lms.mutableScreenCharArray.mutableLine;
        for (int x = from.x; x <= to.x; x++) {
            screen_char_t c = line[x];
            iTermExternalAttribute *attr = eaIndex[x];
            iTermExternalAttribute *updatedAttr = [self applySGR:csi to:&c externalAttribute:attr];
            line[x] = c;
            if (updatedAttr != attr) {
                if (!eaIndex) {
                    eaIndex = [lms eaIndexCreatingIfNeeded:YES];
                }
                eaIndex[x] = updatedAttr;
            }
        }
        [self markCharsDirty:YES
                  inRectFrom:VT100GridCoordMake(from.x, y)
                          to:VT100GridCoordMake(to.x, y)];
    }
}

- (void)setURL:(iTermURL *)url
        inRectFrom:(VT100GridCoord)from
                to:(VT100GridCoord)to {
    for (int y = from.y; y <= to.y; y++) {
        iTermLegacyMutableString *lms = [self legacyMutableStringForLine:y];
        iTermExternalAttributeIndex *eaIndex = [lms eaIndexCreatingIfNeeded:url != nil];

        [eaIndex mutateAttributesFrom:from.x to:to.x block:^iTermExternalAttribute * _Nullable(iTermExternalAttribute * _Nullable old) {
            return [iTermExternalAttribute attributeHavingUnderlineColor:old.hasUnderlineColor
                                                          underlineColor:old.underlineColor
                                                                     url:url
                                                             blockIDList:old.blockIDList
                                                             controlCode:old.controlCodeNumber];
        }];
        [self markCharsDirty:YES
                  inRectFrom:VT100GridCoordMake(from.x, y)
                          to:VT100GridCoordMake(to.x, y)];
    }
}

- (void)setBlockIDList:(NSString *)blockIDList onLine:(int)line {
    iTermLegacyMutableString *lms = [self legacyMutableStringForLine:line];
    iTermExternalAttributeIndex *eaIndex = [lms eaIndexCreatingIfNeeded:blockIDList != nil];

    [eaIndex mutateAttributesFrom:0
                               to:self.size.width - 1
                            block:^iTermExternalAttribute * _Nullable(iTermExternalAttribute * _Nullable old) {
        return [iTermExternalAttribute attributeHavingUnderlineColor:old.hasUnderlineColor
                                                      underlineColor:old.underlineColor
                                                                 url:old.url
                                                         blockIDList:blockIDList
                                                         controlCode:old.controlCodeNumber];
    }];
    [self markCharsDirty:YES
              inRectFrom:VT100GridCoordMake(0, line)
                      to:VT100GridCoordMake(self.size.width - 1, line)];
}

- (void)setRTLFound:(BOOL)rtlFound onLine:(int)line {
    [self mutableLineStringAtLineNumber:line].rtlFound = rtlFound;
}

- (void)copyDirtyFromGrid:(VT100Grid *)otherGrid  didScroll:(BOOL)didScroll {
    if (otherGrid == self) {
        return;
    }
    const BOOL sizeChanged = !VT100GridSizeEquals(self.size, otherGrid.size);
    [self setSize:otherGrid.size];
    for (int i = 0; i < size_.height; i++) {
        const int k = [otherGrid indexOfLineNumber:i];
        iTermMutableLineString *sourceMLS = otherGrid->_lines[k];
        if (!didScroll && !sizeChanged && !sourceMLS.dirty) {
            continue;
        }
        const int j = [self indexOfLineNumber:i];
        _lines[j] = [sourceMLS mutableClone];
    }
    [self sanityCheck];
    _hasChanged = YES;
    [otherGrid copyMiscellaneousStateTo:self];
    [otherGrid resetBidiDirty];
}

- (int)scrollLeft {
    return scrollRegionCols_.location;
}

- (int)scrollRight {
    return VT100GridRangeMax(scrollRegionCols_);
}

#warning TODO: Test all the DWC edge cases in this method
- (int)appendOptimizedStringAtCursor:(id<iTermString>)string
             scrollingIntoLineBuffer:(LineBuffer *)lineBuffer
                 unlimitedScrollback:(BOOL)unlimitedScrollback
             useScrollbackWithRegion:(BOOL)useScrollbackWithRegion
                            rtlFound:(BOOL)rtlFound {
    int numDropped = 0;
    assert(string);

    const int length = [string cellCount];
    const screen_char_t defaultChar = [self defaultChar];
    int lastY = -1;
    const int width = size_.width;

    for (int idx = 0; idx < length; ) {
        // see if next char is the right half of a DWC
        const BOOL haveLeadingDWC = (idx + 1 < length &&
                                     ScreenCharIsDWC_RIGHT([string characterAt:idx + 1]));
        const int widthOffset = haveLeadingDWC ? 1 : 0;

        // wrap if at right edge
        if (cursor_.x >= width - widthOffset) {
            iTermMutableLineString *mls = [self mutableLineStringAtLineNumber:cursor_.y];
            BOOL splitDwc = (cursor_.x == width - 1);
            mls.continuation = defaultChar;
            mls.eol = splitDwc ? EOL_DWC : EOL_SOFT;
            if (splitDwc) {
                [mls setDWCSkip];
            }

            self.cursorX = 0;
            numDropped += [self moveCursorDownOneLineScrollingIntoLineBuffer:lineBuffer
                                                         unlimitedScrollback:unlimitedScrollback
                                                     useScrollbackWithRegion:useScrollbackWithRegion
                                                                  willScroll:nil
                                                            sentToLineBuffer:nil];
        }

        const int spaceRemaining = width - cursor_.x;
        const int charsRemaining = length - idx;
        BOOL wrapDwc = NO;
        int  newx;

        if (spaceRemaining <= charsRemaining) {
            // avoid splitting a DWC across lines
            if (idx + spaceRemaining < length &&
                ScreenCharIsDWC_RIGHT([string characterAt:idx + spaceRemaining])) {
                wrapDwc = YES;
                newx = width - 1;
            } else {
                newx = width;
            }
        } else {
            newx = cursor_.x + charsRemaining;
        }

        const int charsToInsert = newx - cursor_.x;
        if (charsToInsert <= 0) {
            break;
        }

        const int lineNumber = cursor_.y;
        iTermMutableLineString *mls =
            [self mutableLineStringAtLineNumber:lineNumber];
        if (rtlFound && lineNumber != lastY) {
            lastY = lineNumber;
            mls.rtlFound = rtlFound;
        }


        // clear any stray DWC right-half at the insertion point
        if (ScreenCharIsDWC_RIGHT([mls.content characterAt:cursor_.x])) {
            [mls eraseDWCRightAtIndex:cursor_.x currentDate:_currentDate];
            _hasChanged = YES;
        }

        // replace the run in one go (this also updates external attributes)
        NSRange destRange = NSMakeRange(cursor_.x, charsToInsert);
        NSRange srcRange  = NSMakeRange(idx, charsToInsert);
        id<iTermString> substr = [string substringWithRange:srcRange];
        [mls.mutableContent replaceRange:destRange with:substr];

        [self markCharsDirty:YES
                  inRectFrom:VT100GridCoordMake(cursor_.x, lineNumber)
                          to:VT100GridCoordMake(cursor_.x + charsToInsert - 1, lineNumber)];

        // handle DWC wrap-around
        if (wrapDwc) {
            if (cursor_.x + charsToInsert == width - 1) {
                [mls setDWCSkip];
            } else {
                [mls eraseDWCRightAtIndex:cursor_.x currentDate:_currentDate];
            }
        }

        // advance cursor and index
        self.cursorX = newx;
        idx += charsToInsert;

        // clean up any leftover DWC right-half
        if (cursor_.x < width - 1 &&
            ScreenCharIsDWC_RIGHT([mls.content characterAt:cursor_.x])) {
            [mls eraseDWCRightAtIndex:cursor_.x currentDate:_currentDate];
        }

        // fix split-DWC state at end of line
        if (mls.eol == EOL_DWC &&
            !ScreenCharIsDWC_SKIP(mls.lastCharacter)) {
            mls.eol = EOL_SOFT;
        }
    }

    assert(numDropped >= 0);
    return numDropped;
}

- (BOOL)canUseOptimizedStringFastPath {
    if (useScrollRegionCols_) {
        return NO;
    }
    return YES;
}

- (int)appendCharsAtCursor:(const screen_char_t *)buffer
                    length:(int)len
   scrollingIntoLineBuffer:(LineBuffer *)lineBuffer
       unlimitedScrollback:(BOOL)unlimitedScrollback
   useScrollbackWithRegion:(BOOL)useScrollbackWithRegion
                wraparound:(BOOL)wraparound
                      ansi:(BOOL)ansi
                    insert:(BOOL)insert
    externalAttributeIndex:(id<iTermExternalAttributeIndexReading>)attributes
                  rtlFound:(BOOL)rtlFound {
    int numDropped = 0;
    assert(buffer);
    int idx;  // Index into buffer
    int charsToInsert;
    int newx;
    int leftMargin, rightMargin;
    const int scrollLeft = self.scrollLeft;
    const int scrollRight = self.scrollRight;
    const screen_char_t defaultChar = [self defaultChar];
    int lastY = -1;
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
                    iTermMutableLineString *mls = [self mutableLineStringAtLineNumber:cursor_.y];
                    BOOL splitDwc = (cursor_.x == size_.width - 1);
                    mls.continuation = defaultChar;
                    mls.eol = (splitDwc ? EOL_DWC : EOL_SOFT);
                    if (splitDwc) {
                        [mls setDWCSkip];
                    }
                }
                self.cursorX = leftMargin;
                // Advance to the next line
                numDropped += [self moveCursorDownOneLineScrollingIntoLineBuffer:lineBuffer
                                                             unlimitedScrollback:unlimitedScrollback
                                                         useScrollbackWithRegion:useScrollbackWithRegion
                                                                      willScroll:nil
                                                                sentToLineBuffer:nil];

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

                if (rtlFound && cursor_.y != lastY) {
                    lastY = cursor_.y;
                    [self mutableLineStringAtLineNumber:cursor_.y].rtlFound = rtlFound;
                }
                iTermMutableLineString *mls = [self mutableLineStringAtLineNumber:cursor_.y];
                if (rightMargin == size_.width) {
                    // Clear the continuation marker
                    mls.eol = EOL_HARD;
                }

                if (newCursorX < 0) {
                    newCursorX = 0;
                }
                self.cursorX = newCursorX;
                if (ScreenCharIsDWC_RIGHT([mls.content characterAt:cursor_.x])) {
                    // This would cause us to overwrite the second part of a
                    // double-width character. Convert it to a space.
                    [mls eraseCharacterAt:cursor_.x - 1];
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
        if (rtlFound && cursor_.y != lastY) {
            lastY = cursor_.y;
            [self mutableLineStringAtLineNumber:cursor_.y].rtlFound = rtlFound;
        }
        iTermMutableLineString *mls = [self mutableLineStringAtLineNumber:lineNumber];
        iTermExternalAttributeIndex *eaIndex = [mls.ensureLegacy eaIndexCreatingIfNeeded:attributes != nil];

        BOOL mayStompSplitDwc = NO;
        if (newx == size_.width) {
            // The cursor is ending at the right margin. See if there's a DWC_SKIP/EOL_DWC pair
            // there which may be affected.
            mayStompSplitDwc = (!useScrollRegionCols_ &&
                                mls.eol == EOL_DWC &&
                                ScreenCharIsDWC_SKIP(mls.lastCharacter));
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
        if (ScreenCharIsDWC_RIGHT([mls.content characterAt:cursor_.x])) {
            [self eraseDWCRightOnLine:lineNumber x:cursor_.x externalAttributeIndex:eaIndex];
        }

        // This is an ugly little optimization--if we're inserting just one character, see if it would
        // change anything (because the memcmp is really cheap). In particular, this helps vim out because
        // it really likes redrawing pane separators when it doesn't need to.
        if (charsToInsert > 1 ||
            ![mls.content hasEqualWithRange:NSMakeRange(cursor_.x, charsToInsert) to:buffer + idx]) {
            // copy charsToInsert characters into the line and set them dirty.
            screen_char_t *aLine = mls.ensureLegacy.mutableScreenCharArray.mutableLine;
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
                [mls.ensureLegacy setDWCSkipAt:cursor_.x + charsToInsert];
            } else {
                [mls.ensureLegacy eraseCodeAt:cursor_.x + charsToInsert];
            }
        }
        self.cursorX = newx;
        idx += charsToInsert;

        // Overwrote some stuff that was already on the screen leaving behind the
        // second half of a DWC
        if (cursor_.x < size_.width - 1 && ScreenCharIsDWC_RIGHT([mls.content characterAt:cursor_.x])) {
            [eaIndex eraseAt:cursor_.x];
            [mls.ensureLegacy eraseCodeAt:cursor_.x];
        }

        if (mayStompSplitDwc &&
            !ScreenCharIsDWC_SKIP(mls.lastCharacter) &&
            mls.eol == EOL_DWC) {
            // The line no longer ends in a DWC_SKIP, but the continuation mark is still EOL_DWC.
            // Change the continuation mark to EOL_SOFT since there's presumably still a DWC at the
            // start of the next line.
            mls.eol = EOL_SOFT;
        }

        // The next char in the buffer shouldn't be DWC_RIGHT because we
        // wouldn't have inserted its first half due to a check at the top.
        assert(!(idx < len && ScreenCharIsDWC_RIGHT(buffer[idx]) ));

        // ANSI terminals will go to a new line after displaying a character at
        // the rightmost column.
        if (cursor_.x >= effective_width && ansi) {
            if (wraparound) {
                //set the wrapping flag
                mls.continuation = defaultChar;
                mls.eol = ((effective_width == size_.width) ? EOL_SOFT : EOL_DWC);
                self.cursorX = leftMargin;
                numDropped += [self moveCursorDownOneLineScrollingIntoLineBuffer:lineBuffer
                                                             unlimitedScrollback:unlimitedScrollback
                                                         useScrollbackWithRegion:useScrollbackWithRegion
                                                                      willScroll:nil
                                                                sentToLineBuffer:nil];
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
    iTermMutableLineString *mls = [self mutableLineStringAtLineNumber:lineNumber];
    screen_char_t *aLine = mls.ensureLegacy.mutableScreenCharArray.mutableLine;

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
               mls.eol == EOL_DWC) {
        // Stomping on a DWC_SKIP. Join the lines normally.
        mls.continuation = [self defaultChar];
        mls.eol = EOL_SOFT;
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
    screen_char_t *aLine = [self mutableScreenCharsAtLineNumber:lineNumber];
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
        iTermMutableLineString *mls = [self mutableLineStringAtLineNumber:startCoord.y];
        aLine = mls.ensureLegacy.mutableScreenCharArray.mutableLine;

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
                mls.eol == EOL_DWC) {
                // When the previous if statement is true, this one should also always be true.
                mls.eol = EOL_HARD;
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

// NOTE: `rect` is *not* inclusive of rect.end.y, unlike most uses of VT100GridRect.
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
            screen_char_t *sourceLine = [self mutableScreenCharsAtLineNumber:sourceIndex];
            screen_char_t *targetLine = [self mutableScreenCharsAtLineNumber:destIndex];

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
            iTermMutableLineString *pred = [self mutableLineStringAtLineNumber:lineNumberAboveScrollRegion];
            if (pred.eol == EOL_SOFT) {
                pred.eol = EOL_HARD;
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
                iTermMutableLineString *lastLine = [self mutableLineStringAtLineNumber:lastLineOfScrollRegion];
                if (lastLine.eol == EOL_SOFT) {
                    lastLine.eol = EOL_HARD;
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
        iTermMutableLineString *mls = [self mutableLineStringAtLineNumber:y];
        screen_char_t *dest = mls.ensureLegacy.mutableScreenCharArray.mutableLine;
        const screen_char_t *src = s + ((y + sourceLineOffset) * (info.width + 1));
        memmove(dest, src, sizeof(screen_char_t) * charsToCopyPerLine);
        if (size_.width != info.width) {
            // Not copying continuation marks, set them all to hard.
            mls.continuation = mls.lastCharacter;
            mls.eol = EOL_HARD;
        }
        if (charsToCopyPerLine < info.width && ScreenCharIsDWC_RIGHT(src[charsToCopyPerLine])) {
            dest[charsToCopyPerLine - 1].code = 0;
            dest[charsToCopyPerLine - 1].complexChar = NO;
        }
        if (charsToCopyPerLine - 1 < info.width && ScreenCharIsTAB_FILLER(src[charsToCopyPerLine - 1])) {
            dest[charsToCopyPerLine - 1].code = '\t';
            dest[charsToCopyPerLine - 1].complexChar = NO;
        }
        [self setMetadata:iTermMetadataMakeImmutable(sourceMetadataArray[y])
                   onLine:y];
    }
    [self markAllCharsDirty:YES updateTimestamps:NO];

    const int yOffset = MAX(0, info.height - size_.height);
    self.cursorX = MIN(size_.width - 1, MAX(0, info.cursorX));
    self.cursorY = MIN(size_.height - 1, MAX(0, info.cursorY - yOffset));
}

- (void)setCharactersInLine:(int)line
                         to:(const screen_char_t *)chars
                     length:(int)length {
    assert(length <= self.size.width);
    screen_char_t *destination = [self mutableScreenCharsAtLineNumber:line];
    assert(destination != nil);
    memmove(destination, chars, length * sizeof(screen_char_t));
    [self markCharsDirty:YES
              inRectFrom:VT100GridCoordMake(0, line)
                      to:VT100GridCoordMake(length - 1, line)];
}

- (NSString *)debugString {
    NSMutableString* result = [NSMutableString stringWithString:@""];
    int x, y;
    for (y = 0; y < size_.height; ++y) {
        const screen_char_t* p = [self screenCharsAtLineNumber:y];
        if (y == screenTop_) {
            [result appendString:@"--- top of buffer ---\n"];
        }
        NSMutableString *lineString = [[NSMutableString alloc] init];
        NSMutableString *dirtyLineString = [[NSMutableString alloc] init];
        for (x = 0; x < size_.width; ++x) {
            unichar c = 0;
            unichar d = 0;
            if ([self isCharDirtyAt:VT100GridCoordMake(x, y)]) {
                d = '-';
            } else {
                d = '.';
            }
            if (y == cursor_.y && x == cursor_.x) {
                if (d == '-') {
                    d = '=';
                }
                if (d == '.') {
                    d = ':';
                }
            }
            if (p[x].image) {
                c = 'I';
            } else if (p[x].code && !p[x].complexChar) {
                if (p[x].code > 0 && p[x].code < 128) {
                    c = p[x].code;
                } else if (ScreenCharIsDWC_RIGHT(p[x])) {
                    c = '-';
                } else if (ScreenCharIsTAB_FILLER(p[x])) {
                    c = ' ';
                } else if (ScreenCharIsDWC_SKIP(p[x])) {
                    c = '>';
                } else {
                    c = '?';
                }
            } else {
                c = '.';
            }
            [lineString appendCharacter:c];
            [dirtyLineString appendCharacter:d];
        }
        [result appendFormat:@"%04d: %@ %@\n", y, lineString, [self stringForContinuationMark:[self lineStringAtLineNumber:y].eol]];
        [result appendFormat:@"dirty %@%@\n", dirtyLineString, y == cursor_.y ? @" -cursor-" : @""];
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

- (int)scrollWholeScreenDownByLines:(int)count poppingFromLineBuffer:(LineBuffer *)lineBuffer {
    int result = 0;
    for (int i = 0; i < count; i++) {
        if ([self scrollWholeScreenDownPoppingFromLineBuffer:lineBuffer]) {
            result += 1;
        } else {
            break;
        }
    }
    return result;
}

- (BOOL)scrollWholeScreenDownPoppingFromLineBuffer:(LineBuffer *)lineBuffer {
    const int width = self.size.width;
    if ([lineBuffer numLinesWithWidth:width] == 0 || width < 1) {
        return NO;
    }
    [self scrollRect:VT100GridRectMake(0, 0, width, self.size.height)
              downBy:1
           softBreak:NO];
    screen_char_t *line = [self mutableScreenCharsAtLineNumber:0];
    int eol = 0;
    iTermImmutableMetadata metadata;
    screen_char_t continuation;
    const BOOL ok = [lineBuffer popAndCopyLastLineInto:line
                                                 width:width
                                     includesEndOfLine:&eol
                                              metadata:&metadata
                                          continuation:&continuation];
    assert(ok);
    iTermMutableLineString *mls = [self setMetadata:metadata onLine:0];
    mls.eol = eol;
    mls.continuation = continuation;
    if (eol == EOL_DWC) {
        ScreenCharSetDWC_SKIP(&line[width - 1]);
    }
    return YES;
}

- (iTermMutableLineString *)setMetadata:(iTermImmutableMetadata)metadata onLine:(int)line {
    iTermMutableLineString *mls = [self mutableLineStringAtLineNumber:line];
    [mls setMetadata:(iTermLineStringMetadata){
        .timestamp = metadata.timestamp,
        .rtlFound = metadata.rtlFound
    }];
    [mls setExternalAttributes:iTermImmutableMetadataGetExternalAttributesIndex(metadata)];
    return mls;
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
    while (destLineNumber >= 0) {
        iTermMutableLineString *mls = [self mutableLineStringAtLineNumber:destLineNumber];
        screen_char_t *dest = mls.ensureLegacy.mutableScreenCharArray.mutableLine;
        memcpy(dest, defaultLine, sizeof(screen_char_t) * size_.width);
        [self markCharsDirty:YES
                  inRectFrom:VT100GridCoordMake(0, destLineNumber)
                          to:VT100GridCoordMake(size_.width - 1, destLineNumber)];
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
        assert([lineBuffer popAndCopyLastLineInto:dest
                                            width:size_.width
                                includesEndOfLine:&cont
                                         metadata:&metadata
                                     continuation:&continuation]);
        [self setMetadata:metadata onLine:destLineNumber];
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
        mls.continuation = continuation;
        mls.eol = cont;
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

- (NSMutableData *)resultLineData {
    assert(size_.width < INT_MAX);
    assert(size_.width >= 0);
    const int length = sizeof(screen_char_t) * (size_.width + 1);
    if (resultLine_.length != length) {
        resultLine_ = [[NSMutableData alloc] initWithLength:length];
    }
    return resultLine_;
}

- (screen_char_t *)resultLine {
    return (screen_char_t *)resultLine_.mutableBytes;
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

- (NSString *)dumpString {
    return [[[NSArray sequenceWithRange:NSMakeRange(0, size_.height)] mapWithBlock:^id _Nullable(NSNumber * _Nonnull anObject) {
        int i = anObject.intValue;
        return [NSString stringWithFormat:@"Line %d: %@", i, [_lines[i] description]];
    }] componentsJoinedByString:@"\n"];
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
        const screen_char_t *line = [self screenCharsAtLineNumber:y];
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
        const screen_char_t *line = [self screenCharsAtLineNumber:y];
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
        id<iTermLineStringReading> mls = [self lineStringAtLineNumber:y];
        NSDate* date = [NSDate dateWithTimeIntervalSinceReferenceDate:mls.timestamp];
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
        id<iTermLineStringReading> mls = [self lineStringAtLineNumber:y];
        const screen_char_t *line = mls.content.screenCharArray.line;
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
        switch (mls.eol) {
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
    iTermMutableLineString *mls = [self mutableLineStringAtLineNumber:pos.y];
    screen_char_t *line = mls.ensureLegacy.mutableScreenCharArray.mutableLine;
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
        mls.eol == EOL_DWC) {
        // The line shifting means a split DWC is gone. The wrapping changes to hard if the last
        // code is 0 because soft wrapping doesn't make sense across a null code.
        mls.eol = mls.lastCharacter.code ? EOL_SOFT : EOL_HARD;
    }

    if (size_.width > 0 &&
        self.rightMargin == size_.width - 1 &&
        mls.eol == EOL_SOFT &&
        line[size_.width - 1].code == 0) {
        // If the last char becomes a null, convert to a hard line break.
        mls.eol = EOL_HARD;
    }

    [self markCharsDirty:YES
              inRectFrom:VT100GridCoordMake(MIN(self.rightMargin - 1, pos.x), pos.y)
                      to:VT100GridCoordMake(self.rightMargin, pos.y)];
    [self setCharsFrom:pos to:VT100GridCoordMake(pos.x + n - 1, pos.y) toChar:c externalAttributes:attrs];
}

- (NSArray<NSData *> *)orderedScreenCharDataWithAppendedContinuationMarks {
    NSMutableArray *array = [NSMutableArray array];
    for (int i = 0; i < size_.height; i++) {
        id<iTermLineStringReading> mls = [self lineStringAtLineNumber:i];
        NSData *data = [mls screenCharsDataWithEOL:YES];
        if (data.length != (size_.width + 1) * sizeof(screen_char_t)) {
            data = [mls screenCharsDataWithEOL:YES];
        }
        ITAssertWithMessage(data.length == (size_.width + 1) * sizeof(screen_char_t),
                            @"Wrong data size for %@", mls);
        [array addObject:data];
    }
    return array;
}

- (NSArray<VT100Metadata *> *)orderedLineInfos {
    return [self metadataArray];
}

- (NSDictionary *)dictionaryValue {
    return @{ kGridCursorKey: [NSDictionary dictionaryWithGridCoord:cursor_],
              kGridScrollRegionRowsKey: [NSDictionary dictionaryWithGridRange:scrollRegionRows_],
              kGridScrollRegionColumnsKey: [NSDictionary dictionaryWithGridRange:scrollRegionCols_],
              kGridUseScrollRegionColumnsKey: @(useScrollRegionCols_),
              kGridSizeKey: [NSDictionary dictionaryWithGridSize:size_] };
}

+ (VT100GridSize)sizeInStateDictionary:(NSDictionary *)dict {
    VT100GridSize size = [(NSDictionary *)dict[kGridSizeKey] gridSize];
    return size;
}

- (void)setStateFromDictionary:(NSDictionary *)dict {
    if (!dict || [dict isKindOfClass:[NSNull class]]) {
        return;
    }
    VT100GridSize size = [(NSDictionary *)dict[kGridSizeKey] gridSize];

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
    [_lines enumerateObjectsUsingBlock:^(iTermMutableLineString *mls, NSUInteger idx, BOOL *stop) {
        mls.timestamp = 0;
        mls.rtlFound = NO;
    }];
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
    [self mutableLineStringAtLineNumber:line].eol = code;
}

- (void)setContinuationCharacterOnLine:(int)line to:(screen_char_t)continuation {
    [self mutableLineStringAtLineNumber:line].continuation = continuation;
}

- (void)encode:(id<iTermEncoderAdapter>)encoder {
    NSArray<NSArray *> *metadata = [[self orderedLineInfos] mapWithBlock:^id(VT100Metadata *anObject) {
        return anObject.encodedMetadata;
    }];
    NSArray<NSData *> *lines = [[NSArray sequenceWithRange:NSMakeRange(0, size_.height)] mapWithBlock:^id(NSNumber *i) {
        return [[self lineStringAtLineNumber:i.intValue] screenCharsDataWithEOL:YES];
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
        NSMutableData *data = [self mutableLineStringAtLineNumber:y].mutableScreenCharsData;
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
        NSMutableData *data = [self mutableLineStringAtLineNumber:y].mutableScreenCharsData;
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

- (int)lengthOfParagraphFromLineNumber:(int)line {
    int length = 1;
    for (int i = line; i < self.size.height; i++) {
        if ([self continuationMarkForLineNumber:i] == EOL_HARD) {
            break;
        }
        length += 1;
    }
    return length;
}

- (void)enumerateParagraphs:(void (^)(int, NSArray<MutableScreenCharArray *> *))closure {
    for (int i = 0; i < self.size.height; ) {
        int length = [self lengthOfParagraphFromLineNumber:i];
        closure(i, [self mutableLinesInRange:NSMakeRange(i, length)]);
        i += length;
    }
}

- (NSArray<MutableScreenCharArray *> *)mutableLinesInRange:(NSRange)range {
    return [[NSArray sequenceWithRange:range] mapWithBlock:^id _Nullable(NSNumber *number) {
        return [self mutableScreenCharArrayForLine:number.intValue];
    }];
}

- (MutableScreenCharArray *)mutableScreenCharArrayForLine:(int)line {
    screen_char_t *chars = [self mutableScreenCharsAtLineNumber:line];
    return [[MutableScreenCharArray alloc] initWithLine:chars
                                                 length:self.size.width
                                               metadata:[self immutableMetadataAtLineNumber:line]
                                           continuation:chars[self.size.width]];
}

- (BOOL)mayContainRTLInRange:(NSRange)range {
    for (NSInteger i = 0; i < range.length; i++) {
        if ([self lineStringAtLineNumber:range.location + i].rtlFound) {
            return YES;
        }
    }
    return NO;
}

- (void)resetBidiDirty {
    _bidiDirty = NO;
}

- (BOOL)eraseBidiInfoInDirtyLines {
    const int height = self.size.height;
    if (height == _bidiInfo.count) {
        if (![self isAnyCharDirty]) {
            return NO;
        }
        for (int i = 0; i < height; i++) {
            if ([self dirtyRangeForLine:i].length <= 0) {
                continue;
            }
            if (![_bidiInfo[i] isKindOfClass:[NSNull class]]) {
                _bidiDirty = YES;
            }
            _bidiInfo[i] = [NSNull null];
        }
        return YES;
    }

    // Height has changed.
    [self initializeBidi];
    return YES;
}

- (void)initializeBidi {
    const int height = self.size.height;
    _bidiDirty = YES;
    _bidiInfo = [[NSMutableArray alloc] initWithCapacity:height];
    for (int i = 0; i < height; i++) {
        [_bidiInfo addObject:[NSNull null]];
    }
}

- (void)setBidiInfo:(iTermBidiDisplayInfo *)bidiInfo forLine:(int)line {
    if (bidiInfo) {
        if ([_bidiInfo[line] isKindOfClass:[NSNull class]]) {
            _bidiDirty = YES;
        }
        _bidiInfo[line] = bidiInfo;
    } else {
        if (![_bidiInfo[line] isKindOfClass:[NSNull class]]) {
            _bidiDirty = YES;
        }
        _bidiInfo[line] = [NSNull null];
    }
}

- (iTermBidiDisplayInfo *)bidiInfoForLine:(int)line {
    if (line  < 0 || line >= _bidiInfo.count) {
        return nil;
    }
    return [_bidiInfo[line] nilIfNull];
}

#pragma mark - Private

- (NSMutableArray<iTermMutableLineString *> *)linesWithSize:(VT100GridSize)size {
    NSMutableArray<iTermMutableLineString *> *lines = [[NSMutableArray alloc] initWithCapacity:size.height];
    for (int i = 0; i < size.height; i++) {
        iTermUniformString *u = [[iTermUniformString alloc] initWithCharacter:_defaultChar
                                                                        count:size.width];
        iTermMutableString *ms = [[iTermMutableString alloc] init];
        [ms appendString:u];
        [lines addObject:[[iTermMutableLineString alloc] initWithContent:ms
                                                                     eol:EOL_HARD
                                                            continuation:_defaultChar
                                                                metadata:(iTermLineStringMetadata){}]];
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

- (NSMutableData *)lineOfWidth:(int)width filledWithChar:(screen_char_t)c {
    NSMutableData *data = [NSMutableData dataWithLength:sizeof(screen_char_t) * (width + 1)];
    screen_char_t *line = data.mutableBytes;
    for (int i = 0; i < width + 1; i++) {
        line[i] = c;
    }
    return data;
}

- (void)clearLineDataBytes:(screen_char_t *)dest count:(NSInteger)length {
    const screen_char_t c = _defaultChar;
    for (int i = 0; i < length; i++) {
        dest[i] = c;
    }
}

// Returns number of lines dropped from line buffer because it exceeded its size (always 0 or 1).
- (int)appendLineToLineBuffer:(LineBuffer *)lineBuffer
          unlimitedScrollback:(BOOL)unlimitedScrollback {
    if (!lineBuffer) {
        return 0;
    }
    screen_char_t *line = [self mutableScreenCharsAtLineNumber:0];
    iTermMutableLineString *mls = [self mutableLineStringAtLineNumber:0];
    int len = [self lengthOfLine:mls];
    int continuationMark = mls.eol;
    if (continuationMark == EOL_DWC && len == size_.width) {
        --len;
    }
    [lineBuffer appendLine:line
                    length:len
                   partial:(continuationMark != EOL_HARD)
                     width:size_.width
                  metadata:[self immutableMetadataAtLineNumber:0]
              continuation:mls.continuation];
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
        if (![self lineIsEmpty:y]) {
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
        _lines = [self linesWithSize:newSize];

        scrollRegionRows_.location = MIN(scrollRegionRows_.location, size_.height - 1);
        scrollRegionRows_.length = MIN(scrollRegionRows_.length,
                                       size_.height - scrollRegionRows_.location);

        scrollRegionCols_.location = MIN(scrollRegionCols_.location, size_.width - 1);
        scrollRegionCols_.length = MIN(scrollRegionCols_.length,
                                       size_.width - scrollRegionCols_.location);

        cursor_.x = MIN(cursor_.x, size_.width - 1);
        self.cursorY = MIN(cursor_.y, size_.height - 1);
        [self initializeBidi];
        if (withSideEffects) {
            [self.delegate gridDidResize];
        }
#if DEBUG
        [self sanityCheck];
#endif
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

    const screen_char_t *line = [self screenCharsAtLineNumber:cy];
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
    return [[[self lineStringAtLineNumber:coord.y] content] characterAt:coord.x];
}

- (NSString *)stringForCharacterAt:(VT100GridCoord)coord {
    if (coord.y < 0 || coord.y >= _lines.count) {
        return nil;
    }
    const screen_char_t theChar = [self characterAt:coord];
    if (theChar.code == 0 && !theChar.complexChar) {
        return nil;
    }
    if (theChar.image) {
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
    iTermMutableLineString *mls = [self mutableLineStringAtLineNumber:lineNumber];
    if (mls.eol == EOL_DWC) {
        mls.eol = EOL_HARD;
        if (ScreenCharIsDWC_SKIP(mls.lastCharacter)) {  // This really should always be the case.
            [mls eraseCharacterAt:size_.width - 1];
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
    return [[[self mutableLineStringAtLineNumber:line] ensureLegacy] eaIndexCreatingIfNeeded:YES];
}

- (BOOL)erasePossibleDoubleWidthCharInLineNumber:(int)lineNumber
                                startingAtOffset:(int)offset
                                        withChar:(screen_char_t)c {
    screen_char_t *aLine = [self mutableScreenCharsAtLineNumber:lineNumber];
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
+ (NSString *)stringForScreenChars:(screen_char_t *)theLine length:(int)length {
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
    if (_bidiDirty || theCopy->_bidiInfo == nil) {
        theCopy->_bidiInfo = [_bidiInfo mutableCopy];
    }
}

- (id)copyWithZone:(NSZone *)zone {
    VT100Grid *theCopy = [[VT100Grid alloc] initWithSize:size_
                                                delegate:delegate_];
    theCopy->_lines = [_lines mapToMutableArrayWithBlock:^id _Nullable(iTermMutableLineString *mls) {
        return [mls mutableClone];
    }];
    theCopy->screenTop_ = screenTop_;
    [self copyMiscellaneousStateTo:theCopy];
#if DEBUG
        [self sanityCheck];
#endif

    return theCopy;
}

@end
