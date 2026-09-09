//
//  iTermTabTitleFrameFingerprint.m
//  iTerm2
//

#import "iTermTabTitleFrameFingerprint.h"

#import "ScreenChar.h"
#import "ScreenCharArray.h"
#import "VT100Screen.h"
#import "iTermMalloc.h"

// Sentinel bucket for image cells. Must NOT be UINT32_MAX: the storage step below
// keys the CFDictionary as (key + 1) in uint32_t arithmetic, so UINT32_MAX would wrap
// to 0 -> a NULL CFDictionary key, exactly what the +1 scheme exists to avoid. Using
// UINT32_MAX - 1 keeps (key + 1) non-zero without relying on pointer width, and still
// can't collide with a real color key because the top byte encodes `mode`, a tiny enum
// that never reaches 0xFF.
static const uint32_t iTermTabTitleImageBucketKey = UINT32_MAX - 1;

// Pure integer bit-packing, as a static inline C function so the per-cell inner
// loop below is plain arithmetic with no objc_msgSend (~2000 dispatches per
// fingerprint saved). The +[histogramKeyForImage:backgroundColorMode:...] method
// wraps it for the API/tests. See that method's comment for the rationale.
static inline uint32_t iTermTabTitleHistogramKey(BOOL isImage, int mode, int backgroundColor, int bgGreen, int bgBlue) {
    if (isImage) {
        // For an image cell the "background" bytes are the image's x/y indices, not a
        // color (see ScreenChar.h), so they change frame to frame as an inline image
        // or animation redraws. Map every image cell to one fixed bucket so an image
        // region contributes a STABLE key regardless of pixel position - otherwise the
        // background histogram moves each frame, crosses frameChangeThreshold, and
        // re-titles (or flickers the title) every ~5s for no task-relevant change.
        return iTermTabTitleImageBucketKey;
    }
    if (mode != ColorMode24bit) {
        bgGreen = 0;
        bgBlue = 0;
    }
    return ((uint32_t)mode << 24) |
           ((uint32_t)backgroundColor << 16) |
           ((uint32_t)bgGreen << 8) |
           ((uint32_t)bgBlue);
}

@implementation iTermTabTitleFrameFingerprint

+ (NSDictionary<NSNumber *, NSNumber *> *)backgroundHistogramForScreen:(VT100Screen *)screen {
    // Accumulate counts in a CF dictionary with raw integer keys/values (stored in
    // the pointer slots, NULL callbacks so nothing is retained or boxed), then box
    // into NSNumbers once per UNIQUE background color at the end. A grid is ~2000
    // cells but only a handful of distinct backgrounds, so this turns thousands of
    // short-lived NSNumber allocations per fingerprint (recomputed on the display
    // cadence for every idle alternate-screen AI session) into a few.
    CFMutableDictionaryRef counts = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, NULL);
    const int scrollback = [screen numberOfScrollbackLines];
    const int height = [screen height];
    for (int y = 0; y < height; y++) {
        ScreenCharArray *sca = [screen screenCharArrayForLine:scrollback + y];
        const screen_char_t *line = sca.line;
        const int length = sca.length;
        for (int x = 0; x < length; x++) {
            const screen_char_t c = line[x];
            // Reverse video (SGR-7) paints the FOREGROUND color where the background
            // would be, so the VISIBLE background of a reverse cell is its fg color. Bucket
            // by that effective background - the fg fields when inverse - so a TUI that
            // expresses state purely through reverse-video regions (a status line, a
            // reverse-i-search bar, a highlighted line) registers as frame distance instead
            // of hashing to an identical histogram and being skipped. backgroundColor alone
            // (like BackgroundColorsEqual) misses this; the fuller ScreenCharFGBGEqual
            // compares inverse for the same reason. Images ignore inverse (image bucket).
            // Not a separate inverse bit: a reverse cell and a plain cell that paint the
            // SAME visible background should share a bucket.
            const BOOL inverse = c.inverse && !c.image;
            const uint32_t key = iTermTabTitleHistogramKey(c.image,
                                                           inverse ? c.foregroundColorMode : c.backgroundColorMode,
                                                           inverse ? c.foregroundColor : c.backgroundColor,
                                                           inverse ? c.fgGreen : c.bgGreen,
                                                           inverse ? c.fgBlue : c.bgBlue);
            // +1 so a key of 0 is representable (CFDictionary reserves NULL). Counts
            // are always >= 1, so a NULL value reliably means "not yet seen".
            const void *cfKey = (const void *)(uintptr_t)(key + 1);
            const uintptr_t existing = (uintptr_t)CFDictionaryGetValue(counts, cfKey);
            CFDictionarySetValue(counts, cfKey, (const void *)(existing + 1));
        }
    }
    const CFIndex n = CFDictionaryGetCount(counts);
    NSMutableDictionary<NSNumber *, NSNumber *> *histogram =
        [NSMutableDictionary dictionaryWithCapacity:n];
    if (n > 0) {
        // iTermMalloc is never-NULL and overflow-checked, and produces a useful crash
        // log; a raw malloc returning NULL would make CFDictionaryGetKeysAndValues
        // write through NULL and crash with no diagnostic.
        const void **keys = iTermMalloc(sizeof(void *) * n);
        const void **values = iTermMalloc(sizeof(void *) * n);
        CFDictionaryGetKeysAndValues(counts, keys, values);
        for (CFIndex i = 0; i < n; i++) {
            const uint32_t key = (uint32_t)((uintptr_t)keys[i] - 1);
            const NSInteger count = (NSInteger)(uintptr_t)values[i];
            histogram[@(key)] = @(count);
        }
        free(keys);
        free(values);
    }
    CFRelease(counts);
    return histogram;
}

+ (uint32_t)histogramKeyForImage:(BOOL)isImage
               backgroundColorMode:(int)mode
                   backgroundColor:(int)backgroundColor
                           bgGreen:(int)bgGreen
                            bgBlue:(int)bgBlue {
    // Encode the mode (default / ANSI-256 / 24-bit) plus its color components so
    // different color spaces don't collide. Only 24-bit uses green/blue as real
    // components; for default/indexed cells those bytes are not meaningful, and
    // image cells repurpose them as x/y indices. Mixing them in unconditionally
    // would hash a visually identical background into distinct buckets (inflating
    // the frame distance and spuriously firing "task changed"), so drop them
    // outside 24-bit to match BackgroundColorsEqual in ScreenChar.h.
    return iTermTabTitleHistogramKey(isImage, mode, backgroundColor, bgGreen, bgBlue);
}

+ (uint32_t)imageBucketKey {
    return iTermTabTitleImageBucketKey;
}

@end
