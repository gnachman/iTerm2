//
//  iTermSubpixelModelBuilder.m
//  subpixel
//
//  Created by George Nachman on 10/16/17.
//  Copyright © 2017 George Nachman. All rights reserved.
//

#import "iTermSubpixelModelBuilder.h"
extern "C" {
#import "DebugLogging.h"
}
#import <Cocoa/Cocoa.h>

#import "NSColor+iTerm.h"
#import "NSImage+iTerm.h"
#include <map>
#include <unordered_map>
#include <unordered_set>


static const CGSize iTermSubpixelModelSize = { 80, 80 };
static NSString *const iTermSubpixelModelString = @"O";

@interface iTermSubpixelModel()
@property (nonatomic, readonly) NSMutableData *mutableTable;
@end

@implementation iTermSubpixelModel {
    NSMutableData *_table;
}

+ (NSUInteger)keyForColor:(float)color {
    return color * 255;
}

+ (NSUInteger)keyForForegroundColor:(float)foregroundColor
                    backgroundColor:(float)backgroundColor {
    return ([self keyForColor:foregroundColor] << 8) | [self keyForColor:backgroundColor];
}

- (instancetype)initWithForegroundColor:(float)foregroundColor
                        backgroundColor:(float)backgroundColor {
    if (self) {
        _table = [NSMutableData dataWithLength:256 * sizeof(unsigned char)];
        _foregroundColor = foregroundColor;
        _backgroundColor = backgroundColor;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p fg=%f bg=%f>",
            NSStringFromClass(self.class), self,
            _foregroundColor,
            _backgroundColor];
}

- (NSUInteger)key {
    return [iTermSubpixelModel keyForForegroundColor:_foregroundColor
                                     backgroundColor:_backgroundColor];
}

- (NSString *)dump {
    NSMutableArray *array = [NSMutableArray array];
    const unsigned char *bytes = (const unsigned char *)_table.bytes;
    for (int i = 0; i < 256; i++) {
        NSString *s = [NSString stringWithFormat:@"%@ -> (%@)", @(i / 3), @(bytes[i])];
        [array addObject:s];
    }
    return [array componentsJoinedByString:@"\n"];
}

- (NSMutableData *)mutableTable {
    return _table;
}

@end

@implementation iTermSubpixelModelBuilder {
    // Maps the index of a color element (which may be red, green or blue) in
    // the reference image to the value of that element in the reference image.
    // For example, if the first pixel had a blue value of 128, this would contain
    // 0->128. The values in this map are unique.
    std::unordered_map<int, int> *_indexToReferenceColor;

    // Cache of models that have already been built.
    NSMutableDictionary<NSNumber *, iTermSubpixelModel *> *_models;
}

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static id instance;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

+ (NSData *)dataForImageWithForegroundColor:(vector_float4)foregroundColor
                            backgroundColor:(vector_float4)backgroundColor {
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL,
                                             iTermSubpixelModelSize.width,
                                             iTermSubpixelModelSize.height,
                                             8,
                                             iTermSubpixelModelSize.width * 4,
                                             colorSpace,
                                             kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    CGColorSpaceRelease(colorSpace);

    CGContextSetRGBFillColor(ctx, backgroundColor.x, backgroundColor.y, backgroundColor.z, backgroundColor.w);
    CGContextFillRect(ctx, CGRectMake(0, 0, iTermSubpixelModelSize.width, iTermSubpixelModelSize.height));

    NSFont *font = [NSFont fontWithName:@"Monaco" size:12];
    CGFloat foreground[4] = { foregroundColor.x, foregroundColor.y, foregroundColor.z, foregroundColor.w };
    [self drawString:iTermSubpixelModelString
                font:font
                size:iTermSubpixelModelSize
          components:foreground
             context:ctx];
    NSData *data = [NSData dataWithBytes:CGBitmapContextGetData(ctx)
                                  length:iTermSubpixelModelSize.width * iTermSubpixelModelSize.height * 4];
    CGContextRelease(ctx);
    return data;
}

+ (void)drawString:(NSString *)string
              font:(NSFont *)font
              size:(CGSize)size
        components:(CGFloat *)components
           context:(CGContextRef)ctx {
    CGGlyph glyphs[string.length];
    const NSUInteger numCodes = string.length;
    unichar characters[numCodes];
    [string getCharacters:characters];
    BOOL ok = CTFontGetGlyphsForCharacters((CTFontRef)font,
                                           characters,
                                           glyphs,
                                           numCodes);
    ITDebugAssert(ok);
    if (!ok) {
        return;
    }
    size_t length = numCodes;

    // Note: this is slow. It was faster than core text when I did it rarely, but I'm not sure if
    // it's still faster to use the deprecated CG API now.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CGContextSelectFont(ctx,
                        [[font fontName] UTF8String],
                        [font pointSize],
                        kCGEncodingMacRoman);
