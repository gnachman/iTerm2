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

+ (NSUInteger)keyForColor:(vector_float4)color {
    const NSUInteger r = color.x * 255;
    const NSUInteger g = color.y * 255;
    const NSUInteger b = color.z * 255;
    return (r << 24) | (g << 16) | (b << 8);
}

+ (NSUInteger)keyForForegroundColor:(vector_float4)foregroundColor
                    backgroundColor:(vector_float4)backgroundColor {
    return ([self keyForColor:foregroundColor] << 32) | [self keyForColor:backgroundColor];
}

- (instancetype)initWithForegroundColor:(vector_float4)foregroundColor
                        backgroundColor:(vector_float4)backgroundColor {
    if (self) {
        _table = [NSMutableData dataWithLength:3 * 256 * sizeof(unsigned char)];
        _foregroundColor = foregroundColor;
        _backgroundColor = backgroundColor;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p fg=(%f, %f, %f) bg=(%f, %f, %f)>",
                       NSStringFromClass(self.class), self,
                       _foregroundColor.x,
                       _foregroundColor.y,
                       _foregroundColor.z,
                       _backgroundColor.x,
                       _backgroundColor.y,
                       _backgroundColor.z];
}

- (NSUInteger)key {
    return [iTermSubpixelModel keyForForegroundColor:_foregroundColor
                                     backgroundColor:_backgroundColor];
}

- (NSString *)dump {
    NSMutableArray *array = [NSMutableArray array];
    const unsigned char *bytes = (const unsigned char *)_table.bytes;
    for (int i = 0; i < 256 * 3; i += 3) {
        NSString *s = [NSString stringWithFormat:@"%@ -> (%@, %@, %@)", @(i / 3), @(bytes[i]), @(bytes[i+1]), @(bytes[i+2])];
        [array addObject:s];
    }
    return [array componentsJoinedByString:@"\n"];
}

- (NSMutableData *)mutableTable {
    return _table;
}

@end

@implementation iTermSubpixelModelBuilder {
    // Maps the index of a color in the reference image to the color in the reference image.
    // An index is 4 * (x + width * y).
    // A color is ((r << 16) | (g << 8) | b).
    std::unordered_map<int, int> *_indexToReferenceColor;

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
    assert(ok);

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

    // TODO: could use extended srgb on macOS 10.12+
    CGContextSetFillColorSpace(ctx, CGColorSpaceCreateWithName(kCGColorSpaceSRGB));
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
                const int b = bytes[i];
                const int g = bytes[i + 1];
                const int r = bytes[i + 2];
                const int c = ((b << 16) | (g << 8) | r);
                if (referenceColors.insert(c).second) {
                    // The color `c` has not been seen before. Remember it and its index.
                    (*_indexToReferenceColor)[i] = c;
                }
                i += 4;
            }
        }
    }
    return self;
}

- (iTermSubpixelModel *)modelForForegoundColor:(vector_float4)foregroundColor
                               backgroundColor:(vector_float4)backgroundColor {
    NSUInteger key = [iTermSubpixelModel keyForForegroundColor:foregroundColor
                                               backgroundColor:backgroundColor];
    iTermSubpixelModel *cachedModel = _models[@(key)];
    if (cachedModel) {
        return cachedModel;
    }

    assert(backgroundColor.w == 1);
    NSData *imageData = [iTermSubpixelModelBuilder dataForImageWithForegroundColor:foregroundColor
                                                                   backgroundColor:backgroundColor];

    // Maps a reference color to a model color. We'll go back and fill in the gaps with linear
    // interpolations, which is why we use a sorted container. When translating a black-on-white
    // render to a color render, these mapping tables let us look up the proper color for a black
    // on white sample.
    std::map<unsigned char, unsigned char> redMap;
    std::map<unsigned char, unsigned char> greenMap;
    std::map<unsigned char, unsigned char> blueMap;
    const unsigned char *bytes = (const unsigned char *)imageData.bytes;
    for (auto kv : *_indexToReferenceColor) {
        auto index = kv.first;
        auto color = kv.second;

        const unsigned char refRed = (color & 0xff);
        const unsigned char refGreen = ((color >> 8) & 0xff);
        const unsigned char refBlue = ((color >> 16) & 0xff);

        const unsigned char modelRed = bytes[index + 2];
        const unsigned char modelGreen = bytes[index + 1];
        const unsigned char modelBlue = bytes[index];

        redMap[refRed] = modelRed;
        greenMap[refGreen] = modelGreen;
        blueMap[refBlue] = modelBlue;
    }

    iTermSubpixelModel *model = [[iTermSubpixelModel alloc] initWithForegroundColor:foregroundColor
                                                                    backgroundColor:backgroundColor];
    DLog(@"Interpolate red values");
    [self interpolateValuesInMap:&redMap toByteArrayInData:model.mutableTable offset:0 stride:3];
    DLog(@"Interpolate green values");
    [self interpolateValuesInMap:&greenMap toByteArrayInData:model.mutableTable offset:1 stride:3];
    DLog(@"Interpolate blue values");
    [self interpolateValuesInMap:&blueMap toByteArrayInData:model.mutableTable offset:2 stride:3];
    _models[@(key)] = model;
    return model;
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
        DLog(@"Reference color %d -> model color %d", referenceColor, modelColor);

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
