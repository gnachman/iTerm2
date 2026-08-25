========================================================================
 BIDI / RTL manual test files  (cat these in a debug build)
========================================================================

These files exercise the right-to-left features. Each test string sits on
its own line; the ASCII lines above it say what to look for.

To A/B new vs old: build the `bidi-mirroring` branch for NEW behavior and
`master` (or `bidi-mirroring-prerebase-backup`) for OLD, then cat the same
file in each.

------------------------------------------------------------------------
 SETUP (do this in the NEW build)
------------------------------------------------------------------------
1. Turn ON "right-to-left text support" (the Bidi preference). With it OFF
   every file below renders in plain logical order and nothing reorders.

2. Some files need an extra Advanced setting (Settings > Advanced, search):
   - bidi-test-2 (paragraph direction): turn ON
       "Auto-detect paragraph writing direction"
   - bidi-test-3 list markers / cursive: turn ON the profile option
       "Use Ligatures" (Profiles > Text) so Persian/Arabic letters join

3. Test both renderers: run once with the GPU (Metal) renderer on and once
   off; the two must match.

------------------------------------------------------------------------
 THE FILES
------------------------------------------------------------------------
 bidi-test-1-mirroring.txt          brackets, parens, guillemets
 bidi-test-2-paragraph-direction.txt   which way a whole line lays out
 bidi-test-3-cursive-marks-markers.txt cursive joining, combining marks,
                                        numbered list markers
 bidi-test-4-selection-copy.txt     lines to drag-select and copy
 (see also the PR's own zwnj-compare.txt for the paste-stripping test)
========================================================================
