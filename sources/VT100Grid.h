//
//  VT100Grid.h
//  iTerm
//
//  Created by George Nachman on 10/9/13.
//
//

#import <Foundation/Foundation.h>
#import "DVRIndexEntry.h"
#import "ScreenChar.h"
#import "VT100GridTypes.h"
#import "iTermMetadata.h"

@class LineBuffer;
@class VT100LineInfo;
@class VT100Terminal;
@protocol iTermEncoderAdapter;

@protocol VT100GridDelegate <NSObject>
- (iTermUnicodeNormalization)gridUnicodeNormalizationForm;
- (void)gridCursorDidMove;
- (void)gridCursorDidChangeLineFrom:(int)previuos;
- (void)gridDidResize;
@end

@protocol VT100GridReading<NSCopying, NSObject>
@property(nonatomic, readonly) VT100GridSize size;
@property(nonatomic, readonly) int cursorX;
@property(nonatomic, readonly) int cursorY;
@property(nonatomic, readonly) VT100GridCoord cursor;
@property(nonatomic, readonly) BOOL haveScrollRegion;  // is there a left-right or top-bottom margin?
@property(nonatomic, readonly) BOOL haveRowScrollRegion;  // is there a top-bottom margin?
@property(nonatomic, readonly) BOOL haveColumnScrollRegion;  // is there a left-right margin?
@property(nonatomic, readonly) VT100GridRange scrollRegionRows;
@property(nonatomic, readonly) VT100GridRange scrollRegionCols;
@property(nonatomic, readonly) BOOL useScrollRegionCols;
@property(nonatomic, readonly, getter=isAllDirty) BOOL allDirty;
@property(nonatomic, readonly) int leftMargin;
@property(nonatomic, readonly) int rightMargin;
@property(nonatomic, readonly) int topMargin;
@property(nonatomic, readonly) int bottomMargin;
@property(nonatomic, readonly) screen_char_t savedDefaultChar;
@property(nonatomic, weak, readonly) id<VT100GridDelegate> delegate;
@property(nonatomic, readonly) VT100GridCoord preferredCursorPosition;
@property(nonatomic, readonly) VT100GridSize sizeRespectingRegionConditionally;
@property(nonatomic, readonly) BOOL haveScrolled;
@property(nonatomic, readonly) NSDictionary *dictionaryValue;
@property(nonatomic, readonly) NSArray<VT100LineInfo *> *metadataArray;
@property(nonatomic, readonly) screen_char_t defaultChar;

- (id<VT100GridReading>)copy;

- (const screen_char_t *)screenCharsAtLineNumber:(int)lineNumber;
- (iTermImmutableMetadata)immutableMetadataAtLineNumber:(int)lineNumber;
- (BOOL)isCharDirtyAt:(VT100GridCoord)coord;
- (BOOL)isAnyCharDirty;

// Returns the set of dirty indexes on |line|.
- (NSIndexSet *)dirtyIndexesOnLine:(int)line;
- (VT100GridRange)dirtyRangeForLine:(int)y;

// Returns the count of lines excluding totally empty lines at the bottom, and always including the
// line the cursor is on.
- (int)numberOfLinesUsed;

// Like numberOfLinesUsed, but it doesn't care about where the cursor is. Also, if
// `includeWhitespace` is YES then spaces and tabs are considered empty.
- (int)numberOfNonEmptyLinesIncludingWhitespaceAsEmpty:(BOOL)whitespaceIsEmpty;

// Number of used chars in line at lineNumber.
- (int)lengthOfLineNumber:(int)lineNumber;

- (screen_char_t)defaultChar;
- (NSData *)defaultLineOfWidth:(int)width;

// Converts a range relative to the start of a row into a grid run. If row is negative, a smaller-
// than-range.length (but valid!) grid run will be returned.
- (VT100GridRun)gridRunFromRange:(NSRange)range relativeToRow:(int)row;

// Returns temp storage for one line. While this is mutable, it's trivial because it's used only temporarily as a convenience to the caller.
- (screen_char_t *)resultLine;

// Returns a human-readable string with the screen contents and dirty lines interspersed.
- (NSString *)debugString;

// Returns a string for the character at |coord|.
- (NSString *)stringForCharacterAt:(VT100GridCoord)coord;
- (VT100GridCoord)successorOf:(VT100GridCoord)coord;
- (screen_char_t)characterAt:(VT100GridCoord)coord;

// Converts a run into one or more VT100GridRect NSValues.
- (NSArray *)rectsForRun:(VT100GridRun)run;

// Returns a rect describing the current scroll region. Takes useScrollRegionCols into account.
- (VT100GridRect)scrollRegionRect;

