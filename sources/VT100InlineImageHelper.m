//
//  VT100InlineImageHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/20.
//

#import "VT100InlineImageHelper.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermImage.h"
#import "iTermImageInfo.h"
#import "NSData+iTerm.h"
#import "NSImage+iTerm.h"
#import "ScreenChar.h"
#import "VT100Grid.h"

@interface VT100DecodedImage: NSObject
@property (nonatomic, strong, readonly) iTermImage *image;
@property (nullable, nonatomic, copy, readonly) NSData *data;
@property (nonatomic) BOOL isBroken;
@end

@implementation VT100DecodedImage

- (instancetype)initWithBase64String:(NSString *)base64String {
    self = [super init];
    if (self) {
        _data = [NSData dataWithBase64EncodedString:base64String];
        _image = [iTermImage imageWithCompressedData:_data];
        if (!_image) {
            [self broke];
        }
    }
    return self;
}

- (instancetype)initWithNativeImage:(NSImage *)nativeImage {
    self = [super init];
    if (self) {
        DLog(@"Image is native");
        _image = [iTermImage imageWithNativeImage:nativeImage];
        if (!_image) {
            [self broke];
        }
    }
    return self;
}

- (instancetype)initWithSixelData:(NSData *)sixelData {
    self = [super init];
    if (self) {
        _data = sixelData;
        _image = [iTermImage imageWithSixelData:_data];
        if (!_image) {
            [self broke];
        }
    }
    return self;
}

- (void)broke {
    _isBroken = YES;
    DLog(@"Image is broken");
    _image = [iTermImage imageWithNativeImage:[NSImage it_imageNamed:@"broken_image" forClass:self.class]];
    assert(_image);
}

@end

@interface VT100InlineImageHelper()
@property (nonatomic, copy) NSString *name;
@property (nonatomic) int width;
@property (nonatomic) VT100TerminalUnits widthUnits;
@property (nonatomic) int height;
@property (nonatomic) VT100TerminalUnits heightUnits;
@property (nonatomic) BOOL preserveAspectRatio;
@property (nonatomic) NSEdgeInsets inset;
@property (nonatomic) BOOL preconfirmed;
@property (nullable, nonatomic, strong) NSMutableString *base64String;
@property (nullable, nonatomic, strong) NSData *sixelData;
@property (nullable, nonatomic, strong) NSImage *nativeImage;
@property (nonatomic) CGFloat scaleFactor;
@end

@implementation VT100InlineImageHelper

- (instancetype)initWithName:(NSString *)name
                       width:(int)width
                  widthUnits:(VT100TerminalUnits)widthUnits
                      height:(int)height
                 heightUnits:(VT100TerminalUnits)heightUnits
                 scaleFactor:(CGFloat)scaleFactor
         preserveAspectRatio:(BOOL)preserveAspectRatio
                       inset:(NSEdgeInsets)inset
                        type:(NSString *)type
                preconfirmed:(BOOL)preconfirmed {
    self = [super init];
    if (self) {
        _name = [name copy];
        _width = width;
        _widthUnits = widthUnits;
        _height = height;
        _heightUnits = heightUnits;
        _preserveAspectRatio = preserveAspectRatio;
        _inset = inset;
        _type = [type copy];
        if ([iTermAdvancedSettingsModel retinaInlineImages]) {
            _scaleFactor = scaleFactor;
        } else {
            _scaleFactor = 1;
        }
        _base64String = [NSMutableString string];
    }
    return self;
}

- (instancetype)initWithSixelData:(NSData *)data
                      scaleFactor:(CGFloat)scaleFactor {
    self = [self initWithName:@"Sixel Image"
                        width:0
                   widthUnits:kVT100TerminalUnitsAuto
                       height:0
                  heightUnits:kVT100TerminalUnitsAuto
                  scaleFactor:scaleFactor
          preserveAspectRatio:YES
                        inset:NSEdgeInsetsZero
                         type:nil
                 preconfirmed:YES];
    if (self) {
        _sixelData = [data copy];
    }
    return self;
}

