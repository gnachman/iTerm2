//
//  iTermSharedImageStore.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/10/20.
//

#import "iTermSharedImageStore.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSObject+iTerm.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

@interface NSFileManager(CachedImage)
- (NSDate *)lastModifiedDateOfFile:(NSString *)path;
@end

@implementation NSFileManager(CachedImage)

- (NSDate *)lastModifiedDateOfFile:(NSString *)path {
    NSDictionary *attrs = [self attributesOfItemAtPath:path error:nil];
    if (!attrs) {
        return nil;
    }
    return [attrs fileModificationDate];
}

@end

@interface iTermCachedImage: NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, readonly, weak) iTermImageWrapper *image;
@property (nonatomic, readonly, strong) NSDate *lastModified;
@property (nonatomic, readonly) iTermImageWrapper *imageIfValid;

- (instancetype)initWithPath:(NSString *)path
                       image:(out iTermImageWrapper **)imageOut NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end


@implementation iTermCachedImage;

- (instancetype)initWithPath:(NSString *)path image:(out iTermImageWrapper **)imageOut {
    self = [super init];
    if (self) {
        _path = [path copy];
        iTermImageWrapper *image = [iTermImageWrapper withContentsOfFile:path];
        if (image) {
            DLog(@"Loaded image from %@", path);
            _lastModified = [[NSFileManager defaultManager] lastModifiedDateOfFile:_path];
        }
        _image = image;
        *imageOut = image;
    }
    return self;
}

- (iTermImageWrapper *)imageIfValid {
    iTermImageWrapper *image = self.image;
    if (image != nil &&
        self.lastModified != nil &&
        [_lastModified isEqual:[[NSFileManager defaultManager] lastModifiedDateOfFile:_path]]) {
        return image;
    }
    return nil;
}

@end


@implementation iTermSharedImageStore {
    NSMutableDictionary<NSString *, iTermCachedImage *> *_cache;
}

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static id instance;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [NSMutableDictionary dictionary];
    }
    return self;
}

- (iTermImageWrapper * _Nullable)imageWithContentsOfFile:(NSString *)path {
    iTermCachedImage *entry = _cache[path];
    iTermImageWrapper *image = [entry imageIfValid];
    if (image) {
        DLog(@"Use cached image at %@: %p", path, image);
        return image;
    }

    entry = [[iTermCachedImage alloc] initWithPath:path image:&image];
    if (!image) {
        RLog(@"Failed to load image from %@", path);
        return nil;
    }
    [_cache setObject:entry forKey:path];
    return image;
}

@end

static void *iTermImageWrapperCurrentItemContext = &iTermImageWrapperCurrentItemContext;

@implementation iTermImageWrapper {
    id _cgimage;
    NSMutableDictionary<NSNumber *, NSImage *> *_tilingImages;
    NSMutableDictionary<NSString *, NSBitmapImageRep *> *_reps;

    AVQueuePlayer *_videoPlayer;
    AVPlayerLooper *_videoLooper;
    AVPlayerItemVideoOutput *_videoOutput;
    NSInteger _videoPlaybackInterestCount;
}

@synthesize videoOutput = _videoOutput;

+ (instancetype)withContentsOfFile:(NSString *)path {
    if ([self pathIsVideo:path]) {
        return [[self alloc] initWithVideoURL:[NSURL fileURLWithPath:path]];
    }
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
    if (!image) {
        return nil;
    }
    return [[self alloc] initWithImage:image];
}

+ (instancetype)withImage:(NSImage *)image {
    return [[self alloc] initWithImage:image];
}

+ (NSArray<UTType *> *)videoContentTypes {
    return @[ UTTypeMPEG4Movie, UTTypeQuickTimeMovie ];
}

+ (BOOL)pathIsVideo:(NSString *)path {
    NSString *extension = path.pathExtension;
    if (extension.length == 0) {
        return NO;
    }
    UTType *type = [UTType typeWithFilenameExtension:extension];
    if (!type) {
        return NO;
    }
    for (UTType *videoType in [self videoContentTypes]) {
        if ([type conformsToType:videoType]) {
            return YES;
        }
    }
    return NO;
}