// Returns the timestamp of a given line.
- (NSTimeInterval)timestampForLine:(int)y;

- (NSString *)compactLineDump;
- (NSString *)compactLineDumpWithTimestamps;
- (NSString *)compactLineDumpWithContinuationMarks;
- (NSString *)compactDirtyDump;

// Returns the coordinate of the cell before this one. It respects scroll regions and double-width
// characters.
// Returns (-1,-1) if there is no previous cell.
- (VT100GridCoord)coordinateBefore:(VT100GridCoord)coord movedBackOverDoubleWidth:(BOOL *)dwc;

// Saves restorable state. Goes with initWithDictionary:delegate:
- (void)encode:(id<iTermEncoderAdapter>)encoder;

// Returns an array of NSData for lines in order (corresponding with lines on screen).
- (NSArray *)orderedLines;

- (void)enumerateCellsInRect:(VT100GridRect)rect
                       block:(void (^)(VT100GridCoord, screen_char_t, iTermExternalAttribute *, BOOL *))block;

// Append the first numLines to the given line buffer. Returns the number of lines appended.
- (int)appendLines:(int)numLines
      toLineBuffer:(LineBuffer *)lineBuffer
makeCursorLineSoft:(BOOL)makeCursorLineSoft;

// Defaults makeCursorLineSoft=NO
- (int)appendLines:(int)numLines
      toLineBuffer:(LineBuffer *)lineBuffer;

// This is the sole mutation method. We need it to track which lines need to be redrawn and to reduce
// the cost of syncing.
- (void)markAllCharsDirty:(BOOL)dirty updateTimestamps:(BOOL)updateTimestamps;

// How many used cells exist in the range of lines?
- (NSInteger)numberOfCellsUsedInRange:(VT100GridRange)range;

- (BOOL)lineIsEmpty:(int)n;

@end

@interface VT100Grid : NSObject<VT100GridReading> {
@public
    // A gross little optimization
    screen_char_t _defaultChar;
}

// Changing the size erases grid contents.
@property(nonatomic, readwrite) VT100GridSize size;
@property(nonatomic, readwrite) int cursorX;
@property(nonatomic, readwrite) int cursorY;
@property(nonatomic, readwrite) VT100GridCoord cursor;
@property(nonatomic, readonly) BOOL haveScrollRegion;  // is there a left-right or top-bottom margin?
@property(nonatomic, readonly) BOOL haveRowScrollRegion;  // is there a top-bottom margin?
@property(nonatomic, readonly) BOOL haveColumnScrollRegion;  // is there a left-right margin?
@property(nonatomic, readwrite) VT100GridRange scrollRegionRows;
@property(nonatomic, readwrite) VT100GridRange scrollRegionCols;
@property(nonatomic, readwrite) BOOL useScrollRegionCols;
@property(nonatomic, readwrite, getter=isAllDirty) BOOL allDirty;
@property(nonatomic, readonly) int leftMargin;
@property(nonatomic, readonly) int rightMargin;
@property(nonatomic, readonly) int topMargin;
@property(nonatomic, readonly) int bottomMargin;
@property(nonatomic, readwrite) screen_char_t savedDefaultChar;
@property(nonatomic, readwrite) screen_char_t defaultChar;
@property(nonatomic, weak, readwrite) id<VT100GridDelegate> delegate;
@property(nonatomic, readwrite) VT100GridCoord preferredCursorPosition;
// Size of the grid if the cursor is outside the scroll region. Otherwise, size of the scroll region.
@property(nonatomic, readonly) VT100GridSize sizeRespectingRegionConditionally;

// Did the whole screen scroll up? Won't be reflected in dirty bits.
@property(nonatomic, assign) BOOL haveScrolled;

// Serialized state, but excludes screen contents.
// DEPRECATED - use encode: instead.
@property(nonatomic, readonly) NSDictionary *dictionaryValue;
@property(nonatomic, readonly) NSArray<VT100LineInfo *> *metadataArray;
// Time of last update. Used for setting timestamps.
@property(nonatomic) NSTimeInterval currentDate;
@property(nonatomic) BOOL hasChanged;

+ (VT100GridSize)sizeInStateDictionary:(NSDictionary *)dict;

- (instancetype)initWithSize:(VT100GridSize)size delegate:(id<VT100GridDelegate>)delegate;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary
                          delegate:(id<VT100GridDelegate>)delegate;

- (VT100Grid *)copy;

- (screen_char_t *)screenCharsAtLineNumber:(int)lineNumber;
- (iTermMetadata)metadataAtLineNumber:(int)lineNumber;

