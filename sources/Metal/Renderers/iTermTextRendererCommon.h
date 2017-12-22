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

struct iTermMetalBackgroundColorRLE {
    vector_float4 color;
    unsigned short origin;  // Not strictly needed but this is needed to binary search the RLEs
    unsigned short count;
#if __cplusplus
    bool operator<(const iTermMetalBackgroundColorRLE &other) const {
        return origin < other.origin;
    }
    bool operator<(const int &other) const {
        return origin < other;
    }
#endif
};

typedef struct iTermMetalBackgroundColorRLE iTermMetalBackgroundColorRLE;

