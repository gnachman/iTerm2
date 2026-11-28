# Converting a color to L*a*b* swaps its green and blue components

**Where:** `sources/Categories/NSColor+iTerm.m`, `-labColor` (near line 403).

**What happens:** every L\*a\*b\* value the app computes from an `NSColor` is that of a different color, with green and blue exchanged. Neutral grays are unaffected; saturated colors are not. Users of it:
- `-perceptualDistanceTo:`, which `+[iTermColorPresets differenceBetweenColorDicts::]` uses, so Settings' guess at the custom color preset most similar to the current colors (`-mostSimilarCustomPresetName` in `ProfilesColorsPreferencesViewController.m`) measures distances in the wrong space.
- `iTermColorSuggester`, which uses the lightness of the default background to decide how different a suggested trigger highlight color must be (Add Trigger from a selection). The lightness of a green or blue background is far off.

**Why:**

```objc
const iTermSRGBColor srgb = (iTermSRGBColor) {
    .r = color.redComponent,
    .g = color.blueComponent,
    .b = color.greenComponent
};
```

**How to see it:** `NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1).labColor().l` should be about 88 (pure green) and is about 32 (the lightness of pure blue). Seen by reading the code; not run.

**Suggested fix:** `.g = color.greenComponent, .b = color.blueComponent`. This changes which trigger colors are suggested and which preset is called most similar.

**Found:** 2026-11-21, while moving `iTermColorSuggester` to Swift.

**Checked against the tree:** 2026-11-27. The swapped initializer is unchanged.
