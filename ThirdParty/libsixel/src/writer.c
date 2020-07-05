/*
 * Copyright (c) 2014-2018 Hayaki Saito
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
# include <stdio.h>
# include <stdlib.h>
#endif  /* STDC_HEADERS */
#if HAVE_STRING_H
# include <string.h>
#endif  /* HAVE_STRING_H */
#if HAVE_SETJMP_H
# include <setjmp.h>
#endif  /* HAVE_SETJMP_H */
#if HAVE_ERRNO_H
# include <errno.h>
#endif  /* HAVE_ERRNO_H */
#if HAVE_LIBPNG
# include <png.h>
#else
# include "stb_image_write.h"
#endif  /* HAVE_LIBPNG */

#include <sixel.h>

#if !defined(HAVE_MEMCPY)
# define memcpy(d, s, n) (bcopy ((s), (d), (n)))
#endif

#if !defined(HAVE_MEMMOVE)
# define memmove(d, s, n) (bcopy ((s), (d), (n)))
#endif

#if !defined(O_BINARY) && defined(_O_BINARY)
# define O_BINARY _O_BINARY
#endif  /* !defined(O_BINARY) && !defined(_O_BINARY) */


#if !HAVE_LIBPNG
unsigned char *
stbi_write_png_to_mem(unsigned char *pixels, int stride_bytes,
                      int x, int y, int n, int *out_len);
#endif

