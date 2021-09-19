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
@interface ScreenCharArray : NSObject<NSCopying> {
    screen_char_t *_line;  // Array of chars
    int _length;  // Number of chars in _line
    int _eol;  // EOL_SOFT, EOL_HARD, or EOL_DWC
}

@property (nonatomic, assign) screen_char_t *line;  // Assume const unless instructed otherwise
@property (nonatomic, assign) int length;
@property (nonatomic, assign) int eol;
@property (nonatomic) screen_char_t continuation;
@property (nonatomic, readonly) iTermMetadata metadata;

- (instancetype)initWithLine:(screen_char_t *)line
                      length:(int)length
                continuation:(screen_char_t)continuation;

- (instancetype)initWithLine:(screen_char_t *)line
                      length:(int)length
                    metadata:(iTermMetadata)metadata
                continuation:(screen_char_t)continuation;

- (BOOL)isEqualToScreenCharArray:(ScreenCharArray *)other;
- (ScreenCharArray *)screenCharArrayByAppendingScreenCharArray:(ScreenCharArray *)other;
- (ScreenCharArray *)screenCharArrayByRemovingTrailingNullsAndHardNewline;

@end

NS_ASSUME_NONNULL_END
