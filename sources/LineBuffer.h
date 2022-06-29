// -*- mode:objc -*-
/*
 **  LineBuffer.h
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: George Nachman
 **
 **  Project: iTerm
 **
 **  Description: Implements a buffer of lines. It can hold a large number
 **   of lines and can quickly format them to a fixed width.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import <Cocoa/Cocoa.h>
#import "FindContext.h"
#import "iTermEncoderAdapter.h"
#import "iTermFindDriver.h"
#import "ScreenCharArray.h"
#import "LineBufferPosition.h"
#import "LineBufferHelpers.h"
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class LineBlock;
@class LineBuffer;
@class ResultRange;

@protocol iTermLineBufferDelegate<NSObject>
- (void)lineBufferDidDropLines:(LineBuffer * _Nonnull)lineBuffer;
@end

@protocol LineBufferReading<NSObject, NSCopying>
@property(nonatomic, readonly) BOOL mayHaveDoubleWidthCharacter;
// Absolute block number of last block.
@property(nonatomic, readonly) int largestAbsoluteBlockNumber;
// Returns the metadata associated with a line when wrapped to the specified width.
- (iTermImmutableMetadata)metadataForLineNumber:(int)lineNum width:(int)width;

// Metadata for the whole raw line.
- (iTermImmutableMetadata)metadataForRawLineWithWrappedLineNumber:(int)lineNum width:(int)width;

// Copy a line into the buffer. If the line is shorter than 'width' then only the first 'width'
// characters will be modified.
// 0 <= lineNum < numLinesWithWidth:width
// Returns EOL code.
// DEPRECATED, use wrappedLineAtIndex:width: instead.
- (int)copyLineToBuffer:(screen_char_t * _Nonnull)buffer
                  width:(int)width
                lineNum:(int)lineNum
           continuation:(screen_char_t * _Nullable)continuationPtr;

- (void)enumerateLinesInRange:(NSRange)range
                        width:(int)width
                        block:(void (^ _Nonnull)(int,
                                                 ScreenCharArray * _Nonnull,
                                                 iTermImmutableMetadata,
                                                 BOOL * _Nonnull))block;

// Like the above but with a saner way of holding the returned data. Callers are advised not
// to modify the screen_char_t's returned, but the ScreenCharArray is otherwise safe to
// mutate. |continuation| is optional and if set will be filled in with the continuation character.
//
// DEPRECATED - Prefer the 2-arg version below since ScreenCharArray carries the continuation char.
- (ScreenCharArray * _Nonnull)wrappedLineAtIndex:(int)lineNum
                                           width:(int)width
                                    continuation:(screen_char_t * _Nullable)continuation;

- (ScreenCharArray * _Nonnull)wrappedLineAtIndex:(int)lineNum
                                           width:(int)width;


- (ScreenCharArray * _Nonnull)rawLineAtWrappedLine:(int)lineNum width:(int)width;

// This is the fast way to get a bunch of lines at once.
- (NSArray<ScreenCharArray *> * _Nonnull)wrappedLinesFromIndex:(int)lineNum
                                                         width:(int)width
                                                         count:(int)count;

// Get the number of buffer lines at a given width.
- (int)numLinesWithWidth:(int)width;

// If the last wrapped line has the cursor, return true and set *x to its horizontal position.
// 0 <= *x <= width (if *x == width then the cursor is actually on the next line).
// Call this just before popAndCopyLastLineInto:width:includesEndOfLine:metadata:continuation.
- (BOOL)getCursorInLastLineWithWidth:(int)width atX:(int * _Nonnull)x;

// Print the raw lines to the console for debugging.
- (void)dump;

// Set up the find context. See FindContext.h for options bit values.
- (void)prepareToSearchFor:(NSString * _Nonnull)substring
                startingAt:(LineBufferPosition * _Nonnull)start
                   options:(FindOptions)options
                      mode:(iTermFindMode)findMode
               withContext:(FindContext * _Nonnull)context;

// Performs a search. Use prepareToSearchFor:startingAt:options:withContext: to initialize
// the FindContext prior to calling this.
- (void)findSubstring:(FindContext * _Nonnull)context stopAt:(LineBufferPosition * _Nonnull)stopAt;

// Returns an array of XYRange values
- (NSArray<XYRange *> * _Nullable)convertPositions:(NSArray<ResultRange *> * _Nonnull)resultRanges
                                        withWidth:(int)width;

- (LineBufferPosition * _Nullable)positionForCoordinate:(VT100GridCoord)coord
                                                  width:(int)width
                                                 offset:(int)offset;

- (VT100GridCoord)coordinateForPosition:(LineBufferPosition * _Nonnull)position
                                  width:(int)width
                           extendsRight:(BOOL)extendsRight
                                     ok:(BOOL * _Nullable)ok;

- (LineBufferPosition *)positionOfFindContext:(FindContext *)context width:(int)width;

- (LineBufferPosition * _Nonnull)firstPosition;
- (LineBufferPosition * _Nonnull)lastPosition;
- (LineBufferPosition * _Nonnull)penultimatePosition;
- (LineBufferPosition * _Nonnull)positionForStartOfLastLine;

// Convert the block,offset in a findcontext into an absolute position.
- (long long)absPositionOfFindContext:(FindContext * _Nonnull)findContext;
// Convert an absolute position into a position.
- (int)positionForAbsPosition:(long long)absPosition;
// Convert a position into an absolute position.
- (long long)absPositionForPosition:(int)pos;

// Set the start location of a find context to an absolute position.
- (void)storeLocationOfAbsPos:(long long)absPos
                    inContext:(FindContext * _Nonnull)context;

- (NSString * _Nonnull)debugString;
- (void)dumpWrappedToWidth:(int)width;
- (NSString * _Nonnull)compactLineDumpWithWidth:(int)width andContinuationMarks:(BOOL)continuationMarks;

- (int)numberOfDroppedBlocks;

// Returns a dictionary with the contents of the line buffer. If it is more than 10k lines @ 80 columns
// then it is truncated. The data is a weak reference and will be invalid if the line buffer is
// changed.
//- (NSDictionary *)dictionary;
- (void)encode:(id<iTermEncoderAdapter> _Nonnull)encoder maxLines:(NSInteger)maxLines;

// Make a copy of the last |minLines| at width |width|. May copy more than |minLines| for speed.
// Makes a copy-on-write instance so this is fairly cheap to do.
- (LineBuffer * _Nonnull)copyWithMinimumLines:(int)minLines atWidth:(int)width;

- (int)numberOfWrappedLinesWithWidth:(int)width;
- (int)numberOfWrappedLinesWithWidth:(int)width upToAbsoluteBlockNumber:(int)absBlock;

- (LineBuffer *)copy;

// Tests only!
- (LineBlock * _Nonnull)testOnlyBlockAtIndex:(int)i;

- (ScreenCharArray * _Nullable)unwrappedLineAtIndex:(int)i;
- (unsigned int)numberOfUnwrappedLines;


@end

// A LineBuffer represents an ordered collection of strings of screen_char_t. Each string forms a
// logical line of text plus color information. Logic is provided for the following major functions:
//   - If the lines are wrapped onto a screen of some width, find the Nth wrapped line
//   - Append a line
//   - If the lines are wrapped onto a screen of some width, remove the last wrapped line
//   - Store and retrieve a cursor position
//   - Store an unlimited or a fixed number of wrapped lines
// The implementation uses an array of small blocks that hold a few kb of unwrapped lines. Each
// block caches some information to speed up repeated lookups with the same screen width.
@interface LineBuffer : NSObject <LineBufferReading>

@property(nonatomic, readwrite) BOOL mayHaveDoubleWidthCharacter;
@property(nonatomic, weak, nullable) id<iTermLineBufferDelegate> delegate;

// Has anything changed? Feel free to reset this to NO as you please.
@property(nonatomic) BOOL dirty;

- (LineBuffer * _Nonnull)initWithBlockSize:(int)bs;
- (LineBuffer * _Nullable)initWithDictionary:(NSDictionary * _Nonnull)dictionary;

// Call this immediately after init. Otherwise the buffer will hold unlimited lines (until you
// run out of memory).
- (void)setMaxLines:(int)maxLines;
- (int)maxLines;

// Add a line to the buffer. Set partial to true if there's more coming for this line:
// that is to say, this buffer contains only a prefix or infix of the entire line.
//
// NOTE: call dropExcessLinesWithWidth after this if you want to limit the buffer to max_lines.
- (void)appendLine:(const screen_char_t * _Nonnull)buffer
            length:(int)length
           partial:(BOOL)partial
             width:(int)width
          metadata:(iTermImmutableMetadata)metadata
      continuation:(screen_char_t)continuation;

- (void)appendScreenCharArray:(ScreenCharArray *)sca
                        width:(int)width;

- (int)appendContentsOfLineBuffer:(LineBuffer * _Nonnull)other width:(int)width includingCursor:(BOOL)cursor;

// If more lines are in the buffer than max_lines, call this function. It will adjust the count
// of excess lines and try to free the first block(s) if they are unused. Because this could happen
// after any call to appendLines, you should always call this after appendLines.
//
// Returns the number of lines in the buffer that overflowed max_lines.
//
// NOTE: This invalidates the cursor position.
- (int)dropExcessLinesWithWidth:(int)width;

// Copy up to width chars from the last line into *ptr. The last line will be removed or
// truncated from the buffer. Sets *includesEndOfLine to true if this line should have a
// continuation marker.
- (BOOL)popAndCopyLastLineInto:(screen_char_t * _Nonnull)ptr
                         width:(int)width
             includesEndOfLine:(int *_Nonnull)includesEndOfLine
                      metadata:(out iTermImmutableMetadata * _Nullable)metadataPtr
                  continuation:(screen_char_t * _Nullable)continuationPtr;

// Note that the resulting line may be *smaller* than width. Use -paddedToLength:eligibleForDWC:
// if you need to go all Procrustes on it.
- (ScreenCharArray * _Nullable)popLastLineWithWidth:(int)width;

// Removes the last wrapped lines.
- (void)removeLastWrappedLines:(int)numberOfLinesToRemove
                         width:(int)width;

// Remove the last raw (unwrapped) line.
- (void)removeLastRawLine;

// Save the cursor position. Call this just before appending the line the cursor is in.
// x gives the offset from the start of the next line appended. The cursor position is
// invalidated if dropExcessLinesWithWidth is called.
- (void)setCursor:(int)x;

// Append text in reverse video to the end of the line buffer.
- (void)appendMessage:(NSString * _Nonnull)message;

- (void)beginResizing;
- (void)endResizing;

- (void)setPartial:(BOOL)partial;

// If the last block is non-empty, make a new block to avoid having to copy it on write.
- (void)seal;

- (void)mergeFrom:(LineBuffer *)source;
- (void)forceMergeFrom:(LineBuffer *)source;

- (void)performBlockWithTemporaryChanges:(void (^ NS_NOESCAPE)(void))block;

- (void)clear;

@end

NS_ASSUME_NONNULL_END

