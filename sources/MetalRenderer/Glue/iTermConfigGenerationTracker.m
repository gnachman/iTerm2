//
//  iTermConfigGenerationTracker.m
//  iTerm2
//

#import "iTermConfigGenerationTracker.h"

@implementation iTermConfigGenerationTracker {
    iTermRowRenderInputs _lastRenderInputs;
    iTermColorMap *_lastColorMap;
    NSColorSpace *_lastColorSpace;
    iTermFontTable *_lastFontTable;
    uint64_t _generation;
    BOOL _have;
}

- (uint64_t)generationForRenderInputs:(const iTermRowRenderInputs *)inputs
                             colorMap:(iTermColorMap *)colorMap
                           colorSpace:(NSColorSpace *)colorSpace
                            fontTable:(iTermFontTable *)fontTable {
    // The font table is a stable stored property on the text view (a new object
    // only on font change), so pointer comparison is correct. The color space
    // needs isEqual: because AppKit may vend a fresh instance for the same
    // profile. The inputs struct is memset(0) before population by its owner, so
    // memcmp is reliable despite padding.
    //
    // The color map is compared by object identity (held strongly so a discarded
    // map cannot be reallocated at the same address). inputs->colorMapGeneration
    // catches in-place palette edits to a given map; this identity check catches
    // a map SWAP (profile/theme change) to a different object whose per-object
    // generation counter might coincidentally match the old map's last value.
    const BOOL changed = (!_have ||
                          memcmp(inputs, &_lastRenderInputs, sizeof(*inputs)) != 0 ||
                          colorMap != _lastColorMap ||
                          fontTable != _lastFontTable ||
                          !(colorSpace == _lastColorSpace || [colorSpace isEqual:_lastColorSpace]));
    if (changed) {
        _generation++;
        _lastRenderInputs = *inputs;
        _lastColorMap = colorMap;
        _lastColorSpace = colorSpace;
        _lastFontTable = fontTable;
        _have = YES;
    }
    return _generation;
}

@end
