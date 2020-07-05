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

#ifndef LIBSIXEL_CHUNK_H
#define LIBSIXEL_CHUNK_H

#include <sixel.h>

/* chunk object */
typedef struct sixel_chunk
{
    unsigned char *buffer;
    size_t size;
    size_t max_size;
    sixel_allocator_t *allocator;
} sixel_chunk_t;

#ifdef __cplusplus
extern "C" {
#endif

SIXELSTATUS
sixel_chunk_new(
    sixel_chunk_t       /* out */   **ppchunk,
    char const          /* in */    *filename,
    int                 /* in */    finsecure,
    int const           /* in */    *cancel_flag,
    sixel_allocator_t   /* in */    *allocator);


void
sixel_chunk_destroy(
    sixel_chunk_t * const /* in */ pchunk);


#if HAVE_TESTS
int
sixel_chunk_tests_main(void);
#endif

#ifdef __cplusplus
}
#endif

#endif /* LIBSIXEL_CHUNK_H */

/* emacs Local Variables:      */
/* emacs mode: c               */
/* emacs tab-width: 4          */
/* emacs indent-tabs-mode: nil */
/* emacs c-basic-offset: 4     */
/* emacs End:                  */
/* vim: set expandtab ts=4 sts=4 sw=4 : */
/* EOF */
