#import "iTermAttributedStringBuilderBenchmark.h"

#import <QuartzCore/QuartzCore.h>

#import "CVector.h"
#import "ScreenChar.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermAttributedStringBuilder.h"
#import "iTermBackgroundColorRun.h"
#import "iTermColorMap.h"
#import "iTerm2SharedARC-Swift.h"

// Deterministic LCG so the benchmark is reproducible and never flaky.
static inline uint32_t iTermBenchNextRandom(uint32_t *state) {
    *state = (*state * 1664525u) + 1013904223u;
    return *state;
}

#pragma mark - Worker

// One independent build unit: its own builder, colormap, fonttable and stats, so
// several workers can run concurrently with zero shared mutable state.
@interface iTermASBBenchWorker : NSObject <iTermAttributedStringBuilderDelegate>
@end

@implementation iTermASBBenchWorker {
    iTermColorMap *_colorMap;
    NSColorSpace *_colorSpace;
    iTermAttributedStringBuilder *_builder;
    iTermAttributedStringBuilderStats _stats;
}

- (instancetype)initWithColorSpace:(NSColorSpace *)colorSpace ligatures:(BOOL)ligatures {
    self = [super init];
    if (self) {
        _colorSpace = colorSpace;

        _colorMap = [[iTermColorMap alloc] init];
        [_colorMap setColor:[NSColor whiteColor] forKey:kColorMapForeground];
        [_colorMap setColor:[NSColor blackColor] forKey:kColorMapBackground];
        for (int i = 0; i < 16; i++) {
            CGFloat c = (i + 1) / 17.0;
            [_colorMap setColor:[NSColor colorWithSRGBRed:c green:1.0 - c blue:(i % 4) / 3.0 alpha:1]
                         forKey:kColorMap8bitBase + i];
        }

        iTermFontTable *fontTable = [[iTermFontTable alloc] init];

        iTermAttributedStringBuilderStatsPointers pointers = {
            .attrsForChar = &_stats.attrsForChar,
            .shouldSegment = &_stats.shouldSegment,
            .buildMutableAttributedString = &_stats.buildMutableAttributedString,
            .combineAttributes = &_stats.combineAttributes,
            .updateBuilder = &_stats.updateBuilder,
            .advances = &_stats.advances,
        };
        iTermPreciseTimerStatsInit(pointers.attrsForChar, "attrsForChar");
        iTermPreciseTimerStatsInit(pointers.shouldSegment, "shouldSegment");
        iTermPreciseTimerStatsInit(pointers.buildMutableAttributedString, "build");
        iTermPreciseTimerStatsInit(pointers.combineAttributes, "combine");
        iTermPreciseTimerStatsInit(pointers.updateBuilder, "update");
        iTermPreciseTimerStatsInit(pointers.advances, "advances");
        _builder = [[iTermAttributedStringBuilder alloc] initWithStats:pointers];

        [_builder setColorMap:_colorMap
                 reverseVideo:NO
              minimumContrast:0
                        zippy:NO
      asciiLigaturesAvailable:ligatures
               asciiLigatures:ligatures
     preferSpeedToFullLigatureSupport:YES
          lowFiCombiningMarks:NO
                     cellSize:NSMakeSize(7, 14)
         blinkingItemsVisible:YES
                 blinkAllowed:NO
              useNonAsciiFont:NO
               asciiAntiAlias:YES
            nonAsciiAntiAlias:YES
                     isRetina:YES
    forceAntialiasingOnRetina:NO
                  boldAllowed:YES
                italicAllowed:YES
            nonAsciiLigatures:NO
     useNativePowerlineGlyphs:NO
                 fontProvider:fontTable
                    fontTable:fontTable
                     delegate:self];
    }
    return self;
}

- (void)buildLine:(const screen_char_t *)line width:(int)width bg:(NSColor *)bg {
    iTermBackgroundColorRun run = {
        .modelRange = NSMakeRange(0, width),
        .visualRange = NSMakeRange(0, width),
        .bgColor = ALTSEM_DEFAULT,
        .bgColorMode = ColorModeAlternate,
        .selected = NO,
        .isMatch = NO,
        .beneathFaintText = NO,
    };
    CTVector(CGFloat) positions;
    CTVectorCreate(&positions, width);
    NSArray *strings = [_builder attributedStringsForLine:line
                                                 bidiInfo:nil
                                       externalAttributes:nil
                                                    range:NSMakeRange(0, width)
                                          hasSelectedText:NO
                                          backgroundColor:bg
                                           forceTextColor:nil
                                                 colorRun:&run
                                              findMatches:nil
                                          underlinedRange:NSMakeRange(0, 0)
                                                positions:&positions];
    (void)strings.count;  // Keep the optimizer from eliding the work.
    CTVectorDestroy(&positions);
}

#pragma mark iTermAttributedStringBuilderDelegate

- (BOOL)useSelectedTextColor {
    return NO;
}

- (NSColor *)unprocessedColorForBackgroundRun:(const iTermBackgroundColorRun *)run
                               enableBlending:(BOOL)enableBlending {
    return [_colorMap colorForKey:kColorMapBackground] ?: [NSColor blackColor];
}

