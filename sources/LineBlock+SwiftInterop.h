//
//  LineBlock+SwiftInterop.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/29/24.
//

#import <Foundation/Foundation.h>
#import "LineBlock.h"

@class iTermBidiDisplayInfo;
@protocol iTermLineStringReading;
@class iTermMutableLineString;
@protocol iTermMutableStringProtocol;
@class iTermDeltaString;
@class iTermMutableRope;

NS_ASSUME_NONNULL_BEGIN

@interface LineBlock(SwiftInterop)

+ (iTermMutableRope *)createRope;
+ (iTermMutableRope *)ropeFromData:(NSData *)data usedLength:(int)usedLength;
+ (iTermMutableRope *)ropeFromVersion5Data:(NSData *)data;
- (NSData * _Nullable)decompressedDataFromV4Data:(NSData *)v4data;
- (void)sanityCheckBidiDisplayInfoForRawLine:(int)i;
- (void)reallyReloadBidiInfo;
- (iTermBidiDisplayInfo * _Nullable)subBidiInfo:(iTermBidiDisplayInfo *)bidi
                                          range:(NSRange)range
                                          width:(int)width;
- (int)lengthOfLineString:(id<iTermLineStringReading>)lineString;
- (screen_char_t)continuationOfLineString:(id<iTermLineStringReading>)lineString;
- (iTermImmutableMetadata)metadataOfLineString:(id<iTermLineStringReading>)lineString;
- (iTermLineStringMetadata)lineStringMetadataOfLineString:(id<iTermLineStringReading>)lineString;

- (id<iTermLineStringReading>)lineStringWithRange:(NSRange)range
                                     continuation:(screen_char_t)continuation
                                              eol:(unichar)eol
                                         metadata:(iTermLineStringMetadata)metadata
                                             bidi:(iTermBidiDisplayInfo * _Nullable)bidi;
- (screen_char_t)characterAtIndex:(int)i;
- (ScreenCharArray *)screenCharArrayForLineString:(id<iTermLineStringReading>)lineString;
- (iTermBidiDisplayInfo *)bidiOfLineString:(id<iTermLineStringReading>)lineString;
- (iTermMutableRope *)copyOfRope:(iTermMutableRope *)rope;
- (ScreenCharArray *)expensiveFullScreenCharArrayOfRope:(iTermMutableRope *)rope;
- (NSString *)shortDescriptionOfRope:(iTermMutableRope *)rope;
- (NSInteger)lengthOfRope:(iTermMutableRope *)rope;
- (BOOL)rope:(iTermMutableRope *)rope isEqualToRope:(iTermMutableRope *)other;
- (NSString *)debugStringForRawLine:(int)i;
- (void)appendString:(id<iTermLineStringReading>)string;
- (ScreenCharArray *)screenCharArrayForRange:(NSRange)range;
- (void)eraseRTLStatusInRope;
- (iTermDeltaString *)deltaStringFromRopeForRange:(NSRange)range;
- (NSString *)deltaString:(iTermDeltaString *)deltaString
            getCodePoints:(const unichar **)codePointsPtr
                   deltas:(const int **)deltasPtr;
- (NSData *)ropeData;
- (void)replaceRopeWithCopy;
- (NSIndexSet *)doubleWidthIndexSet;
- (void)deleteFromEndOfRope:(int)count;
- (void)setExternalAttributes:(id<iTermExternalAttributeIndexReading>)eaIndex
                  sourceRange:(NSRange)sourceRange
        destinationStartIndex:(NSInteger)destinationStartIndex;
- (void)appendExternalAttributesFrom:(id<iTermLineStringReading>)source;
- (void)replaceRopeWithEmptyRope;

@end

NS_ASSUME_NONNULL_END