// Set both x and y coord of cursor at once. Cursor positions are clamped to legal values. The cursor
// may extend into the right edge (cursorX == size.width is allowed).
- (void)setCursor:(VT100GridCoord)coord;

// Mark a specific character dirty. If updateTimestamp is set, then the line's last-modified time is
// set to the current time.
- (void)markCharDirty:(BOOL)dirty at:(VT100GridCoord)coord updateTimestamp:(BOOL)updateTimestamp;

// Mark chars dirty in a rectangle, inclusive of endpoints.
- (void)markCharsDirty:(BOOL)dirty inRectFrom:(VT100GridCoord)from to:(VT100GridCoord)to;

// Advances the cursor down one line and scrolls the screen, or part of the screen, if necessary.
// Returns the number of lines dropped from lineBuffer. lineBuffer may be nil. If a scroll region is
// present, the lineBuffer is only added to if useScrollbackWithRegion is set. willScroll is called
// if the region will need to scroll up by one line.
- (int)moveCursorDownOneLineScrollingIntoLineBuffer:(LineBuffer *)lineBuffer
                                unlimitedScrollback:(BOOL)unlimitedScrollback
                            useScrollbackWithRegion:(BOOL)useScrollbackWithRegion
                                         willScroll:(void (^)(void))willScroll;

- (void)mutateCellsInRect:(VT100GridRect)rect
                    block:(void (^NS_NOESCAPE)(VT100GridCoord, screen_char_t *, iTermExternalAttribute **, BOOL *))block;

// Move cursor to the left by n steps. Does not wrap around when it hits the left margin.
// If it starts left of the scroll region, clamp it to the left. If it starts right of the scroll
// region, don't move it.  TODO: This is probably wrong w/r/t scroll region logic.
- (void)moveCursorLeft:(int)n;

// Move cursor to the right by n steps. Does not wrap around when it hits the right margin. The
// cursor is not permitted to extend into the width'th column, which setCursorX: allows.
// It has a similar same logic oddity as moveCursorLeft:, but slightly different (if the cursor's
// moved position is inside the scroll region, then it can change).
- (void)moveCursorRight:(int)n;

// Move cursor up by n steps. If there is a scroll region, it won't go past the top.
// Also clamps the cursor's x position to be valid.
- (void)moveCursorUp:(int)n;

// Move cursor down by n steps. If there is a scroll region, it won't go past the bottom.
// Also clamps the cursor's x position to be valid.
- (void)moveCursorDown:(int)n;

// Move cursor up one line.
// Scroll the screen or a region of the screen up by one line. If lineBuffer is set, a line scrolled
// off the top will be moved into the line buffer. If a scroll region is present, the lineBuffer is
// only added to if useScrollbackWithRegion is set.

// When scrolling vertically within a region, the |softBreak| flag is used.
// If |softBreak| is YES then the soft line break on the top line (when scrolling down) or bottom
// line (when scrolling up) is preserved. Otherwise it is made hard.
- (int)scrollUpIntoLineBuffer:(LineBuffer *)lineBuffer
          unlimitedScrollback:(BOOL)unlimitedScrollback
      useScrollbackWithRegion:(BOOL)useScrollbackWithRegion
                    softBreak:(BOOL)softBreak;

// Scroll the whole screen into the line buffer by one line. Returns the number of lines dropped.
// Scroll regions are ignored.
- (int)scrollWholeScreenUpIntoLineBuffer:(LineBuffer *)lineBuffer
                     unlimitedScrollback:(BOOL)unlimitedScrollback;

// Scroll the scroll region down by one line.
- (void)scrollDown;
- (void)moveContentLeft:(int)n;
- (void)moveContentRight:(int)n;

// Clear scroll region, clear screen, move cursor and saved cursor to origin, leaving only the last
// non-empty line at the top of the screen. Some lines may be left behind by giving a positive value
// for |leave|.
- (int)resetWithLineBuffer:(LineBuffer *)lineBuffer
       unlimitedScrollback:(BOOL)unlimitedScrollback
        preserveCursorLine:(BOOL)preserveCursorLine
     additionalLinesToSave:(int)additionalLinesToSave;

// Move the grid contents up, leaving only the whole wrapped line the cursor is on at the top.
- (void)moveWrappedCursorLineToTopOfGrid;

// Set chars in a rectangle, inclusive of from and to. It will clean up orphaned DWCs.
- (void)setCharsFrom:(VT100GridCoord)from to:(VT100GridCoord)to toChar:(screen_char_t)c externalAttributes:(iTermExternalAttribute *)attribute;

// Same as above, but for runs.
- (void)setCharsInRun:(VT100GridRun)run toChar:(unichar)c externalAttributes:(iTermExternalAttribute *)ea;

