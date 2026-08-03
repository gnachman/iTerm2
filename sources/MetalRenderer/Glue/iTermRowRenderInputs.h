//
//  iTermRowRenderInputs.h
//  iTerm2
//
//  Single source of truth for the frame-constant inputs that the Metal row
//  build (metalGetGlyphKeysData and its callees) reads. The build reads these
//  values ONLY from this struct so that, in a later step, a per-row output
//  cache can fingerprint exactly the set of inputs that affect a row's output.
//
//  Pure POD (no object pointers): trivially copyable and, later, byte-hashable.
//  Objects the build must CALL (colorMap, fontTable) are passed separately and
//  will contribute to the fingerprint via their own generation/identity.
//
//  EXCLUDED by contract (keyed elsewhere; must NOT live here):
//    - per-row screen_char_t content and per-line metadata
//    - per-row overlays (selection, find, underline range, annotations, eaIndex)
//    - blink PHASE (_blinkingItemsVisible): a per-entry bit, not a config input
//
//  This holds every frame-constant input that changes the row BUILD output (the
//  glyph-keys/attributes/background-RLE blobs). Inputs that only affect downstream
//  glyph-texture rasterization (antialiasing, cell metrics, scale, baseline,
//  underline descriptors) or separate renderers (cursor guide, offscreen command
//  line, marks) are deliberately NOT here: the texture cache is keyed on the glyph
//  key, and those renderers are outside the cached blobs. minimumContrast is
//  blob-affecting but lives on iTermColorMap, so it's covered by colorMapGeneration.

#import <Cocoa/Cocoa.h>
#import <simd/simd.h>
#import "ITAddressBookMgr.h"   // iTermThinStrokesSetting

// This struct holds only exactly-comparable values (counters and exact
// scalars); it does NOT hold lossy hashes, so a config generation derived by
// comparing it (memcmp) is collision-free. Objects that can't be flattened
// exactly (color space, font table) are compared alongside it rather than
// hashed into it. The owner must memset(0) the struct before populating so its
// padding is defined for memcmp.
typedef struct {
    // 16-byte
    vector_float4 unfocusedSelectionColor;

    // 8-byte
    CGFloat transparencyAlpha;
    iTermThinStrokesSetting thinStrokes;  // NSInteger-width
    NSInteger colorMapGeneration;         // iTermColorMap.generation: exact palette identity

    // 1-byte
    BOOL reverseVideo;
    BOOL useCustomBoldColor;
    BOOL brightenBold;
    BOOL useSelectedTextColor;
    BOOL transparencyAffectsOnlyDefaultBackgroundColor;
    BOOL isFrontTextView;
    BOOL ligaturesEnabled;
    BOOL useNativePowerlineGlyphs;
    BOOL isRetina;
    BOOL blinkAllowed;
    BOOL useNonAsciiFont;
    BOOL underlineHyperlinks;

    // Attributed-string-builder shaping settings. Each independently changes the
    // glyph-keys blob (fast path vs CoreText shaping, ligature level, font
    // variant), so each must be compared. ligaturesEnabled above is just
    // (asciiLigatures || nonAsciiLigatures) used as a gate and is NOT sufficient.
    BOOL asciiLigatures;
    BOOL asciiLigaturesAvailable;
    BOOL nonAsciiLigatures;
    BOOL zippy;
    BOOL preferSpeedToFullLigatureSupport;
    BOOL lowFiCombiningMarks;
    BOOL boldAllowed;
    BOOL italicAllowed;

    uint8_t reserved[4];  // pad to a multiple of 16; kept zeroed by memset
} iTermRowRenderInputs;
