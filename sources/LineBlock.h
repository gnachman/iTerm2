//
//  LineBlock.h
//  iTerm
//
//  Created by George Nachman on 11/21/13.
//
//

#import <Foundation/Foundation.h>
#import "CVector.h"
#import "FindContext.h"
#import "ScreenCharArray.h"
#import "iTermEncoderAdapter.h"
#import "iTermFindViewController.h"
#import "iTermMetadata.h"
#import "LineBlockMetadataArray.h"

NS_ASSUME_NONNULL_BEGIN

@class LineBlock;

extern dispatch_queue_t _Nullable gDeallocQueue;

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
@property(nonatomic, readonly) int firstEntry;
@property(nonatomic, readonly) NSInteger numberOfClients;

+ (nullable instancetype)blockWithDictionary:(NSDictionary *)dictionary
                         absoluteBlockNumber:(long long)absoluteBlockNumber;

- (instancetype)initWithRawBufferSize:(int)size
                  absoluteBlockNumber:(long long)absoluteBlockNumber;

- (instancetype)initWithItems:(CTVector(iTermAppendItem) *)items
                    fromIndex:(int)startIndex
                        width:(int)width
          absoluteBlockNumber:(long long)absoluteBlockNumber;

- (instancetype)initWithItems:(CTVector(iTermAppendItem) *)items
                    fromIndex:(int)startIndex
                        width:(int)width
          absoluteBlockNumber:(long long)absoluteBlockNumber
    continuationPrefixCharacters:(int)prefixCharacters
                 prefixHasDWC:(BOOL)prefixHasDWC;

- (instancetype)init NS_UNAVAILABLE;

// Try to append a line to the end of the buffer. Returns false if it does not fit. If length > buffer_size it will never succeed.
// Callers should split such lines into multiple pieces.
- (BOOL)appendLine:(const screen_char_t * _Nonnull)buffer
            length:(int)length
           partial:(BOOL)partial
             width:(int)width
          metadata:(iTermImmutableMetadata)metadata
      continuation:(screen_char_t)continuation;

// Update the last raw line's metadata scalars (timestamp, rtlFound) by
// appending `metadata` using iTermMetadataAppend semantics. Does NOT
// reset wrapped-line caches or DWC/bidi info—use this only for
// cross-block metadata propagation where the character data is unchanged.
- (void)propagateMetadataToLastRawLine:(iTermImmutableMetadata)metadata
                              length:(int)additionalLength;

// Try to get a line that is lineNum after the first line in this block after wrapping them to a given width.
// If the line is present, return a pointer to its start and fill in *lineLength with the number of bytes in the line.
// If the line is not present, decrement *lineNum by the number of lines in this block and return NULL.
- (const screen_char_t * _Nullable)getWrappedLineWithWrapWidth:(int)width
                                      lineNum:(int * _Nonnull)lineNum
                                   lineLength:(int * _Nonnull)lineLength
                            includesEndOfLine:(int * _Nonnull)includesEndOfLine
                                 continuation:(screen_char_t * _Nullable)continuationPtr;

// Sets *yOffsetPtr (if not null) to the number of consecutive empty lines just before |lineNum| because
// there's no way for the returned pointer to indicate this.
- (const screen_char_t * _Nullable)getWrappedLineWithWrapWidth:(int)width
                                             lineNum:(int * _Nonnull)lineNum
                                          lineLength:(int * _Nonnull)lineLength
                                   includesEndOfLine:(int * _Nonnull)includesEndOfLine
                                             yOffset:(int * _Nullable)yOffsetPtr
                                        continuation:(screen_char_t * _Nullable)continuationPtr
                                isStartOfWrappedLine:(BOOL * _Nullable)isStartOfWrappedLine
                                            metadata:(out iTermImmutableMetadata * _Nullable)metadataPtr;

- (nullable ScreenCharArray *)screenCharArrayForWrappedLineWithWrapWidth:(int)width
                                                                 lineNum:(int)lineNum
                                                                paddedTo:(int)paddedSize
                                                          eligibleForDWC:(BOOL)eligibleForDWC;

- (nullable ScreenCharArray *)rawLineAtWrappedLineOffset:(int)lineNum width:(int)width;
- (nullable NSNumber *)rawLineNumberAtWrappedLineOffset:(int)lineNum width:(int)width;

// Get the number of lines in this block at a given screen width.
- (int)getNumLinesWithWrapWidth:(int)width;

// Only use this for development purposes. It is slow.
- (int)totallyUncachedNumLinesWithWrapWidth:(int)width;

// Returns whether getNumLinesWithWrapWidth will be fast.
- (BOOL)hasCachedNumLinesForWidth:(int)width;

// Returns true if the last line is incomplete.
- (BOOL)hasPartial;

// When >= 0, this block's first raw line is a continuation of the previous
// block's last (partial) raw line. The value is the total number of
// characters in the combined raw line that precede this block's portion.
// -1 means no continuation.
@property(nonatomic, readonly) int continuationPrefixCharacters;

// YES when continuationPrefixCharacters >= 0.
@property(nonatomic, readonly) BOOL startsWithContinuation;

// Remove the last line. Returns false if there was none.
- (BOOL)popLastLineInto:(screen_char_t const * _Nullable * _Nullable)ptr
             withLength:(int * _Nonnull)length
              upToWidth:(int)width
               metadata:(out iTermImmutableMetadata * _Nullable)metadataPtr
           continuation:(screen_char_t * _Nullable)continuationPtr;

- (void)removeLastWrappedLines:(int)numberOfLinesToRemove
                         width:(int)width;