- (instancetype)initWithNativeImageNamed:(NSString *)name
                           spanningWidth:(int)width
                             scaleFactor:(CGFloat)scaleFactor {
    self = [self initWithName:name
                        width:width
                   widthUnits:kVT100TerminalUnitsCells
                       height:1
                  heightUnits:kVT100TerminalUnitsCells
                  scaleFactor:scaleFactor
          preserveAspectRatio:NO
                        inset:NSEdgeInsetsZero
                         type:nil
                 preconfirmed:YES];
    if (self) {
        _nativeImage = [NSImage it_imageNamed:name forClass:self.class];
    }
    return self;
}

#pragma mark - APIs

- (void)appendBase64EncodedData:(NSString *)data {
    const NSInteger lengthBefore = _base64String.length;
    [_base64String appendString: data];
    const NSInteger lengthAfter = _base64String.length;

    if (!_preconfirmed) {
        [self.delegate inlineImageConfirmBigDownloadWithBeforeSize:lengthBefore
                                                         afterSize:lengthAfter
                                                              name:_name ?: @"Unnamed file"];
    }
}

- (BOOL)filenameSmellsLikeText {
    return [[[iTermFileExtensionDB instance] languagesForPath:self.name] count] > 0;
}

- (BOOL)smellsLikeImage {
    if (self.type == nil) {
        if ([self filenameSmellsLikeText]) {
            return NO;
        }
        return YES;
    }
    if ([self.type hasPrefix:@"."]) {
        if ([[[iTermFileExtensionDB instance] languagesForExtension:[self.type substringFromIndex:1]] count]) {
            return NO;
        }

    }
    if ([[[iTermFileExtensionDB instance] languages] containsObject:self.type]) {
        // This assumes all languages it knows about are textual, not graphical.
        return NO;
    }
    if ([self.type hasPrefix:@"image/"] ||
        [self.type hasPrefix:@"video/"]) {
        return YES;
    }
    return NO;
}

- (BOOL)contentIsVeryLikelyText {
    NSData *data = [NSData dataWithBase64EncodedString:_base64String];
    NSString *text = [data stringWithEncoding:NSUTF8StringEncoding];
    return text != nil;
}

- (void)writeToGrid:(VT100Grid *)grid {
    if ([self smellsLikeImage]) {
        VT100DecodedImage *image = [self decodedImage];
        if (image.isBroken) {
            if ([self contentIsVeryLikelyText] && [self writeTextDocumentToGrid:grid]) {
                return;
            }
        }
        [self writeImage:image toGrid:grid];
        return;
    }
    const BOOL wroteAsText = [self writeTextDocumentToGrid:grid];
    if (wroteAsText) {
        return;
    }
    [self writeImageToGrid:grid];
}

- (BOOL)writeTextDocumentToGrid:(VT100Grid *)grid {
    DLog(@"Write text document %@ at %@", _name, VT100GridCoordDescription(grid.cursor));

    NSData *data = [NSData dataWithBase64EncodedString:_base64String];
    if (!data) {
        NSLog(@"Invalid base64 %@", _base64String);
        return NO;
    }
    NSString *contentString = [data stringWithEncoding:NSUTF8StringEncoding];
    if (!contentString) {
        NSLog(@"Not UTF-8 %@", data);
        return NO;
    }

    VT100GridAbsCoordRange range;
    range.start.y = [self.delegate inlineImageCursorAbsoluteCoord].y;
    range.start.x = 0;
    NSArray<NSString *> *lines = [contentString componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        [self.delegate inlineImageAppendStringAtCursor:line];
        [self.delegate inlineImageAppendLinefeed];
        grid.cursorX = 0;
    }


    range.end.y = [self.delegate inlineImageCursorAbsoluteCoord].y - 1;
    range.end.x = grid.size.width - 1;

    [self.delegate inlineImageDidCreateTextDocumentInRange:range
                                                      type:self.type
                                                  filename:_name];
    return YES;
}

- (void)writeImageToGrid:(VT100Grid *)grid {
    DLog(@"Write image %@ at %@", _name, VT100GridCoordDescription(grid.cursor));
    VT100DecodedImage *decodedImage = [self decodedImage];
    if (decodedImage.isBroken) {

    }
    [self writeImage:decodedImage toGrid:grid];
}

