//
//  iTermCacheableImage.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/27/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermCacheableImage : NSObject

- (nullable NSImage *)imageAtPath:(nullable NSString *)path ofSize:(NSSize)size flipped:(BOOL)flipped;

@end

NS_ASSUME_NONNULL_END
