//
//  ScreenCharArray.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/18/21.
//

#import <Foundation/Foundation.h>
#import "ScreenChar.h"
#import "iTermMetadata.h"

@class iTermBidiDisplayInfo;

NS_ASSUME_NONNULL_BEGIN

// Typically used to store a single screen line.
@interface ScreenCharArray : NSObject<NSMutableCopying>

@property (nonatomic, readonly) const screen_char_t *line;
@property (nonatomic) int length;
@property (nonatomic, readonly) int eol;  // EOL_SOFT, EOL_HARD, or EOL_DWC
@property (nonatomic, readonly) screen_char_t continuation;
@property (nonatomic, readonly) iTermImmutableMetadata metadata;
@property (nonatomic, readonly) NSDictionary *dictionaryValue;
@property (nonatomic, readonly) NSString *stringValue;
@property (nonatomic, readonly) NSString *stringValueIncludingNewline;
@property (nonatomic, readonly) NSString *debugStringValue;
@property (nonatomic, readonly, nullable) iTermBidiDisplayInfo *bidiInfo;
@property (nonatomic, readonly, nullable) iTermExternalAttributeIndex *eaIndex;

@property (nonatomic, readonly) NSInteger lengthExcludingTrailingWhitespaceAndNulls;

+ (instancetype)emptyLineOfLength:(int)length;

- (instancetype)initWithLine:(const screen_char_t *)line
                      length:(int)length
                continuation:(screen_char_t)continuation;

- (instancetype)initWithCopyOfLine:(const screen_char_t *)line
                            length:(int)length
                      continuation:(screen_char_t)continuation;

- (instancetype)initWithCopyOfLine:(const screen_char_t *)line
                            length:(int)length
                      continuation:(screen_char_t)continuation
                          bidiInfo:(iTermBidiDisplayInfo * _Nullable)bidiInfo;

- (instancetype)initWithLine:(const screen_char_t *)line
                      length:(int)length
                    metadata:(iTermImmutableMetadata)metadata
                continuation:(screen_char_t)continuation;

- (instancetype)initWithLine:(const screen_char_t *)line
                      length:(int)length
                    metadata:(iTermImmutableMetadata)metadata
                continuation:(screen_char_t)continuation
                    bidiInfo:(iTermBidiDisplayInfo * _Nullable)bidiInfo;

- (instancetype)initWithData:(NSData *)data
                    metadata:(iTermImmutableMetadata)metadata
                continuation:(screen_char_t)continuation;

- (instancetype)initWithLine:(const screen_char_t *)line
                      length:(int)length
                    metadata:(iTermImmutableMetadata)metadata
                continuation:(screen_char_t)continuation
               freeOnRelease:(BOOL)freeOnRelease;

// This is intended for swift so we can avoid the void* hijynx of iTermImmutableMetadata.
- (instancetype)initWithLine:(const screen_char_t *)line
                      length:(int)length
                continuation:(screen_char_t)continuation
                        date:(NSDate *)date
          externalAttributes:(iTermExternalAttributeIndex * _Nullable)eaIndex
                    rtlFound:(BOOL)rtlFound
                    bidiInfo:(iTermBidiDisplayInfo * _Nullable)bidiInfo;

- (instancetype)initWithDictionary:(NSDictionary *)dictionary;

// It only makes sense to use this when freeOnRelease=YES.
// start of malloced memory      start of line to expose
// [index 0] [index 1] [index 2] [index 3]
//
// line = &[index 0]
// offset = 3
// length = 1
- (instancetype)initWithLine:(const screen_char_t *)line  // pointer to 1st byte of malloced memory
                      offset:(size_t)offset  // self.line == line + offset
                      length:(int)length
                    metadata:(iTermImmutableMetadata)metadata
                continuation:(screen_char_t)continuation
               freeOnRelease:(BOOL)freeOnRelease;


- (BOOL)isEqualToScreenCharArray:(ScreenCharArray *)other;
- (ScreenCharArray *)screenCharArrayByAppendingScreenCharArray:(ScreenCharArray *)other;
- (ScreenCharArray *)screenCharArrayByRemovingTrailingNullsAndHardNewline;
- (ScreenCharArray *)inWindow:(VT100GridRange)window;

// It's eligible for DWC if all of these are true:
// 1. This is the last line in history
// 2. The top-left cell of the grid is a double-width character
- (ScreenCharArray *)paddedToLength:(int)length eligibleForDWC:(BOOL)eligibleForDWC;

// Zeros a logical range
- (ScreenCharArray *)copyByZeroingRange:(NSRange)range;
- (ScreenCharArray *)copyByZeroingVisibleRange:(NSRange)range;
- (ScreenCharArray *)paddedOrTruncatedToLength:(NSUInteger)newLength;
- (ScreenCharArray *)paddedToAtLeastLength:(NSUInteger)newLength;
- (ScreenCharArray *)screenCharArrayByRemovingFirst:(int)n;
- (ScreenCharArray *)screenCharArrayByRemovingLast:(int)n;

- (ScreenCharArray *)subArrayToIndex:(int)i;
- (ScreenCharArray *)subArrayFromIndex:(int)i;

- (NSMutableData *)mutableLineData;
- (ScreenCharArray *)screenCharArrayBySettingCharacterAtIndex:(int)i
                                                           to:(screen_char_t)c;
// Ensures that if this object outlives the raw pointer it was initialized with that there won't be a dangling pointer.
- (void)makeSafe;

- (NSAttributedString *)attributedStringValueWithAttributeProvider:(NSDictionary *(^)(screen_char_t, iTermExternalAttribute *))attributeProvider;

// Wraps copy for Swift's benefit
- (instancetype)clone;
- (int)numberOfTrailingEmptyCells;
- (int)numberOfTrailingEmptyCellsWhereSpaceIsEmpty:(BOOL)spaceIsEmpty;
- (int)numberOfLeadingEmptyCellsWhereSpaceIsEmpty:(BOOL)spaceIsEmpty;

@end

@interface MutableScreenCharArray: ScreenCharArray

@property (nonatomic, readonly) screen_char_t *mutableLine;
@property (nonatomic, readwrite) screen_char_t continuation;
@property (nonatomic, readwrite) int eol;

- (void)appendScreenCharArray:(ScreenCharArray *)sca;
- (void)appendString:(NSString *)string style:(screen_char_t)c continuation:(screen_char_t)continuation;
- (void)setExternalAttributesIndex:(iTermExternalAttributeIndex * _Nullable)eaIndex;
- (void)setBackground:(screen_char_t)bg inRange:(NSRange)range;
- (void)setForeground:(screen_char_t)gg inRange:(NSRange)range;
- (void)appendString:(NSString *)string fg:(screen_char_t)fg bg:(screen_char_t)bg;

@end

@interface ScreenCharRope: NSObject
@property (nonatomic, strong) NSArray<ScreenCharArray *> *scas;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithScreenCharArrays:(NSArray<ScreenCharArray *> *)scas NS_DESIGNATED_INITIALIZER;

- (MutableScreenCharArray *)joined;
@end

NS_ASSUME_NONNULL_END
