//
//  VT100LineInfo.h
//  iTerm
//
//  Created by George Nachman on 11/17/13.
//
//

#import <Foundation/Foundation.h>
#import "DVRBuffer.h"
#import "ScreenChar.h"
#import "VT100GridTypes.h"
#import "iTermMetadata.h"

// Reserves a contiguous block of `count` line-content generations from the global
// sequence and returns its base, so a caller can hand out `count` distinct,
// never-reused identities in O(1). Used for the all-dirty grid case.
int64_t VT100LineInfoAllocateGenerationBlock(int64_t count);

@protocol VT100LineInfoReading<NSObject>
@property(nonatomic, readonly) iTermImmutableMetadata immutableMetadata;

// Globally-unique identifier of this line's current content. Advances whenever
// the line is marked dirty. Equal generations imply equal content.
- (int64_t)generation;
- (BOOL)isDirtyAtOffset:(int)x;
- (BOOL)anyCharIsDirty;
- (VT100GridRange)dirtyRange;
- (NSIndexSet *)dirtyIndexes;
- (NSArray *)encodedMetadata;
@end

@interface VT100LineInfo : NSObject <NSCopying, DVREncodable, VT100LineInfoReading>

// Prefer to use this class's APIs to change metadata. Assignment requires reasoning about manual memory management.
@property(nonatomic) iTermMetadata metadata;

- (instancetype)initWithWidth:(int)width;
// Does nothing if now=0. This was super-hot when profiling spam.cc so make it direct. Good luck future me.
- (void)setDirty:(BOOL)dirty inRange:(VT100GridRange)range updateTimestampTo:(NSTimeInterval)now __attribute__((objc_direct));
// Mirror another line's content generation onto this one (used when copying a
// line's content between grids so the destination reports the same identity).
- (void)setGeneration:(int64_t)generation;
// Advance to a fresh globally-unique generation, for content mutations (e.g.
// bidi) that don't go through setDirty:.
- (void)advanceGeneration;
- (BOOL)isDirtyAtOffset:(int)x;
- (BOOL)anyCharIsDirty;
- (VT100GridRange)dirtyRange;
- (NSIndexSet *)dirtyIndexes;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)setRTLFound:(BOOL)rtlFound;
- (void)decodeMetadataArray:(NSArray *)array;
- (void)resetMetadata;
- (NSArray *)encodedMetadata;
- (iTermExternalAttributeIndex *)externalAttributesCreatingIfNeeded:(BOOL)create;
- (void)setExternalAttributeIndex:(iTermExternalAttributeIndex *)eaIndex;
- (void)setMetadataFromImmutable:(iTermImmutableMetadata)metadata;

@end
