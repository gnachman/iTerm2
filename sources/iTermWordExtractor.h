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
@class iTermLocatedString;

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
- (int)wordExtractorNumberOfLines;

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

/// Extract text around a coordinate for regex matching.
/// - Parameters:
///   - coord: The coordinate to center the extraction around
///   - radius: Number of characters to extract before and after the coordinate
///   - targetOffset: On return, contains the offset in the returned string where the coordinate is located
///   - coords: On return, contains VT100GridCoord values (wrapped in NSValue) for each character in the returned string
/// - Returns: The extracted text
- (NSString *)textAroundCoord:(VT100GridCoord)coord
                       radius:(int)radius
                 targetOffset:(int *)targetOffset
                       coords:(NSMutableArray<NSValue *> *)coords;

/// Extract a located string for the entire wrapped line containing a coordinate.
/// This extends to the start and end of the logical line (respecting soft wraps),
/// which provides more stable regex matching than a fixed radius.
/// Returns an iTermLocatedString with 1:1 mapping between UTF-16 code units and grid coordinates.
/// - Parameters:
///   - coord: The coordinate within the wrapped line
///   - targetOffset: On return, contains the offset in the returned string where the coordinate is located
/// - Returns: A located string for the entire wrapped line
- (iTermLocatedString *)locatedStringForWrappedLineEncompassing:(VT100GridCoord)coord
                                                   targetOffset:(int *)targetOffset;
@end

// iTermWordExtractor class is now defined in Swift (iTermWordExtractor.swift)
// Forward declaration for ObjC compatibility
@class iTermWordExtractor;

NS_ASSUME_NONNULL_END
