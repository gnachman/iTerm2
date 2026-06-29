//
//  iTermCacheableImage.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/27/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermCacheableImage : NSObject

- (NSImage *)imageAtPath:(NSString *)path ofSize:(NSSize)size flipped:(BOOL)flipped;

@end

NS_ASSUME_NONNULL_END
