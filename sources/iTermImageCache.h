//
//  iTermImageCache.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/16/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermImageCache : NSObject

@property (nonatomic) NSUInteger byteLimit;

- (instancetype)initWithByteLimit:(NSUInteger)byteLimit NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSImage *)imageWithName:(NSString *)name
                      size:(NSSize)size
                     color:(nullable NSColor *)color;

- (void)addImage:(NSImage *)image
            name:(NSString *)name
            size:(NSSize)size
           color:(nullable NSColor *)color;

@end

NS_ASSUME_NONNULL_END
