# Plan: Add DECDWL / DECDHL Support (Double-Width and Double-Height Lines)

## Context

DEC VT100/VT220 terminals support line-level attributes that make all characters on a line appear double-width (DECDWL) or double-height (DECDHL). These are controlled by escape sequences:
- `ESC # 3` - DECDHL top half (double height + double width, show top half)
- `ESC # 4` - DECDHL bottom half (double height + double width, show bottom half)
- `ESC # 5` - DECSWL (revert to normal single-width)
- `ESC # 6` - DECDWL (double width only)

**How double-height works:** Applications must print the same text on two consecutive lines, marking one as "top" and the other as "bottom." The terminal renders each independently — it scales glyphs 2x and clips to the appropriate half. The terminal does not enforce content pairing.

**Current state in iTerm2:** Token types `VT100CSI_DECDHL` and `VT100CSI_DECDWL` exist but are no-ops. The parser only recognizes `ESC # 8` (DECALN); `ESC # 3/4/5/6` fall through to `VT100_NOTSUPPORT`.

### Impedance Mismatches

1. **Line-level vs. cell-level attributes:** iTerm2's model is cell-oriented (`screen_char_t`). DECDWL/DECDHL are line-level attributes with no existing per-line attribute storage mechanism.

2. **Uniform grid vs. variable effective width:** The VT100Grid assumes all lines have the same width. DECDWL/DECDHL lines hold `width/2` logical characters but use all `width` physical cells (with spacers). Cursor positioning, wrapping, insertion, and deletion all assume uniform character-to-cell mapping.

3. **Every-cell-is-one-charWidth assumption:** Search, filter, selection, right-click, smart selection, semantic history, and many other features assume each cell holds one character at one `charWidth`. A new spacer character (like TAB_FILLER/DWC_RIGHT) lets these subsystems handle double-width lines by following the existing pattern.

4. **Independent lines vs. paired display:** Double-height requires two rows to show one line of text, but the grid treats each row independently. Scrolling, selection, editing, and resize can break the visual pairing.

5. **Fixed-size glyph atlas vs. 2x rendering:** The Metal renderer pre-rasterizes glyphs at one size via `iTermCharacterSource`. The existing parts system (radius-based grid splitting via `bitmapForPart:`) can split 2x-rendered glyphs into standard cell-sized parts.

6. **Renderer consistency:** Both Metal and Core Text paths must produce identical output by using the same `iTermCharacterSource` rendering. iTerm2 switches between renderers (e.g., low power mode) and visual glitches are unacceptable.

7. **LineBuffer rewrapping assumes uniform width:** On resize, lines are rewrapped at the new terminal width. DECDWL/DECDHL lines must rewrap accounting for the DWL_SPACER interleaving.

---

## Implementation Plan

### Phase 1: Line Attribute Storage

**Add `iTermLineAttribute` enum and store in metadata.**

Files: `sources/iTermMetadata.h` / `.m`, `sources/VT100LineInfo.h` / `.m`

```c
typedef enum : uint8_t {
    iTermLineAttributeSingleWidth = 0,      // Normal (DECSWL / default)
    iTermLineAttributeDoubleWidth = 1,      // DECDWL (ESC # 6)
    iTermLineAttributeDoubleHeightTop = 2,  // DECDHL top (ESC # 3)
    iTermLineAttributeDoubleHeightBottom = 3 // DECDHL bottom (ESC # 4)
} iTermLineAttribute;
```

Add `iTermLineAttribute lineAttribute` field to both `iTermMetadata` and `iTermImmutableMetadata`. Default value 0 = single-width — existing code initializes correctly.

Update all functions that create/copy/encode/decode metadata:
- `iTermMetadataInit`, `iTermImmutableMetadataInit`
- `iTermMetadataCopy`, `iTermImmutableMetadataCopy`, `iTermImmutableMetadataMutableCopy`
- `iTermMetadataMakeImmutable`
- `iTermMetadataEncodeToArray` / `iTermMetadataInitFromArray`
- `iTermMetadataEncodeToData` / `iTermMetadataDecodedFromData`
- `iTermMetadataDefault`, `iTermImmutableMetadataDefault`

Add accessor to `VT100LineInfo`: `setLineAttribute:` / `lineAttribute`.

