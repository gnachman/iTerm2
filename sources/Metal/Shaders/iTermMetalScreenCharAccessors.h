//
//  iTermMetalScreenCharAccessors.h
//  iTerm2
//
//  Created by George Nachman on 2/19/18.
//

#import "iTermScreenChar.h"

#ifdef __METAL_VERSION__

// This abomination of a file exists because Metal doesn't seem to pack structs the same as
// Objective-C, leading to insanity.#ifdef __METAL_VERSION__

inline unichar SCCode(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return (p[1] << 8) | p[0];
}

inline unsigned int SCForegroundColor(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return p[2];
}

inline unsigned int SCForegroundGreen(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return p[3];
}

inline unsigned int SCForegroundBlue(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return p[4];
}

inline unsigned int SCBackgroundColor(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return p[5];
}

inline unsigned int SCBackgroundGreen(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return p[6];
}

inline unsigned int SCBackgroundBlue(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return p[7];
}

inline ColorMode SCForegroundMode(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return static_cast<ColorMode>(p[8] & 3);
}

inline ColorMode SCBackgroundMode(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return static_cast<ColorMode>((p[8] >> 2) & 3);
}

inline bool SCComplex(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return !!(p[8] & 16);
}

inline bool SCBold(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return !!(p[8] & 32);
}

inline bool SCFaint(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return !!(p[8] & 64);
}

inline bool SCItalic(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return !!(p[8] & 128);
}

inline bool SCBlink(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return !!(p[9] & 1);
}

inline bool SCUnderline(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return !!(p[9] & 2);
}

inline bool SCImage(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return !!(p[9] & 4);
}

inline unsigned short SCURLCode(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return (p[11] << 8) | p[10];
}

#else

// I guess these should be inline methods but this makes debugging more convenient since lldb won't
// try to step into these things.
#define SCCode(c) ((c)->code)
#define SCForegroundColor(c) ((c)->foregroundColor)
#define SCForegroundGreen(c) ((c)->fgGreen)
#define SCForegroundBlue(c) ((c)->fgBlue)

#define SCBackgroundColor(c) ((c)->backgroundColor)
#define SCBackgroundGreen(c) ((c)->bgGreen)
#define SCBackgroundBlue(c) ((c)->bgBlue)

#define SCForegroundMode(c) ((ColorMode)(c)->foregroundColorMode)
#define SCBackgroundMode(c) ((ColorMode)(c)->backgroundColorMode)

#define SCComplex(c) ((c)->complexChar)
#define SCBold(c) ((c)->bold)
#define SCFaint(c) ((c)->faint)
#define SCItalic(c) ((c)->italic)
#define SCBlink(c) ((c)->blink)
#define SCUnderline(c) ((c)->underline)
#define SCImage(c) ((c)->image)
#define SCURLCode(c) ((c)->urlCode)

#endif

