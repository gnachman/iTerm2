//
//  iTermConfigGenerationTracker.m
//  iTerm2
//

#import "iTermConfigGenerationTracker.h"

@implementation iTermConfigGenerationTracker {
    iTermRowRenderInputs _lastRenderInputs;
    NSColorSpace *_lastColorSpace;
    iTermFontTable *_lastFontTable;
    uint64_t _generation;
    BOOL _have;
}

- (uint64_t)generationForRenderInputs:(const iTermRowRenderInputs *)inputs
                           colorSpace:(NSColorSpace *)colorSpace
                            fontTable:(iTermFontTable *)fontTable {
    // The font table is a stable stored property on the text view (a new object
    // only on font change), so pointer comparison is correct. The color space
    // needs isEqual: because AppKit may vend a fresh instance for the same
    // profile. The inputs struct is memset(0) before population by its owner, so
    // memcmp is reliable despite padding.
    const BOOL changed = (!_have ||
                          memcmp(inputs, &_lastRenderInputs, sizeof(*inputs)) != 0 ||
                          fontTable != _lastFontTable ||
                          !(colorSpace == _lastColorSpace || [colorSpace isEqual:_lastColorSpace]));
    if (changed) {
        _generation++;
        _lastRenderInputs = *inputs;
        _lastColorSpace = colorSpace;
        _lastFontTable = fontTable;
        _have = YES;
    }
    return _generation;
}

@end