Add helpers:
```c
NS_INLINE BOOL iTermLineAttributeIsDoubleWidth(iTermLineAttribute attr) {
    return attr != iTermLineAttributeSingleWidth;
}
NS_INLINE int iTermEffectiveLineWidth(int width, iTermLineAttribute attr) {
    return iTermLineAttributeIsDoubleWidth(attr) ? width / 2 : width;
}
```

### Phase 2: DWL_SPACER Special Character

**Create a new special character for double-width line spacers.**

File: `sources/ScreenChar.h`

Add to the private-use character range (currently 0x0001–0x0007):
```c
#define DWL_SPACER 0x0008  // or next available in ITERM2_PRIVATE range
```

Add helper functions:
```c
NS_INLINE BOOL ScreenCharIsDWL_SPACER(screen_char_t c) { return c.code == DWL_SPACER && !c.complexChar; }
NS_INLINE void ScreenCharSetDWL_SPACER(screen_char_t *c) { c->code = DWL_SPACER; c->complexChar = NO; }
```

DWL_SPACER is analogous to DWC_RIGHT but specifically for DECDWL/DECDHL lines. We don't reuse DWC_RIGHT because a double-width character like `Ｌ` on a DECDWL line needs both DWC_RIGHT (for its natural right half) AND DWL_SPACER (for the line-doubling), resulting in 4 cells:

```
Normal:   [Ｌ][DWC_RIGHT]
DECDWL:   [Ｌ][DWL_SPACER][DWC_RIGHT][DWL_SPACER]
```

### Phase 3: Parser Changes

**Make ESC # 3/4/5/6 generate proper tokens.**

File: `sources/VT100OtherParser.m` (lines 57-70)

Add cases to the `case '#':` switch:
```c
case '3': result->type = VT100CSI_DECDHL; result->u.csi.p[0] = 3; break; // top
case '4': result->type = VT100CSI_DECDHL; result->u.csi.p[0] = 4; break; // bottom
case '5': result->type = VT100CSI_DECSWL; break;
case '6': result->type = VT100CSI_DECDWL; break;
```

Add `VT100CSI_DECSWL` to token enum in `sources/VT100Token.h` and name mapping in `sources/VT100Token.m`.

### Phase 4: Terminal Execution + Line Content Transformation

**Implement token handlers and transform line content on attribute change.**

File: `sources/VT100Terminal.m` (around line 2005)

```objc
case VT100CSI_DECDHL: {
    iTermLineAttribute attr = (token.csi->p[0] == 3) ? iTermLineAttributeDoubleHeightTop
                                                      : iTermLineAttributeDoubleHeightBottom;
    [delegate_ terminalSetLineAttribute:attr];
    break;
}
case VT100CSI_DECDWL:
    [delegate_ terminalSetLineAttribute:iTermLineAttributeDoubleWidth];
    break;
case VT100CSI_DECSWL:
    [delegate_ terminalSetLineAttribute:iTermLineAttributeSingleWidth];
    break;
```

**Line content transformation on attribute change:**

In VT100Screen's `terminalSetLineAttribute:` implementation (or in VT100Grid):

When transitioning **normal → double-width** (DECDWL/DECDHL):
1. Read existing characters from positions 0..width/2-1
2. Expand with DWL_SPACERs: write char at position 2*i, DWL_SPACER at position 2*i+1
3. Characters that were at positions ≥ width/2 are lost (matches xterm — they become inaccessible)
4. Shift external attribute indices accordingly
5. Set line attribute on VT100LineInfo

When transitioning **double-width → normal** (DECSWL):
1. Read characters from even positions (skipping DWL_SPACERs)
2. Compact: write them contiguously at positions 0, 1, 2, ...
3. Fill remaining positions with blanks
4. Shift external attribute indices
5. Clear line attribute

When transitioning between DECDWL ↔ DECDHL (both are double-width):
- Content stays the same (same DWL_SPACER layout)
- Only the line attribute flag changes

### Phase 5: Character Input on Double-Width Lines

**Make `appendCharsAtCursor:` interleave DWL_SPACERs.**

File: `sources/VT100Grid.m`

When appending characters to a DECDWL/DECDHL line, each input character consumes 2 physical grid cells:
- Position 2*c: the character itself
- Position 2*c+1: DWL_SPACER

For an incoming DWC character (already 2 cells wide), it consumes 4 physical cells:
- Position 2*c: left half of DWC
- Position 2*c+1: DWL_SPACER
- Position 2*c+2: DWC_RIGHT
- Position 2*c+3: DWL_SPACER

