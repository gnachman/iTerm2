#import "VT100GridTypes.h"

#import "iTermASCIITexture.h"
#import "iTermCursor.h"
#import "iTermImageRenderer.h"
#import "iTermIndicatorRenderer.h"
#import "iTermLineStyleMarkRenderer.h"
#import "iTermMarkRenderer.h"
#import "iTermMetalDebugInfo.h"
#import "iTermMetalGlyphKey.h"
#import "iTermTextRenderer.h"
#import "iTermTextRendererTransientState.h"

@import MetalKit;
@class iTermTerminalButton;

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalCursorInfo : NSObject
@property (nonatomic) BOOL cursorVisible;
@property (nonatomic) VT100GridCoord coord;
@property (nonatomic) ITermCursorType type;
@property (nonatomic, strong) NSColor *cursorColor;
@property (nonatomic) BOOL doubleWidth;
@property (nonatomic) BOOL cursorShadow;

// Block cursors care about drawing the character overtop the cursor in a
// different color than the character would normally be. If this is set, the
// text color will be changed to that of the `textColor` property.
@property (nonatomic) BOOL shouldDrawText;
@property (nonatomic) vector_float4 textColor;

// This is a "frame" cursor, as seen when the view does not have focus.
@property (nonatomic) BOOL frameOnly;
@property (nonatomic) BOOL copyMode;
@property (nonatomic) BOOL password;
@property (nonatomic) BOOL copyModeCursorSelecting;
@property (nonatomic) VT100GridCoord copyModeCursorCoord;
@property (nonatomic) vector_float4 backgroundColor;
@end

@interface iTermMetalIMEInfo : NSObject

@property (nonatomic) VT100GridCoord cursorCoord;
@property (nonatomic) VT100GridCoordRange markedRange;

- (void)setRangeStart:(VT100GridCoord)start;
- (void)setRangeEnd:(VT100GridCoord)end;

@end

NS_CLASS_AVAILABLE(10_11, NA)
@protocol iTermMetalDriverDataSourcePerFrameState<NSObject>

@property (nonatomic, readonly) VT100GridSize gridSize;
@property (nonatomic, readonly) CGSize cellSize;
@property (nonatomic, readonly) CGSize cellSizeWithoutSpacing;
@property (nonatomic, readonly) vector_float4 defaultBackgroundColor;
@property (nonatomic, readonly) vector_float4 processedDefaultBackgroundColor;
@property (nonatomic, readonly) vector_float4 processedDefaultTextColor;
@property (nonatomic, readonly) iTermLineStyleMarkColors lineStyleMarkColors;
@property (nonatomic, readonly) NSImage *badgeImage;
@property (nonatomic, readonly) CGRect badgeSourceRect;
@property (nonatomic, readonly) CGRect badgeDestinationRect;
@property (nonatomic, nullable, readonly) iTermMetalIMEInfo *imeInfo;
@property (nonatomic, readonly) BOOL showBroadcastStripes;
@property (nonatomic, readonly) NSColor *cursorGuideColor;
@property (nonatomic, readonly) BOOL cursorGuideEnabled;
@property (nonatomic, readonly) vector_float4 fullScreenFlashColor;
@property (nonatomic, readonly) BOOL timestampsEnabled;
@property (nonatomic, readonly) NSColor *timestampsBackgroundColor;
@property (nonatomic, readonly) NSColor *timestampsTextColor;
@property (nonatomic, readonly) long long firstVisibleAbsoluteLineNumber;
@property (nonatomic, readonly) NSEdgeInsets edgeInsets;
@property (nonatomic, readonly) BOOL hasBackgroundImage;
@property (nonatomic, readonly) CGFloat transparencyAlpha;
@property (nonatomic, readonly) CGFloat blend;
@property (nonatomic, readonly) NSEdgeInsets extraMargins;
@property (nonatomic, readonly) BOOL thinStrokesForTimestamps;
@property (nonatomic, readonly) BOOL asciiAntiAliased;
@property (nonatomic, readonly) NSFont *timestampFont;
@property (nonatomic, readonly) NSColorSpace *colorSpace;
@property (nonatomic, readonly) BOOL haveOffscreenCommandLine;
@property (nonatomic, readonly) vector_float4 offscreenCommandLineOutlineColor;
@property (nonatomic, readonly) vector_float4 offscreenCommandLineBackgroundColor;
@property (nonatomic, readonly) VT100GridRange linesToSuppressDrawing;
@property (nonatomic, readonly) NSArray<iTermTerminalButton *> *terminalButtons NS_AVAILABLE_MAC(11);

