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
        ScreenCharArray *sca = [self screenCharArrayForRawLine:i];
        iTermBidiDisplayInfo *expected = [[iTermBidiDisplayInfo alloc] initUnpaddedWithScreenCharArray:sca];
        ITAssertWithMessage([actual isEqual:expected], @"actual=%@ expected=%@", actual, expected);
    }
}

- (void)reallyReloadBidiInfo {
    for (int i = _firstEntry; i < cll_entries; i++) {
        [self updateBidiInfoForRawLine:i];
    }
}

- (ScreenCharArray *)screenCharArrayForRawLine:(int)i {
    return [self screenCharArrayForRange:NSMakeRange([self _lineRawOffset:i],
                                                     [self _lineLength:i])];
}

- (void)updateBidiInfoForRawLine:(int)i {
    const LineBlockMetadata *md = [_metadataArray metadataAtIndex:i];
    iTermBidiDisplayInfo *bidiInfo = nil;

    id<iTermString> string = nil;
    if (md->lineMetadata.rtlFound) {
        string = [_rope substringWithRange:NSMakeRange([self _lineRawOffset:i],
                                                       [self _lineLength:i])];
        const NSRange fullRange = NSMakeRange(0, string.cellCount);
        iTermDeltaString *deltaString = [string deltaStringWithRange:fullRange];
        bidiInfo = [[iTermBidiDisplayInfo alloc] initWithDeltaString:deltaString
                                                           usedCount:[string usedLengthWithRange:fullRange]];
        [_rope setRTLIndexes:[bidiInfo rtlIndexes] ?: [NSIndexSet indexSet]];
    } else if (md->bidi_display_info == nil) {
        // It's already nil so return to avoid making a CoW of _metadataArray for nothing.
        return;
    }

    DLog(@"Block recomputed bidi for raw line %d: %@. string=%@", i, bidiInfo, string);
    [_metadataArray setBidiInfo:bidiInfo
                         atLine:i
                       rtlFound:bidiInfo != nil];
}

- (iTermBidiDisplayInfo * _Nullable)subBidiInfo:(iTermBidiDisplayInfo *)bidi
                                          range:(NSRange)range
                                          width:(int)width {
    return [bidi subInfoInRange:range paddedToWidth:width];
}

- (int)lengthOfLineString:(id<iTermLineStringReading>)lineString {
    return lineString.content.cellCount;
}

- (screen_char_t)continuationOfLineString:(id<iTermLineStringReading>)lineString {
    return lineString.continuation;
}

- (iTermImmutableMetadata)metadataOfLineString:(id<iTermLineStringReading>)lineString {
    return lineString.externalImmutableMetadata;
}

- (id<iTermLineStringReading>)lineStringWithRange:(NSRange)range
                                     continuation:(screen_char_t)continuation
                                              eol:(unichar)eol
                                         metadata:(iTermImmutableMetadata)metadata
                                             bidi:(iTermBidiDisplayInfo *)bidi {
    screen_char_t temp = continuation;
    temp.code = eol;
    iTermSubString *content = [[iTermSubString alloc] initWithBaseString:_rope
                                                                   range:range];

    const iTermLineStringMetadata lmd = {
        .timestamp = metadata.timestamp,
        .rtlFound = metadata.rtlFound
    };
    return [[iTermLineString alloc] initWithContent:content
                                                eol:eol
                                       continuation:temp
                                           metadata:lmd
                                               bidi:bidi
                                              dirty:NO];
}

- (screen_char_t)characterAtIndex:(int)i {
    return [_rope characterAt:i];
}

- (ScreenCharArray *)screenCharArrayForLineString:(id<iTermLineStringReading>)lineString {
    return [lineString screenCharArrayWithBidi:lineString.bidi];
}

- (iTermBidiDisplayInfo *)bidiOfLineString:(id<iTermLineStringReading>)lineString {
    return lineString.bidi;
}