The effective logical width is `width/2`. When the logical cursor reaches position `width/2`, wrapping occurs. This is the same behavior as xterm. (Terminal.app silently swallows characters until the normal-width wrap point, but that appears to be a bug.)

Other grid methods needing DWL_SPACER awareness:
- `eraseLine:` — clear including DWL_SPACERs
- `deleteChars:startingAt:` / `insertChar:at:times:` — maintain DWL_SPACER interleaving
- `cursorLeft:` / `cursorRight:` — skip over DWL_SPACER cells
- Tab stop handling — tab stops apply to logical columns, not physical
- `setCursorX:` — clamp to effective width, position at 2*logicalX

### Phase 6: DWL_SPACER Handling and DWC_RIGHT Audit

**Two concerns:**
1. Add DWL_SPACER handling everywhere TAB_FILLER and DWC_RIGHT are handled.
2. Audit ALL code that uses DWC_RIGHT to verify it still works when DWL_SPACER appears between a DWC character and its DWC_RIGHT. On a double-width line, a DWC expands to `[char][DWL_SPACER][DWC_RIGHT][DWL_SPACER]` — code that assumes DWC_RIGHT is immediately right of its character (e.g., `line[x-1]` when `line[x]` is DWC_RIGHT) will find DWL_SPACER instead.

**Complete list of files referencing DWC_RIGHT (27 files — all need audit):**

| File | DWC_RIGHT usage to audit | DWL_SPACER handling needed |
|------|--------------------------|---------------------------|
| `sources/VT100Grid.m` | Extensive: cursor movement, line wrapping, char insertion/deletion, DWC split handling | Yes — skip DWL_SPACER in `lengthOfLineNumber:`, `numberOfLinesUsed`, cursor movement |
| `sources/ScreenChar.h` | Helper functions: `ScreenCharIsDWC_RIGHT`, `ScreenCharSetDWC_RIGHT` | Already has DWL_SPACER helpers |
| `sources/ScreenChar.m` | `StringToScreenChars`: DWC_RIGHT insertion after double-width chars | May need DWL_SPACER awareness for width calculations |
| `sources/ScreenCharArray.m` | Line manipulation, concatenation | Check subrange/concat with DWL_SPACER between char and DWC_RIGHT |
| `sources/iTermTextExtractor.m` | Text extraction skips DWC_RIGHT; `haveDoubleWidthExtensionAt:` | Must also skip DWL_SPACER during extraction |
| `sources/iTermWordExtractor.m` | `classForCharacter:` returns `kTextExtractorClassDoubleWidthPlaceholder` for DWC_RIGHT | Classify DWL_SPACER same way |
| `sources/iTermWordExtractor.swift` | Range adjustment extends selection over DWC_RIGHT | Also extend over DWL_SPACER |
| `sources/iTermWordExtractor.h` | Class enum definition | No change needed |
| `sources/PTYTextView.m` | Mouse click coordinate snapping, cursor movement | Snap DWL_SPACER clicks to preceding character |
| `sources/iTermTextDrawingHelper.m` | Drawable check filters DWC_RIGHT | DWL_SPACER already filtered (private-use range) |
| `sources/iTermAttributedStringBuilder.m` | Groups DWC_RIGHT with preceding char for rendering | Must also handle DWL_SPACER between char and DWC_RIGHT |
| `sources/iTermMetalPerFrameState.m` | DWC_RIGHT detection for cursor width, selection state | Cursor on DWL line spans 2 cells; selection expansion |
| `sources/iTermBackgroundColorRun.m` | Background color run splitting at DWC boundaries | Check if DWL_SPACER between char and DWC_RIGHT affects runs |
| `sources/VT100ScreenMutableState.m` | RTL detection, screen char operations | Verify DWC handling with interleaved DWL_SPACERs |
| `sources/VT100ScreenMutableState+TerminalDelegate.m` | Content transformation (already implemented) | Already handles expansion |
| `sources/VT100ScreenState.m` | Screen state queries | Check DWC-related queries |
| `sources/LineBlock.mm` | Line wrapping: don't start line with DWC_RIGHT | Also don't start with DWL_SPACER |
| `sources/iTermRecordingCodec.m` | Recording format DWC handling | Handle DWL_SPACER in recordings |
| `sources/iTermDoubleWidthCharacterCache.m` | Cache of DWC positions | May need to account for DWL_SPACER offsets |
| `sources/JSONPrettyPrinter.swift` | JSON output handling | Check if DWC_RIGHT handling is affected |
| `sources/PathExtractor.swift` | Path extraction from terminal content | Check DWC boundary handling |
| `sources/CompressibleCharacterBuffer.swift` | Buffer compression | Check DWC pair handling with interleaved spacers |
| `sources/Fancy Strings/iTermString/iTermNonASCIIString.swift` | Non-ASCII string handling | Check DWC pair assumptions |
| `sources/Fancy Strings/iTermString/iTermLegacyStyleString.swift` | Legacy string operations | Check DWC pair assumptions |
| `sources/Fancy Strings/iTermString/iTermUniformString.swift` | Uniform string operations | Check DWC pair assumptions |
| `sources/Fancy Strings/iTermMutableString/iTermLegacyMutableString.swift` | Mutable string DWC handling | Check DWC pair assumptions |
| `sources/Fancy Strings/iTermLineString.swift` | Line string operations | Check DWC pair assumptions |

