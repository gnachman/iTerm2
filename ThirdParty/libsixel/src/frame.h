/*
 * Copyright (c) 2014-2016 Hayaki Saito
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
 * FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
 * COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
 * IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#ifndef LIBSIXEL_FRAME_H
#define LIBSIXEL_FRAME_H

#include <sixel.h>

/* frame object */
struct sixel_frame {
    unsigned int ref;               /* reference counter */
    unsigned char *pixels;          /* loaded pixel data */
    unsigned char *palette;         /* loaded palette data */
    int width;                      /* frame width */
    int height;                     /* frame height */
    int ncolors;                    /* palette colors */
    int pixelformat;                /* one of enum pixelFormat */
    int delay;                      /* delay in msec */
    int frame_no;                   /* frame number */
    int loop_count;                 /* loop count */
    int multiframe;                 /* whether the image has multiple frames */
    int transparent;                /* -1(no transparent) or >= 0(index of transparent color) */
    sixel_allocator_t *allocator;   /* allocator object */
};

#ifdef __cplusplus
extern "C" {
#endif

#if HAVE_TESTS
int
sixel_dither_tests_main(void);
#endif

#ifdef __cplusplus
}
#endif

#endif /* LIBSIXEL_FRAME_H */

/* emacs Local Variables:      */
/* emacs mode: c               */
/* emacs tab-width: 4          */
/* emacs indent-tabs-mode: nil */
/* emacs c-basic-offset: 4     */
/* emacs End:                  */
/* vim: set expandtab ts=4 sts=4 sw=4 : */
/* EOF */
