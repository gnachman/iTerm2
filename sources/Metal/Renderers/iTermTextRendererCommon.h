//
//  iTermTextRendererCommon.h
//  iTerm2
//
//  Created by George Nachman on 12/22/17.
//

#import <simd/simd.h>

typedef NS_ENUM(int, iTermTextRendererStat) {
    iTermTextRendererStatNewQuad,
    iTermTextRendererStatNewPIU,
    iTermTextRendererStatNewDims,
    iTermTextRendererStatNewTextInfo,
    iTermTextRendererStatSubpixelModel,
    iTermTextRendererStatDraw,

    iTermTextRendererStatCount
};

// Describes how underlines should be drawn.
typedef struct {
    // Offset from the top of the cell, in points.
    float offset;

    // Line thickness, in points.
    float thickness;

    // Color to draw line in.
    vector_float4 color;
} iTermMetalUnderlineDescriptor;

NS_INLINE NSString *iTermMetalUnderlineDescriptorDescription(iTermMetalUnderlineDescriptor *d) {
    return [NSString stringWithFormat:@"offset=%@, thickness=%@, color=(%@, %@, %@, %@)",
            @(d->offset),
            @(d->thickness),
            @(d->color.x),
            @(d->color.y),
            @(d->color.z),
            @(d->color.w)];
}

// RLEs are in logical order. logicalOrigin gives the first logical index, while `origin` gives the
// leftmost visual index. Runs will be consecutive in both logical and visual order (although
// visual order may be reversed, it is irrelevant since all the cells have the same background color).
struct iTermMetalBackgroundColorRLE {
    vector_float4 color;
    unsigned short origin;  // visual origin
    unsigned short logicalOrigin;
    unsigned short count;
    unsigned char isDefault;  // Is this the default background color?
#if __cplusplus
    bool operator<(const iTermMetalBackgroundColorRLE &other) const {
        return origin < other.origin;
    }
    bool operator<(const int &other) const {
        return origin < other;
    }
#endif
};
#if __cplusplus
inline bool operator<(const int &origin, const iTermMetalBackgroundColorRLE &other) {
    return origin < other.origin;
}
#endif

typedef struct iTermMetalBackgroundColorRLE iTermMetalBackgroundColorRLE;

NS_INLINE NSString *iTermMetalBackgroundColorRLEDescription(const iTermMetalBackgroundColorRLE *c) {
    return [NSString stringWithFormat:@"color=(%0.2f, %0.2f, %0.2f, %0.2f) origin=%d count=%d",
            c->color.x,
            c->color.y,
            c->color.z,
            c->color.w,
            c->origin,
            c->count];
}
