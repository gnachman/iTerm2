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
@property(nonatomic, readonly) NSString *shortDescription;

- (instancetype)initWithSize:(int)size;
- (instancetype)initWithData:(NSData *)data;

// Copies `data` into a buffer with room for at least `capacity` characters. Characters past the
// end of `data` are zeroed.
- (instancetype)initWithData:(NSData *)data capacity:(int)capacity;

// Returns the first `length` characters, which must not exceed `size`.
- (NSData *)dataWithLength:(int)length;

- (void)resize:(int)newSize;
- (iTermCharacterBuffer *)clone;
- (BOOL)deepIsEqual:(id)object;

// Compares only the first `length` characters, which must not exceed either buffer's size.
- (BOOL)deepIsEqual:(id)object prefixLength:(int)length;

@end

NS_ASSUME_NONNULL_END
