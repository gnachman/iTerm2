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

@property(nonatomic, retain) NSMutableDictionary *embeddedImages;  // frame number->downscaled image
@property(nonatomic, assign) unichar code;
@property(nonatomic, retain) iTermAnimatedImageInfo *animatedImage;  // If animated GIF, this is nonnil
@end

@implementation iTermImageInfo {
    NSData *_data;
    NSString *_uniqueIdentifier;
    NSDictionary *_dictionary;
    void (^_queuedBlock)();
}

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
        _data = [dictionary[kImageInfoImageKey] retain];
        _dictionary = [dictionary copy];
        _preserveAspectRatio = [dictionary[kImageInfoPreserveAspectRatioKey] boolValue];
        _filename = [dictionary[kImageInfoFilenameKey] copy];
        _code = [dictionary[kImageInfoCodeKey] shortValue];
    }
    return self;
}

- (NSString *)uniqueIdentifier {
    if (!_uniqueIdentifier) {
        _uniqueIdentifier = [[[NSUUID UUID] UUIDString] copy];
    }
    return _uniqueIdentifier;
}

- (void)loadFromDictionaryIfNeeded {
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
    
    [_dictionary release];
    _dictionary = nil;
    
    DLog(@"Queueing load of %@", self.uniqueIdentifier);
    void (^block)() = ^{
        // This is a slow operation that blocks for a long time.
        iTermImage *image = [iTermImage imageWithCompressedData:_data];
        dispatch_sync(dispatch_get_main_queue(), ^{
            [_queuedBlock release];
            _queuedBlock = nil;
            _animatedImage = [[iTermAnimatedImageInfo alloc] initWithImage:image];
            if (!_animatedImage) {
                _image = [image retain];
            }
            DLog(@"Loaded %@", self.uniqueIdentifier);
            [[NSNotificationCenter defaultCenter] postNotificationName:iTermImageDidLoad object:self];
        });
    };
    _queuedBlock = [block copy];
    @synchronized(self) {
        [blocks insertObject:_queuedBlock atIndex:0];
    }
    dispatch_async(queue, ^{
        void (^blockToRun)() = nil;
        @synchronized(self) {
            blockToRun = [blocks firstObject];
            [blockToRun retain];
            [blocks removeObjectAtIndex:0];
        }
        blockToRun();
        [blockToRun release];
    });
}

- (void)dealloc {
    [_filename release];
    [_image release];
    [_embeddedImages release];
    [_animatedImage release];
    [_data release];
    [_dictionary release];
    [_uniqueIdentifier release];
    [super dealloc];
}

