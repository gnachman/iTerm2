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

#include "config.h"

#if STDC_HEADERS
# include <stdlib.h>
# include <stdio.h>
#endif  /* STDC_HEADERS */
#if HAVE_STDRING_H
# include <string.h>
#endif  /* HAVE_STRING_H */
#if HAVE_MATH_H
# include <math.h>
#endif  /* HAVE_MATH_H */
#if HAVE_LIMITS_H
# include <limits.h>
#endif  /* HAVE_LIMITS_H */
#if HAVE_INTTYPES_H
# include <inttypes.h>
#endif  /* HAVE_INTTYPES_H */

#include <sixel.h>
#include "dither.h"
#include "quant.h"
#include "frame.h"
#include "pixelformat.h"
#include "writer.h"
#include "encoder.h"
#include "decoder.h"
#include "status.h"
#include "loader.h"
#include "fromgif.h"
#include "chunk.h"
#include "allocator.h"

#if HAVE_TESTS

int
main(int argc, char *argv[])
{
    int nret = EXIT_FAILURE;

    (void) argc;
    (void) argv;

    nret = sixel_fromgif_tests_main();
    if (nret != EXIT_SUCCESS) {
        goto error;
    }

    puts("fromgif ok.");
    fflush(stdout);

    nret = sixel_loader_tests_main();
    if (nret != EXIT_SUCCESS) {
        goto error;
    }

    puts("loader ok.");
    fflush(stdout);

    nret = sixel_dither_tests_main();
    if (nret != EXIT_SUCCESS) {
        goto error;
    }

    puts("dither ok.");
    fflush(stdout);

    nret = sixel_pixelformat_tests_main();
    if (nret != EXIT_SUCCESS) {
        goto error;
    }

    puts("pixelformat ok.");
    fflush(stdout);

    nret = sixel_frame_tests_main();
    if (nret != EXIT_SUCCESS) {
        goto error;
    }

    puts("frame ok.");
    fflush(stdout);

    nret = sixel_writer_tests_main();
    if (nret != EXIT_SUCCESS) {
        goto error;
    }

    puts("writer ok.");
    fflush(stdout);

    nret = sixel_quant_tests_main();
    if (nret != EXIT_SUCCESS) {
        goto error;
    }

    puts("quant ok.");
    fflush(stdout);

    nret = sixel_encoder_tests_main();
    if (nret != EXIT_SUCCESS) {
        goto error;
    }

    puts("encoder ok.");
    fflush(stdout);

    nret = sixel_decoder_tests_main();
    if (nret != EXIT_SUCCESS) {
        goto error;
    }

    puts("decoder ok.");
    fflush(stdout);

    nret = sixel_status_tests_main();
    if (nret != EXIT_SUCCESS) {
        goto error;
    }

    puts("status ok.");
    fflush(stdout);

    nret = sixel_chunk_tests_main();
    if (nret != EXIT_SUCCESS) {
        goto error;
    }

    puts("chunk ok.");
    fflush(stdout);

    nret = sixel_allocator_tests_main();
    if (nret != EXIT_SUCCESS) {
        goto error;
    }

    puts("allocator ok.");
    fflush(stdout);

error:
    return nret;
}

#endif

/* emacs Local Variables:      */
/* emacs mode: c               */
/* emacs tab-width: 4          */
/* emacs indent-tabs-mode: nil */
/* emacs c-basic-offset: 4     */
/* emacs End:                  */
/* vim: set expandtab ts=4 sts=4 sw=4 : */
/* EOF */