+ (id<iTermMutableStringProtocol>)createRope {
    return [[iTermMutableRope alloc] init];
}

- (id<iTermMutableStringProtocol>)copyOfRope:(id<iTermMutableStringProtocol>)rope {
    return [rope mutableClone];
}

+ (id<iTermMutableStringProtocol>)ropeFromData:(NSData *)data {
    iTermMutableRope *rope = [[iTermMutableRope alloc] init];
    iTermLegacyStyleString *string = [[iTermLegacyStyleString alloc] initWithChars:(const screen_char_t *)data.bytes
                                                                             count:data.length / sizeof(screen_char_t)
                                                                           eaIndex:nil];
    [rope appendString:string];
    return rope;
}

- (ScreenCharArray *)expensiveFullScreenCharArrayOfRope:(id<iTermMutableStringProtocol>)rope {
    return [rope screenCharArray];
}

- (NSString *)shortDescriptionOfRope:(id<iTermMutableStringProtocol>)rope {
    id<iTermString> substring = [rope substringWithRange:NSMakeRange(0, MIN(rope.cellCount, 40))];
    ScreenCharArray *sca = [substring screenCharArray];
    return [sca description];
}

- (NSInteger)lengthOfRope:(id<iTermMutableStringProtocol>)rope {
    return [rope cellCount];
}

- (BOOL)rope:(id<iTermMutableStringProtocol>)rope
isEqualToRope:(id<iTermMutableStringProtocol>)other {
    return [rope isEqualToString:other];
}

- (NSString *)debugStringForRawLine:(int)i {
    const BOOL iscont = (i == cll_entries - 1) && is_partial;
    int prev = i > 0 ? cumulative_line_lengths[i - 1] : 0;
    int ci = MAX(0, cumulative_line_lengths[i] - 1);
    id<iTermLineStringReading> string = [self lineStringWithRange:NSMakeRange(_startOffset + prev - self.bufferStartOffset,
                                                                              cumulative_line_lengths[i] - prev)
                                                     continuation:[self characterAtIndex:ci]
                                                              eol:iscont ? EOL_SOFT : EOL_HARD
                                                         metadata:[_metadataArray immutableLineMetadataAtIndex:i]
                                                             bidi:nil];
    return [string description];
}

- (void)appendString:(id<iTermLineStringReading>)string {
    [_rope appendString:string.content];
}

- (ScreenCharArray *)screenCharArrayForRange:(NSRange)range {
    return [[_rope substringWithRange:range] screenCharArray];
}

- (void)eraseRTLStatusInRope {
    [_rope resetRTLStatus];
}

- (iTermDeltaString *)deltaStringFromRopeForRange:(NSRange)range {
    return [_rope deltaStringWithRange:range];
}

- (NSString *)deltaString:(iTermDeltaString *)deltaString
            getCodePoints:(const unichar **)codePointsPtr
                   deltas:(const int **)deltasPtr {
    *codePointsPtr = deltaString.backingStore;
    *deltasPtr = deltaString.deltas;
    return deltaString.unsafeString;
}

- (NSData *)ropeData {
    ScreenCharArray *sca = _rope.screenCharArray;
    [sca makeSafe];
    return sca.data;
}

- (void)replaceRopeWithCopy {
    _rope = [_rope mutableClone];
}

- (NSIndexSet *)doubleWidthIndexSet {
    return [_rope doubleWidthIndexesWithRange:NSMakeRange(0, _rope.cellCount) rebaseTo:0];
}

- (void)deleteFromEndOfRope:(int)count {
    [_rope deleteFromEnd:count];
}

- (void)setExternalAttributes:(id<iTermExternalAttributeIndexReading>)eaIndex
                  sourceRange:(NSRange)sourceRange
        destinationStartIndex:(NSInteger)destinationStartIndex {
    [_rope setExternalAttributes:eaIndex
                     sourceRange:sourceRange
           destinationStartIndex:destinationStartIndex];
}

@end