**Key pattern to look for:** Any code that does `line[x-1]` or `line[x+1]` relative to a DWC_RIGHT position, assuming the adjacent cell is the real character. On a double-width line, the real character is at `x-2` (with DWL_SPACER at `x-1`).

**Mitigation strategy:** Most of this code will never encounter DWL_SPACER because it only appears on double-width lines in the grid. Code that operates on LineBuffer content won't see DWL_SPACERs (they're stripped on entry). The critical code is grid-level operations and rendering.

### Phase 7: Metal Rendering — 2x Glyphs via Parts System

**Use `iTermCharacterSource` at 2x size and leverage existing parts splitting.**

#### 7a. Glyph key extension

File: `sources/iTermMetalGlyphKey.h`

Add line attribute to `iTermMetalGlyphKey`:
```c
typedef struct iTermMetalGlyphKey {
    // ... existing fields ...
    iTermLineAttribute lineAttribute;  // NEW: affects glyph rasterization size
} iTermMetalGlyphKey;
```

This makes the atlas store separate entries for normal 'A' vs. DECDWL 'A' vs. DECDHL-top 'A' vs. DECDHL-bottom 'A'. Each variant is rasterized at the appropriate scale and stored as standard cell-sized parts.

#### 7b. Glyph rasterization at 2x

File: `sources/Metal/Support/iTermCharacterSource.m`

When `lineAttribute != iTermLineAttributeSingleWidth`:
- **DECDWL:** Render the glyph into a 2*cellWidth × cellHeight area. The character is drawn using Core Text at 2x horizontal scale (or equivalently, into a 2x-wide context). The parts system splits this into a left part and a right part, each cellWidth × cellHeight.
- **DECDHL top:** Render into a 2*cellWidth × 2*cellHeight area. The character is drawn at 2x in both dimensions. Extract only the **top row** of parts (left-top and right-top), each cellWidth × cellHeight. These show the top half of the doubled glyph.
- **DECDHL bottom:** Same rendering, but extract only the **bottom row** of parts (left-bottom and right-bottom).

The `newParts` method determines which parts intersect the glyph's bounding box. For DECDHL, we constrain the bounding box to the relevant vertical half, so only top or bottom parts are emitted.

Each part ends up as a standard cellWidth × cellHeight entry in the texture atlas. No atlas cell size changes needed.

#### 7c. PIU construction

File: `sources/Metal/Renderers/iTermTextRendererTransientState.mm`

