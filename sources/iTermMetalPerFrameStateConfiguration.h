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
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermColorMap;
@class iTermFontTable;
@protocol iTermMetalPerFrameStateDelegate;
@class iTermTerminalButton;
@class iTermTextDrawingHelper;
@class NSColor;
@class PTYFontInfo;
@class PTYTextView;

@interface iTermMetalPerFrameStateConfiguration : NSObject {
@public
    // Geometry
    CGSize _cellSize;
    CGSize _cellSizeWithoutSpacing;
    CGFloat _scale;

    // Colors
    iTermColorMap *_colorMap;
    vector_float4 _fullScreenFlashColor;
    NSColor *_processedDefaultBackgroundColor;  // dimmed, etc.
    NSColor *_processedDefaultTextColor;
    vector_float4 _selectionColor;
    iTermLineStyleMarkColors _lineStyleMarkColors;
    vector_float4 _unfocusedSelectionColor;
    CGFloat _transparencyAlpha;
    BOOL _transparencyAffectsOnlyDefaultBackgroundColor;
    NSColor *_cursorGuideColor;
    NSColorSpace *_colorSpace;

    // Text
    iTermFontTable *_fontTable;
    BOOL _useNonAsciiFont;
    BOOL _asciiAntialias;
    BOOL _nonasciiAntialias;
    iTermMetalUnderlineDescriptor _asciiUnderlineDescriptor;
    iTermMetalUnderlineDescriptor _nonAsciiUnderlineDescriptor;
    iTermMetalUnderlineDescriptor _strikethroughUnderlineDescriptor;
    CGFloat _baselineOffset;
    iTermThinStrokesSetting _thinStrokes;
    BOOL _useBoldFont;
    BOOL _useItalicFont;
    BOOL _reverseVideo;
    BOOL _useCustomBoldColor;
    BOOL _brightenBold;
    BOOL _useNativePowerlineGlyphs;
    BOOL _useSelectedTextColor;

    // Focus
    BOOL _isFrontTextView;
    BOOL _isInKeyWindow;
    BOOL _textViewIsActiveSession;

    // Screen
    BOOL _isRetina;

    // Cursor
    BOOL _shouldDrawFilledInCursor;
    BOOL _cursorGuideEnabled;

    // Size
    VT100GridSize _gridSize;
    BOOL _blinkAllowed;
    NSEdgeInsets _edgeInsets;

    // Background image
    CGFloat _backgroundImageBlend;
    CGFloat _backgroundColorAlpha;  // See iTermAlphaBlendingHelper.h
    iTermBackgroundImageMode _backgroundImageMode;

    // Other
    BOOL _showBroadcastStripes;
    BOOL _timestampsEnabled;
    BOOL _blinkingItemsVisible;
    NSFont *_timestampFont;
    NSArray<iTermTerminalButton *> *_terminalButtons NS_AVAILABLE_MAC(11);
    
    // Offscreen command line
    NSColor *_offscreenCommandLineBackgroundColor;
    NSColor *_offscreenCommandLineOutlineColor;
};

- (void)loadSettingsWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper
                             textView:(PTYTextView *)textView
                                 glue:(id<iTermMetalPerFrameStateDelegate>)glue;

@end

NS_ASSUME_NONNULL_END
