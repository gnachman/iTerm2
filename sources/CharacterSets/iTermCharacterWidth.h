//
//  iTermCharacterWidth.h
//  iTerm2
//
//  Fast character width determination for terminal rendering.
//  Uses bitmaps for BMP and binary search for supplementary planes.
//

#ifndef iTermCharacterWidth_h
#define iTermCharacterWidth_h

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Fast check for double-width characters.
// This is a pure C implementation that avoids all Objective-C overhead.
bool iTermIsDoubleWidthCharacter(uint32_t unicode,
                                 bool ambiguousIsDoubleWidth,
                                 int unicodeVersion,
                                 bool fullWidthFlags);

// Individual checks (exposed for testing)
bool iTermIsFullWidthCharacter(uint32_t unicode, int unicodeVersion);
bool iTermIsAmbiguousWidthCharacter(uint32_t unicode, int unicodeVersion);
bool iTermIsFlagCharacter(uint32_t unicode, int unicodeVersion);

#ifdef __cplusplus
}
#endif

#endif /* iTermCharacterWidth_h */