- (void)saveToFile:(NSString *)filename {
    NSBitmapImageFileType fileType = NSPNGFileType;
    if ([filename hasSuffix:@".bmp"]) {
        fileType = NSBMPFileType;
    } else if ([filename hasSuffix:@".gif"]) {
        fileType = NSGIFFileType;
    } else if ([filename hasSuffix:@".jp2"]) {
        fileType = NSJPEG2000FileType;
    } else if ([filename hasSuffix:@".jpg"] || [filename hasSuffix:@".jpeg"]) {
        fileType = NSJPEGFileType;
    } else if ([filename hasSuffix:@".png"]) {
        fileType = NSPNGFileType;
    } else if ([filename hasSuffix:@".tiff"]) {
        fileType = NSTIFFFileType;
    }

    NSData *data = nil;
    NSDictionary *universalTypeToCocoaMap = @{ (NSString *)kUTTypeBMP: @(NSBMPFileType),
                                               (NSString *)kUTTypeGIF: @(NSGIFFileType),
                                               (NSString *)kUTTypeJPEG2000: @(NSJPEG2000FileType),
                                               (NSString *)kUTTypeJPEG: @(NSJPEGFileType),
                                               (NSString *)kUTTypePNG: @(NSPNGFileType),
                                               (NSString *)kUTTypeTIFF: @(NSTIFFFileType) };
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

- (void)setImageFromImage:(iTermImage *)image data:(NSData *)data {
    [_dictionary release];
    _dictionary = nil;

    [_animatedImage autorelease];
    _animatedImage = [[iTermAnimatedImageInfo alloc] initWithImage:image];

    [_data autorelease];
    _data = [data retain];

    [_image autorelease];
    _image = [image retain];
}

- (NSString *)imageType {
    NSString *type = [_data uniformTypeIdentifierForImageData];
    if (type) {
        return type;
    }

    return (NSString *)kUTTypeImage;
}

- (NSDictionary *)dictionary {
    return @{ kImageInfoSizeKey: [NSValue valueWithSize:_size],
              kImageInfoInsetKey: [NSValue futureValueWithEdgeInsets:_inset],
              kImageInfoImageKey: _data ?: [NSData data],
              kImageInfoPreserveAspectRatioKey: @(_preserveAspectRatio),
              kImageInfoFilenameKey: _filename ?: @"",
              kImageInfoCodeKey: @(_code),
              kImageInfoBrokenKey: @(_broken) };
}


- (BOOL)animated {
    return !_paused && _animatedImage != nil;
}

- (void)setPaused:(BOOL)paused {
    _paused = paused;
    _animatedImage.paused = paused;
}

- (iTermImage *)image {
    [self loadFromDictionaryIfNeeded];
    return _image;
}

- (iTermAnimatedImageInfo *)animatedImage {
    [self loadFromDictionaryIfNeeded];
    return _animatedImage;
}

- (NSImage *)imageWithCellSize:(CGSize)cellSize {
    if (!self.image && !self.animatedImage) {
        return nil;
    }
    if (!_embeddedImages) {
        _embeddedImages = [[NSMutableDictionary alloc] init];
    }
    int frame = self.animatedImage.currentFrame;  // 0 if not animated
    NSImage *embeddedImage = _embeddedImages[@(frame)];

    NSSize region = NSMakeSize(cellSize.width * _size.width,
                               cellSize.height * _size.height);
    if (!NSEqualSizes(embeddedImage.size, region)) {
        NSImage *canvas = [[[NSImage alloc] init] autorelease];
        NSSize size;
        NSImage *theImage;
        if (self.animatedImage) {
            theImage = [self.animatedImage imageForFrame:frame];
        } else {
            theImage = [self.image.images firstObject];
        }
        if (!_preserveAspectRatio) {
            size = region;
        } else {
            double imageAR = theImage.size.width / theImage.size.height;
            double canvasAR = region.width / region.height;
            if (imageAR > canvasAR) {
                // image is wider than canvas, add black bars on top and bottom
                size = NSMakeSize(region.width, region.width / imageAR);
            } else {
                // image is taller than canvas, add black bars on sides
                size = NSMakeSize(region.height * imageAR, region.height);
            }
        }
        [canvas setSize:region];
        [canvas lockFocus];
        NSEdgeInsets inset = _inset;
        inset.top *= cellSize.height;
        inset.bottom *= cellSize.height;
        inset.left *= cellSize.width;
        inset.right *= cellSize.width;
        [theImage drawInRect:NSMakeRect((region.width - size.width) / 2 + inset.left,
                                        (region.height - size.height) / 2 + inset.bottom,
                                        MAX(0, size.width - inset.left - inset.right),
                                        MAX(0, size.height - inset.top - inset.bottom))];
        [canvas unlockFocus];

        self.embeddedImages[@(frame)] = canvas;
    }
    return _embeddedImages[@(frame)];
}

- (NSString *)nameForNewSavedTempFile {
    NSString *name = nil;
    if (_filename.pathExtension.length) {
        // The filename has an extension. Preserve its name in the tempfile's name,
        // and especially importantly, preserve its extension.
        NSString *suffix = [@"." stringByAppendingString:_filename.lastPathComponent];
        name = [[NSWorkspace sharedWorkspace] temporaryFileNameWithPrefix:@"iTerm2."
                                                                   suffix:suffix];
    } else {
        // Empty extension case. Try to guess the exetnsion.
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

- (NSPasteboardItem *)pasteboardItem {
    NSPasteboardItem *pbItem = [[[NSPasteboardItem alloc] init] autorelease];
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

#pragma mark - NSPasteboardItemDataProvider

- (void)pasteboard:(NSPasteboard *)pasteboard item:(NSPasteboardItem *)item provideDataForType:(NSString *)type {
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

@end
