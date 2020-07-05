/*
 * This file is derived from "sixel" original version (2014-3-2)
 * http://nanno.dip.jp/softlib/man/rlogin/sixel.tar.gz
 *
 * Initial developer of this file is kmiya@culti.
 *
 * He distributes it under very permissive license which permits
 * useing, copying, modification, redistribution, and all other
 * public activities without any restrictions.
 *
 * He declares this is compatible with MIT/BSD/GPL.
 *
 * Hayaki Saito <saitoha@me.com> modified this and re-licensed
 * it to the MIT license.
 */
#include "config.h"

#if STDC_HEADERS
# include <stdlib.h>
# include <stdio.h>
#endif  /* STDC_HEADERS */
#if HAVE_CTYPE_H
# include <ctype.h>   /* isdigit */
#endif  /* HAVE_CTYPE_H */
#if HAVE_STRING_H
# include <string.h>  /* memcpy */
#endif  /* HAVE_STRING_H */
#if HAVE_LIMITS_H
# include <limits.h>
#endif  /* HAVE_LIMITS_H */
#if HAVE_INTTYPES_H
# include <inttypes.h>
#endif  /* HAVE_INTTYPES_H */

#include <sixel.h>
#include "output.h"

#define SIXEL_RGB(r, g, b) (((r) << 16) + ((g) << 8) +  (b))

#define PALVAL(n,a,m) (((n) * (a) + ((m) / 2)) / (m))

#define SIXEL_XRGB(r,g,b) SIXEL_RGB(PALVAL(r, 255, 100), PALVAL(g, 255, 100), PALVAL(b, 255, 100))

#define DECSIXEL_PARAMS_MAX 16

static int const sixel_default_color_table[] = {
    SIXEL_XRGB(0,  0,  0),   /*  0 Black    */
    SIXEL_XRGB(20, 20, 80),  /*  1 Blue     */
    SIXEL_XRGB(80, 13, 13),  /*  2 Red      */
    SIXEL_XRGB(20, 80, 20),  /*  3 Green    */
    SIXEL_XRGB(80, 20, 80),  /*  4 Magenta  */
    SIXEL_XRGB(20, 80, 80),  /*  5 Cyan     */
    SIXEL_XRGB(80, 80, 20),  /*  6 Yellow   */
    SIXEL_XRGB(53, 53, 53),  /*  7 Gray 50% */
    SIXEL_XRGB(26, 26, 26),  /*  8 Gray 25% */
    SIXEL_XRGB(33, 33, 60),  /*  9 Blue*    */
    SIXEL_XRGB(60, 26, 26),  /* 10 Red*     */
    SIXEL_XRGB(33, 60, 33),  /* 11 Green*   */
    SIXEL_XRGB(60, 33, 60),  /* 12 Magenta* */
    SIXEL_XRGB(33, 60, 60),  /* 13 Cyan*    */
    SIXEL_XRGB(60, 60, 33),  /* 14 Yellow*  */
    SIXEL_XRGB(80, 80, 80),  /* 15 Gray 75% */
};


typedef struct image_buffer {
    unsigned char *data;
    int width;
    int height;
    int palette[SIXEL_PALETTE_MAX];
    int ncolors;
} image_buffer_t;

typedef enum parse_state {
    PS_GROUND     = 0,
    PS_ESC        = 1,  /* ESC */
    PS_DCS        = 2,  /* DCS Device Control String Introducer \033P P...P I...I F */
    PS_DECSIXEL   = 3,  /* DECSIXEL body part ", $, -, ? ... ~ */
    PS_DECGRA     = 4,  /* DECGRA Set Raster Attributes " Pan; Pad; Ph; Pv */
    PS_DECGRI     = 5,  /* DECGRI Graphics Repeat Introducer ! Pn Ch */
    PS_DECGCI     = 6   /* DECGCI Graphics Color Introducer # Pc; Pu; Px; Py; Pz */
} parse_state_t;

