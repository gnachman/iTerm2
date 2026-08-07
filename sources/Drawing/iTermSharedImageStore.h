//
//  iTermSharedImageStore.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/10/20.
//

#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

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
// When the wrapped file is a video, image holds a placeholder (the poster
// frame, once it loads asynchronously) and videoURL locates the file so views
// can play it. Playback happens in iTermImageView; renderers that can only
// draw still images fall back to the poster frame.
@property (nonatomic, readonly, nullable) NSURL *videoURL;
@property (nonatomic, readonly) BOOL isVideo;

+ (instancetype _Nullable)withContentsOfFile:(NSString *)path;
+ (instancetype)withImage:(NSImage *)image;

// Container formats AVFoundation can reliably decode for background videos.
+ (NSArray<UTType *> *)videoContentTypes;
+ (BOOL)pathIsVideo:(NSString *)path;

// One muted, looping player is shared by every consumer of this wrapper —
// AVPlayerLayers in image views and the Metal renderer alike — so a video
// used in several panes decodes once. Playback runs while at least one
// consumer holds an interest. Call these on the main queue.
- (void)retainVideoPlaybackInterest;
- (void)releaseVideoPlaybackInterest;
// Nil for non-videos. Created on first access; main queue only.
@property (nonatomic, readonly, nullable) AVQueuePlayer *videoPlayer;
// The output vends BGRA pixel buffers for the Metal renderer. Nil until
// videoPlayer or a playback interest has created the player. Safe to read
// from the render thread; AVPlayerItemVideoOutput itself is thread-safe.
@property (atomic, readonly, nullable) AVPlayerItemVideoOutput *videoOutput;

- (instancetype)initWithImage:(NSImage *)image NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (NSImage *)tilingBackgroundImageForBackingScaleFactor:(CGFloat)scale;
- (NSBitmapImageRep *)bitmapInColorSpace:(NSColorSpace *)colorSpace;

@end

// Helps avoid loading NSImages from disk unnecessarily. Useful for terminal background images
// which are often the same.
@interface iTermSharedImageStore: NSObject
+ (instancetype)sharedInstance;
- (iTermImageWrapper * _Nullable)imageWithContentsOfFile:(NSString *)path;
@end

NS_ASSUME_NONNULL_END
