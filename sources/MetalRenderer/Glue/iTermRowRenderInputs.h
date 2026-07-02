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
//  This is an incremental migration: fields are added here as their reads are
//  routed through the struct. Not yet migrated: attributed-string-builder
//  settings, the two advanced settings read in iTermMutableAttributedStringBuilder,
//  cell metrics / scale / baselineOffset, and the object-identity fields that
//  the (not-yet-added) fingerprint will need.

#import <Cocoa/Cocoa.h>
#import <simd/simd.h>
#import "ITAddressBookMgr.h"   // iTermThinStrokesSetting

typedef struct {
    vector_float4 unfocusedSelectionColor;
    CGFloat transparencyAlpha;
    iTermThinStrokesSetting thinStrokes;

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
} iTermRowRenderInputs;
