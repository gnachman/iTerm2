//
//  iTermMetalPerFrameState.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/19/18.
//

#import <Foundation/Foundation.h>
#import "iTermMetalDriver.h"

NS_ASSUME_NONNULL_BEGIN

@class PTYTextView;
@class VT100Screen;
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
                         context:(CGContextRef)context NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