// Copy everything from another grid if needed.
- (void)copyDirtyFromGrid:(VT100Grid *)otherGrid didScroll:(BOOL)didScroll;

// Append a string starting from the cursor's current position.
// Returns number of scrollback lines dropped from lineBuffer.
- (int)appendCharsAtCursor:(const screen_char_t *)buffer
                    length:(int)len
   scrollingIntoLineBuffer:(LineBuffer *)lineBuffer
       unlimitedScrollback:(BOOL)unlimitedScrollback
   useScrollbackWithRegion:(BOOL)useScrollbackWithRegion
                wraparound:(BOOL)wraparound
                      ansi:(BOOL)ansi
                    insert:(BOOL)insert
    externalAttributeIndex:(id<iTermExternalAttributeIndexReading>)attributes;

// Delete some number of chars starting at a given location, moving chars to the right of them back.
- (void)deleteChars:(int)num
         startingAt:(VT100GridCoord)startCoord;

// Scroll a rectangular area of the screen down (positive direction) or up (negative direction).
// Clears the left-over region.
// If |softBreak| is YES then the soft line break on the top line (when scrolling down) or bottom
// line (when scrolling up) is preserved. Otherwise it is made hard.
- (void)scrollRect:(VT100GridRect)rect downBy:(int)direction softBreak:(BOOL)softBreak;

// Load contents from a DVR frame.
- (void)setContentsFromDVRFrame:(const screen_char_t*)s
                  metadataArray:(iTermMetadata *)sourceMetadataArray
                           info:(DVRFrameInfo)info;

// Scroll backwards, pulling content from history back in to the grid. The lowest lines of the grid
// will be lost.
- (int)scrollWholeScreenDownByLines:(int)count poppingFromLineBuffer:(LineBuffer *)lineBuffer;

// Returns a grid-owned empty line.
- (NSMutableData *)defaultLineOfWidth:(int)width;

// Set background/foreground colors in a range.
- (void)setBackgroundColor:(screen_char_t)bg
           foregroundColor:(screen_char_t)fg
                inRectFrom:(VT100GridCoord)from
                        to:(VT100GridCoord)to;

// Set URLCode in a range.
- (void)setURLCode:(unsigned int)code
        inRectFrom:(VT100GridCoord)from
                to:(VT100GridCoord)to;

- (void)setBlockID:(NSString *)blockID onLine:(int)line;

// Pop lines out of the line buffer and on to the screen. Up to maxLines will be restored. Before
// popping, lines to be modified will first be filled with defaultChar.
// Returns whether the cursor position was set.
- (BOOL)restoreScreenFromLineBuffer:(LineBuffer *)lineBuffer
                    withDefaultChar:(screen_char_t)defaultChar
                  maxLinesToRestore:(int)maxLines;

// Ensure the cursor and savedCursor positions are valid.
- (void)clampCursorPositionToValid;

// Returns temp storage for one line.
- (screen_char_t *)resultLine;

// Reset scroll regions to whole screen. NOTE: It does not reset useScrollRegionCols.
- (void)resetScrollRegions;

// If a DWC is present at (offset, lineNumber), then both its cells are erased. They're replaced
// with c (normally -defaultChar). If there's a DWC_SKIP + EOL_DWC on the preceding line
// when offset==0 then those are converted to a null and EOL_HARD. Returns true if a DWC was erased.
- (BOOL)erasePossibleDoubleWidthCharInLineNumber:(int)lineNumber
                                startingAtOffset:(int)offset
                                        withChar:(screen_char_t)c;

// Moves the cursor to the left margin (either 0 or scrollRegionCols.location, depending on
// useScrollRegionCols).
- (void)moveCursorToLeftMargin;

- (void)setContinuationMarkOnLine:(int)line to:(unichar)code ;

// TODO: write a test for this
- (void)insertChar:(screen_char_t)c externalAttributes:(iTermExternalAttribute *)attrs at:(VT100GridCoord)pos times:(int)num;

// Restore saved state excluding screen contents.
// DEPRECATED - use initWithDictionary:delegate: instead.
- (void)setStateFromDictionary:(NSDictionary *)dict;

// Reset timestamps to the uninitialized state.
- (void)resetTimestamps;

// If there is a preferred cursor position that is legal, restore it.
- (void)restorePreferredCursorPositionIfPossible;

- (void)mutateCharactersInRange:(VT100GridCoordRange)range
                          block:(void (^)(screen_char_t *sct,
                                          iTermExternalAttribute **eaOut,
                                          VT100GridCoord coord,
                                          BOOL *stop))block;

#pragma mark - Testing use only

- (VT100LineInfo *)lineInfoAtLineNumber:(int)lineNumber;

@end