- (void)writeImage:(VT100DecodedImage *)decodedImage toGrid:(VT100Grid *)grid {
    DLog(@"Write decoded image %@ named %@ at %@", decodedImage, _name, VT100GridCoordDescription(grid.cursor));
    screen_char_t c;
    int width;
    int height;
    [self getScreenCharacter:&c
                       width:&width
                      height:&height
                        grid:grid
                decodedImage:decodedImage];

    [self writeBaseCharacter:c
                      toGrid:grid
                       width:width
                      height:height
                decodedImage:decodedImage];

    // Add a mark after the image. When the mark gets freed, it will release the image's memory.
    SetDecodedImage(c.code, decodedImage.image, decodedImage.data);
    [self.delegate inlineImageSetMarkOnScreenLine:grid.cursor.y + 1
                                             code:c.code];
    if (decodedImage.data) {
        [self.delegate inlineImageDidFinishWithImageData:decodedImage.data];
    }
}

#pragma mark - Decoding

- (VT100DecodedImage *)decodedImage {
    if (_nativeImage) {
        DLog(@"Image is native");
        assert(_base64String.length == 0);
        assert(!_sixelData);
        return [[VT100DecodedImage alloc] initWithNativeImage:_nativeImage];
    }
    if (_sixelData) {
        DLog(@"Image is sixel");
        assert(_base64String.length == 0);
        return [[VT100DecodedImage alloc] initWithSixelData:_sixelData];
    }
    DLog(@"Image was base-64 encoded");
    return [[VT100DecodedImage alloc] initWithBase64String:_base64String];
}

#pragma mark - Size Calculation

- (NSSize)scaledSizeForDecodedImage:(VT100DecodedImage *)decodedImage {
    NSSize scaledSize = decodedImage.image.size;
    scaledSize.width /= _scaleFactor;
    scaledSize.height /= _scaleFactor;
    return scaledSize;
}

- (BOOL)getRequestedWidthInPoints:(CGFloat *)requestedWidthInPointsPtr
                            width:(int *)widthPtr
                             grid:(VT100Grid *)grid
                       scaledSize:(NSSize)scaledSize
                         cellSize:(NSSize)cellSize {
    const VT100GridSize gridSize = grid.sizeRespectingRegionConditionally;
    switch (_widthUnits) {
        case kVT100TerminalUnitsPixels:
            *widthPtr = ceil((double)_width / (cellSize.width * _scaleFactor));
            *requestedWidthInPointsPtr = _width / _scaleFactor;
            return NO;

        case kVT100TerminalUnitsPercentage: {
            const double fraction = (double)MAX(MIN(100, _width), 0) / 100.0;
            *widthPtr = ceil((double)gridSize.width * fraction);
            *requestedWidthInPointsPtr = gridSize.width * cellSize.width * fraction;
            return NO;
        }

        case kVT100TerminalUnitsCells:
            *widthPtr = _width;
            *requestedWidthInPointsPtr = _width * cellSize.width;
            return NO;

        case kVT100TerminalUnitsAuto:
            if (_heightUnits == kVT100TerminalUnitsAuto) {
                *widthPtr = ceil((double)scaledSize.width / cellSize.width);
                *requestedWidthInPointsPtr = scaledSize.width;
                return NO;
            }
            *requestedWidthInPointsPtr = 0;
            *widthPtr = _width;
            return YES;
    }
}

- (void)getRequestedHeightInPoints:(CGFloat *)requestedHeightInPointsPtr
                            height:(int *)heightPtr
                             grid:(VT100Grid *)grid
                       widthPoints:(CGFloat)widthPoints
                        scaledSize:(NSSize)scaledSize
                          cellSize:(NSSize)cellSize {
    switch (_heightUnits) {
        case kVT100TerminalUnitsPixels:
            *heightPtr = ceil((double)_height / (cellSize.height * _scaleFactor));
            *requestedHeightInPointsPtr = _height / _scaleFactor;
            break;

        case kVT100TerminalUnitsPercentage: {
            const double fraction = (double)MAX(MIN(100, _height), 0) / 100.0;
            *heightPtr = ceil((double)grid.sizeRespectingRegionConditionally.height * fraction);
            *requestedHeightInPointsPtr = grid.sizeRespectingRegionConditionally.height * cellSize.height * fraction;
            break;
        }
        case kVT100TerminalUnitsCells:
            *heightPtr = _height;
            *requestedHeightInPointsPtr = _height * cellSize.height;
            break;

        case kVT100TerminalUnitsAuto:
            if (_widthUnits == kVT100TerminalUnitsAuto) {
                *heightPtr = ceil((double)scaledSize.height / cellSize.height);
                *requestedHeightInPointsPtr = scaledSize.height;
            } else {
                double aspectRatio = scaledSize.width / scaledSize.height;
                const CGFloat heightPoints = widthPoints / aspectRatio;
                *heightPtr = ceil(heightPoints / cellSize.height);
                *requestedHeightInPointsPtr = heightPoints;
            }
            break;
    }
}

