//
//  LineBlock.h
//  iTerm
//
//  Created by George Nachman on 11/21/13.
//
//

#import <Foundation/Foundation.h>
#import "FindContext.h"
#import "ScreenCharArray.h"
#import "iTermEncoderAdapter.h"
#import "iTermFindViewController.h"
#import "iTermMetadata.h"
#import "LineBlockMetadataArray.h"

NS_ASSUME_NONNULL_BEGIN

@class LineBlock;
@protocol iTermLineStringReading;
@class iTermMutableLineString;

// LineBlock represents an ordered collection of lines of text. It stores them contiguously
// in a buffer.
@interface LineBlock : NSObject <iTermUniquelyIdentifiable>

// Once this is set to true, it stays true. If double width characters are
// possibly present then a slower algorithm is used to count the number of
// lines. The default (fast) algorithm would give incorrect results for DWCs
// that get wrapped to the next line.
@property(nonatomic, assign) BOOL mayHaveDoubleWidthCharacter;
@property(nonatomic, readonly) int numberOfCharacters;
@property(nonatomic, readonly) NSInteger generation;

// Block this was copied from.
@property(nonatomic, weak, readonly, nullable) LineBlock *progenitor;
@property(nonatomic, readonly) BOOL invalidated;
@property(nonatomic, readonly) long long absoluteBlockNumber;

// Get the size of the raw buffer.
@property(nonatomic, readonly) int rawBufferSize;

// This is true if there is either a shallow (cowCopy) or deep (post-write) copy.
// We can make certain convenient assumptions when this is false:
// - It is not available to other threads so locking can be omitted.
// - There's no need to check if copy-on-write should be performed.
// - There are no clients.
// The only purpose is as a performance optimization. It is a nice win when appending lots of text.
@property(atomic, readonly) BOOL hasBeenCopied;

// Unique 0-based counter. Does not survive app restoration.
@property(nonatomic, readonly) unsigned int index;

// Called when an assertion fails to add more contextual information to the message.
@property(nonatomic, copy, nullable) NSString *(^debugInfo)(void);

// First valid raw line number.
@property(nonatomic, readonly) int firstEntry;
@property(nonatomic) int desiredCapacity;

+ (instancetype _Nullable)blockWithDictionary:(NSDictionary *)dictionary
                          absoluteBlockNumber:(long long)absoluteBlockNumber;

- (instancetype)initWithRawBufferSize:(int)size
                  absoluteBlockNumber:(long long)absoluteBlockNumber;

- (instancetype)init NS_UNAVAILABLE;

// Try to append a line to the end of the buffer. Returns false if it does not fit. If length > buffer_size it will never succeed.
// Callers should split such lines into multiple pieces.
- (BOOL)appendLineString:(id<iTermLineStringReading>)lineString
                   width:(int)width;

// Try to get a line that is lineNum after the first line in this block after wrapping them to a given width.
// If the line is not present, decrement *lineNum by the number of lines in this block and return nil.
- (id<iTermLineStringReading> _Nullable)wrappedLineStringWithWrapWidth:(int)width
                                                               lineNum:(int *)lineNum;

- (ScreenCharArray * _Nullable)screenCharArrayForWrappedLineWithWrapWidth:(int)width
                                                        lineNum:(int)lineNum
                                                       paddedTo:(int)paddedSize
                                                 eligibleForDWC:(BOOL)eligibleForDWC;

- (ScreenCharArray * _Nullable)rawLineAtWrappedLineOffset:(int)lineNum width:(int)width;
- (ScreenCharArray *)rawLineWithMetadataAtWrappedLineOffset:(int)lineNum width:(int)width;
- (NSNumber * _Nullable)rawLineNumberAtWrappedLineOffset:(int)lineNum width:(int)width;

// Get the number of lines in this block at a given screen width.
- (int)getNumLinesWithWrapWidth:(int)width;

// Only use this for development purposes. It is slow.
- (int)totallyUncachedNumLinesWithWrapWidth:(int)width;

// Returns whether getNumLinesWithWrapWidth will be fast.
- (BOOL)hasCachedNumLinesForWidth:(int)width;

// Returns true if the last line is incomplete.
- (BOOL)hasPartial;

// Remove the last line. Returns false if there was none.
- (id<iTermLineStringReading> _Nullable)popLastLineUpToWidth:(int)width
                                      forceSoftEOL:(BOOL)forceSoftEOL;

- (void)removeLastWrappedLines:(int)numberOfLinesToRemove
                         width:(int)width;
- (void)removeLastRawLine;
- (int)lengthOfLastLine;
- (int)lengthOfLastLineWrappedToWidth:(int)width;

// Drop lines from the start of the buffer. Returns the number of lines actually dropped
// (either n or the number of lines in the block).
- (int)dropLines:(int)n withWidth:(int)width chars:(int *)charsDropped;

// Returns true if there are no lines in the block
- (BOOL)isEmpty;

// Are all lines of length 0? True if there are no lines, as well.
- (BOOL)allLinesAreEmpty;

// Return the number of raw (unwrapped) lines
- (int)numRawLines;

// Return the position of the first used character in the raw buffer. Only valid if not empty.
- (int)startOffset;

// Return the length of a raw (unwrapped) line
- (int)lengthOfRawLine:(int)linenum;

