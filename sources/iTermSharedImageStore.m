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
        DLog(@"Failed to load image from %@", path);
        return nil;
    }
    [_cache setObject:entry forKey:path];
    return image;
}

@end

@implementation iTermImageWrapper {
    id _cgimage;
    NSMutableDictionary<NSNumber *, NSImage *> *_tilingImages;
    NSMutableDictionary<NSString *, NSBitmapImageRep *> *_reps;
}

+ (instancetype)withContentsOfFile:(NSString *)path {
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
    if (!image) {
        return nil;
    }
    return [[self alloc] initWithImage:image];
}

+ (instancetype)withImage:(NSImage *)image {
    return [[self alloc] initWithImage:image];
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

        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cgimage];
        cookedImage = [[NSImage alloc] initWithSize:NSMakeSize(CGImageGetWidth(cgimage) / scale,
                                                               CGImageGetHeight(cgimage) / scale)];
        [cookedImage addRepresentation:rep];
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
            return bitmap;
        }
    }

    // Then see if the image already has a bitmap representation in this color space.
    for (NSImageRep *rep in self.image.representations) {
        NSBitmapImageRep *bitmap = [NSBitmapImageRep castFrom:rep];
        if (bitmap && [bitmap.colorSpace isEqual:colorSpace]) {
            return bitmap;
        }
    }

    // Finally, convert the best representation into the desired color space.
    CGImageRef cgImage = [[self.image bestRepresentationForScale:2] CGImageForProposedRect:nil context:nil hints:nil];
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    bitmap = [bitmap bitmapImageRepByConvertingToColorSpace:colorSpace renderingIntent:NSColorRenderingIntentDefault];
    _reps[colorSpace.localizedName] = bitmap;
    return bitmap;
}

@end

