//
//  iTermCoreTextLineRenderingHelper.m
//  iTerm2
//
//  Created by George Nachman on 11/1/24.
//

#import "iTermCoreTextLineRenderingHelper.h"

#import "iTerm2SharedARC-Swift.h"
#import "NSStringITerm.h"

@implementation iTermCoreTextLineRenderingHelper {
    CTLineRef _line;
    NSString *_string;
    NSData *_drawInCellIndex;
}

- (instancetype)initWithLine:(CTLineRef)line
                      string:(nonnull NSString *)string
             drawInCellIndex:(NSData *)drawInCellIndex {
    self = [super init];
    if (self) {
        _line = line;
        CFRetain(_line);
        _string = [string copy];
        _drawInCellIndex = drawInCellIndex;
    }
    return self;
}

- (void)dealloc {
    CFRelease(_line);
}

- (void)enumerateRuns:(void (^ NS_NOESCAPE)(size_t i,
                                            CTRunRef run,
                                            size_t length,
                                            const CGGlyph *glyphs,
                                            CGPoint *positions,
                                            const CGSize *advances,
                                            const CFIndex *glyphIndexToCharacterIndex,
                                            BOOL *stop))closure {
    CFArrayRef runs = CTLineGetGlyphRuns(_line);
    for (CFIndex j = 0; j < CFArrayGetCount(runs); j++) {
        CTRunRef run = CFArrayGetValueAtIndex(runs, j);
        size_t length = CTRunGetGlyphCount(run);
        const CGGlyph *buffer = CTRunGetGlyphsPtr(run);
        if (!buffer) {
            NSMutableData *tempBuffer =
            [[NSMutableData alloc] initWithLength:sizeof(CGGlyph) * length];
            CTRunGetGlyphs(run, CFRangeMake(0, length), (CGGlyph *)tempBuffer.mutableBytes);
            buffer = tempBuffer.mutableBytes;
        }

        NSMutableData *positionsBuffer =
        [[NSMutableData alloc] initWithLength:sizeof(CGPoint) * length];
        CTRunGetPositions(run, CFRangeMake(0, length), (CGPoint *)positionsBuffer.mutableBytes);
        CGPoint *positions = positionsBuffer.mutableBytes;

        NSMutableData *advancesBuffer =
        [[NSMutableData alloc] initWithLength:sizeof(CGSize) * length];
        CTRunGetAdvances(run, CFRangeMake(0, length), advancesBuffer.mutableBytes);
        CGSize *advances = advancesBuffer.mutableBytes;

        const CFIndex *glyphIndexToCharacterIndex = CTRunGetStringIndicesPtr(run);
        if (!glyphIndexToCharacterIndex) {
            NSMutableData *tempBuffer =
            [[NSMutableData alloc] initWithLength:sizeof(CFIndex) * length];
            CTRunGetStringIndices(run, CFRangeMake(0, length), (CFIndex *)tempBuffer.mutableBytes);
            glyphIndexToCharacterIndex = (CFIndex *)tempBuffer.mutableBytes;
        }

        BOOL stop = NO;
        closure(j, run, length, buffer, positions, advances, glyphIndexToCharacterIndex, &stop);
        if (stop) {
            break;
        }
    }
}

