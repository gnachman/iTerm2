//
//  iTermMetalPerFrameState.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/19/18.
//

#import <Foundation/Foundation.h>
#import "iTermMetalDriver.h"
#import "iTermMetalGlyphKey.h"
#import "iTermTextRendererCommon.h"

NS_ASSUME_NONNULL_BEGIN

@class PTYTextView;
@class VT100Screen;
@class iTermAttributedStringBuilder;
@class iTermImageWrapper;

@protocol iTermMetalPerFrameStateDelegate <NSObject>
// Screen-relative cursor location on last frame
@property (nonatomic) VT100GridCoord oldCursorScreenCoord;
// Used to remember the last time the cursor moved to avoid drawing a blinked-out
// cursor while it's moving.
@property (nonatomic) NSTimeInterval lastTimeCursorMoved;
@property (nonatomic, readonly) iTermImageWrapper *backgroundImage;
@property (nonatomic, readonly) iTermBackgroundImageMode backroundImageMode;
@property (nonatomic, readonly) CGFloat backgroundImageBlend;
@end

@interface iTermMetalPerFrameState : NSObject<
    iTermMetalDriverDataSourcePerFrameState,
    iTermSmartCursorColorDelegate>

@property (nonatomic, readonly) BOOL isAnimating;
@property (nonatomic, readonly) CGSize cellSize;
@property (nonatomic, readonly) CGSize cellSizeWithoutSpacing;
@property (nonatomic, readonly) CGFloat scale;

- (instancetype)initWithTextView:(PTYTextView *)textView
                          screen:(VT100Screen *)screen
                            glue:(id<iTermMetalPerFrameStateDelegate>)glue
                         context:(CGContextRef)context
              doubleWidthContext:(CGContextRef)doubleWidthContext
         attributedStringBuilder:(iTermAttributedStringBuilder *)attributedStringBuilder NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

// Builds background-color RLEs for a screen line. Exposed for testing.
int iTermGetMetalBackgroundColors(iTermMetalPerFrameState *self,
                                  const screen_char_t *line,
                                  iTermMetalBackgroundColorRLE *backgroundRLE,
                                  iTermMetalGlyphAttributes *attributes,
                                  vector_float4 *unprocessedBackgroundColors,
                                  int width,
                                  NSIndexSet *_Nullable selectedIndexes,
                                  NSData *_Nullable findMatches,
                                  id<iTermColorMapReading> colorMap,
                                  iTermExternalAttributeIndex *_Nullable eaIndex,
                                  iTermBidiDisplayInfo *_Nullable bidiInfo,
                                  iTermLineAttribute lineAttribute);

NS_ASSUME_NONNULL_END