// Initialize sketchPtr to 0. The number of set bits estimates the unique number of color combinations.
- (void)metalGetGlyphKeys:(iTermMetalGlyphKey *)glyphKeys
               attributes:(iTermMetalGlyphAttributes *)attributes
                imageRuns:(NSMutableArray<iTermMetalImageRun *> *)imageRuns
               background:(iTermMetalBackgroundColorRLE *)backgrounds
                 rleCount:(int *)rleCount
                markStyle:(out iTermMarkStyle *)markStylePtr
            lineStyleMark:(out BOOL *)lineStyleMarkPtr
                      row:(int)row
                    width:(int)width
           drawableGlyphs:(int *)drawableGlyphsPtr
                     date:(out NSDate * _Nonnull * _Nonnull)date
           belongsToBlock:(out BOOL * _Nonnull)belongsToBlock;

- (iTermCharacterSourceDescriptor *)characterSourceDescriptorForASCIIWithGlyphSize:(CGSize)glyphSize
                                                                       asciiOffset:(CGSize)asciiOffset;

- (nullable iTermMetalCursorInfo *)metalDriverCursorInfo;

- (nullable NSDictionary<NSNumber *, iTermCharacterBitmap *> *)metalImagesForGlyphKey:(iTermMetalGlyphKey *)glyphKey
                                                                          asciiOffset:(CGSize)asciiOffset
                                                                                 size:(CGSize)size
                                                                                scale:(CGFloat)scale
                                                                                emoji:(BOOL *)emoji;

// Returns the background image or nil. If there's a background image, fill in mode.
- (iTermImageWrapper *)metalBackgroundImageGetMode:(nullable iTermBackgroundImageMode *)mode;

// An object that compares as equal if ascii characters produced by metalImagesForGlyph would
// produce the same bitmap.
- (id)metalASCIICreationIdentifierWithOffset:(CGSize)asciiOffset;

// Returns metrics and optional color for underlines.
- (void)metalGetUnderlineDescriptorsForASCII:(out iTermMetalUnderlineDescriptor *)ascii
                                    nonASCII:(out iTermMetalUnderlineDescriptor *)nonAscii
                               strikethrough:(out iTermMetalUnderlineDescriptor *)strikethrough;

- (void)enumerateIndicatorsInFrame:(NSRect)frame block:(void (^)(iTermIndicatorDescriptor *))block;

- (void)metalEnumerateHighlightedRows:(void (^)(vector_float3 color, NSTimeInterval age, int row))block;

- (void)setDebugString:(NSString *)debugString;

- (ScreenCharArray *)screenCharArrayForRow:(int)y;

- (CGRect)relativeFrame;
- (CGRect)containerRect;

@end

NS_CLASS_AVAILABLE(10_11, NA)
@protocol iTermMetalDriverDataSource<NSObject>

- (BOOL)metalDriverShouldDrawFrame;
- (nullable id<iTermMetalDriverDataSourcePerFrameState>)metalDriverWillBeginDrawingFrame;

- (void)metalDriverDidDrawFrame:(id<iTermMetalDriverDataSourcePerFrameState>)perFrameState;

- (void)metalDidFindImages:(NSSet<NSString *> *)foundImages
             missingImages:(NSSet<NSString *> *)missingImages
             animatedLines:(NSSet<NSNumber *> *)animatedLines;  // absolute line numbers

- (void)metalDriverDidProduceDebugInfo:(NSData *)archive;

@end

// Our platform independent render class
NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalDriver : NSObject<MTKViewDelegate>

@property (nullable, nonatomic, weak) id<iTermMetalDriverDataSource> dataSource;
@property (nonatomic, readonly) NSString *identifier;
@property (atomic) BOOL captureDebugInfoForNextFrame;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithDevice:(nonnull id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;

- (void)setCellSize:(CGSize)cellSize
cellSizeWithoutSpacing:(CGSize)cellSizeWithoutSpacing
          glyphSize:(CGSize)glyphSize
           gridSize:(VT100GridSize)gridSize
        asciiOffset:(CGSize)asciiOffset
              scale:(CGFloat)scale
            context:(CGContextRef)context
legacyScrollbarWidth:(unsigned int)legacyScrollbarWidth;

// Draw and return immediately, calling completion block after GPU's completion
// block is called.
// enableSetNeedsDisplay should be NO.
// The arg to completion is YES on success and NO if the draw was aborted for lack of resources.
- (void)drawAsynchronouslyInView:(MTKView *)view completion:(void (^)(BOOL))completion;
- (void)expireNonASCIIGlyphs;

@end

NS_ASSUME_NONNULL_END