static SIXELSTATUS
write_png_to_file(
    unsigned char       /* in */ *data,         /* source pixel data */
    int                 /* in */ width,         /* source data width */
    int                 /* in */ height,        /* source data height */
    unsigned char       /* in */ *palette,      /* palette of source data */
    int                 /* in */ pixelformat,   /* source pixelFormat */
    char const          /* in */ *filename,     /* destination filename */
    sixel_allocator_t   /* in */ *allocator)
{
    SIXELSTATUS status = SIXEL_FALSE;
    FILE *output_fp = NULL;
    unsigned char *pixels = NULL;
    unsigned char *new_pixels = NULL;
#if HAVE_LIBPNG
    int y;
    png_structp png_ptr = NULL;
    png_infop info_ptr = NULL;
    unsigned char **rows = NULL;
#else
    unsigned char *png_data = NULL;
    int png_len;
    int write_len;
#endif  /* HAVE_LIBPNG */
    int i;
    unsigned char *src;
    unsigned char *dst;

    switch (pixelformat) {
    case SIXEL_PIXELFORMAT_PAL1:
    case SIXEL_PIXELFORMAT_PAL2:
    case SIXEL_PIXELFORMAT_PAL4:
        if (palette == NULL) {
            status = SIXEL_BAD_ARGUMENT;
            sixel_helper_set_additional_message(
                "write_png_to_file: no palette is given");
            goto end;
        }
        new_pixels = sixel_allocator_malloc(allocator, (size_t)(width * height * 4));
        if (new_pixels == NULL) {
            status = SIXEL_BAD_ALLOCATION;
            sixel_helper_set_additional_message(
                "write_png_to_file: sixel_allocator_malloc() failed");
            goto end;
        }
        src = new_pixels + width * height * 3;
        dst = pixels = new_pixels;
        status = sixel_helper_normalize_pixelformat(src,
                                                    &pixelformat,
                                                    data,
                                                    pixelformat,
                                                    width, height);
        if (SIXEL_FAILED(status)) {
            goto end;
        }
        for (i = 0; i < width * height; ++i, ++src) {
            *dst++ = *(palette + *src * 3 + 0);
            *dst++ = *(palette + *src * 3 + 1);
            *dst++ = *(palette + *src * 3 + 2);
        }
        break;
    case SIXEL_PIXELFORMAT_PAL8:
        if (palette == NULL) {
            status = SIXEL_BAD_ARGUMENT;
            sixel_helper_set_additional_message(
                "write_png_to_file: no palette is given");
            goto end;
        }
        src = data;
        dst = pixels = new_pixels = sixel_allocator_malloc(allocator, (size_t)(width * height * 3));
        if (new_pixels == NULL) {
            status = SIXEL_BAD_ALLOCATION;
            sixel_helper_set_additional_message(
                "write_png_to_file: sixel_allocator_malloc() failed");
            goto end;
        }
        for (i = 0; i < width * height; ++i, ++src) {
            *dst++ = *(palette + *src * 3 + 0);
            *dst++ = *(palette + *src * 3 + 1);
            *dst++ = *(palette + *src * 3 + 2);
        }
        break;
    case SIXEL_PIXELFORMAT_RGB888:
        pixels = data;
        break;
    case SIXEL_PIXELFORMAT_G8:
        src = data;
        dst = pixels = new_pixels
            = sixel_allocator_malloc(allocator, (size_t)(width * height * 3));
        if (new_pixels == NULL) {
            status = SIXEL_BAD_ALLOCATION;
            sixel_helper_set_additional_message(
                "write_png_to_file: sixel_allocator_malloc() failed");
            goto end;
        }
        if (palette) {
            for (i = 0; i < width * height; ++i, ++src) {
                *dst++ = *(palette + *src * 3 + 0);
                *dst++ = *(palette + *src * 3 + 1);
                *dst++ = *(palette + *src * 3 + 2);
            }
        } else {
            for (i = 0; i < width * height; ++i, ++src) {
                *dst++ = *src;
                *dst++ = *src;
                *dst++ = *src;
            }
        }
        break;
    case SIXEL_PIXELFORMAT_RGB565:
    case SIXEL_PIXELFORMAT_RGB555:
    case SIXEL_PIXELFORMAT_BGR565:
    case SIXEL_PIXELFORMAT_BGR555:
    case SIXEL_PIXELFORMAT_GA88:
    case SIXEL_PIXELFORMAT_AG88:
    case SIXEL_PIXELFORMAT_BGR888:
    case SIXEL_PIXELFORMAT_RGBA8888:
    case SIXEL_PIXELFORMAT_ARGB8888:
    case SIXEL_PIXELFORMAT_BGRA8888:
    case SIXEL_PIXELFORMAT_ABGR8888:
        pixels = new_pixels = sixel_allocator_malloc(allocator, (size_t)(width * height * 3));
        if (new_pixels == NULL) {
            status = SIXEL_BAD_ALLOCATION;
            sixel_helper_set_additional_message(
                "write_png_to_file: sixel_allocator_malloc() failed");
            goto end;
        }
        status = sixel_helper_normalize_pixelformat(pixels,
                                                    &pixelformat,
                                                    data,
                                                    pixelformat,
                                                    width, height);
        if (SIXEL_FAILED(status)) {
            goto end;
        }
        break;
    default:
        status = SIXEL_BAD_ARGUMENT;
        sixel_helper_set_additional_message(
            "write_png_to_file: unkown pixelformat is specified");
        goto end;
    }

    if (strcmp(filename, "-") == 0) {
#if defined(O_BINARY)
# if HAVE__SETMODE
        _setmode(fileno(stdout), O_BINARY);
# elif HAVE_SETMODE
        setmode(fileno(stdout), O_BINARY);
# endif  /* HAVE_SETMODE */
#endif  /* defined(O_BINARY) */
        output_fp = stdout;
    } else {
        output_fp = fopen(filename, "wb");
        if (!output_fp) {
            status = (SIXEL_LIBC_ERROR | (errno & 0xff));
            sixel_helper_set_additional_message("fopen() failed.");
            goto end;
        }
    }

#if HAVE_LIBPNG
    rows = sixel_allocator_malloc(allocator, (size_t)height * sizeof(unsigned char *));
    if (rows == NULL) {
        status = SIXEL_BAD_ALLOCATION;
        sixel_helper_set_additional_message(
            "write_png_to_file: sixel_allocator_malloc() failed");
        goto end;
    }
    for (y = 0; y < height; ++y) {
        rows[y] = pixels + width * 3 * y;
    }
    png_ptr = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    if (!png_ptr) {
        status = SIXEL_PNG_ERROR;
        /* TODO: get error message */
        goto end;
    }
    info_ptr = png_create_info_struct(png_ptr);
    if (!png_ptr) {
        status = SIXEL_PNG_ERROR;
        /* TODO: get error message */
        goto end;
    }
# if USE_SETJMP && HAVE_SETJMP
    if (setjmp(png_jmpbuf(png_ptr))) {
        status = SIXEL_PNG_ERROR;
        /* TODO: get error message */
        goto end;
    }
# endif
    png_init_io(png_ptr, output_fp);
    png_set_IHDR(png_ptr, info_ptr, (png_uint_32)width, (png_uint_32)height,
                 /* bit_depth */ 8, PNG_COLOR_TYPE_RGB, PNG_INTERLACE_NONE,
                 PNG_COMPRESSION_TYPE_BASE, PNG_FILTER_TYPE_BASE);
    png_write_info(png_ptr, info_ptr);
    png_write_image(png_ptr, rows);
    png_write_end(png_ptr, NULL);
#else
    png_data = stbi_write_png_to_mem(pixels, width * 3,
                                     width, height,
                                     /* STBI_rgb */ 3, &png_len);
    if (png_data == NULL) {
        status = (SIXEL_LIBC_ERROR | (errno & 0xff));
        sixel_helper_set_additional_message("stbi_write_png_to_mem() failed.");
        goto end;
    }
    write_len = (int)fwrite(png_data, 1, (size_t)png_len, output_fp);
    if (write_len <= 0) {
        status = (SIXEL_LIBC_ERROR | (errno & 0xff));
        sixel_helper_set_additional_message("fwrite() failed.");
        goto end;
    }
#endif  /* HAVE_LIBPNG */

    status = SIXEL_OK;

end:
    if (output_fp && output_fp != stdout) {
        fclose(output_fp);
    }
#if HAVE_LIBPNG
    sixel_allocator_free(allocator, rows);
    if (png_ptr) {
        png_destroy_write_struct(&png_ptr, &info_ptr);
    }
#else
    sixel_allocator_free(allocator, png_data);
#endif  /* HAVE_LIBPNG */
    sixel_allocator_free(allocator, new_pixels);

    return status;
}


