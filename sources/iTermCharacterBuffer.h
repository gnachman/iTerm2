//
//  iTermCharacterBuffer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/26/24.
//

#import <Foundation/Foundation.h>
#import "ScreenChar.h"

NS_ASSUME_NONNULL_BEGIN

// Stores a chunk of `screen_char_t`s for LineBlock. Many line blocks may reference the same
// character buffer. When one is modified, it gets a private copy to avoid disturbing the others.
@interface iTermCharacterBuffer: NSObject
@property(nonatomic, readonly) int size;
@property(nonatomic, readonly) screen_char_t *mutablePointer;
@property(nonatomic, readonly) const screen_char_t *pointer;
@property(nonatomic, readonly) NSData *data;

- (instancetype)initWithSize:(int)size;
- (instancetype)initWithData:(NSData *)data;

- (void)resize:(int)newSize;
- (iTermCharacterBuffer *)clone;
- (BOOL)deepIsEqual:(id)object;

@end

NS_ASSUME_NONNULL_END
