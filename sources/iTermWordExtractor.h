//
//  iTermWordExtractor.h
//  iTerm2
//
//  Created by George Nachman on 11/11/24.
//

#import <Foundation/Foundation.h>

#import "ScreenChar.h"
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermExternalAttribute;

typedef NS_ENUM(NSInteger, iTermTextExtractorClass) {
    // Any kind of white space.
    kTextExtractorClassWhitespace,

    // Characters that belong to a word.
    kTextExtractorClassWord,

    // Unset character
    kTextExtractorClassNull,

    // DWC_RIGHT or DWC_SKIP
    kTextExtractorClassDoubleWidthPlaceholder,

    // Non-alphanumeric, non-whitespace, non-word, not double-width filler.
    // Miscellaneous symbols, etc.
    kTextExtractorClassOther
};

@protocol iTermWordExtractorDataSource<NSObject>
- (VT100GridRange)wordExtractorLogicalWindow;
- (NSString *)stringForCharacter:(screen_char_t)theChar;
- (screen_char_t)characterAt:(VT100GridCoord)coord;
- (VT100GridCoord)predecessorOfCoord:(VT100GridCoord)coord;
- (VT100GridCoord)successorOfCoord:(VT100GridCoord)coord;
- (VT100GridWindowedRange)windowedRangeWithRange:(VT100GridCoordRange)range;
- (int)xLimit;
- (int)wordExtractorWidth;
- (int)wordExtractroNumberOfLines;

- (void)enumerateCharsInRange:(VT100GridWindowedRange)range
                  supportBidi:(BOOL)logicalOrder
                    charBlock:(BOOL (^NS_NOESCAPE _Nullable)(const screen_char_t *currentLine,
                                                             screen_char_t theChar,
                                                             iTermExternalAttribute *,
                                                             VT100GridCoord logicalCoord,
                                                             VT100GridCoord visualCoord))charBlock
                     eolBlock:(BOOL (^NS_NOESCAPE _Nullable)(unichar code, int numPrecedingNulls, int line))eolBlock;

- (void)enumerateInReverseCharsInRange:(VT100GridWindowedRange)range
                             charBlock:(BOOL (^NS_NOESCAPE _Nullable)(screen_char_t theChar,
                                                                      VT100GridCoord logicalCoord,
                                                                      VT100GridCoord visualCoord))charBlock
                              eolBlock:(BOOL (^NS_NOESCAPE _Nullable)(unichar code, int numPrecedingNulls, int line))eolBlock;

- (BOOL)shouldStopEnumeratingWithCode:(unichar)code
                             numNulls:(int)numNulls
              windowTouchesLeftMargin:(BOOL)windowTouchesLeftMargin
             windowTouchesRightMargin:(BOOL)windowTouchesRightMargin
                     ignoringNewlines:(BOOL)ignoringNewlines;

- (void)performBlockWithLineCache:(void (^NS_NOESCAPE)(void))block;

- (NSInteger)indexInSortedArray:(NSArray<NSNumber *> *)indexes
     withValueLessThanOrEqualTo:(NSInteger)maximumValue
          searchingBackwardFrom:(NSInteger)start;

- (NSInteger)indexInSortedArray:(NSArray<NSNumber *> *)indexes
      withValueGreaterOrEqualTo:(NSInteger)minimumValue
           searchingForwardFrom:(NSInteger)startIndex;

- (BOOL)haveDoubleWidthExtensionAt:(VT100GridCoord)coord;
@end

@interface iTermWordExtractor: NSObject
@property (nonatomic) VT100GridCoord location;
@property (nonatomic) NSInteger maximumLength;
@property (nonatomic) BOOL big;
@property (nonatomic, weak) id<iTermWordExtractorDataSource> dataSource;

- (instancetype)initWithLocation:(VT100GridCoord)location
                   maximumLength:(NSInteger)maximumLength
                             big:(BOOL)big NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (VT100GridWindowedRange)windowedRange;
- (NSString * _Nullable)fastString;
- (VT100GridWindowedRange)windowedRangeForBigWord;

@end

NS_ASSUME_NONNULL_END