#pragma clang diagnostic pop

    CGColorSpaceRef cgColorSpace = [[NSColorSpace it_defaultColorSpace] CGColorSpace];
    CGContextSetFillColorSpace(ctx, cgColorSpace);
    CGContextSetFillColor(ctx, components);

    CGContextSetAllowsFontSubpixelQuantization(ctx, YES);
    CGContextSetShouldSubpixelQuantizeFonts(ctx, YES);
    CGContextSetAllowsFontSubpixelPositioning(ctx, YES);
    CGContextSetShouldSubpixelPositionFonts(ctx, YES);
    CGContextSetShouldSmoothFonts(ctx, YES);

    CGContextSetTextDrawingMode(ctx, kCGTextFill);

    // A hack to make the glyph fill the provided space
    const CGFloat scale = size.height / 11;
    double y = -(-(floorf(font.leading) - floorf(font.descender + 0.5)));
    // Flip vertically and translate to (x, y).
    CGContextSetTextMatrix(ctx, CGAffineTransformMake(scale,  0.0,
                                                      0, scale,
                                                      0, y));
    CGContextSetAllowsAntialiasing(ctx, YES);
    CGContextSetShouldAntialias(ctx, YES);

    CGPoint points[length];
    for (int i = 0; i < length; i++) {
        points[i].x = 0;
        points[i].y = 0;
    }
    CGContextShowGlyphsAtPositions(ctx, glyphs, points, length);
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _models = [NSMutableDictionary dictionary];
        _indexToReferenceColor = new std::unordered_map<int, int>();
        NSData *referenceImageData = [iTermSubpixelModelBuilder dataForImageWithForegroundColor:vector4(0.0f, 0.0f, 0.0f, 1.0f)
                                                                                backgroundColor:vector4(1.0f, 1.0f, 1.0f, 1.0f)];
        std::unordered_set<int> referenceColors;
        const unsigned char *bytes = (const unsigned char *)referenceImageData.bytes;
        int i = 0;
        for (int y = 0; y < iTermSubpixelModelSize.height; y++) {
            for (int x = 0; x < iTermSubpixelModelSize.width; x++) {
                int value = bytes[i];
                for (int j = 0; j < 3; j++) {
                    if (referenceColors.insert(value).second) {
                        (*_indexToReferenceColor)[i] = value;
                    }
                    i++;
                }

                // Skip over alpha
                i++;
            }
        }
    }
    return self;
}

- (iTermSubpixelModel *)modelForForegroundColor:(float)foregroundComponent
                                backgroundColor:(float)backgroundComponent {
    @synchronized (self) {
        NSUInteger key = [iTermSubpixelModel keyForForegroundColor:foregroundComponent
                                               backgroundColor:backgroundComponent];
        iTermSubpixelModel *cachedModel = _models[@(key)];
        if (cachedModel) {
            return cachedModel;
        }

        NSData *imageData = [iTermSubpixelModelBuilder dataForImageWithForegroundColor:simd_make_float4(foregroundComponent, foregroundComponent, foregroundComponent, 1)
                                                                       backgroundColor:simd_make_float4(backgroundComponent, backgroundComponent, backgroundComponent, 1)];
        // Maps a reference color to a model color. We'll go back and fill in the gaps with linear
        // interpolations, which is why we use a sorted container. When translating a black-on-white
        // render to a color render, these mapping tables let us look up the proper color for a black
        // on white sample.
        std::map<unsigned char, unsigned char> map;
        const unsigned char *bytes = (const unsigned char *)imageData.bytes;
        for (auto kv : *_indexToReferenceColor) {
            auto index = kv.first;
            auto color = kv.second;

            const unsigned char ref = (color & 0xff);
            const unsigned char model = bytes[index];

            map[ref] = model;
        }

        iTermSubpixelModel *subpixelModel = [[iTermSubpixelModel alloc] initWithForegroundColor:foregroundComponent
                                                                                backgroundColor:backgroundComponent];
        [self interpolateValuesInMap:&map toByteArrayInData:subpixelModel.mutableTable offset:0 stride:1];
        if (backgroundComponent == 0) {
            DLog(@"Generated model for %f/%f", foregroundComponent, backgroundComponent);
        }
        //NSLog(@"Generated model for %f/%f\n%@", foregroundComponent, backgroundComponent, subpixelModel.table);
        _models[@(key)] = subpixelModel;
        return subpixelModel;
    }
}