typedef struct parser_context {
    parse_state_t state;
    int pos_x;
    int pos_y;
    int max_x;
    int max_y;
    int attributed_pan;
    int attributed_pad;
    int attributed_ph;
    int attributed_pv;
    int repeat_count;
    int color_index;
    int bgindex;
    int param;
    int nparams;
    int params[DECSIXEL_PARAMS_MAX];
} parser_context_t;


/*
 * Primary color hues:
 *  blue:    0 degrees
 *  red:   120 degrees
 *  green: 240 degrees
 */
static int
hls_to_rgb(int hue, int lum, int sat)
{
    double min, max;
    int r, g, b;

    if (sat == 0) {
        r = g = b = lum;
    }

    /* https://wikimedia.org/api/rest_v1/media/math/render/svg/17e876f7e3260ea7fed73f69e19c71eb715dd09d */
    max = lum + sat * (1.0 - (lum > 50 ? (((lum << 2) / 100.0) - 1.0): - (2 * (lum / 100.0) - 1.0))) / 2.0;

    /* https://wikimedia.org/api/rest_v1/media/math/render/svg/f6721b57985ad83db3d5b800dc38c9980eedde1d */
    min = lum - sat * (1.0 - (lum > 50 ? (((lum << 2) / 100.0) - 1.0): - (2 * (lum / 100.0) - 1.0))) / 2.0;

    /* sixel hue color ring is roteted -120 degree from nowdays general one. */
    hue = (hue + 240) % 360;

    /* https://wikimedia.org/api/rest_v1/media/math/render/svg/937e8abdab308a22ff99de24d645ec9e70f1e384 */
    switch (hue / 60) {
    case 0:  /* 0 <= hue < 60 */
        r = max;
        g = (min + (max - min) * (hue / 60.0));
        b = min;
        break;
    case 1:  /* 60 <= hue < 120 */
        r = min + (max - min) * ((120 - hue) / 60.0);
        g = max;
        b = min;
        break;
    case 2:  /* 120 <= hue < 180 */
        r = min;
        g = max;
        b = (min + (max - min) * ((hue - 120) / 60.0));
        break;
    case 3:  /* 180 <= hue < 240 */
        r = min;
        g = (min + (max - min) * ((240 - hue) / 60.0));
        b = max;
        break;
    case 4:  /* 240 <= hue < 300 */
        r = (min + (max - min) * ((hue - 240) / 60.0));
        g = min;
        b = max;
        break;
    case 5:  /* 300 <= hue < 360 */
        r = max;
        g = min;
        b = (min + (max - min) * ((360 - hue) / 60.0));
        break;
    default:
#if HAVE___BUILTIN_UNREACHABLE
        __builtin_unreachable();
#endif
        break;
    }

    return SIXEL_XRGB(r, g, b);
}