// Return a raw line
- (id<iTermLineStringReading> _Nullable)rawLine:(int)linenum;
- (int)offsetOfRawLine:(int)linenum;

// NSLog the contents of the block. For debugging.
- (void)dump:(int)rawOffset droppedChars:(long long)droppedChars toDebugLog:(BOOL)toDebugLog;

// Returns the metadata associated with a line when wrapped to the specified width.
- (iTermImmutableMetadata)metadataForLineNumber:(int)lineNum width:(int)width;
- (iTermImmutableMetadata)metadataForRawLineAtWrappedLineOffset:(int)lineNum width:(int)width;

- (iTermBidiDisplayInfo * _Nullable)bidiInfoForLineNumber:(int)lineNum width:(int)width;

// Appends the contents of the block to |s|.
- (void)appendToDebugString:(NSMutableString *)s;

// Returns the total number of bytes used, including dropped chars.
- (int)rawSpaceUsed;

// Returns the total number of lines, including dropped lines.
- (int)numEntries;

// Searches for a substring, populating results with ResultRange objects.
// Note that when searching backwards offset is actually the upper bound; the search begins just *before* it.
- (void)findSubstring:(NSString*)substring
              options:(FindOptions)options
                 mode:(iTermFindMode)mode
             atOffset:(int)offset
              results:(NSMutableArray*)results
      multipleResults:(BOOL)multipleResults
includesPartialLastLine:(BOOL *)includesPartialLastLine;

// Tries to convert a byte offset into the block to an x,y coordinate relative to the first char
// in the block. Returns YES on success, NO if the position is out of range.
//
// If the position is after the last character on a line, wrapEOL determines if it will return the
// coordinate of the first null on that line of the first character on the next line.
- (BOOL)convertPosition:(int)position
              withWidth:(int)width
              wrapOnEOL:(BOOL)wrapOnEOL
                    toX:(int*)x
                    toY:(int*)y;

// Returns the position of a char at (x, lineNum). Fills in yOffsetPtr with number of blank lines
// before that cell, and sets *extendsPtr if x is at the right margin (after nulls).
- (int)getPositionOfLine:(int*)lineNum
                     atX:(int)x
               withWidth:(int)width
                 yOffset:(int *)yOffsetPtr
                 extends:(BOOL *)extendsPtr;

// Offset into the block of the start of the wrapped line that includes the character at `offset`.
- (int)offsetOfStartOfLineIncludingOffset:(int)offset;

// Count the number of "full lines" in buffer up to position 'length'. A full
// line is one that, after wrapping, goes all the way to the edge of the screen
// and has at least one character wrap around. It is equal to the number of
// lines after wrapping minus one. Examples:
//
// 2 Full Lines:    0 Full Lines:   0 Full Lines:    1 Full Line:
// |xxxxx|          |x     |        |xxxxxx|         |xxxxxx|
// |xxxxx|                                           |x     |
// |x    |
- (int)numberOfFullLinesFromOffset:(int)offset
                            length:(int)length
                             width:(int)width;
// Finds a where the nth line begins after wrapping and returns its offset from the start of the
// buffer.
//
// In the following example, this would return:
// pointer to a if n==0, pointer to g if n==1, asserts if n > 1
// |abcdef|
// |ghi   |
//
// It's more complex with double-width characters.
// In this example, suppose XX is a double-width character.
//
// Returns a pointer to a if n==0, pointer XX if n==1, asserts if n > 1:
// |abcde|   <- line is short after wrapping
// |XXzzzz|
// The slow code for dealing with DWCs is run only if mayHaveDwc is YES.
int OffsetOfWrappedLine(LineBlock *self, int startOffset, int n, int length, int width, BOOL mayHaveDwc);

// Returns a dictionary with the contents of this block. The data is a weak reference and will be
// invalid if the block is changed.
- (NSDictionary *)dictionary;

// Number of empty lines at the end of the block.
- (int)numberOfTrailingEmptyLines;
- (int)numberOfLeadingEmptyLines;
- (BOOL)containsAnyNonEmptyLine;

// Call this only before a line block has been created.
void EnableDoubleWidthCharacterLineCache(void);

- (void)setPartial:(BOOL)partial;
- (ScreenCharArray * _Nullable)lastRawLine;

// For tests only
- (LineBlockMutableMetadata)internalMetadataForLine:(int)line;
- (BOOL)hasOwner;
- (void)dropMirroringProgenitor:(LineBlock *)other;
- (BOOL)isSynchronizedWithProgenitor;
- (void)invalidate;
- (NSInteger)sizeFromLine:(int)lineNum width:(int)width;

- (id)copy NS_UNAVAILABLE;
- (id)copyWithZone:(NSZone * _Nullable)zone NS_UNAVAILABLE;
- (LineBlock *)cowCopy;

- (instancetype)copyWithAbsoluteBlockNumber:(long long)absoluteBlockNumber;
- (NSString *)dumpString;
- (NSString *)dumpStringWithDroppedChars:(long long)droppedChars;
- (void)sanityCheckMetadataCache;
- (void)reloadBidiInfo;

// This doesn't support CoW so only call this before making the first copy.
- (void)eraseRTLStatusInAllCharacters;
- (void)setBidiForLastRawLine:(iTermBidiDisplayInfo * _Nullable)bidi;

#pragma mark - Testing

- (NSInteger)numberOfClients;

@end

NS_ASSUME_NONNULL_END

