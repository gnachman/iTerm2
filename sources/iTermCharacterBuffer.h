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
//
// Sharing is tracked via an internal shareCount (starts at 1). Call -incrementShareCount when
// a second LineBlock begins sharing this buffer (e.g., during cowCopy). Call
// -cloneAndDecrementShareCount to atomically get a private copy and release the shared reference.
// All shareCount operations must be called under the same external lock (gLineBlockMutex).
@interface iTermCharacterBuffer: NSObject
@property(nonatomic, readonly) int size;
@property(nonatomic, readonly) screen_char_t *mutablePointer;
@property(nonatomic, readonly) const screen_char_t *pointer;
@property(nonatomic, readonly) NSData *data;
@property(nonatomic, readonly) NSString *shortDescription;

// YES when shareCount > 1 (another LineBlock shares this buffer).
// Caller must hold gLineBlockMutex.
@property(nonatomic, readonly) BOOL isShared;

// Exposed for testing. Returns the raw shareCount value.
// Caller must hold gLineBlockMutex.
@property(nonatomic, readonly) int testShareCount;

- (instancetype)initWithSize:(int)size;
- (instancetype)initWithData:(NSData *)data;

- (void)resize:(int)newSize;
- (iTermCharacterBuffer *)clone;
- (BOOL)deepIsEqual:(id)object;

// Increment the sharing count. Call when a LineBlock begins sharing this buffer.
// Caller must hold gLineBlockMutex.
- (void)incrementShareCount;

// Decrement the sharing count and return a private clone. The caller takes
// ownership of the clone (which has shareCount 1). Caller must hold gLineBlockMutex.
- (iTermCharacterBuffer *)cloneAndDecrementShareCount;

// Decrement the sharing count without cloning. Call when a LineBlock releases
// its reference to a shared buffer (e.g., during dealloc). Caller must hold
// gLineBlockMutex.
- (void)decrementShareCount;

@end

NS_ASSUME_NONNULL_END