- (void)enumerateGridAlignedRunsWithColumnPositions:(const CGFloat *)xOriginsForCharacters
                                        alignToZero:(BOOL)alignToZero
                                            closure:(void (^ NS_NOESCAPE)(CTRunRef run,
                                                                          CTFontRef font,
                                                                          const CGGlyph *glyphs,
                                                                          const NSPoint *positions,
                                                                          const CFIndex *glyphIndexToCharacterIndex,
                                                                          size_t length,
                                                                          BOOL *stop))closure {
    // The x origin of the column for the current cell. Initialize to -1 to ensure it gets set on
    // the first pass through the position-adjusting loop.
    __block CGFloat lastMaxExtent = 0;
    [self enumerateRuns:^(size_t j,
                          CTRunRef run,
                          size_t length,
                          const CGGlyph * _Nonnull glyphs,
                          CGPoint * _Nonnull positions,
                          const CGSize * _Nonnull advances,
                          const CFIndex * _Nonnull glyphIndexToCharacterIndex,
                          BOOL * _Nonnull stop) {
        const BOOL verbose = self->_verbose;
        if (verbose) {
            NSLog(@"Begin run %@", @(j));
        }
        [self alignGlyphsToGridWithGlyphIndex:glyphIndexToCharacterIndex
                                       length:length
                        xOriginsForCharacters:xOriginsForCharacters
                                  alignToZero:alignToZero
                                    positions:positions
                                     advances:advances
                                lastMaxExtent:&lastMaxExtent
                  characterIndexToDisplayCell:(const int *)_drawInCellIndex.bytes];
        CTFontRef runFont = CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName);
        closure(run, runFont, glyphs, positions, glyphIndexToCharacterIndex, length, stop);
    }];
}

- (NSIndexSet *)baseCharacterIndexes {
    NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];
    [_string enumerateComposedCharacters:^(NSRange range, unichar simple, NSString *complexString, BOOL *stop) {
        [indexSet addIndex:range.location];
    }];
    return indexSet;
}

// Transform positions to put each grapheme cluster in its proper column.
// positions[glyphIndex].x needs to be transformed to subtract whatever horizontal advance
// was present earlier in the string.
- (void)legacy_alignGlyphsToGridWithGlyphIndex:(const CFIndex *)glyphIndexToCharacterIndex
                                 length:(size_t)length
                  xOriginsForCharacters:(const CGFloat *)xOriginsForCharacters
                            alignToZero:(BOOL)alignToZero
                              positions:(CGPoint *)positions
                     advanceAccumulator:(CGFloat *)advanceAccumulatorPtr
                               advances:(const CGSize *)advances
                                    rtl:(BOOL)rtl
                                verbose:(BOOL)verbose {
    CFIndex previousCharacterIndex = -1;
    CGFloat xOriginForCurrentColumn = -1;

    // endOfLastCharacter gives the x coordinate where the previous character ended (its last glyph's origin plus its last glyph's advance).
    CGFloat startOfThisCharacter = 0;

    for (size_t glyphIndex = 0; glyphIndex < length; glyphIndex++) {
        // `characterIndex` indexes into the attributed string.
        const CFIndex characterIndex = glyphIndexToCharacterIndex[glyphIndex];

        // Where this character's column begins
        const CGFloat xOriginForThisCharacter = xOriginsForCharacters[characterIndex] - xOriginsForCharacters[0];

        if (verbose) {
            NSLog(@"  begin glyph %@", @(glyphIndex));
        }

        if (characterIndex != previousCharacterIndex &&
            xOriginForThisCharacter != xOriginForCurrentColumn) {
            // Have advanced to the next character or column.
            startOfThisCharacter = *advanceAccumulatorPtr;
            xOriginForCurrentColumn = xOriginForThisCharacter;
            if (verbose) {
                NSLog(@"  This glyph begins a new character or column. xOffset<-%@, xOriginForCurrentColumn<-%@", @(startOfThisCharacter), @(xOriginForCurrentColumn));
            }
        }
        *advanceAccumulatorPtr = advances[glyphIndex].width + positions[glyphIndex].x;
        if (verbose) {
            NSLog(@"  advance=%@, position=%@. advanceAccumulator<-%@", @(advances[glyphIndex].width), @(positions[glyphIndex].x), @(*advanceAccumulatorPtr));
        }
        // The existing value in `positions` is where Core Text would place this glyph. That is based
        // on the properties of the font itself, which is typically variable width.
        // We subtract `startOfThisCharacter`, which is where the character would nominally begin
        // based on the "advance" of the preceding character. Then add in the x origin that we want (or zero if we just want to know where glyphs fall within their cell).
        positions[glyphIndex].x += (alignToZero ? 0 : xOriginForCurrentColumn) - startOfThisCharacter;
        if (verbose) {
            NSLog(@"  position<-%@", @(positions[glyphIndex].x));
        }
    }
}

@end