- (instancetype)initWithVideoURL:(NSURL *)url {
    // The placeholder keeps image-only consumers working until the poster
    // frame arrives; views that can play video ignore it.
    self = [self initWithImage:[[NSImage alloc] initWithSize:NSMakeSize(1, 1)]];
    if (self) {
        _videoURL = [url copy];
        [self loadPosterFrame];
    }
    return self;
}

- (BOOL)isVideo {
    return _videoURL != nil;
}

- (void)loadPosterFrame {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:_videoURL options:nil];
    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    __weak __typeof(self) weakSelf = self;
    [generator generateCGImagesAsynchronouslyForTimes:@[ [NSValue valueWithCMTime:kCMTimeZero] ]
                                    completionHandler:^(CMTime requestedTime,
                                                        CGImageRef _Nullable cgImage,
                                                        CMTime actualTime,
                                                        AVAssetImageGeneratorResult result,
                                                        NSError * _Nullable error) {
        if (result != AVAssetImageGeneratorSucceeded || !cgImage) {
            DLog(@"Failed to generate poster frame: %@", error);
            return;
        }
        NSImage *poster = [[NSImage alloc] initWithCGImage:cgImage
                                                      size:NSMakeSize(CGImageGetWidth(cgImage),
                                                                      CGImageGetHeight(cgImage))];
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf setPosterFrame:poster];
        });
    }];
}

// Main queue only. Replaces the placeholder and invalidates derived caches.
- (void)setPosterFrame:(NSImage *)poster {
    _image = poster;
    _cgimage = nil;
    [_tilingImages removeAllObjects];
    [_reps removeAllObjects];
}

#pragma mark - Video playback

- (AVQueuePlayer *)videoPlayer {
    if (!self.isVideo) {
        return nil;
    }
    if (!_videoPlayer) {
        AVPlayerItem *item = [AVPlayerItem playerItemWithURL:_videoURL];
        _videoPlayer = [AVQueuePlayer queuePlayerWithItems:@[ item ]];
        _videoPlayer.muted = YES;
        _videoPlayer.preventsDisplaySleepDuringVideoPlayback = NO;
        _videoLooper = [AVPlayerLooper playerLooperWithPlayer:_videoPlayer templateItem:item];
        _videoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (id)kCVPixelBufferMetalCompatibilityKey: @YES
        }];
        // AVPlayerLooper rotates through replica items, so the output must
        // chase the current item; observing with Initial covers the first one.
        [_videoPlayer addObserver:self
                       forKeyPath:@"currentItem"
                          options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                          context:iTermImageWrapperCurrentItemContext];
    }
    return _videoPlayer;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (context != iTermImageWrapperCurrentItemContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    AVPlayerItem *item = _videoPlayer.currentItem;
    if (item && _videoOutput && ![item.outputs containsObject:_videoOutput]) {
        [item addOutput:_videoOutput];
    }
}

- (void)retainVideoPlaybackInterest {
    if (!self.isVideo) {
        return;
    }
    _videoPlaybackInterestCount += 1;
    if (_videoPlaybackInterestCount == 1) {
        [self.videoPlayer play];
    }
}

- (void)releaseVideoPlaybackInterest {
    if (!self.isVideo) {
        return;
    }
    _videoPlaybackInterestCount = MAX(0, _videoPlaybackInterestCount - 1);
    if (_videoPlaybackInterestCount == 0) {
        [_videoPlayer pause];
    }
}

- (void)dealloc {
    if (_videoPlayer) {
        [_videoPlayer removeObserver:self
                          forKeyPath:@"currentItem"
                             context:iTermImageWrapperCurrentItemContext];
    }
}

