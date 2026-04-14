#import "iTermBackgroundColorRLETestHelper.h"
#import "iTermMetalPerFrameState.h"
#import "iTermColorMap.h"

// Minimal mock that provides the methods iTermGetMetalBackgroundColors
// calls on its "self" parameter via ObjC message dispatch.
@interface iTermBGColorRLEMockPerFrameState : NSObject
@end

@implementation iTermBGColorRLEMockPerFrameState

- (vector_float4)unprocessedColorForBackgroundColorKey:(void *)colorKey
                                             isDefault:(BOOL *)isDefault {
    *isDefault = YES;
    return simd_make_float4(0.1f, 0.1f, 0.1f, 1.0f);
}

@end

// Minimal mock for id<iTermColorMapReading>.
@interface iTermBGColorRLEMockColorMap : NSObject <iTermColorMapReading>
@end

@implementation iTermBGColorRLEMockColorMap

@synthesize darkMode = _darkMode;
@synthesize dimOnlyText = _dimOnlyText;
@synthesize faintTextAlpha = _faintTextAlpha;
@synthesize generation = _generation;
@synthesize harmonize = _harmonize;
@synthesize useSeparateColorsForLightAndDarkMode = _useSeparateColorsForLightAndDarkMode;

- (vector_float4)fastProcessedBackgroundColorForBackgroundColor:(vector_float4)color {
    return color;
}

- (BOOL)darkBackground { return NO; }
- (CGFloat)minimumContrast { return 0; }
- (CGFloat)dimmingAmount { return 0; }
- (CGFloat)mutingAmount { return 0; }
- (NSColor *)colorForKey:(iTermColorMapKey)key { return [NSColor blackColor]; }
- (NSColor *)dimmedColorForKey:(iTermColorMapKey)key { return [NSColor blackColor]; }

- (nonnull id)copyWithZone:(nullable NSZone *)zone { return self; }
- (vector_float4)fastColorForKey:(iTermColorMapKey)theKey { return simd_make_float4(0, 0, 0, 1); }
- (vector_float4)fastColorForKey:(iTermColorMapKey)theKey colorSpace:(NSColorSpace *)colorSpace { return simd_make_float4(0, 0, 0, 1); }
- (NSColor *)processedTextColorForTextColor:(NSColor *)textColor overBackgroundColor:(NSColor *)backgroundColor disableMinimumContrast:(BOOL)disableMinimumContrast { return textColor; }
- (NSColor *)processedBackgroundColorForBackgroundColor:(NSColor *)color { return color; }
- (NSColor *)colorByMutingColor:(NSColor *)color { return color; }
- (vector_float4)fastColorByMutingColor:(vector_float4)color { return color; }
- (NSColor *)colorByDimmingTextColor:(NSColor *)color { return color; }
- (NSString *)profileKeyForColorMapKey:(int)theKey { return @""; }
- (NSString *)profileKeyForBaseKey:(NSString *)baseKey { return baseKey; }
- (iTermColorMapKey)keyForSystemMessageForBackground:(BOOL)background { return 0; }
- (NSDictionary<NSNumber *, NSString *> *)colormapKeyToProfileKeyDictionary { return @{}; }
- (iTermColorMapKey)keyForColor:(int)theIndex green:(int)green blue:(int)blue colorMode:(ColorMode)theMode bold:(BOOL)isBold isBackground:(BOOL)isBackground useCustomBoldColor:(BOOL)useCustomBoldColor brightenBold:(BOOL)brightenBold { return 0; }
- (NSColor *)colorForCode:(int)theIndex green:(int)green blue:(int)blue colorMode:(ColorMode)theMode bold:(BOOL)isBold faint:(BOOL)isFaint isBackground:(BOOL)isBackground useCustomBoldColor:(BOOL)useCustomBoldColor brightenBold:(BOOL)brightenBold { return [NSColor blackColor]; }
- (iTermColorMap *)copy { return (iTermColorMap *)self; }
- (VT100SavedColorsSlot *)savedColorsSlot { return nil; }

@end

// Minimal mock for iTermBidiDisplayInfo. Responds to -lut and -numberOfCells
// which are the only methods iTermGetMetalBackgroundColors calls on it.
@interface iTermBGColorRLEMockBidiInfo : NSObject {
    int *_lut;
    int _count;
}
@end

@implementation iTermBGColorRLEMockBidiInfo

- (instancetype)initWithLUT:(const int *)lut length:(int)length {
    self = [super init];
    if (self) {
        _count = length;
        _lut = malloc(length * sizeof(int));
        memcpy(_lut, lut, length * sizeof(int));
    }
    return self;
}

- (void)dealloc {
    free(_lut);
}

- (const int *)lut { return _lut; }
- (int)numberOfCells { return _count; }

@end

@implementation iTermBackgroundColorRLETestHelper

- (int)buildRLEsForLine:(const screen_char_t *)line
                   width:(int)width
                 results:(iTermTestBackgroundRLE *)results
                 maxResults:(int)maxResults
                 bidiLUT:(const int *)bidiLUT
              bidiLUTLen:(int)bidiLUTLen
           lineAttribute:(iTermLineAttribute)lineAttribute {
    iTermMetalBackgroundColorRLE *rles =
        calloc(width, sizeof(iTermMetalBackgroundColorRLE));
    int maxVisual = width;
    for (int i = 0; i < bidiLUTLen; i++) {
        if (bidiLUT[i] + 1 > maxVisual) {
            maxVisual = bidiLUT[i] + 1;
        }
    }
    iTermMetalGlyphAttributes *attributes =
        calloc(maxVisual, sizeof(iTermMetalGlyphAttributes));
    vector_float4 *unprocessed = calloc(width, sizeof(vector_float4));

    iTermBGColorRLEMockPerFrameState *mockSelf =
        [[iTermBGColorRLEMockPerFrameState alloc] init];
    iTermBGColorRLEMockColorMap *mockColorMap =
        [[iTermBGColorRLEMockColorMap alloc] init];

    iTermBGColorRLEMockBidiInfo *mockBidi = nil;
    if (bidiLUT) {
        mockBidi = [[iTermBGColorRLEMockBidiInfo alloc] initWithLUT:bidiLUT
                                                              length:bidiLUTLen];
    }

    int count = iTermGetMetalBackgroundColors(
        (iTermMetalPerFrameState *)mockSelf,
        line, rles, attributes, unprocessed,
        width, nil, nil,
        (id<iTermColorMapReading>)mockColorMap,
        (iTermBidiDisplayInfo *)mockBidi,
        lineAttribute);

    int n = MIN(count, maxResults);
    for (int i = 0; i < n; i++) {
        results[i].origin = rles[i].origin;
        results[i].count = rles[i].count;
        results[i].logicalOrigin = rles[i].logicalOrigin;
    }

    free(rles);
    free(attributes);
    free(unprocessed);
    return count;
}

@end