static SIXELSTATUS
image_buffer_init(
    image_buffer_t     *image,
    int                 width,
    int                 height,
    int                 bgindex,
    sixel_allocator_t  *allocator)
{
    SIXELSTATUS status = SIXEL_FALSE;
    size_t size;
    int i;
    int n;
    int r;
    int g;
    int b;

    /* check parameters */
    if (width <= 0) {
        sixel_helper_set_additional_message(
            "image_buffer_init: an invalid width parameter detected.");
        status = SIXEL_BAD_INPUT;
        goto end;
    }
    if (height <= 0) {
        sixel_helper_set_additional_message(
            "image_buffer_init: an invalid width parameter detected.");
        status = SIXEL_BAD_INPUT;
        goto end;
    }
    if (width > SIXEL_WIDTH_LIMIT) {
        sixel_helper_set_additional_message(
            "image_buffer_init: given width parameter is too huge.");
        status = SIXEL_BAD_INPUT;
        goto end;
    }
    if (height > SIXEL_HEIGHT_LIMIT) {
        sixel_helper_set_additional_message(
            "image_buffer_init: given height parameter is too huge.");
        status = SIXEL_BAD_INPUT;
        goto end;
    }

    size = (size_t)(width) * (size_t)height * sizeof(unsigned char);
    image->width = width;
    image->height = height;
    image->data = (unsigned char *)sixel_allocator_malloc(allocator, size);
    image->ncolors = 2;

    if (image->data == NULL) {
        sixel_helper_set_additional_message(
            "sixel_deocde_raw: sixel_allocator_malloc() failed.");
        status = SIXEL_BAD_ALLOCATION;
        goto end;
    }
    memset(image->data, bgindex, size);

    /* palette initialization */
    for (n = 0; n < 16; n++) {
        image->palette[n] = sixel_default_color_table[n];
    }

    /* colors 16-231 are a 6x6x6 color cube */
    for (r = 0; r < 6; r++) {
        for (g = 0; g < 6; g++) {
            for (b = 0; b < 6; b++) {
                image->palette[n++] = SIXEL_RGB(r * 51, g * 51, b * 51);
            }
        }
    }

    /* colors 232-255 are a grayscale ramp, intentionally leaving out */
    for (i = 0; i < 24; i++) {
        image->palette[n++] = SIXEL_RGB(i * 11, i * 11, i * 11);
    }

    for (; n < SIXEL_PALETTE_MAX; n++) {
        image->palette[n] = SIXEL_RGB(255, 255, 255);
    }

    status = SIXEL_OK;

end:
    return status;
}


static SIXELSTATUS
image_buffer_resize(
    image_buffer_t     *image,
    int                 width,
    int                 height,
    int                 bgindex,
    sixel_allocator_t  *allocator)
{
    SIXELSTATUS status = SIXEL_FALSE;
    size_t size;
    unsigned char *alt_buffer;
    int n;
    int min_height;

    /* check parameters */
    if (width <= 0) {
        sixel_helper_set_additional_message(
            "image_buffer_init: an invalid width parameter detected.");
        status = SIXEL_BAD_INPUT;
        goto end;
    }
    if (height <= 0) {
        sixel_helper_set_additional_message(
            "image_buffer_init: an invalid width parameter detected.");
        status = SIXEL_BAD_INPUT;
        goto end;
    }
    if (height > SIXEL_HEIGHT_LIMIT) {
        sixel_helper_set_additional_message(
            "image_buffer_init: given height parameter is too huge.");
        status = SIXEL_BAD_INPUT;
        goto end;
    }
    if (width > SIXEL_WIDTH_LIMIT) {
        sixel_helper_set_additional_message(
            "image_buffer_init: given width parameter is too huge.");
        status = SIXEL_BAD_INPUT;
        goto end;
    }
    if (height > SIXEL_HEIGHT_LIMIT) {
        sixel_helper_set_additional_message(
            "image_buffer_init: given height parameter is too huge.");
        status = SIXEL_BAD_INPUT;
        goto end;
    }

    size = (size_t)width * (size_t)height;
    alt_buffer = (unsigned char *)sixel_allocator_malloc(allocator, size);
    if (alt_buffer == NULL || size == 0) {
        /* free source image */
        sixel_allocator_free(allocator, image->data);
        image->data = NULL;
        sixel_helper_set_additional_message(
            "image_buffer_resize: sixel_allocator_malloc() failed.");
        status = SIXEL_BAD_ALLOCATION;
        goto end;
    }

    min_height = height > image->height ? image->height: height;
    if (width > image->width) {  /* if width is extended */
        for (n = 0; n < min_height; ++n) {
            /* copy from source image */
            memcpy(alt_buffer + (size_t)width * (size_t)n,
                   image->data + (size_t)image->width * (size_t)n,
                   (size_t)image->width);
            /* fill extended area with background color */
            memset(alt_buffer + (size_t)width * (size_t)n + (size_t)image->width,
                   bgindex,
                   (size_t)(width - image->width));
        }
    } else {
        for (n = 0; n < min_height; ++n) {
            /* copy from source image */
            memcpy(alt_buffer + (size_t)width * (size_t)n,
                   image->data + (size_t)image->width * (size_t)n,
                   (size_t)width);
        }
    }

    if (height > image->height) {  /* if height is extended */
        /* fill extended area with background color */
        memset(alt_buffer + (size_t)width * (size_t)image->height,
               bgindex,
               (size_t)width * (size_t)(height - image->height));
    }

    /* free source image */
    sixel_allocator_free(allocator, image->data);

    image->data = alt_buffer;
    image->width = width;
    image->height = height;

    status = SIXEL_OK;

end:
    return status;
}


