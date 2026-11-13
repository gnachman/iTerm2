//
//  iTermSixelSize.h
//  iTerm2SandboxedWorker
//

#import <stdbool.h>
#import <stddef.h>
#import <stdlib.h>

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

// Allocation functions for libsixel. It sizes its one-byte-per-pixel buffer from the image's
// raster attributes before reporting any dimensions, so without these a few bytes of terminal
// output could make it commit gigabytes. No single allocation it needs for an image within
// iTermSixelMaxPixels is larger than that many bytes.
static inline void *iTermSixelMalloc(size_t size) {
    if (size > (size_t)iTermSixelMaxPixels) {
        return NULL;
    }
    return malloc(size);
}

static inline void *iTermSixelCalloc(size_t count, size_t size) {
    if (size != 0 && count > (size_t)iTermSixelMaxPixels / size) {
        return NULL;
    }
    return calloc(count, size);
}

static inline void *iTermSixelRealloc(void *pointer, size_t size) {
    if (size > (size_t)iTermSixelMaxPixels) {
        return NULL;
    }
    return realloc(pointer, size);
}