- (void)removeLastCells:(int)count;
- (void)removeLastRawLine;
- (int)lengthOfLastLine;
- (int)numberOfWrappedLinesForLastRawLineWrappedToWidth:(int)width;
- (int)lengthOfLastWrappedLineForWidth:(int)width;

// Drop lines from the start of the buffer. Returns the number of lines actually dropped
// (either n or the number of lines in the block).
- (int)dropLines:(int)n withWidth:(int)width chars:(int * _Nullable)charsDropped;

// Returns true if there are no lines in the block
- (BOOL)isEmpty;

// Are all lines of length 0? True if there are no lines, as well.
- (BOOL)allLinesAreEmpty;

// Grow the buffer.
- (void)changeBufferSize:(int)capacity;

// Return the number of raw (unwrapped) lines
- (int)numRawLines;

// Return the position of the first used character in the raw buffer. Only valid if not empty.
- (int)startOffset;

// Return the length of a raw (unwrapped) line
- (int)lengthOfRawLine:(int)linenum;

// Remove extra space from the end of the buffer. Future appends will fail.
- (void)shrinkToFit;

// Return a raw line
- (const screen_char_t * _Nullable)rawLine:(int)linenum;
- (ScreenCharArray *)screenCharArrayForRawLine:(int)linenum;

- (NSString *)debugStringForRawLine:(int)i;

// NSLog the contents of the block. For debugging.
- (void)dump:(int)rawOffset droppedChars:(long long)droppedChars toDebugLog:(BOOL)toDebugLog;

// Returns the metadata associated with a line when wrapped to the specified width.
- (iTermImmutableMetadata)metadataForLineNumber:(int)lineNum width:(int)width;
- (iTermImmutableMetadata)metadataForRawLineAtWrappedLineOffset:(int)lineNum width:(int)width;

- (nullable iTermBidiDisplayInfo *)bidiInfoForLineNumber:(int)lineNum width:(int)width;

// Appends the contents of the block to |s|.
- (void)appendToDebugString:(NSMutableString *)s;

// Returns the total number of screen_char_t's used, including dropped cells.
- (int)rawSpaceUsed;

// Returns the total number of screen_char_t's used, excluding dropped cells.
- (int)nonDroppedSpaceUsed;

// Returns the total number of lines, including dropped lines.
- (int)numEntries;

// Searches for a substring, populating results with ResultRange objects.
// For multi-line searches that may span blocks:
// - Pass priorState if continuing a partial match from a previous block
// - continuationState will be set if a partial match needs to continue on the next block
// - crossBlockResultCount returns the number of results that came from cross-block matches
//   (these already have global positions and should not be adjusted by blockPosition)
- (void)findSubstring:(NSString *)substring
              options:(FindOptions)options
                 mode:(iTermFindMode)mode
             atOffset:(int)offset
              results:(NSMutableArray *)results
      multipleResults:(BOOL)multipleResults
includesPartialLastLine:(BOOL * _Nullable)includesPartialLastLine
  multiLinePriorState:(LineBlockMultiLineSearchState * _Nullable)priorState
    continuationState:(LineBlockMultiLineSearchState * _Nullable * _Nullable)continuationState
crossBlockResultCount:(NSInteger * _Nullable)crossBlockResultCount;

// Tries to convert a byte offset into the block to an x,y coordinate relative to the first char
// in the block. Returns YES on success, NO if the position is out of range.
//
// If the position is after the last character on a line, wrapEOL determines if it will return the
// coordinate of the first null on that line of the first character on the next line.
- (BOOL)convertPosition:(int)position
              withWidth:(int)width
              wrapOnEOL:(BOOL)wrapOnEOL
                    toX:(int * _Nonnull)x
                    toY:(int * _Nonnull)y;

// Returns the position of a char at (x, lineNum). Fills in yOffsetPtr with number of blank lines
// before that cell, and sets *extendsPtr if x is at the right margin (after nulls).
- (int)getPositionOfLine:(int * _Nonnull)lineNum
                     atX:(int)x
               withWidth:(int)width
                 yOffset:(int * _Nullable)yOffsetPtr
                 extends:(BOOL * _Nullable)extendsPtr;

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

- (int)numberOfFullLinesFromBuffer:(const screen_char_t * _Nonnull)buffer
                            length:(int)length
                             width:(int)width;

- (int)offsetOfRawLine:(int)linenum;

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
int OffsetOfWrappedLine(const screen_char_t * _Nonnull p, int n, int length, int width, BOOL mayHaveDwc);

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
- (nullable ScreenCharArray *)lastRawLine;

// For tests only
- (LineBlockMutableMetadata)internalMetadataForLine:(int)line;
- (BOOL)hasOwner;
- (void)dropMirroringProgenitor:(LineBlock *)other;
- (BOOL)isSynchronizedWithProgenitor;
- (void)invalidate;
- (NSInteger)sizeFromLine:(int)lineNum width:(int)width;

- (id)copy NS_UNAVAILABLE;
- (id)copyWithZone:(nullable NSZone *)zone NS_UNAVAILABLE;
- (LineBlock *)cowCopy;

- (instancetype)copyWithAbsoluteBlockNumber:(long long)absoluteBlockNumber;
- (NSString *)dumpString;
- (NSString *)dumpStringWithDroppedChars:(long long)droppedChars;
- (void)sanityCheckMetadataCache;
- (void)reloadBidiInfo;

// This doesn't support CoW so only call this before making the first copy.
- (void)eraseRTLStatusInAllCharacters;
- (void)setBidiForLastRawLine:(nullable iTermBidiDisplayInfo *)bidi;

@end

NS_ASSUME_NONNULL_END