- (void)writeDebugDataToFolder:(NSString *)folder
               foregroundColor:(float)foregroundComponent
               backgroundColor:(float)backgroundComponent {
    NSData *imageData = [iTermSubpixelModelBuilder dataForImageWithForegroundColor:simd_make_float4(foregroundComponent,
                                                                                                    foregroundComponent,
                                                                                                    foregroundComponent,
                                                                                                    1)
                                                                   backgroundColor:simd_make_float4(backgroundComponent,
                                                                                                    backgroundComponent,
                                                                                                    backgroundComponent,
                                                                                                    1)];
    NSString *name = [NSString stringWithFormat:@"SubpixelImage.f_%02x.b_%02x.dat",
                      static_cast<int>(foregroundComponent * 255), static_cast<int>(backgroundComponent * 255)];
    [imageData writeToFile:[folder stringByAppendingPathComponent:name] atomically:NO];

    NSImage *image = [NSImage imageWithRawData:imageData
                                          size:iTermSubpixelModelSize
                                 bitsPerSample:8
                               samplesPerPixel:4
                                      hasAlpha:YES
                                colorSpaceName:NSDeviceRGBColorSpace];
    NSString *imageName = [NSString stringWithFormat:@"SubpixelImage.f_%02x.b_%02x.png",
                           static_cast<int>(foregroundComponent * 255), static_cast<int>(backgroundComponent * 255)];
    [[image dataForFileOfType:NSBitmapImageFileTypePNG] writeToFile:[folder stringByAppendingPathComponent:imageName] atomically:NO];
}

- (void)dealloc {
    delete _indexToReferenceColor;
}

namespace iTerm2 {
    void Backfill(double slope, int previousReferenceColor, double value, size_t stride, unsigned char *output) {
        // Backfill from this value to a reference color of 0
        double backfillSlope = -slope;
        if (value + backfillSlope * previousReferenceColor < 0) {
            backfillSlope = previousReferenceColor / -value;
        }
        double backfillValue = value;
        DLog(@"Backfill [0, %d] with values [%f, %f]", previousReferenceColor, MAX(0, backfillValue + backfillSlope * previousReferenceColor), backfillValue);
        for (int i = previousReferenceColor; i >= 0; i--) {
            output[i * stride] = MAX(0, round(backfillValue));
            backfillValue += backfillSlope;
        }
    }

    void Fill(double slope, double value, int previousReferenceColor, int referenceColor, size_t stride, unsigned char *output) {
        // Fill between this color and the previous reference color
        DLog(@"Fill range [%d, %d] with values [%f, %f]", previousReferenceColor, referenceColor, value, value + slope * (referenceColor - previousReferenceColor));
        for (int i = previousReferenceColor; i <= referenceColor; i++) {
            output[i * stride] = value;
            value += slope;
        }
    }
}

- (void)interpolateValuesInMap:(std::map<unsigned char, unsigned char> *)modelToReferenceMap
             toByteArrayInData:(NSMutableData *)destinationData
                        offset:(size_t)offset
                        stride:(size_t)stride {
    int previousModelColor = -1;
    int previousReferenceColor = -1;
    BOOL first = YES;
    double slope = 0;
    unsigned char *output = (unsigned char *)destinationData.mutableBytes;
    output += offset;
    for (auto kv : *modelToReferenceMap) {
        const int referenceColor = kv.first;
        const int modelColor = kv.second;
//        NSLog(@"%d -> %d", referenceColor, modelColor);

        if (previousModelColor >= 0) {
            slope = static_cast<double>(modelColor - previousModelColor) / static_cast<double>(referenceColor - previousReferenceColor);
            double value = previousModelColor;
            if (first) {
                iTerm2::Backfill(slope, previousReferenceColor, modelColor, stride, output);
                first = NO;
            }
            iTerm2::Fill(slope, value, previousReferenceColor, referenceColor, stride, output);
        }
        previousModelColor = modelColor;
        previousReferenceColor = referenceColor;
    }

    // Fill forward from the last reference color to the end
    const double value = previousModelColor;
    const int distanceLeft = (255 - previousReferenceColor);
    if (value + slope * distanceLeft > 255) {
        slope = (255 - value) / distanceLeft;
    }
    iTerm2::Fill(slope, value, previousReferenceColor, 255, stride, output);
}

@end