When building PIUs for a double-width line:
- The character at even positions gets PIUs from the 2x-rendered glyph's parts
- Left part PIU: offset at `logicalCol * 2 * cellWidth` (the character's physical position)
- Right part PIU: offset at `logicalCol * 2 * cellWidth + cellWidth` (the DWL_SPACER's position)
- DWL_SPACER cells are not drawable → no PIU generated for them directly; the right part from the preceding character covers that position

File: `sources/Metal/Infrastructure/iTermMetalRowData.h`
- Add `iTermLineAttribute lineAttribute` property so the renderer knows each row's attribute

#### 7d. Shader changes

The vertex and fragment shaders should need **minimal changes** since:
- Each part is a standard-size quad at a standard texture atlas cell
- The offset positioning already handles multi-part glyphs correctly
- The only change might be to the texture dimensions uniform if parts reference a different atlas

For DECDHL (where we extract top/bottom halves), the clipping happens during rasterization in `iTermCharacterSource`, not in the shader. The shader sees normal cell-sized parts.

#### 7e. Background/cursor/selection rendering

- Background renderer: each character's background spans 2 cells wide (character cell + DWL_SPACER cell)
- Cursor: spans 2 cells wide on DECDWL/DECDHL lines
- Selection highlight: follows the same 2-cell-per-character pattern

### Phase 8: Legacy (Core Text) Rendering

**Use Core Text scaling directly in both renderers.**

File: `sources/iTermTextDrawingHelper.m`

Both the Metal path (via `iTermCharacterSource`) and the legacy path use Core Text internally. Apply the same scaling in both:

For DECDWL/DECDHL lines in the legacy Core Text path:
1. **DECDWL:** Save graphics state, apply `CGContextScaleCTM(ctx, 2.0, 1.0)` and adjust origin so text renders at double width
2. **DECDHL top:** Apply `CGContextScaleCTM(ctx, 2.0, 2.0)`, set clip rect to the line's physical rect (one row high), translate so the top half of the scaled text is visible
3. **DECDHL bottom:** Same as top, but translate so the bottom half is visible

Since both renderers use Core Text with the same font and the same scaling, output is visually consistent when switching between them (e.g., entering/exiting low power mode).

Background colors: draw at 2x cell width for each logical character position.

### Phase 9: Selection and Mouse Coordinate Mapping

**Use DWL_SPACER to simplify coordinate mapping.**

#### 9a. Mouse event handling

File: `sources/PTYTextView.m`

Mouse clicks on a DWL_SPACER should be treated as clicks on the preceding character. This mirrors how clicks on DWC_RIGHT are handled. Code that translates mouse position to grid coordinate already snaps DWC_RIGHT to the left half; add DWL_SPACER to this same logic.

The code path: mouse position → physical grid coordinate → check if DWL_SPACER → snap to preceding character. No division needed — the spacer character itself signals "I belong to the character before me."

#### 9b. Selection storage

File: `sources/iTermSelection.m`

Selections should store **logical coordinates** (character indices, not physical cell positions). The bidi code already separates logical from physical via `iTermBidiDisplayInfo`'s LUT/inverted-LUT pattern. Similar coordinate translation applies here.

When a selection range is specified in logical coordinates:
- Display rendering expands each logical column to 2 physical cells
- Text extraction uses logical column indices directly into the line data

This avoids a long tail of bugs from physical-coordinate storage.

#### 9c. Physical-to-Logical Coordinate Translation

On double-width lines, the grid stores characters in physical cells (with DWL_SPACERs), but applications communicate in logical columns (width/2 effective width). Every interface between the grid and the application protocol needs translation.

**Logical → Physical (application sends to terminal):**
- CUP (cursor position): `cursorToX:` in VT100ScreenMutableState.m — multiply x by 2
- Tab stops in `appendTabAtCursor:` — look up tab stop in logical coordinates, position cursor at physical 2*x
- Any escape sequence that positions the cursor by column number

**Physical → Logical (terminal reports to application):**
- Mouse reporting: `mouseHandlerCoordForPointInView:` in PTYTextView.m → `mousePress:withModifiers:at:` in VT100Output.m — divide x by 2
- DSR cursor position: `terminalRelativeCursorX` / `terminalCursorX` in VT100ScreenMutableState+TerminalDelegate.m — divide by 2
- Mouse release reporting: same path as mouse press

**Specific sites requiring changes:**

| File | Method | Direction | Fix |
|------|--------|-----------|-----|
| `VT100ScreenMutableState.m:cursorToX:` | CUP handling | Logical→Physical | Multiply x by 2 on DWL lines |
| `VT100ScreenMutableState+TerminalDelegate.m:terminalRelativeCursorX` | DSR reporting | Physical→Logical | Divide by 2 on DWL lines |
| `VT100ScreenMutableState+TerminalDelegate.m:terminalCursorX` | DSR reporting | Physical→Logical | Divide by 2 on DWL lines |
| `PTYTextView.m:mouseHandlerCoordForPointInView:` | Mouse reporting | Physical→Logical | Divide by 2 on DWL lines |
| `VT100ScreenMutableState.m:appendTabAtCursor:` | Tab handling | Logical tab stops | Compute in logical, position in physical |

Note: `coordForPoint:allowRightMarginOverflow:` (already fixed) snaps off DWL_SPACERs for mouse input to the UI. That's different from mouse REPORTING to the application — the former is about where to put the cursor internally, the latter is about what column number to send to the app.

### Phase 10: Copy/Paste and Text Extraction

**DWL_SPACER makes text extraction straightforward.**

#### 10a. Single line (DECDWL/DECDHL)

DWL_SPACER is skipped during text extraction, just like DWC_RIGHT. The text extraction code in `iTermTextExtractor.m` already skips private-use characters. Adding DWL_SPACER to the skip set means extracted text contains only the actual characters.

#### 10b. Double-height deduplication (DECDHL pairs)

When extracting a range of lines for copy:
- If a line is `iTermLineAttributeDoubleHeightBottom` and the previous line was `iTermLineAttributeDoubleHeightTop`:
  - Compare content (after stripping DWL_SPACERs)
  - If matching: skip the bottom line (already included from top)
  - If different: include both (defensive)
- Matches xterm behavior

#### 10c. Edge cases

- **Partial pair selection:** Only top or bottom selected → include that line's content (no dedup)
- **Selection spans top into bottom of same pair:** Include text once using the top line's range
- **Find / URL detection:** Operates on logical content (DWL_SPACERs skipped). URL detection, smart selection, and semantic history all work on text extraction output, so they automatically get the correct content.

### Phase 11: Per-Line Attributes in External Attributes (General Mechanism)

**Problem:** LineBuffer doesn't have a clean way to store per-line attributes. `iTermMetadata` carries the lineAttribute, but when lines are split, subranged, or concatenated inside LineBuffer, a line-level metadata field can become misaligned with its character data.

**Solution:** Add a general-purpose `lineAttribute` field to `iTermExternalAttribute`. This field is set on a range of characters and travels with them through all LineBuffer operations (subrange, concatenation, etc.). It exists **only inside LineBuffer** — it is added when lines enter and stripped when they exit.

#### 11a. Extend `iTermExternalAttribute`

File: `sources/iTermExternalAttributeIndex.h` / `.m`

Add `iTermLineAttribute lineAttribute` property to `iTermExternalAttribute`:
- Default value is `iTermLineAttributeSingleWidth` (0), so `isDefault` remains true for existing attributes without line attributes
- Update `isDefault`: return false if `lineAttribute != iTermLineAttributeSingleWidth`
- Update `dictionaryValue` / `initWithDictionary:` — serialize as a new key (e.g., `iTermExternalAttributeKeyLineAttribute`)
- Update `data` / `fromData:` — add to TLV encoding (append after existing fields; old data without it decodes as singleWidth)
- Update `isEqualToExternalAttribute:` — compare lineAttribute
- Update `copyWithZone:` — copy lineAttribute

This is a general mechanism — any future per-line attribute can be added to `iTermExternalAttribute` the same way.

#### 11b. Grid → LineBuffer (scrolling into history)

When a line with `lineAttribute != singleWidth` enters LineBuffer:
1. Strip DWL_SPACERs from the `screen_char_t` data, compacting to logical content
2. Adjust existing external attribute indices to match compacted positions
3. Set `lineAttribute` on the external attribute of the **first character only**
4. Store the compacted line + annotated external attributes in LineBuffer

Setting it on just the first character means that no matter how the line rewraps into a narrower window, the display line containing that first character gets the double-width attribute. Subsequent wrapped portions of the same raw line are normal-width display lines.

#### 11c. LineBuffer → Grid/Display (reading from history)

When reading a wrapped display line from LineBuffer:
1. Check if the **first character** of the display line has `lineAttribute != singleWidth` in its external attribute
2. If so:
   - Re-insert DWL_SPACERs into the `screen_char_t` data for that display line
   - Expand external attribute indices back to physical positions
   - Strip the `lineAttribute` from the external attribute (it's been consumed)
3. The `lineAttribute` in `iTermMetadata` is also set for the renderer

The external attribute on the first character acts as a marker: "the display line starting at this character is double-width." If rewrapping splits the raw line, only the display line containing that first character gets the double-width treatment.

Files: `sources/iTermExternalAttributeIndex.h` / `.m`, `sources/LineBlock.h` / `.mm`, `sources/LineBuffer.m`, `sources/ScreenCharArray.m`

### Phase 12: Resize / Rewrapping

Since the LineBuffer stores logical content without DWL_SPACERs, rewrapping is straightforward:

- `numberOfWrappedLinesForWidth:` checks the lineAttribute (from external attributes or metadata) and uses `iTermEffectiveLineWidth(newWidth, attr)` to determine how many display lines are needed
- The raw line content is just the logical characters — wrapping at `newWidth/2` for DECDWL lines works the same as wrapping normal lines at `newWidth`
- When reading back for display, the external attribute triggers DWL_SPACER re-insertion

**DECSWL on resize:** Line attributes are preserved across resize. The terminal does not auto-reset attributes. This matches xterm.

File: `sources/LineBuffer.m` (wrapping calculation methods)

---

## Key Design Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Line attribute storage | `iTermMetadata` struct | Flows through entire system; default 0 = no behavior change |
| DECDHL top/bottom distinction | `p[0] = 3` or `4` (matching ESC # digit) | Direct mapping from escape sequence to token parameter |
| Physical cell representation | New DWL_SPACER character | Follows TAB_FILLER/DWC_RIGHT pattern; find update sites by searching those references; handles Ｌ on DECDWL line (4 cells: char + DWL + DWC_RIGHT + DWL) |
| Why not DWC_RIGHT for spacer | Need to distinguish DWC_RIGHT from line-doubling spacer | A fullwidth char on a DECDWL line needs both DWC_RIGHT and DWL_SPACER |
| Glyph rendering | 2x via `iTermCharacterSource` with existing parts system | Sharp rendering; parts split 2x glyph into standard cell-sized atlas entries |
| Both renderers | Same `iTermCharacterSource` bitmaps for Metal and Core Text | Pixel-identical output; no glitch on renderer switch (e.g., low power mode) |
| Selection coordinates | Logical (character index, not physical cell) | Avoids long tail of bugs; consistent with bidi pattern |
| Overflow at end of DECDWL line | Wrap at effective width (width/2) | Matches xterm; Terminal.app's swallowing behavior appears to be a bug |
| Content transform on attr change | Expand/compact grid cells with DWL_SPACERs | Maintains consistency between data model and display |
| DWL_SPACERs in scrollback | Strip on entry, re-insert on display | Double-widthedness is a display-line property; storing spacers would complicate rewrapping since they'd affect line wrapping calculations for all subsequent widths |
| Line attributes in LineBuffer | External attribute on character range | LineBuffer lacks per-line metadata; external attributes travel with characters through subrange/concat/rewrap, making them robust; general mechanism for future per-line attrs |
| iTermMetadataAppend lineAttribute | Preserve lhs (start of logical line) | The line attribute was set on the original row; continuations are typically normal-width |

---

## Verification Plan

1. **Parser test:** Send `printf '\033#6Hello\n'` and verify the token is generated with correct type
2. **Visual test - DECDWL:** `printf '\033#6Hello World\n'` should display "Hello World" at double width
3. **Visual test - DECDHL:**
   ```
   printf '\033#3BANNER\n\033#4BANNER\n'
   ```
   Should display "BANNER" in double-height text spanning two rows
4. **vttest:** Run vttest "Test of double-sized characters" (menu 1 → option 5)
5. **DWC on DECDWL:** `printf '\033#6Ｌ\n'` — fullwidth character should span 4 physical cells
6. **Cursor positioning:** Verify cursor moves in 2-cell steps on DECDWL lines
7. **Wrapping:** Fill a DECDWL line past effective width — verify wrapping at width/2
8. **DECSWL reset:** `printf '\033#6Double\033#5Normal\n'` — content should compact to normal width
9. **Scrolling:** Scroll double-height text off screen → verify renders correctly in scrollback
10. **Selection - DECDWL:** Click/drag on double-width line → correct highlight width and copied text
11. **Selection - DECDHL pair:** Select across both halves → text copied only once
12. **Selection - partial pair:** Select only top or bottom → correct text extracted
13. **Resize:** Resize terminal with double-width text → reflow at effective width
14. **Legacy renderer:** Disable Metal → repeat tests 2–12 → output must be identical
15. **Renderer switch:** Toggle Metal on/off while double-width text is visible → no visual glitch
16. **Mouse reporting:** Enable mouse mode → click on DECDWL line → reports logical column
17. **Search/find:** Search for text that spans a DECDWL line → found correctly
18. **Smart selection:** Double-click a word on a DECDWL line → correct word selected
19. **Semantic history:** Cmd-click a URL on a DECDWL line → correct URL opened
