/*
 * Copyright (c) 2014 kmiya@culti
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
# include <stdio.h>
# include <stdlib.h>
#endif  /* STDC_HEADERS */
#if HAVE_STRING_H
# include <string.h>
#endif  /* HAVE_STRING_H */
#if HAVE_CTYPE_H
# include <ctype.h>
#endif  /* HAVE_CTYPE_H */

#include <sixel.h>

#define PNM_MAX_WIDTH  (1 << 16)
#define PNM_MAX_HEIGHT (1 << 16)
#define PNM_MAX_DEPTH  (1 << 16)

static unsigned char *
pnm_get_line(unsigned char *p, unsigned char *end, unsigned char *line)
{
    int n;

    do {
        /* read the line */
        for (n = 0 ; p < end && *p >= ' '; p++) {
            if (n < 255) {
                line[n++] = *p;
            }
        }

        /* skip invald characters */
        if (p < end && *p < ' ') {
            p++;
        }

        line[n] = '\0';

    } while (line[0] == '#');

    return p;
}


SIXELSTATUS
load_pnm(unsigned char      /* in */  *p,
         int                /* in */  length,
         sixel_allocator_t  /* in */  *allocator,
         unsigned char      /* out */ **result,
         int                /* out */ *psx,
         int                /* out */ *psy,
         unsigned char      /* out */ **ppalette,
         int                /* out */ *pncolors,
         int                /* out */ *ppixelformat)
{
    SIXELSTATUS status = SIXEL_FALSE;
    int n;
    int i;
    int b;
    int x;
    int y;
    int component[3];
    int ascii;
    int maps;
    int width;
    int height;
    int deps;
    char message[256];
    unsigned char *s;
    unsigned char *end;
    unsigned char tmp[256];
    size_t size;

    (void) ppalette;
    (void) pncolors;

    width = height = 0;
    deps = 1;

    end = p + length;
    p = pnm_get_line(p, end, tmp);
    *result = NULL;

    if (tmp[0] != 'P') {
        status = SIXEL_RUNTIME_ERROR;
        sixel_helper_set_additional_message(
            "load_pnm: first character is not 'P'.");
        goto end;
    }

    switch(tmp[1]) {
    case '1':
        /* Portable bitmap - ASCII */
        ascii = 1;
        maps  = 0;
        break;
    case '2':
        /* Portable graymap - ASCII */
        ascii = 1;
        maps  = 1;
        break;
    case '3':
        /* Portable pixmap - ASCII */
        ascii = 1;
        maps  = 2;
        break;
    case '4':
        /* Portable bitmap - Binary */
        ascii = 0;
        maps  = 0;
        break;
    case '5':
        /* Portable graymap - Binary */
        ascii = 0;
        maps  = 1;
        break;
    case '6':
        /* Portable pixmap - Binary */
        ascii = 0;
        maps  = 2;
        break;
    default:
        goto unknown;
    }

    p = pnm_get_line(p, end, tmp);
    if (p == end) {
        /* check empty content */
        /* Issue 71: https://github.com/saitoha/libsixel/issues/71 */
        goto invalid;
    }

    s = tmp;

    /* parse width */
    width = 0;
    for (; *s >= '0' && *s <= '9'; ++s) {
        width = width * 10 + (*s - '0');
        if (width > PNM_MAX_WIDTH) {
            status = SIXEL_RUNTIME_ERROR;
            sprintf(
              message,
              "load_pnm: image width exceeds the limit %d.",
              PNM_MAX_WIDTH);
            sixel_helper_set_additional_message(message);
            goto end;
        }
    }

    while (*s == ' ') {
        s++;
    }

    /* parse height */
    height = 0;
    for (; *s >= '0' && *s <= '9'; ++s) {
        height = height * 10 + (*s - '0');
        if (height > PNM_MAX_HEIGHT) {
            status = SIXEL_RUNTIME_ERROR;
            sprintf(
              message,
              "load_pnm: image height exceeds the limit %d.",
              PNM_MAX_HEIGHT);
            sixel_helper_set_additional_message(message);
            goto end;
        }
    }

    while (*s != '\0') {
        s++;
    }

    if (maps > 0) {
        p = pnm_get_line(p, end, tmp);
        if (p == end) {
            /* check empty content */
            /* Issue 71: https://github.com/saitoha/libsixel/issues/71 */
            goto invalid;
        }
        s = tmp;
        deps = 0;
        for (; *s >= '0' && *s <= '9'; ++s) {
            deps = deps * 10 + (*s - '0');
        }
        if (deps > PNM_MAX_DEPTH) {
            status = SIXEL_RUNTIME_ERROR;
            sprintf(
              message,
              "load_pnm: image depth exceeds the limit %d.",
              PNM_MAX_DEPTH);
            sixel_helper_set_additional_message(message);
            goto end;
        }
    }

    if (width < 1 || height < 1 || deps < 1) {
        goto invalid;
    }

    size = (size_t)width * (size_t)height * 3 + 1;
    *result = (unsigned char *)sixel_allocator_malloc(allocator, size);

    if (*result == NULL) {
        sixel_helper_set_additional_message(
            "load_pnm: sixel_allocator_malloc() failed.");
        status = SIXEL_BAD_ALLOCATION;
        goto end;
    }

    (void) memset(*result, 0, size);

    for (y = 0 ; y < height ; y++) {
        for (x = 0 ; x < width ; x++) {
            b = (maps == 2 ? 3 : 1);
            for (i = 0 ; i < b ; i++) {
                if (ascii) {
                    while (*s == '\0') {
                        if (p >= end) {
                            break;
                        }
                        p = pnm_get_line(p, end, tmp);
                        s = tmp;
                    }
                    n = 0;
                    if (maps == 0) {
                        n = *s == '0';
                        if (*s != '\0')
                            s++;
                    } else {
                        while (isdigit(*s) && n >= 0) {
                            n = n * 10 + (*s++ - '0');
                        }
                        while (*s == ' ') {
                            s++;
                        }
                    }
                } else {
                    if (p >= end) {
                        break;
                    }
                    if (maps == 0) {
                        n = ((*p << (x & 0x7) >> 0x7) & 1) == 0;
                        if ((x & 0x7) == 0x7) {
                            p++;
                        }
                    } else {
                        n = *(p++);
                    }
                }
                component[i] = n;
            }
            if (i < b) {
                break;
            }

            switch(maps) {
            case 0:        /* bitmap */
                if (component[0] == 0) {
                    component[0] = component[1] = component[2] = 0;
                } else {
                    component[0] = component[1] = component[2] = 255;
                }
                break;
            case 1:        /* graymap */
                component[0] = component[1] = component[2] = component[0] * 255 / deps;
                break;
            case 2:        /* pixmap */
                component[0] = (component[0] * 255 / deps);
                component[1] = (component[1] * 255 / deps);
                component[2] = (component[2] * 255 / deps);
                break;
            default:
                goto unknown;
            }

            *(*result + (y * width + x) * 3 + 0) = component[0];
            *(*result + (y * width + x) * 3 + 1) = component[1];
            *(*result + (y * width + x) * 3 + 2) = component[2];
        }
    }

    *psx = width;
    *psy = height;
    *ppixelformat = SIXEL_PIXELFORMAT_RGB888;

    status = SIXEL_OK;
    goto end;

unknown:
    status = SIXEL_RUNTIME_ERROR;
    sixel_helper_set_additional_message(
        "load_pnm: unknown ppm format.");
    sixel_allocator_free(allocator, *result);
    *result = NULL;
    goto end;

invalid:
    status = SIXEL_RUNTIME_ERROR;
    sixel_helper_set_additional_message(
        "load_pnm: invalid data detected.");
    sixel_allocator_free(allocator, *result);
    *result = NULL;
    goto end;

end:
    return status;
}

/* emacs Local Variables:      */
/* emacs mode: c               */
/* emacs tab-width: 4          */
/* emacs indent-tabs-mode: nil */
/* emacs c-basic-offset: 4     */
/* emacs End:                  */
/* vim: set expandtab ts=4 sts=4 sw=4 : */
/* EOF */
