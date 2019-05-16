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
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermColorMap;
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
    vector_float4 _unfocusedSelectionColor;
    CGFloat _transparencyAlpha;
    BOOL _transparencyAffectsOnlyDefaultBackgroundColor;
    NSColor *_cursorGuideColor;

    // Text
    PTYFontInfo *_asciiFont;
    PTYFontInfo *_nonAsciiFont;
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
    BOOL _useBoldColor;
    BOOL _useNativePowerlineGlyphs;

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
    CGFloat _backgroundImageBlending;
    iTermBackgroundImageMode _backgroundImageMode;

    // Other
    BOOL _showBroadcastStripes;
    BOOL _timestampsEnabled;
    BOOL _blinkingItemsVisible;
};

- (void)loadSettingsWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper
                             textView:(PTYTextView *)textView;

@end

NS_ASSUME_NONNULL_END
