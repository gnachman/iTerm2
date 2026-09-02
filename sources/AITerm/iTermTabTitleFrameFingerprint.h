//
//  iTermTabTitleFrameFingerprint.h
//  iTerm2
//
//  A compact fingerprint of the visible screen's background-color layout, used
//  to decide when a session's task has changed enough to regenerate its AI tab
//  title. Background color is the load-bearing signal: a program's chrome (a
//  status bar, a tmux bar, htop's meters, a selection, a diff highlight) paints
//  characteristic backgrounds, and that layout is invariant to the things that
//  churn constantly - typed text, a moving cursor, a ticking clock - while it
//  changes decisively when you switch programs or modes. So comparing this
//  fingerprint over time detects "the task changed" without false-firing on
//  ordinary work, which text diffing cannot do (cursor position and clocks sit
//  inside otherwise-stable rows).
//

#import <Foundation/Foundation.h>

@class VT100Screen;

NS_ASSUME_NONNULL_BEGIN

@interface iTermTabTitleFrameFingerprint : NSObject

/// Histogram of background colors over the visible grid: encoded bg color ->
/// cell count. Compare two histograms (normalized L1 distance) to decide
/// whether the frame changed. Computed on the main thread.
+ (NSDictionary<NSNumber *, NSNumber *> *)backgroundHistogramForScreen:(VT100Screen *)screen;

/// The histogram bucket key for a single cell. Exposed for testing. When isImage
/// is YES the color arguments are ignored and the image sentinel bucket is
/// returned; otherwise green/blue are only meaningful in 24-bit color (see the .m).
+ (uint32_t)histogramKeyForImage:(BOOL)isImage
               backgroundColorMode:(int)mode
                   backgroundColor:(int)backgroundColor
                           bgGreen:(int)bgGreen
                            bgBlue:(int)bgBlue;

/// The reserved histogram bucket every image cell maps to. Callers comparing two
/// histograms may drop it to make the fingerprint size-invariant (an inline image
/// growing/streaming should not count as a task change). See the .m.
+ (uint32_t)imageBucketKey;

@end

NS_ASSUME_NONNULL_END