- (NSColor *)colorForCode:(int)theIndex
                    green:(int)green
                     blue:(int)blue
                colorMode:(ColorMode)theMode
                     bold:(BOOL)isBold
                    faint:(BOOL)isFaint
             isBackground:(BOOL)isBackground {
    // Mirror -[iTermMetalPerFrameState colorForCode:...]: resolve to a color-map
    // key, convert through the target color space, and box as an NSColor.
    iTermColorMapKey key;
    switch (theMode) {
        case ColorMode24bit:
        case ColorModeExternal:
            key = [iTermColorMap keyFor8bitRed:theIndex green:green blue:blue];
            break;
        case ColorModeNormal:
            key = kColorMap8bitBase + (theIndex & 0xff);
            break;
        case ColorModeAlternate:
        default:
            key = isBackground ? kColorMapBackground : kColorMapForeground;
            break;
    }
    vector_float4 v = [_colorMap fastColorForKey:key colorSpace:_colorSpace];
    return [NSColor colorWithDisplayP3Red:v.x green:v.y blue:v.z alpha:v.w];
}

@end

#pragma mark - Benchmark

@implementation iTermAttributedStringBuilderBenchmark {
    int _width;
    int _height;
}

- (instancetype)initWithWidth:(int)width height:(int)height {
    self = [super init];
    if (self) {
        _width = width;
        _height = height;
        _nativeColorSpace = YES;
    }
    return self;
}

- (NSColorSpace *)colorSpaceForRun {
    if (_nativeColorSpace) {
        return [iTermAdvancedSettingsModel p3] ? [NSColorSpace displayP3ColorSpace] : [NSColorSpace sRGBColorSpace];
    }
    return [NSColorSpace genericRGBColorSpace];
}

// Fill `line` (width cells) with printable ASCII and the requested fg scheme.
- (void)fillLine:(screen_char_t *)line scheme:(iTermASBBenchColorScheme)scheme rng:(uint32_t *)rng {
    for (int x = 0; x < _width; x++) {
        screen_char_t c = { 0 };
        c.code = 33 + (iTermBenchNextRandom(rng) % (127 - 33));  // printable ASCII, no space
        switch (scheme) {
            case iTermASBBenchColorSchemeMono:
                c.foregroundColor = ALTSEM_DEFAULT;
                c.foregroundColorMode = ColorModeAlternate;
                break;
            case iTermASBBenchColorSchemeAnsi:
                c.foregroundColor = iTermBenchNextRandom(rng) % 16;
                c.foregroundColorMode = ColorModeNormal;
                break;
            case iTermASBBenchColorSchemeTrueColor: {
                const uint32_t v = iTermBenchNextRandom(rng);
                c.foregroundColor = (v >> 16) & 0xff;
                c.fgGreen = (v >> 8) & 0xff;
                c.fgBlue = v & 0xff;
                c.foregroundColorMode = ColorMode24bit;
                break;
            }
        }
        c.backgroundColor = ALTSEM_DEFAULT;
        c.backgroundColorMode = ColorModeAlternate;
        line[x] = c;
    }
}

- (NSArray<NSData *> *)buildFramePoolWithScheme:(iTermASBBenchColorScheme)scheme count:(int)poolCount {
    const size_t lineBytes = sizeof(screen_char_t) * _width;
    NSMutableArray<NSData *> *pool = [NSMutableArray array];
    uint32_t rng = 0x12345678;
    for (int f = 0; f < poolCount; f++) {
        NSMutableData *frame = [NSMutableData dataWithLength:lineBytes * _height];
        screen_char_t *base = (screen_char_t *)frame.mutableBytes;
        for (int y = 0; y < _height; y++) {
            [self fillLine:base + (y * _width) scheme:scheme rng:&rng];
        }
        [pool addObject:frame];
    }
    return pool;
}

- (NSTimeInterval)runWithColorScheme:(iTermASBBenchColorScheme)scheme
                          iterations:(int)iterations {
    return [self runWithColorScheme:scheme iterations:iterations threads:1];
}

- (NSTimeInterval)runWithColorScheme:(iTermASBBenchColorScheme)scheme
                          iterations:(int)iterations
                             threads:(int)threads {
    const int nthreads = MAX(1, threads);
    NSColorSpace *colorSpace = [self colorSpaceForRun];

    // One private worker per band. Built outside the timed region.
    NSMutableArray<iTermASBBenchWorker *> *workers = [NSMutableArray array];
    for (int t = 0; t < nthreads; t++) {
        [workers addObject:[[iTermASBBenchWorker alloc] initWithColorSpace:colorSpace ligatures:self.ligatures]];
    }

    const int poolCount = 16;
    NSArray<NSData *> *pool = [self buildFramePoolWithScheme:scheme count:poolCount];
    NSColor *bg = [NSColor colorWithDisplayP3Red:0 green:0 blue:0 alpha:1];
    const int width = _width;
    const int height = _height;

    const CFTimeInterval start = CACurrentMediaTime();
    for (int iter = 0; iter < iterations; iter++) {
        const screen_char_t *frame = (const screen_char_t *)[pool[iter % poolCount] bytes];
        if (nthreads == 1) {
            iTermASBBenchWorker *worker = workers[0];
            for (int y = 0; y < height; y++) {
                @autoreleasepool {
                    [worker buildLine:frame + (y * width) width:width bg:bg];
                }
            }
        } else {
            dispatch_apply(nthreads, DISPATCH_APPLY_AUTO, ^(size_t band) {
                iTermASBBenchWorker *worker = workers[band];
                const int firstRow = (int)((band * height) / nthreads);
                const int lastRow = (int)(((band + 1) * height) / nthreads);
                for (int y = firstRow; y < lastRow; y++) {
                    @autoreleasepool {
                        [worker buildLine:frame + (y * width) width:width bg:bg];
                    }
                }
            });
        }
    }
    return CACurrentMediaTime() - start;
}

@end
