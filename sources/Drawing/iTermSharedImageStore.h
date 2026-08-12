//
//  iTermSharedImageStore.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/10/20.
//

#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreVideo/CVMetalTextureCache.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@protocol MTLDevice;

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
// can play it. iTermImageView plays it with an AVPlayerLayer and the GPU
// renderer samples frames through copyVideoPixelBufferForHostTime:generation:;
// consumers that can only draw still images fall back to the poster frame.
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

// Vends the Metal texture for the video frame that should be visible at
// hostTime, for GPU renderers drawing on the given device.
//
// An AVPlayerItemVideoOutput is single-consumer: copying a pixel buffer marks
// it acquired, so if each pane's renderer pulled from the output directly, only
// the first pane to ask would get any given frame and the others would be stuck
// one frame behind — visible as a flickering seam at split dividers when panes
// share one background image. Instead this owns the pull, dequeueing at most
// once per display refresh, and vends one texture per frame so every pane
// sampling this wrapper in a given refresh samples the identical texture.
//
// generation identifies the frame the caller is showing: pass 0 if it has none.
// Returns NULL when no frame has decoded yet or when the visible frame is still
// the one identified by *generation — either way the caller should keep showing
// what it has. Otherwise returns a texture the caller owns (release it with
// CFRelease, and keep it alive for as long as the GPU may sample it) and sets
// *generation to identify it.
//
// A texture is cached per device, so a second GPU — an eGPU, or the discrete
// GPU on a dual-GPU Mac — gets its own. Safe to call from any thread; does not
// create the player, so playback must already be under way (see
// retainVideoPlaybackInterest).
- (nullable CVMetalTextureRef)copyVideoMetalTextureForHostTime:(CFTimeInterval)hostTime
                                                        device:(id<MTLDevice>)device
                                                    generation:(inout NSInteger *)generation CF_RETURNS_RETAINED;

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
