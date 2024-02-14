//
//  ScreenCharArray.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/18/21.
//

#import <Foundation/Foundation.h>
#import "ScreenChar.h"
#import "iTermMetadata.h"

NS_ASSUME_NONNULL_BEGIN

// Typically used to store a single screen line.
@interface ScreenCharArray : NSObject<NSCopying>

@property (nonatomic, readonly) const screen_char_t *line;
@property (nonatomic) int length;
@property (nonatomic, readonly) int eol;  // EOL_SOFT, EOL_HARD, or EOL_DWC
@property (nonatomic, readonly) screen_char_t continuation;
@property (nonatomic, readonly) iTermImmutableMetadata metadata;
@property (nonatomic, readonly) NSDictionary *dictionaryValue;
@property (nonatomic, readonly) NSString *stringValue;
@property (nonatomic, readonly) NSString *stringValueIncludingNewline;

@property (nonatomic, readonly) NSInteger lengthExcludingTrailingWhitespaceAndNulls;

+ (instancetype)emptyLineOfLength:(int)length;

- (instancetype)initWithLine:(const screen_char_t *)line
                      length:(int)length
                continuation:(screen_char_t)continuation;

- (instancetype)initWithCopyOfLine:(const screen_char_t *)line
                            length:(int)length
                      continuation:(screen_char_t)continuation;

- (instancetype)initWithLine:(const screen_char_t *)line
                      length:(int)length
                    metadata:(iTermImmutableMetadata)metadata
                continuation:(screen_char_t)continuation;

- (instancetype)initWithData:(NSData *)data
                    metadata:(iTermImmutableMetadata)metadata
                continuation:(screen_char_t)continuation;

- (instancetype)initWithLine:(const screen_char_t *)line
                      length:(int)length
                    metadata:(iTermImmutableMetadata)metadata
                continuation:(screen_char_t)continuation
               freeOnRelease:(BOOL)freeOnRelease;

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

- (ScreenCharArray *)copyByZeroingRange:(NSRange)range;
- (ScreenCharArray *)paddedOrTruncatedToLength:(NSUInteger)newLength;
- (ScreenCharArray *)paddedToAtLeastLength:(NSUInteger)newLength;
- (ScreenCharArray *)screenCharArrayByRemovingFirst:(int)n;
- (ScreenCharArray *)screenCharArrayByRemovingLast:(int)n;

- (NSMutableData *)mutableLineData;
- (ScreenCharArray *)screenCharArrayBySettingCharacterAtIndex:(int)i
                                                           to:(screen_char_t)c;
// Ensures that if this object outlives the raw pointer it was initialized with that there won't be a dangling pointer.
- (void)makeSafe;

- (NSAttributedString *)attributedStringValueWithAttributeProvider:(NSDictionary *(^)(screen_char_t, iTermExternalAttribute *))attributeProvider;

@end

NS_ASSUME_NONNULL_END
