//
//  iTermImageInfo.m
//  iTerm2
//
//  Created by George Nachman on 5/11/15.
//
//

#import "iTermImageInfo.h"

#import "DebugLogging.h"
#import "iTermAnimatedImageInfo.h"
#import "iTermImage.h"
#import "iTermTuple.h"
#import "FutureMethods.h"
#import "NSData+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSWorkspace+iTerm.h"

static NSString *const kImageInfoSizeKey = @"Size";
static NSString *const kImageInfoImageKey = @"Image";  // data
static NSString *const kImageInfoPreserveAspectRatioKey = @"Preserve Aspect Ratio";
static NSString *const kImageInfoFilenameKey = @"Filename";
static NSString *const kImageInfoInsetKey = @"Edge Insets";
static NSString *const kImageInfoCodeKey = @"Code";
static NSString *const kImageInfoBrokenKey = @"Broken";

NSString *const iTermImageDidLoad = @"iTermImageDidLoad";

@interface iTermImageInfo ()

@property(atomic, strong) NSMutableDictionary *embeddedImages;  // frame number->downscaled image
@property(atomic, assign) unichar code;
@property(atomic, strong) iTermAnimatedImageInfo *animatedImage;  // If animated GIF, this is nonnil
@end

@implementation iTermImageInfo {
    NSData *_data;
    NSString *_uniqueIdentifier;
    NSDictionary *_dictionary;
    void (^_queuedBlock)(void);
    BOOL _paused;
    iTermImage *_image;
    iTermAnimatedImageInfo *_animatedImage;
}

@synthesize image = _image;
@synthesize data = _data;
@synthesize code = _code;
@synthesize broken = _broken;
@synthesize paused = _paused;
@synthesize uniqueIdentifier = _uniqueIdentifier;
@synthesize size = _size;
@synthesize filename = _filename;

