#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Per-cell foreground color scheme used to fill the synthetic grid.
typedef NS_ENUM(NSInteger, iTermASBBenchColorScheme) {
    // Every cell uses the default foreground color: one attribute run per line.
    // This is the cheap "static monochrome text" baseline.
    iTermASBBenchColorSchemeMono = 0,

    // Random ANSI (0-15) foreground per cell. Small palette, so colors repeat and
    // the color-vector cache stays warm, but every cell still starts a new run.
    iTermASBBenchColorSchemeAnsi = 1,

    // Random 24-bit truecolor foreground per cell. This is issue 12763's worst
    // case: essentially every cell is its own attribute run.
    iTermASBBenchColorSchemeTrueColor = 2,
};

// Drives -[iTermAttributedStringBuilder attributedStringsForLine:...] over a
// synthetic full-screen grid so the CPU cost of the per-row build (segmentation,
// per-character attribute computation, attribute-dictionary construction, CoreText
// line creation) can be measured without a live PTYTextView/VT100Screen/Metal stack.
//
// This is the path taken when ligatures or bidi are enabled; it reproduces the
// dominant per-run object-churn cost from issue 12763.
@interface iTermAttributedStringBuilderBenchmark : NSObject

// width/height = grid size in cells (e.g. 250x80 for a maximized display).
- (instancetype)initWithWidth:(int)width height:(int)height NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// When YES (default), colors are resolved in the app's native 24-bit color space,
// hitting the fast path in -fastColorForKey:colorSpace:. When NO, a non-native
// color space forces the per-cell ColorSync conversion.
@property (nonatomic) BOOL nativeColorSpace;

// Enables the ligature-capable (CoreText-shaping) path.
@property (nonatomic) BOOL ligatures;

// Builds a pool of random frames (deterministic; fixed seed) once, then rebuilds
// every visible row `iterations` times, cycling through the pool so the color
// path sees churn like a real animation. Returns the total wall-clock seconds
// spent inside attributedStringsForLine (grid generation is excluded).
//
// `threads` splits each frame's rows into that many bands processed concurrently,
// each band with its own private builder/colormap/fonttable. Pass threads<=1 for
// the serial baseline.
- (NSTimeInterval)runWithColorScheme:(iTermASBBenchColorScheme)scheme
                          iterations:(int)iterations
                             threads:(int)threads;

// Serial baseline; equivalent to threads:1.
- (NSTimeInterval)runWithColorScheme:(iTermASBBenchColorScheme)scheme
                          iterations:(int)iterations;

@end

NS_ASSUME_NONNULL_END
