# WKWebView Coordinate Conversion Debugging Notes

## Problem
The `extendSelection(toPointInWindow:)` method was extending selection to the wrong location due to incorrect coordinate conversion between AppKit window coordinates and JavaScript viewport coordinates.

## Test Setup
- Created `selection-test.html` with comprehensive coordinate logging
- Added debug logging to both Swift and JavaScript sides
- Used grid background and visual click markers for reference

## Initial Implementation (INCORRECT)
```swift
let pointInView = self.convert(point, from: nil)
let webY = self.bounds.height - pointInView.y  // Y-axis flip
let jsX = pointInView.x / self.pageZoom        // Manual zoom scaling
let jsY = webY / self.pageZoom                 // Manual zoom scaling
```

## Observed Issues
1. **Coordinate Mismatch**: 
   - CMD+right-click at window `(1444.53, 964.57)` → view `(1250.53, 575.43)`
   - JavaScript received `(1605.19, 1211.18)` (WRONG)
   - Regular click at screen `(1444, 644)` → JavaScript `(1604, 738)` (expected)

2. **Y-coordinate Conversion Problem**: 
   - Swift calculated Y=1211 but should be ~575-738 range
   - Indicates Y-axis flip was incorrect

3. **Page Zoom Confusion**:
   - Swift: `pageZoom = 0.779`
   - JavaScript: `devicePixelRatio = 2`
   - Manual division by pageZoom was causing coordinate errors

## Root Cause Analysis
- WKWebView's coordinate system already matches JavaScript (top-left origin)
- `convert(point, from: nil)` should give coordinates that directly correspond to JavaScript's `clientX/Y`
- No Y-axis flipping needed since both systems use top-left origin in content area
- No manual pageZoom scaling needed - conversion method handles view transformations

## Fixed Implementation
```swift
let pointInView = self.convert(point, from: nil)
let jsX = pointInView.x  // Direct 1:1 mapping
let jsY = pointInView.y  // Direct 1:1 mapping
```

## Test Results
- **Before Fix**: CMD+click `(1444, 964)` → JS `(1605, 1211)` → Wrong selection location
- **After Fix**: [TO BE TESTED]

## Applied To
- `extendSelection(toPointInWindow:)`
- `openLink(atPointInWindow:inNewTab:)`
- `text(atPointInWindow:radius:)`
- `performSmartSelection(atPointInWindow:rules:)`
- `urls(atPointInWindow:)`

## Key Learnings
1. WKWebView coordinate conversion is simpler than expected
2. `convert(point, from: nil)` handles all necessary transformations
3. Manual coordinate system conversions can introduce errors
4. Comprehensive logging on both sides is essential for debugging coordinate issues

## Next Steps
- Test the fixed implementation
- Verify coordinates match between Swift and JavaScript logs
- Remove debug logging once confirmed working