- (instancetype)initWithCode:(unichar)code {
    self = [super init];
    if (self) {
        _code = code;
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    self = [super init];
    if (self) {
        _size = [dictionary[kImageInfoSizeKey] sizeValue];
        _broken = [dictionary[kImageInfoBrokenKey] boolValue];
        _inset = [dictionary[kImageInfoInsetKey] futureEdgeInsetsValue];
        _data = [dictionary[kImageInfoImageKey] copy];
        _dictionary = [dictionary copy];
        _preserveAspectRatio = [dictionary[kImageInfoPreserveAspectRatioKey] boolValue];
        _filename = [dictionary[kImageInfoFilenameKey] copy];
        _code = [dictionary[kImageInfoCodeKey] shortValue];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p code=%@ size=%@ uniqueIdentifier=%@ filename=%@ broken=%@>",
            self.class, self, @(self.code), NSStringFromSize(self.size), self.uniqueIdentifier, self.filename, @(self.broken)];
}

- (NSString *)uniqueIdentifier {
    @synchronized(self) {
        if (!_uniqueIdentifier) {
            _uniqueIdentifier = [[[NSUUID UUID] UUIDString] copy];
        }
        return _uniqueIdentifier;
    }
}

- (void)loadFromDictionaryIfNeeded {
    @synchronized(self) {
        static dispatch_once_t onceToken;
        static dispatch_queue_t queue;
        static NSMutableArray *blocks;
        dispatch_once(&onceToken, ^{
            blocks = [[NSMutableArray alloc] init];
            queue = dispatch_queue_create("com.iterm2.LazyImageDecoding", DISPATCH_QUEUE_SERIAL);
        });

        if (!_dictionary) {
            @synchronized (self) {
                if (_queuedBlock) {
                    // Move to the head of the queue.
                    NSUInteger index = [blocks indexOfObjectIdenticalTo:_queuedBlock];
                    if (index != NSNotFound) {
                        [blocks removeObjectAtIndex:index];
                        [blocks insertObject:_queuedBlock atIndex:0];
                    }
                }
            }
            return;
        }

        _dictionary = nil;

        DLog(@"Queueing load of %@", self.uniqueIdentifier);
        void (^block)(void) = ^{
            // This is a slow operation that blocks for a long time.
            iTermImage *image = [iTermImage imageWithCompressedData:self->_data];
            dispatch_sync(dispatch_get_main_queue(), ^{
                self->_queuedBlock = nil;
                self->_animatedImage = [[iTermAnimatedImageInfo alloc] initWithImage:image];
                if (!self->_animatedImage) {
                    self->_image = image;
                }
                if (self->_image || self->_animatedImage) {
                    DLog(@"Loaded %@", self.uniqueIdentifier);
                    [[NSNotificationCenter defaultCenter] postNotificationName:iTermImageDidLoad object:self];
                }
            });
        };
        _queuedBlock = [block copy];
        @synchronized(self) {
            [blocks insertObject:_queuedBlock atIndex:0];
        }
        dispatch_async(queue, ^{
            void (^blockToRun)(void) = nil;
            @synchronized(self) {
                blockToRun = [blocks firstObject];
                [blocks removeObjectAtIndex:0];
            }
            blockToRun();
        });
    }
}

- (void)saveToFile:(NSString *)filename {
    @synchronized(self) {
        NSBitmapImageFileType fileType = NSBitmapImageFileTypePNG;
        if ([filename hasSuffix:@".bmp"]) {
            fileType = NSBitmapImageFileTypeBMP;
        } else if ([filename hasSuffix:@".gif"]) {
            fileType = NSBitmapImageFileTypeGIF;
        } else if ([filename hasSuffix:@".jp2"]) {
            fileType = NSBitmapImageFileTypeJPEG2000;
        } else if ([filename hasSuffix:@".jpg"] || [filename hasSuffix:@".jpeg"]) {
            fileType = NSBitmapImageFileTypeJPEG;
        } else if ([filename hasSuffix:@".png"]) {
            fileType = NSBitmapImageFileTypePNG;
        } else if ([filename hasSuffix:@".tiff"]) {
            fileType = NSBitmapImageFileTypeTIFF;
        }

        NSData *data = nil;
        NSDictionary *universalTypeToCocoaMap = @{ (NSString *)kUTTypeBMP: @(NSBitmapImageFileTypeBMP),
                                                   (NSString *)kUTTypeGIF: @(NSBitmapImageFileTypeGIF),
                                                   (NSString *)kUTTypeJPEG2000: @(NSBitmapImageFileTypeJPEG2000),
                                                   (NSString *)kUTTypeJPEG: @(NSBitmapImageFileTypeJPEG),
                                                   (NSString *)kUTTypePNG: @(NSBitmapImageFileTypePNG),
                                                   (NSString *)kUTTypeTIFF: @(NSBitmapImageFileTypeTIFF) };
        NSString *imageType = self.imageType;
        if (self.broken) {
            data = self.data;
        } else if (imageType) {
            NSNumber *nsTypeNumber = universalTypeToCocoaMap[imageType];
            if (nsTypeNumber.integerValue == fileType) {
                data = self.data;
            }
        }
        if (!data) {
            NSBitmapImageRep *rep = [self.image.images.firstObject bitmapImageRep];
            data = [rep representationUsingType:fileType properties:@{}];
        }
        [data writeToFile:filename atomically:NO];
    }
}

- (void)setImageFromImage:(iTermImage *)image data:(NSData *)data {
    @synchronized(self) {
        _dictionary = nil;
        _animatedImage = [[iTermAnimatedImageInfo alloc] initWithImage:image];
        _data = [data copy];
        _image = image;
    }
}

- (NSString *)imageType {
    @synchronized(self) {
        NSString *type = [_data uniformTypeIdentifierForImageData];
        if (type) {
            return type;
        }

        return (NSString *)kUTTypeImage;
    }
}

- (NSDictionary<NSString *, NSObject<NSCopying> *> *)dictionary {
    @synchronized(self) {
        return @{ kImageInfoSizeKey: [NSValue valueWithSize:_size],
                  kImageInfoInsetKey: [NSValue futureValueWithEdgeInsets:_inset],
                  kImageInfoImageKey: _data ?: [NSData data],
                  kImageInfoPreserveAspectRatioKey: @(_preserveAspectRatio),
                  kImageInfoFilenameKey: _filename ?: @"",
                  kImageInfoCodeKey: @(_code),
                  kImageInfoBrokenKey: @(_broken) };
    }
}


- (BOOL)animated {
    @synchronized(self) {
        return !_paused && _animatedImage != nil;
    }
}

- (void)setPaused:(BOOL)paused {
    @synchronized(self) {
        _paused = paused;
        _animatedImage.paused = paused;
    }
}

- (BOOL)paused {
    @synchronized(self) {
        return _paused;
    }
}

- (void)setImage:(iTermImage *)image {
    @synchronized(self) {
        _image = image;
    }
}

- (iTermImage *)image {
    @synchronized(self) {
        [self loadFromDictionaryIfNeeded];
        return _image;
    }
}

- (void)setAnimatedImage:(iTermAnimatedImageInfo *)animatedImage {
    @synchronized (self) {
        _animatedImage = animatedImage;
    }
}

- (iTermAnimatedImageInfo *)animatedImage {
    @synchronized(self) {
        [self loadFromDictionaryIfNeeded];
        return _animatedImage;
    }
}

- (NSImage *)imageWithCellSize:(CGSize)cellSize scale:(CGFloat)scale {
    @synchronized(self) {
        return [self imageWithCellSize:cellSize
                             timestamp:[NSDate timeIntervalSinceReferenceDate]
                                 scale:scale];
    }
}

- (int)frameForTimestamp:(NSTimeInterval)timestamp {
    @synchronized(self) {
        return [self.animatedImage frameForTimestamp:timestamp];
    }
}

- (BOOL)ready {
    @synchronized(self) {
        return (self.image || self.animatedImage);
    }

}
static NSSize iTermImageInfoGetSizeForRegionPreservingAspectRatio(const NSSize region,
                                                                  NSSize imageSize) {
    double imageAR = imageSize.width / imageSize.height;
    double canvasAR = region.width / region.height;
    if (imageAR > canvasAR) {
        // Image is wider than canvas, add letterboxes on top and bottom.
        return NSMakeSize(region.width, region.width / imageAR);
    } else {
        // Image is taller than canvas, add pillarboxes on sides.
        return NSMakeSize(region.height * imageAR, region.height);
    }
}

// NOTE: This gets called off the main queue in the metal renderer.
- (NSImage *)imageWithCellSize:(CGSize)cellSize timestamp:(NSTimeInterval)timestamp scale:(CGFloat)scale {
    @synchronized(self) {
        if (!self.ready) {
            DLog(@"%@ not ready", self.uniqueIdentifier);
            return nil;
        }
        DLog(@"[%p imageWithCellSize:%@ timestamp:%@ scale:%@]",
             self, NSStringFromSize(cellSize), @(timestamp), @(scale));
        if (!_embeddedImages) {
            _embeddedImages = [[NSMutableDictionary alloc] init];
        }
        int frame = [self.animatedImage frameForTimestamp:timestamp];  // 0 if not animated
        iTermTuple *key = [iTermTuple tupleWithObject:@(frame) andObject:@(scale)];
        NSImage *embeddedImage = _embeddedImages[key];
        DLog(@"embeddedImage=%@", embeddedImage);
        NSSize region = NSMakeSize(cellSize.width * _size.width,
                                   cellSize.height * _size.height);
        DLog(@"region=%@", NSStringFromSize(region));
        if (!NSEqualSizes(embeddedImage.size, region)) {
            DLog(@"Sizes differ. Resize.");
            NSImage *theImage;
            if (self.animatedImage) {
                theImage = [self.animatedImage imageForFrame:frame];
            } else {
                theImage = [self.image.images firstObject];
            }
            DLog(@"theImage is %@", theImage);
            NSEdgeInsets inset = _inset;
            inset.top *= cellSize.height;
            inset.bottom *= cellSize.height;
            inset.left *= cellSize.width;
            inset.right *= cellSize.width;
            const NSRect destinationRect = NSMakeRect(inset.left,
                                                      inset.bottom,
                                                      MAX(0, region.width - inset.left - inset.right),
                                                      MAX(0, region.height - inset.top - inset.bottom));
            NSImage *canvas = [theImage safelyResizedImageWithSize:region
                                                   destinationRect:destinationRect
                                                             scale:scale];
            DLog(@"Assign %@ to %@", canvas, key);
            self.embeddedImages[key] = canvas;
        }
        NSImage *image = _embeddedImages[key];
        DLog(@"return %@", image);
        return image;
    }
}

- (NSImage *)firstFrame {
    if (self.animatedImage) {
        return [self.animatedImage imageForFrame:0];
    } else {
        return [self.image.images firstObject];
    }
}

+ (NSEdgeInsets)fractionalInsetsStretchingToDesiredSize:(NSSize)desiredSize
                                              imageSize:(NSSize)imageSize
                                               cellSize:(NSSize)cellSize
                                          numberOfCells:(NSSize)numberOfCells {
    const NSSize region = NSMakeSize(cellSize.width * numberOfCells.width,
                                     cellSize.height * numberOfCells.height);
    const NSEdgeInsets pointInsets = NSEdgeInsetsMake(0,
                                                      0,
                                                      region.height - desiredSize.height,
                                                      region.width - desiredSize.width);
    return NSEdgeInsetsMake(pointInsets.top / cellSize.height,
                            pointInsets.left / cellSize.width,
                            pointInsets.bottom / cellSize.height,
                            pointInsets.right / cellSize.width);
}

+ (NSEdgeInsets)fractionalInsetsForPreservedAspectRatioWithDesiredSize:(NSSize)desiredSize
                                                          forImageSize:(NSSize)imageSize
                                                              cellSize:(NSSize)cellSize
                                                         numberOfCells:(NSSize)numberOfCells {
    const NSSize region = NSMakeSize(cellSize.width * numberOfCells.width,
                                     cellSize.height * numberOfCells.height);
    const NSSize size = iTermImageInfoGetSizeForRegionPreservingAspectRatio(desiredSize, imageSize);

    const NSEdgeInsets pointInsets = NSEdgeInsetsMake(0,
                                                      0,
                                                      region.height - size.height,
                                                      region.width - size.width);
    return NSEdgeInsetsMake(pointInsets.top / cellSize.height,
                            pointInsets.left / cellSize.width,
                            pointInsets.bottom / cellSize.height,
                            pointInsets.right / cellSize.width);
}

- (NSString *)nameForNewSavedTempFile {
    @synchronized(self) {
        NSString *name = nil;
        if (_filename.pathExtension.length) {
            // The filename has an extension. Preserve its name in the tempfile's name,
            // and especially importantly, preserve its extension.
            NSString *suffix = [@"." stringByAppendingString:_filename.lastPathComponent];
            name = [[NSWorkspace sharedWorkspace] temporaryFileNameWithPrefix:@"iTerm2."
                                                                       suffix:suffix];
        } else {
            // Empty extension case. Try to guess the extension.
            NSString *extension = [NSImage extensionForUniformType:self.imageType];
            if (extension) {
                extension = [@"." stringByAppendingString:extension];
            }
            name = [[NSWorkspace sharedWorkspace] temporaryFileNameWithPrefix:@"iTerm2."
                                                                       suffix:extension];
        }
        [self.data writeToFile:name atomically:NO];
        return name;
    }
}

- (NSPasteboardItem *)pasteboardItem {
    @synchronized(self) {
        NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
        NSArray *types;
        NSString *imageType = self.imageType;
        if (imageType) {
            types = @[ (NSString *)kUTTypeFileURL, (NSString *)imageType ];
        } else {
            types = @[ (NSString *)kUTTypeFileURL ];
        }
        [pbItem setDataProvider:self forTypes:types];

        return pbItem;
    }
}

#pragma mark - NSPasteboardItemDataProvider

- (void)pasteboard:(NSPasteboard *)pasteboard item:(NSPasteboardItem *)item provideDataForType:(NSString *)type {
    @synchronized(self) {
        if ([type isEqualToString:(NSString *)kUTTypeFileURL]) {
            // Write image to a temp file and provide its location.
            [item setString:[[NSURL fileURLWithPath:self.nameForNewSavedTempFile] absoluteString]
                    forType:(NSString *)kUTTypeFileURL];
        } else {
            if ([type isEqualToString:(NSString *)kUTTypeImage] && ![_data uniformTypeIdentifierForImageData]) {
                [item setData:_data forType:type];
            } else {
                // Provide our data, which is already in the format requested by |type|.
                [item setData:self.data forType:type];
            }
        }
    }
}

@end
