//
//  iTermMetalPerFrameStateConfiguration.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/19/18.
//

#import <Cocoa/Cocoa.h>
#import <simd/simd.h>
#import "ITAddressBookMgr.h"
#import "iTermTextRendererCommon.h"
#import "iTermLineStyleMarkRenderer.h"
#import "iTermRowRenderInputs.h"
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermButtonPillInfo;
@class iTermColorMap;
@class iTermFontTable;
@protocol iTermMetalPerFrameStateDelegate;
@class iTermRectArray;
@class iTermTerminalButton;
@class iTermTextDrawingHelper;
@class NSColor;
@class PTYFontInfo;
@class PTYTextView;

@interface iTermMetalPerFrameStateConfiguration : NSObject {
@public
    // Frame-constant inputs consumed by the Metal row build. See
    // iTermRowRenderInputs.h. Populated in loadSettingsWithDrawingHelper:.
    iTermRowRenderInputs _renderInputs;

    // Fingerprint of _renderInputs, computed at the end of loadSettings. Two
    // frames with equal values share a value; used to key a per-row cache.
    uint64_t _configGeneration;

    // Geometry
    CGSize _cellSize;
    CGSize _cellSizeWithoutSpacing;
    CGFloat _scale;

    // Colors
    iTermColorMap *_colorMap;
    vector_float4 _fullScreenFlashColor;
    NSColor *_processedDefaultBackgroundColor;  // dimmed, etc.
    BOOL _marginColorEnabled;
    vector_float4 _processedMarginColor;
    NSColor *_processedDefaultTextColor;
    NSColor *_blockHoverColor;
    NSColor *_defaultTextColor;
    vector_float4 _selectionColor;
    iTermLineStyleMarkColors _lineStyleMarkColors;
    NSColor *_cursorGuideColor;
    NSColorSpace *_colorSpace;
    BOOL _forceRegularBottomMargin;

    // Text
    iTermFontTable *_fontTable;
    BOOL _asciiAntialias;
    BOOL _nonasciiAntialias;
    iTermMetalUnderlineDescriptor _asciiUnderlineDescriptor;
    iTermMetalUnderlineDescriptor _nonAsciiUnderlineDescriptor;
    iTermMetalUnderlineDescriptor _strikethroughUnderlineDescriptor;
    CGFloat _baselineOffset;
    BOOL _useBoldFont;
    BOOL _useItalicFont;

    // Focus
    BOOL _isInKeyWindow;
    BOOL _textViewIsActiveSession;
    BOOL _textViewIsFirstResponder;

    // Cursor
    BOOL _shouldDrawFilledInCursor;
    BOOL _cursorGuideEnabled;

    // Size
    VT100GridSize _gridSize;
    NSEdgeInsets _edgeInsets;

    // Background image
    CGFloat _backgroundImageBlend;
    CGFloat _backgroundColorAlpha;  // See iTermAlphaBlendingHelper.h
    iTermBackgroundImageMode _backgroundImageMode;

    // Other
    BOOL _showBroadcastStripes;
    BOOL _timestampsEnabled;
    BOOL _blinkingItemsVisible;
    PTYFontInfo *_timestampFontInfo;
    NSTimeInterval _timestampBaseline;
    NSArray<iTermTerminalButton *> *_terminalButtons;
    long long _totalScrollbackOverflow;
    iTermRectArray *_buttonsBackgroundRects;
    NSArray<iTermButtonPillInfo *> *_buttonPillInfos;
    BOOL _softAlternateScreenMode;

    // Offscreen command line
    NSColor *_offscreenCommandLineBackgroundColor;
    NSColor *_offscreenCommandLineOutlineColor;

    // Selected command (absolute lines)
    NSRange _selectedCommandRegion;

    vector_float4 _selectedCommandOutlineColors[2];
    vector_float4 _shadeColor;
};

- (void)loadSettingsWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper
                             textView:(PTYTextView *)textView
                                 glue:(id<iTermMetalPerFrameStateDelegate>)glue;

@end

NS_ASSUME_NONNULL_END
