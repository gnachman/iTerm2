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
@property (nonatomic, readonly) iTermMetadata metadata;

- (instancetype)initWithLine:(const screen_char_t *)line
                      length:(int)length
                continuation:(screen_char_t)continuation;

- (instancetype)initWithLine:(const screen_char_t *)line
                      length:(int)length
                    metadata:(iTermMetadata)metadata
                continuation:(screen_char_t)continuation;

- (BOOL)isEqualToScreenCharArray:(ScreenCharArray *)other;
- (ScreenCharArray *)screenCharArrayByAppendingScreenCharArray:(ScreenCharArray *)other;
- (ScreenCharArray *)screenCharArrayByRemovingTrailingNullsAndHardNewline;

@end

NS_ASSUME_NONNULL_END