SIXELAPI SIXELSTATUS
sixel_helper_write_image_file(
    unsigned char       /* in */ *data,        /* source pixel data */
    int                 /* in */ width,        /* source data width */
    int                 /* in */ height,       /* source data height */
    unsigned char       /* in */ *palette,     /* palette of source data */
    int                 /* in */ pixelformat,  /* source pixelFormat */
    char const          /* in */ *filename,    /* destination filename */
    int                 /* in */ imageformat,  /* destination imageformat */
    sixel_allocator_t   /* in */ *allocator)   /* allocator object */
{
    SIXELSTATUS status = SIXEL_FALSE;

    if (allocator == NULL) {
        status = sixel_allocator_new(&allocator, NULL, NULL, NULL, NULL);
        if (SIXEL_FAILED(status)) {
            goto end;
        }
    } else {
        sixel_allocator_ref(allocator);
    }

    if (width > SIXEL_WIDTH_LIMIT) {
        sixel_helper_set_additional_message(
            "sixel_encode: bad width parameter."
            " (width > SIXEL_WIDTH_LIMIT)");
        status = SIXEL_BAD_INPUT;
        goto end;
    }

    if (width > SIXEL_HEIGHT_LIMIT) {
        sixel_helper_set_additional_message(
            "sixel_encode: bad width parameter."
            " (width > SIXEL_HEIGHT_LIMIT)");
        status = SIXEL_BAD_INPUT;
        goto end;
    }

    if (height < 1) {
        sixel_helper_set_additional_message(
            "sixel_encode: bad height parameter."
            " (height < 1)");
        status = SIXEL_BAD_INPUT;
        goto end;
    }

    if (width < 1) {
        sixel_helper_set_additional_message(
            "sixel_encode: bad width parameter."
            " (width < 1)");
        status = SIXEL_BAD_INPUT;
        goto end;
    }

    if (height < 1) {
        sixel_helper_set_additional_message(
            "sixel_encode: bad height parameter."
            " (height < 1)");
        status = SIXEL_BAD_INPUT;
        goto end;
    }

    switch (imageformat) {
    case SIXEL_FORMAT_PNG:
        status = write_png_to_file(data, width, height, palette,
                                   pixelformat, filename, allocator);
        break;
    case SIXEL_FORMAT_GIF:
    case SIXEL_FORMAT_BMP:
    case SIXEL_FORMAT_JPG:
    case SIXEL_FORMAT_TGA:
    case SIXEL_FORMAT_WBMP:
    case SIXEL_FORMAT_TIFF:
    case SIXEL_FORMAT_SIXEL:
    case SIXEL_FORMAT_PNM:
    case SIXEL_FORMAT_GD2:
    case SIXEL_FORMAT_PSD:
    case SIXEL_FORMAT_HDR:
    default:
        status = SIXEL_NOT_IMPLEMENTED;
        goto end;
        break;
    }

end:
    sixel_allocator_unref(allocator);
    return status;
}


#if HAVE_TESTS
static int
test1(void)
{
    int nret = EXIT_FAILURE;
    SIXELSTATUS status;
    unsigned char pixels[] = {0xff, 0xff, 0xff};

    status = sixel_helper_write_image_file(
        pixels,
        1,
        1,
        NULL,
        SIXEL_PIXELFORMAT_RGB888,
        "output.gif",
        SIXEL_FORMAT_GIF,
        NULL);

    if (!SIXEL_FAILED(status)) {
        goto error;
    }
    nret = EXIT_SUCCESS;

error:
    return nret;
}