static SIXELSTATUS
parser_context_init(parser_context_t *context)
{
    SIXELSTATUS status = SIXEL_FALSE;

    context->state = PS_GROUND;
    context->pos_x = 0;
    context->pos_y = 0;
    context->max_x = 0;
    context->max_y = 0;
    context->attributed_pan = 2;
    context->attributed_pad = 1;
    context->attributed_ph = 0;
    context->attributed_pv = 0;
    context->repeat_count = 1;
    context->color_index = 15;
    context->bgindex = (-1);
    context->nparams = 0;
    context->param = 0;

    status = SIXEL_OK;

    return status;
}


static SIXELSTATUS
safe_addition_for_params(parser_context_t *context, unsigned char *p)
{
    SIXELSTATUS status = SIXEL_FALSE;
    int x;

    x = *p - '0'; /* 0 <= x <= 9 */
    if ((context->param > INT_MAX / 10) || (x > INT_MAX - context->param * 10)) {
        status = SIXEL_BAD_INTEGER_OVERFLOW;
        sixel_helper_set_additional_message(
            "safe_addition_for_params: ingeger overflow detected.");
        goto end;
    }
    context->param = context->param * 10 + x;
    status = SIXEL_OK;

end:
    return status;
}


/* convert sixel data into indexed pixel bytes and palette data */
SIXELAPI SIXELSTATUS
sixel_decode_raw_impl(
    unsigned char     *p,         /* sixel bytes */
    int                len,       /* size of sixel bytes */
    image_buffer_t    *image,
    parser_context_t  *context,
    sixel_allocator_t *allocator) /* allocator object */
{
    SIXELSTATUS status = SIXEL_FALSE;
    int n;
    int i;
    int y;
    int bits;
    int sixel_vertical_mask;
    int sx;
    int sy;
    int c;
    size_t pos;
    unsigned char *p0 = p;

    while (p < p0 + len) {
        switch (context->state) {
        case PS_GROUND:
            switch (*p) {
            case 0x1b:
                context->state = PS_ESC;
                p++;
                break;
            case 0x90:
                context->state = PS_DCS;
                p++;
                break;
            case 0x9c:
                p++;
                goto finalize;
            default:
                p++;
                break;
            }
            break;

        case PS_ESC:
            switch (*p) {
            case '\\':
            case 0x9c:
                p++;
                goto finalize;
            case 'P':
                context->param = -1;
                context->state = PS_DCS;
                p++;
                break;
            default:
                p++;
                break;
            }
            break;

        case PS_DCS:
            switch (*p) {
            case 0x1b:
                context->state = PS_ESC;
                p++;
                break;
            case '0':
            case '1':
            case '2':
            case '3':
            case '4':
            case '5':
            case '6':
            case '7':
            case '8':
            case '9':
                if (context->param < 0) {
                    context->param = 0;
                }
                status = safe_addition_for_params(context, p);
                if (SIXEL_FAILED(status)) {
                    goto end;
                }
                p++;
                break;
            case ';':
                if (context->param < 0) {
                    context->param = 0;
                }
                if (context->nparams < DECSIXEL_PARAMS_MAX) {
                    context->params[context->nparams++] = context->param;
                }
                context->param = 0;
                p++;
                break;
            case 'q':
                if (context->param >= 0 && context->nparams < DECSIXEL_PARAMS_MAX) {
                    context->params[context->nparams++] = context->param;
                }
                if (context->nparams > 0) {
                    /* Pn1 */
                    switch (context->params[0]) {
                    case 0:
                    case 1:
                        context->attributed_pad = 2;
                        break;
                    case 2:
                        context->attributed_pad = 5;
                        break;
                    case 3:
                    case 4:
                        context->attributed_pad = 4;
                        break;
                    case 5:
                    case 6:
                        context->attributed_pad = 3;
                        break;
                    case 7:
                    case 8:
                        context->attributed_pad = 2;
                        break;
                    case 9:
                        context->attributed_pad = 1;
                        break;
                    default:
                        context->attributed_pad = 2;
                        break;
                    }
                }

                if (context->nparams > 2) {
                    /* Pn3 */
                    if (context->params[2] == 0) {
                        context->params[2] = 10;
                    }
                    context->attributed_pan = context->attributed_pan * context->params[2] / 10;
                    context->attributed_pad = context->attributed_pad * context->params[2] / 10;
                    if (context->attributed_pan <= 0) {
                        context->attributed_pan = 1;
                    }
                    if (context->attributed_pad <= 0) {
                        context->attributed_pad = 1;
                    }
                }
                context->nparams = 0;
                context->state = PS_DECSIXEL;
                p++;
                break;
            default:
                p++;
                break;
            }
            break;

        case PS_DECSIXEL:
            switch (*p) {
            case '\x1b':
                context->state = PS_ESC;
                p++;
                break;
            case '"':
                context->param = 0;
                context->nparams = 0;
                context->state = PS_DECGRA;
                p++;
                break;
            case '!':
                context->param = 0;
                context->nparams = 0;
                context->state = PS_DECGRI;
                p++;
                break;
            case '#':
                context->param = 0;
                context->nparams = 0;
                context->state = PS_DECGCI;
                p++;
                break;
            case '$':
                /* DECGCR Graphics Carriage Return */
                context->pos_x = 0;
                p++;
                break;
            case '-':
                /* DECGNL Graphics Next Line */
                context->pos_x = 0;
                context->pos_y += 6;
                p++;
                break;
            default:
                if (*p >= '?' && *p <= '~') {  /* sixel characters */

                    sx = image->width;
                    while (sx < context->pos_x + context->repeat_count) {
                        sx *= 2;
                    }

                    sy = image->height;
                    while (sy < context->pos_y + 6) {
                        sy *= 2;
                    }

                    if (sx > image->width || sy > image->height) {
                        status = image_buffer_resize(image, sx, sy, context->bgindex, allocator);
                        if (SIXEL_FAILED(status)) {
                            goto end;
                        }
                    }

                    if (context->color_index > image->ncolors) {
                        image->ncolors = context->color_index;
                    }

                    if (context->pos_x < 0 || context->pos_y < 0) {
                        status = SIXEL_BAD_INPUT;
                        goto end;
                    }
                    bits = *p - '?';

                    if (bits == 0) {
                        context->pos_x += context->repeat_count;
                    } else {
                        sixel_vertical_mask = 0x01;
                        if (context->repeat_count <= 1) {
                            for (i = 0; i < 6; i++) {
                                if ((bits & sixel_vertical_mask) != 0) {
                                    pos = (size_t)image->width * (size_t)(context->pos_y + i) + (size_t)context->pos_x;
                                    image->data[pos] = context->color_index;
                                    if (context->max_x < context->pos_x) {
                                        context->max_x = context->pos_x;
                                    }
                                    if (context->max_y < (context->pos_y + i)) {
                                        context->max_y = context->pos_y + i;
                                    }
                                }
                                sixel_vertical_mask <<= 1;
                            }
                            context->pos_x += 1;
                        } else {
                            /* context->repeat_count > 1 */
                            for (i = 0; i < 6; i++) {
                                if ((bits & sixel_vertical_mask) != 0) {
                                    c = sixel_vertical_mask << 1;
                                    for (n = 1; (i + n) < 6; n++) {
                                        if ((bits & c) == 0) {
                                            break;
                                        }
                                        c <<= 1;
                                    }
                                    for (y = context->pos_y + i; y < context->pos_y + i + n; ++y) {
                                        memset(image->data + (size_t)image->width * (size_t)y + (size_t)context->pos_x,
                                               context->color_index,
                                               (size_t)context->repeat_count);
                                    }
                                    if (context->max_x < (context->pos_x + context->repeat_count - 1)) {
                                        context->max_x = context->pos_x + context->repeat_count - 1;
                                    }
                                    if (context->max_y < (context->pos_y + i + n - 1)) {
                                        context->max_y = context->pos_y + i + n - 1;
                                    }
                                    i += (n - 1);
                                    sixel_vertical_mask <<= (n - 1);
                                }
                                sixel_vertical_mask <<= 1;
                            }
                            context->pos_x += context->repeat_count;
                        }
                    }
                    context->repeat_count = 1;
                }
                p++;
                break;
            }
            break;

        case PS_DECGRA:
            /* DECGRA Set Raster Attributes " Pan; Pad; Ph; Pv */
            switch (*p) {
            case '\x1b':
                context->state = PS_ESC;
                p++;
                break;
            case '0':
            case '1':
            case '2':
            case '3':
            case '4':
            case '5':
            case '6':
            case '7':
            case '8':
            case '9':
                status = safe_addition_for_params(context, p);
                if (SIXEL_FAILED(status)) {
                    goto end;
                }
                p++;
                break;
            case ';':
                if (context->nparams < DECSIXEL_PARAMS_MAX) {
                    context->params[context->nparams++] = context->param;
                }
                context->param = 0;
                p++;
                break;
            default:
                if (context->nparams < DECSIXEL_PARAMS_MAX) {
                    context->params[context->nparams++] = context->param;
                }
                if (context->nparams > 0) {
                    context->attributed_pad = context->params[0];
                }
                if (context->nparams > 1) {
                    context->attributed_pan = context->params[1];
                }
                if (context->nparams > 2 && context->params[2] > 0) {
                    context->attributed_ph = context->params[2];
                }
                if (context->nparams > 3 && context->params[3] > 0) {
                    context->attributed_pv = context->params[3];
                }

                if (context->attributed_pan <= 0) {
                    context->attributed_pan = 1;
                }
                if (context->attributed_pad <= 0) {
                    context->attributed_pad = 1;
                }

                if (image->width < context->attributed_ph ||
                        image->height < context->attributed_pv) {
                    sx = context->attributed_ph;
                    if (image->width > context->attributed_ph) {
                        sx = image->width;
                    }

                    sy = context->attributed_pv;
                    if (image->height > context->attributed_pv) {
                        sy = image->height;
                    }

                    status = image_buffer_resize(image, sx, sy, context->bgindex, allocator);
                    if (SIXEL_FAILED(status)) {
                        goto end;
                    }
                }
                context->state = PS_DECSIXEL;
                context->param = 0;
                context->nparams = 0;
            }
            break;

        case PS_DECGRI:
            /* DECGRI Graphics Repeat Introducer ! Pn Ch */
            switch (*p) {
            case '\x1b':
                context->state = PS_ESC;
                p++;
                break;
            case '0':
            case '1':
            case '2':
            case '3':
            case '4':
            case '5':
            case '6':
            case '7':
            case '8':
            case '9':
                status = safe_addition_for_params(context, p);
                if (SIXEL_FAILED(status)) {
                    goto end;
                }
                p++;
                break;
            default:
                context->repeat_count = context->param;
                if (context->repeat_count == 0) {
                    context->repeat_count = 1;
                }
                if (context->repeat_count > 0xffff) {  /* check too huge number */
                    status = SIXEL_BAD_INPUT;
                    sixel_helper_set_additional_message(
                        "sixel_decode_raw_impl: detected too huge repeat parameter.");
                    goto end;
                }
                context->state = PS_DECSIXEL;
                context->param = 0;
                context->nparams = 0;
                break;
            }
            break;

        case PS_DECGCI:
            /* DECGCI Graphics Color Introducer # Pc; Pu; Px; Py; Pz */
            switch (*p) {
            case '\x1b':
                context->state = PS_ESC;
                p++;
                break;
            case '0':
            case '1':
            case '2':
            case '3':
            case '4':
            case '5':
            case '6':
            case '7':
            case '8':
            case '9':
                status = safe_addition_for_params(context, p);
                if (SIXEL_FAILED(status)) {
                    goto end;
                }
                p++;
                break;
            case ';':
                if (context->nparams < DECSIXEL_PARAMS_MAX) {
                    context->params[context->nparams++] = context->param;
                }
                context->param = 0;
                p++;
                break;
            default:
                context->state = PS_DECSIXEL;
                if (context->nparams < DECSIXEL_PARAMS_MAX) {
                    context->params[context->nparams++] = context->param;
                }
                context->param = 0;

                if (context->nparams > 0) {
                    context->color_index = context->params[0];
                    if (context->color_index < 0) {
                        context->color_index = 0;
                    } else if (context->color_index >= SIXEL_PALETTE_MAX) {
                        context->color_index = SIXEL_PALETTE_MAX - 1;
                    }
                }

                if (context->nparams > 4) {
                    if (context->params[1] == 1) {
                        /* HLS */
                        if (context->params[2] > 360) {
                            context->params[2] = 360;
                        }
                        if (context->params[3] > 100) {
                            context->params[3] = 100;
                        }
                        if (context->params[4] > 100) {
                            context->params[4] = 100;
                        }
                        image->palette[context->color_index]
                            = hls_to_rgb(context->params[2], context->params[3], context->params[4]);
                    } else if (context->params[1] == 2) {
                        /* RGB */
                        if (context->params[2] > 100) {
                            context->params[2] = 100;
                        }
                        if (context->params[3] > 100) {
                            context->params[3] = 100;
                        }
                        if (context->params[4] > 100) {
                            context->params[4] = 100;
                        }
                        image->palette[context->color_index]
                            = SIXEL_XRGB(context->params[2], context->params[3], context->params[4]);
                    }
                }
                break;
            }
            break;
        default:
            break;
        }
    }

finalize:
    if (++context->max_x < context->attributed_ph) {
        context->max_x = context->attributed_ph;
    }

    if (++context->max_y < context->attributed_pv) {
        context->max_y = context->attributed_pv;
    }

    if (image->width > context->max_x || image->height > context->max_y) {
        status = image_buffer_resize(image, context->max_x, context->max_y, context->bgindex, allocator);
        if (SIXEL_FAILED(status)) {
            goto end;
        }
    }

    status = SIXEL_OK;

end:
    return status;
}


