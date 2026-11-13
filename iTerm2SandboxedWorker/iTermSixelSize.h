//
//  iTermSixelSize.h
//  iTerm2SandboxedWorker
//

#import <stdbool.h>
#import <stddef.h>

// The largest decoded sixel image accepted, in pixels (8192 x 8192). libsixel allows up to
// 1,000,000 x 1,000,000, which lets a few bytes of terminal output demand terabytes.
#define iTermSixelMaxPixels (8192L * 8192L)

// Computes the number of pixels and RGBA bytes in a width x height image. Returns false if either
// dimension is not positive or the image exceeds iTermSixelMaxPixels.
static inline bool iTermSixelRGBASize(long width, long height, size_t *pixelsOut, size_t *bytesOut) {
    if (width <= 0 || height <= 0) {
        return false;
    }
    // Check each dimension first so the product can't overflow.
    if (width > iTermSixelMaxPixels || height > iTermSixelMaxPixels / width) {
        return false;
    }
    const size_t pixels = (size_t)width * (size_t)height;
    *pixelsOut = pixels;
    *bytesOut = pixels * 4;
    return true;
}