- (instancetype)initWithImage:(NSImage *)unsafeImage {
    self = [super init];
    if (self) {
        _reps = [NSMutableDictionary dictionary];
        _tilingImages = [NSMutableDictionary dictionary];
        NSImage *image = unsafeImage;
        if (unsafeImage.size.height > 0 && unsafeImage.size.width > 0) {
            // Downscale to deal with issue 9346
            const CGFloat maxSize = 5120;
            if (unsafeImage.size.width > maxSize || unsafeImage.size.height > maxSize) {
                const CGFloat xscale = MIN(1, maxSize / unsafeImage.size.width);
                const CGFloat yscale = MIN(1, maxSize / unsafeImage.size.height);
                const CGFloat scale = MIN(xscale, yscale);
                NSImage *downscaled = [unsafeImage it_imageOfSize:NSMakeSize(unsafeImage.size.width * scale,
                                                                             unsafeImage.size.height * scale)];
                image = downscaled;
            }
        }
        _image = image;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p reps=%@ image=%@ tilingImages=%@ cgimage=%@>",
            NSStringFromClass([self class]),
            self,
            _reps,
            _image,
            _tilingImages,
            _cgimage];
}

- (CGImageRef)cgimage {
    if (_cgimage) {
        return (__bridge CGImageRef)_cgimage;
    }
    _cgimage = [self.image layerContentsForContentsScale:[self.image recommendedLayerContentsScale:2]];
    return (__bridge CGImageRef)_cgimage;
}

- (NSSize)scaledSize {
    NSImageRep *rep = [[self.image representations] maxWithComparator:^NSComparisonResult(NSImageRep *a, NSImageRep *b) {
        return [@(a.pixelsWide) compare:@(b.pixelsWide)];
    }];
    if (rep) {
        return NSMakeSize(rep.pixelsWide, rep.pixelsHigh);
    }
    return self.image.size;
}

- (NSImage *)tilingBackgroundImageForBackingScaleFactor:(CGFloat)scale {
    NSImage *cached = _tilingImages[@(scale)];
    if (cached) {
        return cached;
    }
    NSImageRep *bestRep = [self.image.representations maxWithBlock:^NSComparisonResult(NSImageRep *obj1, NSImageRep *obj2) {
        return [@(obj1.size.width) compare:@(obj2.size.width)];
    }];
    NSImage *cookedImage;
    if ([bestRep isKindOfClass:[NSBitmapImageRep class]]) {
        NSBitmapImageRep *bitmap = (NSBitmapImageRep *)bestRep;
        CGImageRef cgimage = bitmap.CGImage;
        if (cgimage) {
            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cgimage];
            cookedImage = [[NSImage alloc] initWithSize:NSMakeSize(CGImageGetWidth(cgimage) / scale,
                                                                   CGImageGetHeight(cgimage) / scale)];
            [cookedImage addRepresentation:rep];
        } else {
            cookedImage = self.image;
        }
    } else {
        cookedImage = self.image;
    }
    _tilingImages[@(scale)] = cookedImage;
    return cookedImage;
}

- (NSBitmapImageRep *)bitmapInColorSpace:(NSColorSpace *)colorSpace {
    // First, try to use a cached bitmap.
    {
        NSBitmapImageRep *bitmap = _reps[colorSpace.localizedName];
        if (bitmap) {
            DLog(@"Already have a cached bitmap in this colorspace");
            return bitmap;
        }
    }

    // Then see if the image already has a bitmap representation in this color space.
    for (NSImageRep *rep in self.image.representations) {
        NSBitmapImageRep *bitmap = [NSBitmapImageRep castFrom:rep];
        if (bitmap && [bitmap.colorSpace isEqual:colorSpace]) {
            DLog(@"Image has a bitmap in this colorspace");
            return bitmap;
        }
    }

    // Finally, convert the best representation into the desired color space.
    NSImageRep *rep = [self.image bestRepresentationForScale:2];
    DLog(@"Need to convert colorspace. Best rep is %@", rep);
    CGImageRef cgImage = [rep CGImageForProposedRect:nil context:nil hints:nil];
    DLog(@"cgImage=%@", cgImage);
    if (cgImage == nil) {
        // I've noticed this happens when low on memory. bitmapImageRepByConvertingToColorSpace will die with an assertion, so better to return nil now.
        return nil;
    }
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    DLog(@"bitmap=%@", bitmap);
    bitmap = [bitmap bitmapImageRepByConvertingToColorSpace:colorSpace renderingIntent:NSColorRenderingIntentDefault];
    DLog(@"bitmap after converting colorspace=%@", bitmap);
    _reps[colorSpace.localizedName] = bitmap;
    return bitmap;
}

@end

