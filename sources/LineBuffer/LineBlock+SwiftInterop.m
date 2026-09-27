//
//  LineBlock+SwiftInterop.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/29/24.
//

#import "LineBlock+SwiftInterop.h"
#import "LineBlock+Private.h"
#import "iTermCharacterBuffer.h"
#import "iTerm2SharedARC-Swift.h"
#import "ScreenCharArray.h"

@implementation LineBlock(SwiftInterop)

- (NSData *)decompressedDataFromV4Data:(NSData *)v4data {
    iTermCompressibleCharacterBuffer *cb = [[iTermCompressibleCharacterBuffer alloc] initWithEncodedData:v4data];
    if (!cb) {
        return nil;
    }
    screen_char_t *p = cb.mutablePointer;
    return [NSData dataWithBytes:p length:cb.size * sizeof(screen_char_t)];
}

- (void)sanityCheckBidiDisplayInfoForRawLine:(int)i {
    const LineBlockMetadata *metadata = [_metadataArray metadataAtIndex:i];
    iTermBidiDisplayInfo *actual = metadata->bidi_display_info;
    if (actual) {
        MutableScreenCharArray *msca = [[MutableScreenCharArray alloc] initWithLine:_characterBuffer.pointer + [self _lineRawOffset:i]
                                                                             length:[self _lineLength:i]
                                                                       continuation:metadata->continuation];
        iTermBidiDisplayInfo *expected = [[iTermBidiDisplayInfo alloc] initUnpaddedWithScreenCharArray:msca];
        ITAssertWithMessage([actual isEqual:expected], @"actual=%@ expected=%@", actual, expected);
    }
}

- (void)reallyReloadBidiInfo {
    for (int i = _firstEntry; i < cll_entries; i++) {
        [self updateBidiInfoForRawLine:i];
    }
}

- (BOOL)anyLineNeedsBidiReload {
    for (int i = _firstEntry; i < cll_entries; i++) {
        const LineBlockMetadata *md = [_metadataArray metadataAtIndex:i];
        if (md->lineMetadata.rtlFound || md->bidi_display_info != nil) {
            return YES;
        }
    }
    return NO;
}

- (MutableScreenCharArray *)mutableScreenCharArrayForRawLine:(int)i {
    const LineBlockMetadata *md = [_metadataArray metadataAtIndex:i];
    return [[MutableScreenCharArray alloc] initWithLine:_characterBuffer.pointer + [self _lineRawOffset:i]
                                                 length:[self _lineLength:i]
                                           continuation:md->continuation];
}

- (void)updateBidiInfoForRawLine:(int)i {
    const LineBlockMetadata *md = [_metadataArray metadataAtIndex:i];
    iTermBidiDisplayInfo *bidiInfo = nil;

    MutableScreenCharArray *msca = nil;
    if (md->lineMetadata.rtlFound) {
        msca = [self mutableScreenCharArrayForRawLine:i];
        bidiInfo = [[iTermBidiDisplayInfo alloc] initUnpaddedWithScreenCharArray:msca];
        if (bidiInfo) {
            [iTermBidiDisplayInfo annotateWithBidiInfo:bidiInfo msca:msca];
        } else {
            const int length = msca.length;
            screen_char_t *line = msca.mutableLine;
            for (int i = 0; i < length; i++) {
                line[i].rtlStatus = RTLStatusLTR;
            }
        }
    } else if (md->bidi_display_info == nil) {
        // It's already nil so return to avoid making a CoW of _metadataArray for nothing.
        return;
    }

    DLog(@"Block recomputed bidi for raw line %d: %@. string=%@", i, bidiInfo, [msca stringValue]);
    [_metadataArray setBidiInfo:bidiInfo
                         atLine:i
                       rtlFound:bidiInfo != nil];
}

- (iTermBidiDisplayInfo *)_bidiInfoForLineNumber:(int)lineNum width:(int)width {
    int mutableLineNum = lineNum;
    const LineBlockLocation location = [self locationOfRawLineForWidth:width lineNum:&mutableLineNum];
    int length = 0;
    int eof = 0;
    int lineOffset = 0;
    iTermBidiDisplayInfo *bidiInfo = nil;
    [self _wrappedLineWithWrapWidth:width
                           location:location
                            lineNum:&mutableLineNum
                         lineLength:&length
                  includesEndOfLine:&eof
                            yOffset:NULL
                       continuation:NULL
               isStartOfWrappedLine:NULL
                           metadata:NULL
                           bidiInfo:&bidiInfo
                         lineOffset:&lineOffset];

    // _wrappedLineWithWrapWidth already extracted this wrapped display row's
    // slice of the raw line's bidi (its range is [offset, offset+width), padded
    // to width). Splitting again by lineOffset (== that same offset) double-
    // applies the offset: for the first wrapped row offset is 0 so it is a
    // harmless no-op, but for every continuation row offset == width, so it asks
    // for [width, …) of a bidi that only has `width` cells and gets nothing;
    // leaving the row with no reorder map, so a right-to-left wrapped line drawn
    // from scrollback renders its continuation rows unreordered (scrambled).
    return bidiInfo;
}


- (iTermBidiDisplayInfo * _Nullable)subBidiInfo:(iTermBidiDisplayInfo *)bidi
                                          range:(NSRange)range
                                          width:(int)width {
    return [bidi subInfoInRange:range paddedToWidth:width];
}

@end