- (void)getRequestedWidthInPoints:(CGFloat *)requestedWidthInPointsPtr
                   automaticWidth:(int *)widthPtr
                        forHeight:(CGFloat)heightPoints
                       scaledSize:(NSSize)scaledSize
                         cellSize:(NSSize)cellSize {
    const CGFloat aspectRatio = scaledSize.width / scaledSize.height;
    const CGFloat widthInPoints = ((CGFloat)heightPoints * aspectRatio);
    *widthPtr = round(widthInPoints / cellSize.width);
    *requestedWidthInPointsPtr = widthInPoints;
}

- (void)getRequestedWidthInPoints:(CGFloat *)requestedWidthInPointsPtr
                            width:(int *)widthPtr
          requestedHeightInPoints:(CGFloat *)requestedHeightInPointsPtr
                           height:(int *)heightPtr
                             grid:(VT100Grid *)grid
                       scaledSize:(NSSize)scaledSize
                         cellSize:(NSSize)cellSize {
    const BOOL needsWidth = [self getRequestedWidthInPoints:requestedWidthInPointsPtr
                                                      width:widthPtr
                                                       grid:grid
                                                 scaledSize:scaledSize
                                                   cellSize:cellSize];
    [self getRequestedHeightInPoints:requestedHeightInPointsPtr
                              height:heightPtr
                                grid:grid
                         widthPoints:*requestedWidthInPointsPtr
                          scaledSize:scaledSize
                            cellSize:cellSize];


    if (needsWidth) {
        [self getRequestedWidthInPoints:requestedWidthInPointsPtr
                         automaticWidth:widthPtr
                              forHeight:*requestedHeightInPointsPtr
                             scaledSize:scaledSize
                               cellSize:cellSize];
    }

    *widthPtr = MAX(1, *widthPtr);
    *heightPtr = MAX(1, *heightPtr);

    const CGFloat maxWidth = grid.sizeRespectingRegionConditionally.width - grid.cursorX;
    // If the requested size is too large, scale it down to fit.
    if (*widthPtr > maxWidth) {
        const CGFloat scale = maxWidth / (double)*widthPtr;
        *widthPtr = grid.sizeRespectingRegionConditionally.width;
        *heightPtr *= scale;
        *heightPtr = MAX(1, *heightPtr);
        *requestedWidthInPointsPtr = *widthPtr * cellSize.width;
        *requestedHeightInPointsPtr = *heightPtr * cellSize.height;
    }

    // Height is capped at 255 because only 8 bits are used to represent the line number of a cell
    // within the image.
    CGFloat maxHeight = 255;
    if (*heightPtr > maxHeight) {
        const CGFloat scale = (double)*heightPtr / maxHeight;
        *heightPtr = maxHeight;
        *widthPtr *= scale;
        *widthPtr = MAX(1, *widthPtr);
        *requestedWidthInPointsPtr = *widthPtr * cellSize.width;
        *requestedHeightInPointsPtr = *heightPtr * cellSize.height;
    }
}

#pragma mark - Insets

- (NSEdgeInsets)insetsForWidthInPoints:(CGFloat)requestedWidthInPoints
                          widthInCells:(int)width
                        heightInPoints:(CGFloat)requestedHeightInPoints
                         heightInCells:(int)height
                              cellSize:(NSSize)cellSize {
    NSEdgeInsets inset = _inset;

    // Tweak the insets to get the exact size the user requested.
    if (requestedWidthInPoints < width * cellSize.width) {
        inset.right += (width * cellSize.width - requestedWidthInPoints);
    }
    if (requestedHeightInPoints < height * cellSize.height) {
        inset.bottom += (height * cellSize.height - requestedHeightInPoints);
    }

    return inset;
}

