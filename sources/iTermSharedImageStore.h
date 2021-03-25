//
//  iTermSharedImageStore.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/10/20.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// The purpose of this class is to associate a CGImageRef with an NSImage. It's
// useful for terminal background images which need this conversion done for
// each window, and it seems to be expensive for both CPU and memory.
// It also makes it easier to diagnose leaks of NSImages.
@interface iTermImageWrapper: NSObject
@property (nonatomic, readonly, strong) NSImage *image;
@property (nonatomic, readonly) CGImageRef cgimage;
// Size of largest rep
@property (nonatomic, readonly) NSSize scaledSize;

+ (instancetype)withContentsOfFile:(NSString *)path;
+ (instancetype)withImage:(NSImage *)image;

- (instancetype)initWithImage:(NSImage *)image NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (NSImage *)tilingBackgroundImageForBackingScaleFactor:(CGFloat)scale;

@end

// Helps avoid loading NSImages from disk unnecessarily. Useful for terminal background images
// which are often the same.
@interface iTermSharedImageStore: NSObject
+ (instancetype)sharedInstance;
- (iTermImageWrapper * _Nullable)imageWithContentsOfFile:(NSString *)path;
@end

NS_ASSUME_NONNULL_END
