#import "VT100GridTypes.h"

#import "iTermASCIITexture.h"
#import "iTermCursor.h"
#import "iTermImageRenderer.h"
#import "iTermIndicatorRenderer.h"
#import "iTermMarkRenderer.h"
#import "iTermMetalDebugInfo.h"
#import "iTermMetalGlyphKey.h"
#import "iTermTextRenderer.h"
#import "iTermTextRendererTransientState.h"

@import MetalKit;

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalCursorInfo : NSObject
@property (nonatomic) BOOL cursorVisible;
@property (nonatomic) VT100GridCoord coord;
@property (nonatomic) ITermCursorType type;
@property (nonatomic, strong) NSColor *cursorColor;

// Block cursors care about drawing the character overtop the cursor in a
// different color than the character would normally be. If this is set, the
// text color will be changed to that of the `textColor` property.
@property (nonatomic) BOOL shouldDrawText;
@property (nonatomic) vector_float4 textColor;

// This is a "frame" cursor, as seen when the view does not have focus.
@property (nonatomic) BOOL frameOnly;
@property (nonatomic) BOOL copyMode;
@property (nonatomic) BOOL copyModeCursorSelecting;
@property (nonatomic) VT100GridCoord copyModeCursorCoord;
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

// Initialize sketchPtr to 0. The number of set bits estimates the unique number of color combinations.
- (void)metalGetGlyphKeys:(iTermMetalGlyphKey *)glyphKeys
               attributes:(iTermMetalGlyphAttributes *)attributes
                imageRuns:(NSMutableArray<iTermMetalImageRun *> *)imageRuns
               background:(iTermMetalBackgroundColorRLE *)backgrounds
                 rleCount:(int *)rleCount
                markStyle:(out iTermMarkStyle *)markStylePtr
                      row:(int)row
                    width:(int)width
           drawableGlyphs:(int *)drawableGlyphsPtr
                     date:(out NSDate * _Nonnull * _Nonnull)date
                     sketch:(out NSUInteger *)sketchPtr;

- (nullable iTermMetalCursorInfo *)metalDriverCursorInfo;

- (NSDictionary<NSNumber *, iTermCharacterBitmap *> *)metalImagesForGlyphKey:(iTermMetalGlyphKey *)glyphKey
                                                                        size:(CGSize)size
                                                                       scale:(CGFloat)scale
                                                                       emoji:(BOOL *)emoji;

// Returns the background image or nil. If there's a background image, fill in blending and tiled.
- (NSImage *)metalBackgroundImageGetTiled:(nullable BOOL *)tiled;

// An object that compares as equal if ascii characters produced by metalImagesForGlyph would
// produce the same bitmap.
- (id)metalASCIICreationIdentifier;

// Returns metrics and optional color for underlines.
- (void)metalGetUnderlineDescriptorsForASCII:(out iTermMetalUnderlineDescriptor *)ascii
                                    nonASCII:(out iTermMetalUnderlineDescriptor *)nonAscii;

- (void)enumerateIndicatorsInFrame:(NSRect)frame block:(void (^)(iTermIndicatorDescriptor *))block;

- (void)metalEnumerateHighlightedRows:(void (^)(vector_float3 color, NSTimeInterval age, int row))block;

- (void)setDebugString:(NSString *)debugString;

- (iTermData *)lineForRow:(int)y;

@end

NS_CLASS_AVAILABLE(10_11, NA)
@protocol iTermMetalDriverDataSource<NSObject>

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

- (nullable instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView;
- (void)setCellSize:(CGSize)cellSize
cellSizeWithoutSpacing:(CGSize)cellSizeWithoutSpacing
           gridSize:(VT100GridSize)gridSize
              scale:(CGFloat)scale;

// Draw and return after the GPU's completion callback is run.
// enableSetNeedsDisplay should be NO.
- (void)drawSynchronouslyInView:(MTKView *)view;

// Draw and return immediately, calling completion block after GPU's completion
// block is called.
// enableSetNeedsDisplay should be NO.
- (void)drawAsynchronouslyInView:(MTKView *)view completion:(void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END