/* convert sixel data into indexed pixel bytes and palette data */
SIXELAPI SIXELSTATUS
sixel_decode_raw(
    unsigned char       /* in */  *p,           /* sixel bytes */
    int                 /* in */  len,          /* size of sixel bytes */
    unsigned char       /* out */ **pixels,     /* decoded pixels */
    int                 /* out */ *pwidth,      /* image width */
    int                 /* out */ *pheight,     /* image height */
    unsigned char       /* out */ **palette,    /* ARGB palette */
    int                 /* out */ *ncolors,     /* palette size (<= 256) */
    sixel_allocator_t   /* in */  *allocator)   /* allocator object or null */
{
    SIXELSTATUS status = SIXEL_FALSE;
    parser_context_t context;
    image_buffer_t image;
    int n;

    image.data = NULL;

    if (allocator) {
        sixel_allocator_ref(allocator);
    } else {
        status = sixel_allocator_new(&allocator, NULL, NULL, NULL, NULL);
        if (SIXEL_FAILED(status)) {
            allocator = NULL;
            goto error;
        }
    }

    /* parser context initialization */
    status = parser_context_init(&context);
    if (SIXEL_FAILED(status)) {
        goto error;
    }

    /* buffer initialization */
    status = image_buffer_init(&image, 1, 1, context.bgindex, allocator);
    if (SIXEL_FAILED(status)) {
        goto error;
    }

    status = sixel_decode_raw_impl(p, len, &image, &context, allocator);
    if (SIXEL_FAILED(status)) {
        goto error;
    }

    *ncolors = image.ncolors + 1;
    int alloc_size = *ncolors;
    if (alloc_size < SIXEL_PALETTE_MAX) {
        /* memory access range should be 0 <= 255 */
        alloc_size = SIXEL_PALETTE_MAX;
    }
    *palette = (unsigned char *)sixel_allocator_malloc(allocator, (size_t)(alloc_size * 3));
    if (palette == NULL) {
        sixel_allocator_free(allocator, image.data);
        sixel_helper_set_additional_message(
            "sixel_deocde_raw: sixel_allocator_malloc() failed.");
        status = SIXEL_BAD_ALLOCATION;
        goto error;
    }
    for (n = 0; n < *ncolors; ++n) {
        (*palette)[n * 3 + 0] = image.palette[n] >> 16 & 0xff;
        (*palette)[n * 3 + 1] = image.palette[n] >> 8 & 0xff;
        (*palette)[n * 3 + 2] = image.palette[n] & 0xff;
    }

    *pwidth = image.width;
    *pheight = image.height;
    *pixels = image.data;

    status = SIXEL_OK;
    goto end;

error:
    free(image.data);
    image.data = NULL;

end:
    sixel_allocator_unref(allocator);
    return status;
}