- (NSEdgeInsets)fractionalInsetForInset:(NSEdgeInsets)inset
                            desiredSize:(NSSize)desiredSize
                               cellSize:(NSSize)cellSize
                           decodedImage:(VT100DecodedImage *)decodedImage
                                  width:(int)width
                                 height:(int)height {
    if (_preserveAspectRatio) {
        // Pick an inset that preserves the exact dimensions of the original image.
        return [iTermImageInfo fractionalInsetsForPreservedAspectRatioWithDesiredSize:desiredSize
                                                                         forImageSize:decodedImage.image.size
                                                                             cellSize:cellSize
                                                                        numberOfCells:NSMakeSize(width, height)];
    }
    return [iTermImageInfo fractionalInsetsStretchingToDesiredSize:desiredSize
                                                         imageSize:decodedImage.image.size
                                                          cellSize:cellSize
                                                     numberOfCells:NSMakeSize(width, height)];
}

#pragma mark - Grid Twiddling

- (screen_char_t)screenCharacterForWidthInPoints:(CGFloat)requestedWidthInPoints
                                    widthInCells:(int)width
                                  heightInPoints:(CGFloat)requestedHeightInPoints
                                   heightInCells:(int)height
                                        cellSize:(NSSize)cellSize
                                    decodedImage:(VT100DecodedImage *)decodedImage {
    const NSEdgeInsets inset = [self insetsForWidthInPoints:requestedWidthInPoints
                                               widthInCells:width
                                             heightInPoints:requestedHeightInPoints
                                              heightInCells:height
                                                   cellSize:cellSize];
    const NSEdgeInsets fractionalInset = [self fractionalInsetForInset:inset
                                                           desiredSize:NSMakeSize(requestedWidthInPoints,
                                                                                  requestedHeightInPoints)
                                                              cellSize:cellSize
                                                          decodedImage:decodedImage
                                                                 width:width
                                                                height:height];
    return ImageCharForNewImage(_name,
                                width,
                                height,
                                _preserveAspectRatio,
                                fractionalInset);
}

- (void)writeBaseCharacter:(screen_char_t)screenChar
                    toGrid:(VT100Grid *)grid
                     width:(int)width
                    height:(int)height
              decodedImage:(VT100DecodedImage *)decodedImage {
    iTermImageInfo *imageInfo = GetMutableImageInfo(screenChar.code);
    imageInfo.broken = decodedImage.isBroken;
    DLog(@"Append %d rows of image characters with %d columns. The value of c.image is %@", height, width, @(screenChar.image));
    const int xOffset = grid.cursorX;
    const int screenWidth = grid.sizeRespectingRegionConditionally.width;
    screen_char_t c = screenChar;
    for (int y = 0; y < height; y++) {
        if (y > 0) {
            [self.delegate inlineImageAppendLinefeed];
        }
        for (int x = xOffset; x < xOffset + width && x < screenWidth; x++) {
            SetPositionInImageChar(&c, x - xOffset, y);
            // DLog(@"Set character at %@,%@: %@", @(x), @(currentGrid_.cursorY), DebugStringForScreenChar(c));
            [grid setCharsFrom:VT100GridCoordMake(x, grid.cursorY)
                            to:VT100GridCoordMake(x, grid.cursorY)
                        toChar:c
            externalAttributes:nil];
        }
    }
    grid.cursorX = grid.cursorX + width;
}

- (void)getScreenCharacter:(screen_char_t *)cPtr
                     width:(int *)widthPtr
                    height:(int *)heightPtr
                      grid:(VT100Grid *)grid
              decodedImage:(VT100DecodedImage *)decodedImage {
    const NSSize scaledSize = [self scaledSizeForDecodedImage:decodedImage];
    const NSSize cellSize = [self.delegate inlineImageCellSize];

    CGFloat requestedWidthInPoints = 0;
    int width = _width;
    CGFloat requestedHeightInPoints = 0;
    int height = _height;
    [self getRequestedWidthInPoints:&requestedWidthInPoints
                              width:&width
            requestedHeightInPoints:&requestedHeightInPoints
                             height:&height
                               grid:grid
                         scaledSize:scaledSize
                           cellSize:cellSize];

    // TODO: Support scroll regions.

    screen_char_t c = [self screenCharacterForWidthInPoints:requestedWidthInPoints
                                               widthInCells:width
                                             heightInPoints:requestedHeightInPoints
                                              heightInCells:height
                                                   cellSize:cellSize
                                               decodedImage:decodedImage];
    *cPtr = c;
    *widthPtr = width;
    *heightPtr = height;
}

@end