static int
test2(void)
{
    int nret = EXIT_FAILURE;
    SIXELSTATUS status;
    unsigned char pixels[] = {0xff, 0xff, 0xff};

    status = sixel_helper_write_image_file(
        pixels,
        1,
        1,
        NULL,
        SIXEL_PIXELFORMAT_RGB888,
        "test-output.png",
        SIXEL_FORMAT_PNG,
        NULL);

    if (SIXEL_FAILED(status)) {
        goto error;
    }
    nret = EXIT_SUCCESS;

error:
    return nret;
}


static int
test3(void)
{
    int nret = EXIT_FAILURE;
    SIXELSTATUS status;
    unsigned char pixels[] = {0x00, 0x7f, 0xff};
    sixel_dither_t *dither = sixel_dither_get(SIXEL_BUILTIN_G8);

    status = sixel_helper_write_image_file(
        pixels,
        1,
        1,
        NULL,
        SIXEL_PIXELFORMAT_G8,
        "test-output.png",
        SIXEL_FORMAT_PNG,
        NULL);

    if (SIXEL_FAILED(status)) {
        goto error;
    }

    status = sixel_helper_write_image_file(
        pixels,
        1,
        1,
        sixel_dither_get_palette(dither),
        SIXEL_PIXELFORMAT_G8,
        "test-output.png",
        SIXEL_FORMAT_PNG,
        NULL);

    if (SIXEL_FAILED(status)) {
        goto error;
    }
    nret = EXIT_SUCCESS;

error:
    return nret;
}


static int
test4(void)
{
    int nret = EXIT_FAILURE;
    SIXELSTATUS status;
    unsigned char pixels[] = {0xa0};
    sixel_dither_t *dither = sixel_dither_get(SIXEL_BUILTIN_MONO_DARK);

    status = sixel_helper_write_image_file(
        pixels,
        1,
        1,
        sixel_dither_get_palette(dither),
        SIXEL_PIXELFORMAT_PAL1,
        "test-output.png",
        SIXEL_FORMAT_PNG,
        NULL);
    if (SIXEL_FAILED(status)) {
        goto error;
    }

    status = sixel_helper_write_image_file(
        pixels,
        1,
        1,
        NULL,
        SIXEL_PIXELFORMAT_PAL1,
        "test-output.png",
        SIXEL_FORMAT_PNG,
        NULL);
    if (status != SIXEL_BAD_ARGUMENT) {
        goto error;
    }

    nret = EXIT_SUCCESS;

error:
    return nret;
}


static int
test5(void)
{
    int nret = EXIT_FAILURE;
    SIXELSTATUS status;
    unsigned char pixels[] = {0x00};
    sixel_dither_t *dither = sixel_dither_get(SIXEL_BUILTIN_XTERM256);

    status = sixel_helper_write_image_file(
        pixels,
        1,
        1,
        sixel_dither_get_palette(dither),
        SIXEL_PIXELFORMAT_PAL8,
        "test-output.png",
        SIXEL_FORMAT_PNG,
        NULL);
    if (SIXEL_FAILED(status)) {
        goto error;
    }

    status = sixel_helper_write_image_file(
        pixels,
        1,
        1,
        NULL,
        SIXEL_PIXELFORMAT_PAL8,
        "test-output.png",
        SIXEL_FORMAT_PNG,
        NULL);
    if (status != SIXEL_BAD_ARGUMENT) {
        goto error;
    }

    nret = EXIT_SUCCESS;

error:
    return nret;
}


static int
test6(void)
{
    int nret = EXIT_FAILURE;
    SIXELSTATUS status;
    unsigned char pixels[] = {0x00, 0x7f, 0xff};

    status = sixel_helper_write_image_file(
        pixels,
        1,
        1,
        NULL,
        SIXEL_PIXELFORMAT_BGR888,
        "test-output.png",
        SIXEL_FORMAT_PNG,
        NULL);

    if (SIXEL_FAILED(status)) {
        goto error;
    }
    nret = EXIT_SUCCESS;

error:
    return nret;
}


SIXELAPI int
sixel_writer_tests_main(void)
{
    int nret = EXIT_FAILURE;
    size_t i;
    typedef int (* testcase)(void);

    static testcase const testcases[] = {
        test1,
        test2,
        test3,
        test4,
        test5,
        test6,
    };

    for (i = 0; i < sizeof(testcases) / sizeof(testcase); ++i) {
        nret = testcases[i]();
        if (nret != EXIT_SUCCESS) {
            goto error;
        }
    }

    nret = EXIT_SUCCESS;

error:
    return nret;
}
#endif  /* HAVE_TESTS */

/* emacs Local Variables:      */
/* emacs mode: c               */
/* emacs tab-width: 4          */
/* emacs indent-tabs-mode: nil */
/* emacs c-basic-offset: 4     */
/* emacs End:                  */
/* vim: set expandtab ts=4 sts=4 sw=4 : */
/* EOF */