/* deprecated */
SIXELAPI SIXELSTATUS
sixel_decode(unsigned char              /* in */  *p,         /* sixel bytes */
             int                        /* in */  len,        /* size of sixel bytes */
             unsigned char              /* out */ **pixels,   /* decoded pixels */
             int                        /* out */ *pwidth,    /* image width */
             int                        /* out */ *pheight,   /* image height */
             unsigned char              /* out */ **palette,  /* ARGB palette */
             int                        /* out */ *ncolors,   /* palette size (<= 256) */
             sixel_allocator_function   /* in */  fn_malloc)  /* malloc function */
{
    SIXELSTATUS status = SIXEL_FALSE;
    sixel_allocator_t *allocator = NULL;
    parser_context_t context;
    image_buffer_t image;
    int n;

    status = sixel_allocator_new(&allocator, fn_malloc, NULL, NULL, NULL);
    if (SIXEL_FAILED(status)) {
        allocator = NULL;
        goto end;
    }

    /* parser context initialization */
    status = parser_context_init(&context);
    if (SIXEL_FAILED(status)) {
        goto end;
    }

    /* buffer initialization */
    status = image_buffer_init(&image, 2048, 2048, context.bgindex, allocator);
    if (SIXEL_FAILED(status)) {
        goto end;
    }

    status = sixel_decode_raw_impl(p, len, &image, &context, allocator);
    if (SIXEL_FAILED(status)) {
        goto end;
    }

    *ncolors = image.ncolors + 1;
    *palette = (unsigned char *)sixel_allocator_malloc(allocator, (size_t)(*ncolors * 3));
    if (palette == NULL) {
        sixel_allocator_free(allocator, image.data);
        sixel_helper_set_additional_message(
            "sixel_deocde_raw: sixel_allocator_malloc() failed.");
        status = SIXEL_BAD_ALLOCATION;
        goto end;
    }
    for (n = 0; n < *ncolors; ++n) {
        (*palette)[n * 3 + 0] = image.palette[n] >> 16 & 0xff;
        (*palette)[n * 3 + 1] = image.palette[n] >> 8 & 0xff;
        (*palette)[n * 3 + 2] = image.palette[n] & 0xff;
    }

    *pwidth = image.width;
    *pheight = image.height;
    *pixels = image.data;

    status = SIXEL_OK;

end:
    sixel_allocator_unref(allocator);
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
