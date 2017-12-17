//
//  iTermCharacterParts.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/15/17.
//

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

extern const int iTermTextureMapMaxCharacterParts;
extern const int iTermTextureMapMiddleCharacterPart;

NS_INLINE int iTermImagePartDX(int part) {
    return (part % iTermTextureMapMaxCharacterParts) - (iTermTextureMapMaxCharacterParts / 2);
}

NS_INLINE int iTermImagePartDY(int part) {
    return (part / iTermTextureMapMaxCharacterParts) - (iTermTextureMapMaxCharacterParts / 2);
}

NS_INLINE int iTermImagePartFromDeltas(int dx, int dy) {
    const int radius = iTermTextureMapMaxCharacterParts / 2;
    return (dx + radius) + (dy + radius) * iTermTextureMapMaxCharacterParts;
}

#if __cplusplus
}
#endif

