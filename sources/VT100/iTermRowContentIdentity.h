//
//  iTermRowContentIdentity.h
//  iTerm2
//
//  Collision-free identity of a displayed row's CONTENT (the screen_char_t line
//  and its metadata), used as one component of the per-row draw cache key. Grid
//  lines and scrollback lines use independent global generation counters, so
//  `source` distinguishes the two generation spaces. Equal
//  (source, generation, mutationCount, remainder, width, eligibleForDWC) tuples
//  imply equal row content.
//
//  IMPORTANT for the (not-yet-written) cache consumer: this identifies content
//  ONLY. It is necessary but NOT sufficient as a cache key. A correct lookup key
//  must ALSO incorporate:
//    - the frame-config generation (iTermConfigGenerationTracker over
//      iTermRowRenderInputs + colorMap/fontTable/colorSpace), and
//    - the per-row OVERLAYS that change the blobs but are NOT captured by the
//      content identity: selection set, find matches, semantic-history/hover
//      underline range, and annotation ranges. (External attributes ARE covered
//      by the content generation. selected-command dimming and the timestamp are
//      draw-time/separate-renderer effects, NOT blob inputs.)
//  Render-only inputs (antialiasing, cell metrics/scale/baseline, underline
//  descriptors, and non-cell renderers) are deliberately excluded from both keys:
//  they affect the downstream glyph texture (keyed on the glyph key) or separate
//  renderers, not the cached blobs.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(uint8_t, iTermRowContentSource) {
    iTermRowContentSourceGrid = 0,     // generation is VT100Grid generationForLine:
    iTermRowContentSourceHistory = 1,  // generation is LineBlock.generation
};

// Field order is large-to-small with a trailing `reserved` so the struct has NO
// implicit padding. That makes it safe to compare/hash byte-wise: a compound
// literal that names every field zero-initializes `reserved` (an unnamed
// member), and with no implicit padding there are no other indeterminate bytes.
// Keep it hole-free when adding fields.
typedef struct {
    int64_t generation;     // 0 is a reserved "uncacheable" sentinel (see below)
    int64_t mutationCount;  // history: disambiguates in-place edits; 0 for grid
    int32_t remainder;      // wrapped-line offset within the block; 0 for grid lines
    // Wrapping width. Required because a scrollback block's `generation` is
    // width-independent (it identifies the raw content) while `remainder` is an
    // offset AT THIS WIDTH: the same (generation, remainder) denotes different
    // wrapped content at different widths, so without this the tuple would
    // collide across a column-count resize.
    int32_t width;
    iTermRowContentSource source;  // uint8_t
    // The last scrollback row is rendered joined with the grid's leading DWC, so
    // its content depends on the grid-top DWC state even though the block didn't
    // change. This captures that dependency for that one boundary row (0 for all
    // other rows).
    uint8_t eligibleForDWC;
    uint8_t reserved[6];    // pad to a multiple of 8; kept zeroed for byte comparison
} iTermRowContentIdentity;

// Real generations start at 1 (both the grid line counter and LineBlock start
// there), so generation == 0 never identifies real, uniquely-known content. It
// is used for lines whose content can't be uniquely identified (a never-written
// grid line, or a failed scrollback lookup). The per-row cache MUST treat a
// generation-0 identity as always-miss / never-store so such lines can't
// collide.
static const int64_t iTermRowContentGenerationUncacheable = 0;